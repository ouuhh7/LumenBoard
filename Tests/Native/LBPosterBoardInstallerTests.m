#import <XCTest/XCTest.h>
#import "../../Daemon/LBPosterBoardInstaller.h"
#import <sys/stat.h>
#import <unistd.h>

@interface LBPosterBoardInstallerTests : XCTestCase
@property(nonatomic, copy) NSString *temporaryRoot;

- (void)testReadOnlyVerificationFindsPublishedDescriptorAndReportsMissingRecord {
    NSString *input = [self makeDescriptorGroupWithNames:@[@"Verification fixture"] missingFiles:[NSSet set]];
    NSString *container = [self.temporaryRoot stringByAppendingPathComponent:@"MockPosterBoardContainer"];
    NSString *descriptorRoot = [[container stringByAppendingPathComponent:@"Library/Application Support/PRBPosterExtensionDataStore/59/Extensions"]
        stringByAppendingPathComponent:@"com.apple.WallpaperKit.CollectionsPoster/descriptors"];
    NSError *error = nil;
    NSDictionary *installed = [LBPosterBoardInstaller installExtractedDescriptorTreeAtPath:input
        descriptorRoot:descriptorRoot error:&error];
    XCTAssertNotNil(installed, @"%@", error);
    NSString *uuid = [installed[@"installedDescriptorIdentifiers"] firstObject];

    NSDictionary *complete = [LBPosterBoardInstaller verifyRegisteredDescriptorIdentifiers:@[uuid]
        posterBoardContainer:container error:&error];
    XCTAssertNotNil(complete, @"%@", error);
    XCTAssertEqualObjects(complete[@"descriptorStoreState"], @"complete");
    XCTAssertEqualObjects(complete[@"verificationScope"], @"filesystem-registration-only");
    XCTAssertEqualObjects(complete[@"posterBoardApplicationState"], @"unverified");
    XCTAssertEqualObjects(complete[@"expectedDescriptorCount"], @1);
    XCTAssertEqualObjects(complete[@"presentDescriptorCount"], @1);
    XCTAssertEqualObjects(complete[@"missingDescriptorCount"], @0);
    XCTAssertEqualObjects(complete[@"invalidDescriptorCount"], @0);

    NSString *published = [descriptorRoot stringByAppendingPathComponent:uuid];
    XCTAssertTrue([[NSFileManager defaultManager] removeItemAtPath:published error:&error], @"%@", error);
    NSDictionary *missing = [LBPosterBoardInstaller verifyRegisteredDescriptorIdentifiers:@[uuid]
        posterBoardContainer:container error:&error];
    XCTAssertNotNil(missing, @"%@", error);
    XCTAssertEqualObjects(missing[@"descriptorStoreState"], @"missing");
    XCTAssertEqualObjects(missing[@"presentDescriptorCount"], @0);
    XCTAssertEqualObjects(missing[@"missingDescriptorCount"], @1);
}

@end

@implementation LBPosterBoardInstallerTests

- (void)setUp {
    [super setUp];
    self.temporaryRoot = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"LumenBoardInstallerTests-%@", NSUUID.UUID.UUIDString.lowercaseString]];
    NSError *error = nil;
    XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:self.temporaryRoot
        withIntermediateDirectories:NO attributes:nil error:&error], @"%@", error);
}

- (void)tearDown {
    if (self.temporaryRoot.length) [[NSFileManager defaultManager] removeItemAtPath:self.temporaryRoot error:nil];
    [super tearDown];
}

- (BOOL)writePlist:(id)object toPath:(NSString *)path {
    NSError *error = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:object
        format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
    if (!data) return NO;
    return [data writeToFile:path options:NSDataWritingAtomic error:&error];
}

