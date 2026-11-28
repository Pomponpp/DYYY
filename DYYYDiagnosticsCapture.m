//
//  DYYYDiagnosticsCapture.m
//  DYYY 诊断系统 · 页面快照
//
//  只读地遍历 UIKit/CoreAnimation 安全字段 + 收集本页类。
//  不递归读任意对象的 ivar 值。
//
//  与旧实现的行为差异：无（逻辑等价的 DYYY 命名重写）。
//  音频专项模式随旧音频探针一起移除（外部 0 调用）。
//

#import "DYYYDiagnosticsCapture.h"
#import "DYYYDiagnosticsCore.h"
#import "DYYYDiagnosticsCompat.h"
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>

#pragma mark - 小型格式化工具

static NSString *DYYYDiagStringFromPointer(const void *pointer) {
    return [NSString stringWithFormat:@"%p", pointer];
}

static NSString *DYYYDiagClassName(id object) {
    if (!object) return @"";
    // class_getName 对"惰性命名的 Swift 类"会先走
    // installMangledNameForLazilyNamedClass → demangledName → Swift demangler，
    // 畸形泛型 mangled 名会 failAssert → abort。直播间里大量 _TtC 泛型 CALayer
    // 正是这类，所以每条导出必崩在那，推荐页偶发。
    //
    // 这里改成读 isa 的 raw 名，但先判一次"名字是否已经在类结构里"：
    // 惰性类的 name 指针为空，此时不取名字，直接返回占位，绝不触发安装流程。
    Class cls = object_getClass(object);
    if (!cls) return @"";
    const char *raw = DYYYDiagRawClassName(cls);
    return raw ? [NSString stringWithUTF8String:raw] : @"(lazy-swift-class)";
}

// 展示用类名：读不到本视图的名字时，往上找一个已知类名的祖先补上下文。
//
// 视图树里大量 Swift 泛型类的名字是懒生成的，读不到；只写 (lazy-swift-class)
// 的话整整一层都看不出是挂在哪。补上最近的已知祖先，至少能判断
// "这是 AWEFeedViewCell 底下的某一层"，定位时比纯占位有用得多。
// 向上最多查 8 层：正常情况 1-2 层就命中，深链全懒时也不至于一路读到根。
static NSString *DYYYDiagClassDisplayName(UIView *view) {
    NSString *name = DYYYDiagClassName(view);
    if (![name isEqualToString:@"(lazy-swift-class)"]) return name;

    UIView *parent = view.superview;
    for (NSUInteger depth = 0; parent && depth < 8; depth++, parent = parent.superview) {
        NSString *parentName = DYYYDiagClassName(parent);
        if ([parentName isEqualToString:@"(lazy-swift-class)"]) continue;
        if (parentName.length == 0) continue;
        return [NSString stringWithFormat:@"(lazy in %@)", parentName];
    }
    return name;
}

static NSString *DYYYDiagObjectDesc(id object) {
    if (!object) return @"";
    @try {
        return [object description] ?: @"";
    } @catch (__unused NSException *e) {
        return @"(description threw)";
    }
}

#pragma mark - 有限值保护

// JSON 序列化遇到 NaN / Inf 会直接抛异常，而 NSJSONSerialization 内部是 C++ 实现，
// 抛出即 std::terminate → abort()，外层 @try 挡不住。真机上就发生在导出诊断包时。
// 所有进入快照字典的浮点数一律先过这里：非有限值降级成字符串，
// 既保证 JSON 可写，也保留"当时到底是什么值"这条信息。
static id DYYYDiagFinite(double value) {
    if (isfinite(value)) return @(value);
    return isnan(value) ? @"nan" : (value > 0 ? @"inf" : @"-inf");
}

static NSString *DYYYDiagStringFromColor(UIColor *color) {
    if (!color) return @"";
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        CGFloat w = 0;
        if (![color getWhite:&w alpha:&a]) return DYYYDiagObjectDesc(color);
        r = g = b = w;
    }
    return [NSString stringWithFormat:@"rgba(%.3f,%.3f,%.3f,%.3f)", r, g, b, a];
}

static NSDictionary *DYYYDiagRectDict(CGRect rect) {
    return @{@"x": DYYYDiagFinite(rect.origin.x), @"y": DYYYDiagFinite(rect.origin.y),
             @"w": DYYYDiagFinite(rect.size.width), @"h": DYYYDiagFinite(rect.size.height)};
}

static NSDictionary *DYYYDiagPointDict(CGPoint point) {
    return @{@"x": DYYYDiagFinite(point.x), @"y": DYYYDiagFinite(point.y)};
}

static NSDictionary *DYYYDiagSizeDict(CGSize size) {
    return @{@"w": DYYYDiagFinite(size.width), @"h": DYYYDiagFinite(size.height)};
}

static NSDictionary *DYYYDiagAffineDict(CGAffineTransform t) {
    return @{@"a": DYYYDiagFinite(t.a), @"b": DYYYDiagFinite(t.b), @"c": DYYYDiagFinite(t.c),
             @"d": DYYYDiagFinite(t.d), @"tx": DYYYDiagFinite(t.tx), @"ty": DYYYDiagFinite(t.ty)};
}

