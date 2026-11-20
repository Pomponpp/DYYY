# DYYY 交接文档（HANDOFF）

> 生成：2026-11-20　交接基线：`91a86ba`（dylib 版本号 `DYYY_2.2-9#120`）
> 用途：任何人（包括三个月后的自己）接手时，先读这一份再看代码。

---

## 0. 30 秒速览

| 项 | 值 |
|---|---|
| 项目性质 | iOS 越狱插件（Tweak），用 Logos/Objective-C 写，Theos 编译 |
| 作用对象 | 抖音（Aweme）UI 与行为定制 |
| 目标版本 | **抖音 41.1.0**（只适配最新版，旧版不维护） |
| 产物 | `DYYY.dylib`（主）+ `com.huami.dyyy_2.2-9_*.deb`（可选） |
| 注入方式 | TrollStore 注入砸壳 IPA，或越狱包管理器安装 |
| 代码规模 | 143 个文件 / 43,841 行 / 339 个 `%hook` |
| 状态 | 功能可用，全屏已重构，诊断子系统完整 |

---

## 1. 真实版本历史 —— 先读这一节，否则会误判项目进度

### 1.1 git 上看到的和历史真相 **不一致**

```
git log  ->  HEAD = 91a86ba  "诊断：进度条位置探针 + 评论分享改从 cell model 取数"
             父提交 b86ccdd / 1fbd23c / 2e90abc ... （同名提交重复多次）
```

**远程这 244 个 commit 不是本地 `git commit` 产生的**，而是用 GitHub API 直接造的
（blob → tree → commit → ref），脚本见 `docs/legacy/push.sh`、`push_v115.sh`。

后果：

- 本地工作副本的 git 索引可能停在很早的提交（例如 `472e082` = #19）
- 工作区文件却是最新代码（脚本从工作区读文件上传）
- 于是 `git status` 会显示"上百个未提交改动"，**实际上这些改动零新增，只是远程代码在本地留下的影子**

**判定方法**（接手时先跑一遍）：

```bash
git fetch origin
git diff origin/main --stat      # 只有 deletions、没有 modifications → 工作区 ≡ 远程
```

### 1.2 结论

- **权威 = GitHub `origin/main`**
- 本地任何"未提交改动"都不要当成新工作，先和 `origin/main` 对比
- 发布流程改造：以后走正常 `commit → push`，不要再用 API 直推脚本

---

## 2. 仓库结构

### 2.1 Hook 入口层（`.xm`）

| 文件 | 职责 |
|---|---|
| `DYYY.xm` | 通用 Hook 大头（179 hook / 19 group），正在拆分 |
| `DYYYHooksFeed.xm` | 首页 Feed（18 hook） |
| `DYYYHooksFullscreen.xm` | 全屏（15 hook） |
| `DYYYHooksLive.xm` | 直播（31 hook） |
| `DYYYHooksMedia.xm` | 媒体/播放器（14 hook） |
| `DYYYHooksProfile.xm` | 个人主页（7 hook） |
| `DYYYHooksComment.xm` | 评论（4 hook） |
| `DYYYHooksSettings.xm` | 设置页（2 hook） |
| `DYYYHooksTabBar.xm` | 底栏（8 hook） |
| `DYYYHooksGlobal.xm` | 全局（5 hook） |
| `DYYYSettings.xm` | 原生设置页改造 + 设置项模型构造（9 hook） |
| `DYYYLongPressPanel.xm` | 长按面板（8 hook / 1 group） |
| `DYYYLoginBypassHooks.xm` | 登录兼容（16 hook / 13 group） |
| `DYYYPrivacyHooks.xm` | 访客/浏览记录拦截（10 hook） |
| `DYYYFeatureHooks.xm` | 引流/直播伴侣提示（7 hook） |
| `DYYYCommentPlaybackHooks.xm` | 评论暂停（2 hook） |
| `DYYYABTestHook.xm` | ABTest 注入（1 hook） |
| `DYYYProgressUnderlineFix.xm` | 进度条黑线修复（3 hook） |
| `DYYYFloatClearButton.xm` | 清屏按钮（0 hook，纯 UI） |

**语法自检基线**：19 个 `.xm`，hook 339 + group 33 = end 372，全平衡。

### 2.2 协调器层（`.m`，业务逻辑）

