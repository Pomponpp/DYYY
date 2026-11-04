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
};

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
