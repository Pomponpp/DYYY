# 外部产物登记（ARTIFACTS）

> 这些文件体积大或含敏感内容，**不进 git**，只在本文件记录"在哪、是什么、怎么来的"。
> 迁移机器时按本表重新准备，而不是复制仓库。

---

## 1. 抖音砸壳二进制（兼容扫描用）

| 项 | 值 |
|---|---|
| 路径 | `C:\Users\Administrator\Documents\deepseek-harness\default-workspace\ipa41\AwemeCore` |
| 体积 | 1,051,394,160 字节（约 1.05 GB） |
| 来源 | 抖音 41.1.0 IPA 的 `Payload/Aweme.app/Frameworks/AwemeCore.framework/AwemeCore` |
| 加密状态 | 已脱壳（cryptid=0），类名明文，可直接 grep |
| 用途 | `scripts/check_compat.sh` 的唯一输入 |
| 重建方法 | `unzip -j "抖音_41.1.0.ipa" "Payload/*.app/Frameworks/AwemeCore.framework/AwemeCore"` |

---

## 2. 抖音框架集合

| 项 | 值 |
|---|---|
| 路径 | `C:\Users\Administrator\Documents\deepseek-harness\default-workspace\fw\` |
| 体积 | 约 1.1 GB |
| 内容 | `AWEExtensionsFramework` / `AWESearchFramework` / `AwemeCore` / `ByteRtsEngineKit` / `EffectSDKFramework` / `OmniStream` / `RTCLive` / `RTCLiveNICOExtension` / `RTCLiveScreenCapturer` / `AudioXAAC` |
| 用途 | 当某类不在 `AwemeCore` 里时，到这些 Framework 里二次查找 |
| 重建方法 | 从 IPA 的 `Frameworks/` 目录整包解出 |

---

## 3. 抖音安装包（IPA）

| 项 | 值 |
|---|---|
| 41.1.0 | 用户提供（砸壳版），路径见上两条的源 |
| 41.0.0 | 历史版本，曾用名 `抖音_41.0.0.ipa` |
| 用途 | ① 重新砸壳 ② 注入 dylib 重新签名（`scripts/trollstore_package.sh`） |

---

## 4. 构建产物（每次构建生成，不进 git）

| 产物 | 位置 | 说明 |
|---|---|---|
| `DYYY.dylib` | `packages/DYYY.dylib`（CI artifact） | 主产物，2.9 MB 左右 |
| `com.huami.dyyy_*.deb` | `packages/` | rootless / rootful / roothide 三种 scheme |

---

## 5. 历史工作副本（可删，内容与远程一致）

| 路径 | 说明 |
|---|---|
| `...\default-workspace\DYYY_src\` | 旧工作区，`git diff origin/main` 零差异，仅保留历史 commit #1–#19 |
| `...\default-workspace\DYYY_orig_src\` | 上游原版快照 |
| `...\default-workspace\DYYY_wtrwx_src\` | 上游分支快照 |
| `...\default-workspace\DYYY_release_src\` | 某个 Release 的解包源码 |

---

## 6. 历史发布脚本（凭证已失效，仅作机制参考）

| 文件 | 机制 |
|---|---|
| `publish.sh` | 从 CI artifact 下载 `DYYY.dylib` → 改版本号 → `POST /releases` |
| `push.sh` | 读工作区文件 → base64 → `POST /git/blobs` → 建 tree → 建 commit → 推 ref |
| `push_v115.sh` | 同上，v115 专用 |

> ⚠ 三者均曾硬编码 GitHub PAT。**新流程禁止照搬**，改为标准 `git commit && git push`。

---

## 7. 诊断产物（排查时由用户导出）

| 文件 | 内容 |
|---|---|
| `DYDebug-<时间戳>.zip` | 诊断包：日志 / 视图树 / VC 树 / layer 树 / 类 dump / 音频探针 / 截图 / 状态 |
| `DYYY-log-<时间戳>.txt` | 纯运行流水（旧格式） |

导出路径：设置 → 诊断工具 → 导出诊断包；或扳手浮窗 → 导出。

---

## 8. 真机环境

| 项 | 值 |
|---|---|
| 设备 | iPhone 13 Pro Max |
| 系统 | iOS 16.1 |
| 注入方式 | TrollStore（无越狱环境，deb 需提取 dylib 后注入 IPA 重签） |
| 验证方式 | 安装后看日志 `hook 生效数` / `关键类命中数` |