static NSDictionary *DYYYDiagTransform3DDict(CATransform3D t) {
    return @{@"m11": DYYYDiagFinite(t.m11), @"m12": DYYYDiagFinite(t.m12), @"m13": DYYYDiagFinite(t.m13), @"m14": DYYYDiagFinite(t.m14),
             @"m21": DYYYDiagFinite(t.m21), @"m22": DYYYDiagFinite(t.m22), @"m23": DYYYDiagFinite(t.m23), @"m24": DYYYDiagFinite(t.m24),
             @"m31": DYYYDiagFinite(t.m31), @"m32": DYYYDiagFinite(t.m32), @"m33": DYYYDiagFinite(t.m33), @"m34": DYYYDiagFinite(t.m34),
             @"m41": DYYYDiagFinite(t.m41), @"m42": DYYYDiagFinite(t.m42), @"m43": DYYYDiagFinite(t.m43), @"m44": DYYYDiagFinite(t.m44)};
}

#pragma mark - 窗口与控制器工具

static BOOL DYYYDiagIsDebugWindow(UIWindow *window) {
    if (!window) return YES;
    // 前缀必须覆盖 DYYYDiag，不能只写 DYYYDiagnostics：
    // 浮层窗口类名是 DYYYDiagOverlayWindow，旧判断放它进了活动窗口列表，
    // 于是"目标窗口"可能选中浮层，导出/分享面板从浮层控制器弹出，
    // 分享结束后浮层残留 presentedViewController，capturesOverlayTouches
    // 返回 YES → 整屏吞触摸，表现为"界面被灰蒙版盖住、只有扳手能点"。
    NSString *cls = DYYYNameOfObject(window);
    return [cls hasPrefix:@"DYYYDiag"] || [cls hasPrefix:@"DYYYDiagnostics"] || [cls hasPrefix:@"FLEX"];
}

NSArray<UIWindow *> *DYYYDiagActiveWindows(void) {
    NSMutableArray<UIWindow *> *windows = [NSMutableArray array];
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) continue;
            if (scene.activationState != UISceneActivationStateForegroundActive) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (!window || DYYYDiagIsDebugWindow(window)) continue;
                if (window.hidden || window.alpha <= 0.01) continue;
                [windows addObject:window];
            }
        }
    }
    if (windows.count == 0) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        for (UIWindow *window in UIApplication.sharedApplication.windows) {
            if (!window || DYYYDiagIsDebugWindow(window)) continue;
            if (window.hidden || window.alpha <= 0.01) continue;
            [windows addObject:window];
        }
#pragma clang diagnostic pop
    }
    return windows;
}

UIWindow *DYYYDiagTargetWindow(void) {
    NSArray<UIWindow *> *windows = DYYYDiagActiveWindows();
    for (UIWindow *window in windows) if (window.isKeyWindow) return window;
    return windows.firstObject;
}

// 沿 responder 链找最近的 VC。
// 同一个父视图下的所有子视图走的是同一条链尾：跳过的层数完全一样，结果必然相同。
// 视图树有几百个节点时，逐节点重走 80 层是纯浪费（330 节点 × 80 ≈ 2.6 万次），
// 这里按"起点视图的 superview"做一次浅缓存，兄弟节点直接复用上一次的答案。
static UIViewController *DYYYDiagViewControllerForView(UIView *view) {
    if (!view) return nil;
    static __unsafe_unretained UIView *sCachedOrigin = nil;
    static UIViewController *sCachedVC = nil;
    UIView *origin = view.superview;
    if (origin && origin == sCachedOrigin) return sCachedVC;

    UIViewController *found = nil;
    UIResponder *responder = view;
    for (NSUInteger i = 0; responder && i < 80; i++) {
        responder = responder.nextResponder;
        if ([responder isKindOfClass:[UIViewController class]]) {
            found = (UIViewController *)responder;
            break;
        }
    }
    sCachedOrigin = origin;
    sCachedVC = found;
    return found;
}

static UIViewController *DYYYDiagTopViewControllerFrom(UIViewController *vc) {
    for (NSUInteger i = 0; vc && i < 80; i++) {
        if (vc.presentedViewController) {
            vc = vc.presentedViewController;
        } else if ([vc isKindOfClass:[UINavigationController class]]) {
            UIViewController *visible = ((UINavigationController *)vc).visibleViewController;
            if (!visible || visible == vc) break;
            vc = visible;
        } else if ([vc isKindOfClass:[UITabBarController class]]) {
            UIViewController *selected = ((UITabBarController *)vc).selectedViewController;
            if (!selected || selected == vc) break;
            vc = selected;
        } else {
            break;
        }
    }
    return vc;
}

UIViewController *DYYYDiagTopPresenter(UIWindow *window) {
    return DYYYDiagTopViewControllerFrom(window.rootViewController);
}

#pragma mark - 页面快照

