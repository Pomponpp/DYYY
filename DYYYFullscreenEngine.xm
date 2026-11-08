// DYYYFullscreenEngine.xm
// 详情页全屏引擎：表撑高单一写入通道 + 建行/落点/分页同源纪律。
//
// 机制要点（长期验证过的四条纪律）：
//   1. 单一写入通道：表高度只在 setFrame: 出口顶回，控制器布局前/后各同步一次；
//      行高查询只"回答"，不再开第二个改高度的口子。
//   2. 同源同刻：fixedCellHeight / cellHeightAtIndex / delegate 行高三个入口
//      先准备表再回答；contentOffsetYForCellAtIndex（落点）与
//      adjustTableViewHeightForTargetIndex（翻页）在 %orig 前后都准备——
//      建行、落点、分页永远看到同一个表状态，消除点A弹B的时序根源。
//   3. 不碰 inset：baseTableViewBottomInset 完全交还原生，
//      全屏视觉 = 表被顶到容器满高，抖音认知与实际高度不再打架。
//   4. 关闭即透明：开关关闭时清掉撑高标记并立刻还原表高，不留状态。
//
// 比例/尺寸全部运行时量取（superview.bounds），无硬编码高度。

#import "AwemeHeaders.h"
#import "DYYYFullscreenEngine.h"
#import <objc/runtime.h>
#import <math.h>

// 覆盖 @3x 亚像素漂移。
static const CGFloat kDYYYEngineTolerance = 0.5;
// 表高达到容器的这个比例才认作"只差一个底栏"，排除布局早期半成品尺寸。
static const CGFloat kDYYYEngineMinHeightRatio = 0.5;

static BOOL gDYYYEngineHooksInstalled = NO;

// 撑高前的原高（HUD 钉位与还原依据），以及所有撑高过的表（关闭时立刻还原）。
static char kDYYYEngineOriginalHeightKey;
static NSHashTable<UITableView *> *gDYYYStretchedTables = nil;

static BOOL DYYYFullscreenEngineOn(void) {
    return DYYYGetBool(@"DYYYEnableFullScreen");
}

#pragma mark - 命中统计（诊断包可读）

static struct {
    NSUInteger tableSetFrame, layoutSync, prepareRuns, prepareChanges;
    NSUInteger fixedRuns, fixedChanges, indexRuns, indexChanges, rowRuns, rowChanges;
} gDYYYEngineStats;

NSString *DYYYFullscreenEngineStats(void) {
    return [NSString stringWithFormat:
        @"引擎=%@ 表setFrame顶回=%lu 布局同步=%lu 准备跑=%lu 准备改=%lu "
        @"固定行高跑=%lu 改=%lu 索引行高跑=%lu 改=%lu 代理行高跑=%lu 改=%lu",
        gDYYYEngineHooksInstalled ? @"已装" : @"入口缺失",
        (unsigned long)gDYYYEngineStats.tableSetFrame,
        (unsigned long)gDYYYEngineStats.layoutSync,
        (unsigned long)gDYYYEngineStats.prepareRuns,
        (unsigned long)gDYYYEngineStats.prepareChanges,
        (unsigned long)gDYYYEngineStats.fixedRuns,
        (unsigned long)gDYYYEngineStats.fixedChanges,
        (unsigned long)gDYYYEngineStats.indexRuns,
        (unsigned long)gDYYYEngineStats.indexChanges,
        (unsigned long)gDYYYEngineStats.rowRuns,
        (unsigned long)gDYYYEngineStats.rowChanges];
}

#pragma mark - 撑高规则（唯一改高度的地方）

