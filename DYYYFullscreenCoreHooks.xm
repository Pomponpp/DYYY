//
//  DYYYFullscreenCoreHooks.xm
//  DYYY
//
//  视频全屏的钩子层 —— 对应 DYYYFullscreenCore 的三层。
//
//  全项目只有这一个全局 UIView setFrame: 钩子。分派按「写入方身份」：
//    · AWEDPlayerViewController_Merge   → 视频容器，一套规则通吃所有页面；
//    · AWEPlayInteractionViewController → HUD，只有撑高过的表需要钉位。
//  其它写入方一律放行。
//
//  为什么这一处必须是写入时拦截、不能改成事后纠正：
//    写入时拦截承担 95% 以上的修正量；改成事后纠正等于把上百次修正
//    压给布局回合，必然可见跳动。
//

#import "DYYYFullscreenCore.h"
#import "AwemeHeaders.h"
#import <objc/runtime.h>
#import <math.h>

// 供 .xm 侧递增统计（Logos 块里不能直接改 .m 的 static 变量）。
void DYYYFullscreenNotePin(BOOL willDisplay);
void DYYYFullscreenNoteTableWrite(void);
void DYYYFullscreenNoteHUDLayoutFallback(void);

#pragma mark - 分派

// 这条钩子挂在全局 UIView 上，抖音每一次 frame 写入都会经过，
// 守卫必须极便宜：只取一次 nextResponder、最多两次类型判断。
static CGRect DYYYAdjustFrame(UIView *view, CGRect frame) {
    UIResponder *owner = view.nextResponder;
    if (!owner) return CGRectNull;

    static Class mergeClass;
    static Class interactionClass;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      mergeClass = NSClassFromString(@"AWEDPlayerViewController_Merge");
      interactionClass = NSClassFromString(@"AWEPlayInteractionViewController");
    });

    if (mergeClass && [owner isKindOfClass:mergeClass]) {
        CGRect target = DYYYFullscreenContainerTarget(view);
        if (CGRectIsNull(target) || DYYYFullscreenRectsClose(frame, target)) return CGRectNull;
        return target;
    }
    if (interactionClass && [owner isKindOfClass:interactionClass]) {
        return DYYYFullscreenHUDAdjust(view, frame);
    }
    return CGRectNull;
}

#pragma mark - 第 1 层：全局写入拦截

%hook UIView

- (void)setFrame:(CGRect)frame {
    CGRect adjusted = DYYYAdjustFrame(self, frame);
    if (CGRectIsNull(adjusted)) {
        %orig;
        return;
    }
    %orig(adjusted);
}

%end

#pragma mark - 第 2 层：表撑高

%hook AWEFeedDataSafeTableView

- (void)setFrame:(CGRect)frame {
    if (!DYYYFullscreenCoreOn() || !NSThread.isMainThread) {
        %orig;
        return;
    }
    UIView *parent = self.superview;
    CGFloat target = parent ? CGRectGetHeight(parent.bounds) : 0.0;
    CGRect adjusted = DYYYFullscreenTableAdjust(self, frame, target);
    if (CGRectIsNull(adjusted)) {
        %orig;
        return;
    }
    DYYYFullscreenNoteTableWrite();
    %orig(adjusted);
}

%end

// 首页表是独立类，不继承上面的基类，走同一规则。
%hook AWEFeedTableView

- (void)setFrame:(CGRect)frame {
    if (!DYYYFullscreenCoreOn() || !NSThread.isMainThread) {
        %orig;
        return;
    }
    UIView *parent = self.superview;
    CGFloat target = parent ? CGRectGetHeight(parent.bounds) : 0.0;
    CGRect adjusted = DYYYFullscreenTableAdjust(self, frame, target);
    if (CGRectIsNull(adjusted)) {
        %orig;
        return;
    }
    DYYYFullscreenNoteTableWrite();
    %orig(adjusted);
}

%end

// 原生控制器布局【前后】各同步一次子表：
// Auto Layout 应用后、原生布局前统一表高，使尺寸适配器按同一高度
// 计算行高与滚动锚点。两阶段分别计数，便于诊断哪一段在起作用。
static void DYYYSyncTable(UITableView *table) {
    if (!table) return;
    UIView *parent = table.superview;
    CGFloat target = parent ? CGRectGetHeight(parent.bounds) : 0.0;
    CGRect adjusted = DYYYFullscreenTableAdjust(table, table.frame, target);
    if (CGRectIsNull(adjusted)) return;
    table.frame = adjusted;
    DYYYFullscreenNoteTableWrite();
}

%hook AWEFeedTableViewController

- (void)viewDidLayoutSubviews {
    if (DYYYFullscreenCoreOn()) DYYYSyncTable(self.tableView);
    %orig;
    if (!DYYYFullscreenCoreOn()) return;
    DYYYSyncTable(self.tableView);
}

%end

%hook AWEAwemeDetailTableViewController

