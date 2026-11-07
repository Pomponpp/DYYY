#import "DYYYFloatDiagWindow.h"
#import "AwemeHeaders.h"
#import "DYYYToast.h"

@class DYYYFloatDiagController;

@interface DYYYFloatDiagWindow ()
@end

static DYYYFloatDiagWindow *_diagWindow = nil;
static DYYYFloatDiagController *_diagController = nil;

// 透传容器视图：只有扳手 frame 内返回 YES，其余穿透
@interface DYYYFloatDiagPassView : UIView
@property (nonatomic, weak) UIButton *wrenchButton;
@end

@implementation DYYYFloatDiagPassView
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    if (!_wrenchButton) return NO;
    CGPoint p = [self convertPoint:point toView:_wrenchButton];
    return [_wrenchButton pointInside:p withEvent:event];
}
@end

@interface DYYYFloatDiagController : UIViewController
@property (nonatomic, strong) UIButton *wrenchButton;
@property (nonatomic, strong) DYYYFloatDiagPassView *passView;
- (void)tapWrench;
- (void)panWrench:(UIPanGestureRecognizer *)pan;
@end

@implementation DYYYFloatDiagWindow

+ (instancetype)sharedWindow {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (@available(iOS 13.0, *)) {
            UIWindowScene *scene = nil;
            for (UIWindowScene *sc in [UIApplication sharedApplication].connectedScenes) {
                if (sc.activationState == UISceneActivationStateForegroundActive) { scene = sc; break; }
            }
            _diagWindow = scene ? [[DYYYFloatDiagWindow alloc] initWithWindowScene:scene]
                                : [[DYYYFloatDiagWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        } else {
            _diagWindow = [[DYYYFloatDiagWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        }
        _diagWindow.backgroundColor = UIColor.clearColor;
        _diagWindow.opaque = NO;
        _diagWindow.windowLevel = UIWindowLevelAlert + 100000.0;
        _diagWindow.hidden = YES;
        _diagController = [DYYYFloatDiagController new];
        _diagWindow.rootViewController = _diagController;
    });
    return _diagWindow;
}

+ (void)show {
    [self sharedWindow].hidden = NO;
}

+ (void)hide {
    [self sharedWindow].hidden = YES;
}

@end

@implementation DYYYFloatDiagController

- (void)loadView {
    // 穿透容器：触摸只认扳手 frame，其余自动穿透（pointInside=NO → hitTest 跳过）
    DYYYFloatDiagPassView *v = [[DYYYFloatDiagPassView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    v.backgroundColor = UIColor.clearColor;
    v.opaque = NO;
    v.userInteractionEnabled = YES;
    self.view = v;
    _passView = v;
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
    self.passView.wrenchButton = wrench;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (CGRectGetMidX(self.wrenchButton.frame) <= 1) {
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

- (UIViewController *)dyyy_topPresenter {
    UIViewController *presenter = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.hidden || w.windowLevel != UIWindowLevelNormal) continue;
        UIViewController *root = w.rootViewController;
        while (root.presentedViewController) root = root.presentedViewController;
        presenter = root;
        break;
    }
    return presenter;
}

- (void)tapWrench {
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"DYYY 诊断"
                                                                 message:nil
                                                          preferredStyle:UIAlertControllerStyleActionSheet];
    void (^work)(UIViewController *) = ^(UIViewController *p) {
        [DYYYDiagnostics exportDiagnosticsBundleFromViewController:p];
    };
    void (^runAfterDismiss)(void) = ^{
        UIViewController *p = [self dyyy_topPresenter];
        if (p.presentedViewController) {
            [p dismissViewControllerAnimated:YES completion:^{ work(p); }];
        } else {
            work(p);
        }
    };
    [menu addAction:[UIAlertAction actionWithTitle:@"导出诊断包" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        runAfterDismiss();
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"导出日志" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        UIViewController *p = [self dyyy_topPresenter];
        [DYYYDiagnostics exportRuntimeLogFromViewController:p];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"环境自检" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        UIViewController *p = [self dyyy_topPresenter];
        [DYYYDiagnostics showAuditReportFromViewController:p];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"清空日志" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        UIViewController *p = [self dyyy_topPresenter];
        [DYYYDiagnostics clearRuntimeLogFromViewController:p];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView = self.wrenchButton;
    menu.popoverPresentationController.sourceRect = self.wrenchButton.bounds;
    [self presentViewController:menu animated:YES completion:nil];
}

@end
