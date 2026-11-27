# tools/ —— 开发辅助脚本

这些脚本**不参与编译**，只用于开发期运行分析。可随仓库一起提交。

---

## 静态解析 AwemeCore 二进制

抖音私有 API 的类名和 selector 每版都在变。静态扫字符串只能确认「名字存在」，
**无法确认它属于哪个类**——不知道宿主类就写不了 `%hook`。

解析 Mach-O 的 `__objc_classlist` / `class_ro_t` / `method_list_t`，
建双向索引：类名 → 全部方法+属性，selector → 宿主类列表。

**本目录不内置解析器**：分析用的脚本按需现写，不随仓库分发。
需要时按下面「实现要点」自己起一个（Python 或 Node 都行），
或者直接问 AI 助手要（当前分析用的是 Python 版，放在仓库外的分析目录里）。

### 需要建立的能力

| 查询 | 用途 |
|---|---|
| 类名 → 方法 + 属性 + 继承链 | 写 `%hook` 前确认有哪些入口 |
| selector → 宿主类列表 | 反查某个 API 在哪个类上 |
| 关键字搜类名 | 版本改了名之后找继任类 |
| 类是否存在 | 判断旧 hook 是否已失效 |

---

## 实现要点（改代码前必读）

这几个坑是踩过的，改错了会得到乱码或空结果。

### 1. `vmaddr == fileoff`

抖音的 AwemeCore 段表里 `__TEXT` 从 0 开始、`__DATA` 的 fileoff 与 vmaddr 相同。
**可以直接把 vmaddr 当文件偏移读。**

### 2. `class_t` 布局

```
+0   isa           (8)
+8   superclass    (8)
+16  cache         (16)
+32  bits          (8)   ← class_ro_t 指针在这里
+40  ...
```

`bits & 0x7ffffffffff8` 取真实指针（低 3 位是标志）。

### 3. `class_ro_t` 布局

```
+0   flags / instanceStart / instanceSize / reserved   (各 4 字节)
+16  ivarLayout   (8)
+24  name         (8)   ← 类名
+32  baseMethods  (8)   ← 方法列表
+40  baseProtocols(8)
+48  ivars        (8)
+56  weakIvarLayout (8)
+64  baseProperties (8) ← 属性列表
```

### 4. ★ relative method list 需要二次解引用

现代 iOS 用相对方法列表（`entsizeAndFlags & 0x80000000`）：

```c
struct method_t {
    int32_t nameOffset;   // 相对【本字段】的偏移
    int32_t typesOffset;
    int32_t impOffset;
};
```

**关键**：`nameOffset` 指向的是 `__objc_selrefs` 里的**槽位**，不是字符串本身。

```python
sel_ref_addr = m_addr + name_offset
str_addr = read_u64(sel_ref_addr)   # ← 这里才拿到字符串地址
sel = read_str(str_addr)
```

**漏掉这一步会得到一堆乱码。**

### 5. 类型编码 `typesOffset` 不经过 selrefs

和 `nameOffset` 不同，`typesOffset` 直接指向 `__objc_methtype` 里的字符串：

```python
types = read_str(m_addr + 4 + types_offset)
```

### 6. 只在 `__objc_classlist` 里找类会漏

- **分类（category）方法**在 `__objc_catlist`，不在类的 method_list 里
- **Swift 类**以 mangled 名（`_TtC<模块长度><模块><类长度><类>`）出现，运行时用带点号的名字（`Module.Class`）查不到
- **类方法**在 metaclass 里，`class_ro_t.baseMethods` 只有实例方法

---

## 已知限制

- 需要**已脱壳**的二进制。App Store 加壳版解不出类信息。
- 共享缓存里的父类（如 `NSObject`、UIKit 类）`superclass` 指针指向镜像外，
  解析时会读到 0 或无效地址，需要单独判断。
- 纯 Swift 类（无 `@objc` 暴露）不在 `__objc_classlist` 里。
