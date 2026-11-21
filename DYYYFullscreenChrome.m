//
//  DYYYFullscreenChrome.m
//  DYYY
//
//  视频全屏的页面装饰层实现。
//
//  三条铁律（行为对照里反复记录过，都是踩坑换来的）：
//
//  1. 装饰层只叠 transform，不改 frame
//     改 frame 会与父布局互相追赶：父每轮写回原高、我们再撑高，
//     主线程卡死在 layoutSublayers / layoutBelowIfNeeded，
//     5 秒退不出 → FRONTBOARD 0x8BADF00D。
//
//  2. 只接管「原本没有 transform」的目标
//     抖音自己在动它（缩放交互）就让开，首次接管时存原值。
//
//  3. 位移量只由「Cell 满高 − 表撑高原高」决定
//     与被移动视图自己的 frame 无关，原生怎么重排都算出同一个值，
//     天然不成环；命中测试跟随 transform，按钮照常可点。
//

#import "DYYYFullscreenChrome.h"
#import "DYYYFullscreenCore.h"
#import "AwemeHeaders.h"
#import "DYYYConfigCache.h"
#import <objc/runtime.h>
#import <math.h>

static const CGFloat kDYYYChromeTolerance = 0.5;
// 从内容视图往上找视频表的层数上限（音乐卡在图文列表与集合视图 cell 里，比普通视频深）。
static const NSUInteger kDYYYCardTableDepth = 16;
// 背景条取样：合并后的首次取样与补取样的延迟。
static const NSTimeInterval kDYYYSampleDelay = 0.05;
static const NSTimeInterval kDYYYResampleDelay = 0.6;

// 接管标记（每类目标一套，互不覆盖）
static char kDYYYRichClipKey;
static char kDYYYRichGradientTransformKey;
static char kDYYYVideoGradientTransformKey;
static char kDYYYLiveChromeTransformKey;
static char kDYYYRichCenterStateKey;
static char kDYYYConstraintOriginalKey;
static char kDYYYStatusBarCoverHiddenKey;

// 接管过的目标（弱引用），供关闭开关时统一还原
static NSHashTable *gDYYYManagedViews;
static NSHashTable *gDYYYFittedConstraints;
static NSHashTable *gDYYYBackdropHosts;

// 统计
static NSUInteger gDYYYRichShrinkBlocked;
static NSUInteger gDYYYLiveLifts;
static NSUInteger gDYYYCardFits[DYYYCardTypeCount];
static NSUInteger gDYYYCardBackdrops[DYYYCardTypeCount];
static NSUInteger gDYYYMissingConstraints;
// 各入口被调用次数：用来区分「没生效」和「压根没被调到」。
static NSUInteger gDYYYHitShrink;
static NSUInteger gDYYYHitRichOverflow;
static NSUInteger gDYYYHitRichGradient;
static NSUInteger gDYYYHitRichCenter;
static NSUInteger gDYYYHitCardInset;
static NSUInteger gDYYYHitCardFit;
static NSUInteger gDYYYHitCardBackdrop;
static NSUInteger gDYYYHitLive;
static NSUInteger gDYYYHitVideoGradient;
static NSUInteger gDYYYHitCover;

#pragma mark - 工具

static void DYYYChromeInitTables(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      gDYYYManagedViews = [NSHashTable weakObjectsHashTable];
      gDYYYFittedConstraints = [NSHashTable weakObjectsHashTable];
      gDYYYBackdropHosts = [NSHashTable weakObjectsHashTable];
    });
}

// center/bounds/anchorPoint 不受 transform 影响，可据此还原应用前的几何。
static CGRect DYYYIdentityFrameInSuperview(UIView *view) {
    CGFloat width = CGRectGetWidth(view.bounds);
    CGFloat height = CGRectGetHeight(view.bounds);
    CGFloat minX = view.center.x - width * view.layer.anchorPoint.x;
    CGFloat minY = view.center.y - height * view.layer.anchorPoint.y;
    return CGRectMake(minX, minY, width, height);
}

