//
//  DYYYFullscreenCoordinator.m
//  全屏几何协调：表高 / 行高 / 落点 / 播放器容器。
//
//  四条机制均经过抖音多个版本验证：
//    · 表高唯一写入通道（setFrame: 拦截，不做多点写入）
//    · 建行/落点/翻页七入口同源（先撑高再放行原生）
//    · 行高只"回答"不"改写"
//    · 播放器容器钉满 + HUD 钉回原高
//  这四条是抖音多个版本上试错得出的唯一解，重写等于重新踩坑。
//  来源致谢见 CREDITS.md。
//
//  DYYY 在此基础上做的改动：
//    · 扩展到作品页 / 他人主页，并按页面类型收窄作用域
//    · 接入自有诊断（运行流水、状态指纹）
//    · 底栏透明与 Profile 页面栈判定
//  详见 CREDITS.md。
//

#import "DYYYFullscreenCoordinator.h"
#import "DYYYFullscreenGeometry.h"
#import "DYYYUtils.h"
#import "DYYYFloatingButtonCoordinator.h"
#import "AwemeHeaders.h"
#import <objc/runtime.h>

@interface DYYYFullscreenPlayerState : NSObject
@property(nonatomic, weak) UIViewController *owner;
@property(nonatomic, assign) CGSize layoutWindowSize;
@property(nonatomic, assign) UIEdgeInsets layoutSafeArea;
@property(nonatomic, assign) CGRect nativeFrame;
@property(nonatomic, assign) CGRect lastAppliedFrame;
@property(nonatomic, assign) BOOL hasNativeFrame;
@property(nonatomic, assign) CGSize closedInteractionSize;
@property(nonatomic, assign) CGRect captionWindowFrame;
@property(nonatomic, assign) BOOL hasCaptionFrame;
@property(nonatomic, assign) BOOL captionAdjusted;
@property(nonatomic, assign) CGPoint captionNativeCenter;
@property(nonatomic, assign) CGPoint captionAppliedCenter;
@property(nonatomic, assign) BOOL applying;
@property(nonatomic, assign) BOOL adjusted;
@property(nonatomic, weak) UIWindow *normalWindow;
@property(nonatomic, assign) BOOL mediaHost;
@property(nonatomic, assign) CGRect mediaHostParentBounds;
@property(nonatomic, assign) BOOL bottomBarEnabled;
@property(nonatomic, assign) CGRect nativeHostFrame;
@property(nonatomic, assign) CGRect fullscreenHostFrame;
@property(nonatomic, strong) NSMapTable<UIView *, NSDictionary *> *bottomBackgrounds;
@property(nonatomic, weak) UIView *transparentBottomBar;
@property(nonatomic, assign) BOOL applyingBottomBackground;
@property(nonatomic, assign) BOOL updatingBottomBar;
@end

@implementation DYYYFullscreenPlayerState
@end

@implementation DYYYFullscreenCoordinator
+ (NSString *)buildIdentifier { return @"fullscreen-creator-native-20261024.2"; }
+ (NSString *)contentSourceForController:(UIViewController *)controller {
    // 以当前内容来源为准，不能仅凭它仍挂在首页导航栈中判断。
    for (NSUInteger depth = 0; controller && depth < 8; depth++, controller = controller.parentViewController) {
        if (![controller respondsToSelector:@selector(referString)]) continue;
        NSString *refer = [(AWEPlayInteractionViewController *)controller referString];
        if (refer.length > 0) return refer;
    }
    return nil;
}
+ (BOOL)usesRecommendedLayoutForController:(UIViewController *)controller {
    // 轻量判断：按内容来源白名单回答，无 mediaHost 状态依赖。
    // 首页推荐流（homepage_hot / homepage_hot_container）= 全屏推荐布局；
    // 其他 homepage_*（关注/朋友/商城/直播等）与全部非首页来源保持原生。
    NSString *refer = [self contentSourceForController:controller];
    if (!refer.length) return NO;
    return [refer isEqualToString:@"homepage_hot"] ||
           [refer isEqualToString:@"homepage_hot_container"];
}
+ (BOOL)usesDetailLayoutForController:(UIViewController *)controller {
    Class detailClass = NSClassFromString(@"AWEAwemeDetailTableViewController");
    Class remoteClass = NSClassFromString(@"AFDPlayRemoteFeedTableViewController");
    BOOL detail = NO;
    for (NSUInteger depth = 0; controller && depth < 8; depth++, controller = controller.parentViewController) {
        if (remoteClass && [controller isKindOfClass:remoteClass]) return NO;
        if ([controller isKindOfClass:detailClass]) detail = YES;
    }
    return detail;
}
+ (UIScrollView *)pagingViewForCell:(UIView *)cell {
    for (UIView *view = cell.superview; view; view = view.superview) {
        if ([view isKindOfClass:[UITableView class]] || [view isKindOfClass:[UICollectionView class]]) return (UIScrollView *)view;
    }
    return nil;
}
+ (BOOL)view:(UIView *)view spansWidthOf:(UIView *)container {
    return view && container && container.bounds.size.width > 0 && fabs(view.bounds.size.width - container.bounds.size.width) <= 1;
}
+ (BOOL)usesFullscreenLayoutForController:(UIViewController *)controller {
    Class remoteClass = NSClassFromString(@"AFDPlayRemoteFeedTableViewController");
    BOOL pureMode = NO;
    for (UIViewController *parent = controller; parent; parent = parent.parentViewController) {
        if (remoteClass && [parent isKindOfClass:remoteClass]) return NO;
        if ([parent respondsToSelector:@selector(getPureModeContainerFrame)]) pureMode = YES;
    }
    if (pureMode || [self usesRecommendedLayoutForController:controller] || [self usesDetailLayoutForController:controller]) return YES;
    UIView *view = controller.viewIfLoaded;
    if (!view.window) return NO;
    UIView *cell = [self cellForPlayer:view owner:controller];
    if (![cell isKindOfClass:[UITableViewCell class]] && ![cell isKindOfClass:[UICollectionViewCell class]]) return NO;
    UIScrollView *pager = [self pagingViewForCell:cell];
    if (![self view:cell spansWidthOf:pager] || pager.bounds.size.height <= 0) return NO;
    // 分页能力和实际容器决定是否适配，窗口大小、设备型号不参与分类。
    if (pager.pagingEnabled) return YES;
    for (UIViewController *parent = controller; parent; parent = parent.parentViewController) {
        if ([parent respondsToSelector:@selector(currentVisibleCellIndex)]) return YES;
    }
    return NO;
}
+ (CGRect)frameForPureModeContainer:(UIViewController *)controller proposed:(CGRect)frame {
    if (![NSThread isMainThread] || !DYYYGetBool(@"DYYYEnableFullScreen")) return frame;
    UIView *view = controller.viewIfLoaded;
    if (!view) return frame;
    if (CGRectIsEmpty(frame) || CGRectIsNull(frame) || CGRectIsInfinite(frame) || fabs(frame.size.width - view.bounds.size.width) > 1) return frame;
    CGFloat height = CGRectGetMaxY(view.bounds) - frame.origin.y;
    // 交给原生列表同步计算行高和分页，媒体可延伸到底部清屏控制栏下方。
    if (height > 0) frame.size.height = height;
    return frame;
}
+ (CGFloat)heightForDetailRow:(CGFloat)height table:(UITableView *)table controller:(UIViewController *)controller {
    if (![NSThread isMainThread] || !DYYYGetBool(@"DYYYEnableFullScreen") || ![self usesDetailLayoutForController:controller]) return height;
    // 行高与 UITableView 分页视口使用同一尺寸，预加载时也不扣第二次底栏。
    return height > 0 && table.bounds.size.height > 0 ? table.bounds.size.height : height;
}
// ===== 详情页全屏几何 =====
// 表高唯一写入通道 = AWEFeedDataSafeTableView.setFrame 拦截（写入时拉满+layout 兜底）；
// 行高 = fullCellHeightForNative 纯函数
// 独立回答（锚 = 原生底栏高）。两者无先后依赖、无共享状态——
// 这是修复"表 926 滚 / cell 843 排"错位的关键。
static const CGFloat kDYYYDetailHeightTol = 0.5;
// 行高接管区间：原生行高比窗口矮 1~160pt 视为"扣底栏"型压缩，接管为满视口。
// 上限覆盖机型组合（如 iPad 分屏残留值），下限排除已接管/未就绪。
static const CGFloat kDYYYRowHeightDiffMin = 1.0;
static const CGFloat kDYYYRowHeightDiffMax = 160.0;

