// DYYYDiag — 一体化诊断浮层
// 独立窗口 + 扳手 + 主线程采集 + 后台压缩 + 自身 VC 分享，机制照搬已验证实现。
// 浮窗样式沿用 DYYY 早期外观；导出包额外融合运行时流水日志与开关状态指纹。
#import "AwemeHeaders.h"
#import "DYYYDiag.h"
#import "DYYYDiagZip.h"
#import "DYYYToast.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import <zlib.h>

#pragma mark - 透传视图 / 窗口（窗口层命中测试，事件不进视图树）

@interface DYYYDiagPassView : UIView
@property (nonatomic, weak) UIButton *wrench;
@end
@implementation DYYYDiagPassView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return (hit == self) ? nil : hit;
}
@end

@interface DYYYDiagOverlayWindow : UIWindow
@property (nonatomic, weak) UIButton *wrench;
@end
@implementation DYYYDiagOverlayWindow
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    DYYYDiagController *c = [self.rootViewController isKindOfClass:DYYYDiagController.class] ? (DYYYDiagController *)self.rootViewController : nil;
    if (c.capturesOverlayTouches) return [super pointInside:point withEvent:event];  // 面板在场：全量收
    if (!_wrench || _wrench.hidden) return NO;
    CGPoint p = [_wrench convertPoint:point fromView:self];
    return [_wrench pointInside:p withEvent:event];
}
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    DYYYDiagController *c = [self.rootViewController isKindOfClass:DYYYDiagController.class] ? (DYYYDiagController *)self.rootViewController : nil;
    UIView *hit = [super hitTest:point withEvent:event];
    if (c.capturesOverlayTouches) return hit ?: c.view;
    if (!hit || hit == self || hit == self.rootViewController.view) return nil;
    return hit;
}
@end

#pragma mark - 全局状态

static DYYYDiagOverlayWindow *gWindow;
static DYYYDiagController *gController;
static BOOL gInstalled;
static BOOL gBusy;

static BOOL DYYYDiagIsOverlay(UIWindow *w) {
    return [NSStringFromClass(w.class) hasPrefix:@"DYYYDiag"];
}

// 安全窗口集合：只画前台可见、非调试自身、alpha>0 的窗口（截图 abort 的关键过滤）
static NSArray<UIWindow *> *DYYYDiagActiveWindows(void) {
    NSMutableArray *out = [NSMutableArray array];
    if (@available(iOS 13.0, *)) {
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if (![s isKindOfClass:[UIWindowScene class]]) continue;
            if (s.activationState != UISceneActivationStateForegroundActive) continue;
            for (UIWindow *w in ((UIWindowScene *)s).windows) {
                if (!w || DYYYDiagIsOverlay(w)) continue;
                if (w.hidden || w.alpha <= 0.01) continue;
                [out addObject:w];
            }
        }
    }
    if (out.count == 0) {
        for (UIWindow *w in UIApplication.sharedApplication.windows) {
            if (!w || DYYYDiagIsOverlay(w)) continue;
            if (w.hidden || w.alpha <= 0.01) continue;
            [out addObject:w];
        }
    }
    return out;
}

static UIWindow *DYYYDiagTargetWindow(void) {
    NSArray *ws = DYYYDiagActiveWindows();
    for (UIWindow *w in ws) if (w.isKeyWindow) return w;
    return ws.firstObject;
}

static UIWindowScene *DYYYDiagForegroundScene(void) {
    if (@available(iOS 13.0, *)) {
        UIWindow *t = DYYYDiagTargetWindow();
        if (t.windowScene) return t.windowScene;
        for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
            if ([s isKindOfClass:[UIWindowScene class]] && s.activationState == UISceneActivationStateForegroundActive)
                return (UIWindowScene *)s;
        }
    }
    return nil;
}

static CGRect DYYYDiagScreenBounds(void) {
    UIWindow *t = DYYYDiagTargetWindow();
    return t ? t.bounds : UIScreen.mainScreen.bounds;
}

#pragma mark - 快照采集（主线程，纯数据）

@interface DYYYDiagSnapshot : NSObject
@property (nonatomic, strong) NSMutableArray *files; // @{path, data}
@end
@implementation DYYYDiagSnapshot
@end

