//
//  DYYYHooksComment.xm
//  从 DYYY.xm 拆出：Comment 域 4 个 hook 块。
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

%hook AWECommentMediaDownloadConfigLivePhoto

BOOL commentLivePhotoNotWaterMark = DYYYGetBool(@"DYYYCommentLivePhotoNotWaterMark");

- (BOOL)needClientWaterMark {
    return commentLivePhotoNotWaterMark ? 0 : %orig;
}

- (BOOL)needClientEndWaterMark {
    return commentLivePhotoNotWaterMark ? 0 : %orig;
}

- (id)watermarkConfig {
    return commentLivePhotoNotWaterMark ? nil : %orig;
}

%end

%hook AWECommentImageModel
- (id)downloadUrl {
    if (DYYYGetBool(@"DYYYCommentNotWaterMark")) {
        return self.originUrl;
    }
    return %orig;
}
%end

%hook AWECommentGuideLunaAnchorView
- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHideCommentViews")) {
        [self setHidden:YES];
    }

    if (DYYYGetBool(@"DYYYMusicCopyText")) {
        UILabel *label = nil;
        if ([self respondsToSelector:@selector(preTitleLabel)]) {
            label = [self valueForKey:@"preTitleLabel"];
        }
        if (label && [label isKindOfClass:[UILabel class]]) {
            label.text = @"";
        }
    }
}

- (void)p_didClickSong {
    if (DYYYGetBool(@"DYYYMusicCopyText")) {
        // 通过 KVC 拿到内部的 songButton
        UIButton *btn = nil;
        if ([self respondsToSelector:@selector(songButton)]) {
            btn = (UIButton *)[self valueForKey:@"songButton"];
        }

        // 获取歌曲名并复制到剪贴板
        if (btn && [btn isKindOfClass:[UIButton class]]) {
            NSString *song = btn.currentTitle;
            if (song.length) {
                [UIPasteboard generalPasteboard].string = song;
                [DYYYToast showSuccessToastWithMessage:@"歌曲名已复制"];
            }
        }
    } else {
        %orig;
    }
}

%end

%hook AWECommentContainerViewController

- (void)viewWillAppear:(BOOL)animated {
    %orig(animated);
    [DYYYCommentPlaybackCoordinator commentController:self visible:YES];
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [DYYYFloatingButtonCoordinator commentController:self visible:YES];
    [DYYYCommentPlaybackCoordinator commentController:self visible:YES];
    NSString *transparentValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYTopBarTransparent"];
    if (transparentValue && transparentValue.length > 0) {
        CGFloat alphaValue = [transparentValue floatValue];
        if (alphaValue >= 0.0 && alphaValue <= 1.0) {

            UIView *parentView = self.view.superview;
            if (parentView) {
                for (UIView *subview in parentView.subviews) {
                    if ([subview.accessibilityLabel isEqualToString:@"搜索"]) {
                        CGFloat finalAlpha = (alphaValue < 0.011) ? 0.011 : alphaValue;
                        subview.alpha = finalAlpha;
                    }
                }
            }
        }
    }
}

- (void)viewDidDisappear:(BOOL)animated {
    BOOL skipsLifecycle = [DYYYCommentPlaybackCoordinator shouldSkipLifecycle:self];
    %orig;
    if (skipsLifecycle) return;
    [DYYYCommentPlaybackCoordinator commentController:self visible:NO];
    [DYYYFullscreenCoordinator commentController:self visible:NO];
    [DYYYFloatingButtonCoordinator commentController:self visible:NO];
}

- (void)viewDidLayoutSubviews {
    %orig;
    [DYYYCommentBlurCoordinator layoutController:self];
    [DYYYFullscreenCoordinator commentController:self visible:YES];
    [DYYYFloatingButtonCoordinator commentController:self visible:YES];

    if (!DYYYGetBool(@"DYYYEnableCommentBlur"))
        return;

    // 41.1 优化：全树遍历结果按控制器缓存，仅在缓存视图脱离视图树时重扫；
    // 面板打开后结构稳定，逐帧全树 BFS 是主要浪费。
    static char kDYYYCommentBlurScanKey;
    NSDictionary *scanCache = objc_getAssociatedObject(self, &kDYYYCommentBlurScanKey);
    NSArray<UIView *> *containerViews = nil;
    NSArray<UIView *> *middleContainers = nil;
    BOOL cacheValid = NO;
    if (scanCache) {
        containerViews = scanCache[@"containers"];
        middleContainers = scanCache[@"middle"];
        cacheValid = YES;
        for (UIView *view in containerViews) {
            if (!view.superview) { cacheValid = NO; break; }
        }
        if (cacheValid) {
            for (UIView *view in middleContainers) {
                if (!view.superview) { cacheValid = NO; break; }
            }
        }
    }

    if (!cacheValid) {
        Class containerViewClass = NSClassFromString(@"AWECommentInputViewSwiftImpl.CommentInputContainerView");
        containerViews = [DYYYUtils findAllSubviewsOfClass:containerViewClass inContainer:self.view];
        Class middleContainerClass = NSClassFromString(@"AWECommentInputViewSwiftImpl.CommentInputViewMiddleContainer");
        middleContainers = [DYYYUtils findAllSubviewsOfClass:middleContainerClass inContainer:self.view];
        objc_setAssociatedObject(self, &kDYYYCommentBlurScanKey,
                                 @{ @"containers": containerViews ?: @[], @"middle": middleContainers ?: @[] },
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    for (UIView *containerView in containerViews) {
        for (UIView *subview in containerView.subviews) {
            if (subview.hidden == NO && subview.backgroundColor && CGColorGetAlpha(subview.backgroundColor.CGColor) == 1) {
                float userTransparency = [[[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYCommentBlurTransparent"] floatValue];
                if (userTransparency <= 0 || userTransparency > 1) {
                    userTransparency = 0.8;
                }
                [DYYYUtils applyBlurEffectToView:subview transparency:userTransparency blurViewTag:999];
            }
        }
    }

    for (UIView *middleContainer in middleContainers) {
        BOOL containsDanmu = NO;
        for (UIView *innerSubviewCheck in middleContainer.subviews) {
            if ([innerSubviewCheck isKindOfClass:[UILabel class]] && [((UILabel *)innerSubviewCheck).text containsString:@"弹幕"]) {
                containsDanmu = YES;
                break;
            }
        }

        [DYYYCommentBlurCoordinator layoutDanmuBackground:middleContainer controller:self enabled:containsDanmu];
        if (!containsDanmu) {
            for (UIView *subview in middleContainer.subviews) {
                if (subview.hidden == NO && subview.backgroundColor && CGColorGetAlpha(subview.backgroundColor.CGColor) == 1) {
                    [DYYYUtils applyBlurEffectToView:subview transparency:0.2f blurViewTag:999];
                }
            }
        }
    }
}

%end
