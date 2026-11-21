//
//  DYYYFullscreenChromeHooks.xm
//  DYYY
//
//  视频全屏的页面装饰层钩子 —— 撑高之后的连带影响。
//
//  分五组：
//    · 图文：缩放抑制 / 媒体居中 / 渐变拉伸 / 溢出放开
//    · 卡片：底边约束收短 + 背景条取样（特殊卡 / 音乐卡 / POI / 文章）
//    · 直播预览：chrome 抬回原位
//    · 视频渐变：压暗层撑满
//    · 顶部遮罩：全屏时隐藏
//
//  所有挂载点在 %ctor 里先验证 selector 存在才装，避免挂到一半。
//  第三方框架（文章正文在 AWESearchFramework）晚于插件加载，用 dyld 回调补装。
//

#import "DYYYFullscreenChrome.h"
#import "DYYYFullscreenCore.h"
#import "AwemeHeaders.h"
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>

#pragma mark - 图文

%hook RichContentContainerViewController

// 全屏时一律不缩小：图文跟着视频一起铺满，缩小态会把内容压回原高。
// 放行走裸 %orig，不重新编组参数 —— class-dump 把 insets 折叠成 (struct)，
// 不重编组就不依赖那个推断。
- (void)updateShrinkState:(BOOL)shrink insets:(UIEdgeInsets)insets animated:(BOOL)animated {
    if (shrink && DYYYFullscreenCoreOn()) {
        DYYYChromeSuppressRichShrink(self);
        return;
    }
    %orig;
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (!DYYYFullscreenCoreOn()) return;
    UIView *view = self.viewIfLoaded;
    if (!view) return;
    DYYYChromeAllowRichOverflow(view);
}

%end

// 图文媒体：原生把 transform 写成缩放态；全屏时按 Cell 重新居中。
// Swift 嵌套类（BDMultiContentContainer.ImageContentView 等）Logos 不认带点的名字，
// 且 %init 必须写在 %ctor 顶层，不能用循环批量绑定；
// 这里改用 method_setImplementation 直接换实现，三个子类型共用同一个 IMP。
static IMP gDYYYRichMediaTransformIMP;

static void DYYYRichMediaTransformReplacement(id self, SEL _cmd, CGAffineTransform transform) {
    if (gDYYYRichMediaTransformIMP) {
        ((void (*)(id, SEL, CGAffineTransform))gDYYYRichMediaTransformIMP)(self, _cmd, transform);
    }
    UIView *view = (UIView *)self;
    if (![view isKindOfClass:[UIView class]]) return;
    CGAffineTransform target = DYYYChromeRichCenterTransform(view, transform);
    if (!CGAffineTransformEqualToTransform(view.transform, target)) view.transform = target;
}

static void DYYYInstallRichMediaHooks(void) {
    static BOOL installed = NO;
    if (installed) return;
    NSArray<NSString *> *names = @[
        @"BDMultiContentContainer.ImageContentView",
        @"BDMultiContentContainer.LivePhotoContentView",
        @"BDMultiContentContainer.VideoContentView",
    ];
    BOOL any = NO;
    for (NSString *name in names) {
        Class cls = NSClassFromString(name);
        if (!cls) continue;
        Method method = class_getInstanceMethod(cls, @selector(setTransform:));
        if (!method) continue;
        if (!gDYYYRichMediaTransformIMP) gDYYYRichMediaTransformIMP = method_getImplementation(method);
        method_setImplementation(method, (IMP)DYYYRichMediaTransformReplacement);
        any = YES;
    }
    installed = any;
}
%hook AWEKnowledgeGradientView

- (void)layoutSubviews {
    %orig;
    DYYYChromeStretchRichGradient(self);
}

%end

// 图文容器：放开阻挡溢出的裁剪层。
%hook AWEStoryContainerCollectionView

- (void)layoutSubviews {
    %orig;
    if (DYYYFullscreenCoreOn()) DYYYChromeAllowRichOverflow(self);
}

%end

#pragma mark - 卡片

// 特殊卡（Lynx）：内容容器收短 + 背景条取样。
%hook AWESpecialCardTemplateLynxViewController

- (void)viewWillLayoutSubviews {
    %orig;
    if (!DYYYFullscreenCoreOn()) return;
    UIView *view = self.viewIfLoaded;
    if (!view) return;
    CGFloat inset = DYYYChromeCardInset(view);
    DYYYChromeFitCard(view, inset, DYYYCardTypeSpecial);
    DYYYChromeSyncCardBackdrop(view.superview ?: view, inset, DYYYCardTypeSpecial);
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (!DYYYFullscreenCoreOn()) return;
    UIView *view = self.viewIfLoaded;
    if (!view) return;
    CGFloat inset = DYYYChromeCardInset(view);
    DYYYChromeFitCard(view, inset, DYYYCardTypeSpecial);
    DYYYChromeSyncCardBackdrop(view.superview ?: view, inset, DYYYCardTypeSpecial);
    DYYYChromeRequestBackdropSample(view.superview ?: view);
}

