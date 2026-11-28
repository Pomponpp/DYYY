#!/usr/bin/env python3
"""AwemeCore ObjC 元数据解析器（Python 版，无需 Node）。

用法:
  python objcdump.py <binary> --index out.json      # 建立 类/方法/属性 索引
  python objcdump.py <binary> --class AWEVideoModel
  python objcdump.py <binary> --grep Brightness
"""
import sys, json, struct, mmap, os

class MachO:
    def __init__(self, path):
        self.f = open(path, 'rb')
        self.size = os.path.getsize(path)
        self.m = mmap.mmap(self.f.fileno(), 0, access=mmap.ACCESS_READ)
        self.segs = []   # (name, vmaddr, vmsize, fileoff, filesize)
        self.sections = {}  # name -> (addr, size, segname)
        self.encrypted = None
        self._parse()

    def _parse(self):
        m = self.m
        magic, cputype, cpusub, filetype, ncmds, sizeofcmds, flags, res = struct.unpack('<IiiIIIII', m[:32])
        assert magic == 0xfeedfacf, hex(magic)
        off = 32
        for _ in range(ncmds):
            cmd, size = struct.unpack('<II', m[off:off+8])
            if cmd == 0x19:  # LC_SEGMENT_64
                segname = m[off+8:off+24].rstrip(b'\0').decode('utf-8', 'replace')
                vmaddr, vmsize, fileoff, filesize = struct.unpack('<QQQQ', m[off+24:off+56])
                nsects = struct.unpack('<I', m[off+64:off+68])[0]
                self.segs.append((segname, vmaddr, vmsize, fileoff, filesize))
                sp = off + 72
                for _ in range(nsects):
                    sname = m[sp:sp+16].rstrip(b'\0').decode('utf-8', 'replace')
                    saddr, ssize = struct.unpack('<QQ', m[sp+32:sp+48])
                    self.sections[sname] = (saddr, ssize, segname)
                    sp += 80
            elif cmd in (0x2C, 0x21):  # LC_ENCRYPTION_INFO(_64)
                cryptoff, cryptsize, cryptid, _pad = struct.unpack('<IIII', m[off+8:off+24])
                self.encrypted = cryptid
            off += size

    # vmaddr -> file offset（按段映射；抖音二进制多数段 fileoff == vmaddr）
    def foff(self, addr):
        for name, vmaddr, vmsize, fileoff, filesize in self.segs:
            if vmaddr <= addr < vmaddr + vmsize:
                d = addr - vmaddr
                if d < filesize:
                    return fileoff + d
                return None
        return None

    def in_file(self, addr):
        return self.foff(addr) is not None

    def methods_with_types(self, cls_addr):
        """返回 {sel: typeEncoding} for 类的 baseMethods"""
        out = {}
        bits = self.u64(cls_addr + 32) & 0x7ffffffffff8
        if not bits:
            return out
        mlist = self.u64(bits + 32)
        if not mlist:
            return out
        ef = self.u32(mlist)
        entsize = ef & 0x0000fffc
        cnt = self.u32(mlist + 4)
        if entsize < 12 or cnt >= 200000:
            return out
        relative = bool(ef & 0x80000000)
        for k in range(cnt):
            e = mlist + 8 + k * entsize
            try:
                if relative:
                    noff = self.i32(e)
                    sel = self.cstr(self.u64(e + noff))
                    toff = self.i32(e + 4)
                    # 类型串在 __TEXT,__objc_methtype，offset 相对本字段直接指向字符串
                    types = self.cstr(e + 4 + toff)
                else:
                    sel = self.cstr(self.u64(e))
                    types = self.cstr(self.u64(e + 8))
            except Exception:
                continue
            if sel:
                out[sel] = types
        return out

    def u64(self, addr):
        o = self.foff(addr)
        if o is None or o + 8 > self.size:
            return 0
        return struct.unpack('<Q', self.m[o:o+8])[0]

    def i32(self, addr):
        o = self.foff(addr)
        if o is None or o + 4 > self.size:
            return 0
        return struct.unpack('<i', self.m[o:o+4])[0]

    def u32(self, addr):
        o = self.foff(addr)
        if o is None or o + 4 > self.size:
            return 0
        return struct.unpack('<I', self.m[o:o+4])[0]

    def cstr(self, addr, maxlen=512):
        o = self.foff(addr)
        if o is None or o >= self.size:
            return ''
        end = self.m.find(b'\0', o, min(o + maxlen, self.size))
        if end < 0:
            end = min(o + maxlen, self.size)
        return self.m[o:end].decode('utf-8', 'replace')


