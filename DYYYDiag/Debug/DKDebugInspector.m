//
//  DKDebugInspector.m
//  DYYY 诊断子系统 —— 浮窗入口
//
//  全局扳手：独立高层级 window 承载调试按钮，点选页面元素后复用
//  DKDebugCapture / DKDebugExport 生成导出包。
//
//  来源：本目录（DYYYDiag/）的采集骨架与 FLEX 类 dump 参考开源社区实现，
//  DYYY 接入了自有运行流水、状态指纹、compat 三件套（audit /
//  class-list / target-methods），并把浮窗与日志统一为「诊断模式」。
//  详见 CREDITS.md。
//

#import "DKDebugInspector.h"
#import "../Shared/DKKeys.h"
#import "../Shared/DKUtils.h"
#import "DKDebugCapture.h"
#import "../DKDYYYBridge.h"
#import "DKDebugExport.h"

@interface DKDebugOverlayView : UIView
@end

@implementation DKDebugOverlayView

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return (hit == self) ? nil : hit;
}

@end

@interface DKDebugOverlayWindow : UIWindow
@end

@interface DKDebugOverlayViewController : UIViewController
@property (nonatomic, strong) UIButton *wrenchButton;
@property (nonatomic, assign) BOOL didPlaceButton;
// 扳手拖动判定：区分「拖」与「点」，避免拖动结束被当成点击弹面板。
@property (nonatomic, assign) CGPoint wrenchDragStartCenter;
@property (nonatomic, assign) BOOL wrenchDidDrag;
- (BOOL)capturesOverlayTouches;
- (void)exportWholePage;
@end

@implementation DKDebugOverlayWindow

// #69 浮窗拖动导致视频暂停的根修：
// 浮层 windowLevel 极高，若它成为 key window，抖音的视频窗口会在拖动期间
// 反复失去 key → 播放器/触摸链中断 → 暂停。
// 浮层只负责显示扳手按钮与面板，从不承载键盘输入，因此不该当 key window。
- (BOOL)canBecomeKeyWindow {
    return NO;
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    DKDebugOverlayViewController *controller = [self.rootViewController isKindOfClass:DKDebugOverlayViewController.class]
                                               ? (DKDebugOverlayViewController *)self.rootViewController
                                               : nil;
    if ([controller capturesOverlayTouches]) return [super pointInside:point withEvent:event];
    CGPoint p = [controller.wrenchButton convertPoint:point fromView:self];
    return [controller.wrenchButton pointInside:p withEvent:event];
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    DKDebugOverlayViewController *controller = [self.rootViewController isKindOfClass:DKDebugOverlayViewController.class]
                                               ? (DKDebugOverlayViewController *)self.rootViewController
                                               : nil;
    if ([controller capturesOverlayTouches]) return hit ?: controller.view;
    if (!hit || hit == controller.view || hit == self) return nil;
    return hit;
}

@end

static DKDebugOverlayWindow *DKDebugWindow;
static DKDebugOverlayViewController *DKDebugController;
static BOOL DKDebugInstalled;
static BOOL DKDebugExportBusy;

#pragma mark - UI 工具

static BOOL DKIsDebugOverlayWindow(UIWindow *window) {
    return [DKNameOfObject(window) hasPrefix:@"DKDebug"];
}

static void DKPresentError(UIViewController *presenter, NSString *message) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"导出失败"
                                                                       message:message ?: @"未知错误"
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleCancel handler:nil]];
        [presenter presentViewController:alert animated:YES completion:nil];
    });
}

// 把 underlying 与保留下来的工作目录一并展开：只显示顶层描述的话，
// ZIP 的 -3/-4/-5 三种失败在界面上长得一模一样，等于没有诊断。
static NSString *DKExportErrorMessage(NSError *error, NSString *fallback) {
    if (!error) return fallback;
    NSMutableString *message = [NSMutableString stringWithString:error.localizedDescription ?: fallback];
    NSError *underlying = error.userInfo[NSUnderlyingErrorKey];
    if (underlying) {
        [message appendFormat:@"\n\n[%@ %ld] %@", underlying.domain ?: @"",
         (long)underlying.code, underlying.localizedDescription ?: @""];
    }
    NSString *workingDirectory = error.userInfo[DKDebugExportWorkingDirectoryKey];
    if (workingDirectory.length) {
        [message appendFormat:@"\n\n工作目录已保留:\n%@", workingDirectory];
    }
    return message;
}

static void DKShareExport(DKDebugExportResult *result, UIViewController *presenter, UIView *sourceView) {
    if (!result.zipURL) {
        DKDebugCleanupExport(result);
        DKPresentError(presenter, @"ZIP 文件不存在");
        return;
    }
    UIActivityViewController *activity = [[UIActivityViewController alloc] initWithActivityItems:@[result.zipURL]
                                                                          applicationActivities:nil];
    if (activity.popoverPresentationController) {
        activity.popoverPresentationController.sourceView = sourceView ?: presenter.view;
        activity.popoverPresentationController.sourceRect = (sourceView ?: presenter.view).bounds;
    }
    activity.completionWithItemsHandler = ^(__unused UIActivityType activityType,
                                            __unused BOOL completed,
                                            __unused NSArray *returnedItems,
                                            __unused NSError *activityError) {
        DKDebugCleanupExport(result);
    };
    [presenter presentViewController:activity animated:YES completion:nil];
}

