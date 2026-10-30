#import "LBPosterBoardInstaller.h"
#import "../Preferences/LBTendiesValidator.h"
#import <sys/stat.h>
#import <sys/types.h>
#import <unistd.h>
#import <errno.h>
#import <spawn.h>
#import <sys/wait.h>
#import <pwd.h>
#import <stdio.h>
#import <string.h>

extern char **environ;

static NSString * const LBIssueDomain = @"com.iuyghi.LumenBoard.PosterBoardInstaller";
static NSString * const LBCollectionsExtension = @"com.apple.WallpaperKit.CollectionsPoster";
static const NSInteger LBExpectedStructureVersion = 59;

static NSError *LBInstallError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:LBIssueDomain code:code userInfo:@{NSLocalizedDescriptionKey: message ?: @"PosterBoard installation failed."}];
}

static BOOL LBIsRegularFile(NSString *path) {
    struct stat st;
    return lstat(path.fileSystemRepresentation, &st) == 0 && S_ISREG(st.st_mode) && !S_ISLNK(st.st_mode);
}

static BOOL LBIsDirectory(NSString *path) {
    struct stat st;
    return lstat(path.fileSystemRepresentation, &st) == 0 && S_ISDIR(st.st_mode) && !S_ISLNK(st.st_mode);
}

static BOOL LBEnsureDirectoryTree(NSString *path, mode_t mode, NSError **error) {
    NSString *normalized = path.stringByStandardizingPath;
    if (![normalized hasPrefix:@"/"]) {
        if (error) *error = LBInstallError(9, @"PosterBoard destination must be an absolute path.");
        return NO;
    }
    NSMutableString *current = [NSMutableString string];
    for (NSString *component in [normalized componentsSeparatedByString:@"/"]) {
        if (!component.length) continue;
        [current appendFormat:@"/%@", component];
        NSString *candidate = [current copy];
        struct stat st;
        if (lstat(candidate.fileSystemRepresentation, &st) == 0) {
            if (!S_ISDIR(st.st_mode) || S_ISLNK(st.st_mode)) {
                if (error) *error = LBInstallError(10, [NSString stringWithFormat:@"Refusing a non-directory or symlink at %@", candidate]);
                return NO;
            }
            continue;
        }
        if (errno != ENOENT || mkdir(candidate.fileSystemRepresentation, mode) != 0) {
            if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
            return NO;
        }
    }
    return YES;
}

static BOOL LBSetMobileOwnership(NSString *root, NSError **error) {
    struct passwd *mobile = getpwnam("mobile");
    // XCTest runs on macOS, where there is no mobile account. Allow mode-only
    // setup for non-root test hosts; the production daemon runs as root and
    // must resolve the mobile account before publishing into PosterBoard.
    if (!mobile && geteuid() == 0) {
        if (error) *error = LBInstallError(11, @"The mobile user could not be resolved for PosterBoard descriptor ownership.");
        return NO;
    }
    NSFileManager *fm = NSFileManager.defaultManager;
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:root];
    NSString *relative = nil;
    NSMutableArray<NSString *> *paths = [NSMutableArray arrayWithObject:root];
    while ((relative = enumerator.nextObject)) [paths addObject:[root stringByAppendingPathComponent:relative]];
    // Change descendants before parents so the staged tree is readable when published.
    for (NSString *path in [paths reverseObjectEnumerator]) {
        struct stat st;
        if (lstat(path.fileSystemRepresentation, &st) != 0 || S_ISLNK(st.st_mode) ||
            (!S_ISDIR(st.st_mode) && !S_ISREG(st.st_mode))) {
            if (error) *error = LBInstallError(12, [NSString stringWithFormat:@"Unsafe object in staged descriptor: %@", path]);
            return NO;
        }
        mode_t mode = S_ISDIR(st.st_mode) ? 0755 : 0644;
        if ((mobile && chown(path.fileSystemRepresentation, mobile->pw_uid, mobile->pw_gid) != 0) ||
            chmod(path.fileSystemRepresentation, mode) != 0) {
            if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
            return NO;
        }
    }
    return YES;
}

