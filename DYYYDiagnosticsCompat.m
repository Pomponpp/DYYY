//
//  DYYYDiagnosticsCompat.m
//  DYYY 诊断子系统
//
//  基于 ObjC 运行时生成类头文件文本。
//  DYYYDiagClassIsSafe 用于限制可内省类集合。
//


#import "DYYYDiagnosticsCompat.h"
#import <CoreFoundation/CoreFoundation.h>
#import <zlib.h>
#import <objc/runtime.h>

static NSString *DYYYDiagCString(const char *value) {
    if (!value) return @"";
    NSString *utf8 = [NSString stringWithUTF8String:value];
    if (utf8) return utf8;
    size_t length = strnlen(value, 4096);
    NSString *latin = [[NSString alloc] initWithBytes:value length:length encoding:NSISOLatin1StringEncoding];
    if (latin) return latin;
    NSMutableString *hex = [NSMutableString stringWithString:@"<bytes:"];
    for (size_t i = 0; i < MIN(length, (size_t)64); i++) [hex appendFormat:@"%02x", (unsigned char)value[i]];
    [hex appendString:@">"];
    return hex;
}

#pragma mark - 安全内省检查

// 用 CFSet + NULL 回调按指针身份比较，用于跳过不安全类。
static CFSetRef DYYYDiagUnsafeClassSet;
static Class DYYYDiagNSObjectClass;
static Class DYYYDiagNSProxyClass;

__attribute__((constructor))
static void DYYYDiagClassDumpInit(void) {
    DYYYDiagNSObjectClass = [NSObject class];
    DYYYDiagNSProxyClass = [NSProxy class];

    static const char *const kUnsafeNames[] = {
        "__ARCLite__", "__NSCFCalendar", "__NSCFTimer", "NSCFTimer",
        "__NSGenericDeallocHandler", "NSAutoreleasePool", "NSPlaceholderNumber",
        "NSPlaceholderString", "NSPlaceholderValue", "Object", "VMUArchitecture",
        "JSExport", "__NSAtom", "_NSZombie_", "_CNZombie_", "__NSMessage",
        "__NSMessageBuilder", "FigIrisAutoTrimmerMotionSampleExport", "_UIPointVector",
    };
    NSUInteger n = sizeof(kUnsafeNames) / sizeof(kUnsafeNames[0]);
    const void **classes = malloc(n * sizeof(void *));
    NSUInteger count = 0;
    for (NSUInteger i = 0; i < n; i++) {
        Class c = objc_getClass(kUnsafeNames[i]);
        if (c) classes[count++] = (__bridge const void *)c;
    }
    DYYYDiagUnsafeClassSet = CFSetCreate(kCFAllocatorDefault, classes, count, NULL);
    free(classes);
}

BOOL DYYYDiagClassIsSafe(Class cls) {
    if (!cls) return NO;
    if (DYYYDiagUnsafeClassSet && CFSetContainsValue(DYYYDiagUnsafeClassSet, (__bridge const void *)cls)) return NO;
    // 无父类者只有 NSObject / NSProxy 两个已知根类是安全的
    if (!class_getSuperclass(cls)) {
        return cls == DYYYDiagNSObjectClass || cls == DYYYDiagNSProxyClass;
    }
    return YES;
}

#pragma mark - 过滤

static BOOL DYYYDiagIsLikelySwiftName(NSString *name) {
    if (name.length == 0) return YES;
    if ([name hasPrefix:@"_Tt"]) return YES;
    if ([name hasPrefix:@"Swift."]) return YES;
    if ([name hasPrefix:@"SwiftUI."]) return YES;
    if ([name containsString:@"<"]) return YES;
    if ([name containsString:@"`"]) return YES;
    if ([name containsString:@"."]) return YES;
    return NO;
}