// 群聊视频详情页（IM 详情）不在全屏作用域：
// 它原生就是"扣底栏 83"布局，拖进度条时抖音自己把进度容器上移一个底栏
// 给输入栏让位（原生交互）。行高/表高若在这里接管，会与原生让位布局打架
// ——表现为拖动中画面跳起一个底栏高度、出现两条底栏分界线，松手弹回。
// 窗口级 IM 会话判定：递归扫当前窗口可见的 VC 树，同时存在
// "IM 容器族"与"详情表控制器"才判定为聊天系视频页。
// 不依赖 parentViewController 链（实测页面创建早期该链未就绪，
// 逐次实时推理会在 926/843 之间摇摆——这才是拖动"弹"的真因）。
// 结果短暂缓存 0.4s，避免热路径每帧全树扫描。
// 判定自证：每次判定结果变化时打一条（verdict + 命中分支 + 对象 + 子VC数）。
// 目的：导包后一眼看出判定走的哪条路，不再靠推理补全。
static __weak UIViewController *DYYYLastIMLoggedController;
static NSInteger DYYYLastIMLoggedVerdict = -1;

static BOOL DYYYLogIMVerdict(BOOL result, NSString *reason, UIViewController *controller) {
    if (DYYYGetBool(@"DYYYDiagEntryEnabled")) {
        BOOL changed = (DYYYLastIMLoggedController != controller) ||
                       (DYYYLastIMLoggedVerdict != (result ? 1 : 0));
        if (changed) {
            DYYYLastIMLoggedController = controller;
            DYYYLastIMLoggedVerdict = result ? 1 : 0;
            NSLog(@"[DYYY][imdetail] verdict=%d reason=%@ cls=%@ 子VC=%lu",
                  result ? 1 : 0,
                  reason ?: @"?",
                  NSStringFromClass([controller class]),
                  (unsigned long)controller.childViewControllers.count);
        }
    }
    return result;
}

static BOOL DYYYWindowHasIMSession(void) {
    static CFTimeInterval cachedAt = 0;
    static BOOL cachedResult = NO;
    CFTimeInterval now = CACurrentMediaTime();
    if (now - cachedAt < 0.4) return cachedResult;
    cachedAt = now;

    UIWindow *window = [DYYYUtils getActiveWindow];
    if (!window) { cachedResult = NO; return NO; }

    static NSArray *imClasses;
    static Class detailClass;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        imClasses = @[
            NSClassFromString(@"AWEIMMessageBaseViewController"),
            NSClassFromString(@"AWEIMMessageTabRootViewController"),
            NSClassFromString(@"AWEIMChatListViewController"),
            NSClassFromString(@"IESIMInputViewController"),
            NSClassFromString(@"AWEIMFeedVideoQuickReplayInputViewController"),
        ].copy;
        detailClass = NSClassFromString(@"AWEAwemeDetailTableViewController");
    });

    __block BOOL hasIM = NO;
    __block BOOL hasDetail = NO;
    NSMutableArray *queue = [NSMutableArray array];
    if (window.rootViewController) [queue addObject:window.rootViewController];
    NSMutableSet<NSValue *> *seen = [NSMutableSet set];
    NSUInteger guard = 0;
    while (queue.count > 0 && guard++ < 200) {
        id item = queue.firstObject;
        [queue removeObjectAtIndex:0];
        if (![item isKindOfClass:[UIViewController class]]) continue;
        UIViewController *vc = (UIViewController *)item;
        NSValue *key = [NSValue valueWithNonretainedObject:vc];
        if ([seen containsObject:key]) continue;
        [seen addObject:key];

        // 只统计真正挂在窗口上的 VC（Tab 切换后旧 Tab 的 view 不在 window）
        if (vc.isViewLoaded && vc.view.window == window) {
            for (Class cls in imClasses) if (cls && [vc isKindOfClass:cls]) { hasIM = YES; break; }
            if (detailClass && [vc isKindOfClass:detailClass]) hasDetail = YES;
        }
        [queue addObjectsFromArray:vc.childViewControllers];
        if (vc.presentedViewController) [queue addObject:vc.presentedViewController];
        if ([vc isKindOfClass:[UINavigationController class]]) {
            [queue addObjectsFromArray:((UINavigationController *)vc).viewControllers];
        }
        if (hasIM && hasDetail) break;
    }
    cachedResult = (hasIM && hasDetail);
    return cachedResult;
}

+ (BOOL)isIMSessionContext:(UIViewController *)controller {
    // 判定"聊天系视频详情页"（群聊 + 朋友聊天）。
    // 第一判据：窗口级结构快照（一次性、不依赖时序）；
    // 其余为兜底（refer / 父链 / 兄弟），保留以防窗口判定失效。
    if (DYYYWindowHasIMSession()) {
        return DYYYLogIMVerdict(YES, @"window", controller);
    }
    static NSArray *imContainerClasses;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        imContainerClasses = @[
            NSClassFromString(@"AWEIMMessageBaseViewController"),
            NSClassFromString(@"AWEIMMessageTabRootViewController"),
            NSClassFromString(@"AWEIMChatListViewController"),
            NSClassFromString(@"IESIMInputViewController"),
            NSClassFromString(@"AWEIMFeedVideoQuickReplayInputViewController"),
        ].copy;
    });
    for (UIViewController *parent = controller; parent; parent = parent.parentViewController) {
        for (Class cls in imContainerClasses) {
            if (cls && [parent isKindOfClass:cls]) return DYYYLogIMVerdict(YES, @"parent", controller);
        }
        // 子 VC / 兄弟层级：实测 IM 容器与详情页是同级兄弟（同挂一个
        // 导航控制器下），且详情页的子 VC 仅在页面完全就绪后才出现。
        for (UIViewController *child in parent.childViewControllers) {
            for (Class cls in imContainerClasses) {
                if (cls && [child isKindOfClass:cls]) return DYYYLogIMVerdict(YES, @"child/sibling", controller);
            }
        }
        // 同导航栈共存：IM 容器在导航栈里与详情页相邻（从聊天点进视频的 push 链）
        UINavigationController *nav = parent.navigationController;
        if (nav) {
            for (UIViewController *stackVC in nav.viewControllers) {
                for (Class cls in imContainerClasses) {
                    if (cls && [stackVC isKindOfClass:cls]) return DYYYLogIMVerdict(YES, @"navstack", controller);
                }
            }
        }
        if ([parent respondsToSelector:@selector(referString)]) {
            NSString *refer = [(AWEPlayInteractionViewController *)parent referString];
            if (refer.length > 0) {
                NSString *lower = [refer lowercaseString];
                if ([lower isEqualToString:@"chat"] || [lower containsString:@"chat_room"] ||
                    [lower hasPrefix:@"im_"]) return DYYYLogIMVerdict(YES, @"refer", controller);
            }
        }
    }
    return NO;
}

