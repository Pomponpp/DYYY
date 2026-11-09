//
//  DYYYHooksOther.xm
//  从 DYYY.xm 拆出：Other 域 101 个 hook 块。
//
//  这些块原本不依赖 DYYY.xm 的块外 static 状态，因此可以独立成文件。
//  搬出时按原顺序整块复制，内容未改。
//

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

%hook AWEDateTimeFormatter

+ (id)formattedDateForTimestamp:(double)timestamp {
    if (!DYYYGetBool(@"DYYYCommentExactTime")) return %orig(timestamp);
    return [NSString stringWithFormat:@"%.0f ", timestamp];
}

%end

%hook AWERLVirtualLabel

- (void)setText:(NSString *)text {
    if (!DYYYGetBool(@"DYYYCommentExactTime") || !text || text.length == 0) {
        %orig(text);
        return;
    }

    if ([text isEqualToString:@"回复"]) {
        %orig(@"");
        return;
    }

    // 40.9 优化：正则 static 化（原实现每次 setText 现场编译），首字符非数字快速排除。
    unichar first = [text characterAtIndex:0];
    if (first < '0' || first > '9') {
        %orig(text);
        return;
    }

    static NSRegularExpression *s_timestampRegex = nil;
    static dispatch_once_t regexOnce;
    dispatch_once(&regexOnce, ^{
      s_timestampRegex = [NSRegularExpression regularExpressionWithPattern:@"^(\\d{10,13})([\\s\\S]*)" options:0 error:nil];
    });

    NSTextCheckingResult *match = [s_timestampRegex firstMatchInString:text options:0 range:NSMakeRange(0, text.length)];

    if (match) {
        NSString *rawTs = [text substringWithRange:[match rangeAtIndex:1]];
        NSString *suffix = [text substringWithRange:[match rangeAtIndex:2]];
        
        long long ts = [rawTs longLongValue];
        
        if (ts > 100000000000) {
            ts = ts / 1000;
        }
        
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:ts];
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss"];
        NSString *formattedDate = [formatter stringFromDate:date];
        
        NSString *newText = [NSString stringWithFormat:@"%@%@", formattedDate, suffix];
        %orig(newText);
    } else {
        %orig(text);
    }
}

%end

%group DYYYCommentExactTimeGroup
%hook AWECommentSwiftBizUI_CommentInteractionBaseLabel

- (void)setText:(NSString *)text {
    %orig(text); // 先让系统把文本赋上去
    
    if (!DYYYGetBool(@"DYYYCommentExactTime")) {
        return;
    }

    UILabel *label = (UILabel *)self;
    if (!text || text.length == 0) return;

    // --- 1. 拦截翻译文本，将其绝对定位在屏幕右侧 100 像素 ---
    if ([text isEqualToString:@"翻译"] || [text isEqualToString:@"隐藏翻译"]) {
        CGRect currentFrame = label.frame;
        CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
        // 重新计算 X 坐标：屏幕宽度 - 100 - 标签自身宽度
        currentFrame.origin.x = screenWidth - 100.0 - currentFrame.size.width;
        label.frame = currentFrame;
        return;
    }

    // --- 2. 拦截时间文本，如果不够宽则扩充宽度 ---
    UIFont *font = label.font;
    if (font) {
        CGFloat expectedWidth = ceilf([text sizeWithAttributes:@{NSFontAttributeName: font}].width);
        CGRect currentFrame = label.frame;
        
        // 如果当前宽度不够，并且不是尚未初始化的状态（>0），则强行修改并重新赋值
        if (currentFrame.size.width < expectedWidth && currentFrame.size.width > 0) {
            currentFrame.size.width = expectedWidth;
            label.frame = currentFrame; 
            label.clipsToBounds = NO;
        }
    }
}

- (void)setFrame:(CGRect)frame {
    if (!DYYYGetBool(@"DYYYCommentExactTime") || ![self respondsToSelector:@selector(text)]) {
        %orig(frame);
        return;
    }

    UILabel *label = (UILabel *)self;
    NSString *text = label.text;

    if (text && text.length > 0) {
        // --- 1. 拦截翻译文本，将其绝对定位在屏幕右侧 100 像素 ---
        if ([text isEqualToString:@"翻译"] || [text isEqualToString:@"隐藏翻译"]) {
            CGFloat screenWidth = [UIScreen mainScreen].bounds.size.width;
            frame.origin.x = screenWidth - 100.0 - frame.size.width;
        } 
        // --- 2. 拦截时间文本，如果不够宽则扩充宽度 ---
        else if ([self respondsToSelector:@selector(font)]) {
            UIFont *font = label.font;
            if (font) {
                CGFloat expectedWidth = ceilf([text sizeWithAttributes:@{NSFontAttributeName: font}].width);
                if (frame.size.width < expectedWidth && frame.size.width > 0) {
                    frame.size.width = expectedWidth;
                    label.clipsToBounds = NO;
                }
            }
        }
    }

    %orig(frame);
}

%end
%end

%hook AWEHPTopTabItemTextContentView

- (void)layoutSubviews {
    %orig;
    NSDictionary<NSString *, NSString *> *titleMapping = DYYYTopTabTitleMapping();
    if (titleMapping.count == 0) {
        return;
    }

    NSString *accessibilityLabel = nil;
    if ([self.superview respondsToSelector:@selector(accessibilityLabel)]) {
        accessibilityLabel = self.superview.accessibilityLabel;
    }
    if (accessibilityLabel.length == 0) {
        return;
    }

    NSString *newTitle = titleMapping[accessibilityLabel];
    if (newTitle.length == 0) {
        return;
    }

    if ([self respondsToSelector:@selector(setContentText:)]) {
        [self setContentText:newTitle];
    } else {
        [self setValue:newTitle forKey:@"contentText"];
    }
}

%end

%hook AWEDanmakuContentLabel
- (void)setTextColor:(UIColor *)textColor {
    if (DYYYGetBool(@"DYYYEnableDanmuColor")) {
        NSString *danmuColor = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYDanmuColor"];
        if (DYYYGetBool(@"DYYYDanmuRainbowRotating")) {
            danmuColor = @"rainbow_rotating";
        }
        [DYYYUtils applyColorSettingsToLabel:self colorHexString:danmuColor];
    } else {
        %orig(textColor);
    }
}

- (void)setStrokeWidth:(double)strokeWidth {
    if (DYYYGetBool(@"DYYYEnableDanmuColor")) {
        %orig(FLT_MIN);
    } else {
        %orig(strokeWidth);
    }
}

- (void)setStrokeColor:(UIColor *)strokeColor {
    if (DYYYGetBool(@"DYYYEnableDanmuColor")) {
        %orig(nil);
    } else {
        %orig(strokeColor);
    }
}

%end

%hook DDanmakuPlayerView