BOOL DYYYDiagClassNameIsRuntimeGenerated(NSString *name) {
    if (name.length == 0) return YES;
    if ([name hasPrefix:@"NSKVONotifying_"]) return YES;   // KVO 运行时子类
    if ([name containsString:@"_hmd_subfix_"]) return YES; // Heimdallr 崩溃修复子类
    if ([name containsString:@"_AWEPERF_"]) return YES;    // 性能监控子类
    if ([name containsString:@"_block_invoke"]) return YES;
    if ([name containsString:@"%"]) return YES;
    return NO;
}

#pragma mark - 类型编码 → 可读类型

static NSString *DYYYDiagTypeFromEncoding(const char *encoding) {
    if (!encoding) return @"id";
    NSString *e = DYYYDiagCString(encoding);
    if (e.length == 0) return @"id";

    if ([e hasPrefix:@"@\""]) {
        NSRange r1 = [e rangeOfString:@"\""];
        NSRange r2 = [e rangeOfString:@"\"" options:NSBackwardsSearch];
        if (r1.location != NSNotFound && r2.location != NSNotFound && r2.location > r1.location) {
            NSString *cls = [e substringWithRange:NSMakeRange(r1.location + 1, r2.location - r1.location - 1)];
            if (cls.length) return [NSString stringWithFormat:@"%@ *", cls];
        }
    }

    switch ([e characterAtIndex:0]) {
        case 'v': return @"void";
        case '@': return @"id";
        case '#': return @"Class";
        case ':': return @"SEL";
        case 'c': return @"char";
        case 'C': return @"unsigned char";
        case 's': return @"short";
        case 'S': return @"unsigned short";
        case 'i': return @"int";
        case 'I': return @"unsigned int";
        case 'l': return @"long";
        case 'L': return @"unsigned long";
        case 'q': return @"long long";
        case 'Q': return @"unsigned long long";
        case 'f': return @"float";
        case 'd': return @"double";
        case 'B': return @"BOOL";
        case '*': return @"char *";
        case '^': return @"void *";
        case '{': return @"struct";
        case '[': return @"void *";
        default:  return @"id";
    }
}

#pragma mark - 属性 / 方法行

static NSString *DYYYDiagPropertyLine(objc_property_t property) {
    const char *n = property_getName(property);
    if (!n) return nil;
    NSString *name = DYYYDiagCString(n);

    NSString *attrs = @"";
    const char *a = property_getAttributes(property);
    if (a) attrs = DYYYDiagCString(a);

    NSString *type = @"id";
    BOOL readonly = [attrs containsString:@",R"];
    BOOL copy = [attrs containsString:@",C"];
    BOOL weak = [attrs containsString:@",W"];
    BOOL nonatomic = [attrs containsString:@",N"];

    if ([attrs hasPrefix:@"T"]) {
        NSString *typePart = [[attrs substringFromIndex:1] componentsSeparatedByString:@","].firstObject ?: @"@";
        type = DYYYDiagTypeFromEncoding(typePart.UTF8String);
    }

    NSMutableArray *parts = [NSMutableArray array];
    [parts addObject:(nonatomic ? @"nonatomic" : @"atomic")];
    if (readonly) [parts addObject:@"readonly"];
    if (copy) [parts addObject:@"copy"];
    else if (weak) [parts addObject:@"weak"];
    else if ([type containsString:@"*"] || [type isEqualToString:@"id"]) [parts addObject:@"strong"];
    else [parts addObject:@"assign"];

    return [NSString stringWithFormat:@"@property (%@) %@ %@;", [parts componentsJoinedByString:@", "], type, name];
}

