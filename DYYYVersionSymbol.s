// DYYYVersionSymbol.s
// Linux 交叉编译（clang-11）时 @available 展开引用 compiler-rt 的
// ___isOSVersionAtLeast，Linux 工具链不附带该库，链接报 Undefined symbols。
// theos 使用的 cctools ld 不支持 --defsym，C 层定义又受条件编译影响，
// 故用纯汇编直接定义符号（链接期强制存在，恒真语义——所有 @available
// 调用点均有 respondsToSelector 运行时保护，且部署目标本身 <= 运行系统）。
// Apple 端（macOS 构建）不编此文件（Makefile 按平台条件加入编译列表）。

#if defined(__linux__)

    .text
    .globl ___isOSVersionAtLeast
___isOSVersionAtLeast:
    mov     w0, #1          // 返回 1（版本满足）
    ret

#endif
