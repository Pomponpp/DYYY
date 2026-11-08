// DYYYFullscreenEngine.h — 详情页全屏引擎（单一写入通道 + 同源纪律）
#ifndef DYYYFullscreenEngine_h
#define DYYYFullscreenEngine_h

#ifdef __cplusplus
extern "C" {
#endif

/// 引擎命中统计（诊断包可读）。
NSString *DYYYFullscreenEngineStats(void);

/// 全屏开关切换时调用：关闭则立刻还原所有撑高过的表。
void DYYYFullscreenEngineOnToggle(void);

/// 该视图所在视频表撑高前的原高；不在撑高作用域内返回 0。
/// HUD/底部控件按此钉位，保持原生位置不随表撑高下移。
CGFloat DYYYEngineOriginalHeightForView(UIView *view);

#ifdef __cplusplus
}
#endif

#endif
