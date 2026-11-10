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

@interface AWENowPlayingInfoCenter : NSObject
@property(nonatomic, weak) id playingPlayer;
@end

@interface MPNowPlayingInfoCenter : NSObject
@property(nonatomic, copy) NSDictionary *nowPlayingInfo;
+ (instancetype)defaultCenter;
@end