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
    // 群聊视频详情页（IM 详情）保持原生表高，见 isImDetailView: 注释
    if ([DYYYFullscreenCoordinator isImDetailView:self]) {
        %orig;
        return;
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

// 兜底：若布局后仍矮于父视图（布局早期半成品漏网），再拉满一次。
// 聊天系视频页（群聊/朋友聊天）必须放行：该页原生表就是"扣底栏 843"，
// 兜底会把表拉满到 926，与原生让位布局打架——实测此路径是拖动"弹"的
// 直接写入者（setFrame 已排除，但本兜底只按高度判断，未做会话排除）。
- (void)layoutSubviews {
    %orig;
    if (!DYYYGetBool(@"DYYYEnableFullScreen") || !NSThread.isMainThread) return;
    if ([DYYYFullscreenCoordinator isImDetailView:self]) return;
    UIView *sv = self.superview;
    if (sv && CGRectGetHeight(sv.bounds) > 0 && self.frame.size.height < CGRectGetHeight(sv.bounds) - 0.5) {
        CGRect f = self.frame;
        f.size.height = CGRectGetHeight(sv.bounds);
        self.frame = f;
    }
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
    if ([DYYYFullscreenCoordinator isImDetailView:self]) return original;
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
    if ([DYYYFullscreenCoordinator isImDetailView:self]) return original;
    return [DYYYFullscreenCoordinator fullCellHeightForNative:original];
}
- (void)setOriginalTableViewHeight:(CGFloat)height {
    %orig([DYYYFullscreenCoordinator isImDetailView:self] ? height : [DYYYFullscreenCoordinator fullCellHeightForNative:height]);
}

%end

%hook AWEUserProFileAdVideoDataController

- (CGFloat)originalTableViewHeight {
    CGFloat original = %orig;
    if ([DYYYFullscreenCoordinator isImDetailView:self]) return original;
    return [DYYYFullscreenCoordinator fullCellHeightForNative:original];
}
- (void)updateOriginalTableViewHeight:(CGFloat)height {
    %orig([DYYYFullscreenCoordinator isImDetailView:self] ? height : [DYYYFullscreenCoordinator fullCellHeightForNative:height]);
}

%end

// 作者正在直播时主页作品详情：直播卡布局（provider block 返回压缩高度，须在此处改）
%hook AWELivePostWorkLiveCardLayoutController

- (CGFloat)originalTableViewHeight {
    CGFloat original = %orig;
    if ([DYYYFullscreenCoordinator isImDetailView:self]) return original;
    return [DYYYFullscreenCoordinator fullCellHeightForNative:original];
}
- (void)setOriginalTableViewHeight:(CGFloat)height {
    %orig([DYYYFullscreenCoordinator isImDetailView:self] ? height : [DYYYFullscreenCoordinator fullCellHeightForNative:height]);
}

%end

%hook AWELivePostWorkLiveCardLayoutDataLayer

- (CGFloat)normalHeight {
    CGFloat original = %orig;
    if ([DYYYFullscreenCoordinator isImDetailView:self]) return original;
    return [DYYYFullscreenCoordinator fullCellHeightForNative:original];
}
- (CGFloat)originalTableViewHeight {
    CGFloat original = %orig;
    if ([DYYYFullscreenCoordinator isImDetailView:self]) return original;
    return [DYYYFullscreenCoordinator fullCellHeightForNative:original];
}
- (void)setOriginalTableViewHeight:(CGFloat)height {
    %orig([DYYYFullscreenCoordinator isImDetailView:self] ? height : [DYYYFullscreenCoordinator fullCellHeightForNative:height]);
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

// ===== 聊天系视频页：内容层撑满（补上从未被撑过的那一层）=====
// 背景：抖音把 cell 内容区按"表高 − 底栏(83)"算成 843，而 cell 本身是 926。
//       同一 cell 内两种高度基准并存，造成
//         ① 视频只占上面 843，底部空 83（不全屏化）
//         ② 进度条手势按 926 换算、松手按 843 布局（拖动中跳起后弹回）
// 修复：只把这一层撑到父视图高度，使 cell / 内容区 / 播放器 / 互动层同高。
//       输入栏（83pt）位置不变，继续浮在视频上方。
// 作用域：全屏开启 + 聊天系视频页（群聊 / 朋友聊天），其余页面完全不动。
%hook AWEAwemeDetailCellViewController

- (void)viewDidLayoutSubviews {
    %orig;

    if (!DYYYGetBool(@"DYYYEnableFullScreen") || !NSThread.isMainThread) return;
    if (![DYYYFullscreenCoordinator isImDetailController:self]) return;

    UIView *contentView = self.view;
    UIView *parent = contentView.superview;
    if (!parent) return;
    // 父视图可能还没拿到最终高度（布局早期），留待下一次布局再处理。
    CGFloat target = CGRectGetHeight(parent.bounds);
    if (!isfinite(target) || target <= 1.0) return;
    if (fabs(CGRectGetHeight(contentView.frame) - target) <= 0.5) return;
    // 只在"被底栏压缩"这一种形态上接管：差值落在 (1, 底栏上限] 区间，
    // 半屏 / 小窗 / 异常尺寸一律放行原生。
    CGFloat diff = target - CGRectGetHeight(contentView.frame);
    if (diff <= 0.5 || diff > 160.0) return;

    CGFloat oldHeight = CGRectGetHeight(contentView.frame);
    CGRect frame = contentView.frame;
    frame.size.height = target;
    contentView.frame = frame;

    if (DYYYGetBool(@"DYYYDiagEntryEnabled")) {
        NSLog(@"[DYYY][cellcontent] 撑满 %.1f → %.1f (parent=%@)",
              oldHeight, target, NSStringFromClass([parent class]));
    }
}

%end
