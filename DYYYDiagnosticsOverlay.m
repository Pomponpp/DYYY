//
//  DYYYDiagnosticsOverlay.m
//  DYYY 诊断子系统 —— 浮窗入口
//
//  全局扳手：独立高层级 window 承载调试按钮，点选页面元素后复用
//  导出走 DYYYDiagnosticsExport（Capture + Export）。
//
//  采集骨架与类结构 dump：与同类实现做过行为对照，
//  结论写在 CREDITS.md。DYYY 接入了自有运行流水、状态指纹、compat 三件套
//  （audit / class-list / target-methods），并把浮窗与日志统一为「诊断模式」。
//

#import "DYYYDiagnosticsOverlay.h"
#import "DYYYDiagnosticsCore.h"
#import "DYYYDiagnosticsCapture.h"
#import "DYYYDiagnosticsExport.h"






@interface DYYYDiagOverlayView : UIView
@end

@implementation DYYYDiagOverlayView

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return (hit == self) ? nil : hit;
}

@end

@interface DYYYDiagOverlayWindow : UIWindow
@end

@interface DYYYDiagOverlayViewController : UIViewController
@property (nonatomic, strong) UIButton *wrenchButton;
@property (nonatomic, assign) BOOL didPlaceButton;
// 扳手拖动判定：区分「拖」与「点」，避免拖动结束被当成点击弹面板。
@property (nonatomic, assign) CGPoint wrenchDragStartCenter;
@property (nonatomic, assign) BOOL wrenchDidDrag;
- (void)persistWrenchPosition;
- (BOOL)capturesOverlayTouches;
- (void)exportWholePage;
@end

@implementation DYYYDiagOverlayWindow

// #69 浮窗拖动导致视频暂停的根修：
// 浮层 windowLevel 极高，若它成为 key window，抖音的视频窗口会在拖动期间
// 反复失去 key → 播放器/触摸链中断 → 暂停。
// 浮层只负责显示扳手按钮与面板，从不承载键盘输入，因此不该当 key window。
- (BOOL)canBecomeKeyWindow {
    return NO;
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    DYYYDiagOverlayViewController *controller = [self.rootViewController isKindOfClass:DYYYDiagOverlayViewController.class]
                                               ? (DYYYDiagOverlayViewController *)self.rootViewController
                                               : nil;
    if ([controller capturesOverlayTouches]) return [super pointInside:point withEvent:event];
    CGPoint p = [controller.wrenchButton convertPoint:point fromView:self];
    return [controller.wrenchButton pointInside:p withEvent:event];
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    DYYYDiagOverlayViewController *controller = [self.rootViewController isKindOfClass:DYYYDiagOverlayViewController.class]
                                               ? (DYYYDiagOverlayViewController *)self.rootViewController
                                               : nil;
    if ([controller capturesOverlayTouches]) return hit ?: controller.view;
    if (!hit || hit == controller.view || hit == self) return nil;
    return hit;
}

@end

static DYYYDiagOverlayWindow *DYYYDiagWindow;
static DYYYDiagOverlayViewController *DYYYDiagController;
static BOOL DYYYDiagInstalled;
// 导出占用标记 + 起始时刻。
//
// 只用一个 BOOL 是历史遗留的坑：任何一条异常路径没走到复位
// （分享面板被打断、切 App、导出线程被系统回收），这个标记就永久是 YES，
// 之后每次点导出都弹「已有导出正在进行」，只能重启抖音。
// 加时间戳后超时自动放行，任何残留都不会把功能锁死。
static BOOL DYYYDiagExportBusy;
static CFAbsoluteTime DYYYDiagExportBusyAt;
static const CFTimeInterval kDYYYDiagExportBusyTimeout = 90.0;

static BOOL DYYYDiagExportIsBusy(void) {
    if (!DYYYDiagExportBusy) return NO;
    if (CFAbsoluteTimeGetCurrent() - DYYYDiagExportBusyAt < kDYYYDiagExportBusyTimeout) return YES;
    DYYYDiagExportBusy = NO;   // 超时残留，强制放行
    return NO;
}

