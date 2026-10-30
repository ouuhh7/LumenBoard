#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CommonCrypto/CommonDigest.h>
#import <sys/stat.h>
#import <unistd.h>
#import <pwd.h>
#import <errno.h>
#import "../Shared/LBPaths.h"
#import "LBPosterBoardInstaller.h"

static NSLock *LBRequestLock;

static BOOL LBValidUUID(NSString *value) {
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:value ?: @""];
    return uuid != nil && [uuid.UUIDString.lowercaseString isEqualToString:value.lowercaseString];
}

static BOOL LBRegularFile(NSString *path, unsigned long long maximumBytes) {
    struct stat st;
    return lstat(path.fileSystemRepresentation, &st) == 0 && S_ISREG(st.st_mode) &&
        !S_ISLNK(st.st_mode) && st.st_size > 0 &&
        (unsigned long long)st.st_size <= maximumBytes;
}

static NSString *LBSHA256(NSString *path) {
    NSInputStream *stream = [NSInputStream inputStreamWithFileAtPath:path];
    if (!stream) return nil;
    [stream open];
    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    uint8_t buffer[64 * 1024];
    NSInteger count = 0;
    while ((count = [stream read:buffer maxLength:sizeof(buffer)]) > 0) {
        CC_SHA256_Update(&context, buffer, (CC_LONG)count);
    }
    NSError *readError = stream.streamError;
    [stream close];
    if (count < 0 || readError) return nil;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &context);
    NSMutableString *result = [NSMutableString stringWithCapacity:64];
    for (NSUInteger index = 0; index < sizeof(digest); index++) [result appendFormat:@"%02x", digest[index]];
    return result;
}

static BOOL LBWriteCompletion(NSString *requestID, NSDictionary *payload) {
    if (!LBValidUUID(requestID)) return NO;
    NSString *destination = [LBCompletedPath() stringByAppendingPathComponent:[requestID stringByAppendingPathExtension:@"plist"]];
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:payload format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    if (data.length == 0) return NO;
    NSString *temporary = [destination stringByAppendingFormat:@".%@.tmp", NSUUID.UUID.UUIDString.lowercaseString];
    if (![data writeToFile:temporary options:NSDataWritingAtomic error:nil]) return NO;
    chmod(temporary.fileSystemRepresentation, 0600);
    if (rename(temporary.fileSystemRepresentation, destination.fileSystemRepresentation) != 0) {
        unlink(temporary.fileSystemRepresentation);
        return NO;
    }
    struct passwd *mobile = getpwnam("mobile");
    if (mobile && chown(destination.fileSystemRepresentation, mobile->pw_uid, mobile->pw_gid) != 0) return NO;
    chmod(destination.fileSystemRepresentation, 0600);
    return YES;
}