- (void)setAlpha:(CGFloat)alpha {
    if (DYYYGetBool(@"DYYYCommentShowDanmaku") && alpha == 0.0) {
        return;
    } else {
        %orig(alpha);
    }
}

%end

%hook AWEMarkView

- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHideLocation")) {
        self.hidden = YES;
        return;
    }
}

%end

%group DYYYSettingsGesture

%hook UIWindow
- (instancetype)initWithFrame:(CGRect)frame {
    UIWindow *window = %orig(frame);
    if (window) {
        UILongPressGestureRecognizer *doubleFingerLongPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleDoubleFingerLongPressGesture:)];
        doubleFingerLongPressGesture.numberOfTouchesRequired = 2;
        // 40.9：头像预览页等全屏覆盖层会自带手势识别器并吞掉触摸，
        // 这里不拦截其它手势，且允许同时识别，保证任意页面双指长按都能唤起设置。
        doubleFingerLongPressGesture.cancelsTouchesInView = NO;
        doubleFingerLongPressGesture.delaysTouchesEnded = NO;
        // 允许与页面内手势并发识别（iOS 7+ 的 UIGestureRecognizer 属性）
        if ([doubleFingerLongPressGesture respondsToSelector:@selector(setDelegate:)]) {
            doubleFingerLongPressGesture.delegate = (id<UIGestureRecognizerDelegate>)DYYYGesturePassthroughDelegate.shared;
        }
        [window addGestureRecognizer:doubleFingerLongPressGesture];
    }
    return window;
}

%new
- (void)handleDoubleFingerLongPressGesture:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        UIViewController *rootViewController = self.rootViewController;
        if (rootViewController) {
            UIViewController *settingVC = [[DYYYSettingViewController alloc] init];

            if (settingVC) {
                BOOL isIPad = UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad;
                if (@available(iOS 15.0, *)) {
                    if (!isIPad) {
                        settingVC.modalPresentationStyle = UIModalPresentationPageSheet;
                    } else {
                        settingVC.modalPresentationStyle = UIModalPresentationFullScreen;
                    }
                } else {
                    settingVC.modalPresentationStyle = UIModalPresentationFullScreen;
                }

                if (settingVC.modalPresentationStyle == UIModalPresentationFullScreen) {
                    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
                    [closeButton setTitle:@"关闭" forState:UIControlStateNormal];
                    closeButton.translatesAutoresizingMaskIntoConstraints = NO;

                    [settingVC.view addSubview:closeButton];

                    [NSLayoutConstraint activateConstraints:@[
                        [closeButton.trailingAnchor constraintEqualToAnchor:settingVC.view.trailingAnchor constant:-10],
                        [closeButton.topAnchor constraintEqualToAnchor:settingVC.view.topAnchor constant:40], [closeButton.widthAnchor constraintEqualToConstant:80],
                        [closeButton.heightAnchor constraintEqualToConstant:40]
                    ]];

                    [closeButton addTarget:self action:@selector(closeSettings:) forControlEvents:UIControlEventTouchUpInside];
                }

                UIView *handleBar = [[UIView alloc] init];
                handleBar.backgroundColor = [UIColor whiteColor];
                handleBar.layer.cornerRadius = 2.5;
                handleBar.translatesAutoresizingMaskIntoConstraints = NO;
                [settingVC.view addSubview:handleBar];

                [NSLayoutConstraint activateConstraints:@[
                    [handleBar.centerXAnchor constraintEqualToAnchor:settingVC.view.centerXAnchor], [handleBar.topAnchor constraintEqualToAnchor:settingVC.view.topAnchor constant:8],
                    [handleBar.widthAnchor constraintEqualToConstant:40], [handleBar.heightAnchor constraintEqualToConstant:5]
                ]];

                [rootViewController presentViewController:settingVC animated:YES completion:nil];
            }
        }
    }
}

%new
- (void)closeSettings:(UIButton *)button {
    [button.superview.window.rootViewController dismissViewControllerAnimated:YES completion:nil];
}

- (void)makeKeyAndVisible {
    %orig;

    if (!isFloatSpeedButtonEnabled)
        return;

    if (speedButton && ![speedButton isDescendantOfView:self]) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self addSubview:speedButton];
          [speedButton loadSavedPosition];
          [speedButton resetFadeTimer];
        });
    }
}
%end

%end

%hook AWEDProgressCoreContainer

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

    id model = nil;
    if ([self respondsToSelector:@selector(model)]) {
        model = [self valueForKey:@"model"];
    }

    if ([progressSlider isKindOfClass:[UIView class]]) {
        [(UIView *)progressSlider dyyy_updateScheduleLabelsLegacyWithCurrentTime:currentTime totalDuration:totalDuration model:model];
    }
}

- (void)updateProgressSliderWithTime:(CGFloat)arg1 totalDuration:(CGFloat)arg2 {
    %orig;
    [self dyyy_syncScheduleLabelsWithCurrentTime:arg1 totalDuration:arg2];
}

%end

%hook AWEUserNameLabel

- (void)layoutSubviews {
    %orig;

    self.transform = CGAffineTransformIdentity;

    // 添加垂直偏移支持
    NSString *verticalOffsetValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYNicknameVerticalOffset"];
    CGFloat verticalOffset = 0;
    if (verticalOffsetValue.length > 0) {
        verticalOffset = [verticalOffsetValue floatValue];
    }

    UIView *parentView = self.superview;
    UIView *grandParentView = nil;

    if (parentView) {
        grandParentView = parentView.superview;
    }

    // 检查祖父视图是否为 AWEBaseElementView 类型
    if (grandParentView && [grandParentView.superview isKindOfClass:%c(AWEBaseElementView)]) {
        CGRect scaledFrame = grandParentView.frame;
        CGFloat translationX = -scaledFrame.origin.x;

        CGAffineTransform translationTransform = CGAffineTransformMakeTranslation(translationX, verticalOffset);
        grandParentView.transform = translationTransform;
    }
    [DYYYFullscreenCoordinator layoutInformationLabel:self];
}

%end

%hook AWEURLModel
%new - (NSURL *)getDYYYSrcURLDownload {
    NSURL *bestURL;
    for (NSString *url in self.originURLList) {
        if ([url containsString:@"video_mp4"] || [url containsString:@".jpeg"] || [url containsString:@".mp3"]) {
            bestURL = [NSURL URLWithString:url];
        }
    }

    if (bestURL == nil) {
        bestURL = [NSURL URLWithString:[self.originURLList firstObject]];
    }

    return bestURL;
}
%end

%hook AWEUserActionSheetView

- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYEnableSheetBlur")) {
        [self applyBlurEffectAndWhiteText];
    }
}

