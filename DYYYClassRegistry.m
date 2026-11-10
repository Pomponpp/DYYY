#import "AwemeHeaders.h"
#import "DYYYClassRegistry.h"
#import <objc/runtime.h>

// 关键类清单：优先收录 40.9 曾失效的改名/迁移类，以及全屏、评论、直播链路核心类。
// 每项 = { 运行时类名, 40.9 继任类名（无则 NULL）, 失效时受影响的功能（中文，供可读报告） }
typedef struct {
    const char *primary;
    const char *successor; // 可为 NULL
    const char *feature;   // 可为 NULL
} DYYYAuditEntry;

#define DYYY_AUDIT(name, feat) {(name), NULL, (feat)}

static const DYYYAuditEntry kDYYYAuditTable[] = {
    // ---- 全屏 / 互动区链路 ----
    DYYY_AUDIT("AWEPlayInteractionViewController", "全屏布局、互动区、评论入口"),
    DYYY_AUDIT("AWEAwemeDetailTableViewController", "详情页全屏分页"),
    DYYY_AUDIT("AWEAwemeDetailCellViewController", "详情页底栏透明"),
    DYYY_AUDIT("AFDPlayRemoteFeedTableViewController", "远程播放页排除"),
    DYYY_AUDIT("AFDPureModePageListViewController", "清屏纯净模式状态栏"),
    DYYY_AUDIT("AFDPureModePageContainerViewController", "清屏页媒体归还"),
    DYYY_AUDIT("AFDPureModePageTapController", "双击点赞屏蔽"),
    DYYY_AUDIT("AWEFeedContainerViewController", "翻页清屏状态保持"),
    DYYY_AUDIT("AWEFeedTableView", "全屏 Feed 高度"),
    DYYY_AUDIT("AWEFeedTableViewCell", "清屏状态重挂"),
    DYYY_AUDIT("AWEFeedViewCell", "清屏状态重挂"),
    DYYY_AUDIT("AWEFeedCellViewController", "速度按钮定位"),
    DYYY_AUDIT("AWEDPlayerFeedPlayerViewController", "倍速播放"),
    DYYY_AUDIT("AWEAwemePlayVideoViewController", "倍速播放"),
    DYYY_AUDIT("AWEDPlayerViewController_Merge", "倍速播放"),
    DYYY_AUDIT("TTPlayerView", "播放器全屏画面"),
    DYYY_AUDIT("AWENormalModeTabBar", "底栏高度/全屏底栏透明"),
    DYYY_AUDIT("AWENormalModeTabBarController", "悬浮按钮页面切换"),
    DYYY_AUDIT("AWEBaseElementView", "昵称下移/缩放"),
    DYYY_AUDIT("AWEUserNameLabel", "昵称下移/缩放"),
    DYYY_AUDIT("AWEPlayInteractionDescriptionLabel", "文案下移、长按复制"),
    DYYY_AUDIT("AWEPlayInteractionDescriptionScrollView", "文案下移"),
    DYYY_AUDIT("AWEStoryProgressContainerView", "清屏图片滑条偏移"),
    DYYY_AUDIT("AWELiveGuideElement", "禁用自动进直播"),
    DYYY_AUDIT("_TtC22AWEFeedPlayControlImpl30PureModePageCellViewController", "清屏图片滑条偏移"),

    // ---- 评论链路 ----
    DYYY_AUDIT("AWECommentContainerViewController", "评论全屏协调、毛玻璃"),
    DYYY_AUDIT("AWECommentInputViewController", "评论输入底栏"),
    DYYY_AUDIT("AWECommentInputBackgroundView", "评论输入背景偏移"),
    DYYY_AUDIT("_TtC20AWECommentSwiftBizUI27CommentInteractionBaseLabel", "评论精确时间"),
    DYYY_AUDIT("_TtC33AWECommentPanelContainerSwiftImpl35CommentContainerInnerViewController", "评论全屏协调"),
    DYYY_AUDIT("_TtC27AWECommentCommerceSwiftImpl24CommentHeaderGeneralView", "评论区商品位隐藏"),
    DYYY_AUDIT("_TtC27AWECommentCommerceSwiftImpl22CommentHeaderGoodsView", "评论区商品位隐藏"),
    DYYY_AUDIT("_TtC30AWECommentPanelHeaderSwiftImpl31CommentHeaderTemplateAnchorView", "评论区锚点隐藏"),
    DYYY_AUDIT("_TtC28AWECommentInputViewSwiftImpl25CommentInputContainerView", "评论输入毛玻璃"),
    DYYY_AUDIT("_TtC28AWECommentInputViewSwiftImpl31CommentInputViewMiddleContainer", "评论输入毛玻璃"),
    DYYY_AUDIT("_TtC28AWECommentMediaFeedSwfitImpl34CommentMediaFeedCellViewController", "多图下载索引"),

    // ---- 40.9 改名继任类 ----
    DYYY_AUDIT("AWEFullPageFeedContainerViewController", "图文页状态栏隐藏"),
    DYYY_AUDIT("AWEProfileAvatarFunctionManager", "保存他人头像"),
    DYYY_AUDIT("AWEFamiliarSkylightBubbleView", "消息页头像气泡隐藏"),
    DYYY_AUDIT("AWEProfileTaskCardStyleListItemCell", "主页发布引导隐藏"),
    DYYY_AUDIT("AWEProfilePublishGuideCollectionViewCell", "空主页发布引导隐藏"),
    DYYY_AUDIT("AWEAwesomeSplashLiveCellAccessoryView", "开屏广告去除"),
    DYYY_AUDIT("IESLLLivePurchaseAtmosphereView", "直播间商品推广隐藏"),
    DYYY_AUDIT("_TtC21AWEIncentiveSwiftImpl20PendantContainerView", "红包挂件隐藏"),
    DYYY_AUDIT("AWEIMCommentShareTableViewCell", "评论分享好友隐藏"),

    // ---- 直播链路 ----
    DYYY_AUDIT("AWELiveFeedStatusLabel", "隐藏点击进入直播间"),
    DYYY_AUDIT("AWELiveFeedLabelTagView", "隐藏直播提示"),
    DYYY_AUDIT("IESLiveInnerFeedLiveRoomCell", "直播时长浮窗"),
    DYYY_AUDIT("IESLiveAudienceViewController", "直播间状态栏/开播时长"),
    DYYY_AUDIT("IESLiveUserSeqlistFragment", "直播真实人数"),
    DYYY_AUDIT("AWEFeedLiveMarkView", "直播标记"),
    DYYY_AUDIT("IESLiveFlowGuidanceFragment", "直播伴侣提示隐藏"),
    DYYY_AUDIT("IESECLiveCardSizeComponent", "直播间商品卡隐藏"),
    DYYY_AUDIT("IESECLiveGoodsCardView", "直播间商品卡隐藏"),
    DYYY_AUDIT("IESLiveBottomRightCardView", "直播间右下卡隐藏"),

    // ---- 其它高频功能 ----
    DYYY_AUDIT("AWEDateTimeFormatter", "评论精确时间"),
    DYYY_AUDIT("AWERLVirtualLabel", "评论精确时间"),
    DYYY_AUDIT("YYLabel", "评论模糊、展开时间"),
    DYYY_AUDIT("DDanmakuPlayerView", "弹幕显示保持"),
    DYYY_AUDIT("AWEDanmakuContentLabel", "弹幕改色"),
    DYYY_AUDIT("AWEFeedChannelManager", "频道隐藏（商城/团购等）"),
    DYYY_AUDIT("AWEHPTopTabItemTextContentView", "顶栏改名"),
    DYYY_AUDIT("AWEHPTopTabItemBadgeContentView", "首页直播胶囊隐藏"),
    DYYY_AUDIT("AWEVersionUpdateManager", "版本检测"),
    DYYY_AUDIT("AWESettingBaseViewController", "DYYY 设置入口"),

    // ---- 自动补全：覆盖全部 %hook 目标（按源文件归属，适配时按域查）----

    // 全屏（DYYYHooksFullscreen.xm，13 项）
    DYYY_AUDIT("AWEDPlayerProgressContainerView", "全屏 · layoutSubviews"),
    DYYY_AUDIT("AWEFeedDataSafeTableView", "全屏 · setFrame"),
    DYYY_AUDIT("AWEFeedTableViewController", "全屏 · viewDidLayoutSubviews"),
    DYYY_AUDIT("AWEPlayInteractionCommentPanelController", "全屏 · performCommentAction"),
    DYYY_AUDIT("AWEPlayInteractionListenFeedView", "全屏 · layoutSubviews"),
    DYYY_AUDIT("AWEPlayInteractionLiveExtendGuideView", "全屏 · layoutSubviews"),
    DYYY_AUDIT("AWEPlayInteractionProgressContainerView", "全屏 · layoutSubviews"),
    DYYY_AUDIT("AWEPlayInteractionProgressController", "全屏 · dyyy_syncScheduleLabelsWithCurrentTime/updateProgressSliderWithTime"),
    DYYY_AUDIT("AWEPlayInteractionSearchAnchorView", "全屏 · layoutSubviews"),
    DYYY_AUDIT("AWEPlayInteractionStrongifyShareContentView", "全屏 · layoutSubviews"),
    DYYY_AUDIT("AWEPlayInteractionTemplateButton", "全屏 · button/setButton"),
    DYYY_AUDIT("AWEPlayInteractionUserAvatarElement", "全屏 · onFollowViewClicked"),
    DYYY_AUDIT("AWEPlayInteractionUserAvatarFollowController", "全屏 · onFollowViewClicked"),

    // Feed（DYYYHooksFeed.xm，15 项）
    DYYY_AUDIT("AWEFeedCommentConfigModel", "Feed · setCommentInputConfigText"),
    DYYY_AUDIT("AWEFeedLiveTabRevisitControlView", "Feed · layoutSubviews"),
    DYYY_AUDIT("AWEFeedLiveTabTopSelectionView", "Feed · setHideTimer"),
    DYYY_AUDIT("AWEFeedMultiTabSelectedContainerView", "Feed · layoutSubviews"),
    DYYY_AUDIT("AWEFeedProgressSlider", "Feed · layoutSubviews/setAlpha"),
    DYYY_AUDIT("AWEFeedRootViewController", "Feed · prefersStatusBarHidden"),
    DYYY_AUDIT("AWEFeedTabJumpGuideView", "Feed · layoutSubviews"),
    DYYY_AUDIT("AWEFeedTopBarContainer", "Feed · didMoveToSuperview/setAlpha"),
    DYYY_AUDIT("AWEFeedUnfollowFamiliarFollowAndDislikeView", "Feed · showUnfollowFamiliarView"),
    DYYY_AUDIT("AWEHotSearchInnerBottomView", "Feed · layoutSubviews"),
    DYYY_AUDIT("AWEHotSpotBlurView", "Feed · layoutSubviews"),
    DYYY_AUDIT("AWEHotSpotListModel", "Feed · disableDisplay/disableDisplayInner"),
    DYYY_AUDIT("AWEHPChannelInvisibleWaterMarkModel", "Feed · isEnter/isAppear"),
    DYYY_AUDIT("AWESearchAnchorListModel", "Feed · hideWords"),
    DYYY_AUDIT("AWESearchEntranceView", "Feed · layoutSubviews"),

    // 底栏（DYYYHooksTabBar.xm，7 项）
    DYYY_AUDIT("AWENormalModeTabBarBadgeContainerView", "底栏 · layoutSubviews"),
    DYYY_AUDIT("AWENormalModeTabBarFeedView", "底栏 · layoutSubviews"),
    DYYY_AUDIT("AWENormalModeTabBarGeneralButton", "底栏 · enableRefresh"),
    DYYY_AUDIT("AWENormalModeTabBarGeneralPlusButton", "底栏 · setImage"),
    DYYY_AUDIT("AWENormalModeTabBarPlusButton", "底栏 · setHidden/didMoveToWindow"),
    DYYY_AUDIT("AWENormalModeTabBarTextView", "底栏 · layoutSubviews"),
    DYYY_AUDIT("AWETabBarElementContainerView", "底栏 · setHidden"),

    // 媒体（DYYYHooksMedia.xm，14 项）
    DYYY_AUDIT("AWEIMCellLiveStatusContainerView", "媒体 · p_initUI"),
    DYYY_AUDIT("AWEIMEmoticonPreviewV2", "媒体 · layoutSubviews/dyyy_saveButtonTapped"),
    DYYY_AUDIT("AWEIMFansGroupTopDynamicDomainTemplateView", "媒体 · layoutSubviews"),
    DYYY_AUDIT("AWEIMFeedBottomQuickEmojiInputBar", "媒体 · layoutSubviews"),
    DYYY_AUDIT("AWEIMFeedVideoQuickReplayInputViewController", "媒体 · tableView/viewDidLayoutSubviews"),
    DYYY_AUDIT("AWEIMInputActionBarInteractor", "媒体 · p_setupUI"),
    DYYY_AUDIT("AWEIMMessageTabOptPushBannerView", "媒体 · initWithFrame"),
    DYYY_AUDIT("AWEIMMessageTabSideBarView", "媒体 · layoutSubviews"),
    DYYY_AUDIT("AWEIMPhotoPickerFunctionModel", "媒体 · setUseShadowIcon/isSelected"),
    DYYY_AUDIT("AWEIMSkylightListView", "媒体 · setFrame"),
    DYYY_AUDIT("AWEMusicCoverButton", "媒体 · layoutSubviews"),
    DYYY_AUDIT("AWEMusicExtraModel", "媒体 · commentTopBarInfo/setCommentTopBarInfo"),
    DYYY_AUDIT("AWEStoryProgressSlideView", "媒体 · layoutSubviews"),
    DYYY_AUDIT("AWEVideoTypeTagView", "媒体 · setupUI"),

    // 直播（DYYYHooksLive.xm，27 项）
    DYYY_AUDIT("AWEInnerNotificationWindow", "直播 · layoutSubviews/didMoveToWindow"),
    DYYY_AUDIT("AWELiveAutoEnterStyleAView", "直播 · layoutSubviews"),
    DYYY_AUDIT("AWELiveFlowAlertView", "直播 · layoutSubviews"),
    DYYY_AUDIT("AWELiveSkylightViewModel", "直播 · dataSource/setDataSource"),
    DYYY_AUDIT("AWELiveStatusIndicatorView", "直播 · layoutSubviews"),
    DYYY_AUDIT("HTSLiveDiggView", "直播 · setIconImageView"),
    DYYY_AUDIT("HTSLiveStreamPcdnManager", "直播"),
    DYYY_AUDIT("IESLiveActivityBannnerView", "直播 · layoutSubviews"),
    DYYY_AUDIT("IESLiveButton", "直播 · layoutSubviews"),
    DYYY_AUDIT("IESLiveConfigurableShortTouchEntranceView", "直播 · layoutSubviews"),
    DYYY_AUDIT("IESLiveDanmakuSupremeView", "直播 · layoutSubviews"),
    DYYY_AUDIT("IESLiveDanmakuVariousView", "直播 · layoutSubviews"),
    DYYY_AUDIT("IESLiveDynamicRankListEntranceView", "直播 · layoutSubviews"),
    DYYY_AUDIT("IESLiveDynamicUserEnterView", "直播 · layoutSubviews"),
    DYYY_AUDIT("IESLiveFeedDrawerEntranceView", "直播 · layoutSubviews"),
    DYYY_AUDIT("IESLiveGameCPExplainCardContainerImpl", "直播 · layoutSubviews"),
    DYYY_AUDIT("IESLiveGroupLiveComponentView", "直播 · layoutSubviews"),
    DYYY_AUDIT("IESLiveHotMessageView", "直播 · layoutSubviews"),
    DYYY_AUDIT("IESLiveKTVSongIndicatorView", "直播 · layoutSubviews"),
    DYYY_AUDIT("IESLiveLaunchTaskPcdn", "直播 · excute"),
    DYYY_AUDIT("IESLiveLayoutPlaceholderView", "直播 · layoutSubviews"),
    DYYY_AUDIT("IESLiveLotteryAnimationViewNew", "直播 · layoutSubviews"),
    DYYY_AUDIT("IESLiveMatrixEntranceView", "直播 · layoutSubviews"),
    DYYY_AUDIT("IESLivePreAnnouncementPanelViewNew", "直播 · layoutSubviews"),
    DYYY_AUDIT("IESLiveRedEnvelopeAniLynxView", "直播 · layoutSubviews"),
    DYYY_AUDIT("IESLiveShortTouchActionView", "直播 · layoutSubviews"),
    DYYY_AUDIT("IESLiveStickerView", "直播 · layoutSubviews"),

    // 评论（DYYYHooksComment.xm，3 项）
    DYYY_AUDIT("AWECommentGuideLunaAnchorView", "评论 · layoutSubviews/p_didClickSong"),
    DYYY_AUDIT("AWECommentImageModel", "评论 · downloadUrl"),
    DYYY_AUDIT("AWECommentMediaDownloadConfigLivePhoto", "评论 · needClientWaterMark/needClientEndWaterMark"),

    // 主页（DYYYHooksProfile.xm，4 项）
    DYYY_AUDIT("AWEProfileMentionLabel", "主页 · layoutSubviews/handleLongPress"),
    DYYY_AUDIT("AWEProfileMixItemCollectionViewCell", "主页 · layoutSubviews"),
    DYYY_AUDIT("AWEProfileNavigationButton", "主页 · setupUI"),
    DYYY_AUDIT("AWEProfileRichEmptyView", "主页 · setTitle/setDetail"),

    // 设置（DYYYHooksSettings.xm，2 项）
    DYYY_AUDIT("AWELeftSideBarAddChildTransitionObject", "设置 · handleShowSliderPanGesture"),
    DYYY_AUDIT("AWELeftSideBarEntranceView", "设置 · setRedDot/setNumericalRedDot"),

    // 通用（DYYYHooksGlobal.xm，4 项）
    DYYY_AUDIT("AWEBaseListSectionBackgroundView", "通用 · setBackgroundColor/setOpaque"),
    DYYY_AUDIT("AWEBaseListViewController", "通用 · viewDidLayoutSubviews/applyBlurEffectIfNeeded"),
    DYYY_AUDIT("UIButton", "通用 · layoutSubviews"),
    DYYY_AUDIT("UIViewController", "通用 · viewWillAppear/viewWillDisappear"),

    // 核心（DYYY.xm，170 项）
    DYYY_AUDIT("_TtC18IESLiveRevenueImpl32IESLiveSwiftDynamicUserEnterView", "核心 · layoutSubviews"),
    DYYY_AUDIT("_TtC18IESLiveRevenueImpl34IESLiveDynamicRankListEntranceView", "核心 · layoutSubviews"),
    DYYY_AUDIT("_TtC18IESLiveRevenueImpl35IESLiveSwiftVideoLayerUserEnterView", "核心 · layoutSubviews"),
    DYYY_AUDIT("_TtC33AWECommentLongPressPanelSwiftImpl32CommentLongPressPanelCopyElement", "核心 · elementTapped"),
    DYYY_AUDIT("_TtC33AWECommentLongPressPanelSwiftImpl37CommentLongPressPanelSaveImageElement", "核心 · elementShouldShow/elementTapped"),
    DYYY_AUDIT("_TtCV28AWECommentPanelListSwiftImpl6NEWAPI27CommentCellStickerComponent", "核心 · handleLongPressWithGes"),
    DYYY_AUDIT("ACCStickerContainerView", "核心 · layoutSubviews"),
    DYYY_AUDIT("AFDCancelMuteAwemeView", "核心 · layoutSubviews"),
    DYYY_AUDIT("AFDFastSpeedView", "核心 · layoutSubviews"),
    DYYY_AUDIT("AFDFriendRecommendTagView", "核心 · layoutSubviews"),
    DYYY_AUDIT("AFDNewFastReplyView", "核心 · layoutSubviews"),
    DYYY_AUDIT("AFDPrivacyHalfScreenViewController", "核心 · updateDarkModeAppearance/viewDidLoad"),
    DYYY_AUDIT("AFDRecommendToFriendEntranceLabel", "核心 · layoutSubviews"),
    DYYY_AUDIT("AFDViewedBottomView", "核心 · layoutSubviews"),
    DYYY_AUDIT("ALMOwnPlayerWrapper", "核心 · setLutFilter"),
    DYYY_AUDIT("ALMSysPlayerWrapper", "核心 · setLutFilter"),
    DYYY_AUDIT("ALMVideoPlayerConfig", "核心"),
    DYYY_AUDIT("AppDelegate", "核心 · application/applicationWillTerminate"),
    DYYY_AUDIT("AVPlayer", "核心 · initWithURL/initWithPlayerItem"),
    DYYY_AUDIT("AVPlayerItem", "核心 · initWithURL/initWithAsset"),
    DYYY_AUDIT("AVPlayerLayer", "核心 · setPlayer/layoutSublayers"),
    DYYY_AUDIT("AWEAdAvatarView", "核心 · layoutSubviews"),
    DYYY_AUDIT("AWEAwemeBackgroundPlayModule", "核心 · nowPlayingInfo/refreshNowPlayingInfoIfNeeded"),
    DYYY_AUDIT("AWEAwemeDetailContainerPlayControlConfig", "核心 · enableUserProfilePostAutoPlay"),
    DYYY_AUDIT("AWEAwemeHotSpotTableViewController", "核心 · prefersStatusBarHidden"),
    DYYY_AUDIT("AWEAwemeModel", "核心 · initWithDictionary/setVideo"),
    DYYY_AUDIT("AWEAwemeStatusModel", "核心 · setListenVideoStatus"),
    DYYY_AUDIT("AWEBDSimPlayerBizConfig", "核心 · enableHDRBrightnessOpt/enableHDRFullModelAdaptation"),
    DYYY_AUDIT("AWECodeGenStoryRingInfoModel", "核心 · storyRingsModelArray/setStoryRingsModelArray"),
    DYYY_AUDIT("AWECommentPanelContainerSwiftImpl_CommentContainerInnerViewController", "核心 · viewDidLayoutSubviews/viewDidDisappear"),
    DYYY_AUDIT("AWECommentPanelContainerSwiftImpl_CommentPanelViewController", "核心 · viewDidLayoutSubviews/viewDidDisappear"),
    DYYY_AUDIT("AWECommentPanelHeaderSwiftImpl_CommentHeaderGeneralView", "核心 · layoutSubviews"),
    DYYY_AUDIT("AWECommentPanelHeaderSwiftImpl_CommentHeaderGoodsView", "核心 · layoutSubviews"),
    DYYY_AUDIT("AWECommentPanelHeaderSwiftImpl_CommentHeaderTemplateAnchorView", "核心 · layoutSubviews"),
    DYYY_AUDIT("AWECommentPanelListSwiftImpl_CommentBottomTipsContainerViewController", "核心 · viewWillAppear"),
    DYYY_AUDIT("AWECommentSwiftBizUI_CommentInteractionBaseLabel", "核心 · setText/setFrame"),
    DYYY_AUDIT("AWEConcernCellLastView", "核心 · layoutSubviews"),
    DYYY_AUDIT("AWECorrelationItemTag", "核心 · layoutSubviews"),
    DYYY_AUDIT("AWEDiscoverFeedEntranceView", "核心 · init"),
    DYYY_AUDIT("AWEDPlayerBrightnessContainer", "核心 · awe_isCurrentVideoHDR"),
    DYYY_AUDIT("AWEDPlayerVideoDisplayOptState", "核心 · enableHDR/setEnableHDR"),
    DYYY_AUDIT("AWEDPlayerVideoModel", "核心 · awe_isHDRVideo/setAwe_isHDRVideo"),
    DYYY_AUDIT("AWEDProgressCoreContainer", "核心 · dyyy_syncScheduleLabelsWithCurrentTime/updateProgressSliderWithTime"),
    DYYY_AUDIT("AWEElementStackView", "核心 · setAlpha/didMoveToWindow"),
    DYYY_AUDIT("AWEFamiliarNavView", "核心 · layoutSubviews"),
    DYYY_AUDIT("AWEFeedABSettings", "核心"),
    DYYY_AUDIT("AWEFeedABTestServiceObjc", "核心"),
    DYYY_AUDIT("AWEFeedBackgroundPlayManager", "核心 · nowPlayingInfo/setNowPlayingInfo"),
    DYYY_AUDIT("AWEFeedIPhoneAutoPlayManager", "核心 · isAutoPlayOpen/getFeedIphoneAutoPlayState"),
    DYYY_AUDIT("AWEFeedModuleService", "核心 · getFeedIphoneAutoPlayState"),
    DYYY_AUDIT("AWEFeedVideoButton", "核心 · touchUpInsideBlock/setImage"),
    DYYY_AUDIT("AWEGeneralSearchModel", "核心 · initWithDictionary"),
    DYYY_AUDIT("AWEGradientView", "核心 · layoutSubviews"),
    DYYY_AUDIT("AWEHotListDataController", "核心 · dyyy_numberValueForLowLikesFilter/dyyy_resolvedDiggCountForAweme"),
    DYYY_AUDIT("AWEHPDiscoverFeedEntranceView", "核心 · layoutSubviews"),
    DYYY_AUDIT("AWEHPSearchBubbleEntranceView", "核心 · layoutSubviews"),
    DYYY_AUDIT("AWEHPTopBarCTAItemView", "核心 · showRedDot/hideCountRedDot"),
    DYYY_AUDIT("AWEIMCustomMenuComponent", "核心 · msg_showMenuForBubbleFrameInScreen/msg_showMenuForBubbleFrameInScreen"),
    DYYY_AUDIT("AWEIMModuleService", "核心 · im_forceHDRToSDR"),
    DYYY_AUDIT("AWEIMVideoBrowserCollectionViewCell", "核心 · setEnablePlayHDR"),
    DYYY_AUDIT("AWEInteractionEditTagStickerModel", "核心 · editTagInfo/setEditTagInfo"),
    DYYY_AUDIT("AWEInteractionHashtagStickerModel", "核心 · hashtagInfo/setHashtagInfo"),
    DYYY_AUDIT("AWEKnowledgeABTestSettings", "核心"),
    DYYY_AUDIT("AWELandscapeFeedEntryView", "核心 · setAlpha/didMoveToWindow"),
    DYYY_AUDIT("AWELandscapeFeedViewController", "核心 · viewDidLoad"),
    DYYY_AUDIT("AWELeftSideBarModel", "核心 · moduleModels/filterModuleItems"),
    DYYY_AUDIT("AWEListDataController", "核心 · setDataSource/dataSource"),
    DYYY_AUDIT("AWEListKitMagicCollectionView", "核心 · layoutSubviews"),
    DYYY_AUDIT("AWELiveAudienceContainerController", "核心 · initWithRoomModel/initWithRoomModel"),
    DYYY_AUDIT("AWELiveAudienceViewController", "核心 · initWithRoomModel/setRoomModel"),
    DYYY_AUDIT("AWELivePreStreamPlayer", "核心 · changeSDR2HDRWithStrategy"),
    DYYY_AUDIT("AWELoadingAndVolumeView", "核心 · layoutSubviews"),
    DYYY_AUDIT("AWELongPressPanelABSettings", "核心"),
    DYYY_AUDIT("AWELongPressPanelDataManager", "核心"),
    DYYY_AUDIT("AWELuckyCatBannerView", "核心 · initWithFrame/init"),
    DYYY_AUDIT("AWEMarkView", "核心 · layoutSubviews"),
    DYYY_AUDIT("AWEMixVideoDetailPlayListDataController", "核心 · setDataSource"),
    DYYY_AUDIT("AWEMixVideoListDataController", "核心 · setDataSource/dataSource"),
    DYYY_AUDIT("AWEMixVideoPanelMoreView", "核心 · setFrame/layoutSubviews"),
    DYYY_AUDIT("AWEMixVideoRelatedListDataController", "核心 · setDataSource/dataSource"),
    DYYY_AUDIT("AWEModernLongPressPanelUIConfig", "核心"),
    DYYY_AUDIT("AWENearbyFullScreenViewModel", "核心 · setShowSkyLight/setHaveSkyLight"),
    DYYY_AUDIT("AWENearbySkyLightCapsuleView", "核心 · layoutSubviews"),
    DYYY_AUDIT("AWENewLiveSkylightViewController", "核心 · showSkylight/updateIsSkylightShowing"),
    DYYY_AUDIT("AWENowPlayingInfoCenter", "核心 · becomePlayingPlayer/setNowPlayingInfo"),
    DYYY_AUDIT("AWEOriginalAdModel", "核心 · init/initWithDictionary"),
    DYYY_AUDIT("AWEPlayDanmakuInputContainView", "核心 · layoutSubviews"),
    DYYY_AUDIT("AWEPlayInteractionFollowPromptView", "核心 · layoutSubviews/didMoveToWindow"),
    DYYY_AUDIT("AWEPlayInteractionSpeedController", "核心 · longPressFastSpeedValue/changeSpeed"),
    DYYY_AUDIT("AWEPlayInteractionStaticFollowAnimationView", "核心 · layoutSubviews"),
    DYYY_AUDIT("AWEPlayInteractionTimestampElement", "核心 · timestampLabel"),
    DYYY_AUDIT("AWEPlayInteractionUserAvatarAdLinkController", "核心 · layoutElementView/reset"),
    DYYY_AUDIT("AWEPlayInteractionUserAvatarDecorationController", "核心 · layoutElementView/viewController_willDisplay"),
    DYYY_AUDIT("AWEPlayInteractionUserAvatarEnterStoreController", "核心 · layoutElementView/viewController_willDisplay"),
    DYYY_AUDIT("AWEPlayInteractionUserAvatarFollowPromptController", "核心 · onFollowViewClicked/onUnFollowViewClicked"),
    DYYY_AUDIT("AWEPlayInteractionUserAvatarMainBusinessController", "核心 · layoutElementView"),
    DYYY_AUDIT("AWEPlayInteractionUserAvatarOptElementElement", "核心 · layoutElementView/viewController_willDisplay"),
    DYYY_AUDIT("AWEPlayInteractionUserAvatarSendMessageController", "核心 · controllerViewDidLayout/controllerStartConfigAvatarView"),
    DYYY_AUDIT("AWEPlayInteractionUserAvatarSendMsgController", "核心 · layoutElementView/viewController_willDisplay"),
    DYYY_AUDIT("AWEPlayInteractionUserAvatarStoryController", "核心 · layoutElementView/showStory25RingView"),
    DYYY_AUDIT("AWEPlayInteractionUserAvatarView", "核心 · layoutSubviews/didMoveToWindow"),
    DYYY_AUDIT("AWEPlayVideoPlayerContext", "核心 · enableHDR/setEnableHDR"),
    DYYY_AUDIT("AWEPlayVideoViewController", "核心 · enableHDR/setEnableHDR"),
    DYYY_AUDIT("AWEPOIEntryAnchorView", "核心 · p_addViews"),
    DYYY_AUDIT("AWEProfileAvatarViewController", "核心 · viewDidAppear/dyyy_handleAvatarSaveLongPress"),
    DYYY_AUDIT("AWERelatedMusicAnchorModel", "核心 · init/initWithDictionary"),
    DYYY_AUDIT("AWEShowPlayletCommentHeaderView", "核心 · layoutSubviews"),
    DYYY_AUDIT("AWEStoryContainerCollectionView", "核心 · layoutSubviews/setFrame"),
    DYYY_AUDIT("AWETeenModeAlertView", "核心 · show"),
    DYYY_AUDIT("AWETeenModeSimpleAlertView", "核心 · show"),
    DYYY_AUDIT("AWETemplateCommonView", "核心 · layoutSubviews"),
    DYYY_AUDIT("AWETemplateStaticLabelInfoModel", "核心 · containers/setContainers"),
    DYYY_AUDIT("AWETemplateTagsCommonView", "核心 · layoutSubviews"),
    DYYY_AUDIT("AWEURLModel", "核心"),
    DYYY_AUDIT("AWEUserActionSheetView", "核心 · layoutSubviews/applyBlurEffectAndWhiteText"),
    DYYY_AUDIT("AWEUserModel", "核心 · roomID/storyRing"),
    DYYY_AUDIT("AWEUserTabListModel", "核心 · profileLandingTab"),
    DYYY_AUDIT("AWEVideoModel", "核心 · playURL/bitrateModels"),
    DYYY_AUDIT("AWEVideoPlayerConfiguration", "核心"),
    DYYY_AUDIT("AWEVideoPlayerScreenBrightnessManager", "核心 · isHDRVideo/setIsHDRVideo"),
    DYYY_AUDIT("BDByteCastEnvInfo", "核心 · isVPNActive/setIsVPNActive"),
    DYYY_AUDIT("BDByteCastMonitorManager", "核心 · netVPNStatus/setNetVPNStatus"),
    DYYY_AUDIT("BDByteCastNetUtilities", "核心 · getVPNStatus"),
    DYYY_AUDIT("BDByteCastUtils", "核心"),
    DYYY_AUDIT("BDByteScreenCastContext", "核心 · isVPNActive/setIsVPNActive"),
    DYYY_AUDIT("BDImage", "核心 · isHDR/setIsHDR"),
    DYYY_AUDIT("BDImageDecoderBVC2", "核心 · isHDR/setIsHDR"),
    DYYY_AUDIT("BDImageDecoderFactory", "核心"),
    DYYY_AUDIT("BDImageDecoderHeic", "核心 · isHDR/setIsHDR"),
    DYYY_AUDIT("BDImageDecoderImageIO", "核心 · isHDRCGImage/hdrOptionsFor"),
    DYYY_AUDIT("BDImageDecoderWebP", "核心 · isHDR/setIsHDR"),
    DYYY_AUDIT("BDMultiContentContainer_ImageContentView", "核心 · setTransform/layoutSubviews"),
    DYYY_AUDIT("BDSimPlayerBizConfig", "核心 · enableHDRBrightnessOpt/enableHDRFullModelAdaptation"),
    DYYY_AUDIT("BDXWebView", "核心 · layoutSubviews"),
    DYYY_AUDIT("CALayer", "核心 · setHidden/setContents"),
    DYYY_AUDIT("CAMetalLayer", "核心 · setWantsExtendedDynamicRangeContent/wantsExtendedDynamicRangeContent"),
    DYYY_AUDIT("CAShapeLayer", "核心 · setFillColor/setStrokeColor"),
    DYYY_AUDIT("CommentInputContainerView", "核心 · layoutSubviews"),
    DYYY_AUDIT("DUXPopover", "核心 · layoutSubviews"),
    DYYY_AUDIT("HDRMTButton", "核心 · configHDRContent"),
    DYYY_AUDIT("HDRMTImageView", "核心 · setMetalLayer/setUpEnv"),
    DYYY_AUDIT("HDRMTUIImageView", "核心 · initWithFrame/hdrEnabled"),
    DYYY_AUDIT("HTSLiveStreamPlayer", "核心 · setEnableVideoSDR2HDR/changeSDR2HDRWithStrategy"),
    DYYY_AUDIT("HTSLiveStreamQualityFragment", "核心 · setupStreamQuality"),
    DYYY_AUDIT("IESECLivePluginLayoutView", "核心 · layoutSubviews"),
    DYYY_AUDIT("IESIMVideoPlayerWrapper", "核心 · setupHDREnable"),
    DYYY_AUDIT("IESLiveAudienceHDRController", "核心"),
    DYYY_AUDIT("IESLivePlayerController", "核心 · isVideoSDR2HDRSupport/setEnableVideoSDR2HDR"),
    DYYY_AUDIT("IESLiveStackView", "核心 · setAlpha/didMoveToWindow"),
    DYYY_AUDIT("IESLiveStreamPlayerVideoAudioEffectPlugin", "核心 · setEnableVideoSDR2HDR/changeSDR2HDRWithStrategy"),
    DYYY_AUDIT("IESVideoPlayerConfig", "核心"),
    DYYY_AUDIT("LOTAnimationView", "核心 · layoutSubviews"),
    DYYY_AUDIT("MPNowPlayingInfoCenter", "核心 · setNowPlayingInfo/setPlaybackState"),
    DYYY_AUDIT("MTKView", "核心 · layoutSubviews"),
    DYYY_AUDIT("PlatformCanvasView", "核心 · layoutSubviews"),
    DYYY_AUDIT("TTAdSplashModel", "核心"),
    DYYY_AUDIT("TTMetalView", "核心 · setCenter"),
    DYYY_AUDIT("TTMetalViewNew", "核心 · setCenter"),
    DYYY_AUDIT("TTMetalViewVP", "核心 · setCenter"),
    DYYY_AUDIT("TVLManager", "核心 · shouldForbidHDR10Render/setShouldForbidHDR10Render"),
    DYYY_AUDIT("TVLPlayerItemPreferences", "核心 · forbidSDR2HDRInPreview/setForbidSDR2HDRInPreview"),
    DYYY_AUDIT("TVLSettingsManager", "核心 · enableMetalRenderHDR"),
    DYYY_AUDIT("UICollectionView", "核心 · handlePan"),
    DYYY_AUDIT("UIImageView", "核心 · setImage/setHighlightedImage"),
    DYYY_AUDIT("UILabel", "核心 · setText/setBackgroundColor"),
    DYYY_AUDIT("UIMenu", "核心"),
    DYYY_AUDIT("UITextField", "核心 · willMoveToWindow/becomeFirstResponder"),
    DYYY_AUDIT("UITextView", "核心 · willMoveToWindow/becomeFirstResponder"),
    DYYY_AUDIT("UIView", "核心 · setHidden/didAddSubview"),
    DYYY_AUDIT("UIWindow", "核心 · initWithFrame/handleDoubleFingerLongPressGesture"),

};

