//
//  DYYYFullscreenCore.m
//  DYYY
//
//  视频全屏几何核心 —— 三层：几何拦截 / 表撑高 / 容器补钉。
//
//  这一版是重写，不是打补丁。三条设计原则来自行为对照：
//
//  1. 单一写入通道
//     全项目只有一个全局 UIView setFrame: 钩子，按「写入方身份」分派。
//     不按视图在哪棵树里 —— 归属是写入方自己的身份，不会串台。
//
//  2. 只回答、不改写
//     行高与 HUD 都先取「表撑高前的原高」，拿不到就放行。
//     于是「没被撑高的表」（聊天页、搜索页）自动出圈，不需要页面特判。
//
//  3. 位置补偿只用 transform
//     约束继续管理尺寸，transform 补视觉偏移；改 frame 必成环。
//
//  为什么必须「写入时拦截」而不是事后纠正：
//     九份导出的统计里，写入时拦截承担 95% 以上的修正量；
//     改成事后纠正等于把上百次修正压给布局回合，必然可见跳动。
//

#import "DYYYFullscreenCore.h"
#import "AwemeHeaders.h"
#import <objc/runtime.h>
#import <math.h>

// 竖屏比例门槛：高/宽达到这个值才拉满整屏。
// 图文、横屏、低比例竖屏拉满会 aspect-fill 过裁，只保持容器自然满幅。
static const CGFloat kDYYYCoverAspectMin = 1.70;
static const long long kDYYYAwemeTypeImage = 68;
// 表高至少要到容器的这个比例才认作「已排好、只差一个底栏」，排除布局早期半成品。
static const CGFloat kDYYYMinHeightRatio = 0.5;
// 从 HUD 往上找视频表的最大层数。
static const NSUInteger kDYYYAncestorLimit = 8;

// 撑高前的表高。挂在表上，既是还原依据，也是 HUD 的钉位目标。
static char kDYYYOriginalHeightKey;
// 所有撑高过的表（弱引用），供关闭开关时立即还原。
static NSHashTable *gDYYYStretchedTables;

// 命中统计
static NSUInteger gDYYYHUDWrites;
static NSUInteger gDYYYHUDLayoutFallback;
static NSUInteger gDYYYTableWrites;
static NSUInteger gDYYYPinWillDisplay;
static NSUInteger gDYYYPinLayout;
static NSUInteger gDYYYMoveWrites;
BOOL DYYYFullscreenCoreOn(void) {
    return DYYYGetBool(@"DYYYEnableFullScreen");
}

#pragma mark - 类缓存
static Class DYYYMergeClass(void) {
    static Class cls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cls = NSClassFromString(@"AWEDPlayerViewController_Merge"); });
    return cls;
}
static Class DYYYInteractionClass(void) {
    static Class cls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cls = NSClassFromString(@"AWEPlayInteractionViewController"); });
    return cls;
}
static Class DYYYTableClass(void) {
    static Class cls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ cls = NSClassFromString(@"AWEFeedDataSafeTableView"); });
    return cls;
}

#pragma mark - Cell 几何

// 往上找 UITableViewCellContentView，最多 12 层。
static UIView *DYYYCellContentView(UIView *view) {
    static Class contentCls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ contentCls = NSClassFromString(@"UITableViewCellContentView"); });
    if (!contentCls) return nil;
    for (NSUInteger i = 0; view && i < 12; i++) {
        if ([view isKindOfClass:contentCls]) return view;
        view = view.superview;
    }
    return nil;
}

// 视频所在 cell 的内容视图高度 = 视频要铺满的目标。
static CGFloat DYYYFullCellHeight(UIView *view) {
    UIView *contentView = DYYYCellContentView(view.superview);
    return contentView ? CGRectGetHeight(contentView.bounds) : 0.0;
}

#pragma mark - 第 1 层：视频容器目标

