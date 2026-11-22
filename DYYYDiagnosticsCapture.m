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
    return object ? DYYYNameOfObject(object) : @"";
}

static NSString *DYYYDiagObjectDesc(id object) {
    if (!object) return @"";
    @try {
        return [object description] ?: @"";
    } @catch (__unused NSException *e) {
        return @"(description threw)";
    }
}

static NSNumber *DYYYDiagNum(double value) {
    return @(value);
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
    return @{@"x": @(rect.origin.x), @"y": @(rect.origin.y),
             @"w": @(rect.size.width), @"h": @(rect.size.height)};
}

static NSDictionary *DYYYDiagPointDict(CGPoint point) {
    return @{@"x": @(point.x), @"y": @(point.y)};
}

static NSDictionary *DYYYDiagSizeDict(CGSize size) {
    return @{@"w": @(size.width), @"h": @(size.height)};
}

static NSDictionary *DYYYDiagAffineDict(CGAffineTransform t) {
    return @{@"a": @(t.a), @"b": @(t.b), @"c": @(t.c),
             @"d": @(t.d), @"tx": @(t.tx), @"ty": @(t.ty)};
}

static NSDictionary *DYYYDiagTransform3DDict(CATransform3D t) {
    return @{@"m11": @(t.m11), @"m12": @(t.m12), @"m13": @(t.m13), @"m14": @(t.m14),
             @"m21": @(t.m21), @"m22": @(t.m22), @"m23": @(t.m23), @"m24": @(t.m24),
             @"m31": @(t.m31), @"m32": @(t.m32), @"m33": @(t.m33), @"m34": @(t.m34),
             @"m41": @(t.m41), @"m42": @(t.m42), @"m43": @(t.m43), @"m44": @(t.m44)};
}

#pragma mark - 窗口与控制器工具

static BOOL DYYYDiagIsDebugWindow(UIWindow *window) {
    NSString *cls = DYYYNameOfObject(window);
    return [cls hasPrefix:@"DYYYDiagnostics"] || [cls hasPrefix:@"FLEX"];
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

static UIViewController *DYYYDiagViewControllerForView(UIView *view) {
    UIResponder *responder = view;
    for (NSUInteger i = 0; responder && i < 80; i++) {
        responder = responder.nextResponder;
        if ([responder isKindOfClass:[UIViewController class]]) return (UIViewController *)responder;
    }
    return nil;
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
        @"zPosition": DYYYDiagNum(layer.zPosition),
        @"opacity": DYYYDiagNum(layer.opacity),
        @"hidden": @(layer.hidden),
        @"masksToBounds": @(layer.masksToBounds),
        @"cornerRadius": DYYYDiagNum(layer.cornerRadius),
        @"sublayerCount": @(layer.sublayers.count),
        @"transform": DYYYDiagTransform3DDict(layer.transform),
        @"mask": layer.mask ? @{
            @"class": DYYYDiagClassName(layer.mask),
            @"address": DYYYDiagStringFromPointer((__bridge const void *)layer.mask),
            @"bounds": DYYYDiagRectDict(layer.mask.bounds)
        } : @{}
    };
}