- (void)viewDidLayoutSubviews {
    if (DYYYFullscreenCoreOn()) DYYYSyncTable(self.tableView);
    %orig;
    if (!DYYYFullscreenCoreOn()) return;
    DYYYSyncTable(self.tableView);
}

%end

#pragma mark - 第 2 层：详情页行高（7 入口同源）

// 每个入口都先「准备表」（撑高 + 记原高），再按同一纯函数回答行高，
// 保证建行 / 落点 / 翻页看到同一个高度。

%hook AWEAwemeDetailTableViewController

- (void)setupDetailTableView {
    %orig;
    if (DYYYFullscreenCoreOn()) DYYYSyncTable(self.tableView);
}

- (void)viewWillLayoutSubviews {
    if (DYYYFullscreenCoreOn()) DYYYSyncTable(self.tableView);
    %orig;
    if (DYYYFullscreenCoreOn()) DYYYSyncTable(self.tableView);
}

- (double)fixedCellHeight {
    if (!DYYYFullscreenCoreOn()) return %orig;
    UITableView *table = self.tableView;
    DYYYSyncTable(table);
    double native = %orig;
    return DYYYFullscreenRowHeight(table, native);
}

- (double)cellHeightAtIndex:(long long)index {
    if (!DYYYFullscreenCoreOn()) return %orig;
    UITableView *table = self.tableView;
    DYYYSyncTable(table);
    double native = %orig;
    return DYYYFullscreenRowHeight(table, native);
}

- (double)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (!DYYYFullscreenCoreOn()) return %orig;
    DYYYSyncTable(table);
    double native = %orig;
    return DYYYFullscreenRowHeight(table, native);
}

- (double)contentOffsetYForCellAtIndex:(long long)index {
    if (DYYYFullscreenCoreOn()) DYYYSyncTable(self.tableView);
    return %orig;
}

- (void)adjustTableViewHeightForTargetIndex:(long long)index {
    if (DYYYFullscreenCoreOn()) DYYYSyncTable(self.tableView);
    %orig;
    if (DYYYFullscreenCoreOn()) DYYYSyncTable(self.tableView);
}


%end

#pragma mark - 第 2 层：HUD 布局后兜底

%hook AWEPlayInteractionViewController

- (void)viewDidLayoutSubviews {
    %orig;

    if (!DYYYFullscreenCoreOn()) return;
    UIView *view = self.viewIfLoaded;
    if (!view) return;

    UIView *table = DYYYFullscreenTableForView(view);
    NSNumber *original = table ? DYYYFullscreenTableOriginalHeight(table) : nil;
    // 表没被撑高过 → 这页不在作用域，HUD 跟着页面走。
    if (!original) return;

    CGFloat pinned = original.doubleValue;
    if (!isfinite(pinned) || pinned <= 0.0) return;

    CGRect frame = view.frame;
    BOOL fits = CGRectGetHeight(frame) <= pinned + kDYYYTolerance;
    if (fabs(CGRectGetMinY(frame)) <= kDYYYTolerance && fits) return;

    view.frame = CGRectMake(CGRectGetMinX(frame), 0.0, CGRectGetWidth(frame), pinned);
    DYYYFullscreenNoteHUDLayoutFallback();
}

%end

#pragma mark - 第 3 层：容器补钉（双入口）

%hook AWEDPlayerViewController_Merge

- (void)willDisplay {
    %orig;
    if (DYYYFullscreenPinContainer(self)) DYYYFullscreenNotePin(YES);
}

- (void)viewDidLayoutSubviews {
    %orig;
    if (DYYYFullscreenPinContainer(self)) DYYYFullscreenNotePin(NO);
}

%end

#pragma mark - 安装

%ctor {
    Class merge = NSClassFromString(@"AWEDPlayerViewController_Merge");
    Class interaction = NSClassFromString(@"AWEPlayInteractionViewController");
    Class detail = NSClassFromString(@"AWEAwemeDetailTableViewController");


    (void)merge;
    (void)interaction;
    // 诊断：把三层统计写进运行时日志，导出包里直接可读。
    // 每 3 秒一行，只在诊断开关打开时写，不刷屏。
    dispatch_async(dispatch_get_main_queue(), ^{
        static dispatch_source_t timer;
        if (timer) return;
        timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0,
                                       dispatch_get_main_queue());
        dispatch_source_set_timer(timer,
                                  dispatch_time(DISPATCH_TIME_NOW, 3ull * NSEC_PER_SEC),
                                  3ull * NSEC_PER_SEC, NSEC_PER_SEC / 2);
        dispatch_source_set_event_handler(timer, ^{
            if (!DYYYGetBool(@"DYYYDiagEntryEnabled")) return;
            static NSUInteger lastHash = 0;
            NSString *line = DYYYFullscreenStats();
            NSUInteger hash = line.hash;
            if (hash == lastHash) return;   // 没变化不重复写
            lastHash = hash;
            NSLog(@"[DYYY][core] %@", line);
            [DYYYDiagnostics appendRuntimeLogLine:
                [@"[DYYY][core] " stringByAppendingString:line]];
        });
        dispatch_resume(timer);
    });
}
