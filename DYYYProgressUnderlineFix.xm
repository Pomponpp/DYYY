//
//  DYYYProgressUnderlineFix.xm
//  DYYY
//
//  进度条容器：清除拖动/播放时出现的深色垫层背景（"黑线"）。
//
//  实现对齐已验证的机制：
//  · 只挂 AWEDPlayerProgressContainerView 一个类（首页视频/详情页视频的
//    进度容器），群聊视频页与图文页不碰；
//  · 只扫直接子视图且严格 UIView（isMemberOfClass）；
//  · 条件只有一条：亮度 < 0.2（深色系，含近黑）。
//  不匹配任何尺寸/位置条件，不改位置——避免与抖音布局循环互顶。
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import "AwemeHeaders.h"

%hook AWEDPlayerProgressContainerView

- (void)layoutSubviews {
    %orig;

    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYEnableFullScreen"]) {
        return;
    }

    for (UIView *subview in self.subviews) {
        if ([subview isMemberOfClass:[UIView class]]) {
            UIColor *bgColor = subview.backgroundColor;
            if (bgColor) {
                CGFloat h, s, v, a;
                if ([bgColor getHue:&h saturation:&s brightness:&v alpha:&a]) {
                    if (v < 0.2) {
                        subview.backgroundColor = [UIColor clearColor];
                    }
                }
            }
        }
    }
}

%end
