//
//  DYYYProbe.xm
//  DYYY
//
//  运行时探针：抖音 40.9 把头像保存迁到了 AWEProfileAvatarPreviewStream 新架构，
//  静态分析无法确定方法归属类，这里在运行时把真实类名、方法签名与动作链写进运行日志，
//  由设置页「导出运行日志」取出后即可精确挂 hook。
//
//  开关：DYYYEnableAvatarProbe（默认开启，装完测完可关闭）
//  日志前缀：[DYYY][probe]
//

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <string.h>

#import "AwemeHeaders.h"

static NSString *const kDYYYProbeEnabledKey = @"DYYYEnableAvatarProbe";

static BOOL DYYYProbeEnabled(void) {
    NSNumber *value = [[NSUserDefaults standardUserDefaults] objectForKey:kDYYYProbeEnabledKey];
    if (!value) {
        return YES; // 默认开启，便于复现问题后直接导出日志
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        return value.boolValue;
    }
    return YES;
}

// 低成本类名判断：只比较 C 字符串，避免热路径上的 NSString 分配。
static BOOL DYYYProbeNameMatches(Class cls) {
    const char *name = cls ? class_getName(cls) : NULL;
    if (!name) {
        return NO;
    }
    return strstr(name, "Avatar") != NULL || strstr(name, "avatar") != NULL ||
           strstr(name, "RoleHead") != NULL || strstr(name, "HeadDownload") != NULL;
}

static BOOL DYYYProbeSelectorMatches(SEL selector) {
    const char *name = selector ? sel_getName(selector) : NULL;
    if (!name) {
        return NO;
    }
    return strstr(name, "Avatar") != NULL || strstr(name, "avatar") != NULL ||
           strstr(name, "RoleHead") != NULL || strstr(name, "Head") != NULL ||
           strstr(name, "save") != NULL || strstr(name, "Save") != NULL ||
           strstr(name, "download") != NULL || strstr(name, "Download") != NULL;
}

static void DYYYProbeLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    if (message.length > 0) {
        NSLog(@"[DYYY][probe] %@", message);
    }
}

#pragma mark - 类清单转储

static NSString *DYYYProbeMethodLine(BOOL classMethod, Method method) {
    SEL selector = method_getName(method);
    const char *types = method_getTypeEncoding(method);
    return [NSString stringWithFormat:@"[probe]   %s %@  types=%s",
                                      classMethod ? "+" : "-",
                                      NSStringFromSelector(selector),
                                      types ?: "?"];
}

static void DYYYProbeDumpClassMethods(NSMutableString *out, Class cls, BOOL classMethod) {
    Class target = classMethod ? object_getClass(cls) : cls;
    if (!target) {
        return;
    }
    unsigned int count = 0;
    Method *methods = class_copyMethodList(target, &count);
    if (!methods) {
        return;
    }
    NSUInteger emitted = 0;
    for (unsigned int index = 0; index < count && emitted < 80; index++) {
        SEL selector = method_getName(methods[index]);
        if (!DYYYProbeSelectorMatches(selector)) {
            continue;
        }
        [out appendFormat:@"%@\n", DYYYProbeMethodLine(classMethod, methods[index])];
        emitted++;
    }
    free(methods);
}

static void DYYYProbeDumpAvatarInventory(void) {
    @autoreleasepool {
        unsigned int classCount = 0;
        Class *classes = objc_copyClassList(&classCount);
        if (!classes) {
            return;
        }

        NSMutableString *out = [NSMutableString string];
        [out appendString:@"[probe] ===== 头像相关类清单开始 =====\n"];
        NSUInteger matchedClasses = 0;
        NSUInteger emittedLines = 0;
        const NSUInteger maxLines = 400;

        for (unsigned int index = 0; index < classCount && emittedLines < maxLines; index++) {
            Class cls = classes[index];
            if (!cls || !DYYYProbeNameMatches(cls)) {
                continue;
            }
            // 只保留与头像预览/主页头像/功能项相关的类，避免日志爆量。
            const char *name = class_getName(cls);
            if (!name) {
                continue;
            }
            BOOL interesting = strstr(name, "Preview") || strstr(name, "ProfileAvatar") ||
                               strstr(name, "AvatarFunction") || strstr(name, "ProfileHeaderAction") ||
                               strstr(name, "RoleHead") || strstr(name, "HeadDownload");
            if (!interesting) {
                continue;
            }

            matchedClasses++;
            Class superClass = class_getSuperclass(cls);
            [out appendFormat:@"[probe] 类 %s : %s\n", name, superClass ? class_getName(superClass) : "(root)"];
            emittedLines++;
        }

        [out appendFormat:@"[probe] ===== 头像相关类清单结束（共 %lu 个类）=====\n", (unsigned long)matchedClasses];
        free(classes);
        DYYYProbeLog(@"%@", out);

        // 第二段：对重点类单独打印方法签名，便于确认保存入口挂在哪个类。
        // 注意：Swift 类需用 mangled 名（_TtC…）查询，点号名在 40.9 不可查。
        NSArray<NSString *> *focusClasses = @[
            @"AWEProfileAvatarFunctionManager",
            @"AWEProfileAvatarFunctionCell",
            @"AWEProfileAvatarFunctionModel",
            @"AWEProfileAvatarViewController",
            @"AWEProfileAvatarActionView",
            @"AWEProfileAvatarActionButtonsView",
            @"AWEDYProfileHeaderActionController",
            @"AWEProfileHeaderActionController",
            @"AWEProfileAvatarCollectionViewCellV2",
            // 40.9 长按头像菜单的真实类（Swift，需 mangled 名）
            @"_TtC17AWEStorySwiftImpl27ProfileAvatarLongPressAlert",
            @"IESLiveShareAvatarCell",
            @"IESIMShareAvatarView",
        ];
        NSMutableString *methods = [NSMutableString string];
        [methods appendString:@"[probe] ===== 重点类方法签名开始 =====\n"];
        for (NSString *className in focusClasses) {
            Class cls = NSClassFromString(className);
            if (!cls) {
                [methods appendFormat:@"[probe] 类 %@ 不存在\n", className];
                continue;
            }
            [methods appendFormat:@"[probe] 类 %@ :\n", className];
            DYYYProbeDumpClassMethods(methods, cls, NO);
            DYYYProbeDumpClassMethods(methods, cls, YES);
        }
        [methods appendString:@"[probe] ===== 重点类方法签名结束 =====\n"];
        DYYYProbeLog(@"%@", methods);
    }
}

