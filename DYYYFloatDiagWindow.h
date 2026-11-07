#import <UIKit/UIKit.h>

@interface DYYYFloatDiagWindow : UIWindow
+ (instancetype)sharedWindow;
+ (void)show;
+ (void)hide;
@end

@interface DYYYFloatDiagController : UIViewController
@property (nonatomic, strong) UIButton *wrenchButton;
@end