```
DYYYFullscreenCoordinator     全屏策略/几何应用（最大的一个）
DYYYFullscreenGeometry        纯几何函数（有单测）
DYYYCommentBlurCoordinator    评论毛玻璃
DYYYCommentPlaybackCoordinator 评论暂停 + 看门狗
DYYYFloatingButtonCoordinator 悬浮按钮统一调度（倍速/清屏/诊断扳手三客户端）
DYYYClassRegistry             启动自检（关键类存在性 → 日志报告）
DYYYDiagnostics               运行日志（append/rotate/cleanup/export/audit）
```

### 2.3 诊断子系统 `DYYYDiag/`（21 文件 / 208KB）

```
DKDYYYBridge      桥接层（DYYY ↔ 诊断）
DKShim            依赖打桩
Debug/DKDebugCapture    视图树/layer/VC 树快照
Debug/DKDebugExport     诊断包打包（日志+快照+状态+截图）
Debug/DKDebugInspector  扳手浮窗 / 菜单 / 触发
Debug/DKAudioProbe      音频探针
Debug/DKTabBarProbe     底栏探针
Debug/DKGlassGuard      液态玻璃守卫
FLEX/DKClassDump        类方法/属性 dump
FLEX/DKZipWriter        零依赖 zip
Shared/DKKeys/DKUtils   常量与工具
```

### 2.4 业务与工具

```
DYYYManager(+Scheduler)   下载/保存/合成/ZIP/相册（业务编排层）
DYYYUtils                 无状态工具（含 dumpAllWindowsViewTreeToFile:）
DYYYSettingsHelper        设置依赖、入口查找、协议弹窗
CityManager               IP 属地（GeoNames + 本地映射）
DYYYTargets.h             抖音目标类名集中定义
DYYYShared.h              跨文件共享声明
_header_categories.h      头文件引入顺序约定
AwemeHeaders.h            全部抖音私有类声明（**新增声明必须进这里**）
```

### 2.5 构建与脚本

```
Makefile                  Theos 构建目标
control                   deb 元信息
.github/workflows/        GitHub Actions（macOS runner）
scripts/check_compat.sh   抖音版本兼容扫描（换版本先跑这个）
scripts/trollstore_package.sh  注入砸壳 IPA + ldid 重签 → 可装 IPA
tests/                    3 个单测（几何/悬浮按钮/异步资源）**尚未接进 CI**
tools/                    类名采集脚本
```

---

## 3. 当前功能状态

| 功能 | 状态 | 备注 |
|---|---|---|
| **全屏（首页/详情/清屏/图文）** | ✅ 已重构并稳定 | 表撑满 + 行高只答不改 + setFrame 写入拦截 |
| **底栏透明** | ✅ | 与全屏联动，作品页已单独处理 |
| **评论毛玻璃** | ✅ | 面板级 hook + 分区背景写入拦截 |
| **评论避让视频** | ✅（独立开关，默认关） | 开启时无毛玻璃 |
| **头像保存（他人主页）** | ✅ 重写实现 | 原生长按入口已被抖音删除，改为自行长按手势 + 统一下载 |
| **保存去水印** | ✅ 部分 | 优先 `playURL`（无水印）；bytevc2 私有编码需转码 |
| **诊断工具** | ✅ | 扳手浮窗 5 项菜单 + 诊断包导出（日志/视图树/音频/类 dump/截图） |
| **广告/推荐/剧集等过滤** | ✅ | 300+ 开关 |
| **登录兼容 / 浏览记录拦截** | ✅ | 风险较高，改版优先回归此项 |
| **HDR 亮度上限** | ❌ 已移除 | 试了 6 版全部无效，抖音亮度不走 `UIScreen`，功能已删 |

---

## 4. 已知坑（血泪清单，改代码前必读）