@interface DYYYClassRegistry ()
// 点号名 / mangled 名双查（Swift 类在运行时是 mangled 形式）。
// 内部使用，不对外暴露。
+ (Class)resolveClassByName:(NSString *)name;
@end

@implementation DYYYClassRegistry

+ (DYYYClassAuditStatus)auditClass:(NSString *)className
                   outResolvedName:(NSString * _Nullable * _Nullable)outResolvedName {
    Class cls = className.length > 0 ? objc_getClass(className.UTF8String) : NULL;
    if (outResolvedName) {
        *outResolvedName = cls ? className : nil;
    }
    return cls ? DYYYClassAuditStatusOK : DYYYClassAuditStatusMissing;
}

+ (Class)resolveSwiftClassDotName:(const char *)dotName mangledName:(const char *)mangledName {
    Class cls = dotName ? objc_getClass(dotName) : NULL;
    if (!cls && mangledName) {
        cls = objc_getClass(mangledName);
    }
    return cls;
}

+ (NSUInteger)auditEntryCount {
    return sizeof(kDYYYAuditTable) / sizeof(kDYYYAuditTable[0]);
}

#pragma mark - Hook 生效数自检

// Logos 把每个 hook 方法重命名为：
//   _logos_method$_ungrouped$AWEFeedTableView$setFrame$
// 类在、但方法签名变了，hook 会编译通过而运行时不生效。
// 扫一遍运行时全部方法名，统计以 _logos_method$ 开头的数量，
// 与编译期写入的期望值比对——这是最真实的健康度指标。
+ (NSUInteger)countInstalledLogosMethods {
    unsigned int classCount = 0;
    Class *classes = objc_copyClassList(&classCount);
    if (!classes) return 0;
    NSUInteger total = 0;
    for (unsigned int i = 0; i < classCount; i++) {
        Class cls = classes[i];
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(cls, &methodCount);
        if (!methods) continue;
        for (unsigned int j = 0; j < methodCount; j++) {
            const char *selName = sel_getName(method_getName(methods[j]));
            if (selName && strncmp(selName, "_logos_method$", 14) == 0) total++;
        }
        free(methods);
    }
    free(classes);
    return total;
}