%new
- (void)applyBlurEffectAndWhiteText {
    // 应用毛玻璃效果到容器视图
    if (self.containerView) {
        self.containerView.backgroundColor = [UIColor clearColor];

        // 动态获取用户设置的透明度
        float userTransparency = [[[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYSheetBlurTransparent"] floatValue];
        if (userTransparency <= 0 || userTransparency > 1) {
            userTransparency = 0.9; // 默认值0.9
        }

        [DYYYUtils applyBlurEffectToView:self.containerView transparency:userTransparency blurViewTag:9999];
        [DYYYUtils clearBackgroundRecursivelyInView:self.containerView];
        // 调用新的通用方法设置文本颜色，这里没有排除需求，所以传入 nil Block
        [DYYYUtils applyTextColorRecursively:[UIColor whiteColor] inView:self.containerView shouldExcludeViewBlock:nil];
    }
}

%end

%hook _TtC33AWECommentLongPressPanelSwiftImpl32CommentLongPressPanelCopyElement

- (void)elementTapped {
    if (!DYYYGetBool(@"DYYYCommentCopyText")) {
        %orig;
        return;
    }

    AWECommentLongPressPanelContext *commentPageContext = [self commentPageContext];
    AWECommentModel *selectdComment = [commentPageContext selectdComment];
    if (!selectdComment) {
        AWECommentLongPressPanelParam *params = [commentPageContext params];
        selectdComment = [params selectdComment];
    }
    NSString *descText = [selectdComment content];
    if (descText.length == 0) {
        %orig;
        return;
    }

    [[UIPasteboard generalPasteboard] setString:descText];
    [DYYYToast showSuccessToastWithMessage:@"评论已复制"];
}
%end

%hook BDByteCastUtils

+ (BOOL)netVPNStatus {
    if (DYYYGetBool(@"DYYYDisableCastVPNCheck")) {
        return NO;
    }
    return %orig;
}

%end

%hook BDByteCastNetUtilities

- (BOOL)getVPNStatus {
    if (DYYYGetBool(@"DYYYDisableCastVPNCheck")) {
        return NO;
    }
    return %orig;
}

%end

%hook BDByteCastMonitorManager

- (BOOL)netVPNStatus {
    if (DYYYGetBool(@"DYYYDisableCastVPNCheck")) {
        return NO;
    }
    return %orig;
}

- (void)setNetVPNStatus:(BOOL)netVPNStatus {
    if (DYYYGetBool(@"DYYYDisableCastVPNCheck")) {
        %orig(NO);
        return;
    }
    %orig(netVPNStatus);
}

%end

%hook BDByteCastEnvInfo

- (BOOL)isVPNActive {
    if (DYYYGetBool(@"DYYYDisableCastVPNCheck")) {
        return NO;
    }
    return %orig;
}

- (void)setIsVPNActive:(BOOL)isVPNActive {
    if (DYYYGetBool(@"DYYYDisableCastVPNCheck")) {
        %orig(NO);
        return;
    }
    %orig(isVPNActive);
}

%end

%hook BDByteScreenCastContext

- (BOOL)isVPNActive {
    if (DYYYGetBool(@"DYYYDisableCastVPNCheck")) {
        return NO;
    }
    return %orig;
}

- (void)setIsVPNActive:(BOOL)isVPNActive {
    if (DYYYGetBool(@"DYYYDisableCastVPNCheck")) {
        %orig(NO);
        return;
    }
    %orig(isVPNActive);
}

%end

%hook AWELongPressPanelDataManager
+ (BOOL)enableModernLongPressPanelConfigWithSceneIdentifier:(id)arg1 {
    return DYYYGetBool(@"DYYYEnableModernPanel");
}
%end

%hook AWELongPressPanelABSettings
+ (NSUInteger)modernLongPressPanelStyleMode {
    if (!DYYYGetBool(@"DYYYEnableModernPanel")) {
        return %orig;
    }

    BOOL forceBlur = DYYYGetBool(@"DYYYLongPressPanelBlur");
    BOOL forceDark = DYYYGetBool(@"DYYYLongPressPanelDark");

    if (forceBlur && forceDark) {
        return 1;
    } else if (!forceBlur && !forceDark) {
        BOOL isDarkMode = [DYYYUtils isDarkMode];
        return isDarkMode ? 1 : 2;
    }
}
%end

%hook AWEModernLongPressPanelUIConfig
+ (NSUInteger)modernLongPressPanelStyleMode {
    if (!DYYYGetBool(@"DYYYEnableModernPanel")) {
        return %orig;
    }

    BOOL forceBlur = DYYYGetBool(@"DYYYLongPressPanelBlur");
    BOOL forceDark = DYYYGetBool(@"DYYYLongPressPanelDark");

    if (forceBlur && forceDark) {
        return 1;
    } else if (!forceBlur && !forceDark) {
        BOOL isDarkMode = [DYYYUtils isDarkMode];
        return isDarkMode ? 1 : 2;
    }
}
%end

%hook AWEUserTabListModel

- (NSInteger)profileLandingTab {
    if (DYYYGetBool(@"DYYYDefaultEnterWorks")) {
        return 0;
    } else {
        return %orig;
    }
}

%end

%group AutoPlay

%hook AWEAwemeDetailTableViewController

- (BOOL)hasIphoneAutoPlaySwitch {
    return YES;
}

%end

%hook AWEAwemeDetailContainerPlayControlConfig

- (BOOL)enableUserProfilePostAutoPlay {
    return YES;
}

%end

%hook AWEFeedIPhoneAutoPlayManager

- (BOOL)isAutoPlayOpen {
    return YES;
}

%end

%hook AWEFeedModuleService

- (BOOL)getFeedIphoneAutoPlayState {
    return YES;
}
%end

%hook AWEFeedIPhoneAutoPlayManager

- (BOOL)getFeedIphoneAutoPlayState {
    BOOL r = %orig;
    return YES;
}
%end

%end

%group DYYYIMMenuLegacyGroup
%hook AWEIMCustomMenuComponent
- (void)msg_showMenuForBubbleFrameInScreen:(CGRect)bubbleFrame tapLocationInScreen:(CGPoint)tapLocation menuItemList:(NSArray *)menuItems moreEmoticon:(BOOL)moreEmoticon onCell:(id)cell extra:(id)extra {
    NSArray *updatedMenuItems = DYYYIMMenuItemsByAddingDownloadAction(menuItems, cell);
    %orig(bubbleFrame, tapLocation, updatedMenuItems, moreEmoticon, cell, extra);
}
%end
%end

%group DYYYIMMenuTapLocationGroup
%hook AWEIMCustomMenuComponent
- (void)msg_showMenuForBubbleFrameInScreen:(CGRect)bubbleFrame tapLocationInScreen:(CGPoint)tapLocation menuItemList:(NSArray *)menuItems menuPanelOptions:(unsigned long long)menuPanelOptions moreEmoticon:(BOOL)moreEmoticon onCell:(id)cell extra:(id)extra {
    NSArray *updatedMenuItems = DYYYIMMenuItemsByAddingDownloadAction(menuItems, cell);
    %orig(bubbleFrame, tapLocation, updatedMenuItems, menuPanelOptions, moreEmoticon, cell, extra);
}
%end
%end

%group DYYYIMMenuHighLowGroup
%hook AWEIMCustomMenuComponent
- (void)msg_showMenuForBubbleFrameInScreen:(CGRect)bubbleFrame highLocationInScreen:(CGPoint)highLocation lowLocationInScreen:(CGPoint)lowLocation tryHighLocationFirst:(BOOL)tryHighLocationFirst menuItemList:(NSArray *)menuItems menuPanelOptions:(unsigned long long)menuPanelOptions onCell:(id)cell extra:(id)extra {
    NSArray *updatedMenuItems = DYYYIMMenuItemsByAddingDownloadAction(menuItems, cell);
    %orig(bubbleFrame, highLocation, lowLocation, tryHighLocationFirst, updatedMenuItems, menuPanelOptions, cell, extra);
}
%end
%end

%hook AWEAdAvatarView
- (void)layoutSubviews {
    %orig;

    // 检查是否需要隐藏头像
    if (DYYYGetBool(@"DYYYHideAvatarButton")) {
        self.hidden = YES;
        return;
    }

    // 应用透明度设置
    NSString *transparencyValue = [[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYAvatarViewTransparency"];
    if (transparencyValue && transparencyValue.length > 0) {
        CGFloat alphaValue = [transparencyValue floatValue];
        if (alphaValue >= 0.0 && alphaValue <= 1.0) {
            self.alpha = alphaValue;
        }
    }
}
%end

%hook AWENearbySkyLightCapsuleView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideNearbyCapsuleView")) {
        [self removeFromSuperview];
        return;
    }
    %orig;
}
%end

%hook AFDCancelMuteAwemeView
- (void)layoutSubviews {
    %orig;

    UIView *superview = self.superview;

    if ([superview isKindOfClass:NSClassFromString(@"AWEBaseElementView")]) {
        if (DYYYGetBool(@"DYYYHideCancelMute")) {
            self.hidden = YES;
            return;
        }
    }
}
%end

%hook AWEPlayDanmakuInputContainView

- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHideDanmuButton")) {
        self.hidden = YES;
        return;
    }
}

%end

%hook AWEShowPlayletCommentHeaderView
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideCommentViews")) {
        self.hidden = YES;
        return;
    }
}

