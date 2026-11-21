//
//  DYYYHooksFullscreen.xm
//  从 DYYY.xm 拆出：Fullscreen 域 16 个 hook 块。
//
//  这些块原本不依赖 DYYY.xm 的块外 static 状态，因此可以独立成文件。
//  搬出时按原顺序整块复制，内容未改。
//

#import "DYYYShared.h"
#import "DYYYTargets.h"
#import <QuartzCore/QuartzCore.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <float.h>
#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <syslog.h>
#import "AwemeHeaders.h"
#import "DYYYCommentPlaybackCoordinator.h"
#import "DYYYHideMessageAndMinePageHooks.h"
#import "DYYYExactInteractionCountHooks.h"
#import "CityManager.h"
#import "DYYYBottomAlertView.h"
#import "DYYYManager.h"
#import "AWMSafeDispatchTimer.h"
#import "DYYYConstants.h"
#import "DYYYFloatClearButton.h"
#import "DYYYFloatSpeedButton.h"
#import "DYYYSettingViewController.h"
#import "DYYYToast.h"
#import "DYYYUtils.h"
#import "DYYYFullscreenCoordinator.h"
#import "DYYYCommentBlurCoordinator.h"
#import "DYYYFloatingButtonCoordinator.h"
#import "DYYYClassRegistry.h"
#import "DYYYDiag/Debug/DKDebugInspector.h"

%hook AWEPlayInteractionUserAvatarElement
- (void)onFollowViewClicked:(UITapGestureRecognizer *)gesture {
    if (DYYYGetBool(@"DYYYFollowTips")) {
        // 获取用户信息
        AWEUserModel *author = nil;
        NSString *nickname = @"";
        NSString *signature = @"";
        NSString *avatarURL = @"";

        if ([self respondsToSelector:@selector(model)]) {
            id model = [self model];
            if ([model isKindOfClass:NSClassFromString(@"AWEAwemeModel")]) {
                author = [model valueForKey:@"author"];
            }
        }

        if (author) {
            // 获取昵称
            if ([author respondsToSelector:@selector(nickname)]) {
                nickname = [author valueForKey:@"nickname"] ?: @"";
            }

            // 获取签名
            if ([author respondsToSelector:@selector(signature)]) {
                signature = [author valueForKey:@"signature"] ?: @"";
            }

            // 获取头像URL
            if ([author respondsToSelector:@selector(avatarThumb)]) {
                AWEURLModel *avatarThumb = [author valueForKey:@"avatarThumb"];
                if (avatarThumb && avatarThumb.originURLList.count > 0) {
                    avatarURL = avatarThumb.originURLList.firstObject;
                }
            }
        }

        NSMutableString *messageContent = [NSMutableString string];
        if (signature.length > 0) {
            [messageContent appendFormat:@"%@", signature];
        }

        NSString *title = nickname.length > 0 ? nickname : @"关注确认";

        [DYYYBottomAlertView showAlertWithTitle:title
                                        message:messageContent
                                      avatarURL:avatarURL
                               cancelButtonText:@"取消"
                              confirmButtonText:@"关注"
                                   cancelAction:nil
                                    closeAction:nil
                                  confirmAction:^{
                                    %orig(gesture);
                                  }];
    } else {
        %orig;
    }
}

%end

%hook AWEPlayInteractionUserAvatarFollowController
- (void)onFollowViewClicked:(UITapGestureRecognizer *)gesture {
    if (DYYYGetBool(@"DYYYFollowTips")) {
        // 获取用户信息
        AWEUserModel *author = nil;
        NSString *nickname = @"";
        NSString *signature = @"";
        NSString *avatarURL = @"";

        if ([self respondsToSelector:@selector(model)]) {
            id model = [self model];
            if ([model isKindOfClass:NSClassFromString(@"AWEAwemeModel")]) {
                author = [model valueForKey:@"author"];
            }
        }

        if (author) {
            // 获取昵称
            if ([author respondsToSelector:@selector(nickname)]) {
                nickname = [author valueForKey:@"nickname"] ?: @"";
            }

            // 获取签名
            if ([author respondsToSelector:@selector(signature)]) {
                signature = [author valueForKey:@"signature"] ?: @"";
            }

            // 获取头像URL
            if ([author respondsToSelector:@selector(avatarThumb)]) {
                AWEURLModel *avatarThumb = [author valueForKey:@"avatarThumb"];
                if (avatarThumb && avatarThumb.originURLList.count > 0) {
                    avatarURL = avatarThumb.originURLList.firstObject;
                }
            }
        }

        NSMutableString *messageContent = [NSMutableString string];
        if (signature.length > 0) {
            [messageContent appendFormat:@"%@", signature];
        }

        NSString *title = nickname.length > 0 ? nickname : @"关注确认";

        [DYYYBottomAlertView showAlertWithTitle:title
                                        message:messageContent
                                      avatarURL:avatarURL
                               cancelButtonText:@"取消"
                              confirmButtonText:@"关注"
                                   cancelAction:nil
                                    closeAction:nil
                                  confirmAction:^{
                                    %orig(gesture);
                                  }];
    } else {
        %orig;
    }
}

