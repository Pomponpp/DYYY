//
//  DKKeys.h
//  集中管理所有 NSUserDefaults 开关键与插件元信息。
//  开关键字符串用于 NSUserDefaults 持久化。
//

#ifndef DKKeys_h
#define DKKeys_h
#ifndef DK_VERSION
#define DK_VERSION @"2.2-9"
#endif
#define DKKeys_h

#import <Foundation/Foundation.h>


#pragma mark - 功能组：视频全屏

// 首页、朋友页、好友聊天页、搜索页、其他用户作品页统一由这一个开关控制。
static NSString *const DKKeyVideoFullscreen = @"DYYYVideoFullscreen";

#pragma mark - 功能组：评论区

// 评论区回复底栏（单选，整数）：0 显示 / 1 隐藏（原位置可点击回复）/ 2 移除（点击交给列表）；后两档列表均铺满。
static NSString *const DKKeyCommentReplyBottomBarMode = @"DYYYCommentReplyBottomBarMode";
static NSString *const DKKeyCommentAIParseMode = @"DYYYCommentAIParseMode";
static NSString *const DKKeyCommentSearchAnchorMode = @"DYYYCommentSearchAnchorMode";
static NSString *const DKKeyCommentLunaAnchorMode = @"DYYYCommentLunaAnchorMode";
static NSString *const DKKeyCommentLocationMode = @"DYYYCommentLocationMode";
static NSString *const DKKeyCommentGameAnchorMode = @"DYYYCommentGameAnchorMode";
static NSString *const DKKeyCommentPlayerDiscussionMode = @"DYYYCommentPlayerDiscussionMode";
static NSString *const DKKeyCommentStoreReviewMode = @"DYYYCommentStoreReviewMode";
static NSString *const DKKeyCommentSeriesAnchorMode = @"DYYYCommentSeriesAnchorMode";
static NSString *const DKKeyCommentDramaAnchorMode = @"DYYYCommentDramaAnchorMode";
static NSString *const DKKeyCommentDramaReviewMode = @"DYYYCommentDramaReviewMode";
static NSString *const DKKeyCommentRemoveAllTopTags = @"DYYYCommentRemoveAllTopTags";
static NSString *const DKKeyCommentRemoveAllTabs = @"DYYYCommentRemoveAllTabs";
// 移除评论列表中的「评论氛围是否满意」评价卡片。
static NSString *const DKKeyRemoveCommentSurvey = @"DYYYRemoveCommentSurvey";
static NSString *const DKKeyCommentMediaCleanBottomBar = @"DYYYCommentMediaCleanBottomBar";
// 材质单选（DKMakeGlassChoice）：总开关 + 清透档两个 BOOL，清透档关即系统 Regular。
static NSString *const DKKeyCommentGlass         = @"DYYYCommentGlass";
static NSString *const DKKeyCommentGlassClear    = @"DYYYCommentGlassClear";

#pragma mark - 功能组：分享

// 材质单选（DKMakeGlassChoice）：总开关 + 清透档两个 BOOL，清透档关即系统 Regular。
static NSString *const DKKeySharePanelGlass      = @"DYYYSharePanelGlass";
static NSString *const DKKeySharePanelGlassClear = @"DYYYSharePanelGlassClear";
// 分享面板精简：入口、累计功能目录、前缀 + shareType 的独立移除开关。
static NSString *const DKKeyShareMenu            = @"DYYYShareMenu";
static NSString *const DKKeyShareMenuCatalog     = @"DYYYShareMenuCatalog";
static NSString *const DKKeyShareMenuHidePrefix  = @"DYYYHideShareMenu.";

#pragma mark - 功能组：搜索页精简

static NSString *const DKKeySearchRemoveHistory = @"DYYYSearchRemoveHistory";
static NSString *const DKKeySearchRemoveGuess = @"DYYYSearchRemoveGuess";
static NSString *const DKKeySearchRemoveAllRanks = @"DYYYSearchRemoveAllRanks";
static NSString *const DKKeySearchRemoveRankFooter = @"DYYYSearchRemoveRankFooter";
static NSString *const DKKeySearchRemoveVoice = @"DYYYSearchRemoveVoice";
// 相机入口：0 显示 / 1 隐藏（保留位置与点击）/ 2 移除（原生布局收拢）。
static NSString *const DKKeySearchCameraMode = @"DYYYSearchCameraMode";

#pragma mark - 功能组：应用内通知

// 材质单选（DKMakeGlassChoice）：总开关 + 清透档两个 BOOL，清透档关即系统 Regular。
static NSString *const DKKeyInnerNotiGlass      = @"DYYYInnerNotiGlass";
static NSString *const DKKeyInnerNotiGlassClear = @"DYYYInnerNotiGlassClear";
// 0–100：0 为抖音原圆角，100 为胶囊。未写入时按 100。
static NSString *const DKKeyInnerNotiCorner     = @"DYYYInnerNotiCorner";
static NSString *const DKKeyTipsGlass          = @"DYYYTipsGlass";
static NSString *const DKKeyTipsGlassClear     = @"DYYYTipsGlassClear";

#pragma mark - 功能组：底栏