- (NSString *)makeDescriptorGroupWithNames:(NSArray<NSString *> *)names
                              missingFiles:(NSSet<NSString *> *)missingFiles {
    NSString *group = [self.temporaryRoot stringByAppendingPathComponent:@"input/descriptors"];
    NSError *error = nil;
    XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:group withIntermediateDirectories:YES attributes:nil error:&error], @"%@", error);
    NSUInteger index = 0;
    for (NSString *name in names) {
        index++;
        NSString *root = [group stringByAppendingPathComponent:[NSString stringWithFormat:@"fixture-%lu", (unsigned long)index]];
        NSString *contents = [root stringByAppendingPathComponent:@"versions/1/contents"];
        NSString *wallpaperName = [NSString stringWithFormat:@"Fixture%lu.Custom.wallpaper", (unsigned long)index];
        NSString *wallpaper = [contents stringByAppendingPathComponent:wallpaperName];
        XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:wallpaper withIntermediateDirectories:YES attributes:nil error:&error], @"%@", error);

        if (![missingFiles containsObject:@"descriptor-id"]) {
            [@"12345" writeToFile:[root stringByAppendingPathComponent:@"com.apple.posterkit.provider.descriptor.identifier"]
                atomically:YES encoding:NSUTF8StringEncoding error:&error];
        }
        if (![missingFiles containsObject:@"role"]) {
            [@"PRPosterRoleLockScreen" writeToFile:[root stringByAppendingPathComponent:@"com.apple.posterkit.role.identifier"]
                atomically:YES encoding:NSUTF8StringEncoding error:&error];
        }
        if (![missingFiles containsObject:@"provider-info"]) {
            XCTAssertTrue([self writePlist:@{@"kConfigurationLastUseDateKey":[NSDate date]}
                toPath:[root stringByAppendingPathComponent:@"providerInfo.plist"]]);
        }
        if (![missingFiles containsObject:@"user-info"]) {
            NSDictionary *userInfo = @{
                @"wallpaperRepresentingFileName":wallpaperName,
                @"wallpaperRepresentingIdentifier":@"12345",
                @"posterEnvironmentOverrides":[@"{}" dataUsingEncoding:NSUTF8StringEncoding]
            };
            XCTAssertTrue([self writePlist:userInfo
                toPath:[contents stringByAppendingPathComponent:@"com.apple.posterkit.provider.contents.userInfo"]]);
        }
        if (![missingFiles containsObject:@"wallpaper-plist"]) {
            NSDictionary *wallpaperPlist = @{
                @"identifier":@12345,
                @"name":name,
                @"assets":@{
                    @"lockAndHome":@{
                        @"default":@{
                            @"identifier":@12345,
                            @"name":name,
                            @"type":@"LayeredAnimation",
                            @"backgroundAnimationFileName":@"PF_Background.ca",
                            @"floatingAnimationFileNameKey":@"PF_Floating.ca"
                        }
                    }
                }
            };
            XCTAssertTrue([self writePlist:wallpaperPlist
                toPath:[wallpaper stringByAppendingPathComponent:@"Wallpaper.plist"]]);
            for (NSString *layerName in @[@"PF_Background.ca", @"PF_Floating.ca"]) {
                NSString *layer = [wallpaper stringByAppendingPathComponent:layerName];
                XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:layer withIntermediateDirectories:NO attributes:nil error:&error], @"%@", error);
                [@"<caml/>" writeToFile:[layer stringByAppendingPathComponent:@"main.caml"] atomically:YES encoding:NSUTF8StringEncoding error:&error];
                [@"index" writeToFile:[layer stringByAppendingPathComponent:@"index.xml"] atomically:YES encoding:NSUTF8StringEncoding error:&error];
            }
        }
        [@"fixture asset" writeToFile:[wallpaper stringByAppendingPathComponent:@"sample.asset"]
            atomically:YES encoding:NSUTF8StringEncoding error:&error];
    }
    return [self.temporaryRoot stringByAppendingPathComponent:@"input"];
}

- (NSDictionary *)install:(NSString *)input {
    NSString *descriptorRoot = [self.temporaryRoot stringByAppendingPathComponent:@"PosterBoard/59/Extensions/com.apple.WallpaperKit.CollectionsPoster/descriptors"];
    NSError *error = nil;
    NSDictionary *result = [LBPosterBoardInstaller installExtractedDescriptorTreeAtPath:input descriptorRoot:descriptorRoot error:&error];
    if (!result) XCTFail(@"Installer failed: %@", error);
    return result;
}