| # | 坑 | 教训 |
|---|---|---|
| **1** | **`%hook` 不能用宏展开类名** | 曾把 321 处 `%hook 真实类名` 替换成 `%hook DYYY_T_XXX`，结果 **739 个 hook 全部失效、所有功能消失**。Logos 的 `%hook` 接受的是 token，不做宏展开。要集中类名只能靠"生成代码"或"字符串常量"，**不能靠 #define** |
| **2** | **亮度限制会误伤全站** | 用"亮度突变"判断 HDR，结果普通视频也被压暗。任何全局副作用必须限定作用域（按页面/按播放器实例） |
| **3** | **`writeToFile` 在诊断导出里连崩 4 版** | 崩溃根因是路径/权限/后台时机组合。最终改为"先写入 App 容器 tmp + 主线程串行 + 完成后才弹分享" |
| **4** | **大范围删除必须外层→内层** | 887 行死代码清理时，先删被调用的函数会留下悬空调用，必须从最外层 hook 往里删，每批编译验证 |
| **5** | **`dispatch_sync(main_queue)` 在点击回调里 = 死锁** | 设置页点导出直接卡死。主线程回调里永远别 sync 主队列 |
| **6** | **全屏禁止逐帧改写 view frame** | 外部每帧写媒体容器 frame 会打停 Metal 渲染 → 画面定格、弹幕照滚。正解是"在抖音写入的那一刻顶回去"，不是"布局后再改" |
| **7** | **行高统一会引发"拔河"** | 抖音每帧写 843、我们写 926，交替 46 次/秒。正解：**不碰 inset、行高只回答不主动改** |
| **8** | **macOS runner 15 分钟硬上限** | 双架构 × 三 scheme 会超时被杀，且被杀的 job 不留日志。构建必须控制在 15 分钟内（单架构 + 精简步骤） |

---

## 5. 待办

`TASKS.md` 最后更新停在 **#87（2026-11-13）**，而当前已到 **#120**，两者不同步。以本节为准：

### P1 · 隐藏评论分享（未完成）
- 现象：长按评论 → 分享面板「分享给朋友」栏仍在
- 已定位：该栏由 `AWEIMShareImpl.ShareCommentHorizontalSectionViewModel` 驱动，**不走** `CommentLongPressPanelNormalSectionViewModel`
- 修法：`%group` + `%init` 动态绑定该 Swift 类，开关开启时隐藏整栏
- 最新进展：已在试「从 cell model 取数」的路径（见 `91a86ba` 提交说明）

### P2 · 群聊视频进度条异常（信息不足）
- 需要：异常时的截图、关掉「显示进度时长」是否复现、关掉「清除进度条黑线」是否复现

### P3 · 首页个别视频画面跳动（罕见）
- 仅个别视频复现，需长时间观察

### 结构性待办
- [ ] `TASKS.md` 与实际版本对齐（现落后 33 个版本）
- [ ] `tests/` 三个单测 + `scripts/check_compat.sh` 接进 CI
- [ ] 巨石 `DYYY.xm` 继续拆分（已拆 9 个 `DYYYHooks*.xm`，还剩主体）
- [ ] 发布流程从"API 直推"改为标准 git 流程

---

## 6. 构建

```bash
# 环境：macOS + Theos + iPhoneOS SDK
export THEOS=~/theos
make package                 # → packages/com.huami.dyyy_*.deb
make package DEBUG=0         # 正式包
```

CI（`.github/workflows/build.yml`）：
- runner：`macos-latest`
- **单 job 必须 15 分钟内完成**，否则被 GitHub 强杀
- 产物：`packages/DYYY.dylib`（artifact）

注入到砸壳 IPA：

```bash
./scripts/trollstore_package.sh "抖音 Douyin_41.1.0.ipa" ./DYYY.dylib
# → 输出已注入并重签的 IPA，TrollStore 直接安装
```

依赖：`optool`（注入 load command）、`ldid`（重签）。

---

## 7. 版本兼容验证

换抖音版本后**先跑这个**，再决定改哪里：

```bash
./scripts/check_compat.sh <AwemeCore 路径>
# AwemeCore 来源：unzip -j 抖音.ipa "Payload/*.app/Frameworks/AwemeCore.framework/AwemeCore"
```

输出：hook 目标类在二进制里的存在性清单 + 缺失列表。

**41.1.0 基线**：352 个 `%hook` 目标类中 351 存在（1 个为 Logos 动态绑定占位，正常）。

---

## 8. 凭证与安全

- **历史问题**：旧工作副本的 `.git/config` 与 3 个发布脚本里曾明文存放 GitHub PAT（带 `delete_repo` 权限）
- **本仓库**：clone 时使用无凭证 URL，`.git/config` 干净
- **动作项**：旧 token 应在 GitHub Settings → Developer settings 中 **revoke**
- 需要 push 时用 credential helper 或 SSH，不要把 token 写进脚本