// 材质单选（DKMakeGlassChoice）：总开关 + 清透档两个 BOOL，清透档关即系统默认磨砂。
static NSString *const DKKeyGlassTabBar      = @"DYYYGlassTabBar";
static NSString *const DKKeyGlassTabBarClear = @"DYYYGlassTabBarClear";
// iPad 玻璃底栏位置（单选）：0 默认居中 / 1 左端 / 2 右端；仅 iPad 生效（见 DKGlassPadElements.xm）。
static NSString *const DKKeyGlassTabBarPadPosition = @"DYYYGlassTabBarPadPosition";
// 底栏动态收缩（单选）：0 关闭 / 1 左侧 / 2 右侧；仅 iPhone 生效（见 DKTabBarCollapse.xm）
static NSString *const DKKeyGlassTabBarCollapse = @"DYYYGlassTabBarCollapse";
// 悬浮玻璃底栏尺寸（百分比，100 为抖音默认效果）：胶囊等比缩放、胶囊长度、拍摄圆键直径，三者都以底边为锚。
// 常规范围见 DKAdjustRange.m，开启「扩展所有缩放与位移」后放宽。
static NSString *const DKKeyGlassTabBarCapsuleHeight = @"DYYYGlassTabBarCapsuleHeight";
static NSString *const DKKeyGlassTabBarCapsuleLength = @"DYYYGlassTabBarCapsuleLength";
static NSString *const DKKeyGlassTabBarPlusSize      = @"DYYYGlassTabBarPlusSize";
// 自定义拍摄图标：图片本体存文件（见 DKPlusIcon.xm），这个键只作设置项 identifier，
// NSUserDefaults 里不写值。是否使用由「拍摄按钮」（DKKeyPlusStyle）选「自定义图片」决定。
static NSString *const DKKeyPlusIcon         = @"DYYYPlusIcon";
// 底栏项目移除：每项一个 BOOL 键，前缀 + 抖音 tabID（见 DKTabBarRemoval.xm）。
static NSString *const DKKeyBottomBarHidePrefix = @"DYYYHideBottomBar.";
static NSString *const DKKeyHidePlusButton      = @"DYYYHideBottomBar.homepage_publish";
// 设置主页入口的 identifier，NSUserDefaults 里不写值。
static NSString *const DKKeyBottomBar           = @"DYYYBottomBar";

#pragma mark - 功能组：外观定制

// 底栏样式（单选，整数）：0 默认 / 1 单图标 / 2 图标+文字，作用于首页、朋友或商城、消息、我。
static NSString *const DKKeyTabBarStyle = @"DYYYTabBarStyle";
// 拍摄按钮（单选，整数）：0 默认 / 1 新图标 / 2 新双色图标 / 3 自定义图片（图片本体见 DKKeyPlusIcon）。
static NSString *const DKKeyPlusStyle   = @"DYYYPlusStyle";
// 底栏文字：每项一个字符串键，前缀 + 抖音 tabID；未设置即抖音默认文字。
static NSString *const DKKeyTabTitlePrefix       = @"DYYYTabBarTitle.";
static NSString *const DKKeyTabTitleHome         = @"DYYYTabBarTitle.homepage_home";
static NSString *const DKKeyTabTitleFriends      = @"DYYYTabBarTitle.homepage_familiar";
static NSString *const DKKeyTabTitleMall         = @"DYYYTabBarTitle.homepage_mall";
static NSString *const DKKeyTabTitleNotification = @"DYYYTabBarTitle.homepage_notification";
static NSString *const DKKeyTabTitleProfile      = @"DYYYTabBarTitle.homepage_profile";

#pragma mark - 功能组：互动按钮

// 图标单选：0 默认 / 1 第一款内置 / 2 第二款内置 / 3 自定义；图片项标识只用于文件与备份。
static NSString *const DKKeyInteractionLikeStyle = @"DYYYInteractionLikeStyle";
static NSString *const DKKeyInteractionCommentStyle = @"DYYYInteractionCommentStyle";
static NSString *const DKKeyInteractionFavoriteStyle = @"DYYYInteractionFavoriteStyle";
static NSString *const DKKeyInteractionShareStyle = @"DYYYInteractionShareStyle";
static NSString *const DKKeyInteractionLikeBeforeIcon = @"DYYYInteractionLikeBeforeIcon";
static NSString *const DKKeyInteractionLikeAfterIcon = @"DYYYInteractionLikeAfterIcon";
static NSString *const DKKeyInteractionCommentIcon = @"DYYYInteractionCommentIcon";
static NSString *const DKKeyInteractionFavoriteBeforeIcon = @"DYYYInteractionFavoriteBeforeIcon";
static NSString *const DKKeyInteractionFavoriteAfterIcon = @"DYYYInteractionFavoriteAfterIcon";
static NSString *const DKKeyInteractionShareIcon = @"DYYYInteractionShareIcon";