static NSDictionary *DYYYDiagLayerInfo(CALayer *layer) {
    if (!layer) return @{};
    return @{
        @"class": DYYYDiagClassName(layer),
        @"address": DYYYDiagStringFromPointer((__bridge const void *)layer),
        @"bounds": DYYYDiagRectDict(layer.bounds),
        @"position": DYYYDiagPointDict(layer.position),
        @"anchorPoint": DYYYDiagPointDict(layer.anchorPoint),
        @"zPosition": DYYYDiagFinite(layer.zPosition),
        @"opacity": DYYYDiagFinite(layer.opacity),
        @"hidden": @(layer.hidden),
        @"masksToBounds": @(layer.masksToBounds),
        @"cornerRadius": DYYYDiagFinite(layer.cornerRadius),
        @"sublayerCount": @(layer.sublayers.count),
        @"transform": DYYYDiagTransform3DDict(layer.transform),
        @"mask": layer.mask ? @{
            @"class": DYYYDiagClassName(layer.mask),
            @"address": DYYYDiagStringFromPointer((__bridge const void *)layer.mask),
            @"bounds": DYYYDiagRectDict(layer.mask.bounds)
        } : @{}
    };
}

#pragma mark - 布局约束摘要

// 把一条约束翻译成可读文本：
//   UILabel.left == superview.left + 12  (p=1000, active)
// firstItem/secondItem 可能是 view 自己、父视图或兄弟视图，统一用类名+地址尾号表示。
static NSString *DYYYDiagConstraintText(NSLayoutConstraint *c, UIView *self_) {
    if (!c) return @"";
    NSString *first = c.firstItem ? [NSString stringWithFormat:@"%@<%p>",
                                     DYYYDiagClassName(c.firstItem), c.firstItem] : @"nil";
    NSString *second = c.secondItem ? [NSString stringWithFormat:@"%@<%p>",
                                      DYYYDiagClassName(c.secondItem), c.secondItem] : @"nil";
    // 把参与方简写成 self / super / sibling，便于阅读
    if (c.firstItem == self_) first = @"self";
    if (c.secondItem == self_) second = @"self";
    if (c.firstItem == self_.superview) first = @"super";
    if (c.secondItem == self_.superview) second = @"super";

    NSString *(^attrName)(NSLayoutAttribute) = ^NSString *(NSLayoutAttribute a) {
        switch (a) {
            case NSLayoutAttributeLeft: return @"left";
            case NSLayoutAttributeRight: return @"right";
            case NSLayoutAttributeTop: return @"top";
            case NSLayoutAttributeBottom: return @"bottom";
            case NSLayoutAttributeLeading: return @"leading";
            case NSLayoutAttributeTrailing: return @"trailing";
            case NSLayoutAttributeWidth: return @"width";
            case NSLayoutAttributeHeight: return @"height";
            case NSLayoutAttributeCenterX: return @"centerX";
            case NSLayoutAttributeCenterY: return @"centerY";
            case NSLayoutAttributeLastBaseline: return @"lastBaseline";
            case NSLayoutAttributeFirstBaseline: return @"firstBaseline";
            case NSLayoutAttributeNotAnAttribute: return @"notAnAttribute";
            default: return @"attr";
        }
    };
    NSString *rel = @"==";
    if (c.relation == NSLayoutRelationGreaterThanOrEqual) rel = @">=";
    else if (c.relation == NSLayoutRelationLessThanOrEqual) rel = @"<=";
    NSMutableString *text = [NSMutableString string];
    [text appendFormat:@"%@.%@ %@ ", first, attrName(c.firstAttribute), rel];
    if (c.secondItem) {
        [text appendFormat:@"%@.%@", second, attrName(c.secondAttribute)];
    }
    if (fabs(c.multiplier - 1.0) > 1e-6) {
        [text appendFormat:@" * %.3f", c.multiplier];
    }
    if (fabs(c.constant) > 1e-6) {
        [text appendFormat:@" %+.1f", c.constant];
    }
    [text appendFormat:@"  (p=%.0f%@)", c.priority, c.active ? @", active" : @""];
    return text;
}

