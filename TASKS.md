# DYYY 项目任务清单（持续更新）

## 当前版本
- 最新发布: DYYY_2.2-9#37（commit a916ea04，19:16 发布）
- CI: 90秒出包（arm64 直出 dylib + 清理陈旧中间产物 step），稳定

## #33 → #37 完成的修复（全部已在 #37 里）
| 项 | 版本 | 状态 |
|---|---|---|
| 详情页全屏 + 底栏透明 | #33 | ✅ 你已确认 |
| 点A弹B（对齐挂翻页入口） | #34 | ⏳ 等你确认 |
| 扳手悬浮入口（addTarget 点击 + 顶层 hook + 即时刷新） | #35/#36 | ⏳ 等你确认 |
| 导出诊断包闪退（两处：presentation 冲突 + 后台写入无人接异常） | #36/#37 | ⏳ 等你确认 |
| 截图全窗口合成（视频画面在） | #36 | ⏳ 等你确认 |
| 日志尾部乱码（flush） | #34 | 已修 |
| 命名统一（环境自检/导出日志/清空日志） | #34 | 已修 |
| CI 清理陈旧中间产物 | #36 | 已修 |

## 等用户确认的测试点
1. 点A弹A + 全屏 + 底栏透明
2. 扳手出现 + 单击弹菜单
3. 导出诊断包不闪退 + screenshot.png（视频画面）+ view-tree.txt
4. 各页面输入栏颜色统一

## 排队中（用户确认 #37 测试后开工）
- 输入栏颜色统一收尾（快捷回复栏已接入，观察反馈）
- 冻结长期观察（#24 后未复现）
- 大改第一阶段：拆 DYYY.xm 巨石 + 四层分离 + CI 接 check_compat.sh/tests/
- PROJECT_MAP.md + TASKS.md 提交进仓库

## 关键结论存档（勿重复试错）
- 41.1 详情表写入全走基类 AWEFeedDataSafeTableView.setFrame:（#32 B路110条/A路0条）
- 行高查询点不决定建行（#28 无条件答926无效）
- 落点计算与表撑高不能同一入口抢跑（#26-#29 实测二选一必错）
- 点A弹B = 926落点体系 + 843旧cell残留混住同offset；对齐在翻页入口做（%orig后只改cell.frame）
- 扳手挂载不能放 DYYYSettingsGesture group（受开关守卫）
- UIButton 点击必须 addTarget，touchesEnded 手动实现不可靠
- 闪退排查：.ips 崩溃报告 > 日志 > 截图（用户已提供两份，均直接定位）
- UIAlertController 在场时 topPresenter 会拿到菜单自身——handler 先 dismiss 再动作
- 后台 dispatch block 里的异常，调用方 @try 包不住——后台写入必须自己 @try
- 截图必须全窗口按windowLevel合成 + afterScreenUpdates:NO（画中画2000层/视频画面）
- 日志导出前要串行队列flush（防半行乱码）
- THEOS 缓存中间产物会行号错乱——构建前 rm .theos/obj；THEOS_FORCE_COMPILE 全量重编会撞15分钟墙