// 透明度：0–100，默认 100；缩放：常规 50–100，默认 100；
// 显示方式：0 显示 / 1 隐藏（不显示、仍可点击）/ 2 移除（不显示、不可点击，所在行收拢）。
// 缩放与上移的范围登记在 DKAdjustRange.m，开启「扩展所有缩放与位移」后放宽。
static NSString *const DKKeyInteractionIconAlpha  = @"DYYYInteractionIconAlpha";
static NSString *const DKKeyInteractionLabelAlpha = @"DYYYInteractionLabelAlpha";
static NSString *const DKKeyAvatarAlpha           = @"DYYYAvatarAlpha";
static NSString *const DKKeyMusicAlpha            = @"DYYYMusicAlpha";
static NSString *const DKKeyInteractionScale      = @"DYYYInteractionScale";
static NSString *const DKKeyAvatarScale            = @"DYYYAvatarScale";
static NSString *const DKKeyMusicScale             = @"DYYYMusicScale";
static NSString *const DKKeyInteractionDisplay    = @"DYYYInteractionDisplay";
static NSString *const DKKeyAvatarDisplay         = @"DYYYAvatarDisplay";
static NSString *const DKKeyMusicDisplay          = @"DYYYMusicDisplay";
// 头像下方关注入口：0 显示 / 1 隐藏（仍可点击）/ 2 移除（与已关注作者时一致）。
static NSString *const DKKeyFollowButtonDisplay   = @"DYYYFollowButtonDisplayMode";
// 互动区域上移：0–100 pt，默认 0（抖音原位）；头像、互动按钮、音乐整体上移。
static NSString *const DKKeyInteractionOffset     = @"DYYYInteractionOffset";

#pragma mark - 功能组：昵称文案

// 视频左下昵称一行与文案及其余信息行。透明度：0–100，默认 100；缩放：常规 25–100，默认 100；
// 上移：常规 0–100 pt，默认 0。缩放与上移的范围登记在 DKAdjustRange.m。
static NSString *const DKKeyNicknameAlpha    = @"DYYYNicknameAlpha";
static NSString *const DKKeyDescriptionAlpha = @"DYYYDescriptionAlpha";
static NSString *const DKKeyNicknameScale    = @"DYYYNicknameScale";
static NSString *const DKKeyDescriptionScale = @"DYYYDescriptionScale";
static NSString *const DKKeyInfoOffset       = @"DYYYInfoOffset";

#pragma mark - 功能组：进度条与图片指示器位置

// 视频进度条上移、图文图片指示器上移：常规 0–100 pt，默认 0。范围登记在 DKAdjustRange.m。
static NSString *const DKKeyProgressOffset       = @"DYYYProgressOffset";
static NSString *const DKKeyStoryIndicatorOffset = @"DYYYStoryIndicatorOffset";
static NSString *const DKKeyRelatedBarOffset = @"DYYYRelatedBarOffset";
// 本机实测缓存（不进备份）：进度条底边、图片指示器底边到交互层底边的原生距离（pt，不含本插件的上移），
// 供「位置同图片指示器」提示使用。
static NSString *const DKKeyProgressBaseBottom       = @"DYYYProgressBaseBottom";
static NSString *const DKKeyStoryIndicatorBaseBottom = @"DYYYStoryIndicatorBaseBottom";

#pragma mark - 功能组：弹幕改色

// 颜色模式：0 固定颜色 / 1 随机纯色 / 2 随机渐变 / 3 固定彩虹 / 4 自定义渐变 / 5 旋转彩虹。
static NSString *const DKKeyDanmakuColorEnabled = @"DYYYEnableDanmakuColor";
static NSString *const DKKeyDanmakuColorMode = @"DYYYDanmakuColorMode";
// 固定颜色的唯一规范存值；十六进制入口是同一值的另一个编辑入口。
static NSString *const DKKeyDanmakuFixedColor = @"DYYYDanmakuFixedColor";
static NSString *const DKKeyDanmakuHexColor = @"DYYYDanmakuHexColor";
static NSString *const DKKeyDanmakuGradientColors = @"DYYYDanmakuGradientColors";

#pragma mark - 功能组：发布时间与地区

// 主页作品信息，与播放页的开关独立。
static NSString *const DKKeyProfilePublishTime = @"DYYYProfileShowPublishTime";
static NSString *const DKKeyProfilePublishLocation = @"DYYYProfileShowPublishLocation";
// 播放页文案下方一行：具体发布时间（作品创建时间，按设备时区）与发布地区（作品城市代码与国家地区码，不含作者自选地点）。
static NSString *const DKKeyPublishTimeEnabled = @"DYYYShowPublishTime";
static NSString *const DKKeyPublishLocationEnabled = @"DYYYShowPublishLocation";
// 国外地名解析用的 GeoNames 用户名；空串为未填写。两个网页入口只作行标识，不存值。
static NSString *const DKKeyGeoNamesUsername = @"DYYYGeoNamesUsername";
static NSString *const DKKeyGeoNamesRegister = @"DYYYGeoNamesRegister";
static NSString *const DKKeyGeoNamesWebServices = @"DYYYGeoNamesWebServices";
// 「文字颜色」子页入口标识，不存值。
static NSString *const DKKeyPublishTextColors = @"DYYYPublishTextColors";
// 时间、地区两段文字各一套颜色：改色开关 / 颜色模式（同弹幕改色六种）/ 固定颜色 / 十六进制入口 / 渐变颜色。
static NSString *const DKKeyPublishTimeColorEnabled = @"DYYYPublishTimeColor";
static NSString *const DKKeyPublishTimeColorMode = @"DYYYPublishTimeColorMode";
static NSString *const DKKeyPublishTimeFixedColor = @"DYYYPublishTimeFixedColor";
static NSString *const DKKeyPublishTimeHexColor = @"DYYYPublishTimeHexColor";
static NSString *const DKKeyPublishTimeGradientColors = @"DYYYPublishTimeGradientColors";
static NSString *const DKKeyPublishLocationColorEnabled = @"DYYYPublishLocationColor";
static NSString *const DKKeyPublishLocationColorMode = @"DYYYPublishLocationColorMode";
static NSString *const DKKeyPublishLocationFixedColor = @"DYYYPublishLocationFixedColor";
static NSString *const DKKeyPublishLocationHexColor = @"DYYYPublishLocationHexColor";
static NSString *const DKKeyPublishLocationGradientColors = @"DYYYPublishLocationGradientColors";