- (void)hunterContainerDidFinishLoadWithURL:(id)url {
    %orig;
    UIView *view = self.viewIfLoaded;
    if (view) DYYYChromeRequestBackdropSample(view.superview ?: view);
}

%end

// 特殊卡（原生面板）
%hook AWESpecialCardTemplateNativeViewController

- (void)attachPanelViewControllerIfNeeded {
    %orig;
    if (!DYYYFullscreenCoreOn()) return;
    UIView *view = self.viewIfLoaded;
    if (!view) return;
    CGFloat inset = DYYYChromeCardInset(view);
    DYYYChromeFitCard(view, inset, DYYYCardTypeSpecial);
}

- (void)viewWillLayoutSubviews {
    %orig;
    if (!DYYYFullscreenCoreOn()) return;
    UIView *view = self.viewIfLoaded;
    if (!view) return;
    DYYYChromeFitCard(view, DYYYChromeCardInset(view), DYYYCardTypeSpecial);
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (!DYYYFullscreenCoreOn()) return;
    UIView *view = self.viewIfLoaded;
    if (!view) return;
    CGFloat inset = DYYYChromeCardInset(view);
    DYYYChromeFitCard(view, inset, DYYYCardTypeSpecial);
    DYYYChromeSyncCardBackdrop(view.superview ?: view, inset, DYYYCardTypeSpecial);
}

%end

// 换卡前清掉自己的背景条，避免旧取样贴到新内容上。
%hook AWESpecialCardTemplatePureCell

- (void)configureWithModel:(id)model {
    if (!DYYYFullscreenCoreOn()) { %orig; return; }
    DYYYChromeSyncCardBackdrop(self.contentView, 0.0, DYYYCardTypeSpecial);
    %orig;
}

%end

// POI 动态卡
%hook AWEFeedPOIDynamicCardCellViewController

- (void)viewWillLayoutSubviews {
    %orig;
    if (!DYYYFullscreenCoreOn()) return;
    UIView *view = self.viewIfLoaded;
    if (view) DYYYChromeFitCard(view, DYYYChromeCardInset(view), DYYYCardTypeSpecial);
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (!DYYYFullscreenCoreOn()) return;
    UIView *view = self.viewIfLoaded;
    if (!view) return;
    CGFloat inset = DYYYChromeCardInset(view);
    DYYYChromeFitCard(view, inset, DYYYCardTypeSpecial);
    DYYYChromeSyncCardBackdrop(view.superview ?: view, inset, DYYYCardTypeSpecial);
}

%end

// 音乐卡：Swift 类，类名带模块前缀，同样用 method_setImplementation。
static IMP gDYYYMusicCardWillLayoutIMP;
static IMP gDYYYMusicCardDidLayoutIMP;

static void DYYYMusicCardWillLayoutReplacement(id self, SEL _cmd) {
    if (gDYYYMusicCardWillLayoutIMP) ((void (*)(id, SEL))gDYYYMusicCardWillLayoutIMP)(self, _cmd);
    if (!DYYYFullscreenCoreOn()) return;
    UIView *view = [self respondsToSelector:@selector(viewIfLoaded)] ? [self viewIfLoaded] : nil;
    if (view) DYYYChromeFitCard(view, DYYYChromeCardInset(view), DYYYCardTypeMusic);
}

static void DYYYMusicCardDidLayoutReplacement(id self, SEL _cmd) {
    if (gDYYYMusicCardDidLayoutIMP) ((void (*)(id, SEL))gDYYYMusicCardDidLayoutIMP)(self, _cmd);
    if (!DYYYFullscreenCoreOn()) return;
    UIView *view = [self respondsToSelector:@selector(viewIfLoaded)] ? [self viewIfLoaded] : nil;
    if (!view) return;
    CGFloat inset = DYYYChromeCardInset(view);
    DYYYChromeFitCard(view, inset, DYYYCardTypeMusic);
    DYYYChromeSyncCardBackdrop(view.superview ?: view, inset, DYYYCardTypeMusic);
}