+ (BOOL)isImDetailController:(UIViewController *)controller {
    return [self isIMSessionContext:controller];
}

+ (BOOL)isImDetailView:(id)view {
    // 数据层对象（DataLayer/DataController 等非视图）不在 responder 链上，
    // 无法反查 VC——改读全局标记：IM 详情页生命周期 hook 维护（imDetailActive）。
    if (![view isKindOfClass:[UIView class]]) return [self imDetailActiveOrNavTop];
    UIViewController *controller = [DYYYUtils firstAvailableViewControllerFromView:view];
    return controller ? [self isImDetailController:controller] : [self imDetailActiveOrNavTop];
}

// IM 详情页活跃标记：由 DYYY.xm 的 IMDetail 生命周期 hook 维护。
static NSInteger imDetailActiveCount = 0;
+ (void)setImDetailActive:(BOOL)active {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self setImDetailActive:active]; });
        return;
    }
    imDetailActiveCount += active ? 1 : -1;
    if (imDetailActiveCount < 0) imDetailActiveCount = 0;
}
+ (BOOL)imDetailActive {
    return imDetailActiveCount > 0;
}

// 导航栈实时检测：当前导航栈顶是详情控制器，且其子控制器含群聊快捷回复栏。
// 与生命周期标记互补——数据层/委托容器对象的调用时机可能早于 viewWillAppear
// （标记尚未置位，行高已被 UIKit 缓存进行尺寸），导航栈快照则任何时候都稳定。
+ (BOOL)isImDetailNavTop {
    UIViewController *top = [DYYYUtils topView];
    if (![top isKindOfClass:[UIViewController class]]) return NO;
    if (![self isImDetailController:top]) return NO;
    // 向下钻取导航/Tab 内容，找到实际的详情控制器（topView 可能返回容器）
    return YES;
}

+ (BOOL)imDetailActiveOrNavTop {
    if ([self imDetailActive]) return YES;
    UIViewController *vc = [DYYYUtils topView];
    int depth = 0;
    while (vc && depth++ < 10) {
        if ([self isImDetailController:vc]) return YES;
        UIViewController *next = nil;
        if ([vc isKindOfClass:[UINavigationController class]]) {
            next = ((UINavigationController *)vc).topViewController;
        } else if (vc.presentedViewController) {
            next = vc.presentedViewController;
        } else {
            for (UIViewController *child in vc.childViewControllers) {
                if (child.viewIfLoaded.window) { next = child; break; }
            }
        }
        if (!next || next == vc) break;
        vc = next;
    }
    return NO;
}



// 表写入通道的统一规则（首页表与详情表共用）：
// 返回 CGRectNull = 放行不干预。
// 首页 feed 表撑高：在控制器布局前后调用，让表高变化早于 cell 排版。
// 表在 layoutSubviews 里改高时 cell 已排完，会造成 offset 与 cell 网格错位。
+ (void)syncFeedTableHeight:(UIViewController *)controller {
    if (!controller || !DYYYGetBool(@"DYYYEnableFullScreen") || !NSThread.isMainThread) return;
    if (![controller respondsToSelector:@selector(tableView)]) return;
    UITableView *table = [(id)controller tableView];
    if (!table) return;
    UIView *parent = table.superview;
    if (!parent) return;
    CGFloat target = CGRectGetHeight(parent.bounds);
    if (!isfinite(target) || target <= 0.0) return;

    CGRect frame = table.frame;
    if (fabs(CGRectGetHeight(frame) - target) <= kDYYYDetailHeightTol) return;
    frame.size.height = target;
    table.frame = frame;
}

+ (CGRect)adjustDetailTableFrame:(UIView *)table frame:(CGRect)frame {
    if (!table) return CGRectNull;
    UIView *parent = table.superview;
    CGFloat target = parent ? CGRectGetHeight(parent.bounds) : 0;
    return [self adjustDetailTableFrame:table frame:frame target:target];
}

+ (CGRect)adjustDetailTableFrame:(UIView *)table frame:(CGRect)frame target:(CGFloat)target {
    if (!table) return CGRectNull;
    if (!DYYYGetBool(@"DYYYEnableFullScreen")) {
        // 关闭后一律放行，抖音写什么就是什么。
        return CGRectNull;
    }
    CGFloat current = CGRectGetHeight(frame);
    // 容器不比来意更高 → 这张表没被底栏压缩过（搜索页/好友聊天页），不在作用域；
    // 高度不到容器一半 → 布局早期半成品，不碰。
    if (!isfinite(target) || !isfinite(current) || target <= 0.0
        || current >= target - kDYYYDetailHeightTol
        || current < target * 0.5) {
        return CGRectNull;
    }
    frame.size.height = target;
    return frame;
}


// 行高纯函数入口：供全部行高 hook 调用。
// 原生值比窗口矮 1~160pt（扣底栏型压缩）→ 回答满视口；其余透传。
+ (CGFloat)fullCellHeightForNative:(CGFloat)nativeHeight {
    if (!DYYYGetBool(@"DYYYEnableFullScreen") || !NSThread.isMainThread) return nativeHeight;
    UIWindow *window = [DYYYUtils getActiveWindow];
    CGFloat windowH = window ? CGRectGetHeight(window.bounds) : 0.0;
    if (!isfinite(nativeHeight) || !isfinite(windowH) || nativeHeight <= 0.0 || windowH <= 0.0) return nativeHeight;
    CGFloat diff = windowH - nativeHeight;
    if (diff > kDYYYRowHeightDiffMin && diff <= kDYYYRowHeightDiffMax) return windowH;
    return nativeHeight;
}

// 行高纯函数：原生行高比窗口矮一个底栏高度（或类似压缩）时，回答满视口高。
// 无状态：不依赖任何关联对象/缓存。锚取窗口高与原生行高的差值区间，
// 特殊行与未就绪尺寸透传。

+ (UIViewController *)controllerForTable:(UITableView *)table {
    UIResponder *responder = table;
    for (int depth = 0; responder && depth < 40; depth++, responder = responder.nextResponder) {
        if ([responder isKindOfClass:[UIViewController class]]) return (UIViewController *)responder;
    }
    return nil;
}