- (void)testInstallsOneDescriptorAndRewritesAllLinkedIdentifiers {
    NSString *input = [self makeDescriptorGroupWithNames:@[@"Synthetic wallpaper"] missingFiles:[NSSet set]];
    NSDictionary *result = [self install:input];
    XCTAssertEqualObjects(result[@"installedDescriptorCount"], @1);
    XCTAssertEqualObjects(result[@"descriptorStructureVersion"], @59);
    XCTAssertEqualObjects(result[@"extension"], @"com.apple.WallpaperKit.CollectionsPoster");

    NSString *descriptorRoot = [self.temporaryRoot stringByAppendingPathComponent:@"PosterBoard/59/Extensions/com.apple.WallpaperKit.CollectionsPoster/descriptors"];
    NSString *uuid = [result[@"installedDescriptorIdentifiers"] firstObject];
    XCTAssertNotNil([[NSUUID alloc] initWithUUIDString:uuid]);
    NSString *published = [descriptorRoot stringByAppendingPathComponent:uuid];
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:[published stringByAppendingPathComponent:@"com.apple.posterkit.provider.descriptor.identifier"]]);

    NSString *rootID = [NSString stringWithContentsOfFile:[published stringByAppendingPathComponent:@"com.apple.posterkit.provider.descriptor.identifier"]
        encoding:NSUTF8StringEncoding error:nil];
    NSInteger numericID = rootID.integerValue;
    XCTAssertGreaterThanOrEqual(numericID, 10000);
    XCTAssertLessThanOrEqual(numericID, 99999);
    XCTAssertNotEqual(numericID, 12345);

    NSString *contents = [published stringByAppendingPathComponent:@"versions/1/contents"];
    NSString *userInfoPath = [contents stringByAppendingPathComponent:@"com.apple.posterkit.provider.contents.userInfo"];
    NSDictionary *userInfo = [NSDictionary dictionaryWithContentsOfFile:userInfoPath];
    XCTAssertEqualObjects(userInfo[@"wallpaperRepresentingIdentifier"], rootID);
    NSString *wallpaperName = userInfo[@"wallpaperRepresentingFileName"];
    NSString *wallpaperPath = [contents stringByAppendingPathComponent:wallpaperName];
    XCTAssertTrue([[NSFileManager defaultManager] fileExistsAtPath:[wallpaperPath stringByAppendingPathComponent:@"sample.asset"]]);
    NSDictionary *wallpaperPlist = [NSDictionary dictionaryWithContentsOfFile:[wallpaperPath stringByAppendingPathComponent:@"Wallpaper.plist"]];
    XCTAssertEqualObjects(wallpaperPlist[@"identifier"], @(numericID));
    XCTAssertEqualObjects(wallpaperPlist[@"assets"][@"lockAndHome"][@"default"][@"identifier"], @(numericID));
}

- (void)testInstallsMultipleDescriptorsWithUniqueUUIDsAndNumericIDs {
    NSString *input = [self makeDescriptorGroupWithNames:@[@"One", @"Two"] missingFiles:[NSSet set]];
    NSDictionary *result = [self install:input];
    XCTAssertEqualObjects(result[@"installedDescriptorCount"], @2);
    NSArray *ids = result[@"installedDescriptorIdentifiers"];
    XCTAssertEqual(ids.count, 2u);
    XCTAssertNotEqualObjects(ids[0], ids[1]);

    NSString *descriptorRoot = [self.temporaryRoot stringByAppendingPathComponent:@"PosterBoard/59/Extensions/com.apple.WallpaperKit.CollectionsPoster/descriptors"];
    NSMutableSet *numericIDs = [NSMutableSet set];
    for (NSString *uuid in ids) {
        NSString *root = [descriptorRoot stringByAppendingPathComponent:uuid];
        NSString *text = [NSString stringWithContentsOfFile:[root stringByAppendingPathComponent:@"com.apple.posterkit.provider.descriptor.identifier"] encoding:NSUTF8StringEncoding error:nil];
        [numericIDs addObject:text ?: @""];
    }
    XCTAssertEqual(numericIDs.count, 2u);
}