static BOOL LBEnsureDirectory(NSString *path, mode_t mode, NSError **error) {
    struct stat st;
    if (lstat(path.fileSystemRepresentation, &st) == 0) {
        if (S_ISDIR(st.st_mode) && !S_ISLNK(st.st_mode)) return YES;
        if (error) *error = LBInstallError(13, [NSString stringWithFormat:@"Refusing a non-directory or symlink at %@", path]);
        return NO;
    }
    if (errno != ENOENT || mkdir(path.fileSystemRepresentation, mode) != 0) {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        return NO;
    }
    return YES;
}

static BOOL LBWriteDataAtomically(NSData *data, NSString *path, NSError **error) {
    NSString *temporary = [path stringByAppendingFormat:@".lumenboard-%@", NSUUID.UUID.UUIDString.lowercaseString];
    int fd = open(temporary.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL
#ifdef O_NOFOLLOW
                  | O_NOFOLLOW
#endif
                  , 0600);
    if (fd < 0) {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
        return NO;
    }
    const uint8_t *bytes = data.bytes;
    NSUInteger offset = 0;
    BOOL ok = YES;
    while (offset < data.length) {
        ssize_t count = write(fd, bytes + offset, data.length - offset);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) { ok = NO; break; }
        offset += (NSUInteger)count;
    }
    if (ok && fsync(fd) != 0) ok = NO;
    int savedErrno = errno;
    close(fd);
    if (!ok || rename(temporary.fileSystemRepresentation, path.fileSystemRepresentation) != 0) {
        if (ok) savedErrno = errno;
        unlink(temporary.fileSystemRepresentation);
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:savedErrno userInfo:nil];
        return NO;
    }
    chmod(path.fileSystemRepresentation, 0600);
    return YES;
}