+ (void)layoutBottomBar:(UIView *)bar controller:(UIViewController *)controller enabled:(BOOL)enabled {
    DYYYFullscreenPlayerState *state = [self state:bar];
    if (state.updatingBottomBar) return;
    state.updatingBottomBar = YES;
    @try {
        enabled = enabled && !CGRectIsEmpty(bar.bounds);
        state.owner = controller;
        state.bottomBarEnabled = enabled;
        if (!enabled) {
            for (UIView *view in state.bottomBackgrounds.keyEnumerator.allObjects) {
                NSDictionary *saved = [state.bottomBackgrounds objectForKey:view];
                DYYYFullscreenPlayerState *target = [self state:view];
                target.applyingBottomBackground = YES;
                view.backgroundColor = saved[@"color"] == [NSNull null] ? nil : saved[@"color"];
                view.opaque = [saved[@"opaque"] boolValue];
                if (view != bar && saved[@"hidden"] && view.hidden != [saved[@"hidden"] boolValue]) view.hidden = [saved[@"hidden"] boolValue];
                if ([view isKindOfClass:[UIVisualEffectView class]]) ((UIVisualEffectView *)view).effect = saved[@"effect"] == [NSNull null] ? nil : saved[@"effect"];
                target.transparentBottomBar = nil;
                target.applyingBottomBackground = NO;
            }
            state.bottomBackgrounds = nil;
            return;
        }
        if (!state.bottomBackgrounds) state.bottomBackgrounds = [NSMapTable weakToStrongObjectsMapTable];
        NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:bar];
        for (NSUInteger i = 0; i < queue.count && i < 32; i++) {
            UIView *view = queue[i];
            CGRect rect = [view convertRect:view.bounds toView:bar];
            BOOL coversBar = rect.size.width >= bar.bounds.size.width - 1 && rect.size.height >= bar.bounds.size.height - 1;
            BOOL decoration = ![view isKindOfClass:[UIControl class]] && ![view isKindOfClass:[UILabel class]];
            BOOL background = view == bar || [view isKindOfClass:[UIVisualEffectView class]] ||
                [NSStringFromClass(view.class) containsString:@"Background"] || (decoration && coversBar);
            if (background) {
                UIView *skin = [bar respondsToSelector:@selector(skinContainerView)] ? [(AWENormalModeTabBar *)bar skinContainerView] : nil;
                BOOL backgroundOnly = view != bar && (view == skin || [NSStringFromClass(view.class) containsString:@"Background"] || [view isKindOfClass:[UIImageView class]]);
                if (![state.bottomBackgrounds objectForKey:view]) {
                    UIVisualEffect *effect = [view isKindOfClass:[UIVisualEffectView class]] ? ((UIVisualEffectView *)view).effect : nil;
                    NSMutableDictionary *saved = [@{@"color": view.backgroundColor ?: [NSNull null], @"opaque": @(view.opaque), @"effect": effect ?: [NSNull null]} mutableCopy];
                    if (coversBar && backgroundOnly) saved[@"hidden"] = @(view.hidden);
                    [state.bottomBackgrounds setObject:saved forKey:view];
                }
                DYYYFullscreenPlayerState *target = [self state:view];
                target.transparentBottomBar = bar;
                target.applyingBottomBackground = YES;
                if (view.backgroundColor && CGColorGetAlpha(view.backgroundColor.CGColor) > 0) view.backgroundColor = UIColor.clearColor;
                if (view.opaque) view.opaque = NO;
                if (coversBar && backgroundOnly && !view.hidden) view.hidden = YES;
                if ([view isKindOfClass:[UIVisualEffectView class]] && ((UIVisualEffectView *)view).effect) ((UIVisualEffectView *)view).effect = nil;
                target.applyingBottomBackground = NO;
            }
            if (queue.count < 32 && ![view isKindOfClass:[UIControl class]]) [queue addObjectsFromArray:view.subviews];
        }
    } @finally {
        state.updatingBottomBar = NO;
    }

}
+ (UIColor *)backgroundForBottomView:(UIView *)view proposed:(UIColor *)color {
    DYYYFullscreenPlayerState *target = objc_getAssociatedObject(view, @selector(state:));
    UIView *bar = target.transparentBottomBar;
    if (!bar || target.applyingBottomBackground) return color;
    DYYYFullscreenPlayerState *state = objc_getAssociatedObject(bar, @selector(state:));
    NSDictionary *saved = [state.bottomBackgrounds objectForKey:view];
    if (!saved) return color;
    NSMutableDictionary *updated = [saved mutableCopy];
    updated[@"color"] = color ?: [NSNull null];
    [state.bottomBackgrounds setObject:updated forKey:view];
    return state.bottomBarEnabled && bar.window ? UIColor.clearColor : color;
}
+ (void)layoutBottomInput:(UIView *)view controller:(UIViewController *)controller {
    if (![NSThread isMainThread]) return;
    // 输入栏底色统一：全屏开就不分页面（视频在某一页铺满，底栏底色
    // 就在那一页让开），避免各页面深浅不一致。旧实现限定"仅详情页"，
    // 导致推荐页/喜欢页/收藏页的输入栏深浅不一。
    [self layoutBottomBar:view controller:controller enabled:DYYYGetBool(@"DYYYEnableFullScreen")];
}
+ (CGFloat)bottomOccupiedHeightForView:(UIView *)view {
    UIWindow *window = view.window;
    if (!window) return 0;
    UIViewController *controller = [DYYYUtils firstAvailableViewControllerFromView:view];
    for (UIViewController *owner = controller; owner; owner = owner.parentViewController) {
        if (![owner respondsToSelector:@selector(activeBottomBar)]) continue;
        UIView *bar = [(AWEAwemeDetailTableViewController *)owner activeBottomBar];
        if (bar.window == window && bar.bounds.size.height > 0) return bar.bounds.size.height;
    }
    // 评论会隐藏底栏，尺寸仍以同一窗口中的真实栏为准。
    for (UIView *bar in [self tabBars].allObjects) if (bar.window == window && bar.bounds.size.height > 0) return bar.bounds.size.height;
    return 0;
}
+ (CGRect)rect:(CGRect)rect followingView:(UIView *)view controller:(UIViewController *)controller anchor:(UIView *)anchor {
    UIWindow *window = view.window;
    UIView *cell = [self cellForPlayer:view owner:controller];
    UIScrollView *pager = [self pagingViewForCell:cell];
    if (window && pager.window == window && [self view:cell spansWidthOf:pager] && ![anchor isDescendantOfView:cell]) {
        // 固定底栏先跟随各自的分页 cell，再换算到文案容器；预加载、复用和
        // 翻页都使用同一个视口基准，不能让屏幕坐标改变每页的文案区域高度。
        CGRect cellRect = [cell convertRect:cell.bounds toView:window];
        CGRect viewport = [pager convertRect:pager.bounds toView:window];
        rect.origin.y += CGRectGetMinY(cellRect) - CGRectGetMinY(viewport);
    }
    return rect;
}
+ (CGRect)bottomBarRect:(UIView *)bar followingView:(UIView *)view controller:(UIViewController *)controller {
    if (!view.window || bar.window != view.window) return CGRectNull;
    return [self rect:[bar convertRect:bar.bounds toView:view.window] followingView:view controller:controller anchor:bar];
}
+ (BOOL)layoutNativeInteraction:(UIViewController *)controller {
    if (![NSThread isMainThread]) return NO;
    UIView *view = controller.viewIfLoaded;
    UIView *parent = view.superview;
    if (view.window) [[self interactions] addObject:controller];
    if (!view.window || ![self view:view spansWidthOf:parent]) return NO;
    BOOL enabled = DYYYGetBool(@"DYYYEnableFullScreen");
    BOOL legacy = [[self contentSourceForController:controller] isEqualToString:@"co_play_watch"];
    for (UIViewController *owner = controller; owner; owner = owner.parentViewController) {
        if (![owner respondsToSelector:@selector(activeBottomBar)]) continue;
        UIView *bar = [(AWEAwemeDetailTableViewController *)owner activeBottomBar];
        if (![bar isKindOfClass:[UIView class]]) continue;
        if (!enabled) { [self layoutBottomBar:bar controller:controller enabled:NO]; continue; }
        if (bar.window != view.window || ![self visible:bar]) continue;
        CGRect barRect = [bar convertRect:bar.bounds toView:view.window];
        UIView *root = owner.viewIfLoaded;
        CGRect rootRect = [root convertRect:root.bounds toView:view.window];
        if (!root || barRect.size.height <= 0 || barRect.size.height >= rootRect.size.height ||
            fabs(barRect.size.width - rootRect.size.width) > 1 || fabs(CGRectGetMaxY(barRect) - CGRectGetMaxY(rootRect)) > 1) continue;
        [self layoutBottomBar:bar controller:controller enabled:YES];
        if (legacy) return NO;
        CGRect frame = view.frame;
        barRect = [self bottomBarRect:bar followingView:view controller:controller];

        // 聊天系视频页（群聊 / 朋友聊天）这里**故意保持原生**：互动层 843。
        //
        // 41.2 实测：content 843 / interaction 843 时，进度容器底边 = 843（正确，
        // 正好压在输入栏上沿）；content 926 / interaction 843 时，进度容器底边 = 760
        // （高 83）。可见抖音的进度容器底边 = interaction 底边 − (content − interaction)。
        // 若把 interaction 也撑到 926，抖音会算成底边 926，进度条直接钻到输入栏下面。
        // 所以这里不动，交给 DYYY.xm 里 DYYYIMProgressContainerTarget 单点归位。

        CGFloat bottom = CGRectGetMinY([parent convertRect:barRect fromView:view.window]);
        CGFloat height = MIN(CGRectGetMaxY(parent.bounds), bottom) - frame.origin.y;
        if (height <= 0) return NO;
        if (fabs(frame.size.height - height) > 0.25) { frame.size.height = height; view.frame = frame; }
        return YES;
    }
    // 没有普通底栏时，保留原有 referString 规则；合集、一起看等例外继续有效。
    return NO;
}
// Live 图文也含 TTPlayerView 和有效视频尺寸，不能用播放器存在与否区分。
+ (BOOL)isImageContentController:(UIViewController *)controller {
    for (NSUInteger depth = 0; controller && depth < 5; depth++, controller = controller.parentViewController) {
        if (![controller respondsToSelector:@selector(model)]) continue;
        AWEAwemeModel *model = [(AWEPlayInteractionViewController *)controller model];
        if (![model isKindOfClass:NSClassFromString(@"AWEAwemeModel")]) continue;
        if ([model respondsToSelector:@selector(awemeType)] && model.awemeType == 68) return YES;
        if ([model respondsToSelector:@selector(albumImages)] && model.albumImages.count > 0) return YES;
        if ([model respondsToSelector:@selector(isLivePhoto)] && model.isLivePhoto) return YES;
        if ([model respondsToSelector:@selector(animatedImageVideoInfo)] && model.animatedImageVideoInfo) return YES;
        return NO;
    }
    return NO;
}
+ (NSHashTable<UIView *> *)players {
    static NSHashTable *players;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ players = [NSHashTable weakObjectsHashTable]; });
    return players;
}
+ (NSHashTable<UIView *> *)tabBars {
    static NSHashTable *views;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ views = [NSHashTable weakObjectsHashTable]; });
    return views;
}
+ (NSHashTable<UIViewController *> *)interactions {
    static NSHashTable *controllers;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ controllers = [NSHashTable weakObjectsHashTable]; });
    return controllers;
}
+ (void)invalidateGuides {
    static BOOL scheduled = NO;
    if (scheduled) return;
    scheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        scheduled = NO;
        for (UIViewController *controller in [self interactions].allObjects) [controller.viewIfLoaded setNeedsLayout];
        for (UIView *player in [self players].allObjects) if (player.window) [player setNeedsLayout];
    });
}
+ (void)layoutRootTabBar:(UIView *)bar {
    BOOL playback = NO;
    DYYYFullscreenPlayerState *state = objc_getAssociatedObject(bar, @selector(state:));
    if ([self hasCommentInWindow:bar.window] && state.bottomBarEnabled) playback = YES;
    if (!playback) for (UIViewController *controller in [self interactions].allObjects) {
        if (controller.viewIfLoaded.window != bar.window || ![self usesFullscreenLayoutForController:controller] ||
            ![DYYYFloatingButtonCoordinator isControllerVisible:controller]) continue;
        playback = YES;
        break;
    }
    // 个人主页 / 作品页这类页面没有播放互动层（无 HUD），playback 永远为 NO，
    // 底栏因此保持不透明。但全屏开启时这些页面同样是全屏浏览，
    // 底栏应当与播放页保持一致（透明）。只按当前顶层控制器判断，
    // 消息页/搜索页等不受影响。
    if (!playback && DYYYGetBool(@"DYYYEnableFullScreen") && [self tabBarHostsProfilePage:bar]) {
        playback = YES;
    }
    BOOL enabled = DYYYGetBool(@"DYYYHideBottomBg") || (DYYYGetBool(@"DYYYEnableFullScreen") && playback);
    [self layoutBottomBar:bar controller:nil enabled:enabled];
}