// 收集与本 view 相关的约束：自身 + 父视图上涉及本 view 的。
// dumpAll=N 时最多取 limit 条，超出只回条数（避免诊断包暴涨）。
static NSArray<NSString *> *DYYYDiagConstraintsForView(UIView *view, NSUInteger limit, NSUInteger *totalOut) {
    if (!view) return @[];
    NSMutableArray<NSLayoutConstraint *> *all = [NSMutableArray array];
    for (NSLayoutConstraint *c in view.constraints) [all addObject:c];
    for (NSLayoutConstraint *c in view.superview.constraints) {
        if (c.firstItem == view || c.secondItem == view) [all addObject:c];
    }
    if (totalOut) *totalOut = all.count;
    NSMutableArray<NSString *> *out = [NSMutableArray array];
    for (NSUInteger i = 0; i < all.count && i < limit; i++) {
        [out addObject:DYYYDiagConstraintText(all[i], view)];
    }
    return out;
}
static NSMutableDictionary *DYYYDiagBaseViewInfo(UIView *view, NSUInteger depth) {
    UIViewController *nearestVC = DYYYDiagViewControllerForView(view);
    NSMutableDictionary *info = [@{
        @"class": DYYYDiagClassDisplayName(view),
        @"address": DYYYDiagStringFromPointer((__bridge const void *)view),
        @"depth": @(depth),
        @"frame": DYYYDiagRectDict(view.frame),
        @"bounds": DYYYDiagRectDict(view.bounds),
        @"center": DYYYDiagPointDict(view.center),
        @"alpha": DYYYDiagFinite(view.alpha),
        @"hidden": @(view.hidden),
        @"opaque": @(view.opaque),
        @"clipsToBounds": @(view.clipsToBounds),
        @"userInteractionEnabled": @(view.userInteractionEnabled),
        @"multipleTouchEnabled": @(view.multipleTouchEnabled),
        @"contentMode": @(view.contentMode),
        @"tag": @(view.tag),
        @"autoresizingMask": @(view.autoresizingMask),
        @"autoresizesSubviews": @(view.autoresizesSubviews),
        @"transform": DYYYDiagAffineDict(view.transform),
        @"backgroundColor": DYYYDiagStringFromColor(view.backgroundColor),
        @"tintColor": DYYYDiagStringFromColor(view.tintColor),
        @"accessibilityIdentifier": view.accessibilityIdentifier ?: @"",
        @"accessibilityLabel": view.accessibilityLabel ?: @"",
        @"nearestViewController": nearestVC ? @{
            @"class": DYYYDiagClassName(nearestVC),
            @"address": DYYYDiagStringFromPointer((__bridge const void *)nearestVC)
        } : @{},
        @"layer": DYYYDiagLayerInfo(view.layer),
        @"subviewCount": @(view.subviews.count),
        // 布局三件套：安全区、是否用约束布局、自身想要的尺寸
        @"safeAreaInsets": @{
            @"top": @(view.safeAreaInsets.top),
            @"left": @(view.safeAreaInsets.left),
            @"bottom": @(view.safeAreaInsets.bottom),
            @"right": @(view.safeAreaInsets.right)
        },
        @"translatesAutoresizingMaskIntoConstraints": @(view.translatesAutoresizingMaskIntoConstraints),
        @"intrinsicContentSize": DYYYDiagSizeDict(view.intrinsicContentSize)
    } mutableCopy];

    // 垂直方向的两个优先级：被压扁时靠它们判断是谁让步了。
    info[@"verticalHugging"] = @([view contentHuggingPriorityForAxis:UILayoutConstraintAxisVertical]);
    info[@"verticalCompressionResistance"] =
        @([view contentCompressionResistancePriorityForAxis:UILayoutConstraintAxisVertical]);

    // 约束列表：只在这个 view 自己有约束、或父视图约束涉及它时才展开。
    // 上限 12 条，超出只记总数——避免整棵树的约束把诊断包撑爆。
    // 用独立 autoreleasepool 包住：约束字符串是临时对象，几百个节点累积会明显抬内存峰值。
    {
        NSUInteger total = 0;
        __block NSArray<NSString *> *texts = nil;
        @autoreleasepool {
            texts = DYYYDiagConstraintsForView(view, 12, &total);
            if (total > 0) {
                info[@"constraintCount"] = @(total);
                info[@"constraints"] = texts;
            }
        }
    }

    if ([view isKindOfClass:[UILabel class]]) {
        UILabel *label = (UILabel *)view;
        info[@"label"] = @{
            @"text": label.text ?: @"",
            @"attributedText": label.attributedText.string ?: @"",
            @"font": DYYYDiagObjectDesc(label.font),
            @"textColor": DYYYDiagStringFromColor(label.textColor),
            @"numberOfLines": @(label.numberOfLines),
            @"textAlignment": @(label.textAlignment)
        };
    }
    if ([view isKindOfClass:[UIButton class]]) {
        UIButton *button = (UIButton *)view;
        info[@"button"] = @{
            @"currentTitle": [button titleForState:UIControlStateNormal] ?: (button.currentTitle ?: @""),
            @"currentAttributedTitle": button.currentAttributedTitle.string ?: @"",
            @"enabled": @(button.enabled),
            @"selected": @(button.selected),
            @"highlighted": @(button.highlighted)
        };
    }
    if ([view isKindOfClass:[UIImageView class]]) {
        UIImageView *imageView = (UIImageView *)view;
        info[@"imageView"] = @{
            @"imageSize": imageView.image ? DYYYDiagSizeDict(imageView.image.size) : @{},
            @"highlighted": @(imageView.highlighted)
        };
    }
    if ([view isKindOfClass:[UIControl class]]) {
        UIControl *control = (UIControl *)view;
        info[@"control"] = @{
            @"enabled": @(control.enabled),
            @"selected": @(control.selected),
            @"highlighted": @(control.highlighted),
            @"state": @(control.state)
        };
    }
    if ([view isKindOfClass:[UIScrollView class]]) {
        UIScrollView *scroll = (UIScrollView *)view;
        info[@"scrollView"] = @{
            @"contentOffset": DYYYDiagPointDict(scroll.contentOffset),
            @"contentSize": DYYYDiagSizeDict(scroll.contentSize),
            @"contentInset": NSStringFromUIEdgeInsets(scroll.contentInset),
            @"adjustedContentInset": NSStringFromUIEdgeInsets(scroll.adjustedContentInset),
            @"zoomScale": DYYYDiagFinite(scroll.zoomScale),
            @"minimumZoomScale": DYYYDiagFinite(scroll.minimumZoomScale),
            @"maximumZoomScale": DYYYDiagFinite(scroll.maximumZoomScale),
            @"pagingEnabled": @(scroll.pagingEnabled),
            @"scrollEnabled": @(scroll.scrollEnabled),
            @"dragging": @(scroll.dragging),
            @"tracking": @(scroll.tracking),
            @"decelerating": @(scroll.decelerating)
        };
    }
    if ([view isKindOfClass:[UIVisualEffectView class]]) {
        info[@"visualEffectView"] = @{ @"effect": DYYYDiagObjectDesc(((UIVisualEffectView *)view).effect) };
    }
    return info;
}

