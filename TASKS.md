# DYYY 项目任务清单

> 最后更新：2026-11-13 · 当前发布版本 **DYYY_2.2-9#87**
> 目标：**抖音 41.1.0**（只适配最新版，旧版本不做适配）

---

## 一、待办事项（按优先级）

### P1 · 隐藏评论分享（已定位，可直接开工）

**现象**：设置 → 隐藏面板 → 隐藏评论分享 → 开 → 长按评论，菜单里「分享给朋友」仍在。

**根因（41.1 视图树实锤）**：

```
该栏 = _TtC14AWEIMShareImpl...CommentHorizontalSectionCell
       （运行时类 AWEIMShareImpl.ShareCommentHorizontalSectionViewModel / Controller）
       ├─ AWEIMShareImpl.ShareContactListRecentShareCell   「最近分享」
       └─ AWEIMShareImpl.ShareContactListTargetCell ×N      好友头像横排
```

它**不走** `CommentLongPressPanelNormalSectionViewModel.setModelsArray`（现有过滤体系所在处），
所以加 `PrivateMessageElement` 过滤永远不会被触发 —— **v87 的修改方向错了**。

**正确修法**：新增 `%group` + `%init` 动态绑定
`AWEIMShareImpl.ShareCommentHorizontalSectionViewModel`，开关开启时整栏隐藏。

**成本**：一个新 group、Swift 类动态绑定、中等风险。

---

### P2 · 群聊视频拖进度条出现「异常进度条」（信息不足）

**现象**：群聊聊天窗内的视频，拖进度条时出现异常进度条。

**已排除**：
- v87 已限制「显示进度时长」强制 alpha 只作用于首页 Feed —— **无效，不是元凶**
- 全屏机制未介入群聊页（日志零记录，符合预期）
- 进度条 frame 现为 `{404, 2}`（高度 2pt，正常）
- `AWEFakeProgressSliderView` 本次未出现

**待补充信息（需要用户提供）**：
1. 「异常进度条」具体长什么样 —— **截图最好**
2. 关掉「显示进度时长」后是否还异常
3. 关掉「清除进度条黑线」（`DYYYProgressUnderlineFix.xm`）后是否还异常

**怀疑方向**：
- 拖动时出现第二条进度条（插件叠加）
- `AWEProgressPreviewSlider` / `AWEFeedProgressRefinedFrameSelectionCollectionView` 位置或闪烁问题
- `DYYYProgressUnderlineFix` 清除黑线时误伤垫层
- 抖音群聊视频原生特性（非本插件问题）

---

### P3 · 首页个别视频画面跳动（罕见，待复测）

**现象**：首页某一个视频画面跳动，**仅此一个**（用户指定为普通视频，非图文）。

**已查线索**：

```
UITableViewCellContentView  {{0, 0}, {428, 926}}
  UIView                    {{0, 0}, {428, 843}}     ← 中间层停在 843 未撑满
  _UITableViewCellSeparatorView  {{20, 925.666}, {408, 0.333}}   ← 分隔线 0.333
```

**推断**：分隔线 `0.333px` 进入 `contentSize`，paging 按 926 对齐 →
累积 `0.333 × N` 误差 → 视觉跳动。

日志中确实出现 `y=0.33 / 912.33 / -912.33 / -13.67 / -2791.67` 等非整页位置。

**下一步（低成本验证，优先）**：
```
找到那个会跳的视频 → 关掉「全屏」开关 → 看还跳不跳
  还跳   → 抖音原生问题，不背锅
  不跳   → 我们的撑高导致，值得修
```

**候选修法**（若确认是我们的问题）：
| 方案 | 做法 | 风险 |
|---|---|---|
| A | hook `_UITableViewCellSeparatorView`，分隔线高度归零 | 低 |
| B | 撑高时把 cell 高度设为 926.333 对齐 | 中 |
| C | 不处理（极罕见边界） | 无 |

> 注意：这属于**全屏几何区（FROZEN）**，动它必须谨慎。

---

### P4 · 隐藏进场特效（未验证）

```
类：IESLiveDynamicUserEnterView
41.1 运行时查不到，无同名替代类
原 hook 保留（空转无害），注释已标注排查方向
等你实际在直播间看到进场动画时再验证
```

