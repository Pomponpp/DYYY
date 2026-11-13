#!/usr/bin/env node
/**
 * aweme_classdump.js —— 从脱壳的 AwemeCore 二进制中提取 ObjC 类信息
 *
 * 用途：
 *   1. 列出任意类的全部方法 / 属性
 *   2. 反向查找任意 selector 的宿主类
 *   3. 按关键字模糊搜索类名
 *
 * 背景：
 *   抖音私有 API 的类名与 selector 在改版时经常变化。
 *   静态扫字符串只能确认"名字存在"，无法确认"属于哪个类"。
 *   本工具解析 Mach-O 的 __objc_classlist / class_ro_t / method_list_t，
 *   建立 类 ↔ 方法/属性 的双向索引，解决定位问题。
 *
 * 用法：
 *   node aweme_classdump.js <AwemeCore 路径> --class AWEVideoModel
 *   node aweme_classdump.js <AwemeCore 路径> --sel setTargetBrightness:
 *   node aweme_classdump.js <AwemeCore 路径> --grep Brightness
 *   node aweme_classdump.js <AwemeCore 路径> --class AWEVideoModel --match water
 *
 * 依赖：
 *   仅 Node.js（无第三方包）。二进制需为已脱壳的 arm64 Mach-O。
 *
 * 实现要点（踩过的坑，勿改）：
 *   1. 段表里 vmaddr == fileoff，可直接把 vmaddr 当文件偏移用。
 *   2. class_t: isa(8) superclass(8) cache(16) bits(8) → bits 在 +32。
 *   3. bits & 0x7ffffffffff8 取 class_ro_t 指针。
 *   4. class_ro_t: flags/instanceStart/instanceSize/reserved 各 4 字节，
 *      然后 ivarLayout(8) name(8) baseMethods(8) baseProtocols(8)
 *      ivars(8) weakIvarLayout(8) baseProperties(8)
 *      → name 在 ro+24，baseMethods 在 ro+32，baseProperties 在 ro+64。
 *   5. 现代 method_list_t 是 relative 格式（entsizeAndFlags & 0x80000000）：
 *      nameOffset 是【相对该字段本身】的 int32，
 *      且指向的是 __objc_selrefs 里的槽位，**必须二次解引用**才拿到字符串。
 *      这是最容易错的一步。
 */

const fs = require('fs');

const args = process.argv.slice(2);
if (args.length < 1 || args[0] === '--help' || args[0] === '-h') {
  console.log(fs.readFileSync(__filename, 'utf8').split('*/')[0]);
  process.exit(0);
}

const BIN = args[0];
if (!fs.existsSync(BIN)) {
  console.error('找不到文件: ' + BIN);
  process.exit(1);
}
const SIZE = fs.statSync(BIN).size;

function flag(name) {
  const i = args.indexOf('--' + name);
  return i >= 0 ? (args[i + 1] || '') : null;
}
const wantClass = flag('class');
const wantSel = flag('sel');
const wantGrep = flag('grep');
const wantMatch = flag('match');

const fd = fs.openSync(BIN, 'r');

function readAt(addr, len) {
  const b = Buffer.alloc(len);
  fs.readSync(fd, b, 0, len, addr);
  return b;
}
function readU64(addr) { return Number(readAt(addr, 8).readBigUInt64LE(0)); }
function readU32(addr) { return readAt(addr, 4).readUInt32LE(0); }
function readStr(addr) {
  if (!addr || addr < 0x1000 || addr >= SIZE) return '';
  const b = readAt(addr, 300);
  const nul = b.indexOf(0);
  return (nul >= 0 ? b.slice(0, nul) : b).toString('utf8');
}

// ---------- 定位 __objc_classlist ----------
function locateClasslist() {
  const hdr = readAt(0, 32);
  if (hdr.readUInt32LE(0) !== 0xfeedfacf) {
    throw new Error('不是 64 位 Mach-O');
  }
  const ncmds = hdr.readUInt32LE(16);
  const sizeofcmds = hdr.readUInt32LE(20);
  const lc = readAt(32, sizeofcmds);
  let p = 0;
  for (let i = 0; i < ncmds; i++) {
    const cmd = lc.readUInt32LE(p);
    const size = lc.readUInt32LE(p + 4);
    if (cmd === 0x19) { // LC_SEGMENT_64
      const nsects = lc.readUInt32LE(p + 64);
      let sp = p + 72;
      for (let k = 0; k < nsects; k++) {
        const sname = lc.slice(sp, sp + 16).toString('utf8').replace(/\0/g, '');
        const addr = Number(lc.readBigUInt64LE(sp + 32));
        const sz = Number(lc.readBigUInt64LE(sp + 40));
        if (sname === '__objc_classlist') return { addr, size: sz };
        sp += 80;
      }
    }
    p += size;
  }
  throw new Error('找不到 __objc_classlist');
}

