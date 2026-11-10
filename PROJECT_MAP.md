# DYYY 家底档案（全量重读产出 · 2026-11-06）

> 本文档由对 DYYY_src 全部源文件 + 脱壳抖音 41.1.0 AwemeCore（988MB）的完整交叉验证产出。
> 用途：以后每次改动前先查此档案，不再"临时发现"已有能力。

## 一、源码结构（72 个源文件）

### 巨石文件（大改第一阶段要拆的）
| 文件 | 大小 | 内容 |
|---|---|---|
| DYYY.xm | 434KB | 全部通用 Hook（352 个 %hook 目标的大头）+ 全屏 + 设置逻辑混杂 |
| DYYYSettings.xm | 216KB | 原生设置页改造 + 全部设置项模型构造 |
| DYYYManager.m | 134KB | 下载/保存/合成业务编排 |
| DYYYUtils.m | 105KB | 无状态工具（含视图树 dump，见"被低估的资产"） |
| DYYYLongPressPanel.xm | 77KB | 长按面板 |
| AwemeHeaders.h | 71KB | 全部私有类声明（AGENTS 规范：新增声明必须进这里）|

### 已分层的模块（全屏线已按此模式走）
- DYYYFullscreenCoordinator（59KB）：全屏策略/几何应用
- DYYYFullscreenGeometry（2KB）：纯几何函数，**有配套单测**
- DYYYCommentBlurCoordinator：评论毛玻璃
- DYYYCommentPlaybackCoordinator：评论暂停+看门狗
- DYYYFloatingButtonCoordinator：悬浮按钮统一调度（倍速/清屏，**扳手入口可直接复用**）
- DYYYClassRegistry：启动自检（关键类存在性报告）
- DYYYDiagnostics：运行日志（append/rotate/cleanup/export/clear/audit）

### 测试基建（上游已有，一直没接进 CI！）
- tests/FullscreenGeometryTests.m（几何断言）
- tests/FloatingButtonVisibilityTests.m（悬浮按钮可见性）
- tests/AsyncResourceTests.m
- scripts/check_compat.sh（**hook 目标 vs 二进制存在性扫描，就是这次手工做的事，可 CI 化**）
- scripts/trollstore_package.sh

## 二、41.1 二进制验证结果

- **352 个 %hook 目标类：351 存在 + 1 占位别名，零缺失**（HOOK_TARGET_OWNER_CLASS 为 Logos 动态绑定占位，正常）
- 全屏闭环 7 个关键 selector 全部存在：setupDetailTableView(3) / fixedCellHeight(1) / cellHeightAtIndex:(2) / contentOffsetYForCellAtIndex:(1) / adjustTableViewHeightForTargetIndex:(1) / updateTableViewLayoutForTargetPageIndex:(1) / baseTableViewBottomInset(1)
- 输入栏相关：AWEIMFeedVideoQuickReplayInputViewController(13) / AWECommentInputBackgroundView(5) / CommentInputContainerView(14) / AWEBaseListSectionBackgroundView(2) 全存在

## 三、设置键（356 个）

- UI 可见键 326 个；内部键 30 个（通知名/缓存/位置持久化/迁移标记，正常）
- 全屏相关键：DYYYEnableFullScreen（总闸）、DYYYFullNewDetailTable（实验闭环）、DYYYFullscreenDiag（诊断打点）、DYYYCommentAvoidVideo（避让）、DYYYEnableCommentBlur（毛玻璃）

## 四、被低估的资产（以前不知道/没用的）

1. **DYYYUtils.dumpAllWindowsViewTreeToFile:** —— 视图树 dump 早就写好了，从没接到任何 UI 入口。#32 诊断包直接接上。
2. **scripts/check_compat.sh** —— 版本兼容扫描脚本已存在，没进 CI。大改时接进 workflow 即可。
3. **tests/ 三个测试** —— 能跑，没接进 CI。同上。
4. **DYYYFloatingButtonCoordinator** —— 悬浮按钮的显示/隐藏/位置/评论态协调全部现成，诊断扳手是它的第三个客户端。

## 五、结构性发现（可能解释 #30 出口 0 记录）

- DYYY 对 `AWEAwemeDetailTableView` 有 1 个 hook（setFrame: 出口），但对 `AWEFeedDataSafeTableView` **0 个 hook**。
- 二进制字符串证据 + 一个已验证稳定的同类实现的注释都指向：**详情表不自己实现 setFrame:，继承基类（AWEFeedDataSafeTableView）的写入入口；首页表才自己实现**。
- 推论：#30 把出口拦截装在 `AWEAwemeDetailTableView` 上，Logos 对"类未实现的方法"做 hook 时改到的是**父类实现**（会波及所有子类）或**根本没装到正确的类**——这足以解释"0 条记录"。
- **待验证**（#32 或下一版全屏修复时）：出口拦截应装在 `AWEFeedDataSafeTableView`（基类），而不是 `AWEAwemeDetailTableView`（子类）。

## 六、维护约定（本次重读确认）

- 新增抖音类声明 → AwemeHeaders.h（AGENTS 规范）
- 新能力 → 优先扩 DYYYUtils/DYYYManager/已有 DYYYXXX 类，禁止全局 C 函数
- UI 写操作 → 主线程；弹窗 → DYYYToast/DYYYBottomAlertView
- 注释自述式，不引用外部项目（用户规定）
- 每一步提交/构建/发布 → 单独等用户"推"（用户规定）