---

### P5 · 入口层瘦身（推迟中）

```
内容：6 个被重复 hook 的类，把分散 hook 合并到一处
     （AWEPlayInteractionViewController ×2、AWEFeedVideoButton ×3 等）
收益：以后加功能时不踩"这个类被谁改过"的坑
风险：低（同文件内移动代码）
状态：用户已同意推迟到下个版本
```

---

### P6 · 死代码清理（随时可做）

```
· alignExistingCellsIfNeeded（#73 后已无调用）
· grep 出的其他未引用方法
纯删除，零风险
```

---

## 发布流程（固定做法，别再试错）

### CI 现状

```
build workflow：只产 packages/DYYY.dylib（不打包 deb）
publish workflow：仍在找 packages/*.deb → 必然失败
```

**原因**：编译曾经超过 15 分钟被砍，为提速把 workflow 改成「只编 arm64 + 只编译不打包」。
publish 脚本没同步改，所以每次 publish 都报 `No .deb files found`。

### 正确发布步骤

```
1. 推送代码
2. workflow_dispatch 触发 build（或等 push 自动触发）
3. 只关心 build job 的结果，忽略 publish 失败
4. build 成功后，从 run 的 artifacts 下载 DYYY-dylib-NNN
5. 用 API 手动创建 release + 上传 dylib
```

### build artifact 下载与发布（可直接复用）

```bash
# 1. 取最新一次 build 成功的 run id
GET /repos/{owner}/{repo}/actions/workflow-runs?per_page=10
#    只挑 name=="build deb" 且 conclusion=="success" 的

# 2. 取该 run 的 artifact id
GET /repos/{owner}/{repo}/actions/runs/{run_id}/artifacts

# 3. 下载 zip
GET /repos/{owner}/{repo}/actions/artifacts/{artifact_id}/zip
#    （Windows 环境没有 unzip，用 7z e）

# 4. 建 release（tag 格式 DYYY_2.2-9#NN）
POST /repos/{owner}/{repo}/releases
   tag_name:            "DYYY_2.2-9#NN"      ← 注意 # 在 URL 里要写成 %23
   target_commitish:    main 的当前 sha
   name:                "DYYY_2.2-9#NN"

# 5. 上传资产（文件名不能带 #，会被当 URL fragment）
POST https://uploads.github.com/repos/{owner}/{repo}/releases/{release_id}/assets?name=DYYY_2.2-9-NN.dylib
```

**命名规范**：
```
tag       DYYY_2.2-9#NN       （可以带 #）
asset     DYYY_2.2-9-NN.dylib （必须用 -，不能用 #）
release 正文里引用版本号用 vNN，不要用 #NN（会被自动链接到上游 issue）
```

### runner 排队的坑

```
现象：build job 卡在 queued，runner_name 为空，15 分钟后 cancelled
注解：The job was not acquired by Runner of type hosted
原因：macOS runner 容量不足，与代码无关

应对：
· 不要反复 dispatch，白等 15 分钟
· 换 macos-13 也一样（仍是 macOS 池）
· 等几小时后重新 dispatch，或等 push 自动触发
· 判断依据：changes（ubuntu）能跑起来但 build 拿不到机器，就是排队问题
```

### 编译错误重灾区

```
1. 字符串引号不配对
   DYYYSettingViewController.m 改协议文案时漏过结尾引号，
   报 unexpected token after Objective-C string。
   改文案后必须检查引号。

2. 宏不能用在 %hook / %init
   logos.pl 早于 cpp，会生成 objc_getClass("DYYY_T_XXX") 拿不到类。

3. 前向声明缺失
   用了新类的方法要先在 AwemeHeaders.h 补 @interface / 方法声明。
```

---

## 二、已完成（近期）

