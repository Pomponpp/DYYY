#import "AwemeHeaders.h"
#import "DYYYFeatureUI.h"

// 隐藏文案下推荐应用下载横幅
static void DYYYRemoveRecommendAppDownloadView(id viewObject) {
    if (![viewObject isKindOfClass:[UIView class]]) {
        return;
    }
    UIView *view = (UIView *)viewObject;
    view.hidden = YES;
    [view removeFromSuperview];
}

static void DYYYHideRecommendAppDownloadViewForOwner(id owner) {
    // 41.3 把挂载点属性名从 addFeedMusicView 改成了 musicView
    id musicView = [DYYYFeatureUI value:owner key:@"musicView"];
    DYYYRemoveRecommendAppDownloadView(musicView);
    [DYYYFeatureUI setValue:nil object:owner key:@"musicView"];
}

// 「隐藏推荐应用下载」：41.3 的挂载点已整体改名——
//   addFeedMusicView                             → musicView
//   setAddFeedMusicView:                         → setMusicView:
//   showFeedMusicViewIfNeeded                    → ensureMusicView / layoutMusicViewIfNeeded
//   shouldShowAddFeedMusicView                   → shouldShowListenFeedCover
// 旧四个方法在二进制里已全部不存在（hook 挂空，所以功能失效）。
// 新实现只认视图注入点，最稳：无论是首次创建还是复用，视图进来就直接摘掉。
// 不去动 shouldShowListenFeedCover —— 那个控制的是听视频封面展示，改了会连带隐藏封面。
%hook AWEPlayInteractionMusicAiRefactorListenFeedController

- (void)setMusicView:(UIView *)view {
    if (DYYYGetBool(@"DYYYHideRecommendAppDownload")) {
        if ([view isKindOfClass:[UIView class]]) {
            view.hidden = YES;
            [view removeFromSuperview];
        }
        %orig(nil);
        return;
    }
    %orig;
}

- (id)createMusicView {
    id view = %orig;
    if (DYYYGetBool(@"DYYYHideRecommendAppDownload")) {
        DYYYRemoveRecommendAppDownloadView(view);
    }
    return view;
}

- (void)ensureMusicView {
    %orig;
    if (DYYYGetBool(@"DYYYHideRecommendAppDownload")) {
        DYYYHideRecommendAppDownloadViewForOwner(self);
    }
}

- (void)layoutMusicViewIfNeeded {
    %orig;
    if (DYYYGetBool(@"DYYYHideRecommendAppDownload")) {
        DYYYHideRecommendAppDownloadViewForOwner(self);
    }
}

%end

// 39.3.0 的应用推荐已改走通用 Diversion Bar。该视图只承载
// pkgInfo/appMarket/downloadIntermediatePage 类应用引流，隐藏它不会删除作品文案或普通音乐信息。
%hook AWEPlayInteractionDiversionBar

- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideRecommendAppDownload")) {
        DYYYRemoveRecommendAppDownloadView(self);
        return;
    }
    %orig;
}

- (void)didMoveToWindow {
    %orig;
    if (DYYYGetBool(@"DYYYHideRecommendAppDownload")) {
        DYYYRemoveRecommendAppDownloadView(self);
    }
}

%end

%hook AWEPlayInteractionNewDiversionBarBottomElement

- (void)setDiversionBarView:(AWEPlayInteractionDiversionBar *)view {
    if (DYYYGetBool(@"DYYYHideRecommendAppDownload")) {
        DYYYRemoveRecommendAppDownloadView(view);
        %orig(nil);
        return;
    }
    %orig;
}

- (void)layoutElementView {
    if (DYYYGetBool(@"DYYYHideRecommendAppDownload")) {
        DYYYRemoveRecommendAppDownloadView([DYYYFeatureUI ivar:self name:"_diversionBarView"]);
        return;
    }
    %orig;
}

%end

// 抖音精选的应用推荐使用独立 Lynx 底栏。只在其自身的
// canShow/update/add 入口阻断，不移除 feed 容器。
static void DYYYHideDouYinSelectAppGuideViews(id owner) {
    DYYYRemoveRecommendAppDownloadView([DYYYFeatureUI ivar:owner name:"_appGuideView"]);
    DYYYRemoveRecommendAppDownloadView([DYYYFeatureUI ivar:owner name:"_appGuideContainer"]);
}

%hook AWEDouYinSelectUGBottomBarController

- (BOOL)canShowBottomBarForAweme:(id)aweme {
    if (DYYYGetBool(@"DYYYHideRecommendAppDownload")) {
        return NO;
    }
    return %orig;
}

- (void)updateBottomBarWithAweme:(id)aweme updateTiming:(BOOL)updateTiming {
    if (DYYYGetBool(@"DYYYHideRecommendAppDownload")) {
        DYYYHideDouYinSelectAppGuideViews(self);
        return;
    }
    %orig;
}

- (void)bottomBarAddedToContainer:(id)container {
    if (DYYYGetBool(@"DYYYHideRecommendAppDownload")) {
        DYYYHideDouYinSelectAppGuideViews(self);
        return;
    }
    %orig;
}

- (void)setAppGuideView:(UIView *)view {
    if (DYYYGetBool(@"DYYYHideRecommendAppDownload")) {
        DYYYRemoveRecommendAppDownloadView(view);
        %orig(nil);
        return;
    }
    %orig;
}

- (void)setAppGuideContainer:(UIView *)view {
    if (DYYYGetBool(@"DYYYHideRecommendAppDownload")) {
        DYYYRemoveRecommendAppDownloadView(view);
        %orig(nil);
        return;
    }
    %orig;
}

%end

%hook AWEFeedMeetMusicView

- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideRecommendAppDownload")) {
        UIView *view = (UIView *)self;
        view.hidden = YES;
        [view removeFromSuperview];
        return;
    }
    %orig;
}

- (void)didMoveToWindow {
    %orig;
    if (DYYYGetBool(@"DYYYHideRecommendAppDownload")) {
        UIView *view = (UIView *)self;
        view.hidden = YES;
        [view removeFromSuperview];
    }
}

%end


%hook IESLiveFlowGuidanceFragment

+ (BOOL)componentShouldActive:(id)attacher {
    if (DYYYGetBool(@"DYYYHideLiveRoomShareCompanion")) {
        return NO;
    }
    return %orig;
}

%end


%hook IESLiveFlowGuidanceAdView

- (void)layoutSubviews {
    if (DYYYGetBool(@"DYYYHideLiveRoomShareCompanion")) {
        self.hidden = YES;
        [self removeFromSuperview];
        return;
    }
    %orig;
}

- (void)didMoveToSuperview {
    if (DYYYGetBool(@"DYYYHideLiveRoomShareCompanion")) {
        if (self.superview) {
            self.hidden = YES;
            [self removeFromSuperview];
        }
        return;
    }
    %orig;
}

%end

