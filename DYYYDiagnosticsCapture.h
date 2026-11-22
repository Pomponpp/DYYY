//
//  DYYYDiagnosticsCapture.h
//  DYYY 诊断系统 · 页面快照
//
//  抓取当前页面的运行时快照（窗口/视图树/VC 树/图层/截图/本页类），
//  产出只含"已算好数据"的 DYYYDiagnosticsContext，交给 Export 落盘。
//

#ifndef DYYY_DIAGNOSTICS_CAPTURE_H
#define DYYY_DIAGNOSTICS_CAPTURE_H

#import <UIKit/UIKit.h>

/// 一次页面快照的产物（纯数据；序列化由 Export 负责）。
@interface DYYYDiagnosticsContext : NSObject
@property (nonatomic, strong) NSDictionary *metadata;
@property (nonatomic, strong) NSArray *windowsJSON;
@property (nonatomic, strong) NSArray *viewTreeJSON;
@property (nonatomic, copy) NSString *viewTreeText;
@property (nonatomic, strong) NSDictionary *selectedViewJSON;
@property (nonatomic, copy) NSString *viewControllersText;
@property (nonatomic, strong) NSArray *layersJSON;
@property (nonatomic, strong) NSData *screenshotPNG;
@property (nonatomic, copy) NSString *summary;
@property (nonatomic, strong) NSArray<NSString *> *pageClassNames;
@property (nonatomic, weak) UIView *sourceView;
@property (nonatomic, weak) UIViewController *presenter;
@end

#ifdef __cplusplus
extern "C" {
#endif

/// 前台全部可见窗口（排除调试自身窗口），按系统返回顺序。
NSArray<UIWindow *> *DYYYDiagActiveWindows(void);

/// 前台 key 窗口（排除调试自身窗口）。
UIWindow *DYYYDiagTargetWindow(void);

/// 某窗口当前最顶层的 VC（穿透 present/nav/tab）。
UIViewController *DYYYDiagTopPresenter(UIWindow *window);

/// 抓取一次页面快照。
DYYYDiagnosticsContext *DYYYDiagCaptureContext(UIWindow *targetWindow, CGPoint point, UIView *selectedView);

#ifdef __cplusplus
}
#endif

#endif /* DYYY_DIAGNOSTICS_CAPTURE_H */
