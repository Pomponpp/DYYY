#import <UIKit/UIKit.h>

/// 按播放页承载结构协调全屏、底栏与评论避让，保留来源例外；不修改 Metal 渲染视图。
@interface DYYYFullscreenCoordinator : NSObject
+ (NSString *)buildIdentifier;
+ (BOOL)usesRecommendedLayoutForController:(UIViewController *)controller;
+ (BOOL)usesDetailLayoutForController:(UIViewController *)controller;
+ (BOOL)usesFullscreenLayoutForController:(UIViewController *)controller;
+ (CGRect)frameForPureModeContainer:(UIViewController *)controller proposed:(CGRect)frame;
// 详情页全屏：
//   adjustDetailTableFrame 是表高的唯一写入通道（写入时拉满 + layout 兜底）；
//   fullCellHeightForNative 只"回答"行高，不改写任何东西（无状态纯函数）；
//   群聊视频页（IM 详情）不在作用域，见 isImDetailController: 注释。
+ (UIViewController *)controllerForTable:(UITableView *)table;
// 首页 feed 表撑高：由 AWEFeedTableViewController 布局前后调用。
// 必须早于 cell 排版，否则表变高而 cell 仍按旧高度排，造成网格错位。
+ (void)syncFeedTableHeight:(UIViewController *)controller;
+ (CGRect)adjustDetailTableFrame:(UIView *)table frame:(CGRect)frame;
+ (CGRect)adjustDetailTableFrame:(UIView *)table frame:(CGRect)frame target:(CGFloat)target;
+ (CGFloat)fullCellHeightForNative:(CGFloat)nativeHeight;
+ (BOOL)isImDetailController:(UIViewController *)controller;
// 数据层对象（非 UIView 子类）用 id 接收，内部走 nextResponder 链找 VC
+ (BOOL)isImDetailView:(id)view;
+ (void)setImDetailActive:(BOOL)active;
+ (BOOL)imDetailActive;
+ (BOOL)imDetailActiveOrNavTop;
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
+ (void)beginCommentInWindow:(UIWindow *)window;
+ (BOOL)hasCommentInWindow:(UIWindow *)window;
+ (void)commentController:(UIViewController *)controller visible:(BOOL)visible;
@end
