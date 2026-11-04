// DYYYConfigCache — 热路径设置读取缓存（类声明见 AwemeHeaders.h）
#import "AwemeHeaders.h"
#import <CoreFoundation/CoreFoundation.h>
#import <os/lock.h>
#import <string.h>

#if !defined(__APPLE__)
// Linux 交叉编译（clang-11）时 @available 展开引用 compiler-rt 的
// ___isOSVersionAtLeast，Linux 工具链不附带该库。此处提供强定义。
// 语义：运行系统版本与调用方传入的部署目标比较（与 compiler-rt 一致）。
// 真机端（Apple）此文件不参与编译，由系统 libclang_rt 提供，无冲突。
int ___isOSVersionAtLeast(int major, int minor, int patch) {
    static int cachedMajor = -1;
    if (cachedMajor < 0) {
        @autoreleasepool {
            NSOperatingSystemVersion v = [[[NSProcessInfo alloc] init] operatingSystemVersion];
            cachedMajor = (int)v.majorVersion;
        }
    }
    if (cachedMajor > major) return 1;
    if (cachedMajor < major) return 0;
    return 1; // major 相等时系统版本 >= 部署目标
}
#endif

static os_unfair_lock gDYYYConfigCacheLock = OS_UNFAIR_LOCK_INIT;
static CFMutableDictionaryRef gDYYYConfigCacheDict = NULL;
static BOOL gDYYYConfigCacheObserverInstalled = NO;

static id DYYYConfigCacheReadRaw(NSString *key) {
    if (key.length == 0) {
        return nil;
    }

    os_unfair_lock_lock(&gDYYYConfigCacheLock);
    if (!gDYYYConfigCacheDict) {
        gDYYYConfigCacheDict = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    }
    if (!gDYYYConfigCacheObserverInstalled) {
        gDYYYConfigCacheObserverInstalled = YES;
        [[NSNotificationCenter defaultCenter] addObserverForName:NSUserDefaultsDidChangeNotification
                                                          object:nil
                                                           queue:nil
                                                      usingBlock:^(__unused NSNotification *note) {
                                                        [DYYYConfigCache invalidate];
                                                      }];
    }
    id cached = gDYYYConfigCacheDict ? (__bridge id)CFDictionaryGetValue(gDYYYConfigCacheDict, (__bridge CFStringRef)key) : nil;
    os_unfair_lock_unlock(&gDYYYConfigCacheLock);
    return cached;
}

static void DYYYConfigCacheStore(NSString *key, id value) {
    if (key.length == 0 || !value) {
        return;
    }
    os_unfair_lock_lock(&gDYYYConfigCacheLock);
    if (gDYYYConfigCacheDict) {
        CFDictionarySetValue(gDYYYConfigCacheDict, (__bridge CFStringRef)key, (__bridge CFTypeRef)value);
    }
    os_unfair_lock_unlock(&gDYYYConfigCacheLock);
}

@implementation DYYYConfigCache

+ (instancetype)new {
    return nil; // 纯类方法工具，禁止实例化
}

+ (id)objectForKey:(NSString *)key {
    id cached = DYYYConfigCacheReadRaw(key);
    if (cached) {
        return cached;
    }
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    if (value) {
        DYYYConfigCacheStore(key, value);
    }
    return value;
}

+ (BOOL)boolForBoolKey:(NSString *)key {
    id value = [self objectForKey:key];
    if ([value isKindOfClass:[NSNumber class]]) {
        return [(NSNumber *)value boolValue];
    }
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value boolValue];
    }
    return NO;
}

+ (float)floatForKey:(NSString *)key {
    id value = [self objectForKey:key];
    if ([value isKindOfClass:[NSNumber class]]) {
        return [(NSNumber *)value floatValue];
    }
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value floatValue];
    }
    return 0.0f;
}

+ (NSInteger)integerForKey:(NSString *)key {
    id value = [self objectForKey:key];
    if ([value isKindOfClass:[NSNumber class]]) {
        return [(NSNumber *)value integerValue];
    }
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value integerValue];
    }
    return 0;
}

+ (NSString *)stringForKey:(NSString *)key {
    id value = [self objectForKey:key];
    return [value isKindOfClass:[NSString class]] ? value : nil;
}

+ (void)invalidate {
    os_unfair_lock_lock(&gDYYYConfigCacheLock);
    if (gDYYYConfigCacheDict) {
        CFDictionaryRemoveAllValues(gDYYYConfigCacheDict);
    }
    os_unfair_lock_unlock(&gDYYYConfigCacheLock);
}

@end
