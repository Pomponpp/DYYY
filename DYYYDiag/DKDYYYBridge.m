// DKDYYYBridge.m — 诊断子系统与 DYYY 主工程的最小桥
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "AwemeHeaders.h"
#import "../DYYYClassRegistry.h"
#import "DKDYYYBridge.h"
#import "Debug/DKDebugInspector.h"
#import "DYYYToast.h"

static BOOL DYYYDiagExportBusy = NO;

@implementation DKDYYYBridge : NSObject

+ (NSString *)runtimeLogPath {
    return [DYYYDiagnostics runtimeLogPath];
}

+ (NSString *)exportFingerprint {
    return [NSString stringWithFormat:
        @"全屏=%d 详情页新机制(实验)=%d 评论避让视频=%d 毛玻璃=%d 设备=%@ 系统=%@ 抖音=%@",
        DYYYGetBool(@"DYYYEnableFullScreen") ? 1 : 0,
        1,
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
    return nil;
}

// ============ 浮窗菜单专属动作（全部 present 到浮窗自己的 VC） ============

// 运行日志：写 DYDebug-log-时间戳.txt 到 DYYY/logs/，再弹分享
+ (void)exportRuntimeLogFromOverlay:(UIViewController *)overlay {
    if (DYYYDiagExportBusy) return;
    DYYYDiagExportBusy = YES;
    [DYYYDiagnostics appendRuntimeLogLine:@"—— 导出时刻开关状态 ——"];
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyyMMdd-HHmmss";
    NSString *name = [NSString stringWithFormat:@"DYDebug-log-%@.txt", [fmt stringFromDate:[NSDate date]]];
    NSString *dst = [[DYYYDiagnostics exportedLogPathWithName:@""] stringByAppendingString:name];
    NSString *src = [DYYYDiagnostics runtimeLogPath];
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:src]) [fm copyItemAtPath:src toPath:dst error:nil];
    DYYYDiagExportBusy = NO;
    NSURL *url = [NSURL fileURLWithPath:dst];
    UIActivityViewController *act = [[UIActivityViewController alloc] initWithActivityItems:@[ url ] applicationActivities:nil];
    act.popoverPresentationController.sourceView = overlay.view;
    act.popoverPresentationController.sourceRect = overlay.view.bounds;
    [overlay presentViewController:act animated:YES completion:nil];
}

// 环境自检：报告写入 DYDebug-audit.txt 并弹分享
+ (void)showAuditReportFromOverlay:(UIViewController *)overlay {
    NSString *report = [DYYYClassRegistry auditReportText] ?: @"(无)";
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyyMMdd-HHmmss";
    NSString *name = [NSString stringWithFormat:@"DYDebug-audit-%@.txt", [fmt stringFromDate:[NSDate date]]];
    NSString *dst = [[DYYYDiagnostics exportedLogPathWithName:@""] stringByAppendingString:name];
    [[report dataUsingEncoding:NSUTF8StringEncoding] writeToFile:dst atomically:YES];
    NSURL *url = [NSURL fileURLWithPath:dst];
    UIActivityViewController *act = [[UIActivityViewController alloc] initWithActivityItems:@[ url ] applicationActivities:nil];
    act.popoverPresentationController.sourceView = overlay.view;
    act.popoverPresentationController.sourceRect = overlay.view.bounds;
    [overlay presentViewController:act animated:YES completion:nil];
}

// 清空日志：Truncate runtime.log + Toast（无 UI 弹窗）
+ (void)clearRuntimeLogFromOverlay:(UIViewController *)overlay {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *src = [DYYYDiagnostics runtimeLogPath];
    if ([fm fileExistsAtPath:src]) [fm createFileAtPath:src contents:[NSData data] attributes:nil];
    [DYYYDiagnostics appendRuntimeLogLine:@"—— 日志已清空，以下为新会话 ——"];
    [DYYYToast showSuccessToastWithMessage:@"运行日志已清空"];
}

@end
