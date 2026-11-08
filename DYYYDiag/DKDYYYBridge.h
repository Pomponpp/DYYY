// DKDYYYBridge.h — 诊断子系统与 DYYY 主工程的桥接口
#ifndef DKDYYYBridge_h
#define DKDYYYBridge_h
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface DKDYYYBridge : NSObject
+ (NSString *)runtimeLogPath;
+ (NSString *)exportFingerprint;
+ (UIViewController *)diagPresenter;
// 浮窗菜单专属：四项诊断动作（present 到浮窗自己的 VC，零抖音耦合）
+ (void)exportRuntimeLogFromOverlay:(UIViewController *)overlay;
+ (void)showAuditReportFromOverlay:(UIViewController *)overlay;
+ (void)clearRuntimeLogFromOverlay:(UIViewController *)overlay;
@end

#endif
