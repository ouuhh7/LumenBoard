#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LBPosterMediaBuilder : NSObject
+ (nullable NSString *)buildDescriptorForSource:(NSString *)sourcePath
                                           kind:(NSString *)kind
                                          title:(NSString *)title
                                       homeBlur:(BOOL)homeBlur
                                      outputRoot:(NSString *)outputRoot
                                           error:(NSError * _Nullable * _Nullable)error;
@end

NS_ASSUME_NONNULL_END
