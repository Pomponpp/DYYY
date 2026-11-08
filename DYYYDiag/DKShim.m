// DKShim.m — 诊断子系统对外部依赖的最小实现
// 音频专项/页面探针按需求移除：空实现占位保持原文件不动。
// 开关读取映射到 DYYY 配置；流水日志与状态指纹由 DKDYYYBridge 提供。
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import "Debug/DKDebugCapture.h"
#import "Shared/DKUtils.h"
#import "AwemeHeaders.h"


#pragma mark - 音频专项（已移除，空实现）

const double DKAudioProbeWarmupSeconds = 1.0;
const double DKAudioProbeRecordSeconds = 3.0;
const double DKAudioProbeTotalSeconds = 5.0;

@implementation DKAudioProbeCapture
@end

void DKAudioProbeInstallIfEnabled(BOOL launchPhase) { (void)launchPhase; }
void DKAudioProbePreferenceDidChange(void) {}
BOOL DKAudioProbeHasLaunchCoverage(void) { return NO; }
BOOL DKAudioProbeIsCaptureActive(void) { return NO; }
double DKAudioProbeCurrentCaptureSecond(void) { return -1; }
BOOL DKAudioProbeStartCapture(NSString *declaredState) { (void)declaredState; return NO; }
void DKAudioProbeStopCapture(void) {}
DKAudioProbeCapture *DKAudioProbeBuildCapture(NSArray *mediaSnapshots, NSDictionary *glassTarget) {
    (void)mediaSnapshots; (void)glassTarget; return nil;
}
NSDictionary *DKAudioProbeSessionSnapshot(void) { return @{}; }
void DKAudioProbeRecordObjectDetails(NSString *name, id object, NSDictionary *details) {
    (void)name; (void)object; (void)details;
}
NSArray *DKAudioProbeObservedObjects(void) { return @{}; }
NSDictionary *DKAudioRuntimeMediaSnapshot(void) { return @{}; }
NSDictionary *DKAudioRuntimeGlassTarget(void) { return @{}; }

#pragma mark - 页面探针（已移除，空报告）

NSString *DKTabBarProbeReport(void) { return @""; }

#pragma mark - 开关读取（映射到 DYYY 配置）

#pragma mark - DKUtils 依赖（玻璃/显示模式等，诊断链路不实际使用，空实现）

BOOL DKGlassOSAvailable(void) { return NO; }
BOOL DKGlassIsGatedKey(NSString *key) { (void)key; return NO; }
void DKGlassGuard(NSString *key) { (void)key; }

#pragma mark - ClassDump 私有根类


#pragma mark - 版本

NSString * const DKVersionString = @"2.2-9";
