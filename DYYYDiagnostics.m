// DYYYDiagnostics — 运行日志导出 + 可读自检报告面板（类声明见 AwemeHeaders.h）
// 日志文件位于 NSTemporaryDirectory()/DYYYLogs/runtime.log（系统会清理临时目录），
// 因此导出时拷贝到 Documents/DYYY/logs 持久保存（文件 App 可直接取）。
// 诊断导出为纯写文件 + Toast，不弹任何分享/告警面板。
#import "AwemeHeaders.h"
#import "DYYYClassRegistry.h"
#import "DYYYToast.h"
#import "DYYYUtils.h"
#import <UIKit/UIKit.h>

static NSString *const kDYYYRuntimeLogSubdir = @"DYYYLogs";
static NSString *const kDYYYRuntimeLogName = @"runtime.log";
static const unsigned long long kDYYYRuntimeLogMaxBytes = 2 * 1024 * 1024; // 2MB 轮转
static const NSUInteger kDYYYRuntimeLogMaxBackups = 1;
static const NSTimeInterval kDYYYRuntimeLogMaxAge = 3 * 24 * 60 * 60; // 保留 3 天

static BOOL gDYYYExportBusy = NO;
static NSUncaughtExceptionHandler *gDYYYPreviousHandler = nil;

@implementation DYYYDiagnostics

// 未捕获 NSException 兜底：写入日志再交还系统（闪退后日志里有现场）
static void DYYYUncaughtExceptionHandler(NSException *exception) {
    @try {
        NSString *line = [NSString stringWithFormat:@"[DYYY][CRASH] 未捕获异常: %@ | %@", exception.name, exception.reason ?: @"(无 reason)"];
        NSArray *symbols = exception.callStackSymbols;
        for (NSString *s in symbols) [DYYYDiagnostics appendRuntimeLogLine:[@"   " stringByAppendingString:s]];
    } @catch (__unused NSException *e) {
    }
    // 交还系统默认 handler，保持崩溃上报行为
    if (gDYYYPreviousHandler) gDYYYPreviousHandler(exception);
}

+ (void)installUncaughtExceptionHandler {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      gDYYYPreviousHandler = NSGetUncaughtExceptionHandler();
      NSSetUncaughtExceptionHandler(DYYYUncaughtExceptionHandler);
    });
}

+ (NSString *)runtimeLogDirectory {
    static NSString *dir = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      dir = [NSTemporaryDirectory() stringByAppendingPathComponent:kDYYYRuntimeLogSubdir];
      [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:nil];
    });
    return dir;
}

+ (NSString *)runtimeLogPath {
    return [[self runtimeLogDirectory] stringByAppendingPathComponent:kDYYYRuntimeLogName];
}

+ (void)appendRuntimeLogLine:(NSString *)line {
    if (line.length == 0) {
        return;
    }

    static dispatch_queue_t logQueue = nil;
    static dispatch_once_t queueOnceToken;
    dispatch_once(&queueOnceToken, ^{
      logQueue = [self logQueueForExport];
    });

    dispatch_async(logQueue, ^{
      @autoreleasepool {
          NSData *lineData = [line dataUsingEncoding:NSUTF8StringEncoding];
          if (lineData.length == 0) {
              return;
          }

          NSString *logPath = [self runtimeLogPath];
          NSFileManager *fileManager = [NSFileManager defaultManager];
          [self rotateRuntimeLogIfNeededOnQueue];
          if (![fileManager fileExistsAtPath:logPath]) {
              [fileManager createFileAtPath:logPath contents:nil attributes:nil];
          }

          NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:logPath];
          if (!fileHandle) {
              return;
          }
          @try {
              [fileHandle seekToEndOfFile];
              [fileHandle writeData:lineData];
              [fileHandle closeFile];
          } @catch (NSException *exception) {
          }
      }
    });
}

// #40：轮转必须在日志串行队列内执行（与 append/closeFile 串行化），
// 主线程直接 move 文件会与队列线程的 handle 操作竞态 → closeFile 崩溃。
+ (void)rotateRuntimeLogIfNeeded {
    if ([NSThread isMainThread]) {
        dispatch_async([self logQueueForExport], ^{ [self rotateRuntimeLogIfNeededOnQueue]; });
        return;
    }
    [self rotateRuntimeLogIfNeededOnQueue];
}