static NSString *DYYYDiagMethodLine(Method m, BOOL isClassMethod) {
    SEL sel = method_getName(m);
    if (!sel) return nil;

    const char *ret = method_copyReturnType(m);
    NSString *retType = DYYYDiagTypeFromEncoding(ret);
    if (ret) free((void *)ret);

    NSString *name = NSStringFromSelector(sel);
    if (name.length == 0) return nil;

    unsigned int argCount = method_getNumberOfArguments(m);
    if (![name containsString:@":"] || argCount <= 2) {
        return [NSString stringWithFormat:@"%c (%@)%@;", isClassMethod ? '+' : '-', retType, name];
    }

    NSArray<NSString *> *parts = [name componentsSeparatedByString:@":"];
    NSMutableString *line = [NSMutableString stringWithFormat:@"%c (%@)", isClassMethod ? '+' : '-', retType];
    for (NSUInteger i = 0; i < parts.count - 1; i++) {
        NSString *label = parts[i];
        char *argTypeRaw = method_copyArgumentType(m, (unsigned int)i + 2);
        NSString *argType = DYYYDiagTypeFromEncoding(argTypeRaw);
        if (argTypeRaw) free(argTypeRaw);
        if (i == 0) {
            [line appendFormat:@"%@:(%@)arg%lu", label.length ? label : @"method", argType, (unsigned long)i];
        } else {
            [line appendFormat:@" %@:(%@)arg%lu", label.length ? label : @"param", argType, (unsigned long)i];
        }
    }
    [line appendString:@";"];
    return line;
}

#pragma mark - 单类头文件

static NSString *DYYYDiagHeaderForClass(Class cls, NSString *imageName) {
    if (!DYYYDiagClassIsSafe(cls)) return nil;
    @try {
        // 用 class_getName 而非 NSStringFromClass：
        // 畸形 Swift mangled 名会让 NSStringFromClass 走 demangle 并 abort，
        // @try 拦不住（abort 不是 ObjC 异常）。
        const char *rawName = class_getName(cls);
        NSString *className = rawName ? [NSString stringWithUTF8String:rawName] : nil;
        if (className.length == 0) return nil;
        if (DYYYDiagIsLikelySwiftName(className)) {
            return [NSString stringWithFormat:
                    @"// Runtime class: %@\n// Image: %@\n// 该名称不是有效的 Objective-C 标识符，无法生成头文件。\n",
                    className, imageName ?: @"Unknown"];
        }

        Class superCls = class_getSuperclass(cls);
        const char *rawSuper = superCls ? class_getName(superCls) : NULL;
        NSString *superName = rawSuper ? [NSString stringWithUTF8String:rawSuper] : @"NSObject";

        NSMutableString *h = [NSMutableString string];
        [h appendString:@"//\n"];
        [h appendString:@"// Dumped by DYYY 诊断系统\n"];
        [h appendFormat:@"// Bundle: %@\n", NSBundle.mainBundle.bundleIdentifier ?: @"Unknown"];
        [h appendFormat:@"// Image: %@\n", imageName ?: @"Unknown"];
        [h appendString:@"//\n\n"];
        [h appendString:@"#import <Foundation/Foundation.h>\n"];
        [h appendString:@"#import <UIKit/UIKit.h>\n\n"];

        unsigned int protocolCount = 0;
        Protocol *__unsafe_unretained *protocols = class_copyProtocolList(cls, &protocolCount);
        NSMutableArray *protocolNames = [NSMutableArray array];
        for (unsigned int i = 0; i < protocolCount; i++) {
            const char *pn = protocol_getName(protocols[i]);
            if (pn) [protocolNames addObject:DYYYDiagCString(pn)];
        }
        if (protocols) free(protocols);

        if (protocolNames.count) {
            [h appendFormat:@"@interface %@ : %@ <%@>\n\n", className, superName, [protocolNames componentsJoinedByString:@", "]];
        } else {
            [h appendFormat:@"@interface %@ : %@\n\n", className, superName];
        }

        unsigned int ivarCount = 0;
        Ivar *ivars = class_copyIvarList(cls, &ivarCount);
        if (ivarCount > 0) [h appendString:@"{\n"];
        for (unsigned int i = 0; i < ivarCount; i++) {
            const char *in = ivar_getName(ivars[i]);
            const char *it = ivar_getTypeEncoding(ivars[i]);
            if (in) [h appendFormat:@"    %@ %@;\n", DYYYDiagTypeFromEncoding(it), DYYYDiagCString(in)];
        }
        if (ivarCount > 0) [h appendString:@"}\n\n"];
        if (ivars) free(ivars);

        unsigned int propertyCount = 0;
        objc_property_t *props = class_copyPropertyList(cls, &propertyCount);
        if (propertyCount > 0) [h appendString:@"#pragma mark - Properties\n\n"];
        for (unsigned int i = 0; i < propertyCount; i++) {
            NSString *line = DYYYDiagPropertyLine(props[i]);
            if (line.length) [h appendFormat:@"%@\n", line];
        }
        if (props) free(props);

        unsigned int methodCount = 0;
        Method *methods = class_copyMethodList(cls, &methodCount);
        if (methodCount > 0) [h appendString:@"\n#pragma mark - Instance Methods\n\n"];
        for (unsigned int i = 0; i < methodCount; i++) {
            NSString *line = DYYYDiagMethodLine(methods[i], NO);
            if (line.length) [h appendFormat:@"%@\n", line];
        }
        if (methods) free(methods);

        Class meta = object_getClass(cls);
        unsigned int classMethodCount = 0;
        Method *classMethods = class_copyMethodList(meta, &classMethodCount);
        if (classMethodCount > 0) [h appendString:@"\n#pragma mark - Class Methods\n\n"];
        for (unsigned int i = 0; i < classMethodCount; i++) {
            NSString *line = DYYYDiagMethodLine(classMethods[i], YES);
            if (line.length) [h appendFormat:@"%@\n", line];
        }
        if (classMethods) free(classMethods);

        [h appendString:@"\n@end\n"];
        return h;
    } @catch (__unused NSException *e) {
        return nil;
    }
}