static void DKSetProgress(UIAlertController *alert, NSString *text) {
    dispatch_async(dispatch_get_main_queue(), ^{
        alert.message = text ?: @"处理中...";
    });
}

static void DKCreateExportInBackground(DKDebugExportContext *context,
                                       DKDebugExportMode mode,
                                       UIAlertController *progressAlert) {
    UIViewController *presenter = context.presenter ?: DKDebugController;
    if (!presenter) {
        DKDebugExportBusy = NO;
        return;
    }

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *exportError = nil;
        DKDebugExportResult *result = DKDebugCreateExport(context, mode, ^(NSString *text) {
            DKSetProgress(progressAlert, text);
        }, &exportError);
        dispatch_async(dispatch_get_main_queue(), ^{
            DKDebugExportBusy = NO;
            [progressAlert dismissViewControllerAnimated:YES completion:^{
                if (result) {
                    DKShareExport(result, presenter, context.sourceView ?: presenter.view);
                } else {
                    DKPresentError(presenter, DKExportErrorMessage(exportError, @"没有生成 ZIP 文件"));
                }
            }];
        });
    });
}

// 当前页面标识：顶层 VC 类名 + referString + 选中 tab。
// 定位问题时先知道在哪，比从截图猜快。
static NSString *DKDebugPageIdentity(void) {
    NSMutableString *out = [NSMutableString string];
    UIWindow *window = DKDebugTargetWindow();
    UIViewController *root = window.rootViewController;
    if (!root) {
        [out appendString:@"(无窗口或无根控制器)"];
        return out;
    }
    UIViewController *top = root;
    if ([top isKindOfClass:[UITabBarController class]]) {
        UIViewController *sel = ((UITabBarController *)top).selectedViewController;
        [out appendFormat:@"tab=%@\r\n", DKNameOfObject(sel)];
        if (sel) top = sel;
    }
    if ([top isKindOfClass:[UINavigationController class]]) {
        top = ((UINavigationController *)top).topViewController ?: top;
    }
    [out appendFormat:@"顶层=%@\r\n", DKNameOfObject(top)];

    // 父链（最多 8 层），能看出是 feed / 详情 / 主页 / 作品
    NSMutableArray<NSString *> *chain = [NSMutableArray array];
    for (UIViewController *c = top; c && chain.count < 8; c = c.parentViewController) {
        [chain addObject:DKNameOfObject(c)];
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

static void DKStartExport(DKDebugExportContext *context, DKDebugExportMode mode) {
    UIViewController *presenter = context.presenter ?: DKDebugController;
    if (!presenter) return;
    if (DKDebugExportBusy) {
        DKPresentError(presenter, @"已有调试采集或导出正在进行");
        return;
    }
    DKDebugExportBusy = YES;

    // 快照锚点：流水里打一行，让 view-tree / 截图 / 日志三者时间点可对齐。
    [DKDYYYBridge appendRuntimeLogLine:@"⭐ 快照（本次导出的页面结构与截图对应这一刻）"];

    // 探针读 UIKit，必须在主线程生成后塞进上下文；后台任务只做序列化与压缩。
    // 探针文本含：状态指纹 + 当前页面标识 + 运行流水全文。
    {
        NSString *runtime = [NSString stringWithContentsOfFile:[DKDYYYBridge runtimeLogPath]
                                                      encoding:NSUTF8StringEncoding error:nil];
        if (!runtime) runtime = @"";
        NSString *fp = [DKDYYYBridge exportFingerprint];
        // 页面标识：定位问题时先知道在哪个 VC、什么 referString，比截图精确。
        NSString *pageTag = DKDebugPageIdentity();
        context.probeText = [NSString stringWithFormat:
            @"== DYYY 状态指纹 ==\r\n%@\r\n"
             "== 当前页面 ==\r\n%@\r\n"
             "== 运行流水（全文 %lu 字，完整内容见 runtime.log）==\r\n%@",
            fp, pageTag, (unsigned long)runtime.length, runtime];
    }

    UIAlertController *progressAlert = [UIAlertController alertControllerWithTitle:@"DYYY"
                                                                           message:@"准备导出..."
                                                                    preferredStyle:UIAlertControllerStyleAlert];
    [presenter presentViewController:progressAlert animated:YES completion:^{
        DKCreateExportInBackground(context, mode, progressAlert);
    }];
}

static UIWindowScene *DKDebugForegroundScene(void) {
    if (@available(iOS 13.0, *)) {
        UIWindow *target = DKDebugTargetWindow();
        if (target.windowScene) return target.windowScene;
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            if (scene.activationState == UISceneActivationStateForegroundActive) return (UIWindowScene *)scene;
        }
    }
    return nil;
}

static CGRect DKDebugScreenBounds(void) {
    UIWindow *target = DKDebugTargetWindow();
    if (target) return target.bounds;
    return UIScreen.mainScreen.bounds;
}

static void DKEnsureDebugWindow(void) {
    if (DKDebugWindow && DKDebugController) {
        if (@available(iOS 13.0, *)) {
            UIWindowScene *scene = DKDebugForegroundScene();
            if (scene && DKDebugWindow.windowScene != scene) DKDebugWindow.windowScene = scene;
        }
        return;
    }

    DKDebugController = [DKDebugOverlayViewController new];
    if (@available(iOS 13.0, *)) {
        UIWindowScene *scene = DKDebugForegroundScene();
        DKDebugWindow = scene ? [[DKDebugOverlayWindow alloc] initWithWindowScene:scene]
                              : [[DKDebugOverlayWindow alloc] initWithFrame:DKDebugScreenBounds()];
    } else {
        DKDebugWindow = [[DKDebugOverlayWindow alloc] initWithFrame:DKDebugScreenBounds()];
    }
    DKDebugWindow.backgroundColor = UIColor.clearColor;
    DKDebugWindow.opaque = NO;
    DKDebugWindow.windowLevel = UIWindowLevelAlert + 100000.0;
    DKDebugWindow.rootViewController = DKDebugController;
    DKDebugWindow.hidden = YES;
}

#pragma mark - 浮层控制器

@implementation DKDebugOverlayViewController

- (void)loadView {
    DKDebugOverlayView *view = [[DKDebugOverlayView alloc] initWithFrame:DKDebugScreenBounds()];
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
        UIEdgeInsets insets = self.view.safeAreaInsets;
        CGFloat x = self.view.bounds.size.width - insets.right - 12.0 - 24.0;
        CGFloat y = insets.top + 12.0 + 24.0;
        self.wrenchButton.center = CGPointMake(x, y);
        self.didPlaceButton = YES;
    }
    [self clampWrenchButton];
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
            // 拖动结束：本次手势标记为已拖动，抑制随之而来的 touchUpInside。
            // 标记会在 wrenchTouchUpInside 里消费掉并复位。
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
    if (!DKPrefBool(DKKeyDebugInspectorEnabled)) return;

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
        [DKDYYYBridge exportRuntimeLogFromOverlay:self];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"环境自检"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        [DKDYYYBridge showAuditReportFromOverlay:self];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"清空日志"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        [DKDYYYBridge clearRuntimeLogFromOverlay:self];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    if (alert.popoverPresentationController) {
        alert.popoverPresentationController.sourceView = self.wrenchButton;
        alert.popoverPresentationController.sourceRect = self.wrenchButton.bounds;
    }
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)exportWholePage {
    UIWindow *targetWindow = DKDebugTargetWindow();
    if (!targetWindow) {
        DKPresentError(self, @"没有找到可导出的 App 窗口");
        return;
    }

    // 调试浮层始终置顶、无需选元素：直接快照整页（selectedView=nil 即整窗）。
    DKDebugExportContext *context = DKDebugCaptureContext(targetWindow, CGPointZero, nil);
    context.presenter = self;
    context.sourceView = self.wrenchButton;
    DKStartExport(context, DKDebugExportModePage);
}