// 当前 tabBar 所在窗口的顶层页面是否为个人主页 / 作品页栈。
+ (BOOL)tabBarHostsProfilePage:(UIView *)bar {
    static Class sProfileContainer;
    static Class sPostWork;
    static Class sUserHome;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      sProfileContainer = NSClassFromString(@"AWEProfileBaseContainerViewController");
      sPostWork = NSClassFromString(@"AWEPostWorkViewControllerV2");
      sUserHome = NSClassFromString(@"AWEUserHomeViewController");
    });
    if (!sProfileContainer && !sPostWork && !sUserHome) return NO;

    UIWindow *window = bar.window;
    if (!window) return NO;
    UITabBarController *tab = nil;
    UIViewController *root = window.rootViewController;
    if ([root isKindOfClass:[UITabBarController class]]) tab = (UITabBarController *)root;
    if (!tab) return NO;

    UIViewController *top = tab.selectedViewController;
    if ([top isKindOfClass:[UINavigationController class]]) {
        top = ((UINavigationController *)top).topViewController;
    }
    if (!top) return NO;

    for (UIViewController *cursor = top; cursor; cursor = cursor.parentViewController) {
        if ((sProfileContainer && [cursor isKindOfClass:sProfileContainer]) ||
            (sPostWork && [cursor isKindOfClass:sPostWork]) ||
            (sUserHome && [cursor isKindOfClass:sUserHome])) {
            return YES;
        }
    }
    return NO;
}
+ (void)registerTabBar:(UIView *)tabBar {
    if (![NSThread isMainThread]) return;
    [[self tabBars] addObject:tabBar];
    [self layoutRootTabBar:tabBar];
    CGRect rect = tabBar.window ? [tabBar convertRect:tabBar.bounds toView:tabBar.window] : CGRectNull;
    NSString *signature = [NSString stringWithFormat:@"%p/%@/%d", tabBar.window, NSStringFromCGRect(rect), [self visible:tabBar]];
    NSString *previous = objc_getAssociatedObject(tabBar, @selector(registerTabBar:));
    if (![signature isEqualToString:previous]) {
        objc_setAssociatedObject(tabBar, @selector(registerTabBar:), signature, OBJC_ASSOCIATION_COPY_NONATOMIC);
        [self invalidateGuides];
    }
}
+ (void)layoutInteraction:(UIViewController *)controller {
    if (![NSThread isMainThread] || ![self usesRecommendedLayoutForController:controller]) return;
    UIView *view = controller.viewIfLoaded;
    UIView *parent = view.superview;
    if (!view.window || ![self view:view spansWidthOf:parent]) return;
    [[self interactions] addObject:controller];
    for (UIView *bar in [self tabBars].allObjects) if (bar.window == view.window) [self layoutRootTabBar:bar];
    if ([self isImageContentController:controller]) return;
    DYYYFullscreenPlayerState *state = [self state:view];
    state.owner = controller;
    CGRect current = view.frame;
    if (!state.hasNativeFrame || !CGRectEqualToRect(current, state.lastAppliedFrame)) state.nativeFrame = current;
    state.hasNativeFrame = YES;
    CGRect target = state.nativeFrame;
    target.size.height = MIN(target.size.height, MAX(0, CGRectGetMaxY(parent.bounds) - target.origin.y));
    if (DYYYGetBool(@"DYYYEnableFullScreen")) {
        target.size.height = MAX(0, CGRectGetMaxY(parent.bounds) - target.origin.y);
        CGRect guide = [parent convertRect:target toView:view.window];
        for (UIView *tabBar in [self tabBars].allObjects) {
            // 清屏只隐藏底栏，不释放其占位；信息区沿用同一边界，退出时无需
            // 等待底栏的显隐动画恢复，也不会把文案按全屏高度重新锚到底部。
            if (tabBar.window != view.window || CGRectIsEmpty(tabBar.bounds)) continue;
            CGRect tabRect = [self bottomBarRect:tabBar followingView:view controller:controller];
            if (CGRectIsNull(tabRect)) continue;
            if (CGRectGetMinY(tabRect) < CGRectGetMidY(guide)) continue;
            CGRect available = [DYYYFullscreenGeometry unoccludedViewport:guide top:CGRectGetMinY(guide) panel:tabRect gap:0];
            if (!CGRectIsNull(available)) guide = available;
        }
        target = [parent convertRect:guide fromView:view.window];
    }
    BOOL activeComment = [self hasCommentInWindow:view.window];
    if (DYYYGetBool(@"DYYYEnableFullScreen")) {
        if (activeComment && state.normalWindow == view.window && state.closedInteractionSize.height > 0) {
            // 评论隐藏 Tab 并不代表信息区可扩高，否则原生底部约束会下跳一个 Tab 高度。
            target.size.height = state.closedInteractionSize.height;
        } else if (!activeComment) {
            state.closedInteractionSize = target.size;
            state.normalWindow = view.window;
        }
    } else {
        state.closedInteractionSize = CGSizeZero;
    }
    state.lastAppliedFrame = target;
    if (fabs(current.size.height - target.size.height) > 0.25 || fabs(current.origin.y - target.origin.y) > 0.25) {
        view.frame = target;
    }
    // 签名覆盖全部几何输入：开关变化时重排一次播放器。
    NSString *signature = [NSString stringWithFormat:@"%@/%d/%d", NSStringFromCGRect(target),
                           DYYYGetBool(@"DYYYEnableFullScreen"), DYYYGetBool(@"DYYYEnableCommentBlur")];
    NSString *previous = objc_getAssociatedObject(controller, @selector(layoutInteraction:));
    if (![signature isEqualToString:previous]) {
        objc_setAssociatedObject(controller, @selector(layoutInteraction:), signature, OBJC_ASSOCIATION_COPY_NONATOMIC);
        // 仅几何输入变化时更新播放器，不能每次 layout 都再次标记自身。
        for (UIView *player in [self players].allObjects) if (player.window == view.window) [player setNeedsLayout];
    }
}
+ (NSHashTable<UIView *> *)informationLabels {
    static NSHashTable *labels;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ labels = [NSHashTable weakObjectsHashTable]; });
    return labels;
}
+ (void)layoutInformationLabel:(UIView *)label {
    if (![NSThread isMainThread] || !label.window || !label.superview) return;
    UIViewController *owner = [DYYYUtils firstAvailableViewControllerFromView:label];
    if (![self usesRecommendedLayoutForController:owner]) return;
    DYYYFullscreenPlayerState *state = [self state:label];
    [[self informationLabels] addObject:label];
    BOOL active = DYYYGetBool(@"DYYYEnableFullScreen") && [self hasCommentInWindow:label.window];
    if (!active) {
        if (state.captionAdjusted && CGPointEqualToPoint(label.center, state.captionAppliedCenter)) label.center = state.captionNativeCenter;
        state.captionAdjusted = NO;
        state.captionWindowFrame = [label convertRect:label.bounds toView:label.window];
        state.hasCaptionFrame = DYYYGetBool(@"DYYYEnableFullScreen");
        state.normalWindow = label.window;
        return;
    }
    if (!state.hasCaptionFrame || state.normalWindow != label.window) return;
    CGRect current = [label convertRect:label.bounds toView:label.window];
    CGFloat shift = CGRectGetMaxY(current) - CGRectGetMaxY(state.captionWindowFrame);
    if (shift > 0.25) {
        if (!state.captionAdjusted || !CGPointEqualToPoint(label.center, state.captionAppliedCenter)) state.captionNativeCenter = label.center;
        // 只拦截越过关闭态底边的下移，保留普通评论合法的向上平移和缩放。
        CGRect target = current;
        target.origin.y -= shift;
        CGPoint center = label.center;
        center.y += CGRectGetMidY([label.superview convertRect:target fromView:label.window]) - CGRectGetMidY(label.frame);
        state.captionAppliedCenter = center;
        state.captionAdjusted = YES;
        label.center = center;
    }
}
+ (void)rememberInteractionGuide:(UIViewController *)controller {
    UIView *view = controller.viewIfLoaded;
    if (![NSThread isMainThread] || ![self usesRecommendedLayoutForController:controller] || !view.window || !DYYYGetBool(@"DYYYEnableFullScreen") || [self hasCommentInWindow:view.window]) return;
    DYYYFullscreenPlayerState *state = [self state:view];
    state.owner = controller;
    state.closedInteractionSize = view.frame.size;
    state.normalWindow = view.window;
}
+ (BOOL)keepsMediaHostFullscreen:(UIView *)view state:(DYYYFullscreenPlayerState *)state {
    return state.mediaHost && !state.applying && state.normalWindow == view.window &&
        CGRectEqualToRect(state.mediaHostParentBounds, view.superview.bounds) &&
        DYYYGetBool(@"DYYYEnableFullScreen") && [self usesFullscreenLayoutForController:state.owner];
}
+ (CGRect)boundsForMediaHost:(UIView *)view proposed:(CGRect)bounds {
    DYYYFullscreenPlayerState *state = objc_getAssociatedObject(view, @selector(state:));
    if (![self keepsMediaHostFullscreen:view state:state]) return bounds;
    CGRect native = state.nativeHostFrame;
    CGPoint center = CGPointMake(CGRectGetMidX(native), CGRectGetMidY(native));
    native.size = bounds.size;
    native.origin = CGPointMake(center.x - bounds.size.width * 0.5, center.y - bounds.size.height * 0.5);
    state.nativeHostFrame = native;
    return (CGRect){CGPointZero, state.fullscreenHostFrame.size};
}
+ (CGPoint)centerForMediaHost:(UIView *)view proposed:(CGPoint)center {
    DYYYFullscreenPlayerState *state = objc_getAssociatedObject(view, @selector(state:));
    if (![self keepsMediaHostFullscreen:view state:state]) return center;
    CGRect native = state.nativeHostFrame;
    native.origin = CGPointMake(center.x - native.size.width * 0.5, center.y - native.size.height * 0.5);
    state.nativeHostFrame = native;
    return CGPointMake(CGRectGetMidX(state.fullscreenHostFrame), CGRectGetMidY(state.fullscreenHostFrame));
}
+ (CGRect)frameForInteractionView:(UIView *)view proposed:(CGRect)frame {
    // 只访问已注册的互动根视图和媒体承载区，不遍历普通视图的 responder。
    DYYYFullscreenPlayerState *state = objc_getAssociatedObject(view, @selector(state:));
    if ([self keepsMediaHostFullscreen:view state:state]) {
        state.nativeHostFrame = frame;
        return state.fullscreenHostFrame;
    }
    if (state.closedInteractionSize.height > 0 && [self usesRecommendedLayoutForController:state.owner] && state.normalWindow == view.window &&
        fabs(frame.size.width - state.closedInteractionSize.width) <= 1 &&
        DYYYGetBool(@"DYYYEnableFullScreen") && [self hasCommentInWindow:view.window]) {
        frame.size.height = state.closedInteractionSize.height;
    }
    return frame;
}
+ (NSHashTable<UIViewController *> *)comments {
    static NSHashTable *comments;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ comments = [NSHashTable weakObjectsHashTable]; });
    return comments;
}
+ (NSMapTable<UIWindow *, NSNumber *> *)pendingComments {
    static NSMapTable *windows;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ windows = [NSMapTable weakToStrongObjectsMapTable]; });
    return windows;
}
+ (NSMapTable<UIViewController *, UIWindow *> *)commentWindows {
    static NSMapTable *windows;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ windows = [NSMapTable weakToWeakObjectsMapTable]; });
    return windows;
}
+ (void)beginCommentInWindow:(UIWindow *)window {
    if (![NSThread isMainThread] || !window || !DYYYGetBool(@"DYYYEnableFullScreen")) return;
    if (![self hasCommentInWindow:window]) {
        for (UIView *label in [self informationLabels].allObjects) {
            if (label.window != window || ![self visible:label]) continue;
            [self layoutInformationLabel:label];
        }
    }
    // 先冻结关闭态，再执行原生打开动作。动画开始早于 viewDidLayoutSubviews。
    // 未成功显示的面板自动在 5 秒后失效，不留下持续的 UI 工作。
    [[self pendingComments] setObject:@(CACurrentMediaTime() + 5) forKey:window];
}
+ (DYYYFullscreenPlayerState *)state:(UIView *)player {
    DYYYFullscreenPlayerState *state = objc_getAssociatedObject(player, @selector(state:));
    if (!state) {
        state = [DYYYFullscreenPlayerState new];
        objc_setAssociatedObject(player, @selector(state:), state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIWindow *window = player.window;
    if (window && (!CGSizeEqualToSize(state.layoutWindowSize, window.bounds.size) || !UIEdgeInsetsEqualToEdgeInsets(state.layoutSafeArea, window.safeAreaInsets))) {
        state.layoutWindowSize = window.bounds.size;
        state.layoutSafeArea = window.safeAreaInsets;
        state.hasNativeFrame = NO;
        state.closedInteractionSize = CGSizeZero;
        state.hasCaptionFrame = NO;
        state.captionAdjusted = NO;
    }
    return state;
}
+ (BOOL)visible:(UIView *)view {
    if (!view.window) return NO;
    CGFloat alpha = 1;
    for (UIView *v = view; v; v = v.superview) {
        alpha *= v.alpha;
        if (v.hidden || alpha < 0.01) return NO;
    }
    return CGRectIntersectsRect([view convertRect:view.bounds toView:view.window], view.window.bounds);
}
+ (UIViewController *)owner:(UIView *)player state:(DYYYFullscreenPlayerState *)state {
    if (state.owner && state.owner.viewIfLoaded.window == player.window && [player isDescendantOfView:state.owner.viewIfLoaded]) return state.owner;
    UIResponder *responder = player;
    for (NSUInteger i = 0; responder && i < 16; i++, responder = responder.nextResponder) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            NSString *name = NSStringFromClass(responder.class);
            if ([name containsString:@"PlayVideoViewController"] || [self isImageContentController:(UIViewController *)responder]) {
                state.owner = (UIViewController *)responder;
                return state.owner;
            }
        }
    }
    return nil;
}
+ (UIView *)cellForPlayer:(UIView *)player owner:(UIViewController *)owner {
    UIView *cell = nil;
    for (UIView *view = player.superview; view && ![view isKindOfClass:[UIWindow class]]; view = view.superview) {
        if (([view isKindOfClass:[UITableViewCell class]] || [view isKindOfClass:[UICollectionViewCell class]]) &&
            [self view:view spansWidthOf:[self pagingViewForCell:view]]) cell = view;
    }
    return cell ?: owner.parentViewController.viewIfLoaded.superview ?: owner.viewIfLoaded.superview;
}
+ (BOOL)hasCommentInWindow:(UIWindow *)window {
    if (!window) return NO;
    NSNumber *deadline = [[self pendingComments] objectForKey:window];
    if (deadline.doubleValue > CACurrentMediaTime()) return YES;
    if (deadline) [[self pendingComments] removeObjectForKey:window];
    for (UIViewController *controller in [self comments].allObjects) {
        if (controller.viewIfLoaded.window == window) return YES;
    }
    return NO;
}
+ (CGRect)targetForPlayer:(UIView *)player native:(CGRect)native state:(DYYYFullscreenPlayerState *)state {
    if (!DYYYGetBool(@"DYYYEnableFullScreen") || ![self visible:player]) return native;
    UIWindow *window = player.window;
    UIViewController *owner = [self owner:player state:state];
    BOOL recommended = [self usesRecommendedLayoutForController:owner];
    if (![self usesFullscreenLayoutForController:owner]) return native;
    if ([self isImageContentController:owner]) return native;
    if (!owner || !player.superview) return native;
    UIView *cell = [self cellForPlayer:player owner:owner];
    if (!cell || cell.window != window) return native;
    CGRect viewport = CGRectIntersection([cell convertRect:cell.bounds toView:window], window.bounds);
    if (CGRectIsNull(viewport) || CGRectIsEmpty(viewport)) return native;
    CGSize media = CGSizeZero;
    if ([owner respondsToSelector:@selector(getPlayerVideoSize)]) media = [(AWEPlayVideoViewController *)owner getPlayerVideoSize];
    if (media.width <= 0 || media.height <= 0) return native;
    if (media.width > media.height) {
        // 横屏视频沿用原生信息层的布局高度；背景仍由全高 Feed 承载。
        for (UIViewController *controller in [self interactions].allObjects) {
            UIView *interaction = controller.viewIfLoaded;
            if (interaction.window != window || ![interaction isDescendantOfView:cell]) continue;
            CGRect guide = [interaction convertRect:interaction.bounds toView:window];
            if (guide.size.height > viewport.size.height * 0.6 && guide.size.height <= viewport.size.height) native.size.height = guide.size.height;
            break;
        }
        return native;
    }
    // 竖屏媒体扩展到本页底部；不影响宽度缩小的原生面板/小窗布局。
    if (fabs(native.size.width - viewport.size.width) < 1 && fabs(native.origin.x) < 1) native.size.height = MAX(native.size.height, viewport.size.height);
    return native;
}
+ (CGRect)frameForPlayer:(UIView *)player proposed:(CGRect)frame {
    if (![NSThread isMainThread]) return frame;
    DYYYFullscreenPlayerState *state = [self state:player];
    if (state.applying) return frame;
    state.nativeFrame = frame;
    state.hasNativeFrame = YES;
    return [self targetForPlayer:player native:frame state:state];
}
+ (void)preparePlayer:(UIView *)player {
    if (![NSThread isMainThread]) return;
    DYYYFullscreenPlayerState *state = [self state:player];
    if (state.applying) return;
    [[self players] addObject:player];
    UIViewController *owner = [self owner:player state:state];
    [self layoutPlayerContainer:owner.parentViewController];
    if ([self isImageContentController:owner]) return;
    if (!state.hasNativeFrame) { state.nativeFrame = player.frame; state.hasNativeFrame = YES; }
    CGRect target = [self targetForPlayer:player native:state.nativeFrame state:state];
    state.adjusted = !CGRectEqualToRect(target, state.nativeFrame);
    CGRect current = player.frame;
    if (fabs(current.origin.x - target.origin.x) + fabs(current.origin.y - target.origin.y) + fabs(current.size.width - target.size.width) + fabs(current.size.height - target.size.height) > 0.25) {
        state.applying = YES;
        player.frame = target;
        state.applying = NO;
    }
}
#pragma mark - 媒体容器

