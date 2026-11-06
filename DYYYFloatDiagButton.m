#import "DYYYFloatDiagButton.h"
#import "AwemeHeaders.h"
#import "DYYYToast.h"

static DYYYFloatDiagButton *_shared = nil;

@implementation DYYYFloatDiagButton

+ (instancetype)sharedButton {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        _shared = [super buttonWithType:UIButtonTypeSystem];
        _shared.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.85];
        _shared.layer.cornerRadius = 22;
        _shared.layer.borderWidth = 1;
        _shared.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.25].CGColor;
        _shared.tintColor = UIColor.whiteColor;
        _shared.titleLabel.font = [UIFont boldSystemFontOfSize:20];
        [_shared setTitle:@"🔧" forState:UIControlStateNormal];
        _shared.frame = CGRectMake(0, 0, 44, 44);
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:_shared action:@selector(dyyy_handlePan:)];
        [_shared addGestureRecognizer:pan];
    });
    return _shared;
}

+ (BOOL)isDiagEntryEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYDiagEntryEnabled"];
}

+ (void)attachToWindowIfNeeded:(UIWindow *)window {
    if (!window) return;
    if (![self isDiagEntryEnabled]) { [self removeFromWindowIfPresent]; return; }
    if (_shared.superview == window) return;
    [_shared removeFromSuperview];
    // 初始位置：右下角，避开底部安全区
    UIWindow *w = window;
    CGFloat x = w.bounds.size.width - 60;
    CGFloat y = w.bounds.size.height - 140;
    _shared.frame = CGRectMake(x, y, 44, 44);
    [w addSubview:_shared];
}

+ (void)removeFromWindowIfPresent {
    [_shared removeFromSuperview];
}

- (instancetype)initWithCoder:(NSCoder *)coder { self = [super initWithCoder:coder]; return self; }

- (void)dyyy_handlePan:(UIPanGestureRecognizer *)pan {
    CGPoint t = [pan translationInView:self.superview];
    if (pan.state == UIGestureRecognizerStateBegan || pan.state == UIGestureRecognizerStateChanged) {
        CGRect f = self.frame;
        f.origin.x += t.x;
        f.origin.y += t.y;
        // 吸边约束在窗口范围内
        if (self.superview) {
            CGFloat maxX = self.superview.bounds.size.width - f.size.width;
            CGFloat maxY = self.superview.bounds.size.height - f.size.height;
            f.origin.x = MIN(MAX(f.origin.x, 0), maxX);
            f.origin.y = MIN(MAX(f.origin.y, 0), maxY);
        }
        self.frame = f;
        [pan setTranslation:CGPointZero inView:self.superview];
    } else if (pan.state == UIGestureRecognizerStateEnded) {
        // 松手不弹菜单（拖动结束误触保护）
    }
}

- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [super touchesEnded:touches withEvent:event];
    UITouch *touch = [touches anyObject];
    CGPoint loc = [touch locationInView:self];
    if (![self pointInside:loc withEvent:event]) return;
    if (fabs(loc.x - self.bounds.size.width/2) > 18 || fabs(loc.y - self.bounds.size.height/2) > 18) return;
    // 单击弹菜单
    UIViewController *presenter = nil;
    for (UIWindow *w in [UIApplication sharedApplication].windows) {
        if (w.hidden || w.windowLevel != UIWindowLevelNormal) continue;
        UIViewController *root = w.rootViewController;
        while (root.presentedViewController) root = root.presentedViewController;
        presenter = root;
        break;
    }
    if (!presenter) return;
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"DYYY 诊断"
                                                                 message:nil
                                                          preferredStyle:UIAlertControllerStyleActionSheet];
    [menu addAction:[UIAlertAction actionWithTitle:@"导出诊断包" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        UIViewController *p = [[[UIApplication sharedApplication] keyWindow] rootViewController];
        while (p.presentedViewController) p = p.presentedViewController;
        [DYYYDiagnostics exportDiagnosticsBundleFromViewController:p];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"导出日志" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        UIViewController *p = [[[UIApplication sharedApplication] keyWindow] rootViewController];
        while (p.presentedViewController) p = p.presentedViewController;
        [DYYYDiagnostics exportRuntimeLogFromViewController:p];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"环境自检" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        UIViewController *p = [[[UIApplication sharedApplication] keyWindow] rootViewController];
        while (p.presentedViewController) p = p.presentedViewController;
        [DYYYDiagnostics showAuditReportFromViewController:p];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"清空日志" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        UIViewController *p = [[[UIApplication sharedApplication] keyWindow] rootViewController];
        while (p.presentedViewController) p = p.presentedViewController;
        [DYYYDiagnostics clearRuntimeLogFromViewController:p];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView = presenter.view;
    menu.popoverPresentationController.sourceRect = CGRectMake(CGRectGetMidX(presenter.view.bounds), CGRectGetMidY(presenter.view.bounds), 1, 1);
    [presenter presentViewController:menu animated:YES completion:nil];
}

@end
