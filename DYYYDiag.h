// DYYYDiag — 一体化诊断浮层（独立窗口 + 采集 + 导出）
#ifndef DYYYDiag_h
#define DYYYDiag_h
#import <UIKit/UIKit.h>

@interface DYYYDiagController : UIViewController
@property (nonatomic, strong) UIButton *wrenchButton;
@end

void DYYYDiagInstall(void);
void DYYYDiagRefresh(void);
#endif
