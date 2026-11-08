// DYYYDiagnostics — 运行日志导出 + 可读自检报告面板（类声明见 AwemeHeaders.h）
// 日志文件位于 NSTemporaryDirectory()/DYYYLogs/runtime.log（系统会清理临时目录），
// 因此导出时拷贝到 Documents/DYYY/logs 持久保存，再经 UIActivityViewController
// 用"存储到文件"落到"文件"App，或 AirDrop/复制到其他设备。
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

static NSUncaughtExceptionHandler *gDYYYPreviousHandler = nil;

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

+ (NSString *)exportedLogPathWithName:(NSString *)name {
    NSString *documents = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *dir = [[documents stringByAppendingPathComponent:@"DYYY"] stringByAppendingPathComponent:@"logs"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:name];
}

// 一键诊断包：日志 + 视图树 + 环境/开关状态 + 截图，四样时间戳天然对齐。
// 导出为单个目录（Documents/DYYY/logs/DYYY-diag-时间戳/）后弹分享。
+ (void)exportDiagnosticsBundleFromViewController:(UIViewController *)presenter {
    if (!presenter) {
        return;
    }
    if (gDYYYExportBusy) { [DYYYToast showSuccessToastWithMessage:@"正在导出，请稍候"]; return; }
    gDYYYExportBusy = YES;
    dispatch_sync([self logQueueForExport], ^{
      [self cleanupStaleLogsOnQueue];
      [self rotateRuntimeLogIfNeededOnQueue];
    });

    // 状态指纹（与单导日志一致，诊断包自带可对性）
    [self appendRuntimeLogLine:@"—— 导出时刻开关状态 ——"];
    [self appendRuntimeLogLine:[NSString stringWithFormat:
        @"[DYYY][fullscreen] 导出状态：全屏=%d 详情页新机制(实验)=%d 评论避让视频=%d 毛玻璃=%d",
        DYYYGetBool(@"DYYYEnableFullScreen") ? 1 : 0,
        DYYYGetBool(@"DYYYFullNewDetailTable") ? 1 : 0,
        DYYYGetBool(@"DYYYCommentAvoidVideo") ? 1 : 0,
        DYYYGetBool(@"DYYYEnableCommentBlur") ? 1 : 0]];

    NSDateFormatter *nameFormatter = [[NSDateFormatter alloc] init];
    nameFormatter.dateFormat = @"yyyyMMdd-HHmmss";
    NSString *stamp = [nameFormatter stringFromDate:[NSDate date]];
[DYYYDiagnostics appendRuntimeLogLine:@"[DYYY][diag] step3 bundleDir built"];
    NSString *bundleDir = [[self exportedLogPathWithName:@""] stringByAppendingString:
        [NSString stringWithFormat:@"DYYY-diag-%@", stamp]];
    [[NSFileManager defaultManager] createDirectoryAtPath:bundleDir
                              withIntermediateDirectories:YES attributes:nil error:nil];

[DYYYDiagnostics appendRuntimeLogLine:@"[DYYY][diag] step4 log copy begin"];
    // ① runtime.log
    NSString *logSrc = [self runtimeLogPath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:logSrc]) {
        [[NSString stringWithFormat:@"DYYY 诊断包 %@\n（运行日志为空）\n", [NSDate date]]
            writeToFile:logSrc atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
    [[NSFileManager defaultManager] copyItemAtPath:logSrc
                                           toPath:[bundleDir stringByAppendingPathComponent:@"runtime.log"]
                                            error:nil];

[DYYYDiagnostics appendRuntimeLogLine:@"[DYYY][diag] step5 view-tree begin"];
    // ② 视图树快照（UIView 属性必须主线程读；非主线程调用时跳过并留痕，
    //    绝不 dispatch_sync(main)——同步到主线程会与日志队列交叉死锁）
    NSString *treePath = [bundleDir stringByAppendingPathComponent:@"view-tree.txt"];
    // 防御：父目录再次确保存在 + 路径合法性（writeToFile 在后台队列抛异常
    // 无法被调用方 @try 捕获，必须在源头保证路径可用）
    if ([NSThread isMainThread]) {
        @try {
            [DYYYUtils dumpAllWindowsViewTreeToFile:treePath];
        } @catch (NSException *e) {
            NSLog(@"[DYYY][diag] view-tree exception: %@", e.name);
        }
    } else {
        [[NSString stringWithFormat:@"view-tree skipped: not main thread"]
            writeToFile:treePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }

[DYYYDiagnostics appendRuntimeLogLine:@"[DYYY][diag] step6 state.json begin"];
    // ③ 环境与开关状态
    NSMutableDictionary *state = [NSMutableDictionary dictionary];
    state[@"timestamp"] = [NSDate date];
    state[@"deviceModel"] = [UIDevice currentDevice].model;
    state[@"systemVersion"] = [UIDevice currentDevice].systemVersion;
    state[@"appVersion"] = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    state[@"screenBounds"] = NSStringFromCGRect([UIScreen mainScreen].bounds);
    state[@"screenScale"] = @([UIScreen mainScreen].scale);
    state[@"fullScreen"] = @(DYYYGetBool(@"DYYYEnableFullScreen"));
    state[@"fullNewDetailTable"] = @(DYYYGetBool(@"DYYYFullNewDetailTable"));
    state[@"commentAvoidVideo"] = @(DYYYGetBool(@"DYYYCommentAvoidVideo"));
    state[@"commentBlur"] = @(DYYYGetBool(@"DYYYEnableCommentBlur"));
    state[@"fullscreenDiag"] = @(DYYYGetBool(@"DYYYFullscreenDiag"));
    state[@"hideStatusbar"] = @(DYYYGetBool(@"DYYYHideStatusbar"));
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:state options:NSJSONWritingPrettyPrinted error:nil];
    if (jsonData) {
        [jsonData writeToFile:[bundleDir stringByAppendingPathComponent:@"state.json"]
                  atomically:YES];
    }

[DYYYDiagnostics appendRuntimeLogLine:@"[DYYY][diag] step7 screenshot begin"];
    // ④ 截图：#43 实测 renderInContext 遇 Metal layer 在部分状态直接 abort
    // （C++ 层 assert，@try 接不住）。暂时用占位说明替代，后续用安全截图方案。
    [[NSString stringWithFormat:@"screenshot skipped: Metal layer abort risk"]
        writeToFile:[bundleDir stringByAppendingPathComponent:@"screenshot-skip.txt"]
         atomically:YES encoding:NSUTF8StringEncoding error:nil];

    // #36 防闪退：调用方可能带着已 present 的面板（扳手菜单），先 dismiss
    // 再延迟 present——"presentation in progress" 异常是 SIGABRT 直接来源
    NSURL *bundleURL = [NSURL fileURLWithPath:bundleDir];
    UIActivityViewController *share = [[UIActivityViewController alloc]
        initWithActivityItems:@[ bundleURL ] applicationActivities:nil];
    // 方案2：打包已完成（异步节点），延迟 0.4s 确保转场彻底结束再 present
    // （对齐媒体导出的成熟时机模式——静态时刻 present，零转场冲突）
    // presenter 恒为自己窗口的 rootVC，无转场冲突，直接 present
    [DYYYDiagnostics appendRuntimeLogLine:@"[DYYY][diag] step8 present share"];
    [DYYYDiagnostics safePresentBundleShare:bundleURL from:presenter];
}

// 安全 present（终极版）：present 前若面板在场先 dismiss，completion 后
// 延迟重试（dismiss completion 触发时 UIKit 状态可能仍未就绪——
// 三份 .ips 都是这一类时序异常）。
+ (void)safePresentViewController:(UIViewController *)vc from:(UIViewController *)presenter retries:(NSInteger)retries {
    if (!presenter || !presenter.view.window) return;
    if (presenter.presentedViewController) {
        [presenter dismissViewControllerAnimated:YES completion:^{
          dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                         dispatch_get_main_queue(), ^{
            [DYYYDiagnostics safePresentViewController:vc from:presenter retries:retries];
          });
        }];
        return;
    }
    @try {
        [presenter presentViewController:vc animated:YES completion:nil];
    } @catch (NSException *e) {
        NSLog(@"[DYYY][diag] present exception: %@", e.name);
        if (retries > 0) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
              [DYYYDiagnostics safePresentViewController:vc from:presenter retries:retries - 1];
            });
        }
    }
}

