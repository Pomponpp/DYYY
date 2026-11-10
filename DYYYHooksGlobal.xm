//
//  DYYYHooksGlobal.xm
//  从 DYYY.xm 拆出：Global 域 5 个 hook 块。
//
//  这些块原本不依赖 DYYY.xm 的块外 static 状态，因此可以独立成文件。
//  搬出时按原顺序整块复制，内容未改。
//

#import "DYYYShared.h"
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

%hook YYLabel

- (void)setBackgroundColor:(UIColor *)color {
    %orig([DYYYCommentBlurCoordinator backgroundColorForTextView:self proposed:color]);
}
- (void)setOpaque:(BOOL)opaque {
    %orig([DYYYCommentBlurCoordinator opaqueForTextView:self proposed:opaque]);
}
- (void)didMoveToWindow {
    %orig;
    [DYYYCommentBlurCoordinator layoutTextView:self];
}

- (void)layoutSubviews {
    %orig;
    [DYYYCommentBlurCoordinator layoutTextView:self];
}

// 1. Hook 富文本赋值方法 (核心)
- (void)setAttributedText:(NSAttributedString *)attributedText {
    if (!DYYYGetBool(@"DYYYCommentExactTime") || !attributedText || attributedText.length == 0) {
        %orig(attributedText);
        return;
    }

    NSString *plainText = [attributedText string];

    // 40.9 优化：正则 static 化 + 首字符快速排除（原每次赋值现场编译正则）。
    unichar firstChar = [plainText characterAtIndex:0];
    if (firstChar < '0' || firstChar > '9') {
        %orig(attributedText);
        return;
    }

    static NSRegularExpression *s_attrTimestampRegex = nil;
    static dispatch_once_t attrRegexOnce;
    dispatch_once(&attrRegexOnce, ^{
      s_attrTimestampRegex = [NSRegularExpression regularExpressionWithPattern:@"^(\\d{10,13})" options:0 error:nil];
    });
    NSTextCheckingResult *match = [s_attrTimestampRegex firstMatchInString:plainText options:0 range:NSMakeRange(0, plainText.length)];

    if (match) {
        NSString *rawTs = [plainText substringWithRange:[match rangeAtIndex:1]];
        long long ts = [rawTs longLongValue];
        
        if (ts > 100000000000) {
            ts = ts / 1000;
        }
        
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:ts];
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
        NSString *formattedDate = [formatter stringFromDate:date];
        
        NSMutableAttributedString *newAttrStr = [attributedText mutableCopy];
        [newAttrStr replaceCharactersInRange:[match rangeAtIndex:1] withString:formattedDate];
        
        %orig(newAttrStr);
    } else {
        %orig(attributedText);
    }
}

%end

%hook AWEBaseListViewController
- (void)viewDidLayoutSubviews {
    // 对齐已验证实现：布局前后各同步一次表高（不碰 inset、不做 beginUpdates）
    if (DYYYGetBool(@"DYYYEnableFullScreen")) {
        [DYYYFullscreenCoordinator prepareDetailTableNew:self];
    }
    %orig;
    if (DYYYGetBool(@"DYYYEnableFullScreen")) {
        [DYYYFullscreenCoordinator prepareDetailTableNew:self];
    }
}

%new
- (void)applyBlurEffectIfNeeded {
    [DYYYCommentBlurCoordinator layoutController:self];
}
%end

%hook UIButton

- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYEnableCommentBlur") && (self.currentTitle.length > 0 || self.currentAttributedTitle.length > 0)) {
        [DYYYCommentBlurCoordinator layoutTextView:self.titleLabel];
    }

    NSString *accessibilityLabel = self.accessibilityLabel;

    if ([accessibilityLabel isEqualToString:@"拍照搜同款"] || [accessibilityLabel isEqualToString:@"扫一扫"]) {
        if (DYYYGetBool(@"DYYYHideScancode")) {
            [self removeFromSuperview];
        }
    }

    if ([accessibilityLabel isEqualToString:@"返回"]) {
        if (DYYYGetBool(@"DYYYHideBack")) {
            UIView *parent = self.superview;
            // 父视图是AWEBaseElementView(排除用户主页返回按钮) 按钮类不是AWENoxusHighlightButton(排除横屏返回按钮)
            if ([parent isKindOfClass:%c(AWEBaseElementView)] && ![self isKindOfClass:%c(AWENoxusHighlightButton)]) {
                [self removeFromSuperview];
            }
            return;
        }
    }
}

%end

%hook AWEBaseListSectionBackgroundView

- (void)setBackgroundColor:(UIColor *)color {
    %orig([DYYYCommentBlurCoordinator backgroundColorForTextView:self proposed:color]);
}

- (void)setOpaque:(BOOL)opaque {
    %orig([DYYYCommentBlurCoordinator opaqueForTextView:self proposed:opaque]);
}

- (void)layoutSubviews {
    %orig;
    [DYYYCommentBlurCoordinator layoutTextView:self];
}

%end

%hook UIViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig;
    if (hideButton.isElementsHidden) [hideButton hideUIElements];
    [DYYYFloatingButtonCoordinator setNeedsRefresh];
}

- (void)viewWillDisappear:(BOOL)animated {
    %orig;
    [DYYYFloatingButtonCoordinator setNeedsRefresh];
}

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    [DYYYFloatingButtonCoordinator refresh];
}

- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    [DYYYFloatingButtonCoordinator refresh];
}
%end
