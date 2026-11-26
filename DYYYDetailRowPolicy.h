//
//  DYYYDetailRowPolicy.h
//  详情页行高回答策略 —— 无 UIKit 依赖的纯决策函数，可在宿主机直接验证。
//
//  背景：41.1 重构确定"行高交还抖音原生（843），全屏视觉由容器撑满补偿"，
//  但遗留的回答路径在表已撑高时仍答 926，与抖音内部 843 写入逐帧互斥，
//  造成 cell 几何震荡（41.1 实测一秒 46 次交替），下游互动层/文案/进度条
//  全部继承震荡，表现为详情页上下错位与进度条拖动跳动。
//

#ifndef DYYY_DETAIL_ROW_POLICY_H
#define DYYY_DETAIL_ROW_POLICY_H

#ifdef __cplusplus
extern "C" {
#endif

/// 详情页行高询问的唯一决策点。
/// @param enabled       全屏开关
/// @param isDetail      是否详情页表
/// @param nativeHeight  抖音原生回答的行高
/// @param tableHeight   当前表视口高
/// @param originalHeight 记录的原生压缩高（NAN = 未记录）
/// @param pinnedHeight  撑高目标（NAN = 无）
/// @param windowHeight  窗口高
/// @return 最终回答给 UIKit 的行高
double DYYYDetailRowHeightAnswer(int enabled, int isDetail,
                                 double nativeHeight, double tableHeight,
                                 double originalHeight, double pinnedHeight,
                                 double windowHeight);

#ifdef __cplusplus
}
#endif

#endif /* DYYY_DETAIL_ROW_POLICY_H */