static NSString *LBReadTrimmedString(NSString *path) {
    if (!LBIsRegularFile(path)) return nil;
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data || data.length == 0 || data.length > 128) return nil;
    NSString *value = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    return [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static BOOL LBIsPositiveNumericIdentifier(id value) {
    if (![value isKindOfClass:NSNumber.class]) return NO;
    long long number = [value longLongValue];
    return number > 0 && number <= 999999;
}

static BOOL LBPathIsSafeRelative(NSString *path) {
    if (![path isKindOfClass:NSString.class] || path.length == 0 || [path hasPrefix:@"/"] || [path containsString:@"\\"]) return NO;
    NSArray<NSString *> *parts = [path componentsSeparatedByString:@"/"];
    for (NSString *part in parts) if (!part.length || [part isEqualToString:@"."] || [part isEqualToString:@".."]) return NO;
    return YES;
}

static BOOL LBValidateDescriptorTree(NSString *root, NSError **error) {
    if (!LBIsDirectory(root)) {
        if (error) *error = LBInstallError(20, @"A descriptor entry is not a regular directory.");
        return NO;
    }

    NSDirectoryEnumerator *enumerator = [NSFileManager.defaultManager enumeratorAtPath:root];
    NSString *relative = nil;
    while ((relative = enumerator.nextObject)) {
        NSString *full = [root stringByAppendingPathComponent:relative];
        struct stat st;
        if (lstat(full.fileSystemRepresentation, &st) != 0 || S_ISLNK(st.st_mode) ||
            (!S_ISDIR(st.st_mode) && !S_ISREG(st.st_mode))) {
            if (error) *error = LBInstallError(21, [NSString stringWithFormat:@"Unsafe descriptor entry: %@", relative]);
            return NO;
        }
    }

    NSString *descriptorIDPath = [root stringByAppendingPathComponent:@"com.apple.posterkit.provider.descriptor.identifier"];
    NSString *rolePath = [root stringByAppendingPathComponent:@"com.apple.posterkit.role.identifier"];
    NSString *providerInfoPath = [root stringByAppendingPathComponent:@"providerInfo.plist"];
    NSString *descriptorID = LBReadTrimmedString(descriptorIDPath);
    NSScanner *identifierScanner = descriptorID.length ? [NSScanner scannerWithString:descriptorID] : nil;
    long long parsedIdentifier = 0;
    BOOL numericDescriptorID = identifierScanner && [identifierScanner scanLongLong:&parsedIdentifier] &&
        identifierScanner.isAtEnd && parsedIdentifier > 0;
    if (!numericDescriptorID || !LBIsRegularFile(rolePath) || !LBIsRegularFile(providerInfoPath)) {
        if (error) *error = LBInstallError(22, @"Descriptor is missing its numeric root identifier, role identifier, or providerInfo.plist.");
        return NO;
    }
    NSData *providerInfo = [NSData dataWithContentsOfFile:providerInfoPath];
    if (!providerInfo || ![NSPropertyListSerialization propertyListWithData:providerInfo options:NSPropertyListImmutable format:nil error:nil]) {
        if (error) *error = LBInstallError(23, @"providerInfo.plist is not a readable property list.");
        return NO;
    }

    __block NSUInteger wallpaperCount = 0;
    __block BOOL userInfoFound = NO;
    __block BOOL wallpaperBundleFound = NO;
    NSDirectoryEnumerator *files = [NSFileManager.defaultManager enumeratorAtPath:root];
    NSString *file = nil;
    while ((file = files.nextObject)) {
        NSString *full = [root stringByAppendingPathComponent:file];
        NSString *last = file.lastPathComponent;
        if ([last isEqualToString:@"com.apple.posterkit.provider.contents.userInfo"]) {
            if (!LBIsRegularFile(full)) continue;
            NSData *data = [NSData dataWithContentsOfFile:full];
            NSDictionary *userInfo = data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainers format:nil error:nil] : nil;
            NSString *representingName = [userInfo[@"wallpaperRepresentingFileName"] isKindOfClass:NSString.class] ? userInfo[@"wallpaperRepresentingFileName"] : nil;
            id representingID = userInfo[@"wallpaperRepresentingIdentifier"];
            if (![userInfo isKindOfClass:NSDictionary.class] || !representingName.length ||
                !LBPathIsSafeRelative(representingName) ||
                !([representingID isKindOfClass:NSString.class] || LBIsPositiveNumericIdentifier(representingID))) {
                if (error) *error = LBInstallError(24, @"provider contents user-info is missing a safe wallpaper filename or identifier.");
                return NO;
            }
            NSString *contentsRoot = full.stringByDeletingLastPathComponent;
            NSString *wallpaperPath = [contentsRoot stringByAppendingPathComponent:representingName];
            if (!LBIsDirectory(wallpaperPath)) {
                if (error) *error = LBInstallError(25, @"The wallpaper bundle referenced by provider user-info does not exist.");
                return NO;
            }
            userInfoFound = YES;
            wallpaperBundleFound = YES;
        }
        if ([last caseInsensitiveCompare:@"Wallpaper.plist"] == NSOrderedSame) {
            if (!LBIsRegularFile(full)) continue;
            NSData *data = [NSData dataWithContentsOfFile:full];
            NSDictionary *wallpaper = data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainers format:nil error:nil] : nil;
            if (![wallpaper isKindOfClass:NSDictionary.class] ||
                !LBIsPositiveNumericIdentifier(wallpaper[@"identifier"]) ||
                ![wallpaper[@"name"] isKindOfClass:NSString.class] ||
                ![wallpaper[@"assets"] isKindOfClass:NSDictionary.class]) {
                if (error) *error = LBInstallError(26, [NSString stringWithFormat:@"Invalid Wallpaper.plist at %@", file]);
                return NO;
            }
            wallpaperCount++;
        }
    }
    if (!wallpaperCount || !userInfoFound || !wallpaperBundleFound) {
        if (error) *error = LBInstallError(27, @"Descriptor requires Wallpaper.plist and provider user-info that references an existing wallpaper bundle.");
        return NO;
    }
    return YES;
}