// 期望值由 DYYY_HOOK_EXPECTED_COUNT 在 %ctor 里写入（= 编译期 hook 方法总数）。
static NSUInteger gDYYYExpectedHookCount = 0;
+ (void)setExpectedHookCount:(NSUInteger)count {
    gDYYYExpectedHookCount = count;
}

+ (NSString *)hookHealthText {
    NSUInteger actual = [self countInstalledLogosMethods];
    if (gDYYYExpectedHookCount == 0) {
        return [NSString stringWithFormat:@"hook 生效数: %lu（未设置期望值，跳过比对）\n", (unsigned long)actual];
    }
    NSInteger diff = (NSInteger)actual - (NSInteger)gDYYYExpectedHookCount;
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"hook 生效数: %lu / 期望 %lu", (unsigned long)actual, (unsigned long)gDYYYExpectedHookCount];
    if (diff == 0) {
        [out appendString:@"  ✅ 全部生效\n"];
    } else {
        [out appendFormat:@"  ⚠️ 差 %ld 个（类存在但方法签名可能已变）\n", (long)diff];
    }
    return out;
}

#pragma mark - 运行时类清单（适配新版用）

// 抖音改版时，新类名靠猜。这里把运行时全部类名按抖音前缀过滤后输出，
// 我拿到后与旧版清单对比，直接给出「缺失 → 疑似新名」的候选。
+ (NSString *)runtimeClassListText {
    static NSString *const kPrefixes[] = { @"AWE", @"IES", @"HTS", @"AFD", @"TT", @"BD", @"DUX", @"ALM" };
    static const NSUInteger kPrefixCount = sizeof(kPrefixes) / sizeof(kPrefixes[0]);

    unsigned int classCount = 0;
    Class *classes = objc_copyClassList(&classCount);
    if (!classes) return @"(无法获取类列表)\n";
    NSMutableArray<NSString *> *names = [NSMutableArray arrayWithCapacity:classCount];
    for (unsigned int i = 0; i < classCount; i++) {
        const char *name = class_getName(classes[i]);
        if (!name) continue;
        for (NSUInteger p = 0; p < kPrefixCount; p++) {
            if (strncmp(name, kPrefixes[p].UTF8String, strlen(kPrefixes[p].UTF8String)) == 0) {
                [names addObject:[NSString stringWithUTF8String:name]];
                break;
            }
        }
    }
    free(classes);
    [names sortUsingSelector:@selector(compare:)];

    NSMutableString *out = [NSMutableString string];
    NSString *appVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown";
    [out appendFormat:@"# DYYY 运行时类清单\n# 抖音版本: %@\n# 过滤前缀: AWE/IES/HTS/AFD/TT/BD/DUX/ALM\n# 总数: %lu\n\n",
                      appVersion, (unsigned long)names.count];
    for (NSString *n in names) [out appendFormat:@"%@\n", n];
    return out;
}