+ (void)layoutPlayerContainer:(UIViewController *)controller {
    Class pureListClass = NSClassFromString(@"AFDPureModePageListViewController");
    BOOL pureModeList = pureListClass && [controller isKindOfClass:pureListClass];
    if (![NSThread isMainThread] || (!pureModeList && ![controller respondsToSelector:@selector(contentView)])) return;
    UIView *view = controller.viewIfLoaded;
    if (!view.window || !view.superview) return;
    BOOL enabled = DYYYGetBool(@"DYYYEnableFullScreen") && [self usesFullscreenLayoutForController:controller];
    UIView *content = pureModeList ? nil : [(AWEDPlayerViewController_Merge *)controller contentView];
    for (UIView *host in content && content != view ? @[view, content] : @[view]) {
        DYYYFullscreenPlayerState *state = objc_getAssociatedObject(host, @selector(state:));
        if (state.applying) continue;
        CGRect current = host.frame;
        if (!enabled) {
            BOOL restore = state.mediaHost && CGRectEqualToRect(current, state.fullscreenHostFrame);
            state.mediaHost = NO;
            if (restore) host.frame = state.nativeHostFrame;
            continue;
        }
        UIView *parent = host.superview;
        if (!parent || CGRectIsEmpty(parent.bounds) || !CGAffineTransformIsIdentity(host.transform)) continue;
        if (!state.mediaHost && ![self view:host spansWidthOf:parent]) continue;
        state = [self state:host];
        if (!state.mediaHost || state.normalWindow != view.window || !CGRectEqualToRect(state.mediaHostParentBounds, parent.bounds)) {
            state.nativeHostFrame = current;
            state.fullscreenHostFrame = current;
        }
        CGRect target = parent.bounds;
        state.mediaHost = YES;
        state.mediaHostParentBounds = parent.bounds;
        state.owner = controller;
        state.normalWindow = view.window;
        state.fullscreenHostFrame = target;
        // 诊断：完整记录每次撑满判定（纯打印，不改行为），用于定位滑动时
        // 多页同时撑满/新旧页状态打架的问题。开关：设置→诊断工具→全屏诊断日志。
        if (DYYYGetBool(@"DYYYDiagEntryEnabled")) {
            UIView *diagCell = [self cellForPlayer:host owner:controller];
            UIView *diagPager = [self pagingViewForCell:diagCell];
            CGRect cellRect = diagCell ? [diagCell convertRect:diagCell.bounds toView:diagCell.window] : CGRectZero;
            UIScrollView *scroll = (UIScrollView *)diagPager;
            CGPoint center = CGPointMake(CGRectGetMidX(host.window.bounds), CGRectGetMidY(host.window.bounds));
            NSLog(@"[DYYY][fullscreen] host=%s cell=%s pager=%s cellRect=%@ win=%@ "
                  @"centerHit=%d tracking=%d dragging=%d decel=%d offset=%@",
                  class_getName([host class]),
                  diagCell ? class_getName([diagCell class]) : "nil",
                  diagPager ? class_getName([diagPager class]) : "nil",
                  NSStringFromCGRect(cellRect),
                  NSStringFromCGRect(host.window.bounds),
                  CGRectContainsPoint(cellRect, center) ? 1 : 0,
                  scroll ? scroll.isTracking : -1,
                  scroll ? scroll.isDragging : -1,
                  scroll ? scroll.isDecelerating : -1,
                  scroll ? NSStringFromCGPoint(scroll.contentOffset) : @"nil");
        }
        // 承载区全程全高；评论避让只改内部播放器，不补背景或等待消失回调。
        if (!CGRectEqualToRect(current, target)) {
            state.applying = YES;
            host.frame = target;
            state.applying = NO;
        }
    }
}

