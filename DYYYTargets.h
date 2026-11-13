//
//  DYYYTargets.h
//  抖音 hook 目标类的【清单与常量表】。
//
//  ⚠️ 重要：本文件的宏不能用于 %hook / %init
//
//  原因（#80 实测教训）：
//    Logos 的处理顺序是：
//      .xm → logos.pl 解析 %hook 语法 → cpp 宏展开 → clang
//    logos.pl 在宏展开【之前】就把 %hook 后的标识符当类名处理，
//    生成 objc_getClass("DYYY_T_XXX") —— 宏在字符串里不会展开，
//    运行时查到 nil，全部 hook 静默失效（实测 hook 生效数 0/739）。
//
//  所以：%hook 必须写真实类名。
//
//  那这份文件还有什么用？
//  1. 适配新版抖音时当【字典】查：全部 306 个目标类集中一处，
//     配合同目录的 DYYYClassRegistry.m 审计表（含被 hook 的方法名）。
//  2. 未来若要做改名保护，只能走 %group + %init 动态绑定：
//       %group XxxGroup
//       %hook AWEPlaceholderName        ← 占位名，logos.pl 认
//       %end
//       %end
//       // %ctor: %init(XxxGroup, AWEPlaceholderName = DYYYTargetClass(@"..."));
//     那时本文件的宏可作为「类名字符串」来源（配合 DYYYTargetClass 帮助函数）。
//  3. CI 脚本可读本文件做版本兼容扫描（对比运行时二进制的类名）。
//
//  维护：新增 hook 目标时在这里补一条（保持清单完整）。
//

#ifndef DYYY_TARGETS_H
#define DYYY_TARGETS_H

// ---- 统计：共 306 个 hook 目标 ----
// ---- 用途：类名清单 / 适配对照表 / CI 扫描源。不用于 %hook。----



// ---- 统计：共 306 个 hook 目标 ----


// ===== Comment（4 项）=====
#define DYYY_T_AWECOMMENT_CONTAINER_VIEW_CONTROLLER              AWECommentContainerViewController
#define DYYY_T_AWECOMMENT_GUIDE_LUNA_ANCHOR_VIEW                 AWECommentGuideLunaAnchorView
#define DYYY_T_AWECOMMENT_IMAGE_MODEL                            AWECommentImageModel
#define DYYY_T_AWECOMMENT_MEDIA_DOWNLOAD_CONFIG_LIVE_PHOTO       AWECommentMediaDownloadConfigLivePhoto

// ===== Feed（18 项）=====
#define DYYY_T_AWEFEED_CHANNEL_MANAGER                           AWEFeedChannelManager
#define DYYY_T_AWEFEED_COMMENT_CONFIG_MODEL                      AWEFeedCommentConfigModel
#define DYYY_T_AWEFEED_LIVE_MARK_VIEW                            AWEFeedLiveMarkView
#define DYYY_T_AWEFEED_LIVE_TAB_REVISIT_CONTROL_VIEW             AWEFeedLiveTabRevisitControlView
#define DYYY_T_AWEFEED_LIVE_TAB_TOP_SELECTION_VIEW               AWEFeedLiveTabTopSelectionView
#define DYYY_T_AWEFEED_MULTI_TAB_SELECTED_CONTAINER_VIEW         AWEFeedMultiTabSelectedContainerView
#define DYYY_T_AWEFEED_PROGRESS_SLIDER                           AWEFeedProgressSlider
#define DYYY_T_AWEFEED_ROOT_VIEW_CONTROLLER                      AWEFeedRootViewController
#define DYYY_T_AWEFEED_TAB_JUMP_GUIDE_VIEW                       AWEFeedTabJumpGuideView
#define DYYY_T_AWEFEED_TOP_BAR_CONTAINER                         AWEFeedTopBarContainer
#define DYYY_T_AWEFEED_UNFOLLOW_FAMILIAR_FOLLOW_AND_DISLIKE_VIEW AWEFeedUnfollowFamiliarFollowAndDislikeView
#define DYYY_T_AWEFEED_VIEW_CELL                                 AWEFeedViewCell
#define DYYY_T_AWEHOT_SEARCH_INNER_BOTTOM_VIEW                   AWEHotSearchInnerBottomView
#define DYYY_T_AWEHOT_SPOT_BLUR_VIEW                             AWEHotSpotBlurView
#define DYYY_T_AWEHOT_SPOT_LIST_MODEL                            AWEHotSpotListModel
#define DYYY_T_AWEHPCHANNEL_INVISIBLE_WATER_MARK_MODEL           AWEHPChannelInvisibleWaterMarkModel
#define DYYY_T_AWESEARCH_ANCHOR_LIST_MODEL                       AWESearchAnchorListModel
#define DYYY_T_AWESEARCH_ENTRANCE_VIEW                           AWESearchEntranceView

