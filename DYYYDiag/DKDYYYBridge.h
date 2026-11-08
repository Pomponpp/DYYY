// DKDYYYBridge.h — 诊断子系统与 DYYY 主工程的桥接口
#ifndef DKDYYYBridge_h
#define DKDYYYBridge_h
#import <Foundation/Foundation.h>

@interface DKDYYYBridge : NSObject
+ (NSString *)runtimeLogPath;
+ (NSString *)exportFingerprint;
+ (UIViewController *)diagPresenter; // 浮窗窗口 rootVC（安全 presenter）
@end

#endif