%end

%hook AWEPlayInteractionProgressContainerView

// ── 逐帧记录容器的位置变化（纯观测，不改值）──────────────────────
//
// #136 结论：该容器的 setFrame 一次都没被调用（pwrite = 0），
// 但用户实测「整条进度条连时间一起上移约一个底栏高度」。
// 整条一起动、又不是 setFrame → 只可能是 center 或 transform。
// 这两个入口 #136 没接，所以抓不到。
//
// 这里把 center / transform / bounds 全部接上，判据 0.01，带毫秒时间戳。
// 打完即删。
- (void)setBounds:(CGRect)bounds {
    CGRect old = self.bounds;
    %orig;
    if (!DYYYGetBool(@"DYYYDiagEntryEnabled")) return;
    if (fabs(old.size.height - bounds.size.height) < 0.01) return;
    static NSInteger sCount = 0;
    if (++sCount > 300) return;
    NSLog(@"[DYYY][cwrite] setBounds #%ld t=%.3f h %.2f→%.2f",
          (long)sCount, CFAbsoluteTimeGetCurrent(), old.size.height, bounds.size.height);
}

- (void)setFrame:(CGRect)frame {
    CGRect old = self.frame;
    %orig;
    if (!DYYYGetBool(@"DYYYDiagEntryEnabled")) return;
    if (fabs(old.origin.y - frame.origin.y) < 0.01 &&
        fabs(old.size.height - frame.size.height) < 0.01) {
        return;
    }
    static NSInteger sCount = 0;
    if (++sCount > 300) return;
    NSLog(@"[DYYY][cwrite] setFrame #%ld t=%.3f y %.2f→%.2f  h %.2f→%.2f",
          (long)sCount, CFAbsoluteTimeGetCurrent(),
          old.origin.y, frame.origin.y, old.size.height, frame.size.height);
}

