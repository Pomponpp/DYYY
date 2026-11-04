#import "AwemeHeaders.h"
#import "DYYYClassRegistry.h"
#import <objc/runtime.h>

// 关键类清单：优先收录 40.9 曾失效的改名/迁移类，以及全屏、评论、直播链路核心类。
// 每项 = { 旧类名或主类名, 40.9 继任类名（无则 NULL） }
typedef struct {
    const char *primary;
    const char *successor; // 可为 NULL
} DYYYAuditEntry;

static const DYYYAuditEntry kDYYYAuditTable[] = {
    // ---- 全屏 / 互动区链路 ----
    { "AWEPlayInteractionViewController", NULL },
    { "AWEAwemeDetailTableViewController", NULL },
    { "AWEAwemeDetailCellViewController", NULL },
    { "AFDPlayRemoteFeedTableViewController", NULL },
    { "AFDPureModePageListViewController", NULL },
    { "AFDPureModePageContainerViewController", NULL },
    { "AFDPureModePageTapController", NULL },
    { "AWEFeedContainerViewController", NULL },
    { "AWEFeedTableView", NULL },
    { "AWEFeedTableViewCell", NULL },
    { "AWEFeedViewCell", NULL },
    { "AWEFeedCellViewController", NULL },
    { "AWEDPlayerFeedPlayerViewController", NULL },
    { "AWEAwemePlayVideoViewController", NULL },
    { "AWEDPlayerViewController_Merge", NULL },
    { "TTPlayerView", NULL },
    { "AWENormalModeTabBar", NULL },
    { "AWENormalModeTabBarController", NULL },
    { "AWEBaseElementView", NULL },
    { "AWEUserNameLabel", NULL },
    { "AWEPlayInteractionDescriptionLabel", NULL },
    { "AWEPlayInteractionDescriptionScrollView", NULL },
    { "AWEStoryProgressContainerView", NULL },
    { "AWELiveGuideElement", NULL },
    { "_TtC22AWEFeedPlayControlImpl30PureModePageCellViewController", NULL },

    // ---- 评论链路 ----
    { "AWECommentContainerViewController", NULL },
    { "AWECommentInputViewController", NULL },
    { "AWECommentInputBackgroundView", NULL },
    { "_TtC20AWECommentSwiftBizUI27CommentInteractionBaseLabel", NULL },
    { "_TtC33AWECommentPanelContainerSwiftImpl35CommentContainerInnerViewController", NULL },
    { "_TtC27AWECommentCommerceSwiftImpl24CommentHeaderGeneralView", NULL },
    { "_TtC27AWECommentCommerceSwiftImpl22CommentHeaderGoodsView", NULL },
    { "_TtC30AWECommentPanelHeaderSwiftImpl31CommentHeaderTemplateAnchorView", NULL },
    { "_TtC28AWECommentInputViewSwiftImpl25CommentInputContainerView", NULL },
    { "_TtC28AWECommentInputViewSwiftImpl31CommentInputViewMiddleContainer", NULL },
    { "_TtC28AWECommentMediaFeedSwfitImpl34CommentMediaFeedCellViewController", NULL },

    // ---- 40.9 改名对（旧名缺失属预期，继任名必须存在） ----
    { "AWEFullPageFeedContainerViewController", NULL },
    { "AWEProfileAvatarFunctionManager", NULL },
    { "AWEFamiliarSkylightBubbleView", NULL },
    { "AWEProfileTaskCardStyleListItemCell", NULL },
    { "AWEProfilePublishGuideCollectionViewCell", NULL },
    { "AWEAwesomeSplashLiveCellAccessoryView", NULL },
    { "IESLLLivePurchaseAtmosphereView", NULL },
    { "_TtC21AWEIncentiveSwiftImpl20PendantContainerView", NULL },
    { "AWEIMCommentShareTableViewCell", NULL },

    // ---- 直播链路 ----
    { "AWELiveFeedStatusLabel", NULL },
    { "AWELiveFeedLabelTagView", NULL },
    { "IESLiveInnerFeedLiveRoomCell", NULL },
    { "IESLiveAudienceViewController", NULL },
    { "IESLiveUserSeqlistFragment", NULL },
    { "AWEFeedLiveMarkView", NULL },
    { "IESLiveFlowGuidanceFragment", NULL },
    { "IESECLiveCardSizeComponent", NULL },
    { "IESECLiveGoodsCardView", NULL },
    { "IESLiveBottomRightCardView", NULL },

    // ---- 其它高频功能 ----
    { "AWEDateTimeFormatter", NULL },
    { "AWERLVirtualLabel", NULL },
    { "YYLabel", NULL },
    { "DDanmakuPlayerView", NULL },
    { "AWEDanmakuContentLabel", NULL },
    { "AWEFeedChannelManager", NULL },
    { "AWEHPTopTabItemTextContentView", NULL },
    { "AWEHPTopTabItemBadgeContentView", NULL },
    { "AWEVersionUpdateManager", NULL },
    { "AWESettingBaseViewController", NULL },
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

+ (NSInteger)runStartupAudit {
    static dispatch_once_t auditOnce;
    __block NSInteger missingCount = 0;
    dispatch_once(&auditOnce, ^{
      NSMutableArray<NSString *> *missing = [NSMutableArray array];
      const NSUInteger entryCount = sizeof(kDYYYAuditTable) / sizeof(kDYYYAuditTable[0]);
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

@end