#pragma mark - 目标类方法清单（方法改名时用）

// 对审计表里的每个类，dump 其全部实例方法名。
// 抖音改了方法名（类名不变）时，靠这份清单能直接看出少了哪个 selector。
+ (NSString *)targetMethodsText {
    NSMutableString *out = [NSMutableString string];
    NSUInteger total = [self auditEntryCount];
    for (NSUInteger index = 0; index < total; index++) {
        const DYYYAuditEntry *entry = &kDYYYAuditTable[index];
        NSString *name = [NSString stringWithUTF8String:entry->primary];
        Class cls = [self resolveClassByName:name];
        if (!cls) {
            [out appendFormat:@"\n## %@  (未找到)\n", name];
            continue;
        }
        [out appendFormat:@"\n## %@\n", name];
        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(cls, &methodCount);
        if (!methods) { [out appendString:@"(无方法)\n"]; continue; }
        NSMutableArray<NSString *> *sels = [NSMutableArray arrayWithCapacity:methodCount];
        for (unsigned int j = 0; j < methodCount; j++) {
            const char *selName = sel_getName(method_getName(methods[j]));
            if (!selName) continue;
            NSString *s = [NSString stringWithUTF8String:selName];
            // 跳过 Logos 注入的方法，只看抖音原生的
            if ([s hasPrefix:@"_logos_"]) continue;
            [sels addObject:s];
        }
        free(methods);
        [sels sortUsingSelector:@selector(compare:)];
        for (NSString *s in sels) [out appendFormat:@"  - %@\n", s];
    }
    return out;
}

