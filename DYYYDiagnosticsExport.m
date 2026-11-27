//
//  DYYYDiagnosticsExport.m
//  DYYY 诊断系统 · 诊断包打包
//
//  把主线程采集完成的快照序列化并打包 zip。
//  音频专项模式随旧音频探针移除（外部 0 调用的死功能）。
//

#import "DYYYDiagnosticsExport.h"
#import "DYYYDiagnosticsCapture.h"
#import "DYYYDiagnosticsCompat.h"
#import "DYYYDiagnosticsCore.h"
#import "DYYYClassRegistry.h"
#import "DYYYToast.h"
#import <CoreGraphics/CoreGraphics.h>

NSString * const DYYYDiagExportWorkingDirectoryKey = @"DYYYDiagExportWorkingDirectory";
static NSString *const DYYYDiagExportErrorDomain = @"com.dyyy.diagnostics-export";
static const NSUInteger kDYYYDiagMaxExportFiles = 8000;

// 构建标识（CI 生成 DYYYBuildStamp.h；本地无则 dev）
#if __has_include("DYYYBuildStamp.h")
#import "DYYYBuildStamp.h"
#define DYYYDiagStr(x) DYYYDiagStr2(x)
#define DYYYDiagStr2(x) @"" x
#define DYYYDiagVersion_STR DYYY_BUILD_VERSION
#define DYYYDiagBuildCommit_STR DYYY_BUILD_COMMIT
#define DYYYDiagBuildBranch_STR DYYY_BUILD_BRANCH
#define DYYYDiagBuildTime_STR DYYY_BUILD_TIME
#else
#define DYYYDiagVersion_STR "2.2-9"
#define DYYYDiagBuildCommit_STR "dev"
#define DYYYDiagBuildBranch_STR "local"
#define DYYYDiagBuildTime_STR "dev"
#endif


NSString * const DYYYDiagVersion = DYYYDiagStr(DYYYDiagVersion_STR);
NSString * const DYYYDiagBuildCommit = DYYYDiagStr(DYYYDiagBuildCommit_STR);
NSString * const DYYYDiagBuildBranch = DYYYDiagStr(DYYYDiagBuildBranch_STR);
NSString * const DYYYDiagBuildTime = DYYYDiagStr(DYYYDiagBuildTime_STR);

#pragma mark - 写入汇集器

@interface DYYYDiagExportSink : NSObject
@property (nonatomic, copy) NSString *rootDir;
@property (nonatomic, strong) NSMutableArray<NSString *> *files;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *errors;
@property (nonatomic, assign) BOOL criticalFailed;
@property (nonatomic, assign) NSUInteger droppedFiles;
- (instancetype)initWithRootDir:(NSString *)rootDir;
@end

@implementation DYYYDiagExportSink
- (instancetype)initWithRootDir:(NSString *)rootDir {
    if ((self = [super init])) {
        _rootDir = [rootDir copy];
        _files = [NSMutableArray array];
        _errors = [NSMutableArray array];
    }
    return self;
}
@end

#pragma mark - 文件工具

static NSError *DYYYDiagMakeExportError(NSInteger code, NSString *message, NSError *underlying) {
    NSMutableDictionary *info = [NSMutableDictionary dictionaryWithObject:message
                                                                   forKey:NSLocalizedDescriptionKey];
    if (underlying) info[NSUnderlyingErrorKey] = underlying;
    return [NSError errorWithDomain:DYYYDiagExportErrorDomain code:code userInfo:info];
}

static NSString *DYYYDiagSafeFileName(NSString *name) {
    NSCharacterSet *bad = [NSCharacterSet characterSetWithCharactersInString:@"/\\:?%*|\"<>"];
    return [[name componentsSeparatedByCharactersInSet:bad] componentsJoinedByString:@"_"];
}

static NSString *DYYYDiagUniqueFileStem(NSString *name) {
    NSString *stem = [name stringByReplacingOccurrencesOfString:@"." withString:@"_"];
    return stem.length ? stem : @"unnamed";
}

static void DYYYDiagRecordError(DYYYDiagExportSink *sink,
                                NSString *item,
                                NSString *kind,
                                NSError *error,
                                BOOL critical) {
    [sink.errors addObject:@{
        @"item": item ?: @"",
        @"kind": kind ?: @"",
        @"critical": @(critical),
        @"error": error.localizedDescription ?: @""
    }];
    if (critical) sink.criticalFailed = YES;
}