+ (void)safePresentBundleShare:(NSURL *)bundleURL from:(UIViewController *)presenter {
    gDYYYExportBusy = NO;
    if (!presenter || !presenter.view.window) return;
    UIActivityViewController *share = [[UIActivityViewController alloc]
        initWithActivityItems:@[ bundleURL ] applicationActivities:nil];
    share.popoverPresentationController.sourceView = presenter.view;
    share.popoverPresentationController.sourceRect =
        CGRectMake(CGRectGetMidX(presenter.view.bounds), CGRectGetMidY(presenter.view.bounds), 1, 1);
    [DYYYToast showSuccessToastWithMessage:@"诊断包已生成，请存储到文件"];
    [DYYYDiagnostics safePresentViewController:share from:presenter retries:2];
}


+ (void)exportRuntimeLogFromViewController:(UIViewController *)presenter {
    if (!presenter) {
        return;
    }

    // 导出前先清理过期日志（3 天前的运行日志与导出副本）
    dispatch_sync([self logQueueForExport], ^{
      [self cleanupStaleLogsOnQueue];
      [self rotateRuntimeLogIfNeededOnQueue];
    });

    // 版本指纹：导出时刻强制写入当前开关状态到运行日志头部。
    // 不再依赖启动时机（清空/轮转都可能把启动行冲掉），导出的日志
    // 永远自带状态可对——治"测了不知道测没测到"。
    [self appendRuntimeLogLine:@"—— 导出时刻开关状态 ——"];
    [self appendRuntimeLogLine:[NSString stringWithFormat:
        @"[DYYY][fullscreen] 导出状态：全屏=%d 详情页新机制(实验)=%d 评论避让视频=%d 毛玻璃=%d",
        DYYYGetBool(@"DYYYEnableFullScreen") ? 1 : 0,
        DYYYGetBool(@"DYYYFullNewDetailTable") ? 1 : 0,
        DYYYGetBool(@"DYYYCommentAvoidVideo") ? 1 : 0,
        DYYYGetBool(@"DYYYEnableCommentBlur") ? 1 : 0]];

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSString *sourcePath = [self runtimeLogPath];
    NSDateFormatter *nameFormatter = [[NSDateFormatter alloc] init];
    nameFormatter.dateFormat = @"yyyyMMdd-HHmmss";
    NSString *exportName = [NSString stringWithFormat:@"DYYY-log-%@.txt", [nameFormatter stringFromDate:[NSDate date]]];
    NSString *exportPath = [self exportedLogPathWithName:exportName];

    if (![fileManager fileExistsAtPath:sourcePath]) {
        // 还没产生日志：先写一条占位，保证导出面板有内容。
        NSString *placeholder = [NSString stringWithFormat:@"DYYY 日志导出 %@\n（当前运行日志为空）\n\n", [NSDate date]];
        [placeholder writeToFile:sourcePath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }

    [fileManager removeItemAtPath:exportPath error:nil];
    NSError *copyError = nil;
    if (![fileManager copyItemAtPath:sourcePath toPath:exportPath error:&copyError]) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"导出失败"
                                                                       message:copyError.localizedDescription ?: @"未知错误"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
        [presenter presentViewController:alert animated:YES completion:nil];
        return;
    }

    NSURL *exportURL = [NSURL fileURLWithPath:exportPath];
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:@[ exportURL ]
                                                                         applicationActivities:nil];
    share.popoverPresentationController.sourceView = presenter.view;
    share.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(presenter.view.bounds), CGRectGetMidY(presenter.view.bounds), 1, 1);

    UIAlertController *done = [UIAlertController alertControllerWithTitle:@"日志已导出"
                                                                 message:[NSString stringWithFormat:@"已保存到 文件→DYYY/logs/%@\n也可用分享面板直接发送。", exportName]
                                                          preferredStyle:UIAlertControllerStyleAlert];
    [done addAction:[UIAlertAction actionWithTitle:@"打开分享" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
                                                      [DYYYDiagnostics safePresentViewController:share from:presenter retries:2];
                                                  }]];
    [done addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    [presenter presentViewController:done animated:YES completion:nil];
}

+ (void)showAuditReportFromViewController:(UIViewController *)presenter {
    if (!presenter) {
        return;
    }

    NSString *report = [DYYYClassRegistry auditReportText];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"DYYY 自检报告"
                                                                   message:report
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"复制报告"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
                                              [UIPasteboard generalPasteboard].string = report;
                                          }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"导出运行日志"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
                                              [self exportRuntimeLogFromViewController:presenter];
                                          }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

@end
