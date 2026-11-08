// DYYYDiag — 一体化诊断浮层（独立窗口 + 采集 + 导出）
#ifndef DYYYDiag_h
#define DYYYDiag_h
#import <UIKit/UIKit.h>

@interface DYYYDiagController : UIViewController
@property (nonatomic, strong) UIButton *wrenchButton;
- (BOOL)capturesOverlayTouches;
@end

// .xm 按 ObjC++ 编译，C 函数声明必须带 extern "C" 才能与 .m 的 C 链接对上
#ifdef __cplusplus
extern "C" {
#endif

+ (UIViewController *)diagPresenter;   // 设置页导出用的安全 presenter（浮窗 rootVC）
void DYYYDiagInstall(void);
void DYYYDiagRefresh(void);

#ifdef __cplusplus
}
#endif

#endif