def build(bin_path, out_json):
    mo = MachO(bin_path)
    cl = mo.sections.get('__objc_classlist')
    if not cl:
        raise SystemExit('找不到 __objc_classlist')
    addr, size, seg = cl
    n = size // 8
    classes = {}
    sel_index = {}
    for i in range(n):
        cls_addr = mo.u64(addr + i * 8)
        if not cls_addr:
            continue
        bits = mo.u64(cls_addr + 32) & 0x7ffffffffff8
        if not bits:
            continue
        name = mo.cstr(mo.u64(bits + 24))
        if not name:
            continue
        super_addr = mo.u64(cls_addr + 8)
        super_name = ''
        if super_addr:
            sbits = mo.u64(super_addr + 32) & 0x7ffffffffff8
            if sbits:
                super_name = mo.cstr(mo.u64(sbits + 24))
        super_in_file = bool(super_addr) and mo.in_file(super_addr)
        methods = []
        mlist = mo.u64(bits + 32)
        if mlist:
            entsize_flags = mo.u32(mlist)
            entsize = entsize_flags & 0x0000fffc
            cnt = mo.u32(mlist + 4)
            if entsize >= 12 and cnt < 200000:
                relative = bool(entsize_flags & 0x80000000)
                for k in range(cnt):
                    e = mlist + 8 + k * entsize
                    if relative:
                        noff = mo.i32(e)
                        sel_slot = e + noff
                        s = mo.cstr(mo.u64(sel_slot))
                    else:
                        # 绝对指针格式
                        s_p = mo.u64(e)
                        s = mo.cstr(s_p)
                    if s:
                        methods.append(s)
                        sel_index.setdefault(s, []).append(name)
        props = []
        cmethods = []
        misa = mo.u64(cls_addr)
        if misa:
            mbits = mo.u64(misa + 32) & 0x7ffffffffff8
            if mbits and mbits != bits:
                cmlst = mo.u64(mbits + 32)
                if cmlst:
                    cef = mo.u32(cmlst)
                    ces = cef & 0x0000fffc
                    ccnt = mo.u32(cmlst + 4)
                    if ces >= 12 and ccnt < 200000:
                        crel = bool(cef & 0x80000000)
                        for k in range(ccnt):
                            e = cmlst + 8 + k * ces
                            if crel:
                                s = mo.cstr(mo.u64(e + mo.i32(e)))
                            else:
                                s = mo.cstr(mo.u64(e))
                            if s:
                                cmethods.append(s)
        plist = mo.u64(bits + 64)
        if plist:
            pentsize = mo.u32(plist) & 0x0000fffc
            pcnt = mo.u32(plist + 4)
            if pentsize >= 16 and pcnt < 50000:
                for k in range(pcnt):
                    e = plist + 8 + k * pentsize
                    noff = mo.i32(e)
                    pname = mo.cstr(e + noff)
                    if pname:
                        props.append(pname)
        ivars = []
        ilist = mo.u64(bits + 48)
        if ilist:
            ientsize = mo.u32(ilist) & 0x0000fffc
            icnt = mo.u32(ilist + 4)
            if ientsize >= 24 and icnt < 50000:
                for k in range(icnt):
                    e = ilist + 8 + k * ientsize
                    noff = mo.i32(e + 8)  # ivar_t: offset(4)? 实际: ivarOffset(8)+nameOff... 兜底 try
                    ivname = mo.cstr(e + noff)
                    if ivname:
                        ivars.append(ivname)
        classes[name] = {
            'super': super_name,
            'super_in_file': super_in_file,
            'addr': cls_addr,
            'methods': sorted(set(methods)),
            'cmethods': sorted(set(cmethods)),
            'props': sorted(set(props)),
            'ivars': sorted(set(ivars)),
        }
    data = {'binary': bin_path, 'cryptid': mo.encrypted, 'class_count': len(classes),
            'segments': mo.segs, 'classes': classes}

    # ---------- 追加 category 方法（分类里的方法不在类自身 method list 里）----------
    cat = mo.sections.get('__objc_catlist')
    cat_added = 0
    if cat:
        caddr, csize, _ = cat
        for k in range(csize // 8):
            ent = mo.u64(caddr + k * 8)
            if not ent:
                continue
            clsptr = mo.u64(ent + 8)
            if not clsptr:
                continue
            bits = mo.u64(clsptr + 32) & 0x7ffffffffff8
            if not bits:
                continue
            cname = mo.cstr(mo.u64(bits + 24))
            if cname not in classes:
                continue
            for slot in (ent + 16, ent + 24):
                mlist = mo.u64(slot)
                if not mlist:
                    continue
                ef = mo.u32(mlist)
                entsize = ef & 0x0000fffc
                cnt = mo.u32(mlist + 4)
                if entsize < 12 or cnt >= 200000:
                    continue
                relative = bool(ef & 0x80000000)
                extra = []
                for j in range(cnt):
                    e = mlist + 8 + j * entsize
                    if relative:
                        noff = mo.i32(e)
                        s = mo.cstr(mo.u64(e + noff))
                    else:
                        s = mo.cstr(mo.u64(e))
                    if s:
                        extra.append(s)
                if extra:
                    cur = set(classes[cname]['methods'])
                    before = len(cur)
                    cur.update(extra)
                    cat_added += len(cur) - before
                    classes[cname]['methods'] = sorted(cur)
                    classes[cname]['has_category'] = True
    data['category_methods_added'] = cat_added
    with open(out_json, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False)
    # 人类可读索引
    txt = out_json.rsplit('.', 1)[0] + '.txt'
    with open(txt, 'w', encoding='utf-8') as f:
        for name in sorted(classes):
            c = classes[name]
            f.write(f'CLASS {name} : {c["super"]}\n')
            for s in c['methods']:
                f.write(f'  - {s}\n')
            for s in c['methods']:
                f.write(f'  + {s}\n')
            for pn in c['props']:
                f.write(f'  P {pn}\n')
    print(f'类 {len(classes)} 个, selector {len(sel_index)} 个 -> {out_json}')
    return data


if __name__ == '__main__':
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(0)
    binp = args[0]
    if '--index' in args:
        build(binp, args[args.index('--index') + 1])
    elif '--class' in args:
        d = build(binp, os.path.join(os.path.dirname(os.path.abspath(binp)), '_tmp_index.json'))
        c = d['classes'].get(args[args.index('--class') + 1])
        print(json.dumps(c, ensure_ascii=False, indent=1) if c else '未找到')
    elif '--grep' in args:
        d = build(binp, os.path.join(os.path.dirname(os.path.abspath(binp)), '_tmp_index.json'))
        kw = args[args.index('--grep') + 1]
        for n in sorted(d['classes']):
            if kw.lower() in n.lower():
                print(n)