static BOOL DYYYDiagWriteData(DYYYDiagExportSink *sink, NSString *relativePath, NSData *data, BOOL critical) {
    if (sink.files.count >= kDYYYDiagMaxExportFiles) {
        sink.droppedFiles++;
        return NO;
    }
    NSString *path = [sink.rootDir stringByAppendingPathComponent:relativePath];
    NSString *dir = [path stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    BOOL ok = data && [[NSFileManager defaultManager] createFileAtPath:path contents:data attributes:nil];
    if (ok) [sink.files addObject:path];
    if (!ok && critical) sink.criticalFailed = YES;
    return ok;
}

static BOOL DYYYDiagWriteString(DYYYDiagExportSink *sink, NSString *relativePath, NSString *string, BOOL critical) {
    return DYYYDiagWriteData(sink, relativePath, [string dataUsingEncoding:NSUTF8StringEncoding], critical);
}

static BOOL DYYYDiagWriteJSON(DYYYDiagExportSink *sink, NSString *relativePath, id object, BOOL critical) {
    if (!object) return NO;
    // 不加 NSJSONWritingPrettyPrinted：诊断包是给机器读的，格式化只会让体积翻倍、
    // 序列化变慢。真要看内容，json.tool 之类的工具随时能格式化。
    // 外层 @try 只能挡住 ObjC 层异常；NaN/Inf 那种在 NSJSONSerialization 内部
    // 是 C++ 抛出的，会直接 terminate —— 所以入口侧必须先用有限值保护过滤干净。
    NSData *data = nil;
    @try {
        data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    } @catch (NSException *exception) {
        DYYYDiagRecordError(sink, relativePath, @"json-serialize",
                            DYYYDiagMakeExportError(21, exception.reason ?: @"JSON 序列化异常", nil),
                            critical);
    }
    if (!data) {
        // 序列化失败不静默留空：写一份占位说明，保证包结构与后续消费方能解析。
        if (critical) sink.criticalFailed = YES;
        NSString *placeholder = @"{\"error\":\"serialize_failed\"}";
        DYYYDiagWriteData(sink, relativePath,
                          [placeholder dataUsingEncoding:NSUTF8StringEncoding], NO);
        return NO;
    }
    return DYYYDiagWriteData(sink, relativePath, data, critical);
}

#pragma mark - README

static NSString *DYYYDiagReadme(DYYYDiagnosticsContext *context) {
    NSMutableString *text = [NSMutableString string];
    [text appendString:@"DYYY 诊断包\n"];
    [text appendFormat:@"Generated: %@\n", context.metadata[@"generatedAt"] ?: @""];
    [text appendFormat:@"DYYY: %@ (build %@)\n", DYYYDiagVersion, DYYYDiagBuildCommit];
    [text appendFormat:@"Bundle: %@\n", context.metadata[@"bundleIdentifier"] ?: @""];
    [text appendFormat:@"App: %@ %@ (%@)\n",
     context.metadata[@"bundleName"] ?: @"", context.metadata[@"appVersion"] ?: @"",
     context.metadata[@"buildVersion"] ?: @""];
    [text appendFormat:@"System: %@ %@\n", context.metadata[@"systemName"] ?: @"",
     context.metadata[@"systemVersion"] ?: @""];
    [text appendString:@"\nContents:\n- page/: UI 主线程快照与本页类\n- compat/: 适配三件套\n- probe/: 运行日志全文\n- ui/: 目标窗口截图\n- crash/: 本 App 最近崩溃报告\n"];
    return text;
}

#pragma mark - 页面内容

static void DYYYDiagWritePageClasses(DYYYDiagExportSink *sink, NSArray<NSString *> *classNames) {
    // 不排序：类名里混着 Swift 泛型 mangled 名，全量 compare 会反复走字符串路径，
    // 放大 Swift demangler 的触发面。遍历顺序对诊断没有影响。
    for (NSString *name in classNames) {
        @autoreleasepool {
            @try {
                Class cls = NSClassFromString(name);
                NSString *header = cls ? DYYYDiagClassDumpHeaderForClass(cls) : nil;
                if (!header.length) continue;
                NSString *relative = [@"page/classes" stringByAppendingPathComponent:
                                      [DYYYDiagUniqueFileStem(name) stringByAppendingString:@".h"]];
                DYYYDiagWriteString(sink, relative, header, NO);
            } @catch (NSException *exception) {
                DYYYDiagRecordError(sink, name, @"page-class",
                                    DYYYDiagMakeExportError(20, exception.reason ?: @"类头文件导出异常", nil), NO);
            }
        }
    }
}

static void DYYYDiagWritePageFiles(DYYYDiagExportSink *sink,
                                   DYYYDiagnosticsContext *context,
                                   void (^progress)(NSString *text)) {
    if (progress) progress(@"写入页面结构...");
    DYYYDiagWriteJSON(sink, @"page/windows.json", context.windowsJSON ?: @[], NO);
    DYYYDiagWriteString(sink, @"page/view-tree.txt", context.viewTreeText, NO);
    DYYYDiagWriteJSON(sink, @"page/view-tree.json", context.viewTreeJSON ?: @[], NO);
    DYYYDiagWriteJSON(sink, @"page/selected-view.json", context.selectedViewJSON ?: @{}, NO);
    DYYYDiagWriteString(sink, @"page/view-controllers.txt", context.viewControllersText, NO);
    DYYYDiagWriteJSON(sink, @"page/layers.json", context.layersJSON ?: @[], NO);
    // 只导"选中视图链 + 当前页控制器"相关的类头文件。
    // 之前是整页所有类（实测 139 个文件 1.9MB），绝大多数与当次排查无关。
    // 注意：这里全程用 NSSet 做成员判断，不排序、不逐项比较——
    // 页面类清单里混着大量 Swift 泛型 mangled 名，任何一次全量比较都会
    // 反复走字符串路径，把 Swift demangler 的触发面放大。
    if (progress) progress(@"导出本页类头文件...");
    NSMutableArray<NSString *> *focused = [NSMutableArray array];
    NSArray<NSString *> *allNames = context.pageClassNames ?: @[];
    NSString *hitClass = [context.selectedViewJSON[@"hitView"] isKindOfClass:[NSDictionary class]]
                             ? context.selectedViewJSON[@"hitView"][@"class"] : nil;
    NSString *vcClass = [context.selectedViewJSON[@"nearestViewController"] isKindOfClass:[NSDictionary class]]
                            ? context.selectedViewJSON[@"nearestViewController"][@"class"] : nil;
    for (NSString *name in allNames) {
        if ([name isEqualToString:hitClass] || [name isEqualToString:vcClass]) [focused addObject:name];
        if (focused.count >= 20) break;
    }
    // 选中链上的类一个都没匹配到时，退回导出前 20 个（保持原始顺序，不排序），保证至少有东西可看。
    if (focused.count == 0) {
        NSUInteger limit = MIN(allNames.count, (NSUInteger)20);
        if (limit > 0) [focused addObjectsFromArray:[allNames subarrayWithRange:NSMakeRange(0, limit)]];
    }
    DYYYDiagWritePageClasses(sink, focused);
}

#pragma mark - 崩溃报告

// 抖音崩溃时系统会把报告写到 CrashReporter 目录（.ips）。导出时把
// 本 App 最近几条带进包里。只读、只统计、不改动原文件。
static void DYYYDiagWriteCrashFiles(DYYYDiagExportSink *sink, void (^progress)(NSString *text)) {
    if (progress) progress(@"收集崩溃报告...");
    NSString *bundleID = NSBundle.mainBundle.bundleIdentifier ?: @"";
    NSMutableArray<NSString *> *roots = [NSMutableArray array];
    NSString *home = NSHomeDirectory();
    [roots addObject:[home stringByAppendingPathComponent:@"Library/Logs/CrashReporter"]];
    [roots addObject:@"/var/mobile/Library/Logs/CrashReporter"];
    [roots addObject:@"/var/mobile/Library/Logs/CrashReporter/DiagnosticLogs"];

    NSFileManager *fm = NSFileManager.defaultManager;
    NSMutableArray<NSDictionary *> *found = [NSMutableArray array];
    NSDateFormatter *df = [[NSDateFormatter alloc] init];
    df.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    df.dateFormat = @"yyyyMMdd-HHmmss";

    for (NSString *root in roots) {
        NSArray<NSString *> *names = [fm contentsOfDirectoryAtPath:root error:nil];
        if (!names.count) continue;
        for (NSString *name in names) {
            BOOL looksLikeOurs = [name containsString:@"Aweme"] || (bundleID.length && [name containsString:bundleID]);
            BOOL isReport = [name.pathExtension isEqualToString:@"ips"] || [name.pathExtension isEqualToString:@"crash"];
            if (!looksLikeOurs || !isReport) continue;
            NSString *full = [root stringByAppendingPathComponent:name];
            NSDictionary *attrs = [fm attributesOfItemAtPath:full error:nil];
            NSDate *mtime = attrs[NSFileModificationDate];
            [found addObject:@{@"path": full, @"name": name, @"mtime": mtime ?: NSDate.date}];
        }
    }
    [found sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
      return [b[@"mtime"] compare:a[@"mtime"]];
    }];

    if (!found.count) {
        DYYYDiagWriteString(sink, @"crash/none.txt", @"未找到本 App 的崩溃报告。\r\n"
                            "若确认发生过闪退，可从「设置 → 隐私与安全性 → 分析与改进 → 分析数据」\r\n"
                            "搜索 Aweme 查找对应 .ips。\r\n", NO);
        return;
    }
    NSUInteger limit = MIN(found.count, (NSUInteger)5);
    NSMutableString *index = [NSMutableString string];
    [index appendFormat:@"共找到 %lu 条崩溃报告，本包携带最近 %lu 条：\r\n\r\n",
                        (unsigned long)found.count, (unsigned long)limit];
    for (NSUInteger i = 0; i < limit; i++) {
        NSDictionary *item = found[i];
        NSData *data = [NSData dataWithContentsOfFile:item[@"path"]];
        if (!data) continue;
        NSString *stamp = [df stringFromDate:item[@"mtime"]];
        NSString *target = [NSString stringWithFormat:@"crash/%@-%@", stamp, item[@"name"]];
        DYYYDiagWriteData(sink, target, data, NO);
        [index appendFormat:@"· %@  →  %@\r\n", stamp, target];
    }
    DYYYDiagWriteString(sink, @"crash/index.txt", index, NO);
}