// 视图树遍历的硬上限。
// 之前递归没有任何深度/数量限制：抖音某些页面（直播间、商城、长列表）视图上千个、
// 层级几十层，递归会把栈撑爆，或让 3MB 级 JSON 涨到几十 MB 被系统杀掉——
// 表现出来就是"偶发闪退"。超限时不报错，写一条 truncated 说明继续导出其余部分。
static const NSUInteger kDYYYDiagMaxTreeDepth = 60;
static const NSUInteger kDYYYDiagMaxTreeNodes = 5000;

// 单次采集的节点计数，归采集入口持有，避免全局可变状态。
typedef struct {
    NSUInteger count;
    BOOL hitLimit;
} DYYYDiagTreeBudget;

static NSDictionary *DYYYDiagViewTreeJSON(UIView *view, NSUInteger depth, NSMutableArray *layers,
                                          DYYYDiagTreeBudget *budget) {
    if (depth >= kDYYYDiagMaxTreeDepth || budget->count >= kDYYYDiagMaxTreeNodes) {
        budget->hitLimit = YES;
        return @{@"truncated": @YES,
                 @"reason": depth >= kDYYYDiagMaxTreeDepth ? @"depth" : @"node-limit",
                 @"class": DYYYDiagClassName(view),
                 @"depth": @(depth)};
    }
    budget->count++;

    NSMutableDictionary *info = DYYYDiagBaseViewInfo(view, depth);
    [layers addObject:@{
        @"viewClass": info[@"class"],
        @"viewAddress": info[@"address"],
        @"nearestViewController": info[@"nearestViewController"],
        @"layer": info[@"layer"]
    }];
    NSMutableArray *children = [NSMutableArray arrayWithCapacity:view.subviews.count];
    for (UIView *subview in view.subviews) {
        @autoreleasepool {
            [children addObject:DYYYDiagViewTreeJSON(subview, depth + 1, layers, budget)];
        }
    }
    info[@"children"] = children;
    return info;
}

static void DYYYDiagAppendViewTreeText(UIView *view, NSUInteger depth, NSMutableString *out,
                                       DYYYDiagTreeBudget *budget) {
    if (depth >= kDYYYDiagMaxTreeDepth || budget->count >= kDYYYDiagMaxTreeNodes) {
        budget->hitLimit = YES;
        [out appendFormat:@"(truncated: %@ depth=%lu)\n",
         depth >= kDYYYDiagMaxTreeDepth ? @"depth" : @"node-limit",
         (unsigned long)depth];
        return;
    }
    budget->count++;

    NSMutableString *indent = [NSMutableString string];
    for (NSUInteger i = 0; i < depth; i++) [indent appendString:@"  "];
    UIViewController *vc = DYYYDiagViewControllerForView(view);
    NSUInteger cTotal = 0;
    DYYYDiagConstraintsForView(view, 0, &cTotal);
    [out appendFormat:@"%@%@ %@ frame=%@ bounds=%@ vc=%@ %@ hidden=%d alpha=%.3f clips=%d user=%d layer=%@ safe(t=%.0f,b=%.0f) transAuto=%d 约束=%lu\n",
     indent,
     DYYYDiagClassDisplayName(view),
     DYYYDiagStringFromPointer((__bridge const void *)view),
     NSStringFromCGRect(view.frame),
     NSStringFromCGRect(view.bounds),
     vc ? DYYYDiagClassName(vc) : @"",
     vc ? DYYYDiagStringFromPointer((__bridge const void *)vc) : @"",
     view.hidden,
     view.alpha,
     view.clipsToBounds,
     view.userInteractionEnabled,
     DYYYDiagClassName(view.layer),
     view.safeAreaInsets.top,
     view.safeAreaInsets.bottom,
     view.translatesAutoresizingMaskIntoConstraints ? 1 : 0,
     (unsigned long)cTotal];
    for (UIView *subview in view.subviews) DYYYDiagAppendViewTreeText(subview, depth + 1, out, budget);
}

static NSDictionary *DYYYDiagWindowJSON(UIWindow *window) {
    return @{
        @"class": DYYYDiagClassName(window),
        @"address": DYYYDiagStringFromPointer((__bridge const void *)window),
        @"frame": DYYYDiagRectDict(window.frame),
        @"bounds": DYYYDiagRectDict(window.bounds),
        @"windowLevel": DYYYDiagFinite(window.windowLevel),
        @"hidden": @(window.hidden),
        @"alpha": DYYYDiagFinite(window.alpha),
        @"keyWindow": @(window.isKeyWindow),
        @"rootViewController": window.rootViewController ? @{
            @"class": DYYYDiagClassName(window.rootViewController),
            @"address": DYYYDiagStringFromPointer((__bridge const void *)window.rootViewController)
        } : @{}
    };
}