- (void)setCenter:(CGPoint)center {
    CGPoint old = self.center;

    // ── 聊天页拖动进度条「弹起来」的修复 ────────────────────────────
    //
    // #138 诊断包实测（多次拖动，每次都完整出现一对）：
    //   setCenter y 743.00 → 660.00   按下开始拖：容器整体上移 83
    //   setCenter y 660.00 → 743.00   松手：落回
    // 743 − 660 = 83，正是输入栏高度。
    //
    // 成因：聊天页有一个快捷回复输入栏（AWEIMFeedVideoQuickReplayInput
    // ViewController）。抖音的原生逻辑是「拖动进度条时把进度条容器上移
    // 一个输入栏高度，给输入栏腾位置；松手再移回来」。
    // 普通视频详情页没有输入栏，所以不移动 —— 这就是只有聊天页弹的原因。
    //
    // 修法：在写入那一刻把「上移 83」这个位移忽略掉，容器始终留在原位。
    // 属于单次替换入参，不是「先写再纠正」，不会形成两方对写。
    //
    // 只在聊天页生效（容器挂在详情表里 + 全屏开着），其他页面一律放行。
    if (DYYYGetBool(@"DYYYEnableFullScreen")) {
        BOOL inDetailTable = NO;
        for (UIView *a = self.superview; a; a = a.superview) {
            if ([a isKindOfClass:[UITableView class]]) { inDetailTable = YES; break; }
        }
        if (inDetailTable) {
            // 把「静止位」记下来：容器第一次被放到详情表里时那个 y 就是它。
            // 之后无论谁来写，只要写的是「静止位 − 一个输入栏高度」这一档，
            // 就按静止位落地，容器肉眼不动。
            static char kRestKey;
            NSNumber *rest = objc_getAssociatedObject(self, &kRestKey);
            if (!rest) {
                // 只在容器已经有明确高度、且不在让位档上时，才认定为静止位
                CGFloat h = CGRectGetHeight(self.bounds);
                if (h > 1.0 && center.y > 100.0) {
                    rest = @(center.y);
                    objc_setAssociatedObject(self, &kRestKey, rest, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
            }
            if (rest) {
                CGFloat restY = rest.doubleValue;
                CGFloat shift = restY - center.y;
                if (shift > 60.0 && shift < 110.0 && fabs(center.x - old.x) < 0.01) {
                    if (DYYYGetBool(@"DYYYDiagEntryEnabled")) {
                        static NSInteger sBlocked = 0;
                        if (++sBlocked <= 40) {
                            NSLog(@"[DYYY][cblock] 拦下让位 %.1f（%.1f→%.1f 落回静止位 %.1f）",
                                  shift, old.y, center.y, restY);
                        }
                    }
                    center.y = restY;
                }
            }
        }
    }

    %orig(center);

    if (!DYYYGetBool(@"DYYYDiagEntryEnabled")) return;
    if (fabs(old.y - center.y) < 0.01) return;

    static NSInteger sCount = 0;
    if (++sCount > 300) return;

    NSLog(@"[DYYY][cwrite] setCenter #%ld t=%.3f y %.2f→%.2f（orig was %.2f）",
          (long)sCount, CFAbsoluteTimeGetCurrent(), old.y, center.y, center.y);
}

- (void)setTransform:(CGAffineTransform)transform {
    CGAffineTransform old = self.transform;
    %orig;
    if (!DYYYGetBool(@"DYYYDiagEntryEnabled")) return;
    if (fabs(old.ty - transform.ty) < 0.01 && fabs(old.a - transform.a) < 0.001) return;

    static NSInteger sCount = 0;
    if (++sCount > 300) return;

    NSMutableString *who = [NSMutableString string];
    if (sCount <= 40 && (sCount % 10) == 0) {
        NSArray<NSString *> *stack = [NSThread callStackSymbols];
        NSUInteger limit = MIN(stack.count, (NSUInteger)8);
        for (NSUInteger i = 1; i < limit; i++) {
            NSString *line = stack[i];
            NSRange r = [line rangeOfString:@"["];
            NSString *t = r.location != NSNotFound ? [line substringFromIndex:r.location] : line;
            [who appendFormat:@"\n        %@", t];
        }
    }
    NSLog(@"[DYYY][cwrite] setTransform #%ld t=%.3f ty %.2f→%.2f  scale %.3f→%.3f%@",
          (long)sCount, CFAbsoluteTimeGetCurrent(),
          old.ty, transform.ty, old.a, transform.a, who);
}

- (void)layoutSubviews {
    %orig;
    DYYYApplyFloatClearProgressStateToView(self);

    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYEnableFullScreen"]) {
        return;
    }

    static char kDYProgressBgKey;
    NSArray *bgViews = objc_getAssociatedObject(self, &kDYProgressBgKey);
    if (!bgViews) {
        NSMutableArray *tmp = [NSMutableArray array];
        for (UIView *subview in self.subviews) {
            if ([subview class] == [UIView class]) {
                [tmp addObject:subview];
            }
        }
        bgViews = [tmp copy];
        objc_setAssociatedObject(self, &kDYProgressBgKey, bgViews, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    for (UIView *v in bgViews) {
        v.backgroundColor = [UIColor clearColor];
    }
}

%end

%hook AWEPlayInteractionProgressController

%new
- (void)dyyy_syncScheduleLabelsWithCurrentTime:(CGFloat)currentTime totalDuration:(CGFloat)totalDuration {
    if (!DYYYGetBool(@"DYYYShowScheduleDisplay")) {
        return;
    }

    id progressSlider = self.progressSlider;
    if (progressSlider && [progressSlider respondsToSelector:@selector(dyyy_updateScheduleLabelsWithCurrentTime:totalDuration:)]) {
        [progressSlider dyyy_updateScheduleLabelsWithCurrentTime:currentTime totalDuration:totalDuration];
        return;
    }

    if ([progressSlider isKindOfClass:[UIView class]]) {
        [(UIView *)progressSlider dyyy_updateScheduleLabelsLegacyWithCurrentTime:currentTime totalDuration:totalDuration model:self.model];
    }
}

- (void)updateProgressSliderWithTime:(CGFloat)arg1 totalDuration:(CGFloat)arg2 {
    %orig;
    [self dyyy_syncScheduleLabelsWithCurrentTime:arg1 totalDuration:arg2];
}

%end

// 文案下移（DYYYDescriptionVerticalOffset）
//
// 类名演变：
//   41.0  AWEPlayInteractionDescriptionScrollView（容器本身就是 ScrollView）
//   41.1  该类已移除，文案改为 Element 体系装配：
//           AWEPlayInteractionDescriptionLabel
//             → UIView
//               → UIScrollView    ← 对这一层做 transform
//
// 该 hook 同时承担：文案下移 + 长按复制手势。
// 合并为一个 %hook 块（Logos 同组重复 %hook 同一个类会报 redefinition）。
%hook AWEPlayInteractionDescriptionLabel

static char kLongPressGestureKey;
static NSString *const kDYYYLongPressCopyEnabledKey = @"DYYYLongPressCopyTextEnabled";

- (void)didMoveToWindow {
    %orig;

    BOOL longPressCopyEnabled = DYYYGetBool(kDYYYLongPressCopyEnabledKey);

    if (![[NSUserDefaults standardUserDefaults] objectForKey:kDYYYLongPressCopyEnabledKey]) {
        longPressCopyEnabled = NO;
        [[NSUserDefaults standardUserDefaults] setBool:NO forKey:kDYYYLongPressCopyEnabledKey];
    }

    UIGestureRecognizer *existingGesture = objc_getAssociatedObject(self, &kLongPressGestureKey);
    if (existingGesture && !longPressCopyEnabled) {
        [self removeGestureRecognizer:existingGesture];
        objc_setAssociatedObject(self, &kLongPressGestureKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }

    if (longPressCopyEnabled && !objc_getAssociatedObject(self, &kLongPressGestureKey)) {
        UILongPressGestureRecognizer *highPriorityLongPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleHighPriorityLongPress:)];
        highPriorityLongPress.minimumPressDuration = 0.3;

        [self addGestureRecognizer:highPriorityLongPress];

        UIView *currentView = self;
        while (currentView.superview) {
            currentView = currentView.superview;

            for (UIGestureRecognizer *recognizer in currentView.gestureRecognizers) {
                if ([recognizer isKindOfClass:[UILongPressGestureRecognizer class]] || [recognizer isKindOfClass:[UIPinchGestureRecognizer class]]) {
                    [recognizer requireGestureRecognizerToFail:highPriorityLongPress];
                }
            }
        }

        objc_setAssociatedObject(self, &kLongPressGestureKey, highPriorityLongPress, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

%new
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if ([gestureRecognizer.view isEqual:self] && [gestureRecognizer isKindOfClass:[UILongPressGestureRecognizer class]]) {
        return NO;
    }
    return YES;
}

%new
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if ([gestureRecognizer.view isEqual:self] && [gestureRecognizer isKindOfClass:[UILongPressGestureRecognizer class]]) {
        return YES;
    }
    return NO;
}

%new
- (void)handleHighPriorityLongPress:(UILongPressGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer.state == UIGestureRecognizerStateBegan) {

        NSString *description = self.text;

        if (description.length > 0) {
            [[UIPasteboard generalPasteboard] setString:description];
            [DYYYToast showSuccessToastWithMessage:@"视频文案已复制"];
        }
    }
}

- (void)layoutSubviews {
    %orig;

    // 文案下移：41.1 起 Label 往上两层是真正的容器
    // （Label → UIView → UIScrollView），与旧版 ScrollView 类的相对位置一致。
    NSString *descriptionOffsetValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYDescriptionVerticalOffset"];
    if (descriptionOffsetValue.length > 0) {
        CGFloat verticalOffset = [descriptionOffsetValue floatValue];
        if (verticalOffset != 0) {
            UIView *containerView = self.superview.superview;
            if (containerView) {
                // 先归零再设值，避免多次 layout 叠加
                if (!CGAffineTransformIsIdentity(containerView.transform)) {
                    containerView.transform = CGAffineTransformIdentity;
                }
                containerView.transform = CGAffineTransformMakeTranslation(0, verticalOffset);
            }
        }
    }
    [DYYYFullscreenCoordinator layoutInformationLabel:self];
}

%end

%hook AWEPlayInteractionStrongifyShareContentView

- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideShareContentView")) {
        UIView *parentView = self.superview;
        if (parentView) {
            parentView.hidden = YES;
        } else {
            self.hidden = YES;
        }
    }
}

