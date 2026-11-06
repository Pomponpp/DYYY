#import <UIKit/UIKit.h>

@interface DYYYFloatDiagButton : UIButton
+ (instancetype)sharedButton;
+ (void)attachToWindowIfNeeded:(UIWindow *)window;
+ (void)refreshPresence;
+ (void)removeFromWindowIfPresent;
+ (BOOL)isDiagEntryEnabled;
@end