static void DYYYDiagExportSetBusy(BOOL busy) {
    DYYYDiagExportBusy = busy;
    DYYYDiagExportBusyAt = busy ? CFAbsoluteTimeGetCurrent() : 0;
}

#pragma mark - UI 工具

static BOOL DYYYDiagIsDebugOverlayWindow(UIWindow *window) {
    return [DYYYNameOfObject(window) hasPrefix:@"DYYYDiag"];
}

// 一切模态 UI 的唯一宿主。
//
// 这是「导出后整个界面被蒙住、只能点扳手」和「卡在分享页」的共同根因：
// 浮层 window 的 windowLevel 是 UIWindowLevelAlert + 100000，
// 从浮层控制器 present 出来的 alert / 分享面板都活在这个高位窗口里。
// 于是 share sheet 被自己的宿主窗口压在下面（看不见、点不到），
// alert 又让 capturesOverlayTouches 返回 YES，浮层整屏吞掉触摸。
//
// 规矩：诊断浮层只负责显示扳手，永远不承载任何 present。
// 所有 alert / 分享 / 进度都必须从 App 自己的窗口控制器弹出。
static UIViewController *DYYYDiagUIContextHost(void) {
    UIWindow *target = DYYYDiagTargetWindow();
    UIViewController *root = target.rootViewController;
    // 找不到 App 自己的窗口就放弃，绝不能退回浮层控制器：
    // 从浮层 present 面板会让 capturesOverlayTouches 返回 YES，
    // 浮层整屏吞掉触摸，表现为"界面被灰蒙版盖住、只剩扳手能点"。
    if (!root) return nil;
    if ([root isKindOfClass:DYYYDiagOverlayViewController.class]) return nil;

    UIViewController *top = root;
    for (NSUInteger depth = 0; top && depth < 16; depth++) {
        UIViewController *presented = top.presentedViewController;
        if (!presented || presented.isBeingDismissed) break;
        top = presented;
    }
    // 沿 present 链走到浮层上时回到窗口根控制器；根也不是 App 的就放弃。
    if ([top isKindOfClass:DYYYDiagOverlayViewController.class] || !top) {
        return [root isKindOfClass:DYYYDiagOverlayViewController.class] ? nil : root;
    }
    if (!top.viewIfLoaded.window) return root;
    return top;
}

static void DYYYDiagPresentError(UIViewController *presenter, NSString *message) {
    (void)presenter;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"导出失败"
                                                                       message:message ?: @"未知错误"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
        UIViewController *host = DYYYDiagUIContextHost();
        if (!host || host.presentedViewController) return;
        [host presentViewController:alert animated:YES completion:nil];
    });
}

// 把 underlying 与保留下来的工作目录一并展开：只显示顶层描述的话，
// ZIP 的 -3/-4/-5 三种失败在界面上长得一模一样，等于没有诊断。
static NSString *DYYYDiagExportErrorMessage(NSError *error, NSString *fallback) {
    if (!error) return fallback;
    NSMutableString *message = [NSMutableString stringWithString:error.localizedDescription ?: fallback];
    NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
    if (underlying) {
        [message appendFormat:@"\n\n[%@ %ld] %@", underlying.domain ?: @"",
         (long)underlying.code, underlying.localizedDescription ?: @""];
    }
    NSString *workingDirectory = error.userInfo[DYYYDiagExportWorkingDirectoryKey];
    if (workingDirectory.length) {
        [message appendFormat:@"\n\n工作目录已保留:\n%@", workingDirectory];
    }
    return message;
}

