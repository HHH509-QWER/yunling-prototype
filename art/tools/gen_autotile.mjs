// 地形接缝 autotile 生成器（⭐ P1）
//
// 为什么需要它：现在地形是"每格从 128px 贴图里随便取一块 32×32" —— 相邻格之间**没有接缝处理**，
// 所以水岸/林缘/岩缘全是 90° 直角，看着像"色块拼图"。
//
// 做法：每种地形生成 **16 个变体**，索引 = 4 邻居掩码：
//   bit0=N(上) bit1=E(右) bit2=S(下) bit3=W(左)，**1 = 邻居是不同地形**（需要画这条边）
// 每个变体在"需要画边"的那一侧画一条暗边 + 内侧一道亮边（视觉上有厚度），
// 两条边相交的角做小圆角（去掉 1~2 像素），这样边界看起来是"自然过渡"而不是方块。
//
// ⚠️ 全部由**地形名 + 掩码**决定（不含随机数），所以：
//    · 同样的变体到处复用也不会看出重复（本来就该一样）
//    · 重跑脚本结果完全一致
//
// 跑法：node art/tools/gen_autotile.mjs  →  art/tiles/auto_<地形>_<mask>.png（80 张）+ 预览图
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";
import { fileURLToPath } from "node:url";
const here = path.dirname(fileURLToPath(import.meta.url));
const outDir = path.resolve(here, "..", "tiles");
const N = 32;

// 每种地形：底色 / 边（暗）/ 内侧亮边 / 点缀
const T = {
  水泽: { base: [26, 41, 61], edge: [14, 24, 40], lit: [70, 116, 158], dot: [40, 60, 86] },
  草地: { base: [28, 36, 28], edge: [16, 22, 17], lit: [50, 66, 44], dot: [38, 50, 35] },
  竹林: { base: [20, 30, 22], edge: [11, 18, 13], lit: [38, 56, 36], dot: [28, 42, 28] },
  灵岩: { base: [37, 36, 42], edge: [22, 21, 26], lit: [64, 62, 72], dot: [48, 46, 54] },
  灵田: { base: [41, 43, 28], edge: [26, 27, 17], lit: [64, 68, 38], dot: [52, 55, 33] },
};

const mk = () => new Uint8Array(N * N * 4);
const px = (b, x, y, c) => {
  x = Math.round(x); y = Math.round(y);
  if (x < 0 || y < 0 || x >= N || y >= N) return;
  const i = (y * N + x) * 4;
  b[i] = c[0]; b[i + 1] = c[1]; b[i + 2] = c[2]; b[i + 3] = 255;
};
// 周期抖动（tileable）：用 (x*7+y*13)%… 之类的小偏移，不引入随机
const dither = (x, y) => ((x * 7 + y * 13 + ((x * y) % 5)) % 11) - 5;