#pragma mark - 功能组：音频可视化

// 两项都是单选，用对话框选，故存整数而非 BOOL。
// 位置：0 关闭 / 1 胶囊上方水平 / 2 胶囊整栏环绕 / 3 拍摄圆键环绕
static NSString *const DKKeyAudioVizPosition = @"DYYYAudioVizPosition";
// 形态：0 离散条 / 1 连续流体
static NSString *const DKKeyAudioVizStyle = @"DYYYAudioVizStyle";

#pragma mark - 功能组：播放体验

static NSString *const DKKeyDoubleTapOpenComment = @"DYYYDoubleTapOpenComment";
// 播放页长按左下昵称复制「@昵称」、长按文案复制作品完整文案。
static NSString *const DKKeyLongPressCopyNickname = @"DYYYLongPressCopyNickname";
static NSString *const DKKeyLongPressCopyDescription = @"DYYYLongPressCopyDescription";
static NSString *const DKKeyDetailHideBottomBar = @"DYYYHideChatVideoBottomBar";
static NSString *const DKKeyDetailReturnMode = @"DYYYDetailReturnMode";
static NSString *const DKKeyDetailSearchMode = @"DYYYDetailSearchMode";
// 所有视频常态下都显示底部进度条。
static NSString *const DKKeyProgressAlwaysVisible = @"DYYYProgressAlwaysVisible";
// 进度条只显示已播部分：隐藏未播放的那段轨道，显隐仍按抖音原逻辑。
static NSString *const DKKeyProgressPlayedOnly = @"DYYYProgressPlayedOnly";
// 进度条旁的已播 / 总时长：0 关闭 / 1 两端（与进度条同一行）/ 2 右端 · 上方 / 3 右端 · 下方 / 4 两端 · 上方 / 5 两端 · 下方
static NSString *const DKKeyProgressTimeStyle = @"DYYYProgressTimeStyle";

#pragma mark - 功能组：播放页精简

