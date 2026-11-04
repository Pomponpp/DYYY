// DYYYDiagnostics — 运行日志导出 + 可读自检报告面板（类声明见 AwemeHeaders.h）
// 日志文件位于 NSTemporaryDirectory()/DYYYLogs/runtime.log（系统会清理临时目录），
// 因此导出时拷贝到 Documents/DYYY/logs 持久保存，再经 UIActivityViewController
// 用"存储到文件"落到"文件"App，或 AirDrop/复制到其他设备。
#import "AwemeHeaders.h"
#import "DYYYClassRegistry.h"
#import <UIKit/UIKit.h>

static NSString *const kDYYYRuntimeLogSubdir = @"DYYYLogs";
static NSString *const kDYYYRuntimeLogName = @"runtime.log";
static const unsigned long long kDYYYRuntimeLogMaxBytes = 4 * 1024 * 1024; // 4MB 轮转
static const NSUInteger kDYYYRuntimeLogMaxBackups = 2;

@implementation DYYYDiagnostics

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
      logQueue = dispatch_queue_create("com.dyyy.runtime-log.queue", DISPATCH_QUEUE_SERIAL);
    });

    dispatch_async(logQueue, ^{
      @autoreleasepool {
          NSData *lineData = [line dataUsingEncoding:NSUTF8StringEncoding];
          if (lineData.length == 0) {
              return;
          }

          NSString *logPath = [self runtimeLogPath];
          NSFileManager *fileManager = [NSFileManager defaultManager];
          [self rotateRuntimeLogIfNeeded];
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
          } @catch (NSException *exception) {
          }
          [fileHandle closeFile];
      }
    });
}

+ (void)rotateRuntimeLogIfNeeded {
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

+ (NSString *)exportedLogPathWithName:(NSString *)name {
    NSString *documents = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSString *dir = [[documents stringByAppendingPathComponent:@"DYYY"] stringByAppendingPathComponent:@"logs"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:name];
}

+ (void)exportRuntimeLogFromViewController:(UIViewController *)presenter {
    if (!presenter) {
        return;
    }

    [self rotateRuntimeLogIfNeeded];

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
                                                      [presenter presentViewController:share animated:YES completion:nil];
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