function variant(pal, mask) {
  const b = mk();
  for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
    const d = dither(x, y) * 1.1;
    const c = [pal.base[0] + d, pal.base[1] + d, pal.base[2] + d];
    px(b, x, y, c);
  }
  // 稀疏点缀（tileable：按坐标取模）
  for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
    if ((x * 5 + y * 11) % 37 === 0) px(b, x, y, pal.dot);
  }
  const nDiff = (mask & 1) !== 0, eDiff = (mask & 2) !== 0, sDiff = (mask & 4) !== 0, wDiff = (mask & 8) !== 0;
  const EDGE = 2, INNER = 3;
  for (let i = 0; i < EDGE; i++) {
    if (nDiff) for (let x = 0; x < N; x++) px(b, x, i, pal.edge);
    if (sDiff) for (let x = 0; x < N; x++) px(b, x, N - 1 - i, pal.edge);
    if (wDiff) for (let y = 0; y < N; y++) px(b, i, y, pal.edge);
    if (eDiff) for (let y = 0; y < N; y++) px(b, N - 1 - i, y, pal.edge);
  }
  // 内侧亮边（有厚度感）
  if (nDiff) for (let x = 0; x < N; x++) px(b, x, EDGE, pal.lit);
  if (sDiff) for (let x = 0; x < N; x++) px(b, x, N - 1 - EDGE, pal.lit);
  if (wDiff) for (let y = 0; y < N; y++) px(b, EDGE, y, pal.lit);
  if (eDiff) for (let y = 0; y < N; y++) px(b, N - 1 - EDGE, y, pal.lit);
  // 角：两侧都不同 → 削角（去掉 1~2 像素，做出圆角）
  const cut = (cx, cy, sx, sy) => {
    for (let j = 0; j < 2; j++) for (let i = 0; i < 2; i++) {
      if (i + j < 2) px(b, cx + sx * i, cy + sy * j, pal.base);
    }
    px(b, cx + sx, cy + sy, pal.lit);
  };
  if (nDiff && wDiff) cut(0, 0, 1, 1);
  if (nDiff && eDiff) cut(N - 1, 0, -1, 1);
  if (sDiff && wDiff) cut(0, N - 1, 1, -1);
  if (sDiff && eDiff) cut(N - 1, N - 1, -1, -1);
  return b;
}

const TBL = (() => { const t = new Int32Array(256); for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; t[n] = c; } return t; })();
const crc32 = (buf) => { let c = -1; for (let i = 0; i < buf.length; i++) c = TBL[(c ^ buf[i]) & 0xFF] ^ (c >>> 8); return (c ^ -1) >>> 0; };
const chunk = (type, data) => { const len = Buffer.alloc(4); len.writeUInt32BE(data.length, 0); const bb = Buffer.concat([Buffer.from(type, "ascii"), Buffer.from(data)]); const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(bb), 0); return Buffer.concat([len, bb, crc]); };
const encodePNG = (rgba, w, h) => {
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) { raw[y * (w * 4 + 1)] = 0; Buffer.from(rgba.buffer, y * w * 4, w * 4).copy(raw, y * (w * 4 + 1) + 1); }
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 6;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", zlib.deflateSync(raw, { level: 9 })), chunk("IEND", new Uint8Array(0))]);
};

export function generate(log = console.log) {
  fs.mkdirSync(outDir, { recursive: true });
  const names = Object.keys(T);
  let n = 0;
  for (const name of names) {
    for (let mask = 0; mask < 16; mask++) {
      const b = variant(T[name], mask);
      fs.writeFileSync(path.join(outDir, "auto_" + name + "_" + mask + ".png"), encodePNG(b, N, N));
      n++;
    }
  }
  // 预览：每行一个地形，16 列掩码，2× 放大
  const K = 2, CW = N * K, AW = CW * 16, AH = CW * names.length;
  const prev = new Uint8Array(AW * AH * 4);
  for (let i = 0; i < prev.length; i += 4) { prev[i] = 20; prev[i + 1] = 22; prev[i + 2] = 26; prev[i + 3] = 255; }
  names.forEach((name, row) => {
    for (let mask = 0; mask < 16; mask++) {
      const b = variant(T[name], mask);
      for (let y = 0; y < CW; y++) for (let x = 0; x < CW; x++) {
        const s = (Math.floor(y / K) * N + Math.floor(x / K)) * 4;
        const d = ((row * CW + y) * AW + mask * CW + x) * 4;
        prev[d] = b[s]; prev[d + 1] = b[s + 1]; prev[d + 2] = b[s + 2]; prev[d + 3] = 255;
      }
    }
  });
  const p = path.join(here, "preview_autotile.png");
  fs.writeFileSync(p, encodePNG(prev, AW, AH));
  log("生成 " + n + " 张（" + names.length + " 地形 × 16 掩码）");
  log("预览: " + p + " " + AW + "x" + AH);
  return { count: n, preview: p };
}
if (process.argv[1] && process.argv[1].endsWith("gen_autotile.mjs")) generate();