// ===== Fullscreen（16 项）=====
#define DYYY_T_AWEDPLAYER_PROGRESS_CONTAINER_VIEW                AWEDPlayerProgressContainerView
#define DYYY_T_AWEFEED_DATA_SAFE_TABLE_VIEW                      AWEFeedDataSafeTableView
#define DYYY_T_AWEFEED_TABLE_VIEW_CELL                           AWEFeedTableViewCell
#define DYYY_T_AWEFEED_TABLE_VIEW_CONTROLLER                     AWEFeedTableViewController
#define DYYY_T_AWEPLAY_INTERACTION_COMMENT_PANEL_CONTROLLER      AWEPlayInteractionCommentPanelController
#define DYYY_T_AWEPLAY_INTERACTION_DESCRIPTION_LABEL             AWEPlayInteractionDescriptionLabel
#define DYYY_T_AWEPLAY_INTERACTION_DESCRIPTION_SCROLL_VIEW       AWEPlayInteractionDescriptionScrollView
#define DYYY_T_AWEPLAY_INTERACTION_LISTEN_FEED_VIEW              AWEPlayInteractionListenFeedView
#define DYYY_T_AWEPLAY_INTERACTION_LIVE_EXTEND_GUIDE_VIEW        AWEPlayInteractionLiveExtendGuideView
#define DYYY_T_AWEPLAY_INTERACTION_PROGRESS_CONTAINER_VIEW       AWEPlayInteractionProgressContainerView
#define DYYY_T_AWEPLAY_INTERACTION_PROGRESS_CONTROLLER           AWEPlayInteractionProgressController
#define DYYY_T_AWEPLAY_INTERACTION_SEARCH_ANCHOR_VIEW            AWEPlayInteractionSearchAnchorView
#define DYYY_T_AWEPLAY_INTERACTION_STRONGIFY_SHARE_CONTENT_VIEW  AWEPlayInteractionStrongifyShareContentView
#define DYYY_T_AWEPLAY_INTERACTION_TEMPLATE_BUTTON               AWEPlayInteractionTemplateButton
#define DYYY_T_AWEPLAY_INTERACTION_USER_AVATAR_ELEMENT           AWEPlayInteractionUserAvatarElement
#define DYYY_T_AWEPLAY_INTERACTION_USER_AVATAR_FOLLOW_CONTROLLER AWEPlayInteractionUserAvatarFollowController

// ===== Global（5 项）=====
#define DYYY_T_AWEBASE_LIST_SECTION_BACKGROUND_VIEW              AWEBaseListSectionBackgroundView
#define DYYY_T_AWEBASE_LIST_VIEW_CONTROLLER                      AWEBaseListViewController
#define DYYY_T_UIBUTTON                                          UIButton
#define DYYY_T_UIVIEW_CONTROLLER                                 UIViewController
#define DYYY_T_YYLABEL                                           YYLabel

// ===== Live（32 项）=====
#define DYYY_T_AWEINNER_NOTIFICATION_WINDOW                      AWEInnerNotificationWindow
#define DYYY_T_AWELIVE_AUTO_ENTER_STYLE_AVIEW                    AWELiveAutoEnterStyleAView
#define DYYY_T_AWELIVE_FEED_LABEL_TAG_VIEW                       AWELiveFeedLabelTagView
#define DYYY_T_AWELIVE_FEED_STATUS_LABEL                         AWELiveFeedStatusLabel
#define DYYY_T_AWELIVE_FLOW_ALERT_VIEW                           AWELiveFlowAlertView
#define DYYY_T_AWELIVE_GUIDE_ELEMENT                             AWELiveGuideElement
#define DYYY_T_AWELIVE_SKYLIGHT_VIEW_MODEL                       AWELiveSkylightViewModel
#define DYYY_T_AWELIVE_STATUS_INDICATOR_VIEW                     AWELiveStatusIndicatorView
#define DYYY_T_HTSLIVE_DIGG_VIEW                                 HTSLiveDiggView
#define DYYY_T_HTSLIVE_STREAM_PCDN_MANAGER                       HTSLiveStreamPcdnManager
#define DYYY_T_IESLIVE_ACTIVITY_BANNNER_VIEW                     IESLiveActivityBannnerView
#define DYYY_T_IESLIVE_BOTTOM_RIGHT_CARD_VIEW                    IESLiveBottomRightCardView
#define DYYY_T_IESLIVE_BUTTON                                    IESLiveButton
#define DYYY_T_IESLIVE_CONFIGURABLE_SHORT_TOUCH_ENTRANCE_VIEW    IESLiveConfigurableShortTouchEntranceView
#define DYYY_T_IESLIVE_DANMAKU_SUPREME_VIEW                      IESLiveDanmakuSupremeView
#define DYYY_T_IESLIVE_DANMAKU_VARIOUS_VIEW                      IESLiveDanmakuVariousView
#define DYYY_T_IESLIVE_DYNAMIC_RANK_LIST_ENTRANCE_VIEW           IESLiveDynamicRankListEntranceView
#define DYYY_T_IESLIVE_DYNAMIC_USER_ENTER_VIEW                   IESLiveDynamicUserEnterView
#define DYYY_T_IESLIVE_FEED_DRAWER_ENTRANCE_VIEW                 IESLiveFeedDrawerEntranceView
#define DYYY_T_IESLIVE_GAME_CPEXPLAIN_CARD_CONTAINER_IMPL        IESLiveGameCPExplainCardContainerImpl
#define DYYY_T_IESLIVE_GROUP_LIVE_COMPONENT_VIEW                 IESLiveGroupLiveComponentView
#define DYYY_T_IESLIVE_HOT_MESSAGE_VIEW                          IESLiveHotMessageView
#define DYYY_T_IESLIVE_KTVSONG_INDICATOR_VIEW                    IESLiveKTVSongIndicatorView
#define DYYY_T_IESLIVE_LAUNCH_TASK_PCDN                          IESLiveLaunchTaskPcdn
#define DYYY_T_IESLIVE_LAYOUT_PLACEHOLDER_VIEW                   IESLiveLayoutPlaceholderView
#define DYYY_T_IESLIVE_LOTTERY_ANIMATION_VIEW_NEW                IESLiveLotteryAnimationViewNew
#define DYYY_T_IESLIVE_MATRIX_ENTRANCE_VIEW                      IESLiveMatrixEntranceView
#define DYYY_T_IESLIVE_PRE_ANNOUNCEMENT_PANEL_VIEW_NEW           IESLivePreAnnouncementPanelViewNew
#define DYYY_T_IESLIVE_RED_ENVELOPE_ANI_LYNX_VIEW                IESLiveRedEnvelopeAniLynxView
#define DYYY_T_IESLIVE_SHORT_TOUCH_ACTION_VIEW                   IESLiveShortTouchActionView
#define DYYY_T_IESLIVE_STICKER_VIEW                              IESLiveStickerView
#define DYYY_T_IESLIVE_USER_SEQLIST_FRAGMENT                     IESLiveUserSeqlistFragment