static NSMutableDictionary *DYYYDiagBaseViewInfo(UIView *view, NSUInteger depth) {
    UIViewController *nearestVC = DYYYDiagViewControllerForView(view);
    NSMutableDictionary *info = [@{
        @"class": DYYYDiagClassName(view),
        @"address": DYYYDiagStringFromPointer((__bridge const void *)view),
        @"depth": @(depth),
        @"frame": DYYYDiagRectDict(view.frame),
        @"bounds": DYYYDiagRectDict(view.bounds),
        @"center": DYYYDiagPointDict(view.center),
        @"alpha": DYYYDiagNum(view.alpha),
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
        @"subviewCount": @(view.subviews.count)
    } mutableCopy];

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
            @"zoomScale": DYYYDiagNum(scroll.zoomScale),
            @"minimumZoomScale": DYYYDiagNum(scroll.minimumZoomScale),
            @"maximumZoomScale": DYYYDiagNum(scroll.maximumZoomScale),
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

static NSDictionary *DYYYDiagViewTreeJSON(UIView *view, NSUInteger depth, NSMutableArray *layers) {
    NSMutableDictionary *info = DYYYDiagBaseViewInfo(view, depth);
    [layers addObject:@{
        @"viewClass": info[@"class"],
        @"viewAddress": info[@"address"],
        @"nearestViewController": info[@"nearestViewController"],
        @"layer": info[@"layer"]
    }];
    NSMutableArray *children = [NSMutableArray arrayWithCapacity:view.subviews.count];
    for (UIView *subview in view.subviews) {
        [children addObject:DYYYDiagViewTreeJSON(subview, depth + 1, layers)];
    }
    info[@"children"] = children;
    return info;
}

static void DYYYDiagAppendViewTreeText(UIView *view, NSUInteger depth, NSMutableString *out) {
    NSMutableString *indent = [NSMutableString string];
    for (NSUInteger i = 0; i < depth; i++) [indent appendString:@"  "];
    UIViewController *vc = DYYYDiagViewControllerForView(view);
    [out appendFormat:@"%@%@ %@ frame=%@ bounds=%@ vc=%@ %@ hidden=%d alpha=%.3f clips=%d user=%d layer=%@\n",
     indent,
     DYYYDiagClassName(view),
     DYYYDiagStringFromPointer((__bridge const void *)view),
     NSStringFromCGRect(view.frame),
     NSStringFromCGRect(view.bounds),
     vc ? DYYYDiagClassName(vc) : @"",
     vc ? DYYYDiagStringFromPointer((__bridge const void *)vc) : @"",
     view.hidden,
     view.alpha,
     view.clipsToBounds,
     view.userInteractionEnabled,
     DYYYDiagClassName(view.layer)];
    for (UIView *subview in view.subviews) DYYYDiagAppendViewTreeText(subview, depth + 1, out);
}

static NSDictionary *DYYYDiagWindowJSON(UIWindow *window) {
    return @{
        @"class": DYYYDiagClassName(window),
        @"address": DYYYDiagStringFromPointer((__bridge const void *)window),
        @"frame": DYYYDiagRectDict(window.frame),
        @"bounds": DYYYDiagRectDict(window.bounds),
        @"windowLevel": DYYYDiagNum(window.windowLevel),
        @"hidden": @(window.hidden),
        @"alpha": DYYYDiagNum(window.alpha),
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

    NSArray<UIWindow *> *windows =
        [DYYYDiagActiveWindows() sortedArrayUsingComparator:^NSComparisonResult(UIWindow *a, UIWindow *b) {
            if (a.windowLevel == b.windowLevel) return NSOrderedSame;
            return a.windowLevel < b.windowLevel ? NSOrderedAscending : NSOrderedDescending;
        }];
    if (windows.count == 0) windows = @[ targetWindow ];

    UIGraphicsBeginImageContextWithOptions(targetWindow.bounds.size, NO, 0);
    for (UIWindow *window in windows) {
        BOOL drew = [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:NO];
        if (!drew) [window.layer renderInContext:UIGraphicsGetCurrentContext()];
    }
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image ? UIImagePNGRepresentation(image) : NSData.data;
}

#pragma mark - 页面类收集

// 收集一个类及其整条继承链的类名：跳过运行时生成子类噪声，但继续上溯。
// 必须用 class_getName 而不是 NSStringFromClass：抖音的 Swift 类里有畸形
// mangled 名，NSStringFromClass 会触发 swift demangle abort 杀掉进程。
static void DYYYDiagCollectClassAndSupers(Class cls, NSMutableSet<NSString *> *names) {
    for (int i = 0; cls && i < 50; i++) {
        if (!DYYYDiagClassIsSafe(cls)) break;
        const char *raw = class_getName(cls);
        NSString *name = raw ? [NSString stringWithUTF8String:raw] : nil;
        if (name.length && !DYYYDiagClassNameIsRuntimeGenerated(name)) [names addObject:name];
        cls = class_getSuperclass(cls);
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

DYYYDiagnosticsContext *DYYYDiagCaptureContext(UIWindow *targetWindow, CGPoint point, UIView *selectedView) {
    DYYYDiagnosticsContext *context = [DYYYDiagnosticsContext new];
    NSArray<UIWindow *> *windows = DYYYDiagActiveWindows();
    NSMutableArray *windowsJSON = [NSMutableArray array];
    NSMutableArray *treeJSON = [NSMutableArray array];
    NSMutableArray *layersJSON = [NSMutableArray array];
    NSMutableString *treeText = [NSMutableString string];
    NSMutableString *vcText = [NSMutableString string];
    NSHashTable *seenVCs = [NSHashTable weakObjectsHashTable];
    NSMutableSet<NSString *> *pageClasses = [NSMutableSet set];
    NSHashTable *seenClassVCs = [NSHashTable weakObjectsHashTable];

    for (UIWindow *window in windows) {
        [windowsJSON addObject:DYYYDiagWindowJSON(window)];
        [treeJSON addObject:DYYYDiagViewTreeJSON(window, 0, layersJSON)];
        DYYYDiagAppendViewTreeText(window, 0, treeText);
        DYYYDiagCollectPageClassesFromView(window, pageClasses);
        DYYYDiagCollectPageClassesFromVC(window.rootViewController, pageClasses, seenClassVCs);
        if (window.rootViewController) {
            [vcText appendFormat:@"Window %@ %@\n", DYYYDiagClassName(window), DYYYDiagStringFromPointer((__bridge const void *)window)];
            DYYYDiagAppendVCText(window.rootViewController, 1, vcText, seenVCs);
        }
    }

    UIViewController *nearestVC = DYYYDiagViewControllerForView(selectedView);
    NSDictionary *selected = @{
        @"tapPointInWindow": DYYYDiagPointDict(point),
        @"hitView": DYYYDiagBaseViewInfo(selectedView ?: targetWindow, 0),
        @"nearestViewController": nearestVC ? @{
            @"class": DYYYDiagClassName(nearestVC),
            @"address": DYYYDiagStringFromPointer((__bridge const void *)nearestVC)
        } : @{},
        @"ancestorChain": selectedView ? DYYYDiagAncestorChain(selectedView) : @[]
    };

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

    context.metadata = DYYYDiagMetadata(targetWindow, point);
    context.windowsJSON = windowsJSON;
    context.viewTreeJSON = treeJSON;
    context.viewTreeText = treeText;
    context.selectedViewJSON = selected;
    context.viewControllersText = vcText;
    context.layersJSON = layersJSON;
    context.screenshotPNG = DYYYDiagScreenshotPNG(targetWindow);
    context.summary = summary;
    context.pageClassNames = pageClasses.allObjects;
    context.sourceView = targetWindow;
    context.presenter = DYYYDiagTopPresenter(targetWindow);
    return context;
}