#pragma mark - 对外 API

NSString *DYYYDiagClassDumpHeaderForClass(Class cls) {
    if (!DYYYDiagClassIsSafe(cls)) return nil;
    NSString *imageName = @"Unknown";
    const char *img = class_getImageName(cls);
    if (img) imageName = [DYYYDiagCString(img) lastPathComponent] ?: @"Unknown";
    return DYYYDiagHeaderForClass(cls, imageName);
}

#pragma mark - ZIP 写入器（不压缩存储 + CRC32 + ZIP64）


#import <CoreFoundation/CoreFoundation.h>
#import <zlib.h>

static void DYYYDiagZipAppendUInt16(NSMutableData *data, uint16_t value) {
    uint16_t v = CFSwapInt16HostToLittle(value);
    [data appendBytes:&v length:sizeof(v)];
}

static void DYYYDiagZipAppendUInt32(NSMutableData *data, uint32_t value) {
    uint32_t v = CFSwapInt32HostToLittle(value);
    [data appendBytes:&v length:sizeof(v)];
}

static void DYYYDiagZipAppendUInt64(NSMutableData *data, uint64_t value) {
    uint64_t v = CFSwapInt64HostToLittle(value);
    [data appendBytes:&v length:sizeof(v)];
}

static NSString *DYYYDiagZipRelativePath(NSString *path, NSString *rootDir) {
    NSString *prefix = [rootDir stringByAppendingString:@"/"];
    if ([path hasPrefix:prefix]) return [path substringFromIndex:prefix.length];
    return path.lastPathComponent ?: @"file";
}

static NSError *DYYYDiagZipError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"DYYY.Zip" code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"ZIP failed"}];
}

static NSData *DYYYDiagZipLocalHeader(NSData *nameData, uint32_t crc, uint32_t size) {
    NSMutableData *d = [NSMutableData data];
    DYYYDiagZipAppendUInt32(d, 0x04034b50);
    DYYYDiagZipAppendUInt16(d, 20);
    DYYYDiagZipAppendUInt16(d, 0x0800);
    DYYYDiagZipAppendUInt16(d, 0);
    DYYYDiagZipAppendUInt16(d, 0);
    DYYYDiagZipAppendUInt16(d, 0);
    DYYYDiagZipAppendUInt32(d, crc);
    DYYYDiagZipAppendUInt32(d, size);
    DYYYDiagZipAppendUInt32(d, size);
    DYYYDiagZipAppendUInt16(d, (uint16_t)nameData.length);
    DYYYDiagZipAppendUInt16(d, 0);
    [d appendData:nameData];
    return d;
}