- (void)testRejectsMissingWallpaperWithoutPublishingAnything {
    NSString *input = [self makeDescriptorGroupWithNames:@[@"Missing wallpaper"] missingFiles:[NSSet setWithObject:@"wallpaper-plist"]];
    NSString *descriptorRoot = [self.temporaryRoot stringByAppendingPathComponent:@"PosterBoard/59/Extensions/com.apple.WallpaperKit.CollectionsPoster/descriptors"];
    NSError *error = nil;
    NSDictionary *result = [LBPosterBoardInstaller installExtractedDescriptorTreeAtPath:input descriptorRoot:descriptorRoot error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
    NSArray *published = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:descriptorRoot error:nil] ?: @[];
    XCTAssertEqual(published.count, 0u);
}

- (void)testRejectsMissingProviderInfoWithoutPublishingAnything {
    NSString *input = [self makeDescriptorGroupWithNames:@[@"Missing provider info"] missingFiles:[NSSet setWithObject:@"provider-info"]];
    NSString *descriptorRoot = [self.temporaryRoot stringByAppendingPathComponent:@"PosterBoard/59/Extensions/com.apple.WallpaperKit.CollectionsPoster/descriptors"];
    NSError *error = nil;
    NSDictionary *result = [LBPosterBoardInstaller installExtractedDescriptorTreeAtPath:input descriptorRoot:descriptorRoot error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
    NSArray *published = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:descriptorRoot error:nil] ?: @[];
    XCTAssertEqual(published.count, 0u);
}

- (void)testRejectsSymlinkInDescriptorWithoutPublishingAnything {
    NSString *input = [self makeDescriptorGroupWithNames:@[@"Symlink fixture"] missingFiles:[NSSet set]];
    NSString *descriptor = [input stringByAppendingPathComponent:@"descriptors/fixture-1"];
    NSString *target = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [@"outside" writeToFile:target atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSString *linkPath = [descriptor stringByAppendingPathComponent:@"escape.link"];
    XCTAssertEqual(symlink(target.fileSystemRepresentation, linkPath.fileSystemRepresentation), 0);

    NSString *descriptorRoot = [self.temporaryRoot stringByAppendingPathComponent:@"PosterBoard/59/Extensions/com.apple.WallpaperKit.CollectionsPoster/descriptors"];
    NSError *error = nil;
    NSDictionary *result = [LBPosterBoardInstaller installExtractedDescriptorTreeAtPath:input descriptorRoot:descriptorRoot error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
    NSArray *published = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:descriptorRoot error:nil] ?: @[];
    XCTAssertEqual(published.count, 0u);
    [[NSFileManager defaultManager] removeItemAtPath:target error:nil];
}


- (void)testRejectsSymlinkInPosterBoardDestinationParent {
    NSString *input = [self makeDescriptorGroupWithNames:@[@"Destination symlink"] missingFiles:[NSSet set]];
    NSString *realParent = [self.temporaryRoot stringByAppendingPathComponent:@"real-store"];
    NSError *error = nil;
    XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:realParent withIntermediateDirectories:YES attributes:nil error:&error], @"%@", error);
    NSString *linkParent = [self.temporaryRoot stringByAppendingPathComponent:@"store-link"];
    XCTAssertEqual(symlink(realParent.fileSystemRepresentation, linkParent.fileSystemRepresentation), 0);

    NSString *descriptorRoot = [linkParent stringByAppendingPathComponent:@"descriptors"];
    NSDictionary *result = [LBPosterBoardInstaller installExtractedDescriptorTreeAtPath:input descriptorRoot:descriptorRoot error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
    NSArray *published = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:realParent error:nil] ?: @[];
    XCTAssertEqual(published.count, 0u);
}

- (void)testRejectsMultipleDescriptorGroupsInsteadOfMixingExtensions {
    NSString *input = [self makeDescriptorGroupWithNames:@[@"Collections"] missingFiles:[NSSet set]];
    NSString *other = [input stringByAppendingPathComponent:@"descriptor"];
    NSError *error = nil;
    XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtPath:other withIntermediateDirectories:YES attributes:nil error:&error], @"%@", error);
    NSDictionary *result = [LBPosterBoardInstaller installExtractedDescriptorTreeAtPath:input
        descriptorRoot:[self.temporaryRoot stringByAppendingPathComponent:@"PosterBoard/descriptors"] error:&error];
    XCTAssertNil(result);
    XCTAssertNotNil(error);
}

@end