// 每项单选，存整数：0 显示 / 1 隐藏（不显示、仍可点击，位置保留）/ 2 移除（不显示、不可点击，按抖音原生排布收拢）。
static NSString *const DKKeyPlaybackFullscreenMode         = @"DYYYPlaybackFullscreenMode";
static NSString *const DKKeyPlaybackDanmakuMode            = @"DYYYPlaybackDanmakuMode";
// 锚点标签：同一种锚点元素，按锚点业务号区分。
// 旧 BOOL 键迁移为统一三档；目录只记录实际遇到的类型，独立档位沿用既有键或动态前缀。
static NSString *const DKKeyPlaybackRemoveAllAnchors       = @"DYYYPlaybackRemoveAllAnchors";
static NSString *const DKKeyPlaybackAllAnchorsMode         = @"DYYYPlaybackAllAnchorsMode";
static NSString *const DKKeyPlaybackAnchorsPage            = @"DYYYPlaybackAnchorsPage";
static NSString *const DKKeyPlaybackAnchorCatalog          = @"DYYYPlaybackAnchorCatalog";
static NSString *const DKKeyPlaybackAnchorModePrefix       = @"DYYYPlaybackAnchorMode.";
// 自定义名称：前缀 + 编码后的身份 → 单行文字；进备份，目录本身不进。
static NSString *const DKKeyPlaybackAnchorNamePrefix       = @"DYYYPlaybackAnchorName.";
static NSString *const DKKeyPlaybackAnchorRenamePage       = @"DYYYPlaybackAnchorRenamePage";
static NSString *const DKKeyPlaybackGameTagMode            = @"DYYYPlaybackGameTagMode";
static NSString *const DKKeyPlaybackMusicAnchorMode        = @"DYYYPlaybackMusicAnchorMode";
static NSString *const DKKeyPlaybackPropEffectMode         = @"DYYYPlaybackPropEffectMode";
static NSString *const DKKeyPlaybackJianyingMode           = @"DYYYPlaybackJianyingMode";
static NSString *const DKKeyPlaybackPaidContentMode        = @"DYYYPlaybackPaidContentMode";
static NSString *const DKKeyPlaybackLocationMode           = @"DYYYPlaybackLocationMode";
// 文案上方
static NSString *const DKKeyPlaybackOtherUserRecommendMode = @"DYYYPlaybackOtherUserRecommendMode";
static NSString *const DKKeyPlaybackFriendRecommendMode    = @"DYYYPlaybackFriendRecommendMode";
static NSString *const DKKeyPlaybackFriendShareMode        = @"DYYYPlaybackFriendShareMode";
static NSString *const DKKeyPlaybackSelectedMode           = @"DYYYPlaybackSelectedMode";
static NSString *const DKKeyPlaybackStoreMode              = @"DYYYPlaybackStoreMode";
// 昵称右侧
static NSString *const DKKeyPlaybackChapterHighlightsMode  = @"DYYYPlaybackChapterHighlightsMode";
static NSString *const DKKeyPlaybackCoCreatorMode          = @"DYYYPlaybackCoCreatorMode";
static NSString *const DKKeyPlaybackSlidesTagMode          = @"DYYYPlaybackSlidesTagMode";
static NSString *const DKKeyPlaybackArticleTagMode         = @"DYYYPlaybackArticleTagMode";
// 文案下方
static NSString *const DKKeyPlaybackRiskNoticeMode         = @"DYYYPlaybackRiskNoticeMode";
static NSString *const DKKeyPlaybackMusicInfoMode          = @"DYYYPlaybackMusicInfoMode";
static NSString *const DKKeyPlaybackQuickReplyMode         = @"DYYYPlaybackQuickReplyMode";
// 底部栏目：统一三档覆盖原生底部容器中的全部业务行，独立档位保持不变。
static NSString *const DKKeyPlaybackRemoveAllBottomBars    = @"DYYYPlaybackRemoveAllBottomBars";
static NSString *const DKKeyPlaybackAllBottomBarsMode      = @"DYYYPlaybackAllBottomBarsMode";
static NSString *const DKKeyPlaybackBottomBarsPage         = @"DYYYPlaybackBottomBarsPage";
static NSString *const DKKeyPlaybackBottomBarCatalog       = @"DYYYPlaybackBottomBarCatalog";
static NSString *const DKKeyPlaybackBottomBarModePrefix    = @"DYYYPlaybackBottomBarMode.";
static NSString *const DKKeyPlaybackBottomBarNamePrefix    = @"DYYYPlaybackBottomBarName.";
// 底部栏目背景透明：覆盖原生底部容器中的全部业务行。
static NSString *const DKKeyPlaybackBottomBarTransparent   = @"DYYYPlaybackBottomBarTransparent";
static NSString *const DKKeyPlaybackBottomBarRenamePage    = @"DYYYPlaybackBottomBarRenamePage";
static NSString *const DKKeyPlaybackRelatedSearchMode      = @"DYYYPlaybackRelatedSearchMode";
static NSString *const DKKeyPlaybackRelatedVideoMode       = @"DYYYPlaybackRelatedVideoMode";
static NSString *const DKKeyPlaybackVideoCollectionMode    = @"DYYYPlaybackVideoCollectionMode";
static NSString *const DKKeyPlaybackHotspotMode            = @"DYYYPlaybackHotspotMode";
static NSString *const DKKeyPlaybackAppDownloadMode        = @"DYYYPlaybackAppDownloadMode";

#pragma mark - 功能组：内容过滤

static NSString *const DKKeyFilterLowLikes = @"DYYYFilterLowLikes";
static NSString *const DKKeyMinimumLikes = @"DYYYMinimumLikes";
static NSString *const DKKeyRemoveRecommendedLive = @"DYYYRemoveRecommendedLive";
static NSString *const DKKeyFilterRecommendedMusic = @"DYYYFilterRecommendedMusic";
static NSString *const DKKeyFilterRecommendedArticle = @"DYYYFilterRecommendedArticle";
// 商家笔记：图文作品上的 POI 富内容卡片（店铺/团购笔记）。
static NSString *const DKKeyFilterRecommendedMerchantNote = @"DYYYFilterRecommendedMerchantNote";
// 特殊卡片：总开关开启时全部类别（含未单独分类的业务）过滤，各类别开关锁定显示为开启，存值不动。
static NSString *const DKKeyFilterRecommendedSpecialCard = @"DYYYFilterRecommendedSpecialCard";
static NSString *const DKKeyFilterRecommendedHotspot = @"DYYYFilterRecommendedHotspot";
static NSString *const DKKeyFilterRecommendedCreation = @"DYYYFilterRecommendedCreation";
static NSString *const DKKeyFilterRecommendedEcommerce = @"DYYYFilterRecommendedEcommerce";
static NSString *const DKKeyFilterRecommendedGame = @"DYYYFilterRecommendedGame";
static NSString *const DKKeyFilterRecommendedSocial = @"DYYYFilterRecommendedSocial";
static NSString *const DKKeyFilterRecommendedInterest = @"DYYYFilterRecommendedInterest";
static NSString *const DKKeyFilterRecommendedMicroApp = @"DYYYFilterRecommendedMicroApp";
static NSString *const DKKeyFilterAds = @"DYYYFilterAds";

#pragma mark - 功能组：顶部频道