static NSDictionary *LBLoadManagedTendiesItem(NSString *identifier, NSError **error) {
    if (!LBValidUUID(identifier)) {
        if (error) *error = [NSError errorWithDomain:@"com.iuyghi.LumenBoard.Daemon" code:100 userInfo:@{NSLocalizedDescriptionKey:@"Invalid managed item identifier."}];
        return nil;
    }
    NSString *itemRoot = [LBLibraryPath() stringByAppendingPathComponent:identifier];
    struct stat rootStat;
    if (lstat(itemRoot.fileSystemRepresentation, &rootStat) != 0 || !S_ISDIR(rootStat.st_mode) || S_ISLNK(rootStat.st_mode)) {
        if (error) *error = [NSError errorWithDomain:@"com.iuyghi.LumenBoard.Daemon" code:101 userInfo:@{NSLocalizedDescriptionKey:@"Managed library item directory is missing or unsafe."}];
        return nil;
    }
    NSString *manifestPath = [itemRoot stringByAppendingPathComponent:@"manifest.plist"];
    if (!LBRegularFile(manifestPath, 1024 * 1024)) {
        if (error) *error = [NSError errorWithDomain:@"com.iuyghi.LumenBoard.Daemon" code:102 userInfo:@{NSLocalizedDescriptionKey:@"Managed item manifest is missing or unsafe."}];
        return nil;
    }
    NSDictionary *manifest = [NSDictionary dictionaryWithContentsOfFile:manifestPath];
    if (![manifest isKindOfClass:NSDictionary.class] ||
        ![manifest[@"identifier"] isKindOfClass:NSString.class] ||
        [manifest[@"identifier"] caseInsensitiveCompare:identifier] != NSOrderedSame ||
        ![manifest[@"type"] isEqual:@"tendies-unvalidated"]) {
        if (error) *error = [NSError errorWithDomain:@"com.iuyghi.LumenBoard.Daemon" code:103 userInfo:@{NSLocalizedDescriptionKey:@"Managed item manifest does not identify a supported .tendies source."}];
        return nil;
    }
    NSString *filename = [manifest[@"sourceFilename"] isKindOfClass:NSString.class] ? manifest[@"sourceFilename"] : nil;
    if (![filename isEqualToString:@"source.tendies"]) {
        if (error) *error = [NSError errorWithDomain:@"com.iuyghi.LumenBoard.Daemon" code:104 userInfo:@{NSLocalizedDescriptionKey:@"Managed .tendies filename is not the expected private source file."}];
        return nil;
    }
    NSString *sourcePath = [itemRoot stringByAppendingPathComponent:filename];
    if (!LBRegularFile(sourcePath, 300ULL * 1024ULL * 1024ULL)) {
        if (error) *error = [NSError errorWithDomain:@"com.iuyghi.LumenBoard.Daemon" code:105 userInfo:@{NSLocalizedDescriptionKey:@"Managed .tendies source is missing, unsafe, or exceeds 300 MiB."}];
        return nil;
    }
    NSString *expectedHash = [manifest[@"sha256"] isKindOfClass:NSString.class] ? manifest[@"sha256"].lowercaseString : nil;
    NSString *actualHash = LBSHA256(sourcePath);
    if (!expectedHash.length || !actualHash.length || ![expectedHash isEqualToString:actualHash]) {
        if (error) *error = [NSError errorWithDomain:@"com.iuyghi.LumenBoard.Daemon" code:106 userInfo:@{NSLocalizedDescriptionKey:@"The source archive SHA-256 does not match the stored import manifest."}];
        return nil;
    }
    return @{@"identifier":identifier, @"sourcePath":sourcePath, @"manifestPath":manifestPath, @"manifest":manifest, @"sha256":actualHash};
}