console.error('定位 __objc_classlist...');
const CL = locateClasslist();
const classCount = CL.size / 8;
console.error('类数量 ' + classCount + '，建立索引（约 10-30 秒）...');

// ---------- 建立索引 ----------
const classInfo = new Map();     // name -> {methods, props}
const selToClasses = new Map();  // sel -> [name]

for (let i = 0; i < classCount; i++) {
  try {
    const classAddr = readU64(CL.addr + i * 8);
    if (!classAddr) continue;
    const bits = readU64(classAddr + 32);
    const ro = bits & 0x7ffffffffff8;
    if (!ro) continue;

    const className = readStr(readU64(ro + 24));
    if (!className || className.length > 200) continue;

    // 方法
    const methods = [];
    const methodsAddr = readU64(ro + 32);
    if (methodsAddr > 0x1000 && methodsAddr < SIZE) {
      const ef = readU32(methodsAddr);
      const count = readU32(methodsAddr + 4);
      const entsize = ef & 0xFFFC;
      const isRel = (ef & 0x80000000) !== 0;
      if (count < 20000 && entsize >= 8 && entsize <= 32) {
        for (let k = 0; k < count; k++) {
          const mAddr = methodsAddr + 8 + k * entsize;
          if (mAddr + entsize > SIZE) break;
          let strAddr;
          if (isRel) {
            const off = readAt(mAddr, 4).readInt32LE(0);
            const selRef = mAddr + off;
            if (selRef <= 0x1000 || selRef >= SIZE) continue;
            strAddr = readU64(selRef);        // ★ 二次解引用
          } else {
            strAddr = readU64(mAddr);
          }
          const sel = readStr(strAddr);
          if (sel && sel.length < 200) methods.push(sel);
        }
      }
    }

    // 属性
    const props = [];
    const propsAddr = readU64(ro + 64);
    if (propsAddr > 0x1000 && propsAddr < SIZE) {
      const ef = readU32(propsAddr);
      const count = readU32(propsAddr + 4);
      const entsize = ef & 0xFFFC;
      if (count > 0 && count < 5000 && entsize >= 8 && entsize <= 32) {
        for (let k = 0; k < count; k++) {
          const pAddr = propsAddr + 8 + k * entsize;
          if (pAddr + entsize > SIZE) break;
          const pn = readStr(readU64(pAddr));
          if (pn && pn.length < 200 && /^[a-zA-Z_][a-zA-Z0-9_]*$/.test(pn)) props.push(pn);
        }
      }
    }

    classInfo.set(className, { methods, props });
    for (const s of methods) {
      if (!selToClasses.has(s)) selToClasses.set(s, []);
      selToClasses.get(s).push(className);
    }
  } catch (e) { /* 跳过损坏项 */ }
}
fs.closeSync(fd);
console.error('索引完成：' + classInfo.size + ' 个类\n');

// ---------- 查询 ----------
const matchRe = wantMatch ? new RegExp(wantMatch, 'i') : null;

if (wantClass) {
  const info = classInfo.get(wantClass);
  if (!info) {
    console.log('未找到类: ' + wantClass);
    // 给个近似建议
    const similar = [...classInfo.keys()].filter(k => k.toLowerCase().includes(wantClass.toLowerCase())).slice(0, 10);
    if (similar.length) console.log('相近的类:\n  ' + similar.join('\n  '));
    process.exit(0);
  }
  console.log('=== ' + wantClass + ' ===');
  console.log('方法 ' + info.methods.length + ' 个，属性 ' + info.props.length + ' 个\n');
  const ms = matchRe ? info.methods.filter(m => matchRe.test(m)) : info.methods;
  if (ms.length) {
    console.log('方法:');
    ms.forEach(m => console.log('  - ' + m));
  }
  const ps = matchRe ? info.props.filter(p => matchRe.test(p)) : info.props;
  if (ps.length) {
    console.log('\n属性:');
    console.log('  ' + ps.join(', '));
  }
}

if (wantSel) {
  const cls = selToClasses.get(wantSel);
  console.log('=== selector: ' + wantSel + ' ===');
  console.log(cls ? '  宿主类: ' + cls.join(', ') : '  （未找到）');
}

if (wantGrep) {
  const re = new RegExp(wantGrep, 'i');
  const hits = [...classInfo.keys()].filter(k => re.test(k)).sort();
  console.log('=== 类名匹配 /' + wantGrep + '/i：' + hits.length + ' 个 ===');
  hits.slice(0, 200).forEach(k => {
    const info = classInfo.get(k);
    console.log('  ' + k.padEnd(56) + ' 方法' + String(info.methods.length).padStart(4) + ' 属性' + String(info.props.length).padStart(3));
  });
  if (hits.length > 200) console.log('  ...还有 ' + (hits.length - 200) + ' 个');
}
