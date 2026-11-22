//
//  DYYYDiagnosticsCore.m
//  DYYY 诊断系统 · 核心门面
//
//  与旧实现的根本差异：日志只写内存环形缓冲，导出那一刻才落盘。
//  旧实现每条日志开文件→写→关，探针高开时拖动每帧一次文件 I/O，
//  队列堆积 + 导出拷贝大文件 = 卡死假死。缓冲后高频路径零 I/O。
//

#import "DYYYDiagnosticsCore.h"
#import "AwemeHeaders.h"
#import "DYYYClassRegistry.h"
#import "DYYYToast.h"
#import "DYYYUtils.h"
#import <objc/runtime.h>
#import <os/log.h>

#pragma mark - 常量

// 缓冲上限：800 行足够覆盖一次完整复现（探针 300 上限 + 布局打点 + 环境行），
// 满了淘汰最旧，天然替代旧的 2MB 文件轮转。
static const NSUInteger kDYYYDiagBufferLimit = 800;
static NSString *const kDYYYDiagLogSubdir = @"DYYYLogs";
static NSString *const kDYYYDiagLogName = @"runtime.log";
static const NSTimeInterval kDYYYDiagMaxAge = 3 * 24 * 60 * 60; // 保留 3 天

static BOOL gDYYYDiagExportBusy = NO;
static NSUncaughtExceptionHandler *gDYYYDiagPreviousHandler = nil;

#pragma mark - 日志缓冲

@implementation DYYYDiagnostics

// 缓冲与串行队列（导出落盘用）。append 只碰缓冲，永远不碰文件。
+ (NSMutableArray<NSString *> *)logBuffer {
    static NSMutableArray<NSString *> *buffer = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ buffer = [NSMutableArray array]; });
    return buffer;
}

+ (dispatch_queue_t)diagQueue {
    static dispatch_queue_t q = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      q = dispatch_queue_create("com.dyyy.diagnostics", DISPATCH_QUEUE_SERIAL);
    });
    return q;
}

+ (void)appendRuntimeLogLine:(NSString *)line {
    if (line.length == 0) return;

    // 环形缓冲：只在串行队列里动数组，append 与 flush 天然互斥。
    dispatch_async([self diagQueue], ^{
      @autoreleasepool {
          NSMutableArray<NSString *> *buffer = [self logBuffer];
          [buffer addObject:line];
          if (buffer.count > kDYYYDiagBufferLimit) {
              [buffer removeObjectsInRange:NSMakeRange(0, buffer.count - kDYYYDiagBufferLimit)];
          }
      }
    });
}

+ (void)flushRuntimeLogToFile {
    // 同步等缓冲排空再写盘：导出前调用，保证读到的 runtime.log 是最新的。
    dispatch_sync([self diagQueue], ^{
      @autoreleasepool {
          NSMutableArray<NSString *> *buffer = [self logBuffer];
          NSMutableString *all = [NSMutableString string];
          for (NSString *line in buffer) {
              [all appendFormat:@"%@\n", line];
          }
          NSString *path = [self runtimeLogPath];
          NSFileManager *fm = [NSFileManager defaultManager];
          NSString *dir = [path stringByDeletingLastPathComponent];
          [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
          // 纯 createFile 落盘（Foundation writeToFile 在 fsync/扩展属性路径
          // 会抛 C++ 异常，@try 接不住——沿用旧实现验证过的写法）。
          [fm createFileAtPath:path contents:[all dataUsingEncoding:NSUTF8StringEncoding] attributes:nil];
      }
    });
}

+ (NSString *)runtimeLogDirectory {
    static NSString *dir = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      dir = [NSTemporaryDirectory() stringByAppendingPathComponent:kDYYYDiagLogSubdir];
      [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                withIntermediateDirectories:YES
                                                 attributes:nil
                                                      error:nil];
    });
    return dir;
}

+ (NSString *)runtimeLogPath {
    return [[self runtimeLogDirectory] stringByAppendingPathComponent:kDYYYDiagLogName];
}

+ (NSString *)exportedLogPathWithName:(NSString *)name {
    NSString *documents = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *dir = [[documents stringByAppendingPathComponent:@"DYYY"] stringByAppendingPathComponent:@"logs"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:name];
}

#pragma mark - 清空与清理