%end

%hook AWEPlayInteractionListenFeedView
- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHideMusicButton")) {
        [self removeFromSuperview];
        return;
    }
}
%end

%hook AWEFeedDataSafeTableView

- (void)setFrame:(CGRect)frame {
    if (!DYYYGetBool(@"DYYYEnableFullScreen") || !NSThread.isMainThread) {
        %orig;
        return;
    }
    // 撑高那一刻记录原高，作为 HUD 钉位的锚点；没被撑高的表（聊天页）不会记。
    UIView *parentForHeight = self.superview;
    CGFloat targetHeight = parentForHeight ? CGRectGetHeight(parentForHeight.bounds) : 0;
    if (targetHeight > 0 && CGRectGetHeight(frame) < targetHeight - 0.5 &&
        CGRectGetHeight(frame) >= targetHeight * 0.5) {
        DYYYGeoRememberOriginalHeight(self, CGRectGetHeight(frame));
    }
    CGRect adjusted = [DYYYFullscreenCoordinator adjustDetailTableFrame:self frame:frame];
    if (CGRectIsNull(adjusted)) {
        %orig;
        return;
    }
    if (DYYYGetBool(@"DYYYDiagEntryEnabled")) {
        NSLog(@"[DYYY][table] setFrame 顶高 %.1f → %.1f", CGRectGetHeight(frame), CGRectGetHeight(adjusted));
    }
    %orig(adjusted);
}