static BOOL LBRewriteDescriptorIdentifiers(NSString *root, NSInteger numericID, NSError **error) {
    NSString *descriptorID = [NSString stringWithFormat:@"%ld", (long)numericID];
    NSData *idData = [descriptorID dataUsingEncoding:NSUTF8StringEncoding];
    NSString *rootIDPath = [root stringByAppendingPathComponent:@"com.apple.posterkit.provider.descriptor.identifier"];
    if (!LBWriteDataAtomically(idData, rootIDPath, error)) return NO;

    NSDirectoryEnumerator *enumerator = [NSFileManager.defaultManager enumeratorAtPath:root];
    NSString *relative = nil;
    while ((relative = enumerator.nextObject)) {
        NSString *full = [root stringByAppendingPathComponent:relative];
        NSString *name = relative.lastPathComponent;
        if ([name isEqualToString:@"com.apple.posterkit.provider.contents.userInfo"]) {
            NSData *data = [NSData dataWithContentsOfFile:full];
            NSMutableDictionary *userInfo = data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainers format:nil error:nil] : nil;
            if (![userInfo isKindOfClass:NSMutableDictionary.class]) {
                if (error) *error = LBInstallError(30, @"Cannot rewrite provider contents user-info.");
                return NO;
            }
            userInfo[@"wallpaperRepresentingIdentifier"] = descriptorID;
            NSData *rewritten = [NSPropertyListSerialization dataWithPropertyList:userInfo format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
            if (!rewritten || !LBWriteDataAtomically(rewritten, full, error)) return NO;
        } else if ([name caseInsensitiveCompare:@"Wallpaper.plist"] == NSOrderedSame) {
            NSData *data = [NSData dataWithContentsOfFile:full];
            NSMutableDictionary *wallpaper = data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListMutableContainers format:nil error:nil] : nil;
            if (![wallpaper isKindOfClass:NSMutableDictionary.class]) {
                if (error) *error = LBInstallError(31, @"Cannot rewrite Wallpaper.plist.");
                return NO;
            }
            wallpaper[@"identifier"] = @(numericID);
            NSMutableDictionary *assets = [wallpaper[@"assets"] mutableCopy];
            NSMutableDictionary *lockAndHome = [assets[@"lockAndHome"] mutableCopy];
            NSMutableDictionary *defaults = [lockAndHome[@"default"] mutableCopy];
            if (defaults && defaults[@"identifier"]) defaults[@"identifier"] = @(numericID);
            if (defaults) lockAndHome[@"default"] = defaults;
            if (lockAndHome) assets[@"lockAndHome"] = lockAndHome;
            if (assets) wallpaper[@"assets"] = assets;
            NSData *rewritten = [NSPropertyListSerialization dataWithPropertyList:wallpaper format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
            if (!rewritten || !LBWriteDataAtomically(rewritten, full, error)) return NO;
        }
    }
    return YES;
}

