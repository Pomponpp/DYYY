#import <UIKit/UIKit.h>

@interface DYYYFloatDiagWindow : UIWindow
// 启动早期一次性安装（hidden 待命），随后只翻 hidden。
+ (void)install;
+ (void)setEnabled:(BOOL)on;
@end

@interface DYYYFloatDiagController : UIViewController
@property (nonatomic, strong) UIButton *wrenchButton;
@end
