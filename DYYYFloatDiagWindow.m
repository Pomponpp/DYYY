#import "DYYYFloatDiagWindow.h"
#import "AwemeHeaders.h"
#import "DYYYToast.h"

@implementation DYYYFloatDiagWindow

+ (instancetype)sharedWindow {
    static DYYYFloatDiagWindow *win = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (@available(iOS 13.0, *)) {
            UIWindowScene *scene = nil;
            for (UIWindowScene *s in [UIApplication sharedApplication].connectedScenes) {
                if (s.activationState == UISceneActivationStateForegroundActive) { scene = s; break; }
            }
            win = scene ? [[DYYYFloatDiagWindow alloc] initWithWindowScene:scene]
                        : [[DYYYFloatDiagWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        } else {
            win = [[DYYYFloatDiagWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        }
        win.backgroundColor = UIColor.clearColor;
        win.opaque = NO;
        win.windowLevel = UIWindowLevelAlert + 100000.0;
        win.hidden = YES;
        DYYYFloatDiagController *vc = [DYYYFloatDiagController new];
        win.rootViewController = vc;
    });
    return win;
}

+ (void)show {
    DYYYFloatDiagWindow *win = [self sharedWindow];
    win.hidden = NO;
    [win makeKeyAndVisible];
}

+ (void)hide {
    DYYYFloatDiagWindow *win = [self sharedWindow];
    win.hidden = YES;
}

@end

@implementation DYYYFloatDiagController

- (void)loadView {
    UIView *v = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    v.backgroundColor = UIColor.clearColor;
    v.opaque = NO;
    self.view = v;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    UIButton *wrench = [UIButton buttonWithType:UIButtonTypeCustom];
    wrench.frame = CGRectMake(0, 0, 48, 48);
    wrench.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.85];
    wrench.layer.cornerRadius = 24;
    wrench.layer.borderWidth = 1;
    wrench.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.25].CGColor;
    wrench.tintColor = UIColor.whiteColor;
    [wrench setTitle:@"🔧" forState:UIControlStateNormal];
    wrench.titleLabel.font = [UIFont boldSystemFontOfSize:20];
    wrench.translatesAutoresizingMaskIntoConstraints = NO;
    [wrench addTarget:self action:@selector(tapWrench) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panWrench:)];
    [wrench addGestureRecognizer:pan];
    [self.view addSubview:wrench];
    self.wrenchButton = wrench;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    // 默认位置：右下角，避开底部安全区
    if (self.wrenchButton.center.x == 24 && self.wrenchButton.center.y == 24) {
        UIView *v = self.view;
        self.wrenchButton.center = CGPointMake(v.bounds.size.width - 48, v.bounds.size.height - 140);
    }
}

- (void)panWrench:(UIPanGestureRecognizer *)pan {
    CGPoint t = [pan translationInView:self.view];
    if (pan.state == UIGestureRecognizerStateBegan || pan.state == UIGestureRecognizerStateChanged) {
        CGPoint c = self.wrenchButton.center;
        c.x += t.x; c.y += t.y;
        CGFloat maxX = self.view.bounds.size.width - 24;
        CGFloat maxY = self.view.bounds.size.height - 24;
        c.x = MIN(MAX(c.x, 24), maxX);
        c.y = MIN(MAX(c.y, 24), maxY);
        self.wrenchButton.center = c;
        [pan setTranslation:CGPointZero inView:self.view];
    }
}

- (void)tapWrench {
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"DYYY 诊断"
                                                                 message:nil
                                                          preferredStyle:UIAlertControllerStyleActionSheet];
    void (^run)(void(^)(UIViewController *)) = ^(void(^work)(UIViewController *p)) {
        work(self);
    };
    [menu addAction:[UIAlertAction actionWithTitle:@"导出诊断包" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        run(^(UIViewController *p) { [DYYYDiagnostics exportDiagnosticsBundleFromViewController:self]; });
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"导出日志" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        run(^(UIViewController *p) { [DYYYDiagnostics exportRuntimeLogFromViewController:self]; });
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"环境自检" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        run(^(UIViewController *p) { [DYYYDiagnostics showAuditReportFromViewController:self]; });
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"清空日志" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        run(^(UIViewController *p) { [DYYYDiagnostics clearRuntimeLogFromViewController:self]; });
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView = self.wrenchButton;
    menu.popoverPresentationController.sourceRect = self.wrenchButton.bounds;
    [self presentViewController:menu animated:YES completion:nil];
}

// hitTest 穿透：只有扳手区域响应触摸，其余全部穿透给抖音
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    CGPoint p = [self.wrenchButton convertPoint:point fromView:self.view];
    return [self.wrenchButton pointInside:p withEvent:event];
}

@end