| 版本 | 内容 | 状态 |
|---|---|---|
| **v100** | HDR 改为亮度上限，移除降画质与吞作品的干预 | ✅ 待构建 |
| **v98** | h264 兜底项改排最后，让 bytevc2 先被尝试 | ✅ |
| **v97** | bytevc2 转码入库（passthrough → HEVC → H.264 分级） | ✅ 代码生效，但源不可解 |
| **v96** | 候选列表补 h264 兜底 + gearName 解析分辨率 | ✅ |
| **v95** | 视频保存改为候选列表 + 失败降级，移除规格 Toast | ⚠️ h264 未进候选导致全失败 |
| **v87** | 群聊进度条作用域限制 + 隐藏评论分享接 Element 过滤 | ⚠️ 两项均未生效（见 P1/P2） |
| **v86** | 文案下移：hook 点从 ScrollView 改到 DescriptionLabel | ✅ **用户已确认修复** |
| **v85** | 41.1 缺失类处理（试修/保留/标注 4 项） | 部分有效 |
| **v84** | 署名 CREDITS.md + 兼容性报告 + hook 计数标定（1671→692） | ✅ |
| **v83** | 适配 41.1.0（ImageContentView mangled 回退）+ 诊断开关合并 | ✅ |
| **v82** | 修自检两 bug（hook 计数恒 0、Swift 类误报） | ✅ |
| **v81** | 回滚 #80 宏替换灾难（logos.pl 早于 cpp） | ✅ |

**兼容性报告当前数据（41.1.0）**：
```
目标类命中  317 / 324  (97.8%)
hook 生效数  692 / 739
未命中       7 项（含 1 个占位名、1 个已废弃活动类）
```

### 视频保存质量 —— 已定案（v98）

**结论：无水印 = playAddr/h264，画质上限 720p，本地无解。**

关键事实（v94–v98 真机日志确认）：

| 字段 | 语义 | 水印 | 画质 |
|---|---|---|---|
| `playAddr`（bitrateModels 内） | 播放流 | **无** | 高画质档为 bvc2，常见 540p/720p |
| `h264URL` | H.264 兼容流 | **无** | 720p 封顶 |
| `downloadURL` | 下载流 | **有** | 可达 1080p |
| `endWatermarkDownloadURL` | 片尾水印版 | **有** | — |
| `captionWatermarkDownloadURL` | 字幕水印版 | **有** | — |

**`codec=bvc2` 是字节私有编码，不是标准 HEVC**：

```
[transcode] 源: 576x1024 codec=bvc2 0.48MB
[transcode] passthrough 失败: 操作已停止
[transcode] hevc 失败: 操作已停止
[transcode] h264 失败: 操作已停止
```

AVFoundation 在解码阶段直接放弃 → 转码路径对 bvc2 无效，
FFmpeg 官方也不支持该系统自定义编码。**1080p 无水印在本地不可能拿到。**

**保存路径现状**：

```
DYYYWatermarkFreeVideoCandidates 产出候选列表：
  · bitrateModels 各档 playAddr（含 bvc2）
  · 末尾追加 h264URL（gear = h264_fallback，排序永远最后）
排序：h264_fallback 最后 → 分辨率面积 ↓ → 码率 ↓
下载：codec == 2 走转码分级，其余直接入库；失败自动降级下一档
```

**注意**：`h264_fallback` 的宽高取自 `videoModel.width/height`（名义值，
常标 1080x1920，实际文件多为 720p），**不能参与面积排序**，否则会挤掉高画质档。

---

## 三、关键结论存档（勿重复试错）

### 适配机制

- **`#define` 宏不能用于 `%hook` / `%init`** —— logos.pl 在 cpp 宏展开之前解析，
  会生成 `objc_getClass("DYYY_T_XXX")`，运行时查不到 → #80 全部 739 个 hook 挂空。
  唯一动态类名方式：`%group` + `%init(Group, Placeholder = runtimeClass)`。
- `%group` 与 `%init` 必须**同文件**；`%init` 占位符必须与紧随其后的 `%hook` 标识符**完全一致**。
- Swift 类在运行时注册为**点号形式**（`Module.Class`），
  `NSClassFromString` 支持点号名；mangled（`_TtC…`）需解析后才能查。
- hook 生效数统计**不能靠方法名前缀猜**（不同 theos generator 格式不同），
  正确做法：判断 `method_getImplementation` 是否落在本 dylib 的 `__TEXT` 段范围。
  且必须**收窄到目标类**，否则会把自有方法算进去（#83 实测 1671 vs 期望 739）。