#pragma mark - 导出入口

DYYYDiagnosticsExportResult *DYYYDiagCreateExport(DYYYDiagnosticsContext *context,
                                                  void (^progress)(NSString *text),
                                                  NSError **error) {
    if (!context) {
        if (error) *error = DYYYDiagMakeExportError(1, @"导出上下文不完整", nil);
        return nil;
    }

    static NSDateFormatter *sStampFormatter;
    static dispatch_once_t stampOnce;
    dispatch_once(&stampOnce, ^{
      sStampFormatter = [[NSDateFormatter alloc] init];
      sStampFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
      sStampFormatter.dateFormat = @"yyyyMMdd-HHmmss";
    });
    NSString *stamp = [sStampFormatter stringFromDate:NSDate.date] ?: @"unknown";
    NSString *rootName = [NSString stringWithFormat:@"DYDebug-%@", stamp];
    NSString *temporary = NSTemporaryDirectory();
    NSString *rootDir = [temporary stringByAppendingPathComponent:rootName];
    NSString *zipPath = [temporary stringByAppendingPathComponent:[rootName stringByAppendingString:@".zip"]];
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm removeItemAtPath:rootDir error:nil];
    [fm removeItemAtPath:zipPath error:nil];

    NSError *directoryError = nil;
    if (![fm createDirectoryAtPath:rootDir withIntermediateDirectories:YES attributes:nil error:&directoryError]) {
        if (error) *error = DYYYDiagMakeExportError(2, @"无法创建导出目录", directoryError);
        return nil;
    }

    DYYYDiagExportSink *sink = [[DYYYDiagExportSink alloc] initWithRootDir:rootDir];
    DYYYDiagStep(@"export: sink 就绪");
    DYYYDiagWriteString(sink, @"README.txt", DYYYDiagReadme(context), NO);
    DYYYDiagStep(@"export: README 完成");
    DYYYDiagWriteData(sink, @"ui/screenshot.png", context.screenshotPNG, NO);
    DYYYDiagStep(@"export: 截图 完成");
    DYYYDiagWritePageFiles(sink, context, progress);
    DYYYDiagStep([NSString stringWithFormat:@"export: 页面文件 完成 files=%lu", (unsigned long)sink.files.count]);

    @try {
        DYYYDiagWriteCrashFiles(sink, progress);
    } @catch (NSException *exception) {
        DYYYDiagRecordError(sink, @"crash", @"crash-collect",
                            DYYYDiagMakeExportError(30, exception.reason ?: @"崩溃报告收集异常", nil), NO);
    }
    DYYYDiagStep(@"export: 崩溃报告 完成");

    // 运行日志全文：Core 先 flush（缓冲 → runtime.log），这里读文件。
    if (progress) progress(@"写入运行日志全文...");
    [[DYYYDiagnostics class] flushRuntimeLogToFile];
    NSString *runtime = [NSString stringWithContentsOfFile:[DYYYDiagnostics runtimeLogPath]
                                                  encoding:NSUTF8StringEncoding error:nil];
    if (runtime.length) {
        DYYYDiagWriteString(sink, @"probe/runtime.log", runtime, NO);
    }
    DYYYDiagStep(@"export: 运行日志 完成");

    // 适配三件套：类自检 / 运行时类清单 / 目标类方法清单。
    if (progress) progress(@"写入适配诊断...");
    DYYYDiagStep(@"export: compat 开始");
    @try {
        DYYYDiagWriteString(sink, @"compat/audit.txt", [DYYYClassRegistry auditReportText], NO);
        DYYYDiagStep(@"export: audit.txt 完成");
        DYYYDiagWriteString(sink, @"compat/hook-health.txt", [DYYYClassRegistry hookHealthText], NO);
        DYYYDiagStep(@"export: hook-health.txt 完成");
        DYYYDiagWriteString(sink, @"compat/class-list.txt", [DYYYClassRegistry runtimeClassListText], NO);
        DYYYDiagStep(@"export: class-list.txt 完成");
        DYYYDiagWriteString(sink, @"compat/target-methods.txt", [DYYYClassRegistry targetMethodsText], NO);
        DYYYDiagStep(@"export: target-methods.txt 完成");
    } @catch (NSException *exception) {
        DYYYDiagRecordError(sink, @"compat", @"compat-collect",
                            DYYYDiagMakeExportError(31, exception.reason ?: @"适配诊断采集异常", nil), NO);
    }

    NSDictionary *manifest = @{
        @"schemaVersion": @"dyyy.debug.v2",
        @"mode": @"page",
        @"dyyyVersion": DYYYDiagVersion,
        @"device": context.metadata ?: @{},
        @"integrity": @{
            @"complete": @(!sink.criticalFailed && sink.droppedFiles == 0),
            @"status": sink.criticalFailed ? @"critical-failure"
                     : (sink.droppedFiles ? @"truncated"
                     : (sink.errors.count ? @"complete-with-recoverable-errors" : @"complete")),
            @"fileCount": @(sink.files.count),
            @"fileLimit": @(kDYYYDiagMaxExportFiles),
            @"truncated": @(sink.droppedFiles > 0),
            @"droppedFiles": @(sink.droppedFiles),
            @"errorCount": @(sink.errors.count),
            @"errors": sink.errors,
        },
    };
    DYYYDiagWriteJSON(sink, @"manifest.json", manifest, NO);

    if (sink.criticalFailed) {
        if (error) {
            *error = [NSError errorWithDomain:DYYYDiagExportErrorDomain code:3 userInfo:@{
                NSLocalizedDescriptionKey: @"关键文件写入失败，工作目录已保留",
                DYYYDiagExportWorkingDirectoryKey: rootDir,
            }];
        }
        return nil;
    }

    if (progress) progress(@"压缩 zip...");
    NSError *zipError = nil;
    BOOL zipped = sink.files.count > 0 && [DYYYDiagZipWriter createZipAtPath:zipPath
                                                                     rootDir:rootDir
                                                                       files:sink.files
                                                                    progress:nil
                                                                       error:&zipError];
    NSDictionary *attributes = zipped ? [fm attributesOfItemAtPath:zipPath error:nil] : nil;
    NSNumber *zipSize = attributes[NSFileSize];
    if (!zipped || zipError || zipSize.unsignedLongLongValue <= 22) {
        [fm removeItemAtPath:zipPath error:nil];
        NSMutableDictionary *info = [NSMutableDictionary dictionaryWithDictionary:@{
            NSLocalizedDescriptionKey: zipError.localizedDescription ?: @"ZIP 未生成或内容为空",
            DYYYDiagExportWorkingDirectoryKey: rootDir,
        }];
        if (zipError) info[NSUnderlyingErrorKey] = zipError;
        if (error) *error = [NSError errorWithDomain:DYYYDiagExportErrorDomain code:4 userInfo:info];
        return nil;
    }

    DYYYDiagnosticsExportResult *result = [DYYYDiagnosticsExportResult new];
    result.zipURL = [NSURL fileURLWithPath:zipPath];
    result.workingDirectoryURL = [NSURL fileURLWithPath:rootDir isDirectory:YES];
    return result;
}