// 每个频道一个 BOOL 键：前缀 + channelID。
static NSString *const DKKeyTopChannelHidePrefix = @"DYYYHideTopChannel.";
// 扫描到的频道目录：NSArray<NSDictionary>，每项含 id/name/title/locked/present。
static NSString *const DKKeyTopChannelCatalog = @"DYYYTopChannelCatalog";
// 设置主页入口的 identifier，NSUserDefaults 里不写值。
static NSString *const DKKeyTopChannels = @"DYYYTopChannels";

#pragma mark - 功能组：顶栏入口

// 单选，存整数：0 显示 / 1 隐藏（不显示、仍可点击）/ 2 移除（不显示、不可点击）。
static NSString *const DKKeyTopBarSideBarMode = @"DYYYTopBarSideBarMode";
static NSString *const DKKeyTopBarSearchMode  = @"DYYYTopBarSearchMode";
// 屏蔽在最左侧频道右滑展开左侧栏。
static NSString *const DKKeyBlockSideBarSwipe = @"DYYYBlockSideBarSwipe";
// 顶栏透明度：0–100，默认 100；作用于左侧栏入口、全部频道与搜索图标。
static NSString *const DKKeyTopBarAlpha       = @"DYYYTopBarAlpha";
// 顶栏液态玻璃的材质单选（DKMakeGlassChoice）：总开关 + 清透档两个 BOOL，清透档关即系统 Regular。
static NSString *const DKKeyTopBarGlass        = @"DYYYTopBarGlass";
static NSString *const DKKeyTopBarGlassClear   = @"DYYYTopBarGlassClear";
// 顶栏液态玻璃尺寸：圆钮与胶囊的统一高度（百分比）、胶囊长度（百分比）。
static NSString *const DKKeyTopBarGlassHeight  = @"DYYYTopBarGlassHeight";
static NSString *const DKKeyTopBarGlassLength  = @"DYYYTopBarGlassLength";

#pragma mark - 功能组：未读红点

// 移除未读红点（点状 / 数字 / 文字）：底栏按钮、首页顶栏频道、左侧栏（≡ 入口与侧边栏面板）三处各一个开关。
static NSString *const DKKeyTabBarRemoveBadge  = @"DYYYTabBarRemoveBadge";
static NSString *const DKKeyTopBarRemoveBadge  = @"DYYYTopBarRemoveBadge";
static NSString *const DKKeySideBarRemoveBadge = @"DYYYSideBarRemoveBadge";

#pragma mark - 功能组：朋友页精简

// 每项单选，存整数：0 显示 / 1 隐藏（不显示、仍可点击，位置保留）/ 2 移除（不显示、不可点击，按抖音原生排布收拢）。
// 顶栏：左上角头像和加号（日常相机）、中间「限时日常」胶囊（移除时天窗也不再展开）、右上角朋友按钮。
static NSString *const DKKeyFriendAvatarEntryMode   = @"DYYYFriendAvatarEntryMode";
static NSString *const DKKeyFriendDailyMode         = @"DYYYFriendDailyMode";
static NSString *const DKKeyFriendButtonMode        = @"DYYYFriendButtonMode";
// 作品：文案上方「朋友」标记、文案下方「私信 xxx」面板、头像下方「私信」图标；凡出现处都生效。
static NSString *const DKKeyFriendRelationTagMode   = @"DYYYFriendRelationTagMode";
static NSString *const DKKeyFriendFastReplyMode     = @"DYYYFriendFastReplyMode";
static NSString *const DKKeyFriendSendMessageMode   = @"DYYYFriendSendMessageMode";
// 作品：昵称右侧「日常」标签、文案上方关注标签（你的关注 / 互相关注等关系文案）。
static NSString *const DKKeyFriendStoryTagMode      = @"DYYYFriendStoryTagMode";
static NSString *const DKKeyFriendFollowTagMode     = @"DYYYFriendFollowTagMode";
// 内容：移除朋友页内容流里的「看看朋友推荐的作品」卡片（开关）。
static NSString *const DKKeyFriendRemoveRecommendCard = @"DYYYFriendRemoveRecommendCard";

#pragma mark - 功能组：消息页精简

// 每项单选，存整数：0 显示 / 1 隐藏（不显示、仍可点击，位置保留）/ 2 移除（不显示、不可点击，按抖音原生排布收拢）。
// 顶栏
static NSString *const DKKeyMessageSideBarMode      = @"DYYYMessageSideBarMode";
static NSString *const DKKeyMessageSlotMode         = @"DYYYMessageSlotMode";
static NSString *const DKKeyMessageSearchMode       = @"DYYYMessageSearchMode";
static NSString *const DKKeyMessagePlusMode         = @"DYYYMessagePlusMode";
// 列表顶部：头像行开头的业务入口、头像行里的好友头像、互动消息会话。
static NSString *const DKKeyMessageDailyMode        = @"DYYYMessageDailyMode";
static NSString *const DKKeyMessageFriendAvatarMode = @"DYYYMessageFriendAvatarMode";
static NSString *const DKKeyMessageInteractionMode  = @"DYYYMessageInteractionMode";

#pragma mark - 功能组：聊天页输入区

