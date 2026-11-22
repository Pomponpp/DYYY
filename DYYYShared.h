//
//  DYYYShared.h
//  DYYY.xm 拆分后的跨文件共享声明。
//
//  内容 = 原 DYYY.xm 头部的 Category 声明（原样搬来，签名与主文件实现一致）。
//  分文件 #import 本头文件即可调用主文件 %new 提供的方法。
//
//  约定：新增跨文件方法时，声明加在这里（或主文件头部同步），否则 CI 编译失败。
//

#ifndef DYYY_SHARED_H
#define DYYY_SHARED_H

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import "AwemeHeaders.h"

@interface AWEFeedProgressSlider (DYYYProgressLabel)
- (NSString *)dyyy_formatTimeFromSeconds:(CGFloat)seconds;
- (CGFloat)dyyy_modelDurationInSeconds;
- (CGFloat)dyyy_scheduleVerticalOffset;
- (void)dyyy_removeScheduleLabels;
- (void)dyyy_updateScheduleLabelsWithCurrentTime:(CGFloat)currentTime totalDuration:(CGFloat)totalDuration;
@end

@interface AWEPlayInteractionProgressController (DYYYProgressLabel)
- (void)dyyy_syncScheduleLabelsWithCurrentTime:(CGFloat)currentTime totalDuration:(CGFloat)totalDuration;
@end

@interface AWEDProgressCoreContainer (DYYYProgressLabel)
- (void)dyyy_syncScheduleLabelsWithCurrentTime:(CGFloat)currentTime totalDuration:(CGFloat)totalDuration;
@end

@interface UIView (DYYYProgressLabelLegacy)
- (void)dyyy_updateScheduleLabelsLegacyWithCurrentTime:(CGFloat)currentTime totalDuration:(CGFloat)totalDuration model:(id)model;
@end

// 自定义图标加载（主文件实现）
UIImage *DYYYLoadCustomImage(NSString *fileName, CGSize targetSize);

#endif
