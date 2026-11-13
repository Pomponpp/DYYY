// DKGlassGuard.h — 玻璃守卫未随诊断模块引入；空声明占位。
#ifndef DKGlassGuard_h
#define DKGlassGuard_h
#import <Foundation/Foundation.h>
#ifdef __cplusplus
extern "C" {
#endif
BOOL DKGlassOSAvailable(void);
BOOL DKGlassIsGatedKey(NSString *key);
void DKGlassGuard(NSString *key);
#ifdef __cplusplus
}
#endif
#endif