static BOOL LBCollectDescriptorRoots(NSString *extractedPath, NSMutableArray<NSString *> *roots, NSError **error) {
    NSDirectoryEnumerator *enumerator = [NSFileManager.defaultManager enumeratorAtPath:extractedPath];
    NSString *relative = nil;
    NSMutableArray<NSString *> *candidates = [NSMutableArray array];
    while ((relative = enumerator.nextObject)) {
        NSString *full = [extractedPath stringByAppendingPathComponent:relative];
        if (!LBIsDirectory(full)) continue;
        NSString *name = relative.lastPathComponent.lowercaseString;
        if ([name isEqualToString:@"descriptor"] || [name isEqualToString:@"descriptors"]) {
            NSArray<NSString *> *parts = [relative.lowercaseString componentsSeparatedByString:@"/"];
            BOOL unsupportedVariant = NO;
            for (NSString *part in parts) {
                if ([part containsString:@"video"] || [part containsString:@"photos"] ||
                    [part containsString:@"mercury"] || [part isEqualToString:@"container"]) unsupportedVariant = YES;
            }
            if (unsupportedVariant) {
                if (error) *error = LBInstallError(40, @"This Tendies archive targets a non-Collections PosterBoard extension or a whole-container restore.");
                return NO;
            }
            [candidates addObject:full];
            [enumerator skipDescendants];
        }
    }
    if (candidates.count != 1) {
        if (error) *error = LBInstallError(41, @"Expected exactly one descriptor/descriptors group for the iOS 16 Collections extension.");
        return NO;
    }
    NSArray<NSString *> *children = [NSFileManager.defaultManager contentsOfDirectoryAtPath:candidates.firstObject error:error];
    if (!children) return NO;
    for (NSString *child in children) {
        if ([child hasPrefix:@"."] || [child isEqualToString:@"__MACOSX"]) continue;
        NSString *path = [candidates.firstObject stringByAppendingPathComponent:child];
        if (!LBIsDirectory(path)) {
            if (error) *error = LBInstallError(42, @"The descriptor group contains a non-directory entry.");
            return NO;
        }
        [roots addObject:path];
    }
    if (!roots.count) {
        if (error) *error = LBInstallError(43, @"The descriptor group contains no descriptor directories.");
        return NO;
    }
    return YES;
}

static BOOL LBReadExistingNumericIdentifiers(NSString *descriptorRoot, NSMutableSet<NSNumber *> *used) {
    NSArray<NSString *> *entries = [NSFileManager.defaultManager contentsOfDirectoryAtPath:descriptorRoot error:nil];
    for (NSString *entry in entries) {
        NSString *path = [descriptorRoot stringByAppendingPathComponent:entry];
        if (!LBIsDirectory(path)) continue;
        NSString *text = LBReadTrimmedString([path stringByAppendingPathComponent:@"com.apple.posterkit.provider.descriptor.identifier"]);
        long long value = text.longLongValue;
        if (text.length && value > 0) [used addObject:@(value)];
    }
    return YES;
}

@implementation LBPosterBoardInstaller

+ (NSString *)findPosterBoardContainer:(NSError **)error {
    NSString *base = @"/var/mobile/Containers/Data/Application";
    if (!LBIsDirectory(base)) {
        if (error) *error = LBInstallError(50, @"The iOS application-container root is not available.");
        return nil;
    }
    for (NSString *entry in [NSFileManager.defaultManager contentsOfDirectoryAtPath:base error:nil] ?: @[]) {
        NSString *candidate = [base stringByAppendingPathComponent:entry];
        if (!LBIsDirectory(candidate)) continue;
        NSString *metadataPath = [candidate stringByAppendingPathComponent:@".com.apple.mobile_container_manager.metadata.plist"];
        if (!LBIsRegularFile(metadataPath)) continue;
        NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:metadataPath];
        if ([metadata[@"MCMMetadataIdentifier"] isEqual:@"com.apple.PosterBoard"]) return candidate;
    }
    if (error) *error = LBInstallError(51, @"PosterBoard app data container was not found by MCMMetadataIdentifier.");
    return nil;
}

