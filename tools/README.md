# tools/ —— 开发辅助脚本

这些脚本**不参与编译**，只用于开发期运行分析。可随仓库一起提交。

---

## aweme_classdump.js

从脱壳的 `AwemeCore` 二进制里提取 ObjC 类信息，解决「某个方法属于哪个类」的定位问题。

### 为什么需要它

抖音私有 API 的类名和 selector 每版都在变。静态扫字符串只能确认「名字存在」，**无法确认它属于哪个类**。

比如 41.1 里已知存在这些 selector：
```
setTargetBrightness:
adjustScreenBrightnessToTargetBrightness
getHDRBrightnessThreshold
```
但不知道宿主类是谁，就没法写 `%hook`。

本工具解析 Mach-O 的 `__objc_classlist` / `class_ro_t` / `method_list_t`，建立双向索引：
- 类名 → 全部方法 + 属性
- selector → 宿主类列表

### 用法

```bash
# 列出某个类的全部方法和属性
node aweme_classdump.js /path/to/AwemeCore --class AWEVideoModel

# 只看名字里带 water 的成员
node aweme_classdump.js /path/to/AwemeCore --class AWEVideoModel --match water

# 反查 selector 的宿主类
node aweme_classdump.js /path/to/AwemeCore --sel setTargetBrightness:

# 按关键字搜类名
node aweme_classdump.js /path/to/AwemeCore --grep Brightness
```

首次运行会建索引（约 10-30 秒，13.6 万个类）。

### 实际战果（41.1.0）

用它定位到：

| 需求 | 定位结果 |
|---|---|
| HDR 亮度调节 | `AWEVideoPlayerScreenBrightnessManager`（23 个方法） |
| HDR 亮度阈值 | `AWEBDSimPlayerBizConfig.getHDRBrightnessThreshold` |
| 无水印字段 | `AWEVideoModel.endWatermarkDownloadURL` / `captionWatermarkDownloadURL` |
| 图片无水印 | `AWEImageAlbumImageModel.watermarkFreeUrlList` |
| 14 种封面 | `AWEVideoModel.originCover` / `universalCoverUltimate` 等 |

---

## 实现要点（改代码前必读）

这几个坑是踩过的，改错了会得到乱码或空结果：

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

```js
const selRefAddr = mAddr + nameOffset;
const strAddr = readU64(selRefAddr);   // ← 这里才拿到字符串地址
const sel = readStr(strAddr);
```

**漏掉这一步会得到一堆乱码**（这次就是这么踩的）。

---

## 注意

- 需要**已脱壳**的二进制。App Store 加壳版解不出类信息。
- 只能读 ObjC 类。纯 Swift 类（无 `@objc` 暴露）不在 `__objc_classlist` 里。
- Swift 类如果带 `@objc` 方法，会以 mangled 名（`_TtC...`）出现在 classlist 里。
