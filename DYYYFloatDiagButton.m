#import "DYYYFloatDiagButton.h"
#import "AwemeHeaders.h"
#import "DYYYToast.h"

static DYYYFloatDiagButton *_shared = nil;

@implementation DYYYFloatDiagButton

+ (instancetype)sharedButton {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        _shared = [[DYYYFloatDiagButton alloc] initWithFrame:CGRectMake(0, 0, 44, 44)];
    });
    return _shared;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.85];
        self.layer.cornerRadius = 22;
        self.layer.borderWidth = 1;
        self.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.25].CGColor;
        self.tintColor = UIColor.whiteColor;
        self.titleLabel.font = [UIFont boldSystemFontOfSize:20];
        [self setTitle:@"🔧" forState:UIControlStateNormal];
        [self addTarget:self action:@selector(dyyy_tapAction) forControlEvents:UIControlEventTouchUpInside];
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dyyy_handlePan:)];
        [self addGestureRecognizer:pan];
    }
    return self;
}

+ (BOOL)isDiagEntryEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYDiagEntryEnabled"];
}

+ (void)refreshPresence {
    UIWindow *key = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (!w.hidden && w.windowLevel == UIWindowLevelNormal) { key = w; break; }
    }
    [self attachToWindowIfNeeded:key];
}

+ (void)attachToWindowIfNeeded:(UIWindow *)window {
    if (!window) return;
    DYYYFloatDiagButton *btn = [self sharedButton];
    if (![self isDiagEntryEnabled]) { [btn removeFromSuperview]; return; }
    if (btn.superview == window) return;
    [btn removeFromSuperview];
    CGFloat x = window.bounds.size.width - 60;
    CGFloat y = window.bounds.size.height - 140;
    btn.frame = CGRectMake(x, y, 44, 44);
    [window addSubview:btn];
}

+ (void)removeFromWindowIfPresent {
    [_shared removeFromSuperview];
}

- (void)dyyy_handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint t = [pan translationInView:self.superview];
    if (pan.state == UIGestureRecognizerStateBegan || pan.state == UIGestureRecognizerStateChanged) {
        CGRect f = self.frame;
        f.origin.x += t.x;
        f.origin.y += t.y;
        if (self.superview) {
            CGFloat maxX = self.superview.bounds.size.width - f.size.width;
            CGFloat maxY = self.superview.bounds.size.height - f.size.height;
            f.origin.x = MIN(MAX(f.origin.x, 0), maxX);
            f.origin.y = MIN(MAX(f.origin.y, 0), maxY);
        }
        self.frame = f;
        [pan setTranslation:CGPointZero inView:self.superview];
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

- (void)dyyy_tapAction {
    UIViewController *presenter = [self dyyy_topPresenter];
    if (!presenter) return;
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"DYYY 诊断"
                                                                 message:nil
                                                          preferredStyle:UIAlertControllerStyleActionSheet];
    // #36：菜单在场时 topPresenter 会拿到菜单自身——先 dismiss 再执行
    void (^runAfterDismiss)(void (^)(UIViewController *)) = ^(void (^work)(UIViewController *p)) {
        UIViewController *p = [self dyyy_topPresenter];
        if (p.presentedViewController) {
            [p dismissViewControllerAnimated:YES completion:^{ work(p); }];
        } else {
            work(p);
        }
    };
    [menu addAction:[UIAlertAction actionWithTitle:@"导出诊断包" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        runAfterDismiss(^(UIViewController *p) { [DYYYDiagnostics exportDiagnosticsBundleFromViewController:p]; });
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"导出日志" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        runAfterDismiss(^(UIViewController *p) { [DYYYDiagnostics exportRuntimeLogFromViewController:p]; });
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"环境自检" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        runAfterDismiss(^(UIViewController *p) { [DYYYDiagnostics showAuditReportFromViewController:p]; });
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"清空日志" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        runAfterDismiss(^(UIViewController *p) { [DYYYDiagnostics clearRuntimeLogFromViewController:p]; });
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView = presenter.view;
    menu.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(presenter.view.bounds), CGRectGetMidY(presenter.view.bounds), 1, 1);
    [presenter presentViewController:menu animated:YES completion:nil];
}

@end
