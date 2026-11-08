// DKAudioProbe.h — 音频专项已移除；此头仅保留声明以兼容历史 import。
#ifndef DKAudioProbe_h
#define DKAudioProbe_h
#import <Foundation/Foundation.h>

extern const double DKAudioProbeWarmupSeconds;
extern const double DKAudioProbeRecordSeconds;
extern const double DKAudioProbeTotalSeconds;

@interface DKAudioProbeCapture : NSObject
@property (nonatomic, copy) NSString *declaredState;
@property (nonatomic, copy) NSString *actualState;
@property (nonatomic, strong) NSDictionary *sessionJSON;
@property (nonatomic, strong) NSArray *backendsJSON;
@property (nonatomic, copy) NSString *timelineJSONL;
@property (nonatomic, copy) NSString *signalJSONL;
@property (nonatomic, strong) NSArray *mediaSnapshotsJSON;
@property (nonatomic, strong) NSDictionary *glassTargetJSON;
@property (nonatomic, strong) NSDictionary *diagnosticsJSON;
@property (nonatomic, copy) NSString *summaryText;
@property (nonatomic, strong) NSArray<NSDictionary *> *pcmFiles;
@end

#ifdef __cplusplus
extern "C" {
#endif

void DKAudioProbeInstallIfEnabled(BOOL launchPhase);
void DKAudioProbePreferenceDidChange(void);
BOOL DKAudioProbeHasLaunchCoverage(void);
BOOL DKAudioProbeIsCaptureActive(void);
double DKAudioProbeCurrentCaptureSecond(void);
BOOL DKAudioProbeStartCapture(NSString *declaredState);
void DKAudioProbeStopCapture(void);
DKAudioProbeCapture *DKAudioProbeBuildCapture(NSArray *mediaSnapshots, NSDictionary *glassTarget);
NSDictionary *DKAudioProbeSessionSnapshot(void);
void DKAudioProbeRecordObjectDetails(NSString *name, id object, NSDictionary *details);
NSArray *DKAudioProbeObservedObjects(void);

#ifdef __cplusplus
}
#endif

#endif