// 视图树文本（含背景色/裁剪/frame，沿用项目既有风格）
static void DYYYDiagAppendView(NSMutableString *s, UIView *v, int depth) {
    if (!v || depth > 40) return;
    NSString *pad = [@"" stringByPaddingToLength:depth * 2 withString:@" " startingAtIndex:0];
    CGFloat r=0,g=0,b=0,a=0;
    UIColor *bg = v.backgroundColor;
    [bg getRed:&r green:&g blue:&b alpha:&a];
    [s appendFormat:@"%@%@ frame=%@ bg=%.2f,%.2f,%.2f,%.2f clip=%d hidden=%d alpha=%.2f\n",
        pad, NSStringFromClass(v.class), NSStringFromCGRect(v.frame), r,g,b,a,
        v.clipsToBounds, v.hidden, v.alpha];
    for (UIView *sub in v.subviews) DYYYDiagAppendView(s, sub, depth + 1);
}

static void DYYYDiagCaptureMain(DYYYDiagSnapshot *snap) {
    NSArray *windows = [DYYYDiagActiveWindows() sortedArrayUsingComparator:^NSComparisonResult(UIWindow *a, UIWindow *b) {
        return a.windowLevel < b.windowLevel ? NSOrderedAscending : (a.windowLevel > b.windowLevel ? NSOrderedDescending : NSOrderedSame);
    }];
    NSMutableString *tree = [NSMutableString string];
    [tree appendFormat:@"采集时刻: %@\n窗口数: %lu\n\n", [NSDate date], (unsigned long)windows.count];
    for (UIWindow *w in windows) {
        [tree appendFormat:@"== %@ level=%.0f ==\n", NSStringFromClass(w.class), w.windowLevel];
        DYYYDiagAppendView(tree, w, 1);
    }

    // 截图：按 level 低→高逐窗口合成，只画安全窗口集合（默认开，与已验证实现一致）
    UIWindow *target = DYYYDiagTargetWindow() ?: windows.firstObject;
    NSData *png = nil;
    if (target) {
        UIGraphicsBeginImageContextWithOptions(target.bounds.size, NO, 0);
        for (UIWindow *w in windows) {
            BOOL drew = [w drawViewHierarchyInRect:w.bounds afterScreenUpdates:NO];
            if (!drew) [w.layer renderInContext:UIGraphicsGetCurrentContext()];
        }
        UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        png = img ? UIImagePNGRepresentation(img) : nil;
    }

    // 环境/开关状态
    NSMutableDictionary *state = [NSMutableDictionary dictionary];
    state[@"timestamp"] = [[NSDate date] description];
    state[@"deviceModel"] = [UIDevice currentDevice].model;
    state[@"systemVersion"] = [UIDevice currentDevice].systemVersion;
    state[@"appVersion"] = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?";
    state[@"screen"] = NSStringFromCGRect(UIScreen.mainScreen.bounds);
    state[@"fullScreen"] = @(DYYYGetBool(@"DYYYEnableFullScreen"));
    state[@"fullNewDetailTable"] = @(DYYYGetBool(@"DYYYFullNewDetailTable"));
    state[@"commentAvoidVideo"] = @(DYYYGetBool(@"DYYYCommentAvoidVideo"));
    state[@"commentBlur"] = @(DYYYGetBool(@"DYYYEnableCommentBlur"));
    state[@"windowCount"] = @(windows.count);

    // 融合：运行时流水日志 + 开关指纹 + 摘要
    NSString *runtime = [NSString stringWithContentsOfFile:[DYYYDiagnostics runtimeLogPath]
                                                  encoding:NSUTF8StringEncoding error:nil] ?: @"(运行日志为空)";
    NSString *fingerprint = [NSString stringWithFormat:
        @"导出状态：全屏=%d 详情页新机制(实验)=%d 评论避让视频=%d 毛玻璃=%d\n",
        DYYYGetBool(@"DYYYEnableFullScreen")?1:0, DYYYGetBool(@"DYYYFullNewDetailTable")?1:0,
        DYYYGetBool(@"DYYYCommentAvoidVideo")?1:0, DYYYGetBool(@"DYYYEnableCommentBlur")?1:0];
    NSString *summary = [NSString stringWithFormat:
        @"# DYYY 诊断摘要\n\n%@\n采集时刻: %@\n安全窗口: %lu\n视图树字节: %lu\n截图: %@\n\n"
        @"快照与 runtime.log 通过本文件时刻对齐。\n",
        fingerprint, [NSDate date], (unsigned long)windows.count,
        (unsigned long)tree.length, png ? @"已生成" : @"未生成"];

    NSData *json = [NSJSONSerialization dataWithJSONObject:state options:NSJSONWritingPrettyPrinted error:nil];
    [snap.files addObject:@{@"name":@"view-tree.txt", @"data":[tree dataUsingEncoding:NSUTF8StringEncoding]}];
    [snap.files addObject:@{@"name":@"state.json", @"data":json ?: [NSData data]}];
    [snap.files addObject:@{@"name":@"runtime.log", @"data":[runtime dataUsingEncoding:NSUTF8StringEncoding]}];
    [snap.files addObject:@{@"name":@"summary.md", @"data":[summary dataUsingEncoding:NSUTF8StringEncoding]}];
    if (png) [snap.files addObject:@{@"name":@"screenshot.png", @"data":png}];
}