// 布局后补正：只走与 setFrame 同一个守卫函数，不另开第二个写入通道。
//
// 原来这里直接写 `self.frame.size.height = 父视图高`，绕过了
// adjustDetailTableFrame 的守卫，属于「多点写入」。行为对照的写法是
// 在控制器 viewDidLayoutSubviews 前后各同步一次，且每次都经过同一个函数。
//
// 守卫里的 `current >= target - 容差 → 放行` 会自动把聊天页摘出去：
// 该页表高本来就是满的（实测 926），不会被误拉满，也不需要 IM 特判。
- (void)layoutSubviews {
    %orig;
    if (!DYYYGetBool(@"DYYYEnableFullScreen") || !NSThread.isMainThread) return;

    UIView *sv = self.superview;
    CGFloat target = sv ? CGRectGetHeight(sv.bounds) : 0;
    if (target <= 0.0) return;

    CGRect f = self.frame;
    CGRect adjusted = [DYYYFullscreenCoordinator adjustDetailTableFrame:self frame:f target:target];
    if (CGRectIsNull(adjusted)) return;

    if (CGRectGetHeight(f) < target - 0.5 && CGRectGetHeight(f) >= target * 0.5) {
        DYYYGeoRememberOriginalHeight(self, CGRectGetHeight(f));
    }
    self.frame = adjusted;
}

%end

// ===== 详情页行高入口全覆盖 =====
// 行高/翻页基准的查询链路不经过 AWEAwemeDetailTableViewController 的
// respondsToSelector 主路径——真实 delegate 容器与数据层各持一份基准高度。
// 每个入口都接同一个行高纯函数，保证"建行/落点/翻页看到同一行高"。
// 各入口带挂载确认日志（诊断模式），改版失效一眼可见。

// delegate 容器：滚动/翻页吸附读它
// 群聊视频详情页（IM 详情）保持原生行高：拖动让位是原生交互
%hook AWEDetailFeedScrollDelegateContainer

- (CGFloat)fixedCellHeight {
    CGFloat original = %orig;
    CGFloat adjusted = [DYYYFullscreenCoordinator fullCellHeightForNative:original];
    if (DYYYGetBool(@"DYYYDiagEntryEnabled")) {
        static BOOL loggedOnce = NO;
        if (!loggedOnce) { loggedOnce = YES;
            NSLog(@"[DYYY][rowh] AWEDetailFeedScrollDelegateContainer.fixedCellHeight 挂载生效 %.1f → %.1f", original, adjusted);
        }
    }
    return adjusted;
}