### 全屏几何（FROZEN —— 已冻结，只在抖音改版导致失效时才动）

- 四条机制：表高唯一写入通道 / 七入口同源 / 行高只回答 / 容器钉满
- 41.1 详情表写入全走基类 `AWEFeedDataSafeTableView.setFrame:`
- 行高查询点不决定建行（无条件答 926 无效）
- 落点计算与表撑高不能同一入口抢跑（二选一必错）
- 点A弹B = 926 落点体系 + 843 旧 cell 残留混住同 offset；对齐在翻页入口做
- 这套机制经过长期验证，**不做"为了优雅"的重构**（#61–#77 共 17 版证明）

### 41.1 类名变更记录

| 功能 | 41.0 类名 | 41.1 现状 |
|---|---|---|
| 文案容器 | `AWEPlayInteractionDescriptionScrollView` | 已移除 → 用 `AWEPlayInteractionDescriptionLabel`（往上两层是容器） |
| 图文图片视图 | `BDMultiContentContainer.ImageContentView` | 只剩 mangled `_TtC23BDMultiContentContainer16ImageContentView` |
| 评论商品位 | `AWECommentPanelHeaderSwiftImpl...View` | 迁移到 `AWECommentCommerceSwiftImpl` 模块 |
| 长按菜单「分享给朋友」 | `AWEIMCommentShareTableViewCell` | `AWEIMShareImpl.ShareCommentHorizontalSectionViewModel` |
| 招财猫 | `AWELuckyCatBannerView` | 限时活动，未注册；新方案 `AITXBridgeUgLuckycatShowLottieAsBanner` |

### 其他

- 扳手挂载不能放 `DYYYSettingsGesture` group（受开关守卫）
- UIButton 点击必须 `addTarget`，`touchesEnded` 手动实现不可靠
- 闪退排查优先级：`.ips` 崩溃报告 > 日志 > 截图
- `UIAlertController` 在场时 `topPresenter` 会拿到菜单自身 —— handler 先 dismiss 再动作
- 后台 dispatch block 里的异常，调用方 `@try` 包不住 —— 后台写入必须自己 `@try`

---

## 四、诊断工具使用

**设置 → 诊断工具**

```
诊断模式      开 → 屏幕出现扳手 + 日志全开
              关 → 扳手消失 + 日志静默（热路径零开销）
兼容性报告    目标类命中数 + 未命中类名 + hook 生效数
              [复制完整清单] [重新检测]
导出日志      写文件到 DYYY/logs/
清空日志
```

**导出诊断包（扳手 → 导出）内容**：
```
manifest.json          设备/版本/屏幕/页面标识
compat/audit.txt       兼容性报告
compat/class-list.txt  运行时类清单（抖音前缀过滤，~108k 类）
compat/target-methods.txt  目标类方法清单
page/view-tree.txt     完整视图树（含类名/frame/vc）
page/view-controllers.txt  VC 栈
probe/runtime.log      运行流水（2MB 轮转）
crash/                 最多 5 个 .ips 崩溃报告
screenshot.png         全窗口合成截图
```

> 视图树是定位类名变更的**最强工具** —— P1 的根因就是靠它查出来的。

---

## 五、41.1 运行分析结论（2026-11-13）

### 保存质量字段（已确认存在）

| 媒体 | 字段优先级 | 收益 |
|---|---|---|
| 作品视频 | `endWatermarkDownloadURL` → `captionWatermarkDownloadURL` → `downloadURL` → `playURL` | 无水印 + 原画质 |
| 作品图片 | `watermarkFreeUrlList` → `downloadURLList` → `urlList` | 无水印 |
| 视频封面 | `originCover` → `universalCoverUltimate` → `coverURL` | 原图 |
| 他人头像 | `avatarLarger` → `avatar300` → `avatarMedium` → `avatarThumb` | 大尺寸 |
| 评论图片 | `downloadUrl` → `originUrl` → `mediumUrl` | 下载流 |
| 评论表情 | `staticURLModel` / `animateURLModel` | 已最优 |
| 评论语音 | `audioUrl` | 已最优 |
| 评论实况 | `videoUrl` | 已最优 |
| 视频音乐 | `playURL` | 无高音质字段 |