// ===== Media（14 项）=====
#define DYYY_T_AWEIMCELL_LIVE_STATUS_CONTAINER_VIEW              AWEIMCellLiveStatusContainerView
#define DYYY_T_AWEIMEMOTICON_PREVIEW_V2                          AWEIMEmoticonPreviewV2
#define DYYY_T_AWEIMFANS_GROUP_TOP_DYNAMIC_DOMAIN_TEMPLATE_VIEW  AWEIMFansGroupTopDynamicDomainTemplateView
#define DYYY_T_AWEIMFEED_BOTTOM_QUICK_EMOJI_INPUT_BAR            AWEIMFeedBottomQuickEmojiInputBar
#define DYYY_T_AWEIMFEED_VIDEO_QUICK_REPLAY_INPUT_VIEW_CONTROLLER AWEIMFeedVideoQuickReplayInputViewController
#define DYYY_T_AWEIMINPUT_ACTION_BAR_INTERACTOR                  AWEIMInputActionBarInteractor
#define DYYY_T_AWEIMMESSAGE_TAB_OPT_PUSH_BANNER_VIEW             AWEIMMessageTabOptPushBannerView
#define DYYY_T_AWEIMMESSAGE_TAB_SIDE_BAR_VIEW                    AWEIMMessageTabSideBarView
#define DYYY_T_AWEIMPHOTO_PICKER_FUNCTION_MODEL                  AWEIMPhotoPickerFunctionModel
#define DYYY_T_AWEIMSKYLIGHT_LIST_VIEW                           AWEIMSkylightListView
#define DYYY_T_AWEMUSIC_COVER_BUTTON                             AWEMusicCoverButton
#define DYYY_T_AWEMUSIC_EXTRA_MODEL                              AWEMusicExtraModel
#define DYYY_T_AWESTORY_PROGRESS_SLIDE_VIEW                      AWEStoryProgressSlideView
#define DYYY_T_AWEVIDEO_TYPE_TAG_VIEW                            AWEVideoTypeTagView

// ===== Profile（7 项）=====
#define DYYY_T_AWEPROFILE_AVATAR_FUNCTION_MANAGER                AWEProfileAvatarFunctionManager
#define DYYY_T_AWEPROFILE_MENTION_LABEL                          AWEProfileMentionLabel
#define DYYY_T_AWEPROFILE_MIX_ITEM_COLLECTION_VIEW_CELL          AWEProfileMixItemCollectionViewCell
#define DYYY_T_AWEPROFILE_NAVIGATION_BUTTON                      AWEProfileNavigationButton
#define DYYY_T_AWEPROFILE_PUBLISH_GUIDE_COLLECTION_VIEW_CELL     AWEProfilePublishGuideCollectionViewCell
#define DYYY_T_AWEPROFILE_RICH_EMPTY_VIEW                        AWEProfileRichEmptyView
#define DYYY_T_AWEPROFILE_TASK_CARD_STYLE_LIST_ITEM_CELL         AWEProfileTaskCardStyleListItemCell

// ===== Settings（2 项）=====
#define DYYY_T_AWELEFT_SIDE_BAR_ADD_CHILD_TRANSITION_OBJECT      AWELeftSideBarAddChildTransitionObject
#define DYYY_T_AWELEFT_SIDE_BAR_ENTRANCE_VIEW                    AWELeftSideBarEntranceView