%end

%hook AWEPOIEntryAnchorView

- (void)p_addViews {
    if (DYYYGetBool(@"DYYYHideCommentViews")) {
        return;
    }
    %orig;
}

%end

%group CommentHeaderGeneralGroup
%hook AWECommentPanelHeaderSwiftImpl_CommentHeaderGeneralView
- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHideCommentViews")) {
        [self setHidden:YES];
    }
}
%end
%end

%group CommentHeaderGoodsGroup
%hook AWECommentPanelHeaderSwiftImpl_CommentHeaderGoodsView
- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHideCommentViews")) {
        [self setHidden:YES];
    }
}
%end
%end

%group CommentHeaderTemplateGroup
%hook AWECommentPanelHeaderSwiftImpl_CommentHeaderTemplateAnchorView
- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHideCommentViews")) {
        [self setHidden:YES];
    }
}
%end
%end

%group CommentBottomTipsVCGroup
%hook AWECommentPanelListSwiftImpl_CommentBottomTipsContainerViewController
- (void)viewWillAppear:(BOOL)animated {
    %orig(animated);
    if (DYYYGetBool(@"DYYYHideCommentTips")) {
        ((UIViewController *)self).view.hidden = YES;
    }
}
%end
%end

%hook AWEDiscoverFeedEntranceView
- (id)init {
    if (DYYYGetBool(@"DYYYHideInteractionSearch")) {
        return nil;
    }
    return %orig;
}
%end

%hook AWETemplateTagsCommonView

- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHideTemplateTags")) {
        UIView *parentView = self.superview;
        if (parentView) {
            parentView.hidden = YES;
        } else {
            self.hidden = YES;
        }
    }
}

%end

%hook AWEFamiliarSkylightBubbleView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideAvatarBubble")) {
        [self removeFromSuperview];
    }
    %orig;
}
%end

%hook AWEFamiliarNavView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideFamiliar")) {
        self.hidden = YES;
    }
    %orig;
}
%end

%hook AWEHPSearchBubbleEntranceView
- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHideSearchBubble")) {
        [self removeFromSuperview];
        return;
    }
}

%end

%hook AWEGradientView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideGradient")) {
        UIView *parent = self.superview;
        if ([parent.accessibilityLabel isEqualToString:@"暂停，按钮"] || [parent.accessibilityLabel isEqualToString:@"播放，按钮"] || [parent.accessibilityLabel isEqualToString:@"“切换视角，按钮"] ||
            [parent isKindOfClass:%c(AWEStoryProgressContainerView)]) {
            self.hidden = YES;
        }
        return;
    }
    %orig;
}
%end

%hook AWELoadingAndVolumeView

- (void)layoutSubviews {
    %orig;
    self.hidden = YES;
    return;
}

%end

%hook AWEAwemeHotSpotTableViewController
- (BOOL)prefersStatusBarHidden {
    if (DYYYGetBool(@"DYYYHideStatusbar")) {
        return YES;
    }
    if (DYYYGetBool(@"DYYYHideStatusBarOnClear") && hideButton && hideButton.isElementsHidden) {
        return YES;
    }
    if (class_getInstanceMethod([self class], @selector(prefersStatusBarHidden)) !=
        class_getInstanceMethod([%c(AWEAwemeHotSpotTableViewController) class], @selector(prefersStatusBarHidden))) {
        return %orig;
    }
    return NO;
}
%end

%hook AWEFullPageFeedContainerViewController
- (BOOL)prefersStatusBarHidden {
    if (DYYYGetBool(@"DYYYHideStatusbar")) {
        return YES;
    }
    if (DYYYGetBool(@"DYYYHideStatusBarOnClear") && hideButton && hideButton.isElementsHidden) {
        return YES;
    }
    if (class_getInstanceMethod([self class], @selector(prefersStatusBarHidden)) !=
        class_getInstanceMethod([%c(AWEFullPageFeedContainerViewController) class], @selector(prefersStatusBarHidden))) {
        return %orig;
    }
    return NO;
}
%end

%hook AFDPureModePageListViewController
- (void)viewWillLayoutSubviews {
    // 先提供完整视口，再由原生更新 cell 尺寸、分页偏移和进度条。
    [DYYYFullscreenCoordinator layoutPlayerContainer:self];
    %orig;
}
%end

%hook AFDNewFastReplyView

- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHidePrivateMessages")) {
        UIView *parentView = self.superview;
        if (parentView) {
            parentView.hidden = YES;
        } else {
            self.hidden = YES;
        }
    }
}

%end