**宿主类**：`AWEVideoModel`（85 属性）、`AWEImageAlbumImageModel`（38 属性）、
`AWECommentImageModel`（8 属性）、`AWEUserModel`。

### 亮度控制（解决 HDR 夜间刺眼）

`AWEVideoPlayerScreenBrightnessManager` —— 播放器亮度控制器，23 个方法：

```
adjustScreenBrightnessToTargetBrightness    调亮度核心入口
setTargetBrightness: / targetBrightness     目标亮度（可截断）
isHDRVideo / setIsHDRVideo:                 是否 HDR 视频
enableBrightnessAdjust / setEnableBrightnessAdjust:   总开关
restoreOriginalBrightness                   退出恢复
p_watchForUserScreenBrightnessChange:       用户手动调就放弃控制
```

`AWEBDSimPlayerBizConfig.getHDRBrightnessThreshold` —— HDR 亮度阈值。

**已排除的误导项**：
- `BrightnessEnhanceManager` 在 `CreativePerform`（创作）目录，**不管播放**
- `IESVSWatermarkServiceImpl` 是直播/短剧水印，**不是播放水印**
- `disable_video_max_brightness_mean` 只是 VEK 配置 key，改不了

### HDR 处理 —— 已定案（v100）

**旧做法全部废弃（两个函数改为恒返回 NO，120 处干预点自动失效）：**

| 旧做法 | 后果 |
|---|---|
| 过滤 HDR 码率档 | 真 HDR 作品没有可播档，整条跳过 |
| 改写 `hdrType` / `hdrBit` | 解码器按 SDR 解 HDR 流，失败 |
| LUT 置 nil | 色调映射缺失，画面发灰 |
| 命中后 `return nil` | 作品从推荐流直接消失 |

**新做法：只限制屏幕亮度上限。**

```objc
%hook AWEVideoPlayerScreenBrightnessManager
- (void)setTargetBrightness:(CGFloat)targetBrightness {
    CGFloat cap = DYYYHDRBrightnessCapValue();
    if (cap <= 0) { %orig; return; }

    BOOL hdr = [self isHDRVideo];
    BOOL bigJump = (targetBrightness > [self originBrightness] + 0.25);
    if (!hdr && !bigJump) { %orig; return; }

    %orig(MIN(targetBrightness, cap));
}
%end
```

**双条件判断的意义**：`isHDRVideo` 可能尚未写入（setter 顺序不确定），
再用「目标亮度比原始亮度高出 0.25 以上」这个特征兜底。
两者都不满足时原样放行，保证普通视频零影响。

**为什么不改流**：官方播放 HDR 时解码出来始终是 HDR 数据，
亮度调节发生在显示层（EDR 增益），不降画质。
任何改数据层的做法（换流 / 去 LUT）都会降画质。

**设置项**：`DYYYHDRBrightnessCap` = 关闭 / 40% / 50% / 60% / 70% / 80% / 90%，默认关闭。

**待验证**：IM（聊天）里的视频是否也走同一个亮度管理类。
日志 `[DYYY][hdr]` 会在两边都打印，实测确认后再决定是否需要单独处理
`IESIMVideoPlayerWrapper.setupHDREnable:`。

### 消息防撤回相关类

```
AWEIMRecallMessage                 37 方法 / 15 属性
  · recalledMsg                    被撤回的原消息（内容仍在）
  · recallUserID / recallerRole / recalledTime

LSIMBizConversation               104 方法 / 61 属性
  · messageDidUpdate:              消息更新（撤回替换入口）★
  · messagesDidInsert:reason:

TIMXLongConnectionClient           37 方法
  · notifyWillHandleMessageWithCallbacks:message:   消息处理前钩子 ★
```

### 开发工具

`tools/aweme_classdump.js` —— Mach-O 解析器。可从脱壳二进制反查
「selector → 宿主类」与「类 → 全部方法/属性」。
用法与实现要点（含 relative method list 必须二次解引用这个坑）见 `tools/README.md`。