// 导出完成后的收尾。
//
// 之前直接弹 UIActivityViewController（系统分享面板），
// 它会盖一层灰蒙版并且层级高于扳手浮窗，用户没关掉之前扳手完全点不动，
// 看起来就像「导出后整个界面被蒙住、扳手失效」。
//
// 改为先弹一个轻量提示：说明文件已生成，给两个按钮
//   「分享」→ 才弹系统分享面板
//   「完成」→ 只清理临时文件，界面立刻恢复可用
// 默认走「完成」，不再强制进分享流程。
// 找一个属于 App 主窗口的控制器来承载系统面板（分享/键盘依赖的 UI）。
//
// 不能直接用浮层控制器：浮层 window 的 canBecomeKeyWindow 返回 NO，
// 拿不到键盘焦点，UIActivityViewController 会卡死——既分享不出去也关不掉。
// 这里沿窗口层级找第一个非浮层、能 present 的控制器。
// 定义在文件靠后位置，导出收尾时要用，先声明。
static void DYYYDiagRecoverOverlayStateIfNeeded(void);

// 导出收尾统一入口：清理临时文件 + 等面板真正关掉后复位浮层状态。
//
// 为什么不能只靠 App 回到前台时复位：
// 在抖音内部直接「完成」的路径下没有切 App，DidBecomeActive 不会触发，
// 残留的 presentedViewController 会一直让浮层接管触摸，
// 表现为「导出完返回，界面点不动，只剩扳手能点」。
static void DYYYDiagFinalizeExportAndRecover(DYYYDiagnosticsExportResult *result) {
    DYYYDiagCleanupExport(result);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                     DYYYDiagRecoverOverlayStateIfNeeded();
                     DYYYDiagnosticsOverlayRefresh();
                   });
}

static void DYYYDiagFinishExport(DYYYDiagnosticsExportResult *result, UIViewController *presenter, UIView *sourceView) {
    (void)presenter;
    (void)sourceView;
    if (!result || !result.zipURL) {
        DYYYDiagCleanupExport(result);
        DYYYDiagPresentError(nil, @"ZIP 文件不存在");
        return;
    }

    // 导出完成直接进系统分享面板，中间不再插一层「导出完成」提示框。
    //
    // 原因：每一次 modal 切换都会让 App 的 active / key 状态抖一次，
    // 播放器监听这些事件后暂停。原来这条链路要连抖三次
    // （进度框 → 导出完成框 → 分享面板），导出完视频就停在暂停态，
    // 得手动暂停+播放触发一次 seek 才恢复。
    // 砍掉中间那层后只剩两次切换，与行为对照版本的链路一致。
    UIViewController *host = DYYYDiagUIContextHost();
    if (!host) {
        DYYYDiagCleanupExport(result);
        return;
    }

    UIActivityViewController *activity =
        [[UIActivityViewController alloc] initWithActivityItems:@[ result.zipURL ] applicationActivities:nil];
    if (activity.popoverPresentationController) {
        activity.popoverPresentationController.sourceView = host.view;
        activity.popoverPresentationController.sourceRect = host.view.bounds;
    }
    __block BOOL recovered = NO;
    void (^recoverOnce)(void) = ^{
      if (recovered) return;
      recovered = YES;
      DYYYDiagFinalizeExportAndRecover(result);
    };
    activity.completionWithItemsHandler =
        ^(__unused UIActivityType type, __unused BOOL completed,
          __unused NSArray *items, __unused NSError *error) {
          recoverOnce();
        };
    [host presentViewController:activity animated:YES completion:nil];
    // 兜底：completionWithItemsHandler 在「交给别的 App」路径上常常不回调
    // （微信/输入法中转），不兜底就会一直卡在分享页。
    // 这里只复位界面状态，不删 zip —— 用户可能还在别的 App 里读这个文件。
    // 真正的清理留给 completionWithItemsHandler。
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                     if (activity.presentingViewController == nil || activity.view.window == nil) {
                         DYYYDiagRecoverOverlayStateIfNeeded();
                         DYYYDiagnosticsOverlayRefresh();
                     }
                   });
}

static void DYYYDiagSetProgress(UIAlertController *alert, NSString *text) {
    dispatch_async(dispatch_get_main_queue(), ^{
        alert.message = text ?: @"处理中...";
    });
}