+ (void)clearRuntimeLogFromViewController:(UIViewController *)presenter {
    if (!presenter) return;

    // 缓冲清空 + 落盘一个新会话头（保证导出永远有版本指纹可对）。
    dispatch_sync([self diagQueue], ^{
      [[self logBuffer] removeAllObjects];
    });
    [self flushRuntimeLogToFile];
    [self appendRuntimeLogLine:@"—— 日志已清空，以下为新会话 ——"];
    [self flushRuntimeLogToFile];

    // 删历史落盘副本（轮转备份已无意义；导出副本按旧规则清）。
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *exportDir = [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject]
        stringByAppendingPathComponent:@"DYYY/logs"];
    for (NSString *file in [fm contentsOfDirectoryAtPath:exportDir error:nil]) {
        if ([file hasSuffix:@".txt"] || [file hasSuffix:@".log"] ||
            [file hasPrefix:@"DYYY-diag-"]) {
            [fm removeItemAtPath:[exportDir stringByAppendingPathComponent:file] error:nil];
        }
    }
    [DYYYToast showSuccessToastWithMessage:@"运行日志已清空"];
}

+ (void)cleanupStaleLogs {
    dispatch_async([self diagQueue], ^{
      @autoreleasepool {
          NSFileManager *fm = [NSFileManager defaultManager];
          NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:-kDYYYDiagMaxAge];
          NSArray<NSString *> *dirs = @[
              [self runtimeLogDirectory],
              [[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject]
                  stringByAppendingPathComponent:@"DYYY/logs"],
          ];
          for (NSString *dir in dirs) {
              NSArray<NSString *> *files = [fm contentsOfDirectoryAtPath:dir error:nil];
              for (NSString *file in files) {
                  if (![file hasSuffix:@".log"] && ![file hasSuffix:@".txt"] &&
                      ![file hasPrefix:@"DYYY-diag-"]) continue;
                  NSString *path = [dir stringByAppendingPathComponent:file];
                  NSDate *modified = [fm attributesOfItemAtPath:path error:nil].fileModificationDate;
                  if (modified && [modified compare:deadline] == NSOrderedAscending) {
                      [fm removeItemAtPath:path error:nil];
                  }
              }
          }
      }
    });
}

#pragma mark - 崩溃捕获

static void DYYYDiagUncaughtExceptionHandler(NSException *exception) {
    @try {
        NSMutableArray<NSString *> *lines = [NSMutableArray array];
        [lines addObject:[NSString stringWithFormat:@"[DYYY][CRASH] 未捕获异常: %@ | %@",
                          exception.name, exception.reason ?: @"(无 reason)"]];
        for (NSString *s in exception.callStackSymbols) {
            [lines addObject:[@"   " stringByAppendingString:s]];
        }
        // 直接在崩溃线程同步写盘：进程将死，异步队列不会再跑。
        NSMutableArray<NSString *> *buffer = [DYYYDiagnostics logBuffer];
        [buffer addObjectsFromArray:lines];
        NSMutableString *all = [NSMutableString string];
        for (NSString *l in buffer) [all appendFormat:@"%@\n", l];
        [[NSFileManager defaultManager] createFileAtPath:[DYYYDiagnostics runtimeLogPath]
                                              contents:[all dataUsingEncoding:NSUTF8StringEncoding]
                                            attributes:nil];
    } @catch (__unused NSException *e) {
    }
    if (gDYYYDiagPreviousHandler) gDYYYDiagPreviousHandler(exception);
}

+ (void)installUncaughtExceptionHandler {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      gDYYYDiagPreviousHandler = NSGetUncaughtExceptionHandler();
      NSSetUncaughtExceptionHandler(DYYYDiagUncaughtExceptionHandler);
    });
}

#pragma mark - 导出（落盘 + 分享）

+ (NSString *)exportRuntimeLogSnapshot {
    // 先把缓冲刷盘，再返回路径。所有导出路径统一走这里。
    [self flushRuntimeLogToFile];
    return [self runtimeLogPath];
}

+ (void)exportRuntimeLogFromViewController:(UIViewController *)presenter {
    NSString *src = [self exportRuntimeLogSnapshot];
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyyMMdd-HHmmss";
    NSString *name = [NSString stringWithFormat:@"DYYY-log-%@.txt", [fmt stringFromDate:[NSDate date]]];
    NSString *dst = [self exportedLogPathWithName:name];
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:src]) [fm copyItemAtPath:src toPath:dst error:nil];

    [DYYYToast showSuccessToastWithMessage:[NSString stringWithFormat:@"日志已导出\n文件App → DYYY/logs/%@", name]];
    NSURL *logURL = [NSURL fileURLWithPath:dst];
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[ logURL ] applicationActivities:nil];
    if (activity.popoverPresentationController) {
        activity.popoverPresentationController.sourceView = presenter.view ?: [UIApplication sharedApplication].keyWindow;
        activity.popoverPresentationController.sourceRect = presenter.view ? presenter.view.bounds : CGRectMake(0, 0, 1, 1);
    }
    if (presenter && presenter.view.window) {
        [presenter presentViewController:activity animated:YES completion:nil];
    }
}

