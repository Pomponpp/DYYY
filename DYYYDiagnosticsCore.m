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
#import <signal.h>
#import <string.h>

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

// 崩溃现场落盘：异常 handler 和信号 handler 共用。
// 崩溃线程同步写盘：进程将死，异步队列不会再跑。
static void DYYYDiagFlushCrashContext(NSString *kind, NSString *detail, NSArray<NSString *> *stack) {
    @try {
        NSMutableArray<NSString *> *lines = [NSMutableArray array];
        [lines addObject:[NSString stringWithFormat:@"[DYYY][CRASH] %@: %@", kind, detail ?: @"(无详情)"]];
        for (NSString *s in stack) {
            [lines addObject:[@"   " stringByAppendingString:s]];
        }
        NSMutableArray<NSString *> *buffer = [DYYYDiagnostics logBuffer];
        [buffer addObjectsFromArray:lines];
        NSMutableString *all = [NSMutableString string];
        for (NSString *l in buffer) [all appendFormat:@"%@\n", l];
        [[NSFileManager defaultManager] createFileAtPath:[DYYYDiagnostics runtimeLogPath]
                                              contents:[all dataUsingEncoding:NSUTF8StringEncoding]
                                            attributes:nil];
    } @catch (__unused NSException *e) {
    }
}

// 信号名：崩溃报告里用可读名字，比裸数字强。
static NSString *DYYYDiagSignalName(int sig) {
    switch (sig) {
        case SIGABRT: return @"SIGABRT(abort)";
        case SIGSEGV: return @"SIGSEGV(段错误)";
        case SIGBUS:  return @"SIGBUS(总线错误)";
        case SIGILL:  return @"SIGILL(非法指令)";
        case SIGFPE:  return @"SIGFPE(算术异常)";
        case SIGTRAP: return @"SIGTRAP(陷阱)";
        default:      return [NSString stringWithFormat:@"signal(%d)", sig];
    }
}

// 上一层信号处理：系统或别的库可能已经装过，处理完原样转交。
static struct sigaction gDYYYDiagPreviousSignalActions[6];
static int gDYYYDiagHandledSignals[6] = {SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGTRAP};

static void DYYYDiagSignalHandler(int sig, siginfo_t *info, void *context) {
    // 这已经是最后时刻：只做内存缓冲 + 一次文件写，不做任何 UIKit 调用。
    NSArray<NSString *> *stack = [NSThread callStackSymbols];
    NSString *addr = (info && info->si_addr) ? [NSString stringWithFormat:@" addr=%p", info->si_addr] : @"";
    DYYYDiagFlushCrashContext(@"信号崩溃", [DYYYDiagSignalName(sig) stringByAppendingString:addr], stack);

    // 还原默认处理并重新投递，让系统照常生成 .ips 报告。
    for (NSUInteger i = 0; i < sizeof(gDYYYDiagHandledSignals) / sizeof(int); i++) {
        if (gDYYYDiagHandledSignals[i] != sig) continue;
        struct sigaction previous = gDYYYDiagPreviousSignalActions[i];
        if (previous.sa_flags & SA_SIGINFO) {
            if (previous.sa_sigaction) previous.sa_sigaction(sig, info, context);
        } else if (previous.sa_handler != SIG_DFL && previous.sa_handler != SIG_IGN) {
            previous.sa_handler(sig);
        }
        break;
    }
    signal(sig, SIG_DFL);
    raise(sig);
}

static void DYYYDiagInstallSignalHandlers(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      for (NSUInteger i = 0; i < sizeof(gDYYYDiagHandledSignals) / sizeof(int); i++) {
          int sig = gDYYYDiagHandledSignals[i];
          struct sigaction action;
          memset(&action, 0, sizeof(action));
          action.sa_sigaction = DYYYDiagSignalHandler;
          action.sa_flags = SA_SIGINFO | SA_ONSTACK;
          sigemptyset(&action.sa_mask);
          sigaction(sig, &action, &gDYYYDiagPreviousSignalActions[i]);
      }
    });
}