static void DYYYDiagCreateExportInBackground(DYYYDiagnosticsContext *context,
                                             UIAlertController *progressAlert) {
    if (!DYYYDiagUIContextHost()) {
        DYYYDiagExportSetBusy(NO);
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *exportError = nil;
        DYYYDiagnosticsExportResult *result = DYYYDiagCreateExport(context, ^(NSString *text) {
            DYYYDiagSetProgress(progressAlert, text);
        }, &exportError);
        dispatch_async(dispatch_get_main_queue(), ^{
            DYYYDiagExportSetBusy(NO);
            [progressAlert dismissViewControllerAnimated:YES completion:^{
                if (result) {
                    DYYYDiagFinishExport(result, nil, nil);
                } else {
                    DYYYDiagPresentError(nil, DYYYDiagExportErrorMessage(exportError, @"没有生成 ZIP 文件"));
                }
            }];
        });
    });
}

// 当前页面标识：顶层 VC 类名 + referString + 选中 tab。
// 定位问题时先知道在哪，比从截图猜快。
static NSString *DYYYDiagPageIdentity(void) {
    NSMutableString *out = [NSMutableString string];
    UIWindow *window = DYYYDiagTargetWindow();
    UIViewController *root = window.rootViewController;
    if (!root) {
        [out appendString:@"(无窗口或无根控制器)"];
        return out;
    }
    UIViewController *top = root;
    if ([top isKindOfClass:[UITabBarController class]]) {
        UIViewController *sel = ((UITabBarController *)top).selectedViewController;
        [out appendFormat:@"tab=%@\r\n", DYYYNameOfObject(sel)];
        if (sel) top = sel;
    }
    if ([top isKindOfClass:[UINavigationController class]]) {
        top = ((UINavigationController *)top).topViewController ?: top;
    }
    [out appendFormat:@"顶层=%@\r\n", DYYYNameOfObject(top)];

    // 父链（最多 8 层），能看出是 feed / 详情 / 主页 / 作品
    NSMutableArray<NSString *> *chain = [NSMutableArray array];
    for (UIViewController *c = top; c && chain.count < 8; c = c.parentViewController) {
        [chain addObject:DYYYNameOfObject(c)];
    }
    [out appendFormat:@"父链=%@\r\n", [chain componentsJoinedByString:@" < "]];

    // 互动层 referString：区分同一 VC 下的不同入口
    if ([top respondsToSelector:NSSelectorFromString(@"referString")]) {
        @try {
            id refer = [top valueForKey:@"referString"];
            [out appendFormat:@"referString=%@\r\n", refer ?: @"(nil)"];
        } @catch (__unused NSException *e) {
        }
    }
    return out;
}