+ (void)showAuditReportFromViewController:(UIViewController *)presenter {
    NSString *summary = [DYYYClassRegistry compatSummaryText] ?: @"(无)";
    NSString *full = [DYYYClassRegistry auditReportText] ?: @"(无)";
    [[NSFileManager defaultManager] createFileAtPath:[self exportedLogPathWithName:@"DYYY-compat.txt"]
                                          contents:[full dataUsingEncoding:NSUTF8StringEncoding]
                                        attributes:nil];
    if (!presenter) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"兼容性报告"
                                                                  message:summary
                                                           preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"复制完整清单"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *a) {
                                              [UIPasteboard generalPasteboard].string = full;
                                              [DYYYToast showSuccessToastWithMessage:@"已复制到剪贴板"];
                                            }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"重新检测"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *a) {
                                              dispatch_async(dispatch_get_main_queue(), ^{
                                                [self showAuditReportFromViewController:presenter];
                                              });
                                            }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}

// 诊断包导出由 DYYYDiagnosticsExport 实现（视图树 + compat + zip 打包），
// 这里只做入口转发；签名保持与旧门面一致。
+ (void)exportDiagnosticsBundleFromViewController:(UIViewController *)presenter {
    extern void DYYYDiagnosticsExportBundle(UIViewController *presenter);
    DYYYDiagnosticsExportBundle(presenter);
}

@end

#pragma mark - 诊断工具函数

NSString *DYYYNameOfClass(Class cls) {
    if (!cls) return @"";
    const char *raw = class_getName(cls);
    return raw ? [NSString stringWithUTF8String:raw] : @"";
}

NSString *DYYYNameOfObject(id object) {
    if (!object) return @"";
    return DYYYNameOfClass([object class]);
}

BOOL DYYYPrefBool(NSString *key) {
    // 诊断浮窗开关映射到 DYYY 设置键
    if ([key isEqualToString:@"DYYYDebugInspectorEnabled"]) {
        return [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYDiagEntryEnabled"];
    }
    return [[NSUserDefaults standardUserDefaults] boolForKey:key];
}

NSInteger DYYYPrefInteger(NSString *key) {
    return [[NSUserDefaults standardUserDefaults] integerForKey:key];
}

UIViewController *DYYYPlayInteractionControllerForView(UIView *view) {
    static Class interactionClass;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ interactionClass = NSClassFromString(@"AWEPlayInteractionViewController"); });
    if (!interactionClass) return nil;
    for (UIResponder *responder = view.nextResponder; responder; responder = responder.nextResponder) {
        if ([responder isKindOfClass:interactionClass]) return (UIViewController *)responder;
    }
    return nil;
}

static UIViewController *DYYYSearchChildController(UIViewController *controller, NSString *className, NSUInteger depth) {
    if (!controller || depth > 12) return nil;
    for (UIViewController *child in controller.childViewControllers) {
        if ([DYYYNameOfObject(child) isEqualToString:className]) return child;
        UIViewController *match = DYYYSearchChildController(child, className, depth + 1);
        if (match) return match;
    }
    return nil;
}

UIViewController *DYYYChildControllerNamed(UIViewController *controller, NSString *className) {
    return DYYYSearchChildController(controller, className, 0);
}

BOOL DYYYColorIsOpaqueBlack(UIColor *color) {
    if (!color) return NO;
    CGFloat red = 0.0, green = 0.0, blue = 0.0, alpha = 0.0;
    if ([color getRed:&red green:&green blue:&blue alpha:&alpha]) {
        return red <= 0.02 && green <= 0.02 && blue <= 0.02 && alpha >= 0.98;
    }
    CGFloat white = 0.0;
    if ([color getWhite:&white alpha:&alpha]) return white <= 0.02 && alpha >= 0.98;
    return NO;
}

UIView *DYYYCellContentView(UIView *view) {
    static Class contentCls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ contentCls = NSClassFromString(@"UITableViewCellContentView"); });
    if (!contentCls) return nil;
    for (NSUInteger i = 0; view && i < 12; i++) {
        if ([view isKindOfClass:contentCls]) return view;
        view = view.superview;
    }
    return nil;
}

CGFloat DYYYFullCellHeight(UIView *view) {
    UIView *contentView = DYYYCellContentView(view.superview);
    return contentView ? CGRectGetHeight(contentView.bounds) : 0.0;
}

BOOL DYYYDiagnosticsOverlayEnabled(void) {
    return DYYYPrefBool(@"DYYYDebugInspectorEnabled");
}

@implementation DYYYDiagnosticsExportResult
@end