static void DYYYDiagUncaughtExceptionHandler(NSException *exception) {
    @try {
        NSMutableArray<NSString *> *lines = [NSMutableArray array];
        [lines addObject:[NSString stringWithFormat:@"[DYYY][CRASH] 未捕获异常: %@ | %@",
                          exception.name, exception.reason ?: @"(无 reason)"]];
        for (NSString *s in exception.callStackSymbols) {
            [lines addObject:[@"   " stringByAppendingString:s]];
        }
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
      // 异常 handler 只挡得住 ObjC 异常。真正把进程打死的多半是信号：
      // abort()（如 NSJSONSerialization 内部 C++ 抛错）、段错误、总线错误，
      // 这些不走 NSException，必须单独装信号处理才能留下现场。
      DYYYDiagInstallSignalHandlers();
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
    // 不用 class_getName：类还没被具名时它会先做 installMangledNameForLazilyNamedClass，
    // 那一步进 libswiftCore 的 demangler，畸形泛型 mangled 名直接 failAssert → abort。
    // 直播间里大量 _TtC 泛型 CALayer 属于这类，导出必崩。
    const char *raw = DYYYDiagRawClassName(cls);
    if (!raw) return @"(lazy-swift-class)";
    return [NSString stringWithUTF8String:raw];
}

// class_t 布局：isa(0) / superclass(8) / cache(16–31) / bits(32)。
// class_ro_t 布局：flags/instanceStart/instanceSize/reserved(0–15) / name(24)。
//
// 判断一段内存是不是合法类名。
// 只读 64 字节上限，避免越过页边界；任何一条不满足就判否，
// 宁可返回 NULL 让调用方给占位符，也不能把结构体字节当字符串吐出去。
static BOOL DYYYDiagLooksLikeClassName(const char *s) {
    if (!s) return NO;
    uintptr_t v = (uintptr_t)s;
    if (v < 0x1000 || (v >> 40) != 0) return NO;   // 必须在用户态低地址
    size_t len = strnlen(s, 64);
    if (len == 0 || len >= 64) return NO;
    char c0 = s[0];
    if (!((c0 >= 'A' && c0 <= 'Z') || (c0 >= 'a' && c0 <= 'z') || c0 == '_')) return NO;
    for (size_t i = 0; i < len; i++) {
        unsigned char c = (unsigned char)s[i];
        if (c <= 0x20 || c > 0x7e) return NO;      // 不含空格/控制字符/非 ASCII
    }
    return YES;
}

// 读类的 name，全程纯内存读，绝不调用 class_getName / NSStringFromClass。
//
// 那个 API 对尚未具名的 Swift 类会先做 installMangledNameForLazilyNamedClass，
// 进 libswiftCore demangler，畸形 mangled 名 failAssert 后 abort —— 这是导出必崩的根因。
//
// bits 掩码后指向的可能是三种形态之一，必须逐层试：
//   ① class_ro_t        : name 在 +24                       （未 realize 的类）
//   ② class_rw_t + ro   : ro_or_rw_ext 在 +8，低位 bit0=0 → 直接是 ro
//   ③ class_rw_t + ext  : ro_or_rw_ext 在 +8，低位 bit0=1 → 指向 class_rw_ext_t，
//                         它的 +0 才是 ro
// 只做①②会漏掉大量已扩展过的类（分类、KVO、动态方法都会走③），
// 表现为大面积读到 NULL 或读到 baseProperties 指针当名字。
const char *DYYYDiagRawClassName(Class cls) {
    if (!cls) return NULL;
    uintptr_t bits = *(uintptr_t *)((uint8_t *)(__bridge void *)cls + 32);
    uintptr_t data = bits & (uintptr_t)0x00007ffffffffff8ULL;
    if (!data) return NULL;

    // ① 直接当 ro
    const char *name = *(const char **)((uint8_t *)data + 24);
    if (DYYYDiagLooksLikeClassName(name)) return name;

    // ②③ data 是 rw：先取 ro_or_rw_ext
    uintptr_t roOrExt = *(uintptr_t *)((uint8_t *)data + 8);
    if (!roOrExt) return NULL;
    uintptr_t ro = roOrExt & (uintptr_t)0x00007ffffffffff8ULL;
    if (!ro) return NULL;

    if (roOrExt & 1) {
        // ③ 指向 class_rw_ext_t，它的首字段才是 ro
        uintptr_t inner = *(uintptr_t *)((uint8_t *)ro + 0);
        if (!inner) return NULL;
        ro = inner & (uintptr_t)0x00007ffffffffff8ULL;
        if (!ro) return NULL;
    }

    // ②/③ 统一从 ro 的 +24 取 name
    name = *(const char **)((uint8_t *)ro + 24);
    if (DYYYDiagLooksLikeClassName(name)) return name;
    return NULL;
}

// 直读父类槽位，不调用 class_getSuperclass。
// class_getSuperclass 内部先 cls->realizeMaybe()：惰性 Swift 类一旦被 realize，
// 同样走 installMangledNameForLazilyNamedClass → demangler → abort。
// 只拆"读名字"不拆"读父类"，上溯时仍会踩到同一个坑——两处必须一起改。
// 未 realize 的类，superclass 在链接期已填好，纯读即可。
Class DYYYDiagSuperClass(Class cls) {
    if (!cls) return Nil;
    // ARC 不允许 uint8_t* 直接转 Class*，先用 void* 读槽位再 bridge。
    void *raw = *(void **)((uint8_t *)(__bridge void *)cls + 8);
    return (__bridge Class)raw;
}

void DYYYDiagStep(NSString *text) {
    [DYYYDiagnostics appendRuntimeLogLine:[@"[DYYY][diag-step] " stringByAppendingString:text]];
    [DYYYDiagnostics flushRuntimeLogToFile];
}

#pragma mark - 分步排查开关

NSString *const DYYYDiagToggleTree = @"DYYYDiagToggleTree";
NSString *const DYYYDiagToggleVC = @"DYYYDiagToggleVC";
NSString *const DYYYDiagToggleClasses = @"DYYYDiagToggleClasses";
NSString *const DYYYDiagToggleShot = @"DYYYDiagToggleShot";
NSString *const DYYYDiagToggleShare = @"DYYYDiagToggleShare";

BOOL DYYYDiagToggleEnabled(NSString *key) {
    if (key.length == 0) return YES;
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    // 没写过就当开：默认行为与加开关前完全一致，不改就等于没改。
    if ([defaults objectForKey:key] == nil) return YES;
    return [defaults boolForKey:key];
}

void DYYYDiagToggleSet(NSString *key, BOOL enabled) {
    if (key.length == 0) return;
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:key];
}