#pragma mark - 后台压缩 + 主线程分享（异步节点）

static void DYYYDiagShare(NSURL *zipURL) {
    UIActivityViewController *act = [[UIActivityViewController alloc] initWithActivityItems:@[zipURL] applicationActivities:nil];
    act.popoverPresentationController.sourceView = gController.wrenchButton;
    act.popoverPresentationController.sourceRect = gController.wrenchButton.bounds;
    act.completionWithItemsHandler = ^(__unused UIActivityType t, __unused BOOL done, __unused NSArray *items, __unused NSError *err) {
        [[NSFileManager defaultManager] removeItemAtURL:zipURL error:nil];
    };
    [gController presentViewController:act animated:YES completion:nil];
}

// 后台：只做写盘与压缩，绝不碰 UIKit。
static void DYYYDiagCompressAndShare(DYYYDiagSnapshot *snap, UIAlertController *progress) {
    NSDateFormatter *f = [NSDateFormatter new]; f.dateFormat = @"yyyyMMdd-HHmmss";
    NSString *name = [NSString stringWithFormat:@"DYYY-diag-%@", [f stringFromDate:[NSDate date]]];
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *dir = [[docs stringByAppendingPathComponent:@"DYYY"] stringByAppendingPathComponent:@"logs"];
    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *root = [dir stringByAppendingPathComponent:name];
    [fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];

    // createFileAtPath:contents: 是纯 C 写入，避开 NSString writeToFile 的 fsync/C++ 异常路径
    NSMutableArray *rel = [NSMutableArray array];
    for (NSDictionary *item in snap.files) {
        NSString *p = [root stringByAppendingPathComponent:item[@"name"]];
        NSData *d = item[@"data"];
        if ([d isKindOfClass:[NSData class]] && [fm createFileAtPath:p contents:d attributes:nil]) {
            [rel addObject:item[@"name"]];
        }
    }

    NSString *zipPath = [dir stringByAppendingPathComponent:[name stringByAppendingString:@".zip"]];
    BOOL ok = [DYYYDiagZip createZipAtPath:zipPath rootDir:root files:rel progress:nil error:nil];

    dispatch_async(dispatch_get_main_queue(), ^{
        gBusy = NO;
        [progress dismissViewControllerAnimated:YES completion:^{
            if (ok) {
                [DYYYToast showSuccessToastWithMessage:[NSString stringWithFormat:@"诊断包已生成\n文件App → DYYY/logs/%@.zip", name]];
                DYYYDiagShare([NSURL fileURLWithPath:zipPath]);
            } else {
                [DYYYToast showSuccessToastWithMessage:[NSString stringWithFormat:@"诊断文件已保存\nDYYY/logs/%@/", name]];
            }
        }];
    });
}

static void DYYYDiagStartExport(void) {
    if (gBusy) { [DYYYToast showSuccessToastWithMessage:@"正在导出，请稍候"]; return; }
    gBusy = YES;

    // 主线程采集（UIKit 只读：视图树 / 截图 / 窗口过滤），采完立刻冻结为纯数据
    DYYYDiagSnapshot *snap = [DYYYDiagSnapshot new];
    snap.files = [NSMutableArray array];
    @try { DYYYDiagCaptureMain(snap); }
    @catch (NSException *e) { NSLog(@"[DYYY][diag] capture: %@", e.name); }

    UIAlertController *p = [UIAlertController alertControllerWithTitle:@"DYYY 诊断" message:@"正在生成诊断包…" preferredStyle:UIAlertControllerStyleAlert];
    [gController presentViewController:p animated:YES completion:^{
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            DYYYDiagCompressAndShare(snap, p);
        });
    }];
}

#pragma mark - 浮层控制器（外观沿用 DYYY 早期样式）

@interface DYYYDiagController ()
@property (nonatomic, assign) BOOL didPlace;
@end

@implementation DYYYDiagController

