// DKDYYYBridge.h — 诊断子系统与 DYYY 主工程的桥接口
#ifndef DKDYYYBridge_h
#define DKDYYYBridge_h
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface DKDYYYBridge : NSObject
+ (NSString *)runtimeLogPath;
+ (void)appendRuntimeLogLine:(NSString *)line;
+ (NSString *)exportFingerprint;
+ (UIViewController *)diagPresenter;
// 浮窗菜单专属：四项诊断动作（present 到浮窗自己的 VC，零抖音耦合）
+ (void)exportRuntimeLogFromOverlay:(UIViewController *)overlay;
+ (void)showAuditReportFromOverlay:(UIViewController *)overlay;
+ (void)clearRuntimeLogFromOverlay:(UIViewController *)overlay;

// 适配诊断：三份采集（跑抖音升级适配时用）
+ (NSString *)compatAuditText;          // 类自检报告 + hook 生效数
+ (NSString *)compatClassListText;      // 运行时全部抖音类名
+ (NSString *)compatTargetMethodsText;  // 目标类的方法清单
@end

#endif