+ (void)rotateRuntimeLogIfNeededOnQueue {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDictionary *attrs = [fileManager attributesOfItemAtPath:[self runtimeLogPath] error:nil];
    unsigned long long size = [attrs fileSize];
    if (size < kDYYYRuntimeLogMaxBytes) {
        return;
    }

    // runtime.log.N -> runtime.log.N+1，最新的挪走，新文件由下次 append 自动创建。
    for (NSInteger backupIndex = (NSInteger)kDYYYRuntimeLogMaxBackups - 1; backupIndex >= 1; backupIndex--) {
        NSString *from = [NSString stringWithFormat:@"%@.%ld", [self runtimeLogPath], (long)backupIndex];
        NSString *to = [NSString stringWithFormat:@"%@.%ld", [self runtimeLogPath], (long)(backupIndex + 1)];
        if ([fileManager fileExistsAtPath:from]) {
            [fileManager removeItemAtPath:to error:nil];
            [fileManager moveItemAtPath:from toPath:to error:nil];
        }
    }
    NSString *firstBackup = [NSString stringWithFormat:@"%@.1", [self runtimeLogPath]];
    [fileManager removeItemAtPath:firstBackup error:nil];
    [fileManager moveItemAtPath:[self runtimeLogPath] toPath:firstBackup error:nil];
}

// 手机侧日志清理：启动时清理超过保留期(3天)的日志文件与过期导出副本，
// 防止长期占用存储。导出目录 Documents/DYYY/logs 也一并清理旧文件。
// #41：清理必须在日志队列内（删 backup/导出副本与队列线程 append 竞态）
+ (void)cleanupStaleLogs {
    if ([NSThread isMainThread]) {
        dispatch_sync([self logQueueForExport], ^{ [self cleanupStaleLogsOnQueue]; });
        return;
    }
    [self cleanupStaleLogsOnQueue];
}

+ (void)cleanupStaleLogsOnQueue {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      NSFileManager *fileManager = [NSFileManager defaultManager];
      NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:-kDYYYRuntimeLogMaxAge];
      NSArray<NSString *> *dirs = @[
          [self runtimeLogDirectory],
          [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject]
              stringByAppendingPathComponent:@"DYYY/logs"],
      ];
      for (NSString *dir in dirs) {
          NSArray<NSString *> *files = [fileManager contentsOfDirectoryAtPath:dir error:nil];
          for (NSString *file in files) {
              if (![file hasSuffix:@".log"] && ![file hasSuffix:@".txt"]) continue;
              NSString *path = [dir stringByAppendingPathComponent:file];
              NSDate *modified = [fileManager attributesOfItemAtPath:path error:nil].fileModificationDate;
              if (modified && [modified compare:deadline] == NSOrderedAscending) {
                  [fileManager removeItemAtPath:path error:nil];
              }
          }
      }
    });
}

// 手动清空：运行日志截断（句柄仍开着，不能删——删了后续写入会落到
// 已删除的 inode 上，表现为"清空后日志再也没内容"）；轮转备份删除；
// 导出副本全部清除。
+ (void)clearRuntimeLogFromViewController:(UIViewController *)presenter {
    if (!presenter) {
        return;
    }
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *runtime = [self runtimeLogPath];
    // 核心：截断而非删除。NSFileHandle 写入句柄仍指向同一文件，
    // 后续 append 正常落盘。
    [fileManager createFileAtPath:runtime contents:[NSData data] attributes:nil];
    NSString *dir = [self runtimeLogDirectory];
    for (NSString *file in [fileManager contentsOfDirectoryAtPath:dir error:nil]) {
        // 只删轮转备份（runtime.log.1 等），主文件已截断
        if ([file hasPrefix:@"runtime.log."] && ![file hasSuffix:@".log"]) {
            [fileManager removeItemAtPath:[dir stringByAppendingPathComponent:file] error:nil];
        }
    }
    NSString *exportDir = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject]
        stringByAppendingPathComponent:@"DYYY/logs"];
    for (NSString *file in [fileManager contentsOfDirectoryAtPath:exportDir error:nil]) {
        if ([file hasSuffix:@".txt"] || [file hasSuffix:@".log"]) {
            [fileManager removeItemAtPath:[exportDir stringByAppendingPathComponent:file] error:nil];
        }
    }
    // 清空后立刻写入新会话头，保证导出永远有版本指纹可对
    [self appendRuntimeLogLine:@"—— 日志已清空，以下为新会话 ——"];
    [DYYYToast showSuccessToastWithMessage:@"运行日志已清空"];
}

