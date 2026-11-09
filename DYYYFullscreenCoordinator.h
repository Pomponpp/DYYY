#import <UIKit/UIKit.h>

/// 按播放页承载结构协调全屏、底栏与评论避让，保留来源例外；不修改 Metal 渲染视图。
@interface DYYYFullscreenCoordinator : NSObject
+ (NSString *)buildIdentifier;
+ (BOOL)usesRecommendedLayoutForController:(UIViewController *)controller;
+ (BOOL)usesDetailLayoutForController:(UIViewController *)controller;
+ (BOOL)usesFullscreenLayoutForController:(UIViewController *)controller;
+ (CGRect)frameForPureModeContainer:(UIViewController *)controller proposed:(CGRect)frame;
// 详情页全屏（对齐验证过的机制）：
//   adjustDetailTableFrame 是表高的唯一写入通道；
//   prepareDetailTableNew 供建行/落点/翻页入口在放行原生之前同步表高；
//   detailRowHeight 只"回答"行高，不改写任何东西。
+ (UIViewController *)controllerForTable:(UITableView *)table;
+ (void)prepareDetailTableNew:(UIViewController *)controller;
// 首页 feed 表撑高：由 AWEFeedTableViewController 布局前后调用。
// 必须早于 cell 排版，否则表变高而 cell 仍按旧高度排，造成网格错位。
+ (void)syncFeedTableHeight:(UIViewController *)controller;
+ (CGRect)adjustDetailTableFrame:(UIView *)table frame:(CGRect)frame;
+ (CGRect)adjustDetailTableFrame:(UIView *)table frame:(CGRect)frame target:(CGFloat)target;
+ (double)detailRowHeight:(UITableView *)table nativeHeight:(double)nativeHeight;
+ (void)alignExistingCellsIfNeeded:(UITableView *)table target:(CGFloat)target;
+ (CGFloat)heightForDetailRow:(CGFloat)height table:(UITableView *)table controller:(UIViewController *)controller;
+ (BOOL)layoutNativeInteraction:(UIViewController *)controller;
+ (BOOL)isImageContentController:(UIViewController *)controller;
+ (void)registerTabBar:(UIView *)tabBar;
+ (BOOL)tabBarHostsProfilePage:(UIView *)bar;
+ (void)invalidateGuides;
+ (CGFloat)bottomOccupiedHeightForView:(UIView *)view;
+ (void)layoutBottomInput:(UIView *)view controller:(UIViewController *)controller;
+ (void)layoutInteraction:(UIViewController *)controller;
+ (void)layoutInformationLabel:(UIView *)label;
+ (void)rememberInteractionGuide:(UIViewController *)controller;
+ (CGRect)frameForInteractionView:(UIView *)view proposed:(CGRect)frame;
+ (CGRect)boundsForMediaHost:(UIView *)view proposed:(CGRect)bounds;
+ (CGPoint)centerForMediaHost:(UIView *)view proposed:(CGPoint)center;
+ (UIColor *)backgroundForBottomView:(UIView *)view proposed:(UIColor *)color;
+ (CGRect)frameForPlayer:(UIView *)player proposed:(CGRect)frame;
+ (void)preparePlayer:(UIView *)player;
+ (void)layoutPlayerContainer:(UIViewController *)controller;
+ (void)finishPlayer:(UIView *)player;
+ (CGAffineTransform)transformForImageView:(UIView *)view proposed:(CGAffineTransform)transform;
+ (void)layoutImageView:(UIView *)view;
+ (void)beginCommentInWindow:(UIWindow *)window;
+ (BOOL)hasCommentInWindow:(UIWindow *)window;
+ (void)commentController:(UIViewController *)controller visible:(BOOL)visible;
@end