// ===== TabBar（8 项）=====
#define DYYY_T_AWENORMAL_MODE_TAB_BAR_BADGE_CONTAINER_VIEW       AWENormalModeTabBarBadgeContainerView
#define DYYY_T_AWENORMAL_MODE_TAB_BAR_CONTROLLER                 AWENormalModeTabBarController
#define DYYY_T_AWENORMAL_MODE_TAB_BAR_FEED_VIEW                  AWENormalModeTabBarFeedView
#define DYYY_T_AWENORMAL_MODE_TAB_BAR_GENERAL_BUTTON             AWENormalModeTabBarGeneralButton
#define DYYY_T_AWENORMAL_MODE_TAB_BAR_GENERAL_PLUS_BUTTON        AWENormalModeTabBarGeneralPlusButton
#define DYYY_T_AWENORMAL_MODE_TAB_BAR_PLUS_BUTTON                AWENormalModeTabBarPlusButton
#define DYYY_T_AWENORMAL_MODE_TAB_BAR_TEXT_VIEW                  AWENormalModeTabBarTextView
#define DYYY_T_AWETAB_BAR_ELEMENT_CONTAINER_VIEW                 AWETabBarElementContainerView

// ===== 核心（DYYY.xm）（200 项）=====
#define DYYY_T_IESLIVE_REVENUE_IMPL32_IESLIVE_SWIFT_DYNAMIC_USER_ENTER_VIEW _TtC18IESLiveRevenueImpl32IESLiveSwiftDynamicUserEnterView
#define DYYY_T_IESLIVE_REVENUE_IMPL34_IESLIVE_DYNAMIC_RANK_LIST_ENTRANCE_VIEW _TtC18IESLiveRevenueImpl34IESLiveDynamicRankListEntranceView
#define DYYY_T_IESLIVE_REVENUE_IMPL35_IESLIVE_SWIFT_VIDEO_LAYER_USER_ENTER_VIEW _TtC18IESLiveRevenueImpl35IESLiveSwiftVideoLayerUserEnterView
#define DYYY_T_AWEINCENTIVE_SWIFT_IMPL20_PENDANT_CONTAINER_VIEW  _TtC21AWEIncentiveSwiftImpl20PendantContainerView
#define DYYY_T_AWECOMMENT_LONG_PRESS_PANEL_SWIFT_IMPL32_COMMENT_LONG_PRESS_PANEL_COPY_ELEMENT _TtC33AWECommentLongPressPanelSwiftImpl32CommentLongPressPanelCopyElement
#define DYYY_T_AWECOMMENT_LONG_PRESS_PANEL_SWIFT_IMPL37_COMMENT_LONG_PRESS_PANEL_SAVE_IMAGE_ELEMENT _TtC33AWECommentLongPressPanelSwiftImpl37CommentLongPressPanelSaveImageElement
#define DYYY_T_TT_CV28_AWECOMMENT_PANEL_LIST_SWIFT_IMPL6_NEWAPI27_COMMENT_CELL_STICKER_COMPONENT _TtCV28AWECommentPanelListSwiftImpl6NEWAPI27CommentCellStickerComponent
#define DYYY_T_ACCSTICKER_CONTAINER_VIEW                         ACCStickerContainerView
#define DYYY_T_AFDCANCEL_MUTE_AWEME_VIEW                         AFDCancelMuteAwemeView
#define DYYY_T_AFDFAST_SPEED_VIEW                                AFDFastSpeedView
#define DYYY_T_AFDFRIEND_RECOMMEND_TAG_VIEW                      AFDFriendRecommendTagView
#define DYYY_T_AFDNEW_FAST_REPLY_VIEW                            AFDNewFastReplyView
#define DYYY_T_AFDPRIVACY_HALF_SCREEN_VIEW_CONTROLLER            AFDPrivacyHalfScreenViewController
#define DYYY_T_AFDPURE_MODE_PAGE_CONTAINER_VIEW_CONTROLLER       AFDPureModePageContainerViewController
#define DYYY_T_AFDPURE_MODE_PAGE_LIST_VIEW_CONTROLLER            AFDPureModePageListViewController
#define DYYY_T_AFDPURE_MODE_PAGE_TAP_CONTROLLER                  AFDPureModePageTapController
#define DYYY_T_AFDRECOMMEND_TO_FRIEND_ENTRANCE_LABEL             AFDRecommendToFriendEntranceLabel
#define DYYY_T_AFDVIEWED_BOTTOM_VIEW                             AFDViewedBottomView
#define DYYY_T_ALMOWN_PLAYER_WRAPPER                             ALMOwnPlayerWrapper
#define DYYY_T_ALMSYS_PLAYER_WRAPPER                             ALMSysPlayerWrapper
#define DYYY_T_ALMVIDEO_PLAYER_CONFIG                            ALMVideoPlayerConfig
#define DYYY_T_APP_DELEGATE                                      AppDelegate
#define DYYY_T_AVPLAYER                                          AVPlayer
#define DYYY_T_AVPLAYER_ITEM                                     AVPlayerItem
#define DYYY_T_AVPLAYER_LAYER                                    AVPlayerLayer
#define DYYY_T_AWEAD_AVATAR_VIEW                                 AWEAdAvatarView
#define DYYY_T_AWEAWEME_BACKGROUND_PLAY_MODULE                   AWEAwemeBackgroundPlayModule
#define DYYY_T_AWEAWEME_DETAIL_CONTAINER_PLAY_CONTROL_CONFIG     AWEAwemeDetailContainerPlayControlConfig
#define DYYY_T_AWEAWEME_DETAIL_TABLE_VIEW_CONTROLLER             AWEAwemeDetailTableViewController
#define DYYY_T_AWEAWEME_HOT_SPOT_TABLE_VIEW_CONTROLLER           AWEAwemeHotSpotTableViewController
#define DYYY_T_AWEAWEME_MODEL                                    AWEAwemeModel
#define DYYY_T_AWEAWEME_PLAY_VIDEO_VIEW_CONTROLLER               AWEAwemePlayVideoViewController
#define DYYY_T_AWEAWEME_STATUS_MODEL                             AWEAwemeStatusModel
#define DYYY_T_AWEAWESOME_SPLASH_LIVE_CELL_ACCESSORY_VIEW        AWEAwesomeSplashLiveCellAccessoryView
#define DYYY_T_AWEBDSIM_PLAYER_BIZ_CONFIG                        AWEBDSimPlayerBizConfig
#define DYYY_T_AWECODE_GEN_STORY_RING_INFO_MODEL                 AWECodeGenStoryRingInfoModel
#define DYYY_T_AWECOMMENT_INPUT_BACKGROUND_VIEW                  AWECommentInputBackgroundView
#define DYYY_T_AWECOMMENT_PANEL_CONTAINER_SWIFT_IMPL_COMMENT_CONTAINER_INNER_VIEW_CONTROLLER AWECommentPanelContainerSwiftImpl_CommentContainerInnerViewController
#define DYYY_T_AWECOMMENT_PANEL_CONTAINER_SWIFT_IMPL_COMMENT_PANEL_VIEW_CONTROLLER AWECommentPanelContainerSwiftImpl_CommentPanelViewController
#define DYYY_T_AWECOMMENT_PANEL_HEADER_SWIFT_IMPL_COMMENT_HEADER_GENERAL_VIEW AWECommentPanelHeaderSwiftImpl_CommentHeaderGeneralView
#define DYYY_T_AWECOMMENT_PANEL_HEADER_SWIFT_IMPL_COMMENT_HEADER_GOODS_VIEW AWECommentPanelHeaderSwiftImpl_CommentHeaderGoodsView
#define DYYY_T_AWECOMMENT_PANEL_HEADER_SWIFT_IMPL_COMMENT_HEADER_TEMPLATE_ANCHOR_VIEW AWECommentPanelHeaderSwiftImpl_CommentHeaderTemplateAnchorView
#define DYYY_T_AWECOMMENT_PANEL_LIST_SWIFT_IMPL_COMMENT_BOTTOM_TIPS_CONTAINER_VIEW_CONTROLLER AWECommentPanelListSwiftImpl_CommentBottomTipsContainerViewController
#define DYYY_T_AWECOMMENT_SWIFT_BIZ_UI_COMMENT_INTERACTION_BASE_LABEL AWECommentSwiftBizUI_CommentInteractionBaseLabel
#define DYYY_T_AWECONCERN_CELL_LAST_VIEW                         AWEConcernCellLastView
#define DYYY_T_AWECORRELATION_ITEM_TAG                           AWECorrelationItemTag
#define DYYY_T_AWEDANMAKU_CONTENT_LABEL                          AWEDanmakuContentLabel
#define DYYY_T_AWEDATE_TIME_FORMATTER                            AWEDateTimeFormatter
#define DYYY_T_AWEDISCOVER_FEED_ENTRANCE_VIEW                    AWEDiscoverFeedEntranceView
#define DYYY_T_AWEDPLAYER_BRIGHTNESS_CONTAINER                   AWEDPlayerBrightnessContainer
#define DYYY_T_AWEDPLAYER_FEED_PLAYER_VIEW_CONTROLLER            AWEDPlayerFeedPlayerViewController
#define DYYY_T_AWEDPLAYER_VIDEO_DISPLAY_OPT_STATE                AWEDPlayerVideoDisplayOptState
#define DYYY_T_AWEDPLAYER_VIDEO_MODEL                            AWEDPlayerVideoModel
#define DYYY_T_AWEDPLAYER_VIEW_CONTROLLER_MERGE                  AWEDPlayerViewController_Merge
#define DYYY_T_AWEDPROGRESS_CORE_CONTAINER                       AWEDProgressCoreContainer
#define DYYY_T_AWEELEMENT_STACK_VIEW                             AWEElementStackView
#define DYYY_T_AWEFAMILIAR_NAV_VIEW                              AWEFamiliarNavView
#define DYYY_T_AWEFAMILIAR_SKYLIGHT_BUBBLE_VIEW                  AWEFamiliarSkylightBubbleView
#define DYYY_T_AWEFEED_ABSETTINGS                                AWEFeedABSettings
#define DYYY_T_AWEFEED_ABTEST_SERVICE_OBJC                       AWEFeedABTestServiceObjc
#define DYYY_T_AWEFEED_BACKGROUND_PLAY_MANAGER                   AWEFeedBackgroundPlayManager
#define DYYY_T_AWEFEED_CONTAINER_VIEW_CONTROLLER                 AWEFeedContainerViewController
#define DYYY_T_AWEFEED_IPHONE_AUTO_PLAY_MANAGER                  AWEFeedIPhoneAutoPlayManager
#define DYYY_T_AWEFEED_MODULE_SERVICE                            AWEFeedModuleService
#define DYYY_T_AWEFEED_TABLE_VIEW                                AWEFeedTableView
#define DYYY_T_AWEFEED_VIDEO_BUTTON                              AWEFeedVideoButton
#define DYYY_T_AWEFULL_PAGE_FEED_CONTAINER_VIEW_CONTROLLER       AWEFullPageFeedContainerViewController
#define DYYY_T_AWEGENERAL_SEARCH_MODEL                           AWEGeneralSearchModel
#define DYYY_T_AWEGRADIENT_VIEW                                  AWEGradientView
#define DYYY_T_AWEHOT_LIST_DATA_CONTROLLER                       AWEHotListDataController
#define DYYY_T_AWEHPDISCOVER_FEED_ENTRANCE_VIEW                  AWEHPDiscoverFeedEntranceView
#define DYYY_T_AWEHPSEARCH_BUBBLE_ENTRANCE_VIEW                  AWEHPSearchBubbleEntranceView
#define DYYY_T_AWEHPTOP_BAR_CTAITEM_VIEW                         AWEHPTopBarCTAItemView
#define DYYY_T_AWEHPTOP_TAB_ITEM_BADGE_CONTENT_VIEW              AWEHPTopTabItemBadgeContentView
#define DYYY_T_AWEHPTOP_TAB_ITEM_TEXT_CONTENT_VIEW               AWEHPTopTabItemTextContentView
#define DYYY_T_AWEIMCUSTOM_MENU_COMPONENT                        AWEIMCustomMenuComponent
#define DYYY_T_AWEIMMODULE_SERVICE                               AWEIMModuleService
#define DYYY_T_AWEIMVIDEO_BROWSER_COLLECTION_VIEW_CELL           AWEIMVideoBrowserCollectionViewCell
#define DYYY_T_AWEINTERACTION_EDIT_TAG_STICKER_MODEL             AWEInteractionEditTagStickerModel
#define DYYY_T_AWEINTERACTION_HASHTAG_STICKER_MODEL              AWEInteractionHashtagStickerModel
#define DYYY_T_AWEKNOWLEDGE_ABTEST_SETTINGS                      AWEKnowledgeABTestSettings
#define DYYY_T_AWELANDSCAPE_FEED_ENTRY_VIEW                      AWELandscapeFeedEntryView
#define DYYY_T_AWELANDSCAPE_FEED_VIEW_CONTROLLER                 AWELandscapeFeedViewController
#define DYYY_T_AWELEFT_SIDE_BAR_MODEL                            AWELeftSideBarModel
#define DYYY_T_AWELIST_DATA_CONTROLLER                           AWEListDataController
#define DYYY_T_AWELIST_KIT_MAGIC_COLLECTION_VIEW                 AWEListKitMagicCollectionView
#define DYYY_T_AWELIVE_AUDIENCE_CONTAINER_CONTROLLER             AWELiveAudienceContainerController
#define DYYY_T_AWELIVE_AUDIENCE_VIEW_CONTROLLER                  AWELiveAudienceViewController
#define DYYY_T_AWELIVE_PRE_STREAM_PLAYER                         AWELivePreStreamPlayer
#define DYYY_T_AWELOADING_AND_VOLUME_VIEW                        AWELoadingAndVolumeView
#define DYYY_T_AWELONG_PRESS_PANEL_ABSETTINGS                    AWELongPressPanelABSettings
#define DYYY_T_AWELONG_PRESS_PANEL_DATA_MANAGER                  AWELongPressPanelDataManager
#define DYYY_T_AWELUCKY_CAT_BANNER_VIEW                          AWELuckyCatBannerView
#define DYYY_T_AWEMARK_VIEW                                      AWEMarkView
#define DYYY_T_AWEMIX_VIDEO_DETAIL_PLAY_LIST_DATA_CONTROLLER     AWEMixVideoDetailPlayListDataController
#define DYYY_T_AWEMIX_VIDEO_LIST_DATA_CONTROLLER                 AWEMixVideoListDataController
#define DYYY_T_AWEMIX_VIDEO_PANEL_MORE_VIEW                      AWEMixVideoPanelMoreView
#define DYYY_T_AWEMIX_VIDEO_RELATED_LIST_DATA_CONTROLLER         AWEMixVideoRelatedListDataController
#define DYYY_T_AWEMODERN_LONG_PRESS_PANEL_UICONFIG               AWEModernLongPressPanelUIConfig
#define DYYY_T_AWENEARBY_FULL_SCREEN_VIEW_MODEL                  AWENearbyFullScreenViewModel
#define DYYY_T_AWENEARBY_SKY_LIGHT_CAPSULE_VIEW                  AWENearbySkyLightCapsuleView
#define DYYY_T_AWENEW_LIVE_SKYLIGHT_VIEW_CONTROLLER              AWENewLiveSkylightViewController
#define DYYY_T_AWENORMAL_MODE_TAB_BAR                            AWENormalModeTabBar
#define DYYY_T_AWENOW_PLAYING_INFO_CENTER                        AWENowPlayingInfoCenter
#define DYYY_T_AWEORIGINAL_AD_MODEL                              AWEOriginalAdModel
#define DYYY_T_AWEPLAY_DANMAKU_INPUT_CONTAIN_VIEW                AWEPlayDanmakuInputContainView
#define DYYY_T_AWEPLAY_INTERACTION_FOLLOW_PROMPT_VIEW            AWEPlayInteractionFollowPromptView
#define DYYY_T_AWEPLAY_INTERACTION_SPEED_CONTROLLER              AWEPlayInteractionSpeedController
#define DYYY_T_AWEPLAY_INTERACTION_STATIC_FOLLOW_ANIMATION_VIEW  AWEPlayInteractionStaticFollowAnimationView
#define DYYY_T_AWEPLAY_INTERACTION_TIMESTAMP_ELEMENT             AWEPlayInteractionTimestampElement
#define DYYY_T_AWEPLAY_INTERACTION_USER_AVATAR_AD_LINK_CONTROLLER AWEPlayInteractionUserAvatarAdLinkController
#define DYYY_T_AWEPLAY_INTERACTION_USER_AVATAR_DECORATION_CONTROLLER AWEPlayInteractionUserAvatarDecorationController
#define DYYY_T_AWEPLAY_INTERACTION_USER_AVATAR_ENTER_STORE_CONTROLLER AWEPlayInteractionUserAvatarEnterStoreController
#define DYYY_T_AWEPLAY_INTERACTION_USER_AVATAR_FOLLOW_PROMPT_CONTROLLER AWEPlayInteractionUserAvatarFollowPromptController
#define DYYY_T_AWEPLAY_INTERACTION_USER_AVATAR_MAIN_BUSINESS_CONTROLLER AWEPlayInteractionUserAvatarMainBusinessController
#define DYYY_T_AWEPLAY_INTERACTION_USER_AVATAR_OPT_ELEMENT_ELEMENT AWEPlayInteractionUserAvatarOptElementElement
#define DYYY_T_AWEPLAY_INTERACTION_USER_AVATAR_SEND_MESSAGE_CONTROLLER AWEPlayInteractionUserAvatarSendMessageController
#define DYYY_T_AWEPLAY_INTERACTION_USER_AVATAR_SEND_MSG_CONTROLLER AWEPlayInteractionUserAvatarSendMsgController
#define DYYY_T_AWEPLAY_INTERACTION_USER_AVATAR_STORY_CONTROLLER  AWEPlayInteractionUserAvatarStoryController
#define DYYY_T_AWEPLAY_INTERACTION_USER_AVATAR_VIEW              AWEPlayInteractionUserAvatarView
#define DYYY_T_AWEPLAY_INTERACTION_VIEW_CONTROLLER               AWEPlayInteractionViewController
#define DYYY_T_AWEPLAY_VIDEO_PLAYER_CONTEXT                      AWEPlayVideoPlayerContext
#define DYYY_T_AWEPLAY_VIDEO_VIEW_CONTROLLER                     AWEPlayVideoViewController
#define DYYY_T_AWEPOIENTRY_ANCHOR_VIEW                           AWEPOIEntryAnchorView
#define DYYY_T_AWEPROFILE_AVATAR_VIEW_CONTROLLER                 AWEProfileAvatarViewController
#define DYYY_T_AWERELATED_MUSIC_ANCHOR_MODEL                     AWERelatedMusicAnchorModel
#define DYYY_T_AWERLVIRTUAL_LABEL                                AWERLVirtualLabel
#define DYYY_T_AWESHOW_PLAYLET_COMMENT_HEADER_VIEW               AWEShowPlayletCommentHeaderView
#define DYYY_T_AWESTORY_CONTAINER_COLLECTION_VIEW                AWEStoryContainerCollectionView
#define DYYY_T_AWESTORY_PROGRESS_CONTAINER_VIEW                  AWEStoryProgressContainerView
#define DYYY_T_AWETEEN_MODE_ALERT_VIEW                           AWETeenModeAlertView
#define DYYY_T_AWETEEN_MODE_SIMPLE_ALERT_VIEW                    AWETeenModeSimpleAlertView
#define DYYY_T_AWETEMPLATE_COMMON_VIEW                           AWETemplateCommonView
#define DYYY_T_AWETEMPLATE_STATIC_LABEL_INFO_MODEL               AWETemplateStaticLabelInfoModel
#define DYYY_T_AWETEMPLATE_TAGS_COMMON_VIEW                      AWETemplateTagsCommonView
#define DYYY_T_AWEURLMODEL                                       AWEURLModel
#define DYYY_T_AWEUSER_ACTION_SHEET_VIEW                         AWEUserActionSheetView
#define DYYY_T_AWEUSER_MODEL                                     AWEUserModel
#define DYYY_T_AWEUSER_NAME_LABEL                                AWEUserNameLabel
#define DYYY_T_AWEUSER_TAB_LIST_MODEL                            AWEUserTabListModel
#define DYYY_T_AWEVIDEO_MODEL                                    AWEVideoModel
#define DYYY_T_AWEVIDEO_PLAYER_CONFIGURATION                     AWEVideoPlayerConfiguration
#define DYYY_T_AWEVIDEO_PLAYER_SCREEN_BRIGHTNESS_MANAGER         AWEVideoPlayerScreenBrightnessManager
#define DYYY_T_BDBYTE_CAST_ENV_INFO                              BDByteCastEnvInfo
#define DYYY_T_BDBYTE_CAST_MONITOR_MANAGER                       BDByteCastMonitorManager
#define DYYY_T_BDBYTE_CAST_NET_UTILITIES                         BDByteCastNetUtilities
#define DYYY_T_BDBYTE_CAST_UTILS                                 BDByteCastUtils
#define DYYY_T_BDBYTE_SCREEN_CAST_CONTEXT                        BDByteScreenCastContext
#define DYYY_T_BDIMAGE                                           BDImage
#define DYYY_T_BDIMAGE_DECODER_BVC2                              BDImageDecoderBVC2
#define DYYY_T_BDIMAGE_DECODER_FACTORY                           BDImageDecoderFactory
#define DYYY_T_BDIMAGE_DECODER_HEIC                              BDImageDecoderHeic
#define DYYY_T_BDIMAGE_DECODER_IMAGE_IO                          BDImageDecoderImageIO
#define DYYY_T_BDIMAGE_DECODER_WEB_P                             BDImageDecoderWebP
#define DYYY_T_BDMULTI_CONTENT_CONTAINER_IMAGE_CONTENT_VIEW      BDMultiContentContainer_ImageContentView
#define DYYY_T_BDSIM_PLAYER_BIZ_CONFIG                           BDSimPlayerBizConfig
#define DYYY_T_BDXWEB_VIEW                                       BDXWebView
#define DYYY_T_CALAYER                                           CALayer
#define DYYY_T_CAMETAL_LAYER                                     CAMetalLayer
#define DYYY_T_CASHAPE_LAYER                                     CAShapeLayer
#define DYYY_T_COMMENT_INPUT_CONTAINER_VIEW                      CommentInputContainerView
#define DYYY_T_DDANMAKU_PLAYER_VIEW                              DDanmakuPlayerView
#define DYYY_T_DUXPOPOVER                                        DUXPopover
#define DYYY_T_HDRMTBUTTON                                       HDRMTButton
#define DYYY_T_HDRMTIMAGE_VIEW                                   HDRMTImageView
#define DYYY_T_HDRMTUIIMAGE_VIEW                                 HDRMTUIImageView
#define DYYY_T_HTSLIVE_STREAM_PLAYER                             HTSLiveStreamPlayer
#define DYYY_T_HTSLIVE_STREAM_QUALITY_FRAGMENT                   HTSLiveStreamQualityFragment
#define DYYY_T_IESECLIVE_CARD_SIZE_COMPONENT                     IESECLiveCardSizeComponent
#define DYYY_T_IESECLIVE_GOODS_CARD_VIEW                         IESECLiveGoodsCardView
#define DYYY_T_IESECLIVE_PLUGIN_LAYOUT_VIEW                      IESECLivePluginLayoutView
#define DYYY_T_IESIMVIDEO_PLAYER_WRAPPER                         IESIMVideoPlayerWrapper
#define DYYY_T_IESLIVE_AUDIENCE_HDRCONTROLLER                    IESLiveAudienceHDRController
#define DYYY_T_IESLIVE_AUDIENCE_VIEW_CONTROLLER                  IESLiveAudienceViewController
#define DYYY_T_IESLIVE_INNER_FEED_LIVE_ROOM_CELL                 IESLiveInnerFeedLiveRoomCell
#define DYYY_T_IESLIVE_PLAYER_CONTROLLER                         IESLivePlayerController
#define DYYY_T_IESLIVE_STACK_VIEW                                IESLiveStackView
#define DYYY_T_IESLIVE_STREAM_PLAYER_VIDEO_AUDIO_EFFECT_PLUGIN   IESLiveStreamPlayerVideoAudioEffectPlugin
#define DYYY_T_IESLLLIVE_PURCHASE_ATMOSPHERE_VIEW                IESLLLivePurchaseAtmosphereView
#define DYYY_T_IESVIDEO_PLAYER_CONFIG                            IESVideoPlayerConfig
#define DYYY_T_LOTANIMATION_VIEW                                 LOTAnimationView
#define DYYY_T_MPNOW_PLAYING_INFO_CENTER                         MPNowPlayingInfoCenter
#define DYYY_T_MTKVIEW                                           MTKView
#define DYYY_T_PLATFORM_CANVAS_VIEW                              PlatformCanvasView
#define DYYY_T_TTAD_SPLASH_MODEL                                 TTAdSplashModel
#define DYYY_T_TTMETAL_VIEW                                      TTMetalView
#define DYYY_T_TTMETAL_VIEW_NEW                                  TTMetalViewNew
#define DYYY_T_TTMETAL_VIEW_VP                                   TTMetalViewVP
#define DYYY_T_TTPLAYER_VIEW                                     TTPlayerView
#define DYYY_T_TVLMANAGER                                        TVLManager
#define DYYY_T_TVLPLAYER_ITEM_PREFERENCES                        TVLPlayerItemPreferences
#define DYYY_T_TVLSETTINGS_MANAGER                               TVLSettingsManager
#define DYYY_T_UICOLLECTION_VIEW                                 UICollectionView
#define DYYY_T_UIIMAGE_VIEW                                      UIImageView
#define DYYY_T_UILABEL                                           UILabel
#define DYYY_T_UIMENU                                            UIMenu
#define DYYY_T_UITEXT_FIELD                                      UITextField
#define DYYY_T_UITEXT_VIEW                                       UITextView
#define DYYY_T_UIVIEW                                            UIView
#define DYYY_T_UIWINDOW                                          UIWindow

#endif