// 拉满整屏只对比例达标的竖屏视频做。
static BOOL DYYYMergeCanCoverScreen(UIView *view) {
    Class mergeClass = DYYYMergeClass();
    UIResponder *owner = view.nextResponder;
    if (!mergeClass || ![owner isKindOfClass:mergeClass]) return NO;
    AWEDPlayerViewController_Merge *merge = (AWEDPlayerViewController_Merge *)owner;
    AWEAwemeModel *model = merge.model;
    if ([model respondsToSelector:@selector(awemeType)] && model.awemeType == kDYYYAwemeTypeImage) return NO;
    if ([merge respondsToSelector:@selector(hasInlandscape)] && merge.hasInlandscape) return NO;
    if ([merge respondsToSelector:@selector(isInLandscapeFeedStatus)] && [merge isInLandscapeFeedStatus]) return NO;
    AWEVideoModel *video = [model respondsToSelector:@selector(video)] ? model.video : nil;
    double width = [video respondsToSelector:@selector(width)] ? video.width.doubleValue : 0.0;
    double height = [video respondsToSelector:@selector(height)] ? video.height.doubleValue : 0.0;
    // 宽或高为 0：model 还没就绪，按比例达标处理，等下一轮补算。
    return width <= 0.0 || height <= 0.0 || (height / width) >= kDYYYCoverAspectMin;
}
CGRect DYYYFullscreenContainerTarget(id view) {
    UIView *v = (UIView *)view;
    if (!DYYYFullscreenCoreOn()) return CGRectNull;

    // 作用域只到主窗口：画中画/横屏播放器自带一整套同样的层级，
    // 钉成满幅会把小窗撑成盖住整页的全屏播放器。
    UIWindow *window = v.window;
    if (window && window.windowLevel != UIWindowLevelNormal) return CGRectNull;
    UIView *parent = v.superview;
    CGFloat width = CGRectGetWidth(parent.bounds);
    CGFloat height = CGRectGetHeight(parent.bounds);
    if (width <= 0.0 || height <= 0.0) return CGRectNull;
    if (DYYYMergeCanCoverScreen(v)) {
        CGFloat full = DYYYFullCellHeight(v);
        if (full > height) height = full;
    }
    return CGRectMake(0.0, 0.0, width, height);
}
BOOL DYYYFullscreenRectsClose(CGRect lhs, CGRect rhs) {
    return fabs(CGRectGetMinX(lhs) - CGRectGetMinX(rhs)) <= kDYYYTolerance
        && fabs(CGRectGetMinY(lhs) - CGRectGetMinY(rhs)) <= kDYYYTolerance
        && fabs(CGRectGetWidth(lhs) - CGRectGetWidth(rhs)) <= kDYYYTolerance
        && fabs(CGRectGetHeight(lhs) - CGRectGetHeight(rhs)) <= kDYYYTolerance;
}

