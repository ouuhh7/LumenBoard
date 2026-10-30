#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LBPosterBoardInstaller : NSObject

/// Installs descriptor-format .tendies contents into the iOS 16 Collections
/// descriptor store for a known PosterBoard data-container path.
/// The caller must run as root. Container-format archives are rejected.
+ (nullable NSDictionary *)installArchiveAtPath:(NSString *)archivePath
                          posterBoardContainer:(NSString *)containerPath
                                          error:(NSError * _Nullable * _Nullable)error;

/// Installs an already safely extracted descriptor tree into a supplied store.
/// This entry point is also used by the macOS XCTest suite.
+ (nullable NSDictionary *)installExtractedDescriptorTreeAtPath:(NSString *)extractedPath
                                                   descriptorRoot:(NSString *)descriptorRoot
                                                             error:(NSError * _Nullable * _Nullable)error;

/// Resolves the PosterBoard app data container using its MCM metadata identifier.
+ (nullable NSString *)findPosterBoardContainer:(NSError * _Nullable * _Nullable)error;

@end

NS_ASSUME_NONNULL_END