#pragma mark - 浮窗与卡片透明度

NSString *const DYYYDiagWrenchOpacityKey = @"DYYYWrenchOpacity";
NSString *const DYYYDiagCardOpacityKey = @"DYYYWrenchCardOpacity";

// 浮窗下限 0.20：再低按钮几乎看不见，用户会找不到入口，只能重启改设置。
static const CGFloat kDYYYDiagWrenchOpacityDefault = 0.70;
static const CGFloat kDYYYDiagWrenchOpacityMin = 0.20;

// 卡片是临时出现的面板，调到 0 也没有"找不到入口"的风险。
static const CGFloat kDYYYDiagCardOpacityDefault = 0.85;
static const CGFloat kDYYYDiagCardOpacityMin = 0.0;

static CGFloat DYYYDiagClampOpacity(NSString *key, CGFloat fallback, CGFloat lo, CGFloat hi) {
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults objectForKey:key] == nil) return fallback;
    CGFloat v = [defaults doubleForKey:key];
    if (v < lo) v = lo;
    if (v > hi) v = hi;
    return v;
}

CGFloat DYYYDiagWrenchOpacity(void) {
    return DYYYDiagClampOpacity(DYYYDiagWrenchOpacityKey,
                                kDYYYDiagWrenchOpacityDefault,
                                kDYYYDiagWrenchOpacityMin, 1.0);
}

void DYYYDiagSetWrenchOpacity(CGFloat alpha) {
    if (alpha < kDYYYDiagWrenchOpacityMin) alpha = kDYYYDiagWrenchOpacityMin;
    if (alpha > 1.0) alpha = 1.0;
    [NSUserDefaults.standardUserDefaults setDouble:alpha forKey:DYYYDiagWrenchOpacityKey];
}

CGFloat DYYYDiagCardOpacity(void) {
    return DYYYDiagClampOpacity(DYYYDiagCardOpacityKey,
                                kDYYYDiagCardOpacityDefault,
                                kDYYYDiagCardOpacityMin, 1.0);
}

void DYYYDiagSetCardOpacity(CGFloat alpha) {
    if (alpha < kDYYYDiagCardOpacityMin) alpha = kDYYYDiagCardOpacityMin;
    if (alpha > 1.0) alpha = 1.0;
    [NSUserDefaults.standardUserDefaults setDouble:alpha forKey:DYYYDiagCardOpacityKey];
}

NSString *DYYYNameOfObject(id object) {
    if (!object) return @"";
    // 不能用 [object class]：对某些 Swift 泛型类实例，-class 会走进
    // objc_class::demangledName → libswiftCore 的 copyGenericClassObjCName，
    // 畸形 mangled 名会 failAssert → abort。真机实测在直播间/推荐页导出必崩。
    // object_getClass 只读 isa，不触发 demangle。
    return DYYYNameOfClass(object_getClass(object));
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
