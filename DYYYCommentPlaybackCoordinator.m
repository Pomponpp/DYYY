#import "DYYYCommentPlaybackCoordinator.h"
#import "AwemeHeaders.h"
#import "AWMSafeDispatchTimer.h"
#import "DYYYFloatingButtonCoordinator.h"

@interface DYYYCommentPlaybackCoordinator ()
@property(nonatomic, strong) NSHashTable *viewModels;
@property(nonatomic, weak) UIViewController *commentController;
@property(nonatomic, strong) AWMSafeDispatchTimer *watchdog;
@property(nonatomic, weak) _TtC33AWECommentPanelContainerSwiftImpl30CommentContainerInnerViewModel *pausedViewModel;
@end

@implementation DYYYCommentPlaybackCoordinator

+ (instancetype)shared {
    static DYYYCommentPlaybackCoordinator *coordinator;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        coordinator = [self new];
        coordinator.viewModels = [NSHashTable weakObjectsHashTable];
    });
    return coordinator;
}

#pragma mark - 原生评论暂停与恢复

+ (void)registerViewModel:(id)viewModel {
    if (!viewModel) return;
    if (!NSThread.isMainThread) {
        __weak id weakViewModel = viewModel;
        dispatch_async(dispatch_get_main_queue(), ^{ [self registerViewModel:weakViewModel]; });
        return;
    }
    [[self shared].viewModels addObject:viewModel];
    [self pauseIfNeeded];
}

+ (void)pauseIfNeeded {
    DYYYCommentPlaybackCoordinator *coordinator = [self shared];
    if (!coordinator.commentController || coordinator.pausedViewModel || !DYYYGetBool(@"DYYYCommentPausePlayback")) return;

    AWEPlayInteractionViewController *current = (id)[DYYYFloatingButtonCoordinator currentInteractionController];
    id bestViewModel = nil;
    CGFloat bestScore = -CGFLOAT_MAX;
    for (_TtC33AWECommentPanelContainerSwiftImpl30CommentContainerInnerViewModel *viewModel in coordinator.viewModels.allObjects) {
        @try {
            if (![viewModel respondsToSelector:@selector(isFeedVideoPlaying)] || ![viewModel isFeedVideoPlaying]) continue;
            if (![viewModel respondsToSelector:@selector(pauseVideoIfPlayingWithoutShowingPauseIcon)]) continue;
            id player = [viewModel respondsToSelector:@selector(feedVideoPlayerController)] ? [viewModel feedVideoPlayerController] : nil;
            CGFloat score = 0;
            if ([player isKindOfClass:UIViewController.class]) {
                UIView *view = ((UIViewController *)player).viewIfLoaded;
                if (view.window && !view.hidden) {
                    CGRect rect = [view convertRect:view.bounds toView:view.window];
                    CGRect visible = CGRectIntersection(rect, view.window.bounds);
                    if (!CGRectIsNull(visible)) score = visible.size.width * visible.size.height;
                }
            }
            if (current && [player respondsToSelector:@selector(model)]) {
                AWEAwemeModel *model = [player model];
                if (model == current.model || (model.itemID.length && [model.itemID isEqualToString:current.model.itemID])) score += 1.0e12;
            }
            if (score > bestScore) { bestScore = score; bestViewModel = viewModel; }
        } @catch (__unused NSException *exception) {
        }
    }
    @try {
        // 使用 main 中的原生入口，保留宿主评论暂停状态和媒体预览的恢复约定。
        [bestViewModel pauseVideoIfPlayingWithoutShowingPauseIcon];
        coordinator.pausedViewModel = bestViewModel;
        [self startRecoveryWatchdog];
    } @catch (NSException *exception) {
        NSLog(@"[DYYY] 评论暂停失败：%@", exception.reason);
    }
}

// 冻结根修（41.1 实测）：恢复原本只挂在评论容器 viewDidDisappear，但 41.1
// 半屏评论是往窗口里加 subview，关闭时不走 disappear → 恢复永不执行，
// 播放器停在 rate=0：画面定格、弹幕照常、必须手动点暂停再播放才恢复。
// 兜底：暂停成功后轮询评论面板是否已脱离窗口，脱离即恢复播放。
+ (void)startRecoveryWatchdog {
    DYYYCommentPlaybackCoordinator *coordinator = [self shared];
    if (coordinator.watchdog.isRunning) return;
    if (!coordinator.watchdog) coordinator.watchdog = [AWMSafeDispatchTimer new];
    __weak UIViewController *panel = coordinator.commentController;
    __weak id paused = coordinator.pausedViewModel;
    [coordinator.watchdog startWithInterval:0.5 leeway:0.1 queue:dispatch_get_main_queue() repeats:YES handler:^{
      DYYYCommentPlaybackCoordinator *inner = [self shared];
      // 脱离窗口、被隐藏、或整层透明都视为评论已关闭（41.1 关闭方式不确定）。
      UIView *panelView = panel.viewIfLoaded;
      BOOL panelGone = !panel || !panelView.window || panelView.hidden || panelView.alpha < 0.01;
      if (!panelGone) return;
      id viewModel = inner.pausedViewModel ?: paused;
      inner.commentController = nil;
      inner.pausedViewModel = nil;
      [inner.watchdog cancel];
      @try {
          if ([viewModel respondsToSelector:@selector(recoverPlayIfPauseByComment)]) {
              [viewModel recoverPlayIfPauseByComment];
              NSLog(@"[DYYY] 评论面板已脱离窗口，看门狗恢复播放");
          }
      } @catch (__unused NSException *exception) {
      }
    }];
}

+ (void)commentController:(UIViewController *)controller visible:(BOOL)visible {
    if (!NSThread.isMainThread) {
        __weak UIViewController *weakController = controller;
        dispatch_async(dispatch_get_main_queue(), ^{ [self commentController:weakController visible:visible]; });
        return;
    }
    if (!controller) return;
    DYYYCommentPlaybackCoordinator *coordinator = [self shared];
    if (visible) {
        coordinator.commentController = controller;
        [self pauseIfNeeded];
        return;
    }
    if (coordinator.commentController != controller) return;
    if ([self shouldSkipLifecycle:controller]) return;
    id paused = coordinator.pausedViewModel;
    coordinator.commentController = nil;
    coordinator.pausedViewModel = nil;
    [coordinator.watchdog cancel];
    @try {
        if ([paused respondsToSelector:@selector(recoverPlayIfPauseByComment)]) [paused recoverPlayIfPauseByComment];
    } @catch (NSException *exception) {
        NSLog(@"[DYYY] 评论播放恢复失败：%@", exception.reason);
    }
}

+ (BOOL)ownsPlayback {
    return [self shared].pausedViewModel != nil;
}

+ (BOOL)shouldSkipLifecycle:(UIViewController *)controller {
    @try {
        if (![controller respondsToSelector:@selector(state)]) return NO;
        _TtC33AWECommentPanelContainerSwiftImpl31CommentViewControllerStateModel *state = [(AWECommentContainerViewController *)controller state];
        return [state respondsToSelector:@selector(isSkipCommentPanelLifecycle)] && state.isSkipCommentPanelLifecycle;
    } @catch (__unused NSException *exception) {
        return NO;
    }
}

@end