// 点号名 / mangled 名双查（Swift 类在运行时是 mangled 形式）
+ (Class)resolveClassByName:(NSString *)name {
    Class cls = NSClassFromString(name);
    if (cls) return cls;
    NSString *mangled = [name stringByReplacingOccurrencesOfString:@"." withString:@"_"];
    return NSClassFromString(mangled);
}

+ (NSInteger)runStartupAudit {
    static dispatch_once_t auditOnce;
    __block NSInteger missingCount = 0;
    dispatch_once(&auditOnce, ^{
      NSMutableArray<NSString *> *missing = [NSMutableArray array];
      const NSUInteger entryCount = [self auditEntryCount];
      for (NSUInteger index = 0; index < entryCount; index++) {
          const DYYYAuditEntry *entry = &kDYYYAuditTable[index];
          NSString *name = [NSString stringWithUTF8String:entry->primary];
          NSString *resolvedName = nil;
          if ([self auditClass:name outResolvedName:&resolvedName] == DYYYClassAuditStatusMissing) {
              [missing addObject:name];
          }
      }
      missingCount = missing.count;
      NSString *appVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"unknown";
      if (missing.count == 0) {
          NSLog(@"[DYYY][audit] 抖音 %@ 关键类自检通过（%lu 项全部命中）", appVersion, (unsigned long)entryCount);
      } else {
          NSLog(@"[DYYY][audit] 抖音 %@ 关键类自检：缺失 %ld/%lu 项，对应功能可能失效：%@",
                appVersion, (long)missing.count, (unsigned long)entryCount,
                [missing componentsJoinedByString:@", "]);
      }
    });
    return missingCount;
}