void DYYYDiagCleanupExport(DYYYDiagnosticsExportResult *result) {
    if (!result) return;
    NSFileManager *fm = NSFileManager.defaultManager;
    if (result.workingDirectoryURL.isFileURL) [fm removeItemAtURL:result.workingDirectoryURL error:nil];
    if (result.zipURL.isFileURL) [fm removeItemAtURL:result.zipURL error:nil];
}

// 供 DYYYDiagnosticsCore 的门面方法调用的 C 入口。
// 旧设置页入口：视图树+环境+compat 三件套+zip，落盘到 Documents/DYYY/logs。
void DYYYDiagnosticsExportBundle(UIViewController *presenter) {
    static BOOL busy = NO;
    if (busy) return;
    busy = YES;

    [DYYYDiagnostics appendRuntimeLogLine:@"—— 导出时刻开关状态 ——"];
    [DYYYDiagnostics appendRuntimeLogLine:[NSString stringWithFormat:
        @"[DYYY][fullscreen] 导出状态：全屏=%d 毛玻璃=%d",
        DYYYPrefBool(@"DYYYEnableFullScreen") ? 1 : 0,
        DYYYPrefBool(@"DYYYEnableCommentBlur") ? 1 : 0]];

    UIWindow *target = DYYYDiagTargetWindow();
    DYYYDiagnosticsContext *context = DYYYDiagCaptureContext(target, CGPointZero, nil);

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        DYYYDiagnosticsExportResult *result = DYYYDiagCreateExport(context, nil, &error);
        dispatch_async(dispatch_get_main_queue(), ^{
            busy = NO;
            if (!result) {
                [DYYYToast showSuccessToastWithMessage:@"诊断包导出失败"];
                return;
            }
            // zip 拷贝到 Documents/DYYY/logs 持久保存（文件 App 可取）。
            NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
            fmt.dateFormat = @"yyyyMMdd-HHmmss";
            NSString *dir = [[DYYYDiagnostics exportedLogPathWithName:@""] stringByAppendingPathComponent:
                [NSString stringWithFormat:@"DYYY-diag-%@", [fmt stringFromDate:[NSDate date]]]];
            [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                      withIntermediateDirectories:YES
                                                       attributes:nil error:nil];
            NSString *zipDir = result.workingDirectoryURL.path;
            NSFileManager *fm = [NSFileManager defaultManager];
            for (NSString *f in [fm contentsOfDirectoryAtPath:zipDir error:nil]) {
                NSString *from = [zipDir stringByAppendingPathComponent:f];
                NSString *to = [dir stringByAppendingPathComponent:f];
                BOOL isDir = NO;
                [fm fileExistsAtPath:from isDirectory:&isDir];
                if ([fm fileExistsAtPath:from] && !isDir) {
                    [fm copyItemAtPath:from toPath:to error:nil];
                }
            }
            DYYYDiagCleanupExport(result);
            [DYYYToast showSuccessToastWithMessage:
                [NSString stringWithFormat:@"诊断包已生成\n文件App → DYYY/logs/%@", [dir lastPathComponent]]];
        });
    });
}