#import "DYYYCommentBlurCoordinator.h"
#import "DYYYFullscreenCoordinator.h"
#import "DYYYUtils.h"
#import <objc/runtime.h>

@interface DYYYCommentBlurState : NSObject
@property(nonatomic, strong) NSMapTable<UIView *, id> *backgrounds;
@property(nonatomic, strong) NSMapTable<UIView *, NSNumber *> *opaqueValues;
@property(nonatomic, strong) NSMapTable<UIView *, UIView *> *danmuBackgrounds;
@property(nonatomic, strong) NSMapTable<UIView *, NSNumber *> *hiddenValues;
@property(nonatomic, weak) UIView *panel;
@property(nonatomic, assign) BOOL discoveredLists;
@property(nonatomic, assign) BOOL applying;
@property(nonatomic, weak) UIVisualEffectView *effectView;
@property(nonatomic, assign) UIBlurEffectStyle style;
@property(nonatomic, assign) CGFloat transparency;
@end
@implementation DYYYCommentBlurState
@end

@implementation DYYYCommentBlurCoordinator
+ (void)clearBackground:(UIView *)view state:(DYYYCommentBlurState *)state {
    if (![state.backgrounds objectForKey:view]) {
        [state.backgrounds setObject:view.backgroundColor ?: [NSNull null] forKey:view];
    }
    if (view.backgroundColor && CGColorGetAlpha(view.backgroundColor.CGColor) > 0) view.backgroundColor = [UIColor clearColor];
}
+ (void)clearTextBackground:(UIView *)view state:(DYYYCommentBlurState *)state {
    if (![state.opaqueValues objectForKey:view]) [state.opaqueValues setObject:@(view.opaque) forKey:view];
    state.applying = YES;
    [self clearBackground:view state:state];
    if (view.opaque) view.opaque = NO;
    state.applying = NO;
}
+ (void)updatePanel:(UIViewController *)controller {
    UIView *view = controller.viewIfLoaded;
    if (!view) return;
    DYYYCommentBlurState *state = objc_getAssociatedObject(view, @selector(updatePanel:));
    if (!DYYYGetBool(@"DYYYEnableCommentBlur")) {
        if (!state) return;
        [state.effectView removeFromSuperview];
        for (UIView *background in state.danmuBackgrounds.objectEnumerator) [background removeFromSuperview];
        for (UIView *child in state.hiddenValues.keyEnumerator) child.hidden = [state.hiddenValues objectForKey:child].boolValue;
        for (UIView *background in state.backgrounds.keyEnumerator) {
            if (objc_getAssociatedObject(background, @selector(layoutListView:)) == state) {
                objc_setAssociatedObject(background, @selector(layoutListView:), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            NSNumber *opaque = [state.opaqueValues objectForKey:background];
            if (opaque && !background.opaque) background.opaque = opaque.boolValue;
            id color = [state.backgrounds objectForKey:background];
            // 原生已重新设置背景时不覆盖新状态。
            if (!background.backgroundColor || CGColorGetAlpha(background.backgroundColor.CGColor) == 0) {
                background.backgroundColor = color == [NSNull null] ? nil : color;
            }
        }
        objc_setAssociatedObject(view, @selector(updatePanel:), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }
    if (!view.window) return;
    if (!state) {
        state = [DYYYCommentBlurState new];
        state.backgrounds = [NSMapTable weakToStrongObjectsMapTable];
        state.opaqueValues = [NSMapTable weakToStrongObjectsMapTable];
        state.danmuBackgrounds = [NSMapTable weakToStrongObjectsMapTable];
        state.hiddenValues = [NSMapTable weakToStrongObjectsMapTable];
        state.panel = view;
        objc_setAssociatedObject(view, @selector(updatePanel:), state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [self clearBackground:view state:state];
    // 40.7 的实际评论列表自带不透明背景，会遮住根视图上的毛玻璃。
    // 先处理直接滚动子视图；新面板仅做一次有界发现，文字标签一并去掉底色。
    for (UIView *child in view.subviews) {
        if ([child isKindOfClass:[UIScrollView class]]) [self clearBackground:child state:state];
    }
    if (!state.discoveredLists) {
        state.discoveredLists = YES;
        NSMutableArray<UIView *> *pending = [view.subviews mutableCopy];
        // 41.0 视图树实锤（DYKiller 导出）：评论列表区的不透明底色来自
        // AWEBaseListSectionBackgroundView（rgba(0.086,0.086,0.086,1.0)），
        // 旧 BFS 只清 UIScrollView/UILabel，漏掉这个 ListKit 分区背景，
        // 表现为毛玻璃层之上永远盖着一块黑。
        static Class sectionBackgroundClass = nil;
        static dispatch_once_t sectionOnce;
        dispatch_once(&sectionOnce, ^{
          sectionBackgroundClass = NSClassFromString(@"AWEBaseListSectionBackgroundView");
        });
        for (NSUInteger index = 0; index < pending.count && index < 512; index++) {
            UIView *child = pending[index];
            if ([child isKindOfClass:[UIScrollView class]]) [self clearBackground:child state:state];
            if ([child isKindOfClass:[UILabel class]] || [child isKindOfClass:NSClassFromString(@"YYLabel")]) [self clearTextBackground:child state:state];
            if (sectionBackgroundClass && [child isKindOfClass:sectionBackgroundClass]) [self clearBackground:child state:state];
            for (UIView *descendant in child.subviews) {
                if (pending.count >= 512) break;
                [pending addObject:descendant];
            }
        }
    }
    CGFloat transparency = [[[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYCommentBlurTransparent"] floatValue];
    if (transparency <= 0 || transparency > 1) transparency = 0.9;
    UIBlurEffectStyle style = [DYYYUtils isDarkMode] ? UIBlurEffectStyleDark : UIBlurEffectStyleLight;
    UIVisualEffectView *effect = state.effectView;
    if (!effect || effect.superview != view) {
        [DYYYUtils applyBlurEffectToView:view transparency:transparency blurViewTag:999];
        for (UIView *child in view.subviews) {
            if ([child isKindOfClass:[UIVisualEffectView class]] && child.tag == 999) {
                effect = (UIVisualEffectView *)child;
                state.effectView = effect;
                effect.userInteractionEnabled = NO;
                break;
            }
        }
        state.style = style;
        state.transparency = transparency;
    } else if (state.style != style || fabs(state.transparency - transparency) > 0.001) {
        [DYYYUtils applyBlurEffectToView:view transparency:transparency blurViewTag:999];
        state.style = style;
        state.transparency = transparency;
    }
    if (effect && !CGRectEqualToRect(effect.frame, view.bounds)) effect.frame = view.bounds;
}
+ (DYYYCommentBlurState *)stateForContentView:(UIView *)view {
    if (![NSThread isMainThread] || !DYYYGetBool(@"DYYYEnableCommentBlur")) return nil;
    DYYYCommentBlurState *state = objc_getAssociatedObject(view, @selector(layoutListView:));
    if (!state.panel || objc_getAssociatedObject(state.panel, @selector(updatePanel:)) != state || ![view isDescendantOfView:state.panel]) {
        state = nil;
        objc_setAssociatedObject(view, @selector(layoutListView:), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        // 40.9 评论面板嵌套层级比以前深（cell/collectionView/container 多层包裹），
        // 16 层会够不到带状态的祖先，导致清理逻辑整条跳过、原生不透明底色残留，
        // 表现为「一会黑块一会毛玻璃」。这里加深到 64 层。
        UIView *ancestor = view.superview;
        for (NSUInteger depth = 0; ancestor && depth < 64; depth++, ancestor = ancestor.superview) {
            state = objc_getAssociatedObject(ancestor, @selector(updatePanel:));
            if (state) break;
        }
        // 兜底：视图树被临时摘下（scroll 复用瞬间）时，从窗口根视图向下找已注册面板。
        if (!state) {
            UIWindow *window = view.window;
            if (window) {
                NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:window];
                for (NSUInteger index = 0; index < queue.count && index < 512; index++) {
                    UIView *node = queue[index];
                    DYYYCommentBlurState *candidate = objc_getAssociatedObject(node, @selector(updatePanel:));
                    if (candidate && candidate.panel) {
                        state = candidate;
                        break;
                    }
                    [queue addObjectsFromArray:node.subviews];
                }
            }
        }
        if (state) objc_setAssociatedObject(view, @selector(layoutListView:), state, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return state.panel ? state : nil;
}
+ (void)layoutDanmuBackground:(UIView *)container controller:(UIViewController *)controller enabled:(BOOL)enabled {
    DYYYCommentBlurState *state = objc_getAssociatedObject(controller.viewIfLoaded, @selector(updatePanel:));
    UIView *target = container.superview.subviews.firstObject;
    if (!state || !target) return;
    UIView *background = [state.danmuBackgrounds objectForKey:target];
    UIView *originalChild = target.subviews.firstObject;
    if (!enabled) {
        [background removeFromSuperview];
        [state.danmuBackgrounds removeObjectForKey:target];
        NSNumber *hidden = [state.hiddenValues objectForKey:originalChild];
        if (hidden) {
            originalChild.hidden = hidden.boolValue;
            [state.hiddenValues removeObjectForKey:originalChild];
        }
        return;
    }
    if (originalChild && originalChild != background) {
        if (![state.hiddenValues objectForKey:originalChild]) [state.hiddenValues setObject:@(originalChild.hidden) forKey:originalChild];
        if (!originalChild.hidden) originalChild.hidden = YES;
    }
    if (!background) {
        background = [[UIView alloc] initWithFrame:target.bounds];
        background.backgroundColor = UIColor.whiteColor;
        background.userInteractionEnabled = NO;
        background.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [state.danmuBackgrounds setObject:background forKey:target];
        [target addSubview:background];
    }
    if (!CGRectEqualToRect(background.frame, target.bounds)) background.frame = target.bounds;
}

+ (void)layoutListView:(UIView *)view {
    DYYYCommentBlurState *state = [self stateForContentView:view];
    // 新版正文列表位于 UICollectionViewCell 内，清除外层背景不足以透出材质。
    if (state) [self clearBackground:view state:state];
}
+ (void)layoutTextView:(UIView *)view {
    DYYYCommentBlurState *state = [self stateForContentView:view];
    // 原生复用昵称、时间及回复标签时会重新设置不透明底色。
    if (state) [self clearTextBackground:view state:state];
}
+ (UIColor *)backgroundColorForTextView:(UIView *)view proposed:(UIColor *)color {
    DYYYCommentBlurState *state = [self stateForContentView:view];
    if (!state || state.applying) return color;
    // 原生可只重画而不触发布局，在写入入口拦住底色，并记住最新的恢复值。
    [state.backgrounds setObject:color ?: [NSNull null] forKey:view];
    if (![state.opaqueValues objectForKey:view]) [state.opaqueValues setObject:@(view.opaque) forKey:view];
    state.applying = YES;
    if (view.opaque) view.opaque = NO;
    state.applying = NO;
    return [UIColor clearColor];
}
+ (BOOL)opaqueForTextView:(UIView *)view proposed:(BOOL)opaque {
    DYYYCommentBlurState *state = [self stateForContentView:view];
    if (!state || state.applying) return opaque;
    if (![state.backgrounds objectForKey:view]) [state.backgrounds setObject:view.backgroundColor ?: [NSNull null] forKey:view];
    if (![state.opaqueValues objectForKey:view]) [state.opaqueValues setObject:@(opaque) forKey:view];
    return NO;
}
+ (void)layoutController:(UIViewController *)controller {
    if (![NSThread isMainThread]) return;
    // 40.9：Swift 类点号名已不可查，必须回退 mangled 名，否则整条毛玻璃清理逻辑直接跳过
    // （表现为评论列表部分 cell 保留不透明背景、透出视频画面）。
    Class innerClass = NSClassFromString(@"AWECommentPanelContainerSwiftImpl.CommentContainerInnerViewController");
    if (!innerClass) innerClass = NSClassFromString(@"_TtC33AWECommentPanelContainerSwiftImpl35CommentContainerInnerViewController");
    // 41.0：外层面板类。首次从 Feed 打开评论区走 Panel 而不经过 Inner，
    // 必须同样执行布局。二进制里还有多个不同长度后缀的 CommentViewController
    // 变体（31/33/35/36/40/42/47），只认两个精确类名会再次漏掉真实持有者。
    static Class panelClass = nil;
    static dispatch_once_t panelOnce;
    dispatch_once(&panelOnce, ^{
      panelClass = NSClassFromString(@"AWECommentPanelContainerSwiftImpl.CommentPanelViewController");
      if (!panelClass) panelClass = NSClassFromString(@"_TtC33AWECommentPanelContainerSwiftImpl38CommentPanelViewController");
    });
    // 兜底判定：类名里含 CommentPanelContainerSwiftImpl 或 Comment 且是面板级 VC，
    // 一律视为评论面板处理（41.0 版本类名后缀不确定，不能依赖精确匹配）。
    NSString *vcName = [NSString stringWithUTF8String:class_getName([controller class])];
    BOOL looksLikePanel = [vcName containsString:@"CommentPanelContainerSwiftImpl"] ||
                          [vcName containsString:@"CommentContainerInner"] ||
                          [vcName containsString:@"CommentPanelViewController"] ||
                          [vcName containsString:@"AWECommentContainerViewController"];
    // 诊断日志：每次布局都打（带类名与命中路径），观察打开评论时的触发链。
    NSLog(@"[DYYY][blur] layoutController vc=%@ panelHit=%d inner=%d", vcName,
          looksLikePanel ? 1 : 0, innerClass && [controller isKindOfClass:innerClass] ? 1 : 0);
    if (looksLikePanel) {
        [self updatePanel:controller];
        return;
    }
    Class containerClass = NSClassFromString(@"AWECommentContainerViewController");
    if (!containerClass || ![controller isKindOfClass:containerClass]) return;
    // 宿主回调覆盖新版 Swift 面板没有调用旧父类布局方法的情况。
    NSMutableArray<UIViewController *> *pending = [controller.childViewControllers mutableCopy];
    for (NSUInteger index = 0; index < pending.count && index < 64; index++) {
        UIViewController *child = pending[index];
        NSString *childName = [NSString stringWithUTF8String:class_getName([child class])];
        BOOL childIsPanel = [childName containsString:@"CommentPanelContainerSwiftImpl"] ||
                            [childName containsString:@"CommentContainerInner"] ||
                            [childName containsString:@"CommentPanelViewController"];
        if (childIsPanel) {
            [self updatePanel:child];
            [DYYYFullscreenCoordinator commentController:child visible:child.viewIfLoaded.window != nil];
        } else if (pending.count < 64) {
            [pending addObjectsFromArray:child.childViewControllers];
        }
    }
}
@end