static NSString *const DKKeyChatRemoveEmojiSuggestions = @"DYYYChatRemoveEmojiSuggestions";
static NSString *const DKKeyChatPlayEntryMode           = @"DYYYChatPlayEntryMode";
static NSString *const DKKeyChatRemovePlusPhotos        = @"DYYYChatRemovePlusPhotos";
static NSString *const DKKeyChatInputGlass              = @"DYYYChatInputGlass";
static NSString *const DKKeyChatInputGlassClear         = @"DYYYChatInputGlassClear";
static NSString *const DKKeyChatRemoveBack              = @"DYYYChatRemoveBack";
static NSString *const DKKeyChatRemoveUnread            = @"DYYYChatRemoveUnread";
static NSString *const DKKeyChatRemoveOnline            = @"DYYYChatRemoveOnline";
static NSString *const DKKeyChatRemoveCall              = @"DYYYChatRemoveCall";
static NSString *const DKKeyChatRemoveMenu              = @"DYYYChatRemoveMenu";
static NSString *const DKKeyChatGroupZoneNoAutoExpand   = @"DYYYChatGroupZoneNoAutoExpand";
// 聊天页顶栏自定义：子页面入口、顶部渐变模糊、居中头像（0 默认 / 1 居中）、火花与在线位置（0 居中 / 1 左侧 / 2 右侧）。
static NSString *const DKKeyChatTopCustomPage           = @"DYYYChatTopCustomPage";
static NSString *const DKKeyChatTopBlur                 = @"DYYYChatTopBlur";
static NSString *const DKKeyChatTopCenter               = @"DYYYChatTopCenter";
static NSString *const DKKeyChatTopStreakPosition       = @"DYYYChatTopStreakPosition";
static NSString *const DKKeyChatTopOnlinePosition       = @"DYYYChatTopOnlinePosition";

#pragma mark - 功能组：长按菜单

// 作品长按菜单：每个原生菜单项一个 BOOL 键，前缀 + 抖音菜单项标识（panelBizVMIdentifier）。
static NSString *const DKKeyFeedMenuHidePrefix    = @"DYYYHideFeedMenu.";
// 打开过的作品长按菜单里出现的原生菜单项：NSArray<NSDictionary>，每项含 id/title。
static NSString *const DKKeyFeedMenuCatalog       = @"DYYYFeedMenuCatalog";
// 宫格排列（单选，整数）：0 每行 1 个（抖音原生列表）/ 1 每行 2 个 / 2 每行 3 个 / 3 每行 4 个。
static NSString *const DKKeyFeedMenuColumns       = @"DYYYFeedMenuColumns";
// 设置子页入口的 identifier，NSUserDefaults 里不写值。
static NSString *const DKKeyFeedMenu              = @"DYYYFeedMenu";
// 长按作品不弹出长按面板（BOOL）。
static NSString *const DKKeyFeedMenuNoPanel       = @"DYYYFeedMenuNoPanel";
// 评论长按菜单：每项一个 BOOL 键，前缀 + 菜单项标识（元素 elementType 数字，或分享行 share）。
static NSString *const DKKeyCommentMenuHidePrefix = @"DYYYHideCommentMenu.";
static NSString *const DKKeyCommentMenuCatalog    = @"DYYYCommentMenuCatalog";
static NSString *const DKKeyCommentMenuColumns    = @"DYYYCommentMenuColumns";
static NSString *const DKKeyCommentMenu           = @"DYYYCommentMenu";
// 作品长按菜单的材质单选（DKMakeGlassChoice）：总开关 + 清透档两个 BOOL，清透档关即系统 Regular。
static NSString *const DKKeyFeedMenuGlass         = @"DYYYFeedMenuGlass";
static NSString *const DKKeyFeedMenuGlassClear    = @"DYYYFeedMenuGlassClear";
// 复制评论时去掉开头的「@用户名: 」，只复制评论内容。
static NSString *const DKKeyCommentCopyWithoutName = @"DYYYCommentCopyWithoutName";

#pragma mark - 功能组：个人主页

static NSString *const DKKeyProfileHideUGCGuide = @"DYYYHideProfileUGCGuide";