+ (NSDictionary *)installArchiveAtPath:(NSString *)archivePath posterBoardContainer:(NSString *)containerPath error:(NSError **)error {
    NSOperatingSystemVersion os = NSProcessInfo.processInfo.operatingSystemVersion;
    if (os.majorVersion != 16) {
        if (error) *error = LBInstallError(52, @"This importer currently targets PosterBoard descriptor structure 59 on iOS 16 only.");
        return nil;
    }
    if (!LBIsDirectory(containerPath)) {
        if (error) *error = LBInstallError(53, @"The resolved PosterBoard container is not a regular directory.");
        return nil;
    }
    NSString *applicationSupport = [containerPath stringByAppendingPathComponent:@"Library/Application Support"];
    NSString *extensionRoot = [[applicationSupport stringByAppendingPathComponent:@"PRBPosterExtensionDataStore/59/Extensions"] stringByAppendingPathComponent:LBCollectionsExtension];
    NSString *descriptorRoot = [extensionRoot stringByAppendingPathComponent:@"descriptors"];

    NSString *stage = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"LumenBoard-%@", NSUUID.UUID.UUIDString.lowercaseString]];
    NSError *validationError = nil;
    NSDictionary *validation = [LBTendiesValidator validateArchiveAtPath:archivePath extractToPath:stage error:&validationError];
    if (![validation[@"status"] isEqual:@"extracted"]) {
        if (error) *error = validationError ?: LBInstallError(54, @"The .tendies archive did not pass validation and extraction.");
        return nil;
    }
    NSDictionary *result = [self installExtractedDescriptorTreeAtPath:stage descriptorRoot:descriptorRoot error:error];
    [NSFileManager.defaultManager removeItemAtPath:stage error:nil];
    if (!result) return nil;

    // PosterBoard reads the descriptor store at process start. Request a controlled
    // refresh after the complete descriptor set is published.
    NSString *preferencesPath = [containerPath stringByAppendingPathComponent:@"Library/Preferences/com.apple.PosterBoard.unprotectedUserDefaults.plist"];
    NSMutableDictionary *preferences = [[NSDictionary dictionaryWithContentsOfFile:preferencesPath] mutableCopy] ?: [NSMutableDictionary dictionary];
    preferences[@"PBF_LOCALE_DID_CHANGE"] = @NO;
    preferences[@"PBF_RESET_FILE_PROTECTIONS"] = @YES;
    NSData *preferencesData = [NSPropertyListSerialization dataWithPropertyList:preferences format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
    BOOL preferencesWritten = preferencesData && LBWriteDataAtomically(preferencesData, preferencesPath, nil);
    int status = 0;
    char *arguments[] = {"/usr/bin/killall", "-9", "PosterBoard", NULL};
    pid_t pid = 0;
    int spawnResult = posix_spawn(&pid, arguments[0], NULL, NULL, arguments, environ);
    BOOL refreshRequested = NO;
    if (spawnResult == 0) {
        int waitStatus = 0;
        if (waitpid(pid, &waitStatus, 0) == pid && WIFEXITED(waitStatus)) status = WEXITSTATUS(waitStatus);
        refreshRequested = (status == 0);
    }
    NSMutableDictionary *final = [result mutableCopy];
    final[@"refreshPreferencesWritten"] = @(preferencesWritten);
    final[@"posterBoardRefreshRequested"] = @(refreshRequested);
    if (!preferencesWritten || !refreshRequested) {
        final[@"refreshWarning"] = @"Descriptors were installed, but PosterBoard could not be conclusively refreshed. A device restart or manual PosterBoard restart may be required.";
    }
    return final;
}