static void DYYYDiagStartExport(DYYYDiagnosticsContext *context) {
    if (DYYYDiagExportIsBusy()) {
        DYYYDiagPresentError(nil, @"已有调试采集或导出正在进行");
        return;
    }
    UIViewController *host = DYYYDiagUIContextHost();
    if (!host) return;
    DYYYDiagExportSetBusy(YES);

    // 快照锚点：流水里打一行，让 view-tree / 截图 / 日志三者时间点可对齐。
    [DYYYDiagnostics appendRuntimeLogLine:@"⭐ 快照（本次导出的页面结构与截图对应这一刻）"];

    // 探针读 UIKit，必须在主线程生成后塞进上下文；后台任务只做序列化与压缩。
    // 探针文本含：状态指纹 + 当前页面标识 + 运行流水全文。
    {
        [DYYYDiagnostics flushRuntimeLogToFile];
        NSString *runtime = [NSString stringWithContentsOfFile:[DYYYDiagnostics runtimeLogPath]
                                                      encoding:NSUTF8StringEncoding error:nil];
        if (!runtime) runtime = @"";
        NSString *fp = [NSString stringWithFormat:@"全屏=%d 毛玻璃=%d 设备=%@ 系统=%@ 抖音=%@",
            DYYYPrefBool(@"DYYYEnableFullScreen") ? 1 : 0,
            DYYYPrefBool(@"DYYYEnableCommentBlur") ? 1 : 0,
            [UIDevice currentDevice].model,
            [UIDevice currentDevice].systemVersion,
            [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?"];
        // 页面标识：定位问题时先知道在哪个 VC、什么 referString，比截图精确。
        NSString *pageTag = DYYYDiagPageIdentity();
        context.probeText = [NSString stringWithFormat:
            @"== DYYY 状态指纹 ==\r\n%@\r\n"
             "== 当前页面 ==\r\n%@\r\n"
             "== 运行流水（全文 %lu 字，完整内容见 runtime.log）==\r\n%@",
            fp, pageTag, (unsigned long)runtime.length, runtime];
    }

    UIAlertController *progressAlert = [UIAlertController alertControllerWithTitle:@"DYYY"
                                                                           message:@"准备导出..."
                                                                    preferredStyle:UIAlertControllerStyleAlert];
    [host presentViewController:progressAlert animated:YES completion:^{
        DYYYDiagCreateExportInBackground(context, progressAlert);
    }];
}

static UIWindowScene *DYYYDiagForegroundScene(void) {
    if (@available(iOS 13.0, *)) {
        UIWindow *target = DYYYDiagTargetWindow();
        if (target.windowScene) return target.windowScene;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            if (scene.activationState == UISceneActivationStateForegroundActive) return (UIWindowScene *)scene;
        }
    }
    return nil;
}

static CGRect DYYYDiagScreenBounds(void) {
    UIWindow *target = DYYYDiagTargetWindow();
    if (target) return target.bounds;
    return UIScreen.mainScreen.bounds;
}

static void DYYYDiagEnsureDebugWindow(void) {
    if (DYYYDiagWindow && DYYYDiagController) {
        if (@available(iOS 13.0, *)) {
            UIWindowScene *scene = DYYYDiagForegroundScene();
            if (scene && DYYYDiagWindow.windowScene != scene) DYYYDiagWindow.windowScene = scene;
        }
        return;
    }

    DYYYDiagController = [DYYYDiagOverlayViewController new];
    if (@available(iOS 13.0, *)) {
        UIWindowScene *scene = DYYYDiagForegroundScene();
        DYYYDiagWindow = scene ? [[DYYYDiagOverlayWindow alloc] initWithWindowScene:scene]
                              : [[DYYYDiagOverlayWindow alloc] initWithFrame:DYYYDiagScreenBounds()];
    } else {
        DYYYDiagWindow = [[DYYYDiagOverlayWindow alloc] initWithFrame:DYYYDiagScreenBounds()];
    }
    DYYYDiagWindow.backgroundColor = UIColor.clearColor;
    DYYYDiagWindow.opaque = NO;
    DYYYDiagWindow.windowLevel = UIWindowLevelAlert + 100000.0;
    DYYYDiagWindow.rootViewController = DYYYDiagController;
    DYYYDiagWindow.hidden = YES;
}

#pragma mark - 浮层控制器

@implementation DYYYDiagOverlayViewController

- (void)loadView {
    DYYYDiagOverlayView *view = [[DYYYDiagOverlayView alloc] initWithFrame:DYYYDiagScreenBounds()];
    view.backgroundColor = UIColor.clearColor;
    view.opaque = NO;
    self.view = view;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.wrenchButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.wrenchButton.frame = CGRectMake(0, 0, 48, 48);
    self.wrenchButton.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.82];
    self.wrenchButton.tintColor = UIColor.whiteColor;
    self.wrenchButton.layer.cornerRadius = 24;
    self.wrenchButton.layer.shadowColor = UIColor.blackColor.CGColor;
    self.wrenchButton.layer.shadowOpacity = 0.24;
    self.wrenchButton.layer.shadowRadius = 8;
    self.wrenchButton.layer.shadowOffset = CGSizeMake(0, 2);
    self.wrenchButton.accessibilityLabel = @"DYYY 诊断";

    UIImage *image = nil;
    if ([UIImage respondsToSelector:@selector(systemImageNamed:)]) image = [UIImage systemImageNamed:@"wrench.fill"];
    if (image) {
        [self.wrenchButton setImage:image forState:UIControlStateNormal];
    } else {
        [self.wrenchButton setTitle:@"W" forState:UIControlStateNormal];
        self.wrenchButton.titleLabel.font = [UIFont boldSystemFontOfSize:20];
    }
    [self.wrenchButton addTarget:self action:@selector(wrenchTouchUpInside) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.wrenchButton];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleWrenchPan:)];
    pan.cancelsTouchesInView = NO;   // 拖扳手不取消视频触摸链（防播放暂停）
    pan.delaysTouchesBegan = NO;
    pan.delaysTouchesEnded = NO;
    [self.wrenchButton addGestureRecognizer:pan];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (!self.didPlaceButton) {
        // 位置记忆：优先恢复上次拖动到的位置（按屏幕坐标存，与安全区无关）；
        // 没有记录或落在屏幕外时，回落到默认右上角。
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSString *stored = [defaults stringForKey:@"DYYYWrenchPosition"];
        BOOL restored = NO;
        if (stored.length > 0) {
            NSArray *parts = [stored componentsSeparatedByString:@","];
            if (parts.count == 2) {
                CGFloat sx = [parts[0] doubleValue];
                CGFloat sy = [parts[1] doubleValue];
                CGRect screen = UIScreen.mainScreen.bounds;
                if (sx > 0 && sy > 0 && sx < screen.size.width && sy < screen.size.height) {
                    // 存储值是相对屏幕的绝对坐标，这里转成窗口内坐标
                    UIWindow *win = self.view.window;
                    if (win) {
                        CGPoint inWindow = [win convertPoint:CGPointMake(sx, sy) fromWindow:nil];
                        self.wrenchButton.center = inWindow;
                        restored = YES;
                    }
                }
            }
        }
        if (!restored) {
            UIEdgeInsets insets = self.view.safeAreaInsets;
            CGFloat x = self.view.bounds.size.width - insets.right - 12.0 - 24.0;
            CGFloat y = insets.top + 12.0 + 24.0;
            self.wrenchButton.center = CGPointMake(x, y);
        }
        self.didPlaceButton = YES;
    }
    [self clampWrenchButton];
}

