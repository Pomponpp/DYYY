#import <UIKit/UIKit.h>

/// 按播放页承载结构协调全屏、底栏与评论避让，保留来源例外；不修改 Metal 渲染视图。
@interface DYYYFullscreenCoordinator : NSObject
+ (NSString *)buildIdentifier;
+ (BOOL)usesRecommendedLayoutForController:(UIViewController *)controller;
+ (BOOL)usesDetailLayoutForController:(UIViewController *)controller;
+ (BOOL)usesFullscreenLayoutForController:(UIViewController *)controller;
+ (CGRect)frameForPureModeContainer:(UIViewController *)controller proposed:(CGRect)frame;
+ (CGFloat)bottomInsetForDetail:(CGFloat)inset controller:(UIViewController *)controller;
+ (void)reconcileDetailPaging:(UIViewController *)controller;
// #31 详情页全屏闭环：建行/落点计算前主动准备表（撑满+记原高），
// 行高查询用同源规则回答。两者必须成对使用。
+ (void)prepareDetailTableNew:(UIViewController *)controller;
+ (double)detailRowHeight:(UITableView *)table nativeHeight:(double)nativeHeight;
+ (void)alignExistingCellsIfNeeded:(UITableView *)table target:(CGFloat)target;
+ (CGFloat)heightForDetailRow:(CGFloat)height table:(UITableView *)table controller:(UIViewController *)controller;
+ (BOOL)layoutNativeInteraction:(UIViewController *)controller;
+ (BOOL)isImageContentController:(UIViewController *)controller;
+ (void)registerTabBar:(UIView *)tabBar;
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