// 面板（菜单/进度/分享）在场时窗口恢复全量命中——否则"关闭"的触摸被穿透。
// （音频专项删除时误切掉了原实现，按原版补回。）
- (BOOL)capturesOverlayTouches {
    return self.presentedViewController != nil;
}

@end

#pragma mark - 对外入口

void DKDebugInspectorRefreshOverlay(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL enabled = DKPrefBool(DKKeyDebugInspectorEnabled);
        if (!enabled) {
            if (DKDebugWindow) {
                DKDebugWindow.hidden = YES;
                [DKDebugTargetWindow() makeKeyWindow];
            }
            return;
        }

        DKEnsureDebugWindow();
        DKDebugWindow.frame = DKDebugScreenBounds();
        DKDebugWindow.hidden = NO;
        UIWindow *targetWindow = DKDebugTargetWindow();
        if (targetWindow && !targetWindow.isKeyWindow) [targetWindow makeKeyWindow];
    });
}

void DKDebugInspectorInstall(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (DKDebugInstalled) {
            DKDebugInspectorRefreshOverlay();
            return;
        }
        DKDebugInstalled = YES;

        NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
        [nc addObserverForName:UIWindowDidBecomeKeyNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
            if (DKIsDebugOverlayWindow((UIWindow *)note.object)) return;
            DKDebugInspectorRefreshOverlay();
        }];
        [nc addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note) {
            DKDebugInspectorRefreshOverlay();
        }];
        DKDebugInspectorRefreshOverlay();
    });
}