// 把当前扳手位置存成屏幕绝对坐标，跨启动、跨屏幕旋转都能还原。
- (void)persistWrenchPosition {
    UIWindow *win = self.view.window;
    if (!win) return;
    CGPoint inScreen = [win convertPoint:self.wrenchButton.center toWindow:nil];
    NSString *value = [NSString stringWithFormat:@"%.1f,%.1f", inScreen.x, inScreen.y];
    [[NSUserDefaults standardUserDefaults] setObject:value forKey:@"DYYYWrenchPosition"];
}

- (void)clampWrenchButton {
    UIEdgeInsets insets = self.view.safeAreaInsets;
    CGFloat halfW = self.wrenchButton.bounds.size.width / 2.0;
    CGFloat halfH = self.wrenchButton.bounds.size.height / 2.0;
    CGFloat minX = insets.left + halfW + 6.0;
    CGFloat maxX = self.view.bounds.size.width - insets.right - halfW - 6.0;
    CGFloat minY = insets.top + halfH + 6.0;
    CGFloat maxY = self.view.bounds.size.height - insets.bottom - halfH - 6.0;
    CGPoint c = self.wrenchButton.center;
    c.x = MIN(MAX(c.x, minX), maxX);
    c.y = MIN(MAX(c.y, minY), maxY);
    self.wrenchButton.center = c;
}