+ (dispatch_queue_t)logQueueForExport {
    static dispatch_queue_t q = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ q = dispatch_queue_create("com.dyyy.runtime-log.export", DISPATCH_QUEUE_SERIAL); });
    return q;
}

// 纯 C 落盘（Foundation writeToFile 在 fsync/扩展属性路径会抛 C++ 异常，@try 接不住）
+ (BOOL)safeWriteData:(NSData *)data toPath:(NSString *)path {
    return [[NSFileManager defaultManager] createFileAtPath:path contents:data attributes:nil];
}

+ (BOOL)safeWriteString:(NSString *)str toPath:(NSString *)path {
    return [self safeWriteData:[str dataUsingEncoding:NSUTF8StringEncoding] toPath:path];
}

+ (NSString *)exportedLogPathWithName:(NSString *)name {
    NSString *documents = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *dir = [[documents stringByAppendingPathComponent:@"DYYY"] stringByAppendingPathComponent:@"logs"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:name];
}

// 一键诊断包：日志 + 视图树 + 环境/开关状态 + 截图，四样时间戳天然对齐。
// 导出为单个目录（Documents/DYYY/logs/DYYY-diag-时间戳/）后弹分享。
+ (void)exportDiagnosticsBundleFromViewController:(UIViewController *)presenter {
    // 纯写文件 + Toast：零 present / 零 UIActivityViewController / 零 UIAlertController。
    // 所有历史 .ips 的崩点（present 冲突、Metal abort、Foundation C++ 写入）
    // 在这条路径上物理不存在。产物固定落在 文件App→DYYY/logs/DYYY-diag-时间戳/。
    if (gDYYYExportBusy) { [DYYYToast showSuccessToastWithMessage:@"正在导出，请稍候"]; return; }
    gDYYYExportBusy = YES;
    [self appendRuntimeLogLine:[NSString stringWithFormat:
        @"[DYYY][diag] stepP1 presenter=%@ window=%d busy已置",
        NSStringFromClass(presenter.class), presenter.view.window ? 1 : 0]];

    [self appendRuntimeLogLine:@"—— 导出时刻开关状态 ——"];
    [self appendRuntimeLogLine:[NSString stringWithFormat:
        @"[DYYY][fullscreen] 导出状态：全屏=%d 详情页新机制(实验)=%d 评论避让视频=%d 毛玻璃=%d",
        DYYYGetBool(@"DYYYEnableFullScreen") ? 1 : 0,
        DYYYGetBool(@"DYYYFullNewDetailTable") ? 1 : 0,
        DYYYGetBool(@"DYYYCommentAvoidVideo") ? 1 : 0,
        DYYYGetBool(@"DYYYEnableCommentBlur") ? 1 : 0]];

    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyyMMdd-HHmmss";
    NSString *stamp = [fmt stringFromDate:[NSDate date]];
    NSString *dir = [[self exportedLogPathWithName:@""] stringByAppendingString:
        [NSString stringWithFormat:@"DYYY-diag-%@", stamp]];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];

    // ① 运行日志（拷贝，源文件由串行队列维护）
    NSString *logSrc = [self runtimeLogPath];
    if ([fm fileExistsAtPath:logSrc]) {
        [fm copyItemAtPath:logSrc toPath:[dir stringByAppendingPathComponent:@"runtime.log"] error:nil];
    }

    // ② 视图树（DYYYUtils 内部已用 POSIX 写入，避开 Foundation C++ 异常）
    if ([NSThread isMainThread]) {
        @try { [DYYYUtils dumpAllWindowsViewTreeToFile:[dir stringByAppendingPathComponent:@"view-tree.txt"]]; }
        @catch (NSException *e) { NSLog(@"[DYYY][diag] view-tree exception: %@", e.name); }
    }

    // ③ 环境状态
    NSMutableDictionary *st = [NSMutableDictionary dictionary];
    st[@"timestamp"] = [NSDate date];
    st[@"deviceModel"] = [UIDevice currentDevice].model;
    st[@"systemVersion"] = [UIDevice currentDevice].systemVersion;
    st[@"appVersion"] = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    st[@"screenBounds"] = NSStringFromCGRect([UIScreen mainScreen].bounds);
    st[@"fullScreen"] = @(DYYYGetBool(@"DYYYEnableFullScreen"));
    st[@"fullNewDetailTable"] = @(DYYYGetBool(@"DYYYFullNewDetailTable"));
    st[@"commentBlur"] = @(DYYYGetBool(@"DYYYEnableCommentBlur"));
    NSData *jd = [NSJSONSerialization dataWithJSONObject:st options:NSJSONWritingPrettyPrinted error:nil];
    if (jd) [self safeWriteData:jd toPath:[dir stringByAppendingPathComponent:@"state.json"]];

    // ④ 截图禁用说明（Metal 层会 C++ abort，@try 接不住）
    [self safeWriteString:@"screenshot disabled: Metal layer abort risk" toPath:[dir stringByAppendingPathComponent:@"screenshot-skip.txt"]];

    gDYYYExportBusy = NO;
    [self appendRuntimeLogLine:@"[DYYY][diag] stepP2 采集完成，准备分享面板"];
    NSURL *zipless = [NSURL fileURLWithPath:dir];
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[ zipless ] applicationActivities:nil];
    if (activity.popoverPresentationController) {
        activity.popoverPresentationController.sourceView = presenter.view ?: [UIApplication sharedApplication].keyWindow;
        activity.popoverPresentationController.sourceRect = presenter.view ? presenter.view.bounds : CGRectMake(0, 0, 1, 1);
    }
    [DYYYToast showSuccessToastWithMessage:[NSString stringWithFormat:@"诊断包已生成\n文件App → DYYY/logs/%@", [dir lastPathComponent]]];
    [self appendRuntimeLogLine:[NSString stringWithFormat:
        @"[DYYY][diag] stepP3 present到%@ window=%d",
        NSStringFromClass(presenter.class), presenter.view.window ? 1 : 0]];
    @try {
    if (presenter && presenter.view.window) {
        [presenter presentViewController:activity animated:YES completion:nil];
        [self appendRuntimeLogLine:@"[DYYY][diag] stepP4 present调用已发出"];
    } else {
        NSLog(@"[DYYY][diag] no presenter window, bundle at %@", dir);
        [self appendRuntimeLogLine:@"[DYYY][diag] stepP4 无窗口presenter，跳过分享"];
    }
    } @catch (NSException *e) {
        [self appendRuntimeLogLine:[NSString stringWithFormat:@"[DYYY][diag] stepP4 present异常: %@", e.name]];
    }
}

