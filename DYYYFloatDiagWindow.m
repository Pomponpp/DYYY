#import "DYYYFloatDiagWindow.h"
#import "AwemeHeaders.h"
#import "DYYYToast.h"

static DYYYFloatDiagWindow *gDiagWindow = nil;
static DYYYFloatDiagController *gDiagController = nil;

@implementation DYYYFloatDiagWindow

+ (void)install {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        UIWindowScene *scene = nil;
        if (@available(iOS 13.0, *)) {
            for (UIScene *sc in [UIApplication sharedApplication].connectedScenes) {
                if ([sc isKindOfClass:[UIWindowScene class]] &&
                    sc.activationState == UISceneActivationStateForegroundActive) {
                    scene = (UIWindowScene *)sc;
                    break;
                }
            }
        }
        if (scene) {
            gDiagWindow = [[DYYYFloatDiagWindow alloc] initWithWindowScene:scene];
        } else {
            gDiagWindow = [[DYYYFloatDiagWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        }
        gDiagWindow.backgroundColor = UIColor.clearColor;
        gDiagWindow.opaque = NO;
        gDiagWindow.windowLevel = UIWindowLevelAlert + 100000.0;
        gDiagWindow.hidden = YES;                 // 待命，不 makeKeyAndVisible
        gDiagController = [DYYYFloatDiagController new];
        gDiagWindow.rootViewController = gDiagController;
    });
}

+ (void)setEnabled:(BOOL)on {
    [self install];
    gDiagWindow.hidden = !on;                    // 只翻 hidden，不重建、不抢焦点
}

// 窗口层直接拒绝非扳手区域的命中测试——事件根本不进视图树，
// 高等级全屏窗口不会卷入抖音的 hitTest/layout 链（卡死根因）。
- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event {
    UIButton *w = gDiagController.wrenchButton;
    if (!w || w.hidden) return NO;
    CGPoint p = [w convertPoint:point fromView:self];
    return [w pointInside:p withEvent:event];
}

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    if (hit == self || hit == self.rootViewController.view) return nil;
    return hit;
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
    [wrench addTarget:self action:@selector(tapWrench) forControlEvents:UIControlEventTouchUpInside];
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(panWrench:)];
    [wrench addGestureRecognizer:pan];
    [self.view addSubview:wrench];
    self.wrenchButton = wrench;
    CGFloat x = self.view.bounds.size.width - 48;
    CGFloat y = self.view.bounds.size.height - 140;
    wrench.center = CGPointMake(x, y);
}

- (void)panWrench:(UIPanGestureRecognizer *)pan {
    CGPoint t = [pan translationInView:self.view];
    if (pan.state == UIGestureRecognizerStateBegan || pan.state == UIGestureRecognizerStateChanged) {
        CGPoint c = self.wrenchButton.center;
        c.x += t.x; c.y += t.y;
        c.x = MIN(MAX(c.x, 24), self.view.bounds.size.width - 24);
        c.y = MIN(MAX(c.y, 24), self.view.bounds.size.height - 24);
        self.wrenchButton.center = c;
        [pan setTranslation:CGPointZero inView:self.view];
    }
}

- (void)tapWrench {
    UIAlertController *menu = [UIAlertController alertControllerWithTitle:@"DYYY 诊断"
                                                                 message:nil
                                                          preferredStyle:UIAlertControllerStyleActionSheet];
    // presenter 恒为自己的 rootVC——导出链路一次都不碰抖音的 VC 层级
    __weak __typeof(self) weakSelf = self;
    [menu addAction:[UIAlertAction actionWithTitle:@"导出诊断包" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        [DYYYDiagnostics exportDiagnosticsBundleFromViewController:weakSelf];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"导出日志" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        [DYYYDiagnostics exportRuntimeLogFromViewController:weakSelf];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"环境自检" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        [DYYYDiagnostics showAuditReportFromViewController:weakSelf];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"清空日志" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
        [DYYYDiagnostics clearRuntimeLogFromViewController:weakSelf];
    }]];
    [menu addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    menu.popoverPresentationController.sourceView = self.wrenchButton;
    menu.popoverPresentationController.sourceRect = self.wrenchButton.bounds;
    [self presentViewController:menu animated:YES completion:nil];
}

@end