- (void)handleWrenchPan:(UIPanGestureRecognizer *)pan {
    CGPoint delta = [pan translationInView:self.view];

    switch (pan.state) {
        case UIGestureRecognizerStateBegan:
            self.wrenchDragStartCenter = self.wrenchButton.center;
            self.wrenchDidDrag = NO;
            break;

        case UIGestureRecognizerStateChanged: {
            // pan 只有在手指真正移动后才会进 Changed，
            // 所以只要进了这里，就说明这次是「拖」不是「点」。
            self.wrenchDidDrag = YES;
            self.wrenchButton.center = CGPointMake(self.wrenchButton.center.x + delta.x,
                                                   self.wrenchButton.center.y + delta.y);
            [pan setTranslation:CGPointZero inView:self.view];
            [self clampWrenchButton];
            break;
        }

        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            // 拖动结束后记住位置，下次启动直接还原。
            if (self.wrenchDidDrag) {
                [self persistWrenchPosition];
            }
            break;

        default:
            break;
    }
}

// 单击入口。pan 手势一旦真移动过就会把 wrenchDidDrag 置 YES，
// 这次 touchUpInside 直接忽略；否则正常弹面板。
// 定时复位兜底：万一 touchUpInside 没来（被上层吃掉），2 秒后自动清标记，
// 避免下次单击被误判成拖动残留。
- (void)wrenchTouchUpInside {
    if (self.wrenchDidDrag) {
        self.wrenchDidDrag = NO;
        return;
    }
    [self showDebugMenu];
}

- (void)showDebugMenu {
    if (!DYYYPrefBool(@"DYYYDebugInspectorEnabled")) return;

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"DYYY 诊断"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    [alert addAction:[UIAlertAction actionWithTitle:@"导出诊断包 (zip)"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        [self exportWholePage];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"导出运行日志"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        [DYYYDiagnostics exportRuntimeLogFromViewController:DYYYDiagUIContextHost()];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"环境自检"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        [DYYYDiagnostics showAuditReportFromViewController:DYYYDiagUIContextHost()];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"清空日志"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        [DYYYDiagnostics clearRuntimeLogFromViewController:DYYYDiagUIContextHost()];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    if (alert.popoverPresentationController) {
        alert.popoverPresentationController.sourceView = self.wrenchButton;
        alert.popoverPresentationController.sourceRect = self.wrenchButton.bounds;
    }
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)exportWholePage {
    // 扳手菜单（ActionSheet）是从浮层控制器自己弹出的。它的 action handler 一触发，
    // 菜单还在做 dismiss 动画；此时马上从别的控制器 present 进度框，
    // 两条 modal 链相撞，菜单可能停在半关闭状态。
    // 一旦浮层控制器残留 presentedViewController，capturesOverlayTouches 就返回 YES，
    // 浮层整屏吞触摸 —— 表现为"界面被灰蒙版盖住、只剩扳手能点"，必须重启。
    // 跳一帧让菜单先完成 dismiss，再进入导出。
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *targetWindow = DYYYDiagTargetWindow();
        if (!targetWindow) {
            DYYYDiagPresentError(self, @"没有找到可导出的 App 窗口");
            return;
        }

        // 调试浮层始终置顶、无需选元素：直接快照整页（selectedView=nil 即整窗）。
        DYYYDiagnosticsContext *context = DYYYDiagCaptureContext(targetWindow, CGPointZero, nil);
        context.presenter = nil;
        context.sourceView = nil;
        DYYYDiagStartExport(context);
    });
}

// 面板（菜单/进度）在场时窗口恢复全量命中——否则"关闭"的触摸被穿透。
//
// 注意：不能只看 presentedViewController != nil。
// 分享面板（UIActivityViewController）在「交给别的 App 处理」的路径下
// （比如微信输入法中转），completionWithItemsHandler 可能不触发，
// dismiss 也可能被 App 切换打断，presentedViewController 会一直挂着。
// 这时浮层会整屏吞掉触摸，表现为「导出后界面被蒙住、扳手点不动」。
//
// 所以这里要把分享面板排除掉，并且跳过正在 dismiss 的控制器。
- (BOOL)capturesOverlayTouches {
    UIViewController *presented = self.presentedViewController;
    if (!presented) return NO;
    if (presented.isBeingDismissed) return NO;
    if ([presented isKindOfClass:[UIActivityViewController class]]) return NO;

    // 引用还在、但视图已经不在任何窗口上 → 是 dismiss 后没清干净的残留。
    // 这时候若仍然接管触摸，整个浮层会吞掉抖音的点击，
    // 表现为「只能点扳手、其他都没反应」。
    if (presented.isViewLoaded && presented.view.window == nil) return NO;

    return YES;
}

