//
//  DYYYHooksProfile.xm
//  从 DYYY.xm 拆出：Profile 域 7 个 hook 块。
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

%hook DYYY_T_AWEPROFILE_MENTION_LABEL

- (void)layoutSubviews {
    %orig;

    if (!DYYYGetBool(@"DYYYBioCopyText")) {
        return;
    }

    BOOL hasLongPressGesture = NO;
    for (UIGestureRecognizer *gesture in self.gestureRecognizers) {
        if ([gesture isKindOfClass:[UILongPressGestureRecognizer class]]) {
            hasLongPressGesture = YES;
            break;
        }
    }

    if (!hasLongPressGesture) {
        UILongPressGestureRecognizer *longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
        longPressGesture.minimumPressDuration = 0.5;
        [self addGestureRecognizer:longPressGesture];
        self.userInteractionEnabled = YES;
    }
}

%new
- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        NSString *bioText = self.text;
        if (bioText && bioText.length > 0) {
            [[UIPasteboard generalPasteboard] setString:bioText];
            [DYYYToast showSuccessToastWithMessage:@"个人简介已复制"];
        }
    }
}

%end

%hook DYYY_T_AWEPROFILE_AVATAR_FUNCTION_MANAGER
- (BOOL)shouldShowSaveAvatarItem {
    BOOL shouldEnable = DYYYGetBool(@"DYYYEnableSaveAvatar");
    if (shouldEnable) {
        return YES;
    }
    return %orig;
}

// 40.9：仅放行菜单项不够，下载本身还被 allowsAvatarDownload 拦截（表现为菜单可见但点了没反应）。
- (BOOL)allowsAvatarDownload {
    if (DYYYGetBool(@"DYYYEnableSaveAvatar")) {
        return YES;
    }
    return %orig;
}

// 40.9：主页大头像预览页的下载按钮由 allowsRoleHeadDownload 控制，
// 该属性位于预览数据模型上，故在管理器一侧一并放行。
- (BOOL)allowsRoleHeadDownload {
    if (DYYYGetBool(@"DYYYEnableSaveAvatar")) {
        return YES;
    }
    return %orig;
}

- (BOOL)currentAllowsRoleHeadDownload {
    if (DYYYGetBool(@"DYYYEnableSaveAvatar")) {
        return YES;
    }
    return %orig;
}

// 40.9 实测（探针日志）：头像预览页功能项显示由该方法控制，
// AWEProfileAvatarFunctionModel title=保存头像 对应 type == 1。
- (BOOL)p_shouldShowFunctionWithType:(long long)type {
    if (type == 1 && DYYYGetBool(@"DYYYEnableSaveAvatar")) {
        return YES;
    }
    return %orig;
}
%end

%hook DYYY_T_AWEPROFILE_NAVIGATION_BUTTON
- (void)setupUI {

    if (DYYYGetBool(@"DYYYHideButton")) {
        return;
    }
    %orig;
}
%end

%hook DYYY_T_AWEPROFILE_MIX_ITEM_COLLECTION_VIEW_CELL
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHidePostView")) {
        if ([self.accessibilityLabel isEqualToString:@"私密作品"]) {
            self.hidden = YES;
            return;
        }
    }
}
%end

%hook DYYY_T_AWEPROFILE_TASK_CARD_STYLE_LIST_ITEM_CELL
- (BOOL)shouldShowPublishGuide {
    if (DYYYGetBool(@"DYYYHidePostView")) {
        return NO;
    }
    return %orig;
}
%end

%hook DYYY_T_AWEPROFILE_PUBLISH_GUIDE_COLLECTION_VIEW_CELL
- (void)didMoveToSuperview {
    %orig;
    if (DYYYGetBool(@"DYYYHidePostView")) {
        if ([self superview]) {
            [self setHidden:YES];
        }
    }
}
%end

%hook DYYY_T_AWEPROFILE_RICH_EMPTY_VIEW

- (void)setTitle:(id)title {
    if (DYYYGetBool(@"DYYYHidePostView")) {
        return;
    }
    %orig(title);
}

- (void)setDetail:(id)detail {
    if (DYYYGetBool(@"DYYYHidePostView")) {
        return;
    }
    %orig(detail);
}
%end
