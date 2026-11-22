//
//  DYYYDiagnosticsCore.h
//  DYYY 诊断系统 · 核心门面
//
//  运行日志（内存环形缓冲，导出时才落盘）+ 导出/清空/清理 + 崩溃捕获
//  + 诊断工具函数（DYYY 命名）。
//
//  设计要点：高频路径（拖动/探针每帧打点）只写内存，零文件 I/O；
//  任何要读 runtime.log 的消费方（导出、诊断包、浮窗）先 flush。
//

#ifndef DYYY_DIAGNOSTICS_CORE_H
#define DYYY_DIAGNOSTICS_CORE_H

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

#pragma mark - 运行日志

@interface DYYYDiagnostics : NSObject

/// 运行日志文件路径（NSTemporaryDirectory()/DYYYLogs/runtime.log）。
/// 读取前必须先调 flushRuntimeLogToFile，否则拿到的是上一次导出时的内容。
+ (NSString *)runtimeLogPath;

/// 追加一行运行日志：只写内存环形缓冲（上限 800 行，满了淘汰最旧），零文件 I/O。
+ (void)appendRuntimeLogLine:(NSString *)line;

/// 把内存缓冲一次性落盘到 runtimeLogPath（覆盖旧内容）。
/// 所有读取 runtimeLogPath 的动作前必须调用。
+ (void)flushRuntimeLogToFile;

/// 导出运行日志副本到 Documents/DYYY/logs（文件 App 可取），返回落盘路径。
+ (NSString *)exportedLogPathWithName:(NSString *)name;

/// 清空运行日志（内存缓冲 + 落盘文件 + 历史导出副本），弹 Toast。
+ (void)clearRuntimeLogFromViewController:(UIViewController *)presenter;

/// 清理超过保留期（3 天）的日志与过期导出副本。
+ (void)cleanupStaleLogs;

/// 未捕获 NSException 兜底：崩溃时把缓冲刷盘，保留现场。
+ (void)installUncaughtExceptionHandler;

#pragma mark - 导出

/// 一键诊断包：日志 + 视图树 + 环境状态 + compat 三件套，落盘后弹分享。
+ (void)exportDiagnosticsBundleFromViewController:(UIViewController *)presenter;

/// 导出运行日志（设置页入口），弹分享。
+ (void)exportRuntimeLogFromViewController:(UIViewController *)presenter;

/// 自检报告写文件 + 弹窗摘要（设置页入口）。
+ (void)showAuditReportFromViewController:(UIViewController *)presenter;

@end

#pragma mark - 诊断工具函数

#ifdef __cplusplus
extern "C" {
#endif

/// 类名 / 对象类名的安全读取（nil 安全）。
NSString *DYYYNameOfClass(Class cls);
NSString *DYYYNameOfObject(id object);

/// 诊断开关读取（统一走 NSUserDefaults，DYYY 键名直读）。
BOOL DYYYPrefBool(NSString *key);
NSInteger DYYYPrefInteger(NSString *key);

/// 沿 responder 链向上找播放互动控制器。
UIViewController *DYYYPlayInteractionControllerForView(UIView *view);

/// 按类名在子控制器树里查找（最多 12 层）。
UIViewController *DYYYChildControllerNamed(UIViewController *controller, NSString *className);

/// 判断颜色是否为不透明纯黑（阈值 0.02 / 0.98）。
BOOL DYYYColorIsOpaqueBlack(UIColor *color);

/// cell contentView 查找与满高读取。
UIView *DYYYCellContentView(UIView *view);
CGFloat DYYYFullCellHeight(UIView *view);

/// 诊断浮窗总开关是否打开（DYYYDiagEntryEnabled）。
BOOL DYYYDiagnosticsOverlayEnabled(void);

#ifdef __cplusplus
}
#endif

/// 诊断包一次导出的产物（zip + 工作目录）。
@interface DYYYDiagnosticsExportResult : NSObject
@property (nonatomic, strong) NSURL *zipURL;
@property (nonatomic, strong) NSURL *workingDirectoryURL;
@end

NS_ASSUME_NONNULL_END

#endif /* DYYY_DIAGNOSTICS_CORE_H */
