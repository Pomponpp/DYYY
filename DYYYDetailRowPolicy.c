//
//  DYYYDetailRowPolicy.c
//  详情页行高回答策略：唯一决策点。
//
//  方向（回归 #152 语义）：抖音原生在非全屏下按"屏高 − 底栏"给行高（iPhone 13 Pro Max
//  上 926 − 83 = 843）。全屏时我们要行高等于满视口，所以把"原生压缩高"映射到
//  "撑高目标"，让建行、落点、翻页吸附看到同一个数，避免 843/926 逐帧互斥。
//
//  为什么不能"一律透传原生"：
//    表已被撑到 926 而行高仍答 843 时，UIKit 按 843 建行、表却 926，
//    cell 之间会留下 83 的空档，cell 高度由两套来源交替写回，
//    表现为详情页上下错位与进度条拖动跳动。
//
//  两条映射规则（只在这两个值之间做替换，其它一律透传，保护特殊行）：
//    1. 已记录原生压缩高：native ≈ 原高 或 native ≈ 目标  → 答目标
//    2. 原高未知（首建行 / 表未撑高 / 查询来自滚动容器）：
//       native 本身已是被底栏压缩过的满屏高（与窗口高差 0.5~160）→ 答窗口高
//
//  纯 C、无 UIKit 依赖，宿主机可直接编译验证（见 tests/DetailRowPolicyTests.c）。
//

#include "DYYYDetailRowPolicy.h"

#include <math.h>

static const double kDYYYRowTol = 0.5;

/// 底栏占据的高度上限：超过这个差值说明对方不是"满屏减去底栏"，
/// 而是窄条/特殊行（如 100pt 的广告行），必须透传。
static const double kDYYYRowMaxCompression = 160.0;

double DYYYDetailRowHeightAnswer(int enabled, int isDetail,
                                 double nativeHeight, double tableHeight,
                                 double originalHeight, double pinnedHeight,
                                 double windowHeight) {
    if (!enabled || !isDetail) return nativeHeight;
    if (!isfinite(nativeHeight) || nativeHeight <= 0.0) return nativeHeight;

    /* 撑高目标：钉住值优先，其次取当前表视口高（两者取大）。 */
    double target = NAN;
    if (isfinite(pinnedHeight) && pinnedHeight > 0.0) target = pinnedHeight;
    if (isfinite(tableHeight) && tableHeight > 0.0
        && (!isfinite(target) || tableHeight > target)) {
        target = tableHeight;
    }

    /* 规则 1：原高已知 —— 只映射"原高 ↔ 目标"这两个值。 */
    if (isfinite(originalHeight) && originalHeight > 0.0 && isfinite(target)) {
        if (fabs(nativeHeight - originalHeight) <= kDYYYRowTol) return target;
        if (fabs(nativeHeight - target) <= kDYYYRowTol) return target;
        return nativeHeight;
    }

    /* 规则 2：原高未知 —— 只有"满屏减去底栏"的 native 才替换成窗口高。 */
    if (isfinite(windowHeight) && windowHeight > 0.0 && nativeHeight >= windowHeight * 0.5) {
        double diff = windowHeight - nativeHeight;
        if (fabs(diff) <= kDYYYRowTol) return windowHeight;
        if (diff > kDYYYRowTol && diff <= kDYYYRowMaxCompression) return windowHeight;
    }

    return nativeHeight;
}