static NSData *DYYYDiagZipCentralHeader(NSData *nameData, uint32_t crc, uint32_t size, uint32_t offset) {
    NSMutableData *d = [NSMutableData data];
    DYYYDiagZipAppendUInt32(d, 0x02014b50);
    DYYYDiagZipAppendUInt16(d, 20);
    DYYYDiagZipAppendUInt16(d, 20);
    DYYYDiagZipAppendUInt16(d, 0x0800);
    DYYYDiagZipAppendUInt16(d, 0);
    DYYYDiagZipAppendUInt16(d, 0);
    DYYYDiagZipAppendUInt16(d, 0);
    DYYYDiagZipAppendUInt32(d, crc);
    DYYYDiagZipAppendUInt32(d, size);
    DYYYDiagZipAppendUInt32(d, size);
    DYYYDiagZipAppendUInt16(d, (uint16_t)nameData.length);
    DYYYDiagZipAppendUInt16(d, 0);
    DYYYDiagZipAppendUInt16(d, 0);
    DYYYDiagZipAppendUInt16(d, 0);
    DYYYDiagZipAppendUInt16(d, 0);
    DYYYDiagZipAppendUInt32(d, 0);
    DYYYDiagZipAppendUInt32(d, offset);
    [d appendData:nameData];
    return d;
}

static NSData *DYYYDiagZipEndRecords(uint64_t entryCount, uint64_t centralSize, uint64_t centralOffset) {
    NSMutableData *end = [NSMutableData data];
    BOOL needsZip64 = entryCount >= UINT16_MAX;
    if (needsZip64) {
        uint64_t zip64EndOffset = centralOffset + centralSize;
        DYYYDiagZipAppendUInt32(end, 0x06064b50);
        DYYYDiagZipAppendUInt64(end, 44);
        DYYYDiagZipAppendUInt16(end, 45);
        DYYYDiagZipAppendUInt16(end, 45);
        DYYYDiagZipAppendUInt32(end, 0);
        DYYYDiagZipAppendUInt32(end, 0);
        DYYYDiagZipAppendUInt64(end, entryCount);
        DYYYDiagZipAppendUInt64(end, entryCount);
        DYYYDiagZipAppendUInt64(end, centralSize);
        DYYYDiagZipAppendUInt64(end, centralOffset);

        DYYYDiagZipAppendUInt32(end, 0x07064b50);
        DYYYDiagZipAppendUInt32(end, 0);
        DYYYDiagZipAppendUInt64(end, zip64EndOffset);
        DYYYDiagZipAppendUInt32(end, 1);
    }

    uint16_t legacyEntryCount = entryCount >= UINT16_MAX ? UINT16_MAX : (uint16_t)entryCount;
    DYYYDiagZipAppendUInt32(end, 0x06054b50);
    DYYYDiagZipAppendUInt16(end, 0);
    DYYYDiagZipAppendUInt16(end, 0);
    DYYYDiagZipAppendUInt16(end, legacyEntryCount);
    DYYYDiagZipAppendUInt16(end, legacyEntryCount);
    DYYYDiagZipAppendUInt32(end, (uint32_t)centralSize);
    DYYYDiagZipAppendUInt32(end, (uint32_t)centralOffset);
    DYYYDiagZipAppendUInt16(end, 0);
    return end;
}

@implementation DYYYDiagZipWriter

