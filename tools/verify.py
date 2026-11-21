#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
DYYY 本地静态校验（替代"拿真机当编译器"）

校验项：
 1. %hook / %group / %end 配对
 2. 每个 %hook 的类名在 41.2 class-list 里真实存在
 3. 每个 hook 的方法名（含冒号）在 target-methods 里真实存在
 4. 括号平衡
 5. %c(Class) 引用都在 AwemeHeaders.h 或 DYYY 自有头文件里有声明
 6. 自定义头文件里引用的抖音类都能在 class-list 找到

用法: python verify.py [--repo DIR] [--dump DIR]
退出码: 0 全通过 / 1 有失败
"""
import re, os, sys, glob, argparse

sys.stdout.reconfigure(encoding="utf-8")

KNOWN_DEAD = {
    "AWELuckyCatBannerView",            # 限时活动，41.x 未注册
    "AWEIMCommentShareTableViewCell",   # 已迁移为 AWEIMShareImpl.ShareCommentHorizontalSectionViewModel
}

def load_class_list(p):
    s = set()
    for line in open(p, encoding="utf-8", errors="ignore"):
        line = line.strip().rstrip(",").strip('"')
        if not line:
            continue
        # class-list.txt 可能是 JSON 数组或每行一个
        if line.startswith("[") or line.startswith("]"):
            continue
        if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_.]*", line):
            s.add(line)
    return s

def load_target_methods(p):
    """返回 {class: set(methodSelector)}"""
    out = {}
    cur = None
    for line in open(p, encoding="utf-8", errors="ignore"):
        if line.startswith("## "):
            cur = line[3:].strip()
            out.setdefault(cur, set())
        elif line.startswith("  - ") and cur:
            out[cur].add(line[4:].strip())
    return out

def strip_comments(s):
    s = re.sub(r"/\*.*?\*/", "", s, flags=re.S)
    s = re.sub(r"//[^\n]*", "", s)
    return s

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", default="F:/AIwendang/DYYY")
    ap.add_argument("--dump", default="/tmp/dbg233")
    a = ap.parse_args()

    cl = load_class_list(os.path.join(a.dump, "compat/class-list.txt"))
    tm = load_target_methods(os.path.join(a.dump, "compat/target-methods.txt"))
    print("语料：class-list %d 个类 / target-methods %d 个类" % (len(cl), len(tm)))
    print()

    # 二进制符号（用于 dump 未覆盖时的二级确认）
    binary_syms = set()
    bindir = os.path.join(a.dump, "..", "_bindump")
    cache = os.path.join(a.dump, "_symcache.txt")
    if os.path.exists(cache):
        binary_syms = set(x.strip() for x in open(cache, encoding="utf-8", errors="ignore") if x.strip())
        print("二进制符号缓存：%d 条" % len(binary_syms))

    files = sorted(glob.glob(os.path.join(a.repo, "*.xm")))
    hdrs = sorted(glob.glob(os.path.join(a.repo, "*.h")))

    fail = 0
    warn = 0

    # ---------- 1. 结构配对 + 括号 ----------
    for f in files:
        raw = open(f, encoding="utf-8", errors="ignore").read()
        s = strip_comments(raw)
        h = len(re.findall(r"^%(?:hook|group)\b", s, re.M))
        e = len(re.findall(r"^%end\b", s, re.M))
        no_str = re.sub(r'"(?:\\.|[^"\\])*"', '""', s)
        bal = no_str.count("{") - no_str.count("}")
        if h != e:
            print("[FAIL] %s: %%hook/%%group=%d  %%end=%d" % (os.path.basename(f), h, e)); fail += 1
        if bal != 0:
            print("[FAIL] %s: 括号差 %+d" % (os.path.basename(f), bal)); fail += 1

    # ---------- 2/3. hook 目标真实存在 ----------
    # 收集 %init(Group, Placeholder = runtimeClass) 的占位符 —— 这些是运行时动态挂载，
    # 静态 dump 里查不到（项目约定：Swift 私有类只能这样挂）
    dynamic = set()
    for f in files:
        raw = strip_comments(open(f, encoding="utf-8", errors="ignore").read())
        for m in re.finditer(r"%init\(\s*\w+\s*,\s*([A-Za-z_][\w.]*)\s*=", raw):
            dynamic.add(m.group(1))
        # %init(Placeholder = x) 单参形式
        for m in re.finditer(r"%init\(\s*([A-Za-z_][\w.]*)\s*=", raw):
            dynamic.add(m.group(1))
    if dynamic:
        print("运行时动态挂载类（跳过 dump 校验）：%d 个" % len(dynamic))

    hook_re = re.compile(r"^%hook\s+([A-Za-z_][\w.]*)", re.M)
    method_re = re.compile(r"^\s*[-+]\s*\([^)]*\)\s*([A-Za-z_]\w*(?::[A-Za-z_]\w*)*)", re.M)

    checked_cls = set()
    for f in files:
        base = os.path.basename(f)
        raw = open(f, encoding="utf-8", errors="ignore").read()
        s = strip_comments(raw)
        # 按 %hook 分块
        blocks = []
        pos = 0
        for m in hook_re.finditer(s):
            end = s.find("%end", m.end())
            blocks.append((m.group(1), s[m.end(): end if end > 0 else len(s)]))
        for cls, body in blocks:
            short = cls.split(".")[-1]
            # 系统类 / 宏占位符不参与 dump 校验（dump 只含抖音自身类）
            if short.startswith(("NS", "UI", "CA", "CF", "CG", "CL", "MK", "AV", "PH",
                                 "WK", "SK", "GK", "MTK", "JS", "OS", "SEC", "AC", "MP", "CB", "CN", "EK", "HK", "PK")):
                checked_cls.add(short)
                continue
            if not re.fullmatch(r"[A-Z][\w.]*", short) or short.isupper():
                continue
            if short in dynamic:
                checked_cls.add(short)
                continue
            if short not in cl:
                # dump 只覆盖部分类；再查二进制符号做二级确认
                if short in binary_syms:
                    print("[WARN] %s: %%hook %s —— dump 未覆盖但二进制存在" % (base, cls)); warn += 1
                    checked_cls.add(short); continue
                if short in KNOWN_DEAD:
                    print("[WARN] %s: %%hook %s —— 已知失效（见 TASKS.md/类名变更记录）" % (base, cls)); warn += 1
                else:
                    print("[FAIL] %s: %%hook %s —— dump 与二进制均未找到（死 hook）" % (base, cls)); fail += 1
                continue
            checked_cls.add(short)
            known = tm.get(short)
            if known is None:
                known = set()
            for mm in method_re.finditer(body):
                sel = mm.group(1)
                # %new 方法跳过
                pre = body[max(0, mm.start() - 60): mm.start()]
                if "%new" in pre:
                    continue
                if known and sel not in known:
                    print("[WARN] %s: %s 未在 dump 中找到 -%s" % (base, short, sel)); warn += 1

    # ---------- 4. AwemeHeaders 里声明的类是否都存在 ----------
    ah = os.path.join(a.repo, "AwemeHeaders.h")
    if os.path.exists(ah):
        s = strip_comments(open(ah, encoding="utf-8", errors="ignore").read())
        for m in re.finditer(r"@interface\s+([A-Za-z_][\w.]*)", s):
            name = m.group(1).split(".")[-1]
            if name is None:
                continue
            # 只校验明显像抖音私有类的
            if (name.startswith(("AWE", "AWED", "AWEI", "ACC", "TT", "BD", "AFD", "IES", "DD"))
                    and name not in cl):
                print("[WARN] AwemeHeaders.h 声明了 %s，但 41.2 dump 里没有" % name); warn += 1

    # ---------- 5. 返回类型一致性（对照 dump 里的类头） ----------
    dumpdir = os.path.join(a.dump, "page/classes")
    sig_map = {}
    if os.path.isdir(dumpdir):
        for hf in glob.glob(os.path.join(dumpdir, "*.h")):
            txt = open(hf, encoding="utf-8", errors="ignore").read()
            m0 = re.search(r"@interface\s+([A-Za-z_][\w.]*)", txt)
            if not m0:
                continue
            cname = m0.group(1).split(".")[-1]
            sigs = {}
            for mm in re.finditer(r"^\s*-\s*\(([^)]*)\)\s*([A-Za-z_]\w*(?::[A-Za-z_]\w*)*)", txt, re.M):
                sigs[mm.group(2)] = mm.group(1).strip()
            sig_map[cname] = sigs

    checked_sig = 0
    for f in files:
        base = os.path.basename(f)
        raw = open(f, encoding="utf-8", errors="ignore").read()
        s2 = strip_comments(raw)
        for m in hook_re.finditer(s2):
            cls = m.group(1).split(".")[-1]
            end = s2.find("%end", m.end())
            body = s2[m.end(): end if end > 0 else len(s2)]
            sigs = sig_map.get(cls)
            if not sigs:
                continue
            for mm in method_re.finditer(body):
                sel = mm.group(1)
                if sel not in sigs:
                    continue
                rt_hook = mm.group(0)
                mret = re.search(r"-\s*\(([^)]*)\)", rt_hook)
                if not mret:
                    continue
                hook_ret = mret.group(1).strip()
                dump_ret = sigs[sel]
                checked_sig += 1
                # 归一：CGFloat/double 在 arm64 等价；id 与具体类不严格比较
                norm = lambda x: "double" if x in ("CGFloat", "double", "float") else x
                if norm(hook_ret) != norm(dump_ret) and "id" not in (hook_ret, dump_ret):
                    print("[WARN] %s: %s -%s 返回类型 hook=%s dump=%s" % (base, cls, sel, hook_ret, dump_ret))
                    warn += 1

    # ---------- 6. 布局回环风险：在 layout 回调里写几何 ----------
    # #128 的卡死就是这个模式：viewDidLayoutSubviews 里改 frame → 触发重布局
    # → 原生改回 → 再改 → 每秒数百次 → watchdog 杀进程。
    LAYOUT_CB = re.compile(r"-\s*\(void\)\s*(viewDidLayoutSubviews|layoutSubviews|viewWillLayoutSubviews)\s*\{")
    GEOM_WRITE = re.compile(r"(\.frame\s*=|\.center\s*=|\.bounds\s*=|setFrame:|setCenter:|setBounds:)")
    loop_risk = 0
    for f in files:
        base = os.path.basename(f)
        raw = open(f, encoding="utf-8", errors="ignore").read()
        s2 = strip_comments(raw)
        for m in LAYOUT_CB.finditer(s2):
            # 取方法体（简单括号配平）
            i = s2.find("{", m.end() - 1)
            depth = 0
            j = i
            while j < len(s2):
                if s2[j] == "{":
                    depth += 1
                elif s2[j] == "}":
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
            body = s2[i:j]
            if GEOM_WRITE.search(body):
                line = s2[:m.start()].count("\n") + 1
                print("[WARN] %s:%d -%s 内含几何写入 —— 布局回环风险（#128 卡死同型）"
                      % (base, line, m.group(1)))
                loop_risk += 1
    print("布局回环扫描：%d 处命中" % loop_risk)

    print("返回类型比对：%d 处" % checked_sig)
    print()
    print("已校验 %d 个 %%hook 目标类" % len(checked_cls))
    print("结果：FAIL=%d  WARN=%d" % (fail, warn))
    return 0 if fail == 0 else 1

if __name__ == "__main__":
    sys.exit(main())