// 渲染布局完成后记录画面尺寸，供评论避让使用。
+ (void)finishPlayer:(UIView *)player {
    if (![NSThread isMainThread]) return;
    DYYYFullscreenPlayerState *state = [self state:player];
    UIViewController *owner = [self owner:player state:state];
    [self layoutPlayerContainer:owner.parentViewController];
    if (![self usesFullscreenLayoutForController:owner] || [self isImageContentController:owner]) return;
}
+ (void)commentController:(UIViewController *)controller visible:(BOOL)visible {
    if (![NSThread isMainThread]) {
        __weak UIViewController *weakController = controller;
        dispatch_async(dispatch_get_main_queue(), ^{ if (weakController) [self commentController:weakController visible:visible]; });
        return;
    }
    UIView *view = controller.viewIfLoaded;
    CGRect rect = visible && view.window ? [view convertRect:view.bounds toView:view.window] : CGRectNull;
    NSString *signature = [NSString stringWithFormat:@"%p/%@/%d/%d", view.window, NSStringFromCGRect(rect), visible,
                           DYYYGetBool(@"DYYYEnableFullScreen"), DYYYGetBool(@"DYYYEnableCommentBlur")];
    NSString *previous = objc_getAssociatedObject(controller, @selector(commentController:visible:));
    if ([signature isEqualToString:previous]) return;
    objc_setAssociatedObject(controller, @selector(commentController:visible:), signature, OBJC_ASSOCIATION_COPY_NONATOMIC);
    if (visible) {
        [[self comments] addObject:controller];
        if (view.window) [[self commentWindows] setObject:view.window forKey:controller];
    } else {
        UIWindow *window = [[self commentWindows] objectForKey:controller] ?: view.window;
        [[self comments] removeObject:controller];
        [[self commentWindows] removeObjectForKey:controller];
        BOOL remaining = NO;
        for (UIViewController *other in [self comments].allObjects) if (other.viewIfLoaded.window == window) { remaining = YES; break; }
        if (window && !remaining) [[self pendingComments] removeObjectForKey:window];
    }
    // 同一轮布局只安排一次；不在评论回调里递归触发布局。
    static BOOL scheduled = NO;
    if (scheduled) return;
    scheduled = YES;
    dispatch_async(dispatch_get_main_queue(), ^{
        scheduled = NO;
        for (UIView *player in [self players].allObjects) if (player.window) [player setNeedsLayout];
    });
}
@end