+ (NSString *)auditReportText {
    // 每次调用都重新探测：类可能在启动后才完成注册，缓存会固化误报。
    NSMutableString *report = [NSMutableString string];
      NSString *appVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"未知";
      NSString *tweakVersion = @"2.2-9";
      NSDateFormatter *timeFormatter = [[NSDateFormatter alloc] init];
      timeFormatter.dateFormat = @"yyyy-MM-dd HH:mm:ss";
      [report appendFormat:@"DYYY 自检报告\n抖音版本: %@\n插件版本: %@\n检测时间: %@\n\n",
                          appVersion, tweakVersion, [timeFormatter stringFromDate:[NSDate date]]];

      NSMutableArray<NSString *> *missingFeatures = [NSMutableArray array];
      NSUInteger okCount = 0;
      NSUInteger total = [self auditEntryCount];
      for (NSUInteger index = 0; index < total; index++) {
          const DYYYAuditEntry *entry = &kDYYYAuditTable[index];
          NSString *name = [NSString stringWithUTF8String:entry->primary];
          if ([self auditClass:name outResolvedName:nil] == DYYYClassAuditStatusOK) {
              okCount++;
          } else if (entry->feature) {
              NSString *featureName = [NSString stringWithUTF8String:entry->feature];
              NSString *line = [NSString stringWithFormat:@"· %@（类 %@ 未找到）", featureName, name];
              if (![missingFeatures containsObject:line]) {
                  [missingFeatures addObject:line];
              }
          }
      }

      [report appendFormat:@"关键类命中: %lu/%lu\n", (unsigned long)okCount, (unsigned long)total];
      if (missingFeatures.count == 0) {
          [report appendString:@"\n✅ 全部关键类在线，未发现因抖音改版失效的功能。\n"];
      } else {
          [report appendString:@"\n⚠️ 以下功能可能失效：\n"];
          for (NSString *line in missingFeatures) {
              [report appendFormat:@"%@\n", line];
          }
          [report appendString:@"\n如功能异常与上表无关，请把本页下方运行日志一并发给作者。\n"];
      }
    return report;
}

@end
