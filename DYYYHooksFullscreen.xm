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

// ── 进度条拖动弹跳修复：约束不动，transform 补视觉偏移 ──────────────
//
// 已确认的事实：
//   #138 诊断包：setCenter 在 743 ↔ 660 之间成对翻转，差值 83（输入栏高度）
//   #140 调用栈：四条栈前 7 帧完全相同 → Auto Layout 约束求解路径
//   即：这 83pt 不是动画代码写的，是每轮布局重新解约束算出来的。
//
// 所以改 frame / 改 center / 拦写入全部无效 —— 约束一重算就覆盖。
// （#139 拦 setCenter 把容器钉死在 826，整条推出屏幕，进度条消失。）
//
// transform 不参与 auto layout，约束求解不会重置它。
// 在布局之后用 transform 把视觉位置补回正确值，是唯一不与约束对写的手段。
//
// 正确位置直接算，不采样（#139 就是采样采到 826 才崩）：
//   容器锚点居中 → 正确 center.y = 父视图高 − 容器高 / 2
//   实测校验：843 − 200/2 = 743（与诊断包静止位一致）
static void DYYYProgressPinVisual(UIView *container) {
    if (![container isKindOfClass:[UIView class]]) return;

    // 关掉全屏时复位，不留残留。
    if (!DYYYGetBool(@"DYYYEnableFullScreen")) {
        if (!CGAffineTransformIsIdentity(container.transform)) {
            container.transform = CGAffineTransformIdentity;
        }
        return;
    }

    // 只在详情表里生效（聊天页/详情页），其它页面不碰。
    BOOL inTable = NO;
    for (UIView *a = container.superview; a; a = a.superview) {
        if ([a isKindOfClass:[UITableView class]]) { inTable = YES; break; }
    }
    if (!inTable) {
        if (!CGAffineTransformIsIdentity(container.transform)) {
            container.transform = CGAffineTransformIdentity;
        }
        return;
    }

    UIView *parent = container.superview;
    CGFloat parentH = parent ? CGRectGetHeight(parent.bounds) : 0;
    CGFloat containerH = CGRectGetHeight(container.bounds);
    if (parentH <= 0.0 || containerH <= 0.0) return;

    CGFloat correctCenterY = parentH - containerH / 2.0;
    CGFloat delta = correctCenterY - container.center.y;

    // 只补偿「差一个输入栏高度」这一档；初始化中间态、横屏等一律复位不动。
    if (fabs(delta) < 1.0 || fabs(delta) > 120.0) {
        if (!CGAffineTransformIsIdentity(container.transform)) {
            container.transform = CGAffineTransformIdentity;
        }
        return;
    }

    CGAffineTransform target = CGAffineTransformMakeTranslation(0, delta);
    if (!CGAffineTransformEqualToTransform(container.transform, target)) {
        container.transform = target;
        if (DYYYGetBool(@"DYYYDiagEntryEnabled")) {
            static NSInteger sPinned = 0;
            if (++sPinned <= 30) {
                NSLog(@"[DYYY][cpin] 补偿 %.2f（当前 %.2f 应为 %.2f，父高 %.0f 容器高 %.0f）",
                      delta, container.center.y, correctCenterY, parentH, containerH);
            }
        }
    }
}

- (void)layoutSubviews {
    %orig;
    DYYYApplyFloatClearProgressStateToView(self);

    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYEnableFullScreen"]) {
        if (!CGAffineTransformIsIdentity(self.transform)) {
            self.transform = CGAffineTransformIdentity;
        }
        return;
    }

    DYYYProgressPinVisual(self);

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

// 第二入口：容器随 cell 平移时不会重新布局，挂入窗口时也要同步一次。
// （行为对照里记录过这一点；只挂 layoutSubviews 会漏掉这类平移。）
- (void)didMoveToWindow {
    %orig;
    DYYYProgressPinVisual(self);
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

// 表撑高与详情页行高已移入 DYYYFullscreenCoreHooks（唯一写入通道）。


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