+ (NSDictionary *)installExtractedDescriptorTreeAtPath:(NSString *)extractedPath descriptorRoot:(NSString *)descriptorRoot error:(NSError **)error {
    if (!LBIsDirectory(extractedPath)) {
        if (error) *error = LBInstallError(60, @"The extracted descriptor tree is missing.");
        return nil;
    }
    NSMutableArray<NSString *> *sourceRoots = [NSMutableArray array];
    if (!LBCollectDescriptorRoots(extractedPath, sourceRoots, error)) return nil;
    for (NSString *source in sourceRoots) if (!LBValidateDescriptorTree(source, error)) return nil;

    NSString *extensionRoot = descriptorRoot.stringByDeletingLastPathComponent;
    if (!LBEnsureDirectoryTree(extensionRoot, 0755, error) || !LBEnsureDirectoryTree(descriptorRoot, 0755, error)) return nil;
    NSMutableSet<NSNumber *> *usedIDs = [NSMutableSet set];
    LBReadExistingNumericIdentifiers(descriptorRoot, usedIDs);

    NSString *stagingRoot = [extensionRoot stringByAppendingPathComponent:[NSString stringWithFormat:@".lumenboard-staging-%@", NSUUID.UUID.UUIDString.lowercaseString]];
    if (!LBEnsureDirectory(stagingRoot, 0700, error)) return nil;
    NSMutableArray<NSString *> *stagedPaths = [NSMutableArray array];
    NSMutableArray<NSString *> *publishedPaths = [NSMutableArray array];
    NSMutableArray<NSString *> *committedPaths = [NSMutableArray array];
    NSMutableArray<NSString *> *publishedIdentifiers = [NSMutableArray array];
    BOOL success = YES;
    NSError *localError = nil;

    for (NSString *source in sourceRoots) {
        NSString *newUUID = NSUUID.UUID.UUIDString.uppercaseString;
        NSString *staged = [stagingRoot stringByAppendingPathComponent:newUUID];
        NSString *destination = [descriptorRoot stringByAppendingPathComponent:newUUID];
        struct stat destinationStat;
        if (lstat(destination.fileSystemRepresentation, &destinationStat) == 0 || errno != ENOENT) {
            localError = LBInstallError(61, @"Generated descriptor UUID unexpectedly collides with an existing item.");
            success = NO;
            break;
        }
        if (![NSFileManager.defaultManager copyItemAtPath:source toPath:staged error:&localError]) { success = NO; break; }
        NSInteger identifier = 0;
        for (NSUInteger attempt = 0; attempt < 1000; attempt++) {
            NSInteger candidate = 10000 + arc4random_uniform(90000);
            if (![usedIDs containsObject:@(candidate)]) { identifier = candidate; break; }
        }
        if (!identifier) {
            localError = LBInstallError(62, @"Could not allocate a collision-free PosterBoard wallpaper identifier.");
            success = NO;
            break;
        }
        [usedIDs addObject:@(identifier)];
        if (!LBRewriteDescriptorIdentifiers(staged, identifier, &localError) || !LBSetMobileOwnership(staged, &localError)) { success = NO; break; }
        [stagedPaths addObject:staged];
        [publishedPaths addObject:destination];
        [publishedIdentifiers addObject:newUUID];
    }

    if (success) {
        for (NSUInteger index = 0; index < stagedPaths.count; index++) {
            NSString *staged = stagedPaths[index];
            NSString *destination = publishedPaths[index];
            // Re-check immediately before publication and refuse to replace any
            // object created concurrently since the initial collision check.
            struct stat destinationStat;
            if (lstat(destination.fileSystemRepresentation, &destinationStat) == 0 || errno != ENOENT) {
                localError = LBInstallError(64, @"Destination UUID appeared during staging; refusing to overwrite it.");
                success = NO;
                break;
            }
            if (rename(staged.fileSystemRepresentation, destination.fileSystemRepresentation) != 0) {
                localError = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
                success = NO;
                break;
            }
            [committedPaths addObject:destination];
        }
    }
    if (!success) {
        // Roll back only directories this invocation actually published. Never
        // delete a colliding path that appeared concurrently.
        for (NSString *path in committedPaths.reverseObjectEnumerator) {
            if (LBIsDirectory(path)) [NSFileManager.defaultManager removeItemAtPath:path error:nil];
        }
        [NSFileManager.defaultManager removeItemAtPath:stagingRoot error:nil];
        if (error) *error = localError ?: LBInstallError(63, @"Descriptor publication failed and was rolled back.");
        return nil;
    }
    [NSFileManager.defaultManager removeItemAtPath:stagingRoot error:nil];
    return @{@"installedDescriptorIdentifiers": publishedIdentifiers,
             @"installedDescriptorCount": @(publishedIdentifiers.count),
             @"descriptorStructureVersion": @(LBExpectedStructureVersion),
             @"extension": LBCollectionsExtension};
}

@end