- (void)loadView {
    DYYYDiagPassView *v = [[DYYYDiagPassView alloc] initWithFrame:DYYYDiagScreenBounds()];
    v.backgroundColor = UIColor.clearColor; v.opaque = NO;
    self.view = v;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    UIButton *w = [UIButton buttonWithType:UIButtonTypeCustom];
    w.frame = CGRectMake(0, 0, 44, 44);
    w.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.85];
    w.layer.cornerRadius = 22;
    w.layer.borderWidth = 1;
    w.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.25].CGColor;
    w.tintColor = UIColor.whiteColor;
    [w setTitle:@"🔧" forState:UIControlStateNormal];
    w.titleLabel.font = [UIFont boldSystemFontOfSize:20];
    [w addTarget:self action:@selector(tapWrench) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panWrench:)];
    [w addGestureRecognizer:pan];
    [self.view addSubview:w];
    self.wrenchButton = w;
    ((DYYYDiagPassView *)self.view).wrench = w;
    gWindow.wrench = w;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (!self.didPlace) {
        self.wrenchButton.center = CGPointMake(self.view.bounds.size.width - 48,
                                               self.view.bounds.size.height - 140);
        self.didPlace = YES;
    }
    UIEdgeInsets in = self.view.safeAreaInsets;
    CGFloat hx = 22, hy = 22;
    CGPoint c = self.wrenchButton.center;
    c.x = MIN(MAX(c.x, in.left+hx+6), self.view.bounds.size.width-in.right-hx-6);
    c.y = MIN(MAX(c.y, in.top+hy+6), self.view.bounds.size.height-in.bottom-hy-6);
    self.wrenchButton.center = c;
}

- (void)panWrench:(UIPanGestureRecognizer *)pan {
    CGPoint d = [pan translationInView:self.view];
    self.wrenchButton.center = CGPointMake(self.wrenchButton.center.x+d.x, self.wrenchButton.center.y+d.y);
    [pan setTranslation:CGPointZero inView:self.view];
    [self viewDidLayoutSubviews];
}

// 有面板（菜单/进度/分享）在场时窗口恢复全量命中——否则"关闭"的触摸被穿透
- (BOOL)capturesOverlayTouches {
    return self.presentedViewController != nil;
}

- (void)tapWrench {
    if (!DYYYGetBool(@"DYYYDiagEntryEnabled")) return;
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"DYYY 诊断" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [menu addAction:[UIAlertAction actionWithTitle:@"导出诊断包" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        DYYYDiagStartExport();
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView = self.wrenchButton;
    menu.popoverPresentationController.sourceRect = self.wrenchButton.bounds;
    [self presentViewController:menu animated:YES completion:nil];
}

@end

#pragma mark - 安装 / 刷新（启动早期装好，hidden 待命，只翻 hidden）

static void DYYYDiagEnsureWindow(void) {
    if (gWindow && gController) {
        // 启动早期建的窗口可能没有 scene；获得前台 scene 后补挂
        if (@available(iOS 13.0, *)) {
            UIWindowScene *scene = DYYYDiagForegroundScene();
            if (scene && gWindow.windowScene != scene) gWindow.windowScene = scene;
        }
        return;
    }
    gController = [DYYYDiagController new];
    UIWindowScene *scene = DYYYDiagForegroundScene();
    gWindow = scene ? [[DYYYDiagOverlayWindow alloc] initWithWindowScene:scene]
                    : [[DYYYDiagOverlayWindow alloc] initWithFrame:DYYYDiagScreenBounds()];
    gWindow.backgroundColor = UIColor.clearColor;
    gWindow.opaque = NO;
    gWindow.windowLevel = UIWindowLevelAlert + 100000.0;
    gWindow.rootViewController = gController;
    gWindow.hidden = YES;
}

+ (UIViewController *)diagPresenter {
    [DYYYDiagEnsureWindow];
    gWindow.hidden = NO;
    return gController;   // presenter 恒为自己窗口 rootVC，与浮窗同一条安全路径
}

void DYYYDiagRefresh(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        BOOL on = DYYYGetBool(@"DYYYDiagEntryEnabled");
        if (!on) { if (gWindow) gWindow.hidden = YES; return; }
        DYYYDiagEnsureWindow();
        gWindow.frame = DYYYDiagScreenBounds();
        gWindow.hidden = NO;
        UIWindow *t = DYYYDiagTargetWindow();
        if (t && !t.isKeyWindow) [t makeKeyWindow];
    });
}

void DYYYDiagInstall(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (gInstalled) { DYYYDiagRefresh(); return; }
        gInstalled = YES;
        NSNotificationCenter *nc = NSNotificationCenter.defaultCenter;
        [nc addObserverForName:UIWindowDidBecomeKeyNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *n) {
            if (!DYYYDiagIsOverlay((UIWindow *)n.object)) DYYYDiagRefresh();
        }];
        [nc addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *n) {
            DYYYDiagRefresh();
        }];
        DYYYDiagRefresh();
    });
}