+ (BOOL)createZipAtPath:(NSString *)zipPath
                rootDir:(NSString *)rootDir
                  files:(NSArray<NSString *> *)files
               progress:(DYYYDiagZipProgressBlock)progress
                  error:(NSError **)error {
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *parent = zipPath.stringByDeletingLastPathComponent;
    if (parent.length) {
        NSError *dirError = nil;
        if (![fm createDirectoryAtPath:parent withIntermediateDirectories:YES attributes:nil error:&dirError] && dirError) {
            if (error) *error = dirError;
            return NO;
        }
    }

    [fm removeItemAtPath:zipPath error:nil];
    if (![fm createFileAtPath:zipPath contents:NSData.data attributes:nil]) {
        if (error) {
            *error = [NSError errorWithDomain:@"DYYY.Zip"
                                         code:-1
                                     userInfo:@{NSLocalizedDescriptionKey: @"ZIP file creation failed"}];
        }
        return NO;
    }

    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:zipPath];
    if (!handle) {
        if (error) {
            *error = [NSError errorWithDomain:@"DYYY.Zip"
                                         code:-2
                                     userInfo:@{NSLocalizedDescriptionKey: @"ZIP file handle creation failed"}];
        }
        return NO;
    }

    NSMutableData *central = [NSMutableData data];
    NSMutableSet<NSString *> *seenPaths = [NSMutableSet set];
    uint32_t offset = 0;
    uint64_t entryCount = 0;
    NSUInteger total = files.count;
    NSUInteger done = 0;

    for (NSString *file in files) {
        NSError *entryError = nil;
        @autoreleasepool {
            do {
                BOOL isDir = NO;
                if (![fm fileExistsAtPath:file isDirectory:&isDir] || isDir) {
                    entryError = DYYYDiagZipError(-3, [NSString stringWithFormat:@"ZIP source file missing: %@", file]);
                    break;
                }

                NSString *relative = DYYYDiagZipRelativePath(file, rootDir);
                if ([seenPaths containsObject:relative]) {   // 同一相对路径只写最终文件内容一次
                    done++;
                    break;
                }
                [seenPaths addObject:relative];
                NSData *content = [NSData dataWithContentsOfFile:file];
                NSData *nameData = [relative dataUsingEncoding:NSUTF8StringEncoding];
                if (!content || !nameData.length || nameData.length > UINT16_MAX || content.length > UINT32_MAX) {
                    entryError = DYYYDiagZipError(-4, [NSString stringWithFormat:@"ZIP entry unsupported: %@", relative]);
                    break;
                }

                uint32_t size = (uint32_t)content.length;
                uint32_t crc = (uint32_t)crc32(0, content.bytes, (uInt)content.length);
                NSData *local = DYYYDiagZipLocalHeader(nameData, crc, size);
                if (local.length + content.length > UINT32_MAX - offset) {
                    entryError = DYYYDiagZipError(-8, @"ZIP32 data offset overflow");
                    break;
                }
                @try {
                    [handle writeData:local];
                    [handle writeData:content];
                } @catch (NSException *exception) {
                    entryError = DYYYDiagZipError(-5, exception.reason ?: @"ZIP entry write failed");
                    break;
                }
                [central appendData:DYYYDiagZipCentralHeader(nameData, crc, size, offset)];

                offset += (uint32_t)(local.length + content.length);
                entryCount++;
                done++;
                if (progress) progress((CGFloat)done / (CGFloat)MAX(total, 1));
            } while (NO);
        }
        if (entryError) {
            [handle closeFile];
            if (error) *error = entryError;
            return NO;
        }
    }

    if (central.length > UINT32_MAX) {
        [handle closeFile];
        if (error) *error = DYYYDiagZipError(-9, @"ZIP32 central directory overflow");
        return NO;
    }
    uint64_t centralOffset = offset;
    uint64_t centralSize = central.length;
    @try {
        [handle writeData:central];
    } @catch (NSException *exception) {
        [handle closeFile];
        if (error) *error = DYYYDiagZipError(-6, exception.reason ?: @"ZIP central directory write failed");
        return NO;
    }
    NSData *end = DYYYDiagZipEndRecords(entryCount, centralSize, centralOffset);
    @try {
        [handle writeData:end];
    } @catch (NSException *exception) {
        [handle closeFile];
        if (error) *error = DYYYDiagZipError(-7, exception.reason ?: @"ZIP footer write failed");
        return NO;
    }
    [handle closeFile];
    return YES;
}

@end
