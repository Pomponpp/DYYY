//
//  DYYYProgressUnderlineFix.xm
//  DYYY
//
//  独立文件：清除进度条底部那条「黑线」（近黑、满宽、极薄、不透明的细垫层）。
//
//  设计要点（为降低与上游同步的冲突）：
//  1. 本文件不修改 DYYY.xm / DYYYSettings.xm 等既有文件，只新增自身 + Makefile 一行。
//  2. logos 多层 %hook 会正常串联，因此与既有进度容器 hook 并存不冲突。
//  3. 仅在「全屏开启」或「容器已被撑到接近整屏宽」时清理，普通模式尽量不改动外观。
//  4. 匹配条件保守：只清不透明、偏黑、极薄(<=3pt)、满宽、贴左的 UIView，
//     排除 UIControl（滑块/按钮）与隐藏视图，避免误伤进度轨道与缩略图。
//
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "AwemeHeaders.h"

static void DYYYFixClearProgressUnderline(UIView *container) {
    if (!container || ![NSThread isMainThread]) return;

    BOOL fsOn = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYEnableFullScreen"];
    CGFloat w = CGRectGetWidth(container.bounds);
    CGFloat screenW = CGRectGetWidth([UIScreen mainScreen].bounds);
    // 容器被撑到接近整屏宽：全屏/撑满场景（含仅由外部插件撑满的情况）
    BOOL stretched = (w > 0.0 && fabs(w - screenW) < 2.0);
    if (!fsOn && !stretched) return;

    static const CGFloat tol = 1.0;

    // 直接子视图 + 下探一层，覆盖抖音改类名/换层级的情况
    NSMutableArray<UIView *> *candidates = [NSMutableArray arrayWithArray:container.subviews];
    for (UIView *sub in container.subviews) {
        if (sub.subviews.count) {
            [candidates addObjectsFromArray:sub.subviews];
        }
    }

    for (UIView *v in candidates) {
        if (![v isKindOfClass:[UIView class]]) continue;
        if ([v isKindOfClass:[UIControl class]]) continue;  // 不碰滑块、按钮等可交互控件
        if (v.hidden) continue;

        UIColor *color = v.backgroundColor;
        if (!color) continue;

        CGFloat hue = 0, sat = 0, bright = 0, alpha = 0;
        if (![color getHue:&hue saturation:&sat brightness:&bright alpha:&alpha]) continue;
        if (alpha < 0.99) continue;          // 只清不透明（半透明分隔线不动）
        if (bright > 0.2) continue;          // 只清偏黑

        CGRect f = v.frame;
        CGFloat hgt = CGRectGetHeight(f);
        if (hgt <= 0.0 || hgt > 3.0) continue;             // 极薄
        if (fabs(CGRectGetMinX(f)) > tol) continue;        // 贴左
        if (fabs(CGRectGetWidth(f) - w) > tol) continue;   // 满宽

        v.backgroundColor = [UIColor clearColor];
        v.opaque = NO;
    }
}

%hook AWEPlayInteractionProgressContainerView
- (void)layoutSubviews {
    %orig;

    // 群聊「拖动时进度条上移」的定位探针（只打日志，不改值）。
    // 录屏逐帧测出：拖动过程中进度条 y 从 1740px 上移到 1563px，
    // 约 87pt ≈ tabBarHeight(83)，松手后弹回。
    // 这里记录容器自身位置，看是容器整体上移还是内部滑块单独上移。
    static CGRect lastFrame;
    CGRect f = self.frame;
    if (!CGRectEqualToRect(lastFrame, f)) {
        lastFrame = f;
        NSLog(@"[DYYY][prog] 容器 frame=%@ super=%@",
              NSStringFromCGRect(f), NSStringFromClass([self.superview class]));
    }

    DYYYFixClearProgressUnderline(self);
}
%end

%hook AWEDPlayerProgressContainerView

- (void)layoutSubviews {
    %orig;

    // 群聊拖动时这个容器整体上移了约 83pt（= tabBarHeight），松手复原。
    // 记录自身与父视图位置，判断是谁动的。
    static CGRect lastFrame;
    static CGRect lastSuperFrame;
    CGRect f = self.frame;
    CGRect sf = self.superview ? self.superview.frame : CGRectZero;
    if (!CGRectEqualToRect(lastFrame, f) || !CGRectEqualToRect(lastSuperFrame, sf)) {
        lastFrame = f;
        lastSuperFrame = sf;
        NSLog(@"[DYYY][prog] 容器D frame=%@ 父=%@ super=%@",
              NSStringFromCGRect(f), NSStringFromCGRect(sf),
              NSStringFromClass([self.superview class]));
    }

    DYYYFixClearProgressUnderline(self);
}

// 谁在改这个容器的 frame？打调用栈，一次就能定位。
- (void)setFrame:(CGRect)frame {
    CGFloat oldY = self.frame.origin.y;
    if (fabs(oldY - frame.origin.y) > 1.0) {
        NSLog(@"[DYYY][prog] 容器D setFrame y %.1f → %.1f", oldY, frame.origin.y);
        NSArray<NSString *> *stack = [NSThread callStackSymbols];
        NSUInteger limit = MIN(stack.count, (NSUInteger)14);
        for (NSUInteger i = 0; i < limit; i++) {
            NSLog(@"[DYYY][prog]    %@", stack[i]);
        }
    }
    %orig;
}

// 位置也可能走 center 而不是 frame，一起挂上。
- (void)setCenter:(CGPoint)center {
    CGFloat oldY = self.center.y;
    if (fabs(oldY - center.y) > 1.0) {
        NSLog(@"[DYYY][prog] 容器D setCenter y %.1f → %.1f", oldY, center.y);
        NSArray<NSString *> *stack = [NSThread callStackSymbols];
        NSUInteger limit = MIN(stack.count, (NSUInteger)14);
        for (NSUInteger i = 0; i < limit; i++) {
            NSLog(@"[DYYY][prog]    %@", stack[i]);
        }
    }
    %orig;
}

%end

%hook AWEStoryProgressContainerView
- (void)layoutSubviews {
    %orig;
    DYYYFixClearProgressUnderline(self);
}
%end

// 注：AWEDProgressCoreContainer 在 AwemeHeaders.h 中并非 UIView 子类，无法安全转换，
// 故不在此 hook，避免编译错误。
