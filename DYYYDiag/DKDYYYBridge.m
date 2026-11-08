// DKDYYYBridge.m — 诊断子系统与 DYYY 主工程的最小桥
// 提供：运行流水日志路径、状态指纹。诊断文件原样保留，只经此桥读取 DYYY 数据。
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "AwemeHeaders.h"
#import "Debug/DKDebugInspector.h"

@implementation DKDYYYBridge : NSObject

+ (NSString *)runtimeLogPath {
    return [DYYYDiagnostics runtimeLogPath];
}

+ (NSString *)exportFingerprint {
    return [NSString stringWithFormat:
        @"全屏=%d 详情页新机制(实验)=%d 评论避让视频=%d 毛玻璃=%d 设备=%@ 系统=%@ 抖音=%@",
        DYYYGetBool(@"DYYYEnableFullScreen") ? 1 : 0,
        DYYYGetBool(@"DYYYFullNewDetailTable") ? 1 : 0,
        DYYYGetBool(@"DYYYCommentAvoidVideo") ? 1 : 0,
        DYYYGetBool(@"DYYYEnableCommentBlur") ? 1 : 0,
        [UIDevice currentDevice].model,
        [UIDevice currentDevice].systemVersion,
        [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?"];
}

+ (UIViewController *)diagPresenter {
    DKDebugInspectorInstall();
    DKDebugInspectorRefreshOverlay();
    // 调用方在主线程：直接同步查窗口（无 dispatch_sync，避免主队列死锁）
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if ([NSStringFromClass(w.class) hasPrefix:@"DKDebug"] && w.rootViewController && !w.hidden) {
            return w.rootViewController;
        }
    }
    return nil;  // 浮层未就绪：调用方退化处理
}

@end
