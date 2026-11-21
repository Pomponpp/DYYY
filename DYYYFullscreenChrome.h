//
//  DYYYFullscreenChrome.h
//  DYYY
//
//  视频全屏的「页面装饰」层 —— 撑高之后的连带影响。
//
//  视频表被撑高一个底栏后，同表里的其它内容不会自动跟着变：
//    · 图文：内容仍按原高排，底部空出来；缩放交互仍按旧尺寸换算
//    · 卡片（特殊卡/音乐卡/POI/文章）：内容容器还停在原高
//    · 直播预览：chrome 挂在容器高度上，整体下移一个底栏
//    · 渐变/压暗：只铺到原内容底边
//
//  这一层统一用 transform 与约束 constant 处理，绝不动 frame：
//    改 frame 会与父布局互相追赶，主线程卡死 → 看门狗 0x8BADF00D。
//  transform 不参与 auto layout，约束求解不会重置它。
//

#ifndef DYYY_FULLSCREEN_CHROME_H
#define DYYY_FULLSCREEN_CHROME_H

#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 卡片类型（背景条取样按类型分开统计）。
typedef NS_ENUM(NSUInteger, DYYYCardType) {
    DYYYCardTypeSpecial = 0,
    DYYYCardTypeMusic,
    DYYYCardTypeArticle,
    DYYYCardTypeCount
};

/// 图文：抑制缩放（等价于视频的 videoDidShrink）。
void DYYYChromeSuppressRichShrink(id controller);

/// 图文：可见背景渐变拉伸到底（只叠 transform）。
void DYYYChromeStretchRichGradient(id gradient);

/// 图文：媒体按 Cell 居中（拦截 setTransform，保持原生缩放态）。
CGAffineTransform DYYYChromeRichCenterTransform(id view, CGAffineTransform native);

/// 图文：放开阻挡溢出的裁剪层。
void DYYYChromeAllowRichOverflow(id view);

/// 卡片：把内容容器与上层之间的底边约束收短 inset；inset 为 0 时还原。
BOOL DYYYChromeFitCard(id container, CGFloat inset, DYYYCardType type);

/// 卡片：宿主越过原生安全底边的高度；不在已撑高的表里返回 0。
CGFloat DYYYChromeCardInset(id view);

/// 卡片：背景条按内容底边取样并延伸（inset 为 0 时移除）。
void DYYYChromeSyncCardBackdrop(id host, CGFloat inset, DYYYCardType type);

/// 卡片：内容可能变化后安排取样（合并连续请求 + 稍后补一次）。
void DYYYChromeRequestBackdropSample(id host);

/// 直播预览：把挂在容器高度上的 chrome 抬回原位（只叠 transform）。
void DYYYChromeLiftLiveChrome(id container);

/// 视频：容器内非贴底的压暗渐变跟着撑满（只叠 transform）。
void DYYYChromeStretchVideoGradient(id gradient);

/// 评论态顶部黑遮罩：全屏时隐藏（它是「视频缩小」态的产物）。
void DYYYChromeHideStatusBarCover(id interaction);

/// 关闭开关时还原全部装饰层接管。
void DYYYChromeRestoreAll(void);

/// 统计，供诊断读取。
NSString *DYYYChromeStats(void);
NSString *DYYYChromeStatsDetail(void);

#ifdef __cplusplus
}
#endif

#endif /* DYYY_FULLSCREEN_CHROME_H */
