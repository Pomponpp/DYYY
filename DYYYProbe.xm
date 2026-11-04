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

// 无条件 dump 某个类的全部方法（用于定位头像预览页的保存入口）
static void DYYYProbeDumpClassFull(Class cls) {
    if (!cls) {
        return;
    }
    NSMutableString *out = [NSMutableString string];
    const char *name = class_getName(cls);
    Class superClass = class_getSuperclass(cls);
    [out appendFormat:@"[probe] ===== 全量方法 dump: %s (super: %s) =====\n", name,
                      superClass ? class_getName(superClass) : "(root)"];

    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    if (methods) {
        for (unsigned int i = 0; i < count && i < 300; i++) {
            SEL sel = method_getName(methods[i]);
            const char *types = method_getTypeEncoding(methods[i]);
            [out appendFormat:@"[probe]   - %@  types=%s\n", NSStringFromSelector(sel), types ?: "?"];
        }
        free(methods);
    }

    Class meta = object_getClass(cls);
    unsigned int ccount = 0;
    Method *cmethods = class_copyMethodList(meta, &ccount);
    if (cmethods) {
        for (unsigned int i = 0; i < ccount && i < 100; i++) {
            SEL sel = method_getName(cmethods[i]);
            [out appendFormat:@"[probe]   + %@\n", NSStringFromSelector(sel)];
        }
        free(cmethods);
    }

    [out appendFormat:@"[probe] ===== dump 结束: %s =====\n", name];
    DYYYProbeLog(@"%@", out);
}

// dump 某个视图层级内所有按钮/控件及其点击动作（用于定位保存按钮）
static void DYYYProbeDumpControls(UIView *root, NSString *tag) {
    if (!root) {
        return;
    }
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"[probe] ===== 控件清单 %@ =====\n", tag];
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    NSUInteger limit = 600;
    for (NSUInteger i = 0; i < queue.count && i < limit; i++) {
        UIView *v = queue[i];
        if ([v isKindOfClass:[UIControl class]]) {
            UIControl *c = (UIControl *)v;
            NSMutableArray<NSString *> *targets = [NSMutableArray array];
            for (id t in c.allTargets) {
                [targets addObject:NSStringFromClass([t class])];
            }
            NSString *label = v.accessibilityLabel ?: @"";
            [out appendFormat:@"[probe]   %s  frame=%@  label=%@  targets=%@  tags=%lu\n",
                              class_getName([v class]), NSStringFromCGRect(v.frame), label,
                              [targets componentsJoinedByString:@","], (unsigned long)c.allControlEvents];
        }
        if ([v isKindOfClass:[UILabel class]]) {
            UILabel *l = (UILabel *)v;
            if (l.text.length > 0 && l.text.length < 40) {
                [out appendFormat:@"[probe]   UILabel \"%@\"\n", l.text];
            }
        }
        [queue addObjectsFromArray:v.subviews];
    }
    [out appendFormat:@"[probe] ===== 控件清单结束 %@ =====\n", tag];
    DYYYProbeLog(@"%@", out);
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

// 3) 页面出现/弹出：确认头像预览页，dump 该类全部方法与控件（保存按钮就在这一页）
%hook UIViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    if (!DYYYProbeEnabled()) {
        return;
    }
    const char *name = class_getName([self class]);
    if (!name) {
        return;
    }
    // 头像预览页出现后，延迟一点等待布局完成，再抓控件与类方法
    if (strstr(name, "Avatar") || strstr(name, "Preview") || strstr(name, "Head")) {
        DYYYProbeLog(@"页面出现 %s", name);
        __weak UIViewController *weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                         UIViewController *strongSelf = weakSelf;
                         if (!strongSelf) {
                             return;
                         }
                         DYYYProbeDumpClassFull([strongSelf class]);
                         DYYYProbeDumpControls(strongSelf.view, NSStringFromClass([strongSelf class]));
                         // 头像页：把功能项模型逐条打印（含标题/类型），可直接看到"保存"
                         if ([NSStringFromClass([strongSelf class]) containsString:@"ProfileAvatarViewController"]) {
                             if ([strongSelf respondsToSelector:NSSelectorFromString(@"functionModels")]) {
                                 id models = [strongSelf valueForKey:@"functionModels"];
                                 if ([models isKindOfClass:[NSArray class]]) {
                                     NSMutableString *buf = [NSMutableString string];
                                     [buf appendFormat:@"[probe] ===== 功能项模型 %lu 条 =====\n",
                                                       (unsigned long)[models count]];
                                     for (id model in (NSArray *)models) {
                                         NSString *cls = NSStringFromClass([model class]);
                                         [buf appendFormat:@"[probe]   --- %@ ---\n", cls];
                                         // 遍历模型的全部 ivar，找出可能的开关字段
                                         unsigned int ivarCount = 0;
                                         Ivar *ivars = class_copyIvarList([model class], &ivarCount);
                                         for (unsigned int i = 0; i < ivarCount && i < 40; i++) {
                                             const char *name = ivar_getName(ivars[i]);
                                             if (!name) continue;
                                             NSString *key = [NSString stringWithUTF8String:name];
                                             id value = nil;
                                             @try {
                                                 value = [model valueForKey:key];
                                             } @catch (__unused NSException *e) {
                                                 value = @"<不可读>";
                                             }
                                             [buf appendFormat:@"[probe]     %@ = %@\n", key, value ?: @"(nil)"];
                                         }
                                         if (ivars) free(ivars);
                                         // 同时列出该类所有方法，便于找 enable/hidden/show 之类
                                         unsigned int mCount = 0;
                                         Method *methods = class_copyMethodList([model class], &mCount);
                                         for (unsigned int i = 0; i < mCount && i < 40; i++) {
                                             SEL sel = method_getName(methods[i]);
                                             [buf appendFormat:@"[probe]     method: %@\n", NSStringFromSelector(sel)];
                                         }
                                         if (methods) free(methods);
                                     }
                                     DYYYProbeLog(@"%@", buf);
                                 }
                             }
                         }
                       });
    }
}