static NSDictionary *LBProcessImportRequest(NSDictionary *request, NSError **error) {
    NSString *identifier = [request[@"identifier"] isKindOfClass:NSString.class] ? request[@"identifier"] : nil;
    NSDictionary *item = LBLoadManagedTendiesItem(identifier, error);
    if (!item) return nil;

    NSString *container = [LBPosterBoardInstaller findPosterBoardContainer:error];
    if (!container) return nil;

    NSDictionary *installation = [LBPosterBoardInstaller installArchiveAtPath:item[@"sourcePath"]
        posterBoardContainer:container error:error];
    if (!installation) return nil;

    NSMutableDictionary *manifest = [item[@"manifest"] mutableCopy];
    manifest[@"status"] = @"imported";
    manifest[@"installationState"] = @"installed";
    manifest[@"installedAt"] = [NSDate date];
    manifest[@"installedDescriptorIdentifiers"] = installation[@"installedDescriptorIdentifiers"] ?: @[];
    manifest[@"installationReport"] = installation;
    NSData *manifestData = [NSPropertyListSerialization dataWithPropertyList:manifest
        format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    if (!manifestData || ![manifestData writeToFile:item[@"manifestPath"] options:NSDataWritingAtomic error:error]) {
        // The descriptors are already safely published. Do not remove them because
        // a local manifest write failure must not turn a completed system install into
        // a destructive rollback. The completion tells the UI to report the mismatch.
        NSMutableDictionary *result = [installation mutableCopy];
        result[@"manifestUpdateWarning"] = @"PosterBoard descriptors were installed, but the local manifest could not be updated.";
        return result;
    }
    struct passwd *mobile = getpwnam("mobile");
    if (mobile) chown([item[@"manifestPath"] fileSystemRepresentation], mobile->pw_uid, mobile->pw_gid);
    chmod([item[@"manifestPath"] fileSystemRepresentation], 0600);
    return installation;
}

static void LBProcessRequests(void) {
    [LBRequestLock lock];
    @try {
        NSFileManager *fm = NSFileManager.defaultManager;
        NSError *directoryError = nil;
        if (!LBEnsureDaemonDirectories(&directoryError)) {
            NSLog(@"[LumenBoard] Cannot initialize IPC directories: %@", directoryError);
            return;
        }
        NSArray<NSString *> *entries = [fm contentsOfDirectoryAtPath:LBRequestsPath() error:nil] ?: @[];
        for (NSString *entry in entries) @autoreleasepool {
            if (![entry.pathExtension.lowercaseString isEqualToString:@"plist"]) continue;
            NSString *requestID = entry.stringByDeletingPathExtension.lowercaseString;
            if (!LBValidUUID(requestID)) continue;
            NSString *path = [LBRequestsPath() stringByAppendingPathComponent:entry];
            if (!LBRegularFile(path, 1024 * 1024)) continue;

            NSDictionary *request = [NSDictionary dictionaryWithContentsOfFile:path];
            if (![request isKindOfClass:NSDictionary.class] ||
                ![request[@"requestID"] isKindOfClass:NSString.class] ||
                [request[@"requestID"] caseInsensitiveCompare:requestID] != NSOrderedSame) {
                [fm removeItemAtPath:path error:nil];
                continue;
            }

            NSError *operationError = nil;
            NSDictionary *operationResult = nil;
            NSString *action = [request[@"action"] isKindOfClass:NSString.class] ? request[@"action"] : @"";
            if ([action isEqualToString:@"import-tendies"]) {
                operationResult = LBProcessImportRequest(request, &operationError);
            } else {
                operationError = [NSError errorWithDomain:@"com.iuyghi.LumenBoard.Daemon" code:110 userInfo:@{NSLocalizedDescriptionKey:@"Unsupported daemon action."}];
            }

            NSMutableDictionary *completion = [@{
                @"requestID":requestID,
                @"action":action,
                @"finished":@YES,
                @"success":@(operationResult != nil)
            } mutableCopy];
            if (operationResult) completion[@"result"] = operationResult;
            if (operationError) {
                completion[@"error"] = operationError.localizedDescription ?: @"Native import failed.";
                completion[@"errorCode"] = @(operationError.code);
            }
            if (!LBWriteCompletion(requestID, completion)) {
                NSLog(@"[LumenBoard] Failed to write completion for request %@", requestID);
                continue;
            }
            [fm removeItemAtPath:path error:nil];
        }
    } @finally {
        [LBRequestLock unlock];
    }
}

static void LBNotificationCallback(CFNotificationCenterRef center, void *observer, CFStringRef name,
                                   const void *object, CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)name; (void)object; (void)userInfo;
    @autoreleasepool { LBProcessRequests(); }
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        (void)argc; (void)argv;
        LBRequestLock = [NSLock new];
        NSError *error = nil;
        if (!LBEnsureDaemonDirectories(&error)) {
            NSLog(@"[LumenBoard] Cannot initialize support directories: %@", error);
            return 1;
        }
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL,
            LBNotificationCallback, (__bridge CFStringRef)LBDarwinReloadNotification(), NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
        LBProcessRequests();
        NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:2.0 repeats:YES block:^(__unused NSTimer *timer) {
            @autoreleasepool { LBProcessRequests(); }
        }];
        (void)timer;
        [[NSRunLoop currentRunLoop] run];
    }
    return 0;
}