static NSArray *DYYYDiagAncestorChain(UIView *view) {
    NSMutableArray *chain = [NSMutableArray array];
    UIView *v = view;
    for (NSUInteger depth = 0; v && depth < 120; depth++, v = v.superview) {
        [chain addObject:DYYYDiagBaseViewInfo(v, depth)];
    }
    return chain;
}

static void DYYYDiagAppendVCText(UIViewController *vc, NSUInteger depth, NSMutableString *out, NSHashTable *seen) {
    if (!vc || [seen containsObject:vc]) return;
    [seen addObject:vc];
    NSMutableString *indent = [NSMutableString string];
    for (NSUInteger i = 0; i < depth; i++) [indent appendString:@"  "];
    BOOL loaded = vc.isViewLoaded;
    UIView *view = loaded ? vc.view : nil;
    [out appendFormat:@"%@%@ %@ viewLoaded=%@ view=%@ %@ frame=%@\n",
     indent,
     DYYYDiagClassName(vc),
     DYYYDiagStringFromPointer((__bridge const void *)vc),
     loaded ? @"YES" : @"NO",
     DYYYDiagClassName(view),
     view ? DYYYDiagStringFromPointer((__bridge const void *)view) : @"",
     view ? NSStringFromCGRect(view.frame) : @"null"];

    if ([vc isKindOfClass:[UINavigationController class]]) {
        UINavigationController *nav = (UINavigationController *)vc;
        [out appendFormat:@"%@  nav.top=%@ nav.visible=%@\n", indent, DYYYDiagClassName(nav.topViewController), DYYYDiagClassName(nav.visibleViewController)];
    }
    if ([vc isKindOfClass:[UITabBarController class]]) {
        UITabBarController *tab = (UITabBarController *)vc;
        [out appendFormat:@"%@  tab.selected=%@\n", indent, DYYYDiagClassName(tab.selectedViewController)];
    }
    for (UIViewController *child in vc.childViewControllers) DYYYDiagAppendVCText(child, depth + 1, out, seen);
    if (vc.presentedViewController) {
        [out appendFormat:@"%@  presented:\n", indent];
        DYYYDiagAppendVCText(vc.presentedViewController, depth + 1, out, seen);
    }
}

// 按 windowLevel 从低到高逐个画，截图才等于用户真正看到的画面。
// 只画 key 窗口会漏掉浮层：抖音的内嵌画中画 AWEDPlayerPiPWindow 在 windowLevel 2000。
static NSData *DYYYDiagScreenshotPNG(UIWindow *targetWindow) {
    if (!targetWindow) return NSData.data;

    // 按 windowLevel 从低到高逐个画，截图才等于用户真正看到的画面。
    // 只画 key 窗口会漏层：内嵌画中画窗口在 windowLevel 2000，铺满全屏时
    // 只画目标窗口会得到一张"看起来正常但缺了主画面"的图，排查会绕远路。
    // scale 传 0 = 跟随屏幕，与设备实际像素一致。
    NSArray<UIWindow *> *windows =
        [DYYYDiagActiveWindows() sortedArrayUsingComparator:^NSComparisonResult(UIWindow *a, UIWindow *b) {
            if (a.windowLevel == b.windowLevel) return NSOrderedSame;
            return a.windowLevel < b.windowLevel ? NSOrderedAscending : NSOrderedDescending;
        }];
    if (windows.count == 0) windows = @[ targetWindow ];

    UIGraphicsBeginImageContextWithOptions(targetWindow.bounds.size, NO, 0);
    @try {
        for (UIWindow *window in windows) {
            BOOL drew = [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:NO];
            if (!drew) [window.layer renderInContext:UIGraphicsGetCurrentContext()];
        }
        UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
        return image ? UIImagePNGRepresentation(image) : NSData.data;
    } @catch (__unused NSException *exception) {
        return NSData.data;
    } @finally {
        UIGraphicsEndImageContext();
    }
}

#pragma mark - 页面类收集

// 收集一个类及其整条继承链的类名：跳过运行时生成子类噪声，但继续上溯。
// 全程不调用任何会触发 realize 的 runtime API：
//   · 名字走 DYYYDiagRawClassName（直读 class_ro_t.name）
//   · 父类走 DYYYDiagSuperClass（直读 class_t.superclass）
// 任何一次 realize 都可能把惰性 Swift 泛型类送进 demangler，
// 畸形 mangled 名 failAssert → abort。直播间里这类层最多，所以那边最易崩。
static void DYYYDiagCollectClassAndSupers(Class cls, NSMutableSet<NSString *> *names) {
    for (int i = 0; cls && i < 50; i++) {
        // 已知坏类立即停，不再对它们做任何读取或上溯。
        if (!DYYYDiagClassIsSafe(cls)) break;
        const char *raw = DYYYDiagRawClassName(cls);
        NSString *name = raw ? [NSString stringWithUTF8String:raw] : nil;
        if (name.length && !DYYYDiagClassNameIsRuntimeGenerated(name)) [names addObject:name];
        cls = DYYYDiagSuperClass(cls);
    }
}