%hook _TtC18IESLiveRevenueImpl34IESLiveDynamicRankListEntranceView
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideLiveDetail")) {
        self.hidden = YES;
        return;
    }
}
%end

%hook AFDRecommendToFriendEntranceLabel
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideRecommendTips")) {
        if (self.accessibilityLabel) {
            [self removeFromSuperview];
        }
    }
}

%end

%hook AWENewLiveSkylightViewController

- (void)showSkylight:(BOOL)arg0 animated:(BOOL)arg1 actionMethod:(unsigned long long)arg2 {
    if (DYYYGetBool(@"DYYYHideLiveView")) {
        return;
    }
    %orig(arg0, arg1, arg2);
}

- (void)updateIsSkylightShowing:(BOOL)arg0 {
    if (DYYYGetBool(@"DYYYHideLiveView")) {
        %orig(NO);
    } else {
        %orig(arg0);
    }
}

%end

%hook AWENearbyFullScreenViewModel

- (void)setShowSkyLight:(id)arg1 {
    if (DYYYGetBool(@"DYYYHideMenuView")) {
        arg1 = nil;
    }
    %orig(arg1);
}

- (void)setHaveSkyLight:(id)arg1 {
    if (DYYYGetBool(@"DYYYHideMenuView")) {
        arg1 = nil;
    }
    %orig(arg1);
}

%end

%hook AWECorrelationItemTag

- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideItemTag")) {
        self.hidden = YES;
        return;
    }
}

%end

%hook AWEHPDiscoverFeedEntranceView

- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYHideDiscover")) {
        UIView *firstSubview = self.subviews.firstObject;
        if ([firstSubview isKindOfClass:[UIImageView class]]) {
            ((UIImageView *)firstSubview).image = nil;
        }
    }
}

%end

%hook AWEHPTopTabItemBadgeContentView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideConcernCapsuleView")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

%hook AWETemplateCommonView
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideCameraLocation")) {
        [self removeFromSuperview];
    }
}
%end

%hook AWEHPTopBarCTAItemView

- (void)showRedDot {
    if (![[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYHideSidebarDot"])
        %orig;
}

- (void)hideCountRedDot {
    if (![[NSUserDefaults standardUserDefaults] objectForKey:@"DYYYHideSidebarDot"])
        %orig;
}

- (void)layoutSubviews {
    %orig;

    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideSidebarDot"]) {
        return;
    }

    static char kDYSidebarBadgeCacheKey;
    NSArray *cachedBadges = objc_getAssociatedObject(self, &kDYSidebarBadgeCacheKey);
    if (!cachedBadges) {
        NSMutableArray *badges = [NSMutableArray array];
        for (UIView *subview in self.subviews) {
            if ([subview isKindOfClass:%c(DUXBadge)]) {
                [badges addObject:subview];
            }
        }
        cachedBadges = [badges copy];
        objc_setAssociatedObject(self, &kDYSidebarBadgeCacheKey, cachedBadges, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    for (UIView *badge in cachedBadges) {
        badge.hidden = YES;
    }
}
%end

%hook ACCStickerContainerView
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideSearchSame")) {
        [self removeFromSuperview];
    }
}
%end

%hook BDXWebView
- (void)layoutSubviews {
    %orig;

    BOOL enabled = DYYYGetBool(@"DYYYHideGiftPavilion");
    if (!enabled)
        return;

    NSString *title = [self valueForKey:@"title"];

    if ([title containsString:@"任务Banner"] || [title containsString:@"活动Banner"]) {
        self.hidden = YES;
    }
}
%end

%hook IESECLivePluginLayoutView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideLiveGoodsMsg")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

%hook IESECLiveCardSizeComponent
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideLiveGoodsMsg")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

%hook IESECLiveGoodsCardView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideLiveGoodsMsg")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

%hook IESLLLivePurchaseAtmosphereView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideLiveGoodsMsg") && self.superview) {
        self.superview.hidden = YES;
        return;
    }
    %orig;
}
%end

%hook _TtC18IESLiveRevenueImpl32IESLiveSwiftDynamicUserEnterView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideLivePopup")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

%hook PlatformCanvasView
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHideLivePopup")) {
        UIView *pview = self.superview;
        UIView *gpview = pview.superview;
        // 基于accessibilitylabel的判断
        BOOL isLynxView = [pview isKindOfClass:%c(UILynxView)] && [gpview isKindOfClass:%c(LynxView)] && [gpview.accessibilityLabel isEqualToString:@"lynxview"];
        // 基于最近的视图控制器IESLiveAudienceViewController的判断
        UIViewController *vc = [DYYYUtils firstAvailableViewControllerFromView:self];
        BOOL isLiveAudienceVC = [vc isKindOfClass:%c(IESLiveAudienceViewController)];
        if (isLynxView && isLiveAudienceVC) {
            self.hidden = YES;
        }
    }
    return;
}
%end

%hook _TtC18IESLiveRevenueImpl35IESLiveSwiftVideoLayerUserEnterView
- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideLivePopup")) {
        self.hidden = YES;
        return;
    }
    %orig;
}
%end

%hook AWEListDataController

- (void)setDataSource:(NSMutableArray *)dataSource {
    NSArray *filtered = [DYYYUtils arrayByRemovingAdvertisements:dataSource];
    %orig(filtered);
}

- (NSMutableArray *)dataSource {
    NSMutableArray *dataSource = %orig;
    NSArray *filtered = [DYYYUtils arrayByRemovingAdvertisements:dataSource];
    if (filtered != dataSource && [dataSource isKindOfClass:[NSMutableArray class]]) {
        [dataSource setArray:filtered];
    } else if (filtered != dataSource) {
        return [filtered mutableCopy];
    }
    return dataSource;
}

- (void)setFilteredDataSource:(NSMutableArray *)filteredDataSource {
    NSArray *filtered = [DYYYUtils arrayByRemovingAdvertisements:filteredDataSource];
    %orig(filtered);
}

- (NSMutableArray *)filteredDataSource {
    NSMutableArray *filteredDataSource = %orig;
    NSArray *filtered = [DYYYUtils arrayByRemovingAdvertisements:filteredDataSource];
    if (filtered != filteredDataSource && [filteredDataSource isKindOfClass:[NSMutableArray class]]) {
        [filteredDataSource setArray:filtered];
    } else if (filtered != filteredDataSource) {
        return [filtered mutableCopy];
    }
    return filteredDataSource;
}

%end

%hook AWEMixVideoListDataController

- (void)setDataSource:(id)dataSource {
    NSArray *filtered = [DYYYUtils arrayByRemovingAdvertisements:dataSource];
    %orig(filtered);
}

- (id)dataSource {
    id dataSource = %orig;
    NSArray *filtered = [DYYYUtils arrayByRemovingAdvertisements:dataSource];
    if (filtered != dataSource && [dataSource isKindOfClass:[NSMutableArray class]]) {
        [dataSource setArray:filtered];
    } else if (filtered != dataSource) {
        return filtered;
    }
    return dataSource;
}