static void DYYYInstallMusicCardHooks(void) {
    static BOOL installed = NO;
    if (installed) return;
    Class cls = NSClassFromString(@"AWEMusicStreamingSwiftImpl.MusicCardViewController");
    if (!cls) return;
    Method will = class_getInstanceMethod(cls, @selector(viewWillLayoutSubviews));
    Method did = class_getInstanceMethod(cls, @selector(viewDidLayoutSubviews));
    if (will) {
        gDYYYMusicCardWillLayoutIMP = method_getImplementation(will);
        method_setImplementation(will, (IMP)DYYYMusicCardWillLayoutReplacement);
    }
    if (did) {
        gDYYYMusicCardDidLayoutIMP = method_getImplementation(did);
        method_setImplementation(did, (IMP)DYYYMusicCardDidLayoutReplacement);
    }
    installed = (will || did);
}
#pragma mark - 长文章（第三方框架，晚于插件加载）

static void DYYYArticleInstallHooks(void);

// 文章正文控制器在 AWESearchFramework 里，该框架晚于插件加载；
// 回调在加载器上下文内，只调度到主队列安装。
static void DYYYArticleImageAdded(const struct mach_header *header, intptr_t slide) {
    (void)slide;
    Dl_info info = {0};
    if (!dladdr(header, &info) || !info.dli_fname) return;
    NSString *path = @(info.dli_fname);
    if (![path containsString:@"AWESearchFramework"]) return;
    dispatch_async(dispatch_get_main_queue(), ^{ DYYYArticleInstallHooks(); });
}

// 文章正文在 AWESearchFramework 里，晚于插件加载，且类名不稳定。
// 用 method_setImplementation 直接换实现，不经过 %hook（Logos 无法为运行时类名生成符号）。
static IMP gDYYYArticleLayoutIMP;
static IMP gDYYYArticleModelIMP;

static void DYYYArticleLayoutReplacement(id self, SEL _cmd) {
    if (gDYYYArticleLayoutIMP) ((void (*)(id, SEL))gDYYYArticleLayoutIMP)(self, _cmd);
    if (!DYYYFullscreenCoreOn()) return;
    UIView *view = [self respondsToSelector:@selector(viewIfLoaded)] ? [self viewIfLoaded] : nil;
    if (!view) return;
    CGFloat inset = DYYYChromeCardInset(view);
    DYYYChromeFitCard(view, inset, DYYYCardTypeArticle);
    DYYYChromeSyncCardBackdrop(view.superview ?: view, inset, DYYYCardTypeArticle);
}

static void DYYYArticleModelReplacement(id self, SEL _cmd, id model) {
    if (gDYYYArticleModelIMP) ((void (*)(id, SEL, id))gDYYYArticleModelIMP)(self, _cmd, model);
    UIView *view = [self respondsToSelector:@selector(viewIfLoaded)] ? [self viewIfLoaded] : nil;
    if (view) DYYYChromeRequestBackdropSample(view.superview ?: view);
}
static void DYYYArticleInstallHooks(void) {
    static BOOL installed = NO;
    if (installed) return;
    Class cls = NSClassFromString(@"AWESearchFeedArticleViewController");
    if (!cls) return;

    Method layout = class_getInstanceMethod(cls, @selector(viewDidLayoutSubviews));
    Method update = class_getInstanceMethod(cls, @selector(updateModel:));
    if (!layout && !update) return;
    installed = YES;

    if (layout) {
        gDYYYArticleLayoutIMP = method_getImplementation(layout);
        method_setImplementation(layout, (IMP)DYYYArticleLayoutReplacement);
    }
    if (update) {
        gDYYYArticleModelIMP = method_getImplementation(update);
        method_setImplementation(update, (IMP)DYYYArticleModelReplacement);
    }
}

#pragma mark - 直播预览

%hook AWELivePreStream4LayerContainerView

- (void)layoutSubviews {
    %orig;
    if (DYYYFullscreenCoreOn()) DYYYChromeLiftLiveChrome(self);
}

%end

#pragma mark - 视频渐变与顶部遮罩

%hook AWEGradientView

- (void)layoutSubviews {
    %orig;
    if (DYYYFullscreenCoreOn()) DYYYChromeStretchVideoGradient(self);
}

%end

%hook AWEPlayInteractionViewController

- (void)viewDidLayoutSubviews {
    %orig;
    DYYYChromeHideStatusBarCover(self);
}

%end

#pragma mark - 安装

%ctor {
    DYYYInstallRichMediaHooks();
    DYYYInstallMusicCardHooks();

    // 文章控制器在 AWESearchFramework 里，可能还没加载。
    DYYYArticleInstallHooks();
    _dyld_register_func_for_add_image(DYYYArticleImageAdded);
}
