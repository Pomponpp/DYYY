//
//  DYYYDiagnosticsExport.h
//  DYYY 诊断系统 · 诊断包打包
//

#ifndef DYYY_DIAGNOSTICS_EXPORT_H
#define DYYY_DIAGNOSTICS_EXPORT_H

#import <Foundation/Foundation.h>
#import "DYYYDiagnosticsCapture.h"

/// ZIP 生成失败时，工作目录会被保留，路径放在 error.userInfo 的这个键上。
extern NSString *const DYYYDiagExportWorkingDirectoryKey;

/// 构建标识常量（Capture 的 metadata 与 README 使用）。
extern NSString * const DYYYDiagVersion;
extern NSString * const DYYYDiagBuildCommit;
extern NSString * const DYYYDiagBuildBranch;
extern NSString * const DYYYDiagBuildTime;

#ifdef __cplusplus
extern "C" {
#endif

/// 在后台线程生成导出包。失败时返回 nil，并通过 error 返回真实原因。
DYYYDiagnosticsExportResult *DYYYDiagCreateExport(DYYYDiagnosticsContext *context,
                                                  void (^progress)(NSString *text),
                                                  NSError **error);

/// 分享完成或取消后删除工作目录和 zip。
void DYYYDiagCleanupExport(DYYYDiagnosticsExportResult *result);

#ifdef __cplusplus
}
#endif

#endif /* DYYY_DIAGNOSTICS_EXPORT_H */
