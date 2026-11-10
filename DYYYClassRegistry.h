// DYYYClassRegistry — Hook 目标类存在性自检
// 40.9 适配教训：抖音改版会改名/删除私有类，hook 静默失效且难以定位。
// 本注册表在启动时统一探测所有关键类，缺失的输出一行汇总日志，
// 把"全屏错乱/功能异常"降级为"看日志即知哪个类需要跟进"。
// 声明集中在 AwemeHeaders.h（项目规范），实现留在 .m。
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, DYYYClassAuditStatus) {
    DYYYClassAuditStatusOK = 0,      // 类存在
    DYYYClassAuditStatusMissing,     // 类缺失（抖音改名/删除，或系统私有类不在主二进制）
};

@interface DYYYClassRegistry : NSObject

// 探测单个类，返回状态；outResolvedName 可选输出实际命中的运行时名。
+ (DYYYClassAuditStatus)auditClass:(NSString *)className
                   outResolvedName:(NSString * _Nullable * _Nullable)outResolvedName;

// 启动自检：探测注册表内全部类，缺失的输出一行汇总日志。返回缺失数量。
+ (NSInteger)runStartupAudit;

// 可读自检报告（中文，逐条列出关键类状态与对应功能），结果缓存。
+ (NSString *)auditReportText;

// Hook 生效数自检：扫运行时 _logos_method$ 前缀方法数，与期望值比对。
// 类在但方法签名变了时，hook 会静默失效——这是唯一能发现它的手段。
+ (void)setExpectedHookCount:(NSUInteger)count;
+ (NSUInteger)countInstalledLogosMethods;
+ (NSString *)hookHealthText;

// 运行时类清单（抖音前缀过滤）：适配新版时与旧清单对比得出「缺失 → 疑似新名」。
+ (NSString *)runtimeClassListText;

// 目标类方法清单：抖音改了方法名（类名不变）时，靠它对比出少了哪个 selector。
+ (NSString *)targetMethodsText;

// 供 Hook 代码使用的安全取类：先点号名，再 mangled 名。
+ (Class _Nullable)resolveSwiftClassDotName:(const char *)dotName
                                mangledName:(const char *)mangledName;

@end