// 个人主页精简，只作用于自己的主页。
// 每项单选，存整数：0 显示 / 1 隐藏（不显示、仍可点击，位置保留）/ 2 移除（不显示、不可点击，按抖音原生排布收拢）。
// 顶栏：添加好友、访客、搜索图标、侧栏图标。
static NSString *const DKKeyProfileAddFriendMode     = @"DYYYProfileAddFriendMode";
static NSString *const DKKeyProfileVisitorMode       = @"DYYYProfileVisitorMode";
static NSString *const DKKeyProfileSearchMode        = @"DYYYProfileSearchMode";
static NSString *const DKKeyProfileSideBarMode       = @"DYYYProfileSideBarMode";
// 头像与昵称：头像右下角加号、昵称后的切换账号箭头、抖音号下方的胶囊行。
static NSString *const DKKeyProfileAvatarPlusMode    = @"DYYYProfileAvatarPlusMode";
static NSString *const DKKeyProfileSwitchAccountMode = @"DYYYProfileSwitchAccountMode";
static NSString *const DKKeyProfileCapsuleMode       = @"DYYYProfileCapsuleMode";
// 数据与按钮：获赞 / 互关 / 关注 / 粉丝整行、编辑主页；两者共用一行。
static NSString *const DKKeyProfileStatsMode         = @"DYYYProfileStatsMode";
static NSString *const DKKeyProfileEditMode          = @"DYYYProfileEditMode";
// 内容：「记录下幸福瞬间」等发布引导横幅（按所在分区识别）。
static NSString *const DKKeyProfileGuideBannerMode   = @"DYYYProfileGuideBannerMode";
// 功能区（开关）：移除观看历史、全部功能等入口所在的整行，不占位。
static NSString *const DKKeyProfileRemoveServiceArea = @"DYYYProfileRemoveServiceArea";
// 分页（开关）：开启即移除对应分页。
static NSString *const DKKeyProfileRemovePostTab      = @"DYYYProfileRemovePostTab";
static NSString *const DKKeyProfileRemoveDailyTab     = @"DYYYProfileRemoveDailyTab";
static NSString *const DKKeyProfileRemoveFavoriteTab  = @"DYYYProfileRemoveFavoriteTab";
static NSString *const DKKeyProfileRemoveLikeTab      = @"DYYYProfileRemoveLikeTab";
static NSString *const DKKeyProfileRemoveFootprintTab = @"DYYYProfileRemoveFootprintTab";

#pragma mark - 功能组：媒体保存

// 作品长按面板里的保存项；保存视频 / 保存当前图片开启时移除原生「保存至相册」。
static NSString *const DKKeyMediaSaveVideo         = @"DYYYMediaSaveVideo";
static NSString *const DKKeyMediaSaveCurrentImage  = @"DYYYMediaSaveCurrentImage";
static NSString *const DKKeyMediaSaveAllImages     = @"DYYYMediaSaveAllImages";
static NSString *const DKKeyMediaSaveCover         = @"DYYYMediaSaveCover";
static NSString *const DKKeyMediaSaveMusic         = @"DYYYMediaSaveMusic";
// 评论长按「保存到相册」改由插件保存图片、实况与视频评论。
static NSString *const DKKeyMediaSaveComment       = @"DYYYMediaSaveComment";
// 评论表情：长按菜单与单击后的表情页增加「保存表情包」。
static NSString *const DKKeyMediaSaveCommentSticker = @"DYYYMediaSaveCommentSticker";
// 抖音原生的评论图片 / 实况保存不带水印。
static NSString *const DKKeyCommentImageNoWatermark     = @"DYYYCommentImageNoWatermark";
static NSString *const DKKeyCommentLivePhotoNoWatermark = @"DYYYCommentLivePhotoNoWatermark";
// 私信表情消息长按菜单、单击后的表情页、表情面板长按预览增加「保存表情包」。
static NSString *const DKKeyMediaSaveChatSticker   = @"DYYYMediaSaveChatSticker";
static NSString *const DKKeyMediaSaveHaptic        = @"DYYYMediaSaveHaptic";
// 通用提示面板的材质单选：总开关关时为系统模糊，开时按清透档取 Regular / Clear。
static NSString *const DKKeyMediaSaveGlass         = @"DYYYMediaSaveGlass";
static NSString *const DKKeyMediaSaveGlassClear    = @"DYYYMediaSaveGlassClear";

#pragma mark - 功能组：备份工具

// 备份工具页的四个动作行，只作设置项 identifier，NSUserDefaults 里不写值。
static NSString *const DKKeyBackupExport  = @"DYYYBackupExport";
static NSString *const DKKeyBackupRestore = @"DYYYBackupRestore";
static NSString *const DKKeyBackupUndo    = @"DYYYBackupUndo";
static NSString *const DKKeyBackupReset   = @"DYYYBackupReset";
// 上次导出备份的时间（NSDate）。不属于任何设置项：不进备份，恢复默认也不清。
static NSString *const DKKeyBackupLastExportDate = @"DYYYBackupLastExportDate";

#pragma mark - 设置页

// 「液态玻璃 (iOS26+)」子页入口的 identifier，供玻璃守卫在低系统灰显整个入口；不写值。
static NSString *const DKKeySettingsPageGlass = @"DYYYPageLiquidGlass";

#pragma mark - 功能组：调整范围

// 扩展所有缩放与位移：开启后 DKAdjustRange 登记的各项按扩展范围生效。开启前须确认，不进备份。
static NSString *const DKKeyAdjustRangeExtended = @"DYYYAdjustRangeExtended";

#pragma mark - 功能组：快捷入口

// 个人主页功能区末尾的 参考实现 设置入口（开关，只作用于自己的主页）。
static NSString *const DKKeyProfileSettingsEntry     = @"DYYYProfileSettingsEntry";
// 入口文字（单选，整数）：0「参考实现」/ 1「插件设置」。
static NSString *const DKKeyProfileSettingsEntryName = @"DYYYProfileSettingsEntryName";

#pragma mark - 功能组：调试工具

static NSString *const DKKeyDebugInspectorEnabled = @"DYYYDebugInspectorEnabled";

#endif /* DKKeys_h */