#pragma mark - 视图层级快照

static NSString *DYYYProbeChainDescription(UIView *view, NSUInteger depth) {
    NSMutableString *chain = [NSMutableString string];
    UIView *current = view;
    for (NSUInteger level = 0; current && level < depth; level++) {
        if (level > 0) {
            [chain appendString:@" <- "];
        }
        [chain appendFormat:@"%s", class_getName(current.class)];
        current = current.superview;
    }
    return chain;
}

#pragma mark - Hook

// 1) 长按手势挂载点：定位"别人主页头像"到底是哪个视图类
%hook UIView

- (void)addGestureRecognizer:(UIGestureRecognizer *)gestureRecognizer {
    %orig;

    if (!DYYYProbeEnabled() || ![gestureRecognizer isKindOfClass:[UILongPressGestureRecognizer class]]) {
        return;
    }
    if (!DYYYProbeNameMatches(self.class)) {
        return;
    }
    DYYYProbeLog(@"长按手势挂载 → 视图层级: %@", DYYYProbeChainDescription(self, 8));
}

%end

// 2) 动作派发：抓出真正响应"保存头像"的 target 类与 selector
%hook UIApplication

- (BOOL)sendAction:(SEL)action to:(id)target from:(id)sender forEvent:(UIEvent *)event {
    if (DYYYProbeEnabled()) {
        Class targetClass = target ? [target class] : Nil;
        Class senderClass = sender ? [sender class] : Nil;
        if (DYYYProbeNameMatches(targetClass) || DYYYProbeNameMatches(senderClass)) {
            const char *selName = action ? sel_getName(action) : NULL;
            DYYYProbeLog(@"动作派发 action=%s target=%s sender=%s",
                         selName ?: "?",
                         targetClass ? class_getName(targetClass) : "nil",
                         senderClass ? class_getName(senderClass) : "nil");
        }
    }
    return %orig;
}

%end

// 3) 页面弹出：确认头像预览页的真实控制器类
%hook UIViewController

- (void)presentViewController:(UIViewController *)viewControllerToPresent
                     animated:(BOOL)flag
                   completion:(void (^)(void))completion {
    if (DYYYProbeEnabled() && viewControllerToPresent) {
        Class presentedClass = [viewControllerToPresent class];
        const char *name = class_getName(presentedClass);
        if (name && (strstr(name, "Avatar") || strstr(name, "Preview") || strstr(name, "Head"))) {
            DYYYProbeLog(@"弹出页面 %s（由 %s 发起）", name, class_getName(self.class));
        }
    }
    %orig;
}

%end

// 4) 控制器 push：抓头像预览页（主页头像通常走 push 而非 present）
%hook UINavigationController

- (void)pushViewController:(UIViewController *)viewController animated:(BOOL)animated {
    if (DYYYProbeEnabled() && viewController) {
        const char *name = class_getName([viewController class]);
        if (name && (strstr(name, "Avatar") || strstr(name, "Preview") || strstr(name, "Head"))) {
            DYYYProbeLog(@"push 页面 %s", name);
        }
    }
    %orig;
}

%end

%ctor {
    if (!DYYYProbeEnabled()) {
        return;
    }
    // 延后到启动完成后（抖音自身类已注册），避免类清单缺项。
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(10.0 * NSEC_PER_SEC)),
                   dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
                     DYYYProbeDumpAvatarInventory();
                   });
}