---

## 9. 接手第一周建议

1. 读 `AGENTS.md`（工程约定）+ `PROJECT_MAP.md`（家底档案）+ 本文件
2. `git fetch && git diff origin/main --stat` 确认工作区与远程一致
3. `./scripts/check_compat.sh` 对着目标抖音版本跑一遍，拿到当前基线
4. 找一个低风险开关改一行 → 走完整链路（编译 → 注入 → 真机 → 回滚），熟悉流程
5. 再动 P1

---

## 10. 项目归宿与上游动态（2026-11-20 更新）

### 10.1 上游已恢复维护

原作者仓库 `huami1314/DYYY` 在停滞很久后，**2026-11-20 恢复维护**：

```
4658034  refactor: 适配抖音 41.2.0，重构并升级至 3.0
3e6993c  fix: 评论区毛玻璃、隐藏头像、长按倍速，新增摇一摇导出视图树（3.0.1）
```

上游当前状态：**55 个文件 / 5 个 .xm / 总 hook 约 282 / 适配抖音 41.2.0**。

### 10.2 两边对比

| 维度 | 上游 3.0.1 | 本仓库 #120 |
|---|---|---|
| 抖音版本 | **41.2.0** | 41.1.0 |
| 文件数 | 55 | 143 |
| `.xm` 文件 | 5 | 19（含 9 个 `DYYYHooks*.xm` 拆分件） |
| 总 hook | ≈ 282 | **339** |
| `DYYY.xm` 行数 | 9,238 | 10,466 |
| 架构策略 | **数据层优先**（过滤 model / 改数据源） | **视图层深挖**（hook 布局 / 几何 / 渲染） |
| 全屏（详情页撑满 / 表高拦截 / 文字避让） | ❌ 没有（只有底栏透明 + 按钮隐藏） | ✅ 完整 |
| 诊断子系统 | ⚠ 仅「摇一摇导出视图树」 | ✅ DYYYDiag 21 文件（诊断包 / 类 dump / 截图 / 音频 / 扳手浮窗） |
| 头像保存（他人主页） | ❌ | ✅ 自建长按手势 + 统一下载 |
| 保存去水印（playURL 优先） | ❌ | ✅ |
| 评论毛玻璃 | ✅ | ✅ |
| 抗改版能力 | **强**（改得少，数据层不易碎） | 弱（视图 hook 每次大版本都要重调） |

### 10.3 关键战略差异（决定两边能否合并）

上游的解法是「**把 UI 逻辑下沉到数据层**」——不藏视图，而是让数据源不产出该栏。

```
数据层能做：隐藏某栏 / 过滤内容 / 改文案数值     → 抗改版强
数据层做不了：全屏（必须改视图几何）             → 所以上游没有全屏
              诊断包（本就是看视图的工具）        → 所以上游只有摇一摇视图树
```

**结论：两边是互补关系，不是替代关系。**

### 10.4 观察期策略（当前决定：观察，不追不平）

```
✗ 不追 41.2.0（追了就得重调全屏，而全屏正是上游做不了的那块）
✗ 不合并上游代码（数据层 hook 与视图层 hook 会在同类上打架）

✓ 记录上游每个 Release 的功能变化，重点看它能否摸到全屏
✓ 把全屏 / 诊断 / 保存增强 整理成可独立挂载的补丁集
✓ 借鉴上游「从数据源过滤」的思路改造本仓库里仍然靠「藏视图」实现的开关
```

**丢弃条件**：只有在「上游做出了全屏」或「本仓库不再需要全屏与诊断」时才成立。

---

## 11. 关联资源（不在本仓库内）

| 资源 | 位置 | 说明 |
|---|---|---|
| 抖音 41.1.0 AwemeCore（1.05GB） | `C:\Users\Administrator\Documents\deepseek-harness\default-workspace\ipa41\AwemeCore` | 砸壳二进制，兼容扫描用 |
| 抖音框架集合（1.1GB） | 同目录 `fw\` | 各 Framework 二进制 |
| 旧工作副本（含 `.git` 历史） | 同目录 `DYYY_src\` | 内容与远程一致，可删 |
| 上图 / 发布脚本 | 同目录 `publish.sh` `push.sh` `push_v115.sh` | 历史机制证据，凭证已失效 |

> 上述路径仅作记录，本仓库不引用、不依赖它们。