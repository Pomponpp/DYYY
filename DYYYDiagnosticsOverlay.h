//
//  DYYYDiagnosticsOverlay.h
//  DYYY 诊断系统 · 浮窗扳手
//

#ifndef DYYY_DIAGNOSTICS_OVERLAY_H
#define DYYY_DIAGNOSTICS_OVERLAY_H

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

/// 安装浮窗（全局扳手）：独立高层级 window，hidden 待命。
void DYYYDiagnosticsOverlayInstall(void);

/// 按开关刷新浮窗显隐（开关关闭时隐藏并归还 key window）。
void DYYYDiagnosticsOverlayRefresh(void);

#ifdef __cplusplus
}
#endif

#endif /* DYYY_DIAGNOSTICS_OVERLAY_H */