- (void)presentViewController:(UIViewController *)viewControllerToPresent
                     animated:(BOOL)flag
                   completion:(void (^)(void))completion {
    if (DYYYProbeEnabled() && viewControllerToPresent) {
        Class presentedClass = [viewControllerToPresent class];
        const char *name = class_getName(presentedClass);
        if (name && (strstr(name, "Avatar") || strstr(name, "Preview") || strstr(name, "Head"))) {
            DYYYProbeLog(@"弹出页面 %s（由 %s 发起）", name, class_getName(self.class));
            DYYYProbeDumpClassFull(presentedClass);
        }
    }
    %orig;
}

%end

// 4) 控制器 push：抓头像预览页（主页大头像走 push），并 dump 全部方法
%hook UINavigationController

- (void)pushViewController:(UIViewController *)viewController animated:(BOOL)animated {
    if (DYYYProbeEnabled() && viewController) {
        Class cls = [viewController class];
        const char *name = class_getName(cls);
        if (name && (strstr(name, "Avatar") || strstr(name, "Preview") || strstr(name, "Head"))) {
            DYYYProbeLog(@"push 页面 %s", name);
            DYYYProbeDumpClassFull(cls);
        }
    }
    %orig;
}

%end

// 5) 头像预览页的功能项判定：记录传入的功能类型与返回结果。
//    40.9 用 p_shouldShowFunctionWithType:(long long) 替代旧的 shouldShowSaveAvatarItem，
//    打出每个 type 的返回值即可确定"保存"对应的枚举值。
%hook AWEProfileAvatarViewController

- (BOOL)p_shouldShowFunctionWithType:(long long)type {
    BOOL result = %orig;
    if (DYYYProbeEnabled()) {
        id userValue = nil;
        id obj = (id)self;
        if ([obj respondsToSelector:NSSelectorFromString(@"user")]) {
            @try {
                userValue = [obj valueForKey:@"user"];
            } @catch (__unused NSException *e) {
                userValue = nil;
            }
        }
        DYYYProbeLog(@"[功能项] type=%lld 显示=%d", type, result ? 1 : 0);
    }
    return result;
}

- (id)p_collectionViewCellWithType:(long long)type {
    id cell = %orig;
    if (DYYYProbeEnabled()) {
        DYYYProbeLog(@"[功能项Cell] type=%lld -> %s", type, cell ? class_getName([cell class]) : "nil");
    }
    return cell;
}

// 渲染入口：记录功能项按钮视图构建时的模型数量
- (void)p_setupViews {
    %orig;
    if (DYYYProbeEnabled()) {
        id models = nil;
        @try {
            models = [(id)self valueForKey:@"functionModels"];
        } @catch (__unused NSException *e) {
            models = nil;
        }
        NSUInteger count = [models isKindOfClass:[NSArray class]] ? [models count] : 0;
        DYYYProbeLog(@"[setupViews] 功能项模型数=%lu", (unsigned long)count);
        // 记录 actionButtonsView 的子视图数量，判断是否真的没渲染
        id buttonsView = nil;
        @try {
            buttonsView = [(id)self valueForKey:@"actionButtonsView"];
        } @catch (__unused NSException *e) {
            buttonsView = nil;
        }
        if ([buttonsView isKindOfClass:[UIView class]]) {
            UIView *bv = (UIView *)buttonsView;
            DYYYProbeLog(@"[setupViews] actionButtonsView=%s frame=%@ subviews=%lu",
                         class_getName([bv class]), NSStringFromCGRect(bv.frame),
                         (unsigned long)bv.subviews.count);
            for (UIView *sub in bv.subviews) {
                DYYYProbeLog(@"[setupViews]   子视图 %s frame=%@ hidden=%d",
                             class_getName([sub class]), NSStringFromCGRect(sub.frame), sub.hidden ? 1 : 0);
            }
        } else {
            DYYYProbeLog(@"[setupViews] actionButtonsView 不存在");
        }
    }
}

- (void)updateActionViewWithType:(long long)type status:(BOOL)status animated:(BOOL)animated {
    %orig;
    if (DYYYProbeEnabled()) {
        DYYYProbeLog(@"[功能项状态] type=%lld status=%d", type, status ? 1 : 0);
    }
}

%end

// 6) 功能管理器：记录它给出的功能项模型（含类型与标题）
%hook AWEProfileAvatarFunctionManager

- (BOOL)p_shouldShowFunctionWithType:(long long)type {
    BOOL result = %orig;
    if (DYYYProbeEnabled()) {
        DYYYProbeLog(@"[Manager功能项] type=%lld 显示=%d", type, result ? 1 : 0);
    }
    return result;
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