static void DYYYDiagCollectPageClassesFromView(UIView *view, NSMutableSet<NSString *> *names) {
    if (!view) return;
    DYYYDiagCollectClassAndSupers(object_getClass(view), names);
    DYYYDiagCollectClassAndSupers(object_getClass(view.layer), names);
    for (UIView *sub in view.subviews) DYYYDiagCollectPageClassesFromView(sub, names);
}

static void DYYYDiagCollectPageClassesFromVC(UIViewController *vc, NSMutableSet<NSString *> *names, NSHashTable *seen) {
    if (!vc || [seen containsObject:vc]) return;
    [seen addObject:vc];
    DYYYDiagCollectClassAndSupers(object_getClass(vc), names);
    if (vc.isViewLoaded) DYYYDiagCollectClassAndSupers(object_getClass(vc.view), names);
    for (UIViewController *child in vc.childViewControllers) DYYYDiagCollectPageClassesFromVC(child, names, seen);
    if (vc.presentedViewController) DYYYDiagCollectPageClassesFromVC(vc.presentedViewController, names, seen);
}

static NSDictionary *DYYYDiagMetadata(UIWindow *targetWindow, CGPoint point) {
    extern NSString * const DYYYDiagVersion;
    extern NSString * const DYYYDiagBuildCommit;
    extern NSString * const DYYYDiagBuildBranch;
    extern NSString * const DYYYDiagBuildTime;
    return @{
        @"generatedAt": DYYYDiagObjectDesc(NSDate.date),
        @"dyyyVersion": DYYYDiagVersion,
        @"buildCommit": DYYYDiagBuildCommit,
        @"buildBranch": DYYYDiagBuildBranch,
        @"buildTime": DYYYDiagBuildTime,
        @"bundleIdentifier": NSBundle.mainBundle.bundleIdentifier ?: @"",
        @"bundleName": NSBundle.mainBundle.infoDictionary[@"CFBundleName"] ?: @"",
        @"appVersion": NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] ?: @"",
        @"buildVersion": NSBundle.mainBundle.infoDictionary[(NSString *)kCFBundleVersionKey] ?: @"",
        @"systemName": UIDevice.currentDevice.systemName ?: @"",
        @"systemVersion": UIDevice.currentDevice.systemVersion ?: @"",
        @"deviceModel": UIDevice.currentDevice.model ?: @"",
        @"screenBounds": DYYYDiagRectDict(UIScreen.mainScreen.bounds),
        @"tapPointInTargetWindow": DYYYDiagPointDict(point),
        @"targetWindow": targetWindow ? DYYYDiagWindowJSON(targetWindow) : @{}
    };
}

@implementation DYYYDiagnosticsContext
@end

// 分步打点用 Core 里的 DYYYDiagStep（写一行并立即落盘）。
// 崩溃发生在后台线程时，进程被杀后内存缓冲留不下任何东西，
// 每步主动 flush 才能保证 runtime.log 停在最后一个成功步骤。