%end

%hook AWEMixVideoDetailPlayListDataController

- (void)setDataSource:(id)dataSource {
    NSArray *filtered = [DYYYUtils arrayByRemovingAdvertisements:dataSource];
    %orig(filtered);
}

%end

%hook AWEMixVideoRelatedListDataController

- (void)setDataSource:(id)dataSource {
    NSArray *filtered = [DYYYUtils arrayByRemovingAdvertisements:dataSource];
    %orig(filtered);
}

- (id)dataSource {
    id dataSource = %orig;
    NSArray *filtered = [DYYYUtils arrayByRemovingAdvertisements:dataSource];
    if (filtered != dataSource && [dataSource isKindOfClass:[NSMutableArray class]]) {
        [dataSource setArray:filtered];
    } else if (filtered != dataSource) {
        return filtered;
    }
    return dataSource;
}

%end

%hook AWECodeGenStoryRingInfoModel

- (NSArray *)storyRingsModelArray {
	BOOL DYYYHideAvatarButton = DYYYGetBool(@"DYYYHideAvatarButton");
	if (DYYYHideAvatarButton) {
		return @[];
	}
	return %orig;
}

- (void)setStoryRingsModelArray:(NSArray *)array {
	BOOL DYYYHideAvatarButton = DYYYGetBool(@"DYYYHideAvatarButton");
	if (DYYYHideAvatarButton) {
		%orig(@[]);
		return;
	}
	%orig;
}

%end

%hook AWEInteractionHashtagStickerModel

- (id)hashtagInfo {
	BOOL DYYYHideChallengeStickers = DYYYGetBool(@"DYYYHideChallengeStickers");
	if (DYYYHideChallengeStickers) {
		return nil;
	}
	return %orig;
}

- (void)setHashtagInfo:(id)info {
	BOOL DYYYHideChallengeStickers = DYYYGetBool(@"DYYYHideChallengeStickers");
	if (DYYYHideChallengeStickers) {
		%orig(nil);
		return;
	}
	%orig;
}

- (id)hashtagId {
	BOOL DYYYHideChallengeStickers = DYYYGetBool(@"DYYYHideChallengeStickers");
	if (DYYYHideChallengeStickers) {
		return nil;
	}
	return %orig;
}

- (id)hashtagName {
	BOOL DYYYHideChallengeStickers = DYYYGetBool(@"DYYYHideChallengeStickers");
	if (DYYYHideChallengeStickers) {
		return nil;
	}
	return %orig;
}

%end

%hook AWEInteractionEditTagStickerModel

- (id)editTagInfo {
	if (DYYYGetBool(@"DYYYHideEditTag")) {
		return nil;
	}
	return %orig;
}

- (void)setEditTagInfo:(id)info {
	if (DYYYGetBool(@"DYYYHideEditTag")) {
		%orig(nil);
		return;
	}
	%orig;
}

%end

%hook AWETemplateStaticLabelInfoModel

- (NSArray *)containers {
	if (DYYYGetBool(@"DYYYHideTemplateLabel")) {
		return @[];
	}
	return %orig;
}

- (void)setContainers:(NSArray *)containers {
	if (DYYYGetBool(@"DYYYHideTemplateLabel")) {
		%orig(@[]);
		return;
	}
	%orig;
}

%end

%hook AFDFriendRecommendTagView

- (void)layoutSubviews {
	if (DYYYGetBool(@"DYYYHideFriendRecommend")) {
		self.hidden = YES;
		return;
	}
	%orig;
}

%end

%hook AWERelatedMusicAnchorModel

- (instancetype)init {
	BOOL DYYYHideQuqishuiting = DYYYGetBool(@"DYYYHideQuqishuiting");
	if (DYYYHideQuqishuiting) {
		return nil;
	}
	return %orig;
}

- (instancetype)initWithDictionary:(id)dict error:(NSError **)error {
	BOOL DYYYHideQuqishuiting = DYYYGetBool(@"DYYYHideQuqishuiting");
	if (DYYYHideQuqishuiting) {
		return nil;
	}
	return %orig;
}

%end

%hook TTAdSplashModel

+ (id)alloc {
	if (DYYYGetBool(@"DYYYNoAds")) {
		return nil;  // 直接返回 nil，阻止对象创建
	}
	return %orig;
}

%end

%hook AWEOriginalAdModel
- (instancetype)init {
	BOOL noAds = DYYYGetBool(@"DYYYNoAds");
	if (noAds) {
		return nil;  // 阻止创建，直接返回 nil
	}
	return %orig;
}

- (instancetype)initWithDictionary:(id)dict error:(NSError **)error {
	BOOL noAds = DYYYGetBool(@"DYYYNoAds");
	if (noAds) {
		return nil;  // 阻止创建，直接返回 nil
	}
	return %orig;
}
%end

%hook AWEGeneralSearchModel
- (instancetype)initWithDictionary:(id)dict error:(NSError **)error {
	id orig = %orig;
	
	BOOL noAds = DYYYGetBool(@"DYYYNoAds");
	if (!noAds || !orig) {
		return orig;
	}
	
	if ([DYYYUtils isAdvertisementContainerModel:orig] || [DYYYUtils isAdvertisementRawData:dict]) {
		return nil;
	}
	
	return orig;
}
%end

%hook AWEAwesomeSplashLiveCellAccessoryView

- (id)ddExtraView {
	if (DYYYGetBool(@"DYYYNoAds")) {
		return NULL;
	}

	return %orig;
}

%end

%hook AWETeenModeAlertView
- (BOOL)show {
	if (DYYYGetBool(@"DYYYHideTeenMode")) {
		return NO;
	}
	return %orig;
}
%end

%hook AWETeenModeSimpleAlertView
- (BOOL)show {
	if (DYYYGetBool(@"DYYYHideTeenMode")) {
		return NO;
	}
	return %orig;
}
%end

%hook AWEAwemeStatusModel
- (void)setListenVideoStatus:(NSInteger)status {
    if (status == 1 && DYYYGetBool(@"DYYYEnableBackgroundListen")) {
        status = 2;
    }
    %orig(status);
}
%end

%hook AFDPrivacyHalfScreenViewController