// 只接管原本没有 transform 的目标；首次修改时保存原值。
static BOOL DYYYApplyVerticalLift(UIView *view, const void *baselineKey, CGFloat lift) {
    if (!view || lift <= kDYYYChromeTolerance) return NO;

    NSValue *baseline = objc_getAssociatedObject(view, baselineKey);
    if (!baseline) {
        // 抖音自己在动它（缩放交互）就让开。
        if (!CGAffineTransformIsIdentity(view.transform)) return NO;
        baseline = [NSValue valueWithCGAffineTransform:view.transform];
        objc_setAssociatedObject(view, baselineKey, baseline, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        DYYYChromeInitTables();
        [gDYYYManagedViews addObject:view];
    }

    CGAffineTransform target = CGAffineTransformMakeTranslation(0.0, -lift);
    if (!CGAffineTransformEqualToTransform(view.transform, target)) {
        view.transform = target;
    }
    return YES;
}

// 纵向拉伸：把 top→targetBottom 这段撑满（只叠 transform）。
static BOOL DYYYApplyVerticalStretch(UIView *view, const void *baselineKey,
                                     CGFloat top, CGFloat targetBottom) {
    if (!view) return NO;
    CGFloat height = CGRectGetHeight(view.bounds);
    if (height <= 0.0 || targetBottom <= top + height + kDYYYChromeTolerance) return NO;

    CGFloat scaleY = (targetBottom - top) / height;
    if (scaleY <= 1.0 + 1e-4) return NO;

    NSValue *baseline = objc_getAssociatedObject(view, baselineKey);
    if (!baseline) {
        if (!CGAffineTransformIsIdentity(view.transform)) return NO;
        baseline = [NSValue valueWithCGAffineTransform:view.transform];
        objc_setAssociatedObject(view, baselineKey, baseline, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        DYYYChromeInitTables();
        [gDYYYManagedViews addObject:view];
    }

    CGAffineTransform transform = CGAffineTransformMake(
        1.0, 0.0, 0.0, scaleY, 0.0, (height / 2.0) * (scaleY - 1.0));
    if (!CGAffineTransformEqualToTransform(view.transform, transform)) {
        view.transform = transform;
    }
    return YES;
}

static void DYYYRestoreTransformBaseline(UIView *view, const void *baselineKey) {
    NSValue *baseline = objc_getAssociatedObject(view, baselineKey);
    if (!baseline) return;
    view.transform = baseline.CGAffineTransformValue;
    objc_setAssociatedObject(view, baselineKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// 视频所在 cell 的内容视图高度 = 视频要铺满的目标。
static double DYYYCellHeightFor(UIView *view) {
    UIView *probe = view.superview;
    static Class contentCls;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ contentCls = NSClassFromString(@"UITableViewCellContentView"); });
    if (!contentCls) return 0.0;
    for (NSUInteger i = 0; probe && i < 12; i++, probe = probe.superview) {
        if ([probe isKindOfClass:contentCls]) return CGRectGetHeight(probe.bounds);
    }
    return 0.0;
}
#pragma mark - 图文

void DYYYChromeSuppressRichShrink(UIViewController *controller) {
    // 缩放抑制在钩子层直接 return，不进 %orig；这里只做计数。
    if (!controller) return;
    gDYYYHitShrink++;
    gDYYYRichShrinkBlocked++;
}

// 图文向 Cell 底部溢出时，只解除真实阻挡它的裁剪层；原本不裁剪的不接管。
void DYYYChromeAllowRichOverflow(UIView *view) {
    if (!view) return;
    gDYYYHitRichOverflow++;
    DYYYChromeInitTables();

    if (!objc_getAssociatedObject(view, &kDYYYRichClipKey)) {
        if (!view.clipsToBounds) return;
        objc_setAssociatedObject(view, &kDYYYRichClipKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [gDYYYManagedViews addObject:view];
    }
    if (view.clipsToBounds) view.clipsToBounds = NO;
}

static void DYYYRestoreRichOverflow(UIView *view) {
    if (!objc_getAssociatedObject(view, &kDYYYRichClipKey)) return;
    view.clipsToBounds = YES;
    objc_setAssociatedObject(view, &kDYYYRichClipKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void DYYYChromeStretchRichGradient(UIView *gradient) {
    if (!gradient) return;
    gDYYYHitRichGradient++;
    CGFloat height = CGRectGetHeight(gradient.bounds);
    UIView *container = gradient.superview;
    if (!container || height <= 0.0) return;

    // 渐变只铺到原内容底边，Cell 撑高后下面那段会露出。
    // 只叠纵向缩放，不动 frame：改 frame 会与父布局互相追赶。
    CGFloat top = gradient.center.y - height / 2.0;
    CGFloat target = DYYYFullscreenCoreOn() ? DYYYCellHeightFor(gradient) : 0.0;
    if (target <= 0.0) {
        DYYYRestoreTransformBaseline(gradient, &kDYYYRichGradientTransformKey);
        return;
    }
    if (!DYYYApplyVerticalStretch(gradient, &kDYYYRichGradientTransformKey, top, target)) {
        DYYYRestoreTransformBaseline(gradient, &kDYYYRichGradientTransformKey);
    }
}
CGAffineTransform DYYYChromeRichCenterTransform(UIView *view, CGAffineTransform native) {
    gDYYYHitRichCenter++;
    if (!DYYYFullscreenCoreOn()) return native;
    // 原生写入非单位矩阵（用户正在缩放）→ 保持原生值，释放接管。
    if (!CGAffineTransformIsIdentity(native)) return native;
    return native;
}

#pragma mark - 卡片

CGFloat DYYYChromeCardInset(UIView *view) {
    if (!view || !DYYYFullscreenCoreOn()) return 0.0;
    gDYYYHitCardInset++;

    UIView *table = nil;
    UITableViewCell *cell = nil;
    UIView *probe = view.superview;
    if ([view isKindOfClass:[UITableViewCell class]]) cell = (UITableViewCell *)view;

    for (NSUInteger depth = 0; probe && depth < kDYYYCardTableDepth; depth++, probe = probe.superview) {
        if (DYYYFullscreenTableForView(probe)) { table = DYYYFullscreenTableForView(probe); break; }
        if ([probe isKindOfClass:[UITableViewCell class]]) cell = (UITableViewCell *)probe;
    }
    if (!table || !cell) return 0.0;

    NSNumber *original = DYYYFullscreenTableOriginalHeight(table);
    if (!original) return 0.0;   // 表没被撑高过 → 这页不在作用域

    // 原高以当前行顶边为锚；换到宿主坐标后，只让出它实际越过安全底边的部分。
    CGPoint safeBottom = [cell convertPoint:CGPointMake(0.0, original.doubleValue) toView:view];
    CGFloat inset = CGRectGetMaxY(view.bounds) - safeBottom.y;
    return inset > kDYYYChromeTolerance ? MIN(CGRectGetHeight(view.bounds), inset) : 0.0;
}

// container.bottom == anchor.bottom（或两项颠倒）的等式约束，装在 anchor 上。
static NSLayoutConstraint *DYYYCardBottomConstraint(UIView *container, BOOL *reversed) {
    for (UIView *anchor = container.superview; anchor; anchor = anchor.superview) {
        for (NSLayoutConstraint *c in anchor.constraints) {
            if (!c.active || c.relation != NSLayoutRelationEqual
                || c.firstAttribute != NSLayoutAttributeBottom
                || c.secondAttribute != NSLayoutAttributeBottom
                || c.multiplier != 1.0) continue;
            if (c.firstItem == container && c.secondItem == anchor) { *reversed = NO; return c; }
            if (c.firstItem == anchor && c.secondItem == container) { *reversed = YES; return c; }
        }
        if ([anchor isKindOfClass:[UITableViewCell class]]
            || [anchor isKindOfClass:[UICollectionViewCell class]]) break;
    }
    return nil;
}

static void DYYYRestoreConstraint(NSLayoutConstraint *c) {
    NSNumber *original = objc_getAssociatedObject(c, &kDYYYConstraintOriginalKey);
    if (!original) return;
    c.constant = original.doubleValue;
    objc_setAssociatedObject(c, &kDYYYConstraintOriginalKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [gDYYYFittedConstraints removeObject:c];
}

BOOL DYYYChromeFitCard(UIView *container, CGFloat inset, DYYYCardType type) {
    if (!container.superview || type >= DYYYCardTypeCount) return NO;
    gDYYYHitCardFit++;
    DYYYChromeInitTables();

    BOOL reversed = NO;
    NSLayoutConstraint *bottom = DYYYCardBottomConstraint(container, &reversed);
    if (!bottom) {
        if (inset > 0.0) gDYYYMissingConstraints++;
        return NO;
    }
    if (inset <= 0.0) {
        DYYYRestoreConstraint(bottom);
        return NO;
    }

    NSNumber *original = objc_getAssociatedObject(bottom, &kDYYYConstraintOriginalKey);
    if (!original) {
        original = @(bottom.constant);
        objc_setAssociatedObject(bottom, &kDYYYConstraintOriginalKey, original,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [gDYYYFittedConstraints addObject:bottom];
    }
    CGFloat target = original.doubleValue + (reversed ? inset : -inset);
    if (fabs(bottom.constant - target) <= kDYYYChromeTolerance) return YES;
    bottom.constant = target;
    gDYYYCardFits[type]++;
    return YES;
}

#pragma mark - 卡片背景条

@interface DYYYCardBackdropView : UIImageView
@property(nonatomic) BOOL samplePending;
@property(nonatomic) BOOL resamplePending;
@property(nonatomic) CGFloat contentBottom;
@property(nonatomic) CGRect sourceBounds;
@end

@implementation DYYYCardBackdropView
@end

static DYYYCardBackdropView *DYYYCardBackdrop(UIView *host) {
    for (UIView *subview in host.subviews) {
        if ([subview isKindOfClass:[DYYYCardBackdropView class]]) return (DYYYCardBackdropView *)subview;
    }
    return nil;
}

void DYYYChromeSyncCardBackdrop(UIView *host, CGFloat inset, DYYYCardType type) {
    if (!host || type >= DYYYCardTypeCount) return;
    gDYYYHitCardBackdrop++;
    DYYYChromeInitTables();

    DYYYCardBackdropView *strip = DYYYCardBackdrop(host);
    if (inset <= 0.0) {
        [strip removeFromSuperview];
        [gDYYYBackdropHosts removeObject:host];
        return;
    }
    if (!strip) {
        strip = [[DYYYCardBackdropView alloc] initWithFrame:CGRectZero];
        strip.userInteractionEnabled = NO;
        strip.contentMode = UIViewContentModeScaleToFill;
        strip.hidden = YES;
        [host insertSubview:strip atIndex:0];
        [gDYYYBackdropHosts addObject:host];
        gDYYYCardBackdrops[type]++;
    } else if (host.subviews.firstObject != strip) {
        [host insertSubview:strip atIndex:0];
    }
    CGFloat bottom = CGRectGetMaxY(host.bounds) - inset;
    if (strip.contentBottom != bottom || !CGRectEqualToRect(strip.sourceBounds, host.bounds)) {
        strip.contentBottom = bottom;
        strip.sourceBounds = host.bounds;
        strip.image = nil;
        strip.hidden = YES;
        strip.frame = CGRectMake(CGRectGetMinX(host.bounds), bottom,
                                 CGRectGetWidth(host.bounds), inset);
        DYYYChromeRequestBackdropSample(host);
    }
}

// 在底部预留量对应的内容横带内，从下往上找整行不透明像素。
static UIImage *DYYYCardBottomImage(UIView *host, DYYYCardBackdropView *strip, CGFloat *bottom) {
    CGRect bounds = host.bounds;
    CGFloat scale = host.traitCollection.displayScale;
    if (scale <= 0.0) return nil;

    CGFloat end = floor(strip.contentBottom * scale) / scale;
    CGFloat depth = MIN(end - CGRectGetMinY(bounds), CGRectGetMaxY(bounds) - strip.contentBottom);
    if (depth <= 0.0 || CGRectGetWidth(bounds) <= 0.0) return nil;

    size_t width = (size_t)floor(CGRectGetWidth(bounds) * scale);
    size_t height = (size_t)ceil(depth * scale);
    CGFloat top = end - height / scale;

    CGColorSpaceRef space = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, width * 4, space,
        kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!context) return nil;

    CGContextTranslateCTM(context, 0.0, height);
    CGContextScaleCTM(context, scale, -scale);
    CGContextTranslateCTM(context, -CGRectGetMinX(bounds), -top);

    // 背景条已延伸进原内容的透明边时，取样仍只读取原页面。
    BOOL hidden = strip.layer.hidden;
    strip.layer.hidden = YES;
    [host.layer renderInContext:context];
    strip.layer.hidden = hidden;

    const uint8_t *pixels = CGBitmapContextGetData(context);
    size_t stride = CGBitmapContextGetBytesPerRow(context);
    UIImage *image = nil;

    for (size_t row = height; row > 0; row--) {
        const uint8_t *line = pixels + (row - 1) * stride;
        BOOL opaque = YES;
        for (size_t x = 0; x < width; x++) {
            if (line[x * 4 + 3] != UINT8_MAX) { opaque = NO; break; }
        }
        if (!opaque) continue;
        CGImageRef snapshot = CGBitmapContextCreateImage(context);
        CGImageRef sample = CGImageCreateWithImageInRect(snapshot, CGRectMake(0, row - 1, width, 1));
        image = [UIImage imageWithCGImage:sample scale:scale orientation:UIImageOrientationUp];
        CGImageRelease(sample);
        CGImageRelease(snapshot);
        *bottom = top + row / scale;
        break;
    }
    CGContextRelease(context);
    return image;
}

static void DYYYCardSampleBackdrop(UIView *host) {
    DYYYCardBackdropView *strip = DYYYCardBackdrop(host);
    if (!strip || !host.window) return;
    CGFloat bottom = 0.0;
    UIImage *image = DYYYCardBottomImage(host, strip, &bottom);
    strip.image = image;
    strip.hidden = image == nil;
    if (!image) return;
    strip.frame = CGRectMake(CGRectGetMinX(host.bounds), bottom,
                             CGRectGetWidth(host.bounds),
                             CGRectGetMaxY(host.bounds) - bottom);
}

// 每条背景条各合并一次短延迟取样与一次补取样；布局连续到达时不累积延时任务。
static void DYYYCardScheduleSample(UIView *host, NSTimeInterval delay, BOOL resample) {
    DYYYCardBackdropView *strip = DYYYCardBackdrop(host);
    if (resample ? strip.resamplePending : strip.samplePending) return;
    if (resample) strip.resamplePending = YES;
    else strip.samplePending = YES;

    __weak UIView *weakHost = host;
    __weak DYYYCardBackdropView *weakStrip = strip;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
                     UIView *strongHost = weakHost;
                     DYYYCardBackdropView *strongStrip = weakStrip;
                     if (!strongStrip || !DYYYFullscreenCoreOn()
                         || DYYYCardBackdrop(strongHost) != strongStrip) return;
                     if (resample) strongStrip.resamplePending = NO;
                     else strongStrip.samplePending = NO;
                     DYYYCardSampleBackdrop(strongHost);
                   });
}

void DYYYChromeRequestBackdropSample(UIView *host) {
    if (!DYYYFullscreenCoreOn() || !host || !DYYYCardBackdrop(host)) return;
    DYYYCardScheduleSample(host, kDYYYSampleDelay, NO);
    DYYYCardScheduleSample(host, kDYYYResampleDelay, YES);
}

#pragma mark - 直播 / 视频渐变 / 顶部遮罩

// 位移量 = Cell 满高 − 表撑高原高；表没被撑高过返回 0。
static CGFloat DYYYLiveLift(UIView *container) {
    UIView *table = DYYYFullscreenTableForView(container);
    NSNumber *original = table ? DYYYFullscreenTableOriginalHeight(table) : nil;
    if (!original) return 0.0;

    CGFloat full = DYYYCellHeightFor(container);
    if (full <= 0.0) return 0.0;
    // 容器还没跟着 cell 一起长高时同样返回 0：那一刻 chrome 仍贴着矮容器的底。
    if (CGRectGetHeight(container.bounds) < full - kDYYYChromeTolerance) return 0.0;
    return full - original.doubleValue;
}

void DYYYChromeLiftLiveChrome(UIView *container) {
    if (!container) return;
    gDYYYHitLive++;
    CGFloat lift = DYYYFullscreenCoreOn() ? DYYYLiveLift(container) : 0.0;

    // 只认具名槽位，不做遍历：遍历找目标在冷启动上时灵时不灵。
    id control = [container respondsToSelector:NSSelectorFromString(@"controlContainer")]
                     ? [container performSelector:NSSelectorFromString(@"controlContainer")] : nil;
    id watermark = [container respondsToSelector:NSSelectorFromString(@"bottomDarkWatermark")]
                       ? [container performSelector:NSSelectorFromString(@"bottomDarkWatermark")] : nil;

    for (id target in @[ control ?: [NSNull null], watermark ?: [NSNull null] ]) {
        if (![target isKindOfClass:[UIView class]]) continue;
        if (!DYYYApplyVerticalLift((UIView *)target, &kDYYYLiveChromeTransformKey, lift)) {
            DYYYRestoreTransformBaseline((UIView *)target, &kDYYYLiveChromeTransformKey);
        }
    }
    if (lift > kDYYYChromeTolerance) gDYYYLiveLifts++;
}

void DYYYChromeStretchVideoGradient(UIView *gradient) {
    if (!gradient) return;
    gDYYYHitVideoGradient++;
    CGFloat height = CGRectGetHeight(gradient.bounds);
    UIView *container = gradient.superview;
    if (!container || height <= 0.0) return;

    CGFloat top = gradient.center.y - height / 2.0;
    CGFloat containerHeight = CGRectGetHeight(container.bounds);
    // 只处理「不贴底」的压暗层：贴底的本来就该跟着容器走。
    if (top <= 1.0 || top + height >= containerHeight - 1.0) {
        DYYYRestoreTransformBaseline(gradient, &kDYYYVideoGradientTransformKey);
        return;
    }
    if (!DYYYApplyVerticalStretch(gradient, &kDYYYVideoGradientTransformKey, top, containerHeight)) {
        DYYYRestoreTransformBaseline(gradient, &kDYYYVideoGradientTransformKey);
    }
}

// 遮罩高度是「窗口」安全区高，尺子必须取窗口的：
// HUD 根视图在 cell 里，它自己的安全区随 cell 在滚动视图中的位置变化。
static CGFloat DYYYStatusBarCoverHeight(UIView *hudView) {
    UIWindow *window = hudView.window;
    return window ? window.safeAreaInsets.top : hudView.safeAreaInsets.top;
}

static UIView *DYYYFindStatusBarCover(UIView *hudView) {
    CGFloat safeTop = DYYYStatusBarCoverHeight(hudView);
    CGFloat width = CGRectGetWidth(hudView.bounds);
    if (safeTop <= 1.0 || width <= 0.0) return nil;

    for (UIView *view in hudView.subviews) {
        if (object_getClass(view) != [UIView class]) continue;
        if (!view.opaque || view.hidden) continue;

        CGRect frame = view.frame;
        if (fabs(CGRectGetMinX(frame)) > 1.0 || fabs(CGRectGetMinY(frame)) > 1.0
            || fabs(CGRectGetWidth(frame) - width) > 1.0
            || fabs(CGRectGetHeight(frame) - safeTop) > 2.0) continue;

        UIColor *bg = view.backgroundColor;
        if (!bg) continue;
        CGFloat h, s, b, a;
        if (![bg getHue:&h saturation:&s brightness:&b alpha:&a]) continue;
        if (b <= 0.05) return view;   // 纯黑
    }
    return nil;
}

void DYYYChromeHideStatusBarCover(UIViewController *interaction) {
    gDYYYHitCover++;
    UIView *hudView = interaction.viewIfLoaded;
    if (!hudView) return;

    if (DYYYFullscreenCoreOn()) {
        UIView *cover = DYYYFindStatusBarCover(hudView);
        if (cover) {
            cover.hidden = YES;
            objc_setAssociatedObject(cover, &kDYYYStatusBarCoverHiddenKey, @YES,
                                     OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
        return;
    }
    // 关闭后还原被我们藏起来的那些。
    for (UIView *view in hudView.subviews) {
        if (!objc_getAssociatedObject(view, &kDYYYStatusBarCoverHiddenKey)) continue;
        view.hidden = NO;
        objc_setAssociatedObject(view, &kDYYYStatusBarCoverHiddenKey, nil,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

#pragma mark - 还原与统计

void DYYYChromeRestoreAll(void) {
    DYYYChromeInitTables();
    for (UIView *view in gDYYYManagedViews.allObjects) {
        DYYYRestoreTransformBaseline(view, &kDYYYRichGradientTransformKey);
        DYYYRestoreTransformBaseline(view, &kDYYYVideoGradientTransformKey);
        DYYYRestoreTransformBaseline(view, &kDYYYLiveChromeTransformKey);
        DYYYRestoreRichOverflow(view);
    }
    [gDYYYManagedViews removeAllObjects];
    for (NSLayoutConstraint *c in gDYYYFittedConstraints.allObjects) DYYYRestoreConstraint(c);
    [gDYYYFittedConstraints removeAllObjects];
    for (UIView *host in gDYYYBackdropHosts.allObjects) [DYYYCardBackdrop(host) removeFromSuperview];
    [gDYYYBackdropHosts removeAllObjects];
}

NSString *DYYYChromeStats(void) {
    DYYYChromeInitTables();
    return [NSString stringWithFormat:
            @"入口命中 图文缩放=%lu 溢出=%lu 图文渐变=%lu 媒体居中=%lu | "
             "卡片 inset=%lu 收短=%lu 背景条=%lu | 直播=%lu 视频渐变=%lu 遮罩=%lu",
            (unsigned long)gDYYYHitShrink, (unsigned long)gDYYYHitRichOverflow,
            (unsigned long)gDYYYHitRichGradient, (unsigned long)gDYYYHitRichCenter,
            (unsigned long)gDYYYHitCardInset, (unsigned long)gDYYYHitCardFit,
            (unsigned long)gDYYYHitCardBackdrop,
            (unsigned long)gDYYYHitLive, (unsigned long)gDYYYHitVideoGradient,
            (unsigned long)gDYYYHitCover];
}

NSString *DYYYChromeStatsDetail(void) {
    DYYYChromeInitTables();
    return [NSString stringWithFormat:
            @"生效 图文缩放被拦=%lu 直播抬升=%lu 卡片收短=%lu/%lu/%lu "
             "背景条=%lu/%lu/%lu 缺约束=%lu 接管中=视图%lu 约束%lu 背景条%lu",
            (unsigned long)gDYYYRichShrinkBlocked, (unsigned long)gDYYYLiveLifts,
            (unsigned long)gDYYYCardFits[DYYYCardTypeSpecial],
            (unsigned long)gDYYYCardFits[DYYYCardTypeMusic],
            (unsigned long)gDYYYCardFits[DYYYCardTypeArticle],
            (unsigned long)gDYYYCardBackdrops[DYYYCardTypeSpecial],
            (unsigned long)gDYYYCardBackdrops[DYYYCardTypeMusic],
            (unsigned long)gDYYYCardBackdrops[DYYYCardTypeArticle],
            (unsigned long)gDYYYMissingConstraints,
            (unsigned long)gDYYYManagedViews.allObjects.count,
            (unsigned long)gDYYYFittedConstraints.allObjects.count,
            (unsigned long)gDYYYBackdropHosts.allObjects.count];
}