DYYYDiagnosticsContext *DYYYDiagCaptureContext(UIWindow *targetWindow, CGPoint point, UIView *selectedView) {
    DYYYDiagStep(@"capture 开始");
    DYYYDiagnosticsContext *context = [DYYYDiagnosticsContext new];
    NSArray<UIWindow *> *windows = DYYYDiagActiveWindows();
    DYYYDiagStep([NSString stringWithFormat:@"windows 取得 %lu 个", (unsigned long)windows.count]);
    NSMutableArray *windowsJSON = [NSMutableArray array];
    NSMutableArray *treeJSON = [NSMutableArray array];
    NSMutableArray *layersJSON = [NSMutableArray array];
    NSMutableString *treeText = [NSMutableString string];
    NSMutableString *vcText = [NSMutableString string];
    NSHashTable *seenVCs = [NSHashTable weakObjectsHashTable];
    NSMutableSet<NSString *> *pageClasses = [NSMutableSet set];
    NSHashTable *seenClassVCs = [NSHashTable weakObjectsHashTable];
    BOOL treeTruncated = NO;

    for (UIWindow *window in windows) {
        NSString *winName = DYYYDiagClassName(window);
        [windowsJSON addObject:DYYYDiagWindowJSON(window)];
        DYYYDiagStep([NSString stringWithFormat:@"%@ windowsJSON 完成", winName]);
        // JSON 与文本树各自独立预算：两者遍历路径不同，不共享计数才能各自完整。
        DYYYDiagTreeBudget jsonBudget = {0, NO};
        DYYYDiagTreeBudget textBudget = {0, NO};
        if (DYYYDiagToggleEnabled(DYYYDiagToggleTree)) {
            [treeJSON addObject:DYYYDiagViewTreeJSON(window, 0, layersJSON, &jsonBudget)];
            DYYYDiagStep([NSString stringWithFormat:@"%@ 视图树JSON 完成 %lu 节点", winName, (unsigned long)jsonBudget.count]);
            DYYYDiagAppendViewTreeText(window, 0, treeText, &textBudget);
            DYYYDiagStep([NSString stringWithFormat:@"%@ 视图树文本 完成 %lu 节点", winName, (unsigned long)textBudget.count]);
            if (jsonBudget.hitLimit || textBudget.hitLimit) treeTruncated = YES;
        } else {
            DYYYDiagStep([NSString stringWithFormat:@"%@ 视图树 已跳过（开关关闭）", winName]);
        }
        if (DYYYDiagToggleEnabled(DYYYDiagToggleClasses)) {
            DYYYDiagCollectPageClassesFromView(window, pageClasses);
            DYYYDiagStep([NSString stringWithFormat:@"%@ 页面类(视图) 完成 %lu 个", winName, (unsigned long)pageClasses.count]);
            DYYYDiagCollectPageClassesFromVC(window.rootViewController, pageClasses, seenClassVCs);
            DYYYDiagStep([NSString stringWithFormat:@"%@ 页面类(VC) 完成 %lu 个", winName, (unsigned long)pageClasses.count]);
        } else {
            DYYYDiagStep([NSString stringWithFormat:@"%@ 页面类 已跳过（开关关闭）", winName]);
        }
        if (DYYYDiagToggleEnabled(DYYYDiagToggleVC) && window.rootViewController) {
            [vcText appendFormat:@"Window %@ %@\n", DYYYDiagClassName(window), DYYYDiagStringFromPointer((__bridge const void *)window)];
            DYYYDiagAppendVCText(window.rootViewController, 1, vcText, seenVCs);
            DYYYDiagStep([NSString stringWithFormat:@"%@ VC树 完成", winName]);
        } else if (!DYYYDiagToggleEnabled(DYYYDiagToggleVC)) {
            DYYYDiagStep([NSString stringWithFormat:@"%@ VC树 已跳过（开关关闭）", winName]);
        }
    }

    UIViewController *nearestVC = DYYYDiagViewControllerForView(selectedView);
    DYYYDiagStep(@"nearestVC 解析完成");
    NSDictionary *selected = @{
        @"tapPointInWindow": DYYYDiagPointDict(point),
        @"hitView": DYYYDiagBaseViewInfo(selectedView ?: targetWindow, 0),
        @"nearestViewController": nearestVC ? @{
            @"class": DYYYDiagClassName(nearestVC),
            @"address": DYYYDiagStringFromPointer((__bridge const void *)nearestVC)
        } : @{},
        @"ancestorChain": selectedView ? DYYYDiagAncestorChain(selectedView) : @[]
    };
    DYYYDiagStep(@"selectedView 信息完成");

    NSString *summary = [NSString stringWithFormat:
                         @"Hit: %@ %@\nFrame: %@\nBounds: %@\nNearest VC: %@ %@\nWindows: %lu\nSubviews: %lu",
                         DYYYDiagClassName(selectedView),
                         DYYYDiagStringFromPointer((__bridge const void *)selectedView),
                         selectedView ? NSStringFromCGRect(selectedView.frame) : @"",
                         selectedView ? NSStringFromCGRect(selectedView.bounds) : @"",
                         nearestVC ? DYYYDiagClassName(nearestVC) : @"",
                         nearestVC ? DYYYDiagStringFromPointer((__bridge const void *)nearestVC) : @"",
                         (unsigned long)windows.count,
                         (unsigned long)selectedView.subviews.count];
    DYYYDiagStep(@"summary 完成");

    NSMutableDictionary *metadata = [DYYYDiagMetadata(targetWindow, point) mutableCopy];
    if (treeTruncated) {
        // 快照被上限截断时明确标注，避免把"不完整"误读成"页面就这么大"。
        metadata[@"treeTruncated"] = @YES;
        metadata[@"treeLimitDepth"] = @(kDYYYDiagMaxTreeDepth);
        metadata[@"treeLimitNodes"] = @(kDYYYDiagMaxTreeNodes);
    }
    context.metadata = metadata;
    DYYYDiagStep(@"metadata 完成");
    context.windowsJSON = windowsJSON;
    context.viewTreeJSON = treeJSON;
    context.viewTreeText = treeText;
    context.selectedViewJSON = selected;
    context.viewControllersText = vcText;
    context.layersJSON = layersJSON;
    context.summary = summary;
    context.pageClassNames = pageClasses.allObjects;
    context.sourceView = targetWindow;
    context.presenter = DYYYDiagTopPresenter(targetWindow);
    DYYYDiagStep([NSString stringWithFormat:@"截图 开始 classes=%lu", (unsigned long)pageClasses.count]);
    if (DYYYDiagToggleEnabled(DYYYDiagToggleShot)) {
        context.screenshotPNG = DYYYDiagScreenshotPNG(targetWindow);
        DYYYDiagStep([NSString stringWithFormat:@"截图 完成 %lu 字节", (unsigned long)context.screenshotPNG.length]);
    } else {
        DYYYDiagStep(@"截图 已跳过（开关关闭）");
    }
    DYYYDiagStep(@"capture 全部完成");
    return context;
}