%new
- (void)updateDarkModeAppearance {
    BOOL isDarkMode = [DYYYUtils isDarkMode];

    UIView *contentView = self.view.subviews.count > 1 ? self.view.subviews[1] : nil;
    if (contentView) {
        if (isDarkMode) {
            contentView.backgroundColor = [UIColor colorWithRed:0.13 green:0.13 blue:0.13 alpha:1.0];
        } else {
            contentView.backgroundColor = [UIColor whiteColor];
        }
    }

    // 修改标题文本颜色
    if (self.titleLabel) {
        if (isDarkMode) {
            self.titleLabel.textColor = [UIColor whiteColor];
        } else {
            self.titleLabel.textColor = [UIColor blackColor];
        }
    }

    // 修改内容文本颜色
    if (self.contentLabel) {
        if (isDarkMode) {
            self.contentLabel.textColor = [UIColor lightGrayColor];
        } else {
            self.contentLabel.textColor = [UIColor darkGrayColor];
        }
    }

    // 修改左侧按钮颜色和文字颜色
    if (self.leftCancelButton) {
        if (isDarkMode) {
            [self.leftCancelButton setBackgroundColor:[UIColor colorWithRed:0.25 green:0.25 blue:0.25 alpha:1.0]]; // 暗色模式按钮背景色
            [self.leftCancelButton setTitleColor:[UIColor lightGrayColor] forState:UIControlStateNormal];          // 暗色模式文字颜色
        } else {
            [self.leftCancelButton setBackgroundColor:[UIColor colorWithRed:0.9 green:0.9 blue:0.9 alpha:1.0]]; // 默认按钮背景色
            [self.leftCancelButton setTitleColor:[UIColor darkTextColor] forState:UIControlStateNormal];        // 默认文字颜色
        }
    }
}

- (void)viewDidLoad {
    %orig;
    [self updateDarkModeAppearance];
}

- (void)viewWillAppear:(BOOL)animated {
    %orig;
    [self updateDarkModeAppearance];
}

- (void)configWithImageView:(UIImageView *)imageView
                  lockImage:(UIImage *)lockImage
           defaultLockState:(BOOL)defaultLockState
             titleLabelText:(NSString *)titleText
           contentLabelText:(NSString *)contentText
       leftCancelButtonText:(NSString *)leftButtonText
     rightConfirmButtonText:(NSString *)rightButtonText
       rightBtnClickedBlock:(void (^)(void))rightBtnBlock
     leftButtonClickedBlock:(void (^)(void))leftBtnBlock {

    %orig;
    [self updateDarkModeAppearance];
}

%end

%hook UITextField

- (void)willMoveToWindow:(UIWindow *)newWindow {
    %orig;

    if (newWindow) {
        BOOL isDarkMode = [DYYYUtils isDarkMode];
        self.keyboardAppearance = isDarkMode ? UIKeyboardAppearanceDark : UIKeyboardAppearanceLight;
    }
}

- (BOOL)becomeFirstResponder {
    BOOL isDarkMode = [DYYYUtils isDarkMode];
    self.keyboardAppearance = isDarkMode ? UIKeyboardAppearanceDark : UIKeyboardAppearanceLight;
    return %orig;
}

%end

%hook UITextView

- (void)willMoveToWindow:(UIWindow *)newWindow {
    %orig;

    if (newWindow) {
        BOOL isDarkMode = [DYYYUtils isDarkMode];
        self.keyboardAppearance = isDarkMode ? UIKeyboardAppearanceDark : UIKeyboardAppearanceLight;
    }
}

- (BOOL)becomeFirstResponder {
    BOOL isDarkMode = [DYYYUtils isDarkMode];
    self.keyboardAppearance = isDarkMode ? UIKeyboardAppearanceDark : UIKeyboardAppearanceLight;
    return %orig;
}

%end

%hook AWEListKitMagicCollectionView

- (void)layoutSubviews {
    %orig;
    [DYYYCommentBlurCoordinator layoutListView:self];

}

%end

%hook AFDPureModePageTapController

- (void)onVideoPlayerViewDoubleClicked:(id)arg1 {
    BOOL isSwitchOn = DYYYGetBool(@"DYYYDisableDoubleTapLike");
    if (!isSwitchOn) {
        %orig;
    }
}

%end