%end

// 他人主页作品详情：数据层基准（从直播间/带直播卡主页进入时行高走这里）
%hook AWEUserProfileAdDataLayer

- (CGFloat)originalTableViewHeight {
    CGFloat original = %orig;
    return [DYYYFullscreenCoordinator fullCellHeightForNative:original];
}
- (void)setOriginalTableViewHeight:(CGFloat)height {
    %orig([DYYYFullscreenCoordinator fullCellHeightForNative:height]);
}

%end

%hook AWEUserProFileAdVideoDataController

- (CGFloat)originalTableViewHeight {
    CGFloat original = %orig;
    return [DYYYFullscreenCoordinator fullCellHeightForNative:original];
}
- (void)updateOriginalTableViewHeight:(CGFloat)height {
    %orig([DYYYFullscreenCoordinator fullCellHeightForNative:height]);
}

%end

// 作者正在直播时主页作品详情：直播卡布局（provider block 返回压缩高度，须在此处改）
%hook AWELivePostWorkLiveCardLayoutController

- (CGFloat)originalTableViewHeight {
    CGFloat original = %orig;
    return [DYYYFullscreenCoordinator fullCellHeightForNative:original];
}
- (void)setOriginalTableViewHeight:(CGFloat)height {
    %orig([DYYYFullscreenCoordinator fullCellHeightForNative:height]);
}

%end

%hook AWELivePostWorkLiveCardLayoutDataLayer

- (CGFloat)normalHeight {
    CGFloat original = %orig;
    return [DYYYFullscreenCoordinator fullCellHeightForNative:original];
}
- (CGFloat)originalTableViewHeight {
    CGFloat original = %orig;
    return [DYYYFullscreenCoordinator fullCellHeightForNative:original];
}
- (void)setOriginalTableViewHeight:(CGFloat)height {
    %orig([DYYYFullscreenCoordinator fullCellHeightForNative:height]);
}

%end

%hook AWEPlayInteractionSearchAnchorView

- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideInteractionSearch")) {
        [self removeFromSuperview];
        return;
    }
    %orig;
}

%end

%hook AWEPlayInteractionTemplateButton
- (id)button {
	BOOL DYYYHideBottomInteraction = DYYYGetBool(@"DYYYHideBottomInteraction");
	if (DYYYHideBottomInteraction) {
		return nil;
	}
	return %orig;
}

- (void)setButton:(id)button {
	BOOL DYYYHideBottomInteraction = DYYYGetBool(@"DYYYHideBottomInteraction");
	if (DYYYHideBottomInteraction) {
		return;  // 不设置按钮
	}
	%orig;
}
%end

%hook AWEPlayInteractionLiveExtendGuideView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideLiveCapsuleView")) {
        [self removeFromSuperview];
        return;
    }
    %orig;
}
%end

%hook AWEFeedTableViewController

- (void)viewDidLayoutSubviews {
    [DYYYFullscreenCoordinator syncFeedTableHeight:self];
    %orig;
    [DYYYFullscreenCoordinator syncFeedTableHeight:self];
}

%end

%hook AWEFeedTableViewCell
- (void)prepareForReuse {
    if (hideButton && hideButton.isElementsHidden) {
        [hideButton hideUIElements];
    }
    %orig;
}

- (void)layoutSubviews {
    %orig;
    if (hideButton && hideButton.isElementsHidden) {
        [hideButton hideUIElements];
    }
}
%end

%hook AWEDPlayerProgressContainerView

- (void)layoutSubviews {
    %orig;
    DYYYApplyFloatClearProgressStateToView(self);

    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYEnableFullScreen"]) {
        return;
    }

    for (UIView *subview in self.subviews) {
        if ([subview isMemberOfClass:[UIView class]]) {
            UIColor *bgColor = subview.backgroundColor;
            if (bgColor) {
                CGFloat h, s, v, a;
                if ([bgColor getHue:&h saturation:&s brightness:&v alpha:&a]) {
                    if (v < 0.2) {
                        subview.backgroundColor = [UIColor clearColor];
                    }
                }
            }
        }
    }
}

%end

%hook AWEPlayInteractionCommentPanelController
- (void)performCommentAction {
    [DYYYFullscreenCoordinator beginCommentInWindow:[DYYYUtils getActiveWindow]];
    %orig;
}
%end