// 返回 CGRectNull = 放行不干预。
static CGRect DYYYEngineAdjustFrameToHeight(UITableView *table, CGRect frame, CGFloat target) {
    if (!DYYYFullscreenEngineOn()) {
        // 关闭一律放行并清标记，抖音写什么就是什么。
        objc_setAssociatedObject(table, &kDYYYEngineOriginalHeightKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return CGRectNull;
    }
    CGFloat current = CGRectGetHeight(frame);
    if (!isfinite(target) || !isfinite(current) || target <= 0.0
        || current >= target - kDYYYEngineTolerance
        || current < target * kDYYYEngineMinHeightRatio) {
        return CGRectNull;
    }
    if (!objc_getAssociatedObject(table, &kDYYYEngineOriginalHeightKey)) {
        objc_setAssociatedObject(table, &kDYYYEngineOriginalHeightKey, @(current), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [gDYYYStretchedTables addObject:table];
        if (DYYYGetBool(@"DYYYFullscreenDiag")) {
            NSLog(@"[DYYY][engine] 记原高=%.1f 顶高=%.1f", current, target);
        }
    }
    frame.size.height = target;
    return frame;
}

static CGRect DYYYEngineAdjustTableFrame(UITableView *table, CGRect frame) {
    UIView *parent = table.superview;
    if (!parent) return CGRectNull;
    return DYYYEngineAdjustFrameToHeight(table, frame, CGRectGetHeight(parent.bounds));
}

// 控制器布局入口的准备：详情表建行前可能尚未入树，取控制器根视图高度。
static BOOL DYYYEnginePrepareForController(UIViewController *controller, UITableView *table) {
    if (!DYYYFullscreenEngineOn() || !NSThread.isMainThread || !table) return NO;
    UIView *root = controller.viewIfLoaded;
    if (!root) return NO;
    UIWindow *window = table.window ?: root.window;
    if (window && window.windowLevel != UIWindowLevelNormal) return NO;
    if (table.superview && ![table isDescendantOfView:root]) return NO;
    if (!CGAffineTransformIsIdentity(table.transform)) return NO;

    CGFloat target = table.superview ? CGRectGetHeight(table.superview.bounds)
                                     : CGRectGetHeight(root.bounds);
    gDYYYEngineStats.prepareRuns++;
    CGRect adjusted = DYYYEngineAdjustFrameToHeight(table, table.frame, target);
    if (CGRectIsNull(adjusted)) return NO;
    table.frame = adjusted;
    gDYYYEngineStats.prepareChanges++;
    return YES;
}

// 行高只"回答"：表已撑高（bounds≈满视口且记有原高）时，整页行高答满视口；
// 特殊行（与两个基准都不符）透传；未接管透传。
static double DYYYEngineRowHeight(UITableView *table, double nativeHeight, NSUInteger *runs, NSUInteger *changes) {    if (!DYYYFullscreenEngineOn() || !NSThread.isMainThread || !table) return nativeHeight;
    (*runs)++;
    NSNumber *original = objc_getAssociatedObject(table, &kDYYYEngineOriginalHeightKey);
    CGFloat target = CGRectGetHeight(table.bounds);
    if (!original || !isfinite(nativeHeight) || !isfinite(target)
        || nativeHeight <= 0.0 || target <= original.doubleValue + kDYYYEngineTolerance) {
        return nativeHeight;
    }
    if (fabs(nativeHeight - original.doubleValue) > kDYYYEngineTolerance
        && fabs(nativeHeight - target) > kDYYYEngineTolerance) {
        return nativeHeight;
    }
    if (fabs(nativeHeight - target) > kDYYYEngineTolerance) (*changes)++;
    return target;
}

#pragma mark - 对外查询（HUD 钉位与诊断用）

// 该视图所在视频表撑高前的原高；不在撑高作用域内返回 0。
// DYYY 的 HUD/底部控件布局据此保持原生位置，不随表撑高整体下移。
CGFloat DYYYEngineOriginalHeightForView(UIView *view) {
    if (!DYYYFullscreenEngineOn()) return 0.0;
    UIView *ancestor = view.superview;
    Class tableCls = NSClassFromString(@"AWEFeedDataSafeTableView");
    for (NSUInteger i = 0; ancestor && i < 8; i++, ancestor = ancestor.superview) {
        if (tableCls && [ancestor isKindOfClass:tableCls]) {
            NSNumber *original = objc_getAssociatedObject(ancestor, &kDYYYEngineOriginalHeightKey);
            return original.doubleValue;
        }
    }
    return 0.0;
}

#pragma mark - 表写入通道（视频表基类：首页与详情表共用）

%hook AWEFeedDataSafeTableView

- (void)setFrame:(CGRect)frame {
    CGRect adjusted = DYYYEngineAdjustTableFrame(self, frame);
    if (CGRectIsNull(adjusted)) {
        %orig;
        return;
    }
    gDYYYEngineStats.tableSetFrame++;
    %orig(adjusted);
}

%end

#pragma mark - 详情页控制器（建行/落点/分页同源纪律）

%hook AWEAwemeDetailTableViewController

- (void)setupDetailTableView {
    %orig;
    if (DYYYFullscreenEngineOn()) DYYYEnginePrepareForController(self, self.tableView);
}

- (void)viewWillLayoutSubviews {
    if (DYYYFullscreenEngineOn()) DYYYEnginePrepareForController(self, self.tableView);
    %orig;
    if (DYYYFullscreenEngineOn()) DYYYEnginePrepareForController(self, self.tableView);
}

- (double)fixedCellHeight {
    if (!DYYYFullscreenEngineOn()) return %orig;
    UITableView *table = self.tableView;
    DYYYEnginePrepareForController(self, table);
    double nativeHeight = %orig;
    return DYYYEngineRowHeight(table, nativeHeight, &gDYYYEngineStats.fixedRuns, &gDYYYEngineStats.fixedChanges);
}

- (double)cellHeightAtIndex:(long long)index {
    if (!DYYYFullscreenEngineOn()) return %orig;
    UITableView *table = self.tableView;
    DYYYEnginePrepareForController(self, table);
    double nativeHeight = %orig;
    return DYYYEngineRowHeight(table, nativeHeight, &gDYYYEngineStats.indexRuns, &gDYYYEngineStats.indexChanges);
}

- (double)tableView:(UITableView *)table heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (!DYYYFullscreenEngineOn()) return %orig;
    DYYYEnginePrepareForController(self, table);
    double nativeHeight = %orig;
    return DYYYEngineRowHeight(table, nativeHeight, &gDYYYEngineStats.rowRuns, &gDYYYEngineStats.rowChanges);
}

- (double)contentOffsetYForCellAtIndex:(long long)index {
    if (DYYYFullscreenEngineOn()) DYYYEnginePrepareForController(self, self.tableView);
    return %orig;
}

- (void)adjustTableViewHeightForTargetIndex:(long long)index {
    if (DYYYFullscreenEngineOn()) DYYYEnginePrepareForController(self, self.tableView);
    %orig;
    if (DYYYFullscreenEngineOn()) DYYYEnginePrepareForController(self, self.tableView);
}

%end

#pragma mark - 首页表控制器布局同步（Auto Layout 应用前后各一次）

static void DYYYEngineSyncTable(UITableView *table) {
    if (!table) return;
    gDYYYEngineStats.layoutSync++;
    CGRect adjusted = DYYYEngineAdjustTableFrame(table, table.frame);
    if (CGRectIsNull(adjusted)) return;
    table.frame = adjusted;
}

%hook AWEFeedTableViewController

- (void)viewDidLayoutSubviews {
    if (DYYYFullscreenEngineOn()) DYYYEngineSyncTable(self.tableView);
    %orig;
    if (DYYYFullscreenEngineOn()) DYYYEngineSyncTable(self.tableView);
}

%end

#pragma mark - 关闭还原

static void DYYYEngineRestore(void) {
    for (UITableView *table in gDYYYStretchedTables.allObjects) {
        NSNumber *original = objc_getAssociatedObject(table, &kDYYYEngineOriginalHeightKey);
        if (!original) continue;
        objc_setAssociatedObject(table, &kDYYYEngineOriginalHeightKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        CGRect frame = table.frame;
        frame.size.height = original.doubleValue;
        table.frame = frame;
    }
    [gDYYYStretchedTables removeAllObjects];
}

#pragma mark - 安装（方法存在性自检，改版断线自报告）

%ctor {
    gDYYYStretchedTables = [NSHashTable weakObjectsHashTable];

    Class detail = NSClassFromString(@"AWEAwemeDetailTableViewController");
    SEL required[] = {
        @selector(setupDetailTableView), @selector(viewWillLayoutSubviews),
        @selector(fixedCellHeight), @selector(cellHeightAtIndex:),
        @selector(tableView:heightForRowAtIndexPath:),
        @selector(contentOffsetYForCellAtIndex:),
        @selector(adjustTableViewHeightForTargetIndex:),
    };
    NSMutableArray<NSString *> *missing = [NSMutableArray array];
    for (SEL sel : required) {
        if (!detail || !class_getInstanceMethod(detail, sel)) {
            [missing addObject:NSStringFromSelector(sel)];
        }
    }
    if (missing.count == 0) {
        %init;
        gDYYYEngineHooksInstalled = YES;
    } else {
        NSLog(@"[DYYY][engine] 全屏引擎入口缺失，未安装：%@", [missing componentsJoinedByString:@", "]);
    }

    // 全屏开关关闭时立刻还原（自监听配置变化，不依赖设置页回调）。
    [NSNotificationCenter.defaultCenter addObserverForName:NSUserDefaultsDidChangeNotification
                                                    object:nil
                                                     queue:[NSOperationQueue mainQueue]
                                                usingBlock:^(__unused NSNotification *note) {
        DYYYFullscreenEngineOnToggle();
    }];
}

// 设置页开关关闭时调用：立刻还原所有撑高过的表。
void DYYYFullscreenEngineOnToggle(void) {
    if (!DYYYFullscreenEngineOn()) DYYYEngineRestore();
}
