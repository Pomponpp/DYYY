//
//  DYYYFullscreenCore.h
//  DYYY
//
//  视频全屏 —— 按行为对照的三层结构重写。
//
//  第 1 层 几何拦截（唯一写入点）
//      全局 UIView setFrame: 单点分派，按写入方身份：
//        AWEDPlayerViewController_Merge   → 视频容器
//        AWEPlayInteractionViewController → HUD
//        其它                             → 一律放行
//      理由：两个各自改值的拦截器会争夺同一个返回值，谁最后写谁赢。
//
//  第 2 层 表撑高 + HUD 钉位
//      表高守卫 current >= target - 容差 → 放行（没被压缩过就不撑）；
//      HUD 只向下压，拿不到「表撑高前的原高」就放行。
//      两条都靠「表是否被撑高」这一个事实分叉，聊天页/搜索页自动出圈。
//
//  第 3 层 容器补钉
//      willDisplay + viewDidLayoutSubviews 双入口，都调同一幂等函数。
//
//  这三层之外的东西（图文、卡片、直播、清屏视口）是「撑高之后的连带影响」，
//  在 DYYYFullscreenChrome 里，不属于本文件。
//

#ifndef DYYY_FULLSCREEN_CORE_H
#define DYYY_FULLSCREEN_CORE_H

#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 全屏总开关。
BOOL DYYYFullscreenCoreOn(void);

/// 视频容器（Merge 根视图）此刻应有的 frame；算不出来返回 CGRectNull。
CGRect DYYYFullscreenContainerTarget(UIView *view);

/// 两个矩形是否已经一致（容差覆盖 @3x 亚像素漂移）。
BOOL DYYYFullscreenRectsClose(CGRect lhs, CGRect rhs);

/// 视频表撑高：写入时拦截与布局前后同步共用这一个函数。
CGRect DYYYFullscreenTableAdjust(UITableView *table, CGRect frame, CGFloat target);

/// 表撑高前的高度；没被撑高过返回 nil。
NSNumber *DYYYFullscreenTableOriginalHeight(UIView *table);

/// 该视图所在的视频表；不在表内返回 nil。
UIView *DYYYFullscreenTableForView(UIView *view);

/// 详情页行高：带「表被撑高过」前提，拿不到原高就回答原生值。
double DYYYFullscreenRowHeight(UITableView *table, double nativeHeight);

/// HUD 高度钉位：只向下压，不向上拉。返回 CGRectNull 表示放行。
CGRect DYYYFullscreenHUDAdjust(UIView *view, CGRect frame);

/// 容器补钉（幂等）：把 Merge 根视图按目标 frame 放好。
BOOL DYYYFullscreenPinContainer(UIViewController *merge);

/// 背景色延伸：非满屏视频（横屏/低比例）容器被钉高后，
/// 把露出来的那层祖先涂成播放器原生背景色，消除底部黑边。
void DYYYFullscreenSyncBackdrop(UIViewController *controller);

/// 供 .xm 侧递增统计（Logos 块里不能直接改 .m 的 static 变量）。
void DYYYFullscreenNotePin(BOOL willDisplay);
void DYYYFullscreenNoteTableWrite(void);
void DYYYFullscreenNoteHUDLayoutFallback(void);

/// 关闭开关时立刻把表高还回去。
void DYYYFullscreenRestoreTables(void);

/// 各层命中统计，供诊断读取。
NSString *DYYYFullscreenStats(void);

#ifdef __cplusplus
}
#endif

#endif /* DYYY_FULLSCREEN_CORE_H */