+ (void)exportRuntimeLogFromViewController:(UIViewController *)presenter {
    // 纯写文件 + Toast，零弹窗
    [self appendRuntimeLogLine:@"—— 导出时刻开关状态 ——"];
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyyMMdd-HHmmss";
    NSString *name = [NSString stringWithFormat:@"DYYY-log-%@.txt", [fmt stringFromDate:[NSDate date]]];
    NSString *dst = [self exportedLogPathWithName:name];
    NSString *src = [self runtimeLogPath];
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:src]) [fm copyItemAtPath:src toPath:dst error:nil];
    NSURL *logURL = [NSURL fileURLWithPath:dst];
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[ logURL ] applicationActivities:nil];
    if (activity.popoverPresentationController) {
        activity.popoverPresentationController.sourceView = presenter.view ?: [UIApplication sharedApplication].keyWindow;
        activity.popoverPresentationController.sourceRect = presenter.view ? presenter.view.bounds : CGRectMake(0, 0, 1, 1);
    }
    [DYYYToast showSuccessToastWithMessage:[NSString stringWithFormat:@"日志已导出\n文件App → DYYY/logs/%@", name]];
    if (presenter && presenter.view.window) {
        [presenter presentViewController:activity animated:YES completion:nil];
    } else {
        NSLog(@"[DYYY][diag] log at %@", dst);
    }
}

+ (void)showAuditReportFromViewController:(UIViewController *)presenter {
    // 写报告文件 + Toast，零弹窗
    NSString *report = [DYYYClassRegistry auditReportText] ?: @"(无)";
    [self safeWriteString:report toPath:[self exportedLogPathWithName:@"DYYY-audit.txt"]];
    [DYYYToast showSuccessToastWithMessage:@"自检报告已保存\n文件App → DYYY/logs/DYYY-audit.txt"];
}

@end
