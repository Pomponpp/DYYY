//
//  DYYYDiagnosticsCompat.h
//  DYYY 诊断系统 · compat 三件套
//
//  ClassIsSafe / 类名过滤 / 单类头文件生成（基于 ObjC 运行时）
//  + 最小 ZIP 写入器（不压缩存储，zlib 算 CRC32，支持 ZIP64 条目计数）。
//

#ifndef DYYY_DIAGNOSTICS_COMPAT_H
#define DYYY_DIAGNOSTICS_COMPAT_H

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

/// 该类是否可安全内省（排除已知会崩的 Foundation 私有类）。
BOOL DYYYDiagClassIsSafe(Class cls);

/// 类名是否为运行时生成（KVO 子类 / block / Heimdallr / 性能监控子类）。
BOOL DYYYDiagClassNameIsRuntimeGenerated(NSString *name);

/// 生成单类头文件文本；不安全或畸形 Swift 名返回注释说明。
NSString *DYYYDiagClassDumpHeaderForClass(Class cls);

#ifdef __cplusplus
}
#endif

typedef void (^DYYYDiagZipProgressBlock)(CGFloat progress);

@interface DYYYDiagZipWriter : NSObject

+ (BOOL)createZipAtPath:(NSString *)zipPath
                rootDir:(NSString *)rootDir
                  files:(NSArray<NSString *> *)files
               progress:(DYYYDiagZipProgressBlock _Nullable)progress
                  error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

#endif /* DYYY_DIAGNOSTICS_COMPAT_H */