#pragma mark - 第 2 层：表撑高
UIView *DYYYFullscreenTableForView(id view) {
    UIView *v = (UIView *)view;
    Class tableCls = DYYYTableClass();
    if (!tableCls) return nil;
    UIView *ancestor = v.superview;
    for (NSUInteger i = 0; ancestor && i < kDYYYAncestorLimit; i++, ancestor = ancestor.superview) {
        if ([ancestor isKindOfClass:tableCls]) return ancestor;
    }
    return nil;
}
NSNumber *DYYYFullscreenTableOriginalHeight(id table) {
    UIView *tbl = (UIView *)table;
    return objc_getAssociatedObject(tbl, &kDYYYOriginalHeightKey);
}
CGRect DYYYFullscreenTableAdjust(id tableObj, CGRect frame, CGFloat target) {
    UITableView *table = (UITableView *)tableObj;
    if (!table) return CGRectNull;
    if (!DYYYFullscreenCoreOn()) {
        // 关闭后一律放行，抖音写什么就是什么；标记清掉以免 HUD 继续被钉。
        objc_setAssociatedObject(table, &kDYYYOriginalHeightKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return CGRectNull;
    }
    CGFloat current = CGRectGetHeight(frame);
    // 容器不比来意更高 → 这张表没被底栏压缩过（搜索页、好友聊天页就是这种），
    // 不在作用域内；高度不到容器一半 → 布局早期的半成品，记下它会把 HUD 钉错位置。
    if (!isfinite(target) || !isfinite(current)
        || target <= 0.0
        || current >= target - kDYYYTolerance
        || current < target * kDYYYMinHeightRatio) {
        return CGRectNull;
    }
    if (!objc_getAssociatedObject(table, &kDYYYOriginalHeightKey)) {
        objc_setAssociatedObject(table, &kDYYYOriginalHeightKey, @(current),
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (!gDYYYStretchedTables) gDYYYStretchedTables = [NSHashTable weakObjectsHashTable];
        [gDYYYStretchedTables addObject:table];
    }
    frame.size.height = target;
    return frame;
}

#pragma mark - 第 2 层：行高
double DYYYFullscreenRowHeight(id tableObj, double nativeHeight) {
    UITableView *table = (UITableView *)tableObj;
    if (!DYYYFullscreenCoreOn() || !NSThread.isMainThread || !table) return nativeHeight;
    NSNumber *original = DYYYFullscreenTableOriginalHeight(table);
    CGFloat target = CGRectGetHeight(table.bounds);
    // 拿不到原高 → 这张表没被撑高过 → 不在作用域，回答原生值。
    if (!original || !isfinite(nativeHeight) || !isfinite(target)
        || nativeHeight <= 0.0 || target <= original.doubleValue + kDYYYTolerance) {
        return nativeHeight;
    }
    // 只统一「整页行」：原生特殊行、自动尺寸、未就绪尺寸继续用原返回值。
    if (fabs(nativeHeight - original.doubleValue) > kDYYYTolerance
        && fabs(nativeHeight - target) > kDYYYTolerance) {
        return nativeHeight;
    }
    return target;
}

#pragma mark - 第 2 层：HUD 钉位
CGRect DYYYFullscreenHUDAdjust(id view, CGRect frame) {
    UIView *v = (UIView *)view;
    if (!DYYYFullscreenCoreOn()) return CGRectNull;
    UIView *table = DYYYFullscreenTableForView(v);
    if (!table) return CGRectNull;
    NSNumber *original = DYYYFullscreenTableOriginalHeight(table);
    // 拿不到原高 → 这页不在作用域，完全放行。
    // 好友聊天页就是这种：表没被撑高过，HUD 本来就该跟着页面走。
    if (!original) return CGRectNull;
    CGFloat pinned = original.doubleValue;
    if (!isfinite(pinned) || pinned <= 0.0) return CGRectNull;
    // 没超过原高 → 原生缩小态，放行。
    if (CGRectGetHeight(frame) <= pinned + kDYYYTolerance) return CGRectNull;
    frame.origin.y = 0.0;
    frame.size.height = pinned;
    gDYYYHUDWrites++;
    return frame;
}

#pragma mark - 第 3 层：容器补钉
BOOL DYYYFullscreenPinContainer(id mergeObj) {
    UIViewController *merge = (UIViewController *)mergeObj;
    if (!DYYYFullscreenCoreOn()) return NO;
    UIView *view = merge.viewIfLoaded;
    if (!view) return NO;
    CGRect target = DYYYFullscreenContainerTarget(view);
    if (CGRectIsNull(target) || DYYYFullscreenRectsClose(view.frame, target)) return NO;

    // 钉位目标恒在原点，所以来意的 origin 不在原点就是有人要把视频挪走
    // （评论区缩放是唯一来源），单独计数便于诊断。
    if (fabs(CGRectGetMinX(view.frame)) > kDYYYTolerance
        || fabs(CGRectGetMinY(view.frame)) > kDYYYTolerance) {
        gDYYYMoveWrites++;
    }
    view.frame = target;
    return YES;
}

#pragma mark - 统计
NSString *DYYYFullscreenStats(void) {
    return [NSString stringWithFormat:
            @"HUD写入=%lu HUD布局后兜底=%lu 表补正=%lu "
             "容器willDisplay=%lu 容器布局后=%lu 挪动被拦=%lu 已撑高表=%lu",
            (unsigned long)gDYYYHUDWrites, (unsigned long)gDYYYHUDLayoutFallback,
            (unsigned long)gDYYYTableWrites,
            (unsigned long)gDYYYPinWillDisplay, (unsigned long)gDYYYPinLayout,
            (unsigned long)gDYYYMoveWrites,
            (unsigned long)gDYYYStretchedTables.allObjects.count];
}

// 供 .xm 侧递增用（Logos 块里不能直接改 static 变量）。
void DYYYFullscreenNotePin(BOOL willDisplay) {
    if (willDisplay) gDYYYPinWillDisplay++;
    else gDYYYPinLayout++;
}
void DYYYFullscreenNoteTableWrite(void) {
    gDYYYTableWrites++;
}
void DYYYFullscreenNoteHUDLayoutFallback(void) {
    gDYYYHUDLayoutFallback++;
}

// 关闭开关时立刻把表高还回去，不必等抖音下一次写 frame。
void DYYYFullscreenRestoreTables(void) {
    for (UITableView *table in gDYYYStretchedTables.allObjects) {
        NSNumber *original = DYYYFullscreenTableOriginalHeight(table);
        if (!original) continue;
        objc_setAssociatedObject(table, &kDYYYOriginalHeightKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        CGRect frame = table.frame;
        frame.size.height = original.doubleValue;
        table.frame = frame;
    }
    [gDYYYStretchedTables removeAllObjects];
}

// ===== 背景色延伸（非满屏视频的黑边）=====

//

// 诊断包实证（DYDebug-20261122-062737，首页横屏视频）：

//   cell contentView 428x926   ← 满高

//   外层 UIView       926      ← 我们钉满的容器

//   TTPlayerView      843      ← 原生 player view，装视频画面

//   TTMetalViewVP     240.8    ← 实际画面（16:9 比例 fit）

//

// 容器 926、内容 843，底部差 83 —— 那段空隙就是黑边来源。

// 抖音自己会用 playerBackgroundView 的颜色去填，但它只填原生那一层；

// 我们把容器钉高之后，露出来的那层祖先没人管。

//

// 做法（行为对照的机制，不是抄代码）：

//   1. 从播放器视图往上，找第一个「高度超过它内容底边」的祖先 —— 那层才是会露出来的

//   2. 把它的 backgroundColor 设成播放器原生背景色

//   3. 首次接管时存下原值，关闭全屏时按标记还原

//

// 图文页要排除：图文 cell 里嵌套的那套播放器 alpha=0，若让它也涂色，

// 会用黑底把图文渐变的末色盖掉（行为对照里记录过这个「偶发」现象）。
static char kDYYYBackdropAppliedKey;
static char kDYYYBackdropCanvasKey;

// 从 anchor 往上找第一层「比内容底边更高」的祖先，最多到 cell contentView。
static UIView *DYYYBackdropCanvas(UIView *anchor) {
    if (!anchor) return nil;
    static Class sContentClass;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ sContentClass = NSClassFromString(@"UITableViewCellContentView"); });
    for (UIView *ancestor = anchor.superview; ancestor; ancestor = ancestor.superview) {
        CGRect rect = [anchor convertRect:anchor.bounds toView:ancestor];
        if (CGRectGetHeight(ancestor.bounds) > CGRectGetMaxY(rect) + 0.5) return ancestor;
        if (sContentClass && [ancestor isKindOfClass:sContentClass]) break;
    }
    return nil;
}

// 按标记还原所有接管过的层（不假设是哪一层，承载层会随布局变化）。
static void DYYYRestoreBackdrop(UIView *anchor, UIView *except) {
    if (!anchor) return;
    UIView *ancestor = anchor.superview;
    for (NSUInteger i = 0; ancestor && i < 12; i++, ancestor = ancestor.superview) {
        if (ancestor == except) continue;
        id baseline = objc_getAssociatedObject(ancestor, &kDYYYBackdropCanvasKey);
        if (!baseline) continue;
        ancestor.backgroundColor = (baseline == [NSNull null]) ? nil : (UIColor *)baseline;
        objc_setAssociatedObject(ancestor, &kDYYYBackdropCanvasKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

// 取播放器原生背景色：优先走原生访问入口，缺入口时退回控制器属性。

// 只认「已挂载且可见」的背景层，避免拿到还没落位的空壳。
static UIColor *DYYYPlayerBackdropColor(UIViewController *controller) {
    if (!controller) return nil;
    UIView *backdrop = nil;
    if ([controller respondsToSelector:NSSelectorFromString(@"getPlayerBackgroundView")]) {
        backdrop = [controller performSelector:NSSelectorFromString(@"getPlayerBackgroundView")];
    }
    if (![backdrop isKindOfClass:[UIView class]] &&
        [controller respondsToSelector:NSSelectorFromString(@"playerBackgroundView")]) {
        backdrop = [controller performSelector:NSSelectorFromString(@"playerBackgroundView")];
    }
    if (![backdrop isKindOfClass:[UIView class]]) return nil;
    if (!backdrop.superview || backdrop.hidden) return nil;
    return backdrop.backgroundColor;
}

// 图文页排除：父链上有 RichContentContainerViewController 就不接管。
static BOOL DYYYIsUnderRichContent(UIViewController *controller) {
    static Class sRichClass;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ sRichClass = NSClassFromString(@"RichContentContainerViewController"); });
    if (!sRichClass) return NO;
    for (NSUInteger i = 0; controller && i < 12; i++, controller = controller.parentViewController) {
        if ([controller isKindOfClass:sRichClass]) return YES;
    }
    return NO;
}

// 主入口：涂色或还原。color 为 nil 表示本条不需要延伸（关闭全屏/无背景色）。
void DYYYFullscreenSyncBackdrop(id controllerObj) {
    UIViewController *controller = (UIViewController *)controllerObj;
    if (![NSThread isMainThread] || !controller) return;
    UIView *anchor = controller.viewIfLoaded;
    if (!anchor) return;
    BOOL applied = objc_getAssociatedObject(controller, &kDYYYBackdropAppliedKey) != nil;
    UIColor *color = nil;
    if (DYYYGetBool(@"DYYYEnableFullScreen") && !DYYYIsUnderRichContent(controller)) {
        color = DYYYPlayerBackdropColor(controller);
    }
    if (!color && !applied) return;   // 绝大多数内容没有原生背景，直接退出
    UIView *canvas = color ? DYYYBackdropCanvas(anchor) : nil;
    DYYYRestoreBackdrop(anchor, canvas);
    if (!canvas) {
        objc_setAssociatedObject(controller, &kDYYYBackdropAppliedKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (!objc_getAssociatedObject(canvas, &kDYYYBackdropCanvasKey)) {
        objc_setAssociatedObject(canvas, &kDYYYBackdropCanvasKey,
                                 canvas.backgroundColor ?: (id)[NSNull null],
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (![canvas.backgroundColor isEqual:color]) canvas.backgroundColor = color;
    objc_setAssociatedObject(controller, &kDYYYBackdropAppliedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