@end

#pragma mark - 对外入口

// 回到前台时清理残局。
//
// 场景：导出 ZIP → 系统分享面板 → 选微信输入法/其它 App 中转 → 分享完切回抖音。
// 这条路径下 UIActivityViewController 的 completionWithItemsHandler 常常不触发，
// dismiss 也可能被 App 切换打断，导致：
//   · DYYYDiagExportBusy 一直是 YES（下次导出报「已有导出正在进行」）
//   · presentedViewController 挂着已失效的分享面板
//   · 浮层持续吞触摸，扳手点不动
// 这里在每次回到前台时统一收尾。
static void DYYYDiagRecoverOverlayStateIfNeeded(void) {
    UIViewController *controller = DYYYDiagController;
    if (controller) {
        UIViewController *presented = controller.presentedViewController;
        if (presented) {
            BOOL isStaleShare = [presented isKindOfClass:[UIActivityViewController class]];
            BOOL isGone = presented.isBeingDismissed || presented.view.window == nil;
            if (isStaleShare || isGone) {
                [controller dismissViewControllerAnimated:NO completion:nil];
            }
        }
    }

    // 分享面板是从 App 控制器弹的，走「交给别的 App」路径时可能停在
    // dismiss 一半的状态：面板已经不在窗口上，但控制器仍认为它在 present。
    // 这种残留会让 App 窗口一直保持 dimmed（整体发灰），
    // 一并清掉。只处理已经离屏或正在关闭的分享面板，不碰用户正在用的弹窗。
    UIViewController *host = DYYYDiagUIContextHost();
    if (host && host != controller) {
        UIViewController *presented = host.presentedViewController;
        if ([presented isKindOfClass:[UIActivityViewController class]] &&
            (presented.isBeingDismissed || presented.view.window == nil)) {
            [host dismissViewControllerAnimated:NO completion:nil];
        }
    }

    // 导出流程没有正常收尾时，busy 标记会一直卡住，这里无条件放行。
    DYYYDiagExportSetBusy(NO);
}

void DYYYDiagnosticsOverlayRefresh(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL enabled = DYYYPrefBool(@"DYYYDebugInspectorEnabled");
        if (!enabled) {
            if (DYYYDiagWindow) {
                DYYYDiagWindow.hidden = YES;
                [DYYYDiagTargetWindow() makeKeyWindow];
            }
            return;
        }

        DYYYDiagEnsureDebugWindow();
        DYYYDiagWindow.frame = DYYYDiagScreenBounds();
        DYYYDiagWindow.hidden = NO;
        UIWindow *targetWindow = DYYYDiagTargetWindow();
        if (targetWindow && !targetWindow.isKeyWindow) [targetWindow makeKeyWindow];
    });
}

void DYYYDiagnosticsOverlayInstall(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (DYYYDiagInstalled) {
            DYYYDiagnosticsOverlayRefresh();
            return;
        }
        DYYYDiagInstalled = YES;

        NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
        [nc addObserverForName:UIWindowDidBecomeKeyNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            if (DYYYDiagIsDebugOverlayWindow((UIWindow *)note.object)) return;
            DYYYDiagnosticsOverlayRefresh();
        }];
        [nc addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            // 从分享面板/别的 App 切回来时，先收掉残留状态，再刷新浮层。
            DYYYDiagRecoverOverlayStateIfNeeded();
            DYYYDiagnosticsOverlayRefresh();
        }];
        DYYYDiagnosticsOverlayRefresh();
    });
}
