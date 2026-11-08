//
//  DYYYDiagZip.h
//  DYKiller
//
//  调试导出使用的最小 ZIP 写入器。
//  以不压缩方式写入文件，使用 zlib 计算 CRC32，并支持 ZIP64 条目计数。
//

#ifndef DYYYDiagZip_h
#define DYYYDiagZip_h

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^DYYYDiagZipProgressBlock)(CGFloat progress);

@interface DYYYDiagZip : NSObject

+ (BOOL)createZipAtPath:(NSString *)zipPath
                rootDir:(NSString *)rootDir
                  files:(NSArray<NSString *> *)files
               progress:(DYYYDiagZipProgressBlock _Nullable)progress
                  error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END

#endif /* DYYYDiagZip_h */