%hook AFDFastSpeedView
- (void)layoutSubviews {
    %orig;

    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYEnableFullScreen"]) {
        return;
    }

    static char kDYFastSpeedBgKey;
    NSArray *bgViews = objc_getAssociatedObject(self, &kDYFastSpeedBgKey);
    if (!bgViews) {
        NSMutableArray *tmp = [NSMutableArray array];
        for (UIView *subview in self.subviews) {
            if ([subview class] == [UIView class]) {
                [tmp addObject:subview];
            }
        }
        bgViews = [tmp copy];
        objc_setAssociatedObject(self, &kDYFastSpeedBgKey, bgViews, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    for (UIView *view in bgViews) {
        view.backgroundColor = [UIColor clearColor];
    }
}
%end

%hook TTPlayerView
- (void)setFrame:(CGRect)frame {
    if (![NSThread isMainThread]) {
        __weak UIView *weakView = self;
        dispatch_async(dispatch_get_main_queue(), ^{ weakView.frame = frame; });
        return;
    }
    %orig([DYYYFullscreenCoordinator frameForPlayer:self proposed:frame]);
}

- (void)layoutSubviews {
    [DYYYFullscreenCoordinator preparePlayer:self];
    %orig;
    UIView *parent = self.superview;
    if (parent) parent.backgroundColor = self.backgroundColor;
    [DYYYFullscreenCoordinator finishPlayer:self];
}
%end

%hook TTMetalView
- (void)setCenter:(CGPoint)center {
    BOOL shouldAdjust = NO;
    UIView *view = (UIView *)self;
    if (DYYYGetBool(@"DYYYEnableFullScreen")) {
        CGFloat viewWidth = CGRectGetWidth(view.bounds);
        CGFloat containerWidth = view.superview.bounds.size.width;
        if (containerWidth > 0 && fabs(viewWidth - containerWidth) <= 1) {
            UIViewController *vc = [DYYYUtils firstAvailableViewControllerFromView:view];
            Class playClass = %c(AWEPlayVideoViewController);
            if (playClass && [vc isKindOfClass:playClass] && [DYYYFullscreenCoordinator usesRecommendedLayoutForController:vc] && [DYYYFullscreenCoordinator isImageContentController:vc]) {
                AWEPlayVideoViewController *playVC = (AWEPlayVideoViewController *)vc;
                AWEAwemeModel *model = playVC.model;
                if ([model respondsToSelector:@selector(isShowLandscapeEntryView)] && model.isShowLandscapeEntryView) {
                    shouldAdjust = YES;
                }
            }
        }
    }

    if (shouldAdjust) {
        CGFloat offset = [DYYYFullscreenCoordinator bottomOccupiedHeightForView:view];
        if (offset > 0) {
            center.y -= offset * 0.5;
        }
    }

    %orig(center);
}
%end

%hook TTMetalViewNew
- (void)setCenter:(CGPoint)center {
    BOOL shouldAdjust = NO;
    UIView *view = (UIView *)self;
    if (DYYYGetBool(@"DYYYEnableFullScreen")) {
        CGFloat viewWidth = CGRectGetWidth(view.bounds);
        CGFloat containerWidth = view.superview.bounds.size.width;
        if (containerWidth > 0 && fabs(viewWidth - containerWidth) <= 1) {
            UIViewController *vc = [DYYYUtils firstAvailableViewControllerFromView:view];
            Class playClass = %c(AWEPlayVideoViewController);
            if (playClass && [vc isKindOfClass:playClass] && [DYYYFullscreenCoordinator usesRecommendedLayoutForController:vc] && [DYYYFullscreenCoordinator isImageContentController:vc]) {
                AWEPlayVideoViewController *playVC = (AWEPlayVideoViewController *)vc;
                AWEAwemeModel *model = playVC.model;
                if ([model respondsToSelector:@selector(isShowLandscapeEntryView)] && model.isShowLandscapeEntryView) {
                    shouldAdjust = YES;
                }
            }
        }
    }

    if (shouldAdjust) {
        CGFloat offset = [DYYYFullscreenCoordinator bottomOccupiedHeightForView:view];
        if (offset > 0) {
            center.y -= offset * 0.5;
        }
    }

    %orig(center);
}
%end

%hook TTMetalViewVP
- (void)setCenter:(CGPoint)center {
    BOOL shouldAdjust = NO;
    UIView *view = (UIView *)self;
    if (DYYYGetBool(@"DYYYEnableFullScreen")) {
        CGFloat viewWidth = CGRectGetWidth(view.bounds);
        CGFloat containerWidth = view.superview.bounds.size.width;
        if (containerWidth > 0 && fabs(viewWidth - containerWidth) <= 1) {
            UIViewController *vc = [DYYYUtils firstAvailableViewControllerFromView:view];
            Class playClass = %c(AWEPlayVideoViewController);
            if (playClass && [vc isKindOfClass:playClass] && [DYYYFullscreenCoordinator usesRecommendedLayoutForController:vc] && [DYYYFullscreenCoordinator isImageContentController:vc]) {
                AWEPlayVideoViewController *playVC = (AWEPlayVideoViewController *)vc;
                AWEAwemeModel *model = playVC.model;
                if ([model respondsToSelector:@selector(isShowLandscapeEntryView)] && model.isShowLandscapeEntryView) {
                    shouldAdjust = YES;
                }
            }
        }
    }

    if (shouldAdjust) {
        CGFloat offset = [DYYYFullscreenCoordinator bottomOccupiedHeightForView:view];
        if (offset > 0) {
            center.y -= offset * 0.5;
        }
    }

    %orig(center);
}
%end

%hook AWEMixVideoPanelMoreView

- (void)setFrame:(CGRect)frame {
    if (DYYYGetBool(@"DYYYEnableFullScreen")) {
        CGFloat bottomHeight = [DYYYFullscreenCoordinator bottomOccupiedHeightForView:self];
        CGFloat targetY = frame.origin.y - bottomHeight;
        CGFloat screenHeightMinusGDiff = CGRectGetMaxY(self.superview.bounds) - bottomHeight;

        CGFloat tolerance = 10.0;

        if (self.superview && bottomHeight > 0 && fabs(targetY - screenHeightMinusGDiff) <= tolerance) {
            frame.origin.y = targetY;
        }
    }
    %orig(frame);
}

- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYEnableFullScreen")) {
        self.backgroundColor = [UIColor clearColor];
    }
}

%end

%hook CommentInputContainerView

- (void)layoutSubviews {
    %orig;
    UIViewController *parentVC = nil;
    if ([self respondsToSelector:@selector(viewController)]) {
        id viewController = [self performSelector:@selector(viewController)];
        if ([viewController respondsToSelector:@selector(parentViewController)]) {
            parentVC = [viewController parentViewController];
        }
    }

    [DYYYFullscreenCoordinator layoutBottomInput:self controller:parentVC];
}

%end

%hook DUXPopover
- (void)layoutSubviews {
    %orig;

    if (!DYYYGetBool(@"DYYYHidePopover")) {
        return;
    }

    id rawContent = nil;
    @try {
        rawContent = [self valueForKey:@"content"];
    } @catch (__unused NSException *e) {
        return;
    }

    NSString *text = [rawContent isKindOfClass:NSString.class] ? (NSString *)rawContent : [rawContent description];

    if ([text containsString:@"上次看到"]) {
        self.hidden = YES;
        return;
    }
}
%end

%hook _TtC21AWEIncentiveSwiftImpl20PendantContainerView
- (void)layoutSubviews {
    %orig;
    if (DYYYGetBool(@"DYYYHidePendantGroup")) {
        [self removeFromSuperview];
    }
}
%end

%hook AWELuckyCatBannerView
- (id)initWithFrame:(CGRect)frame {
    return nil;
}

- (id)init {
    return nil;
}
%end

%hook AFDViewedBottomView
- (void)layoutSubviews {
    %orig;

    if (DYYYGetBool(@"DYYYEnableFullScreen")) {

        self.backgroundColor = [UIColor clearColor];

        self.effectView.hidden = YES;
    }
}
%end

%group BDMultiContentImageViewGroup
%hook BDMultiContentContainer_ImageContentView

- (void)setTransform:(CGAffineTransform)transform {
    %orig([DYYYFullscreenCoordinator transformForImageView:self proposed:transform]);
}

- (void)layoutSubviews {
    %orig;
    [DYYYFullscreenCoordinator layoutImageView:self];
}

%end
%end

%group DYYYFullscreenCommentGroup
%hook AWECommentPanelContainerSwiftImpl_CommentContainerInnerViewController
- (void)viewDidLayoutSubviews {
    %orig;
    [DYYYCommentBlurCoordinator layoutController:self];
    [DYYYFullscreenCoordinator commentController:self visible:YES];
    [DYYYFloatingButtonCoordinator commentController:self visible:YES];
}
- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    [DYYYFullscreenCoordinator commentController:self visible:NO];
    [DYYYFloatingButtonCoordinator commentController:self visible:NO];
}
%end
%end

%group DYYYFullscreenCommentPanelGroup
// 41.0：评论区外层面板是 CommentPanelViewController（38 字符类），
// 首次从 Feed 打开评论区走它而不经过 InnerViewController，
// 旧 hook 全部旁路（用户实测毛玻璃不透 + 日志无第二次 [DYYY][blur]）。
// 面板级 hook 保证任意打开路径都会触发毛玻璃布局与全屏协调。
%hook AWECommentPanelContainerSwiftImpl_CommentPanelViewController
- (void)viewDidLayoutSubviews {
    %orig;
    [DYYYCommentBlurCoordinator layoutController:self];
    [DYYYFullscreenCoordinator commentController:self visible:YES];
    [DYYYFloatingButtonCoordinator commentController:self visible:YES];
}
- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    [DYYYFullscreenCoordinator commentController:self visible:NO];
    [DYYYFloatingButtonCoordinator commentController:self visible:NO];
}
%end
%end
