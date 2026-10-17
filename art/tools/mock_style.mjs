// 目标画风示意（赛璐璐 / 动画风）—— 给用户看「做出来大概是什么样」
//
// ⭐ 关键手法：**4 倍超采样再降采样**。用代码画的东西天生是硬边，
//    但按 4× 画、再平均降采样 → 边缘自然平滑 = 动画线条的手感。
//    这也正是新管线要的：**允许分数倍缩放**（像素风禁止的那条，在这里是必需）。
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";
import { fileURLToPath } from "node:url";
const here = path.dirname(fileURLToPath(import.meta.url));

const S = 4;                    // 超采样倍数
const W = 960, H = 540;         // 成品尺寸（游戏里是 1366×768，这里示意用 16:9）
const BW = W * S, BH = H * S;

const buf = new Float32Array(BW * BH * 4);
const px = (x, y, c, a = 1) => {
  x = Math.round(x); y = Math.round(y);
  if (x < 0 || y < 0 || x >= BW || y >= BH) return;
  const i = (y * BW + x) * 4;
  buf[i] = buf[i] * (1 - a) + c[0] * a;
  buf[i + 1] = buf[i + 1] * (1 - a) + c[1] * a;
  buf[i + 2] = buf[i + 2] * (1 - a) + c[2] * a;
  buf[i + 3] = Math.min(1, buf[i + 3] + a);
};
const rect = (x0, y0, x1, y1, c, a = 1) => { for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) px(x, y, c, a); };
const ell = (cx, cy, rx, ry, c, a = 1) => {
  for (let y = Math.floor(cy - ry) - 1; y <= Math.ceil(cy + ry) + 1; y++)
    for (let x = Math.floor(cx - rx) - 1; x <= Math.ceil(cx + rx) + 1; x++) {
      const d = Math.sqrt(((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2);
      if (d <= 1) px(x, y, c, a);
    }
};
// 描边：沿图形边缘外扩一圈（动画的线稿）
const ring = (cx, cy, rx, ry, w, c) => ell(cx, cy, rx + w, ry + w, c), inner = (cx, cy, rx, ry) => ell(cx, cy, rx, ry, [0,0,0], 0);
const V = (x, y) => [x * S, y * S];   // 逻辑坐标 → 超采样坐标

// ---------------- 场景 ----------------
// 天空（两段平的，不做渐变 —— 赛璐璐的"云带"感）
rect(0, 0, BW, BH, [0.62, 0.76, 0.86]);
rect(0, 190 * S, BW, BH, [0.72, 0.83, 0.80]);
// 远山（两层，各 2 色）
for (let x = 0; x < BW; x += S) {
  const t = x / BW * Math.PI * 2;
  const h1 = 200 + 42 * Math.sin(t * 1.7) + 22 * Math.sin(t * 3.3 + 1.2);
  const h2 = 238 + 30 * Math.sin(t * 2.1 + 2.0) + 16 * Math.sin(t * 4.4);
  for (let y = h2 * S * 0.55; y < BH; y++) { for (let k = 0; k < S; k++) px(x + k, y, [0.44, 0.56, 0.60]); }
  for (let y = h1 * S * 0.55; y < h2 * S * 0.55; y++) { for (let k = 0; k < S; k++) px(x + k, y, [0.36, 0.48, 0.54]); }
}
// 草地（平涂 + 一层受光带）
for (let y = 300 * S; y < BH; y++) {
  const t = (y - 300 * S) / (BH - 300 * S);
  const c = [0.34 + 0.10 * (1 - t), 0.48 + 0.12 * (1 - t), 0.30 + 0.08 * (1 - t)];
  for (let x = 0; x < BW; x++) px(x, y, c);
}
// 河（一条平滑曲线 + 亮岸）
for (let y = 300 * S; y < BH; y++) {
  const t = (y - 300 * S) / (BH - 300 * S);
  const cx = (120 + 300 * t + 60 * Math.sin(t * 3.2)) * S;
  const w = (26 + 40 * t) * S;
  for (let x = cx - w; x <= cx + w; x++) px(x, y, [0.22, 0.42, 0.62]);
  for (let x = cx - w - 3 * S; x < cx - w; x++) px(x, y, [0.66, 0.72, 0.62]);
  for (let x = cx + w; x < cx + w + 3 * S; x++) px(x, y, [0.66, 0.72, 0.62]);
}
// 树（2 层色 + 描边）与石头
const tree = (lx, ly, s) => {
  const [x, y] = V(lx, ly);
  rect(x - 5 * S * s, y, x + 5 * S * s, y + 34 * S * s, [0.36, 0.26, 0.20]);
  for (const [dx, dy, r] of [[-16, -18, 20], [14, -16, 18], [0, -32, 22]]) {
    ell(x + dx * S * s, y + dy * S * s, (r + 2.5) * S * s, (r + 2.5) * S * s, [0.16, 0.26, 0.18]);   // 描边
  }
  for (const [dx, dy, r] of [[-16, -18, 20], [14, -16, 18], [0, -32, 22]]) {
    ell(x + dx * S * s, y + dy * S * s, r * S * s, r * S * s, [0.28, 0.44, 0.26]);
    ell(x + dx * S * s - r * 0.25 * S * s, y + dy * S * s - r * 0.3 * S * s, r * 0.62 * S * s, r * 0.55 * S * s, [0.38, 0.56, 0.32]);
  }
};
tree(210, 400, 1.0); tree(836, 356, 0.8); tree(300, 508, 1.15);
for (let i = 0; i < 7; i++) {
  const [x, y] = V(560 + i * 46, 470 + (i % 3) * 22);
  ell(x, y + 3 * S, 11 * S, 5 * S, [0.30, 0.40, 0.28]);
  ell(x, y, 12 * S, 8 * S, [0.48, 0.50, 0.48]);
  ell(x - 3 * S, y - 2 * S, 7 * S, 4 * S, [0.60, 0.62, 0.60]);
}

// ---------------- 主角（赛璐璐）----------------
const cx = 480 * S, cy = 452 * S;     // 脚底
const HH = 150 * S;                   // 全身高
// 落地阴影（软，不是硬的椭圆）
for (let i = 5; i >= 1; i--) ell(cx, cy, (26 + i * 7) * S, (7 + i * 2.4) * S, [0.10, 0.14, 0.10], 0.10);
// 腿 / 鞋
rect(cx - 11 * S, cy - 34 * S, cx - 3 * S, cy - 6 * S, [0.16, 0.17, 0.21]);
rect(cx + 3 * S, cy - 34 * S, cx + 11 * S, cy - 6 * S, [0.16, 0.17, 0.21]);
ell(cx - 8 * S, cy - 4 * S, 9 * S, 5 * S, [0.10, 0.11, 0.14]);
ell(cx + 8 * S, cy - 4 * S, 9 * S, 5 * S, [0.10, 0.11, 0.14]);
// 袍（三层：背光 / 固有 / 受光）
const robeTop = cy - 96 * S, robeBot = cy - 30 * S;
for (let y = robeTop; y < robeBot; y++) {
  const t = (y - robeTop) / (robeBot - robeTop);
  const half = (26 + 22 * t) * S;
  for (let x = cx - half; x <= cx + half; x++) {
    const u = (x - (cx - half)) / (2 * half);
    let c = [0.86, 0.87, 0.90];
    if (u < 0.22) c = [0.97, 0.97, 1.0];            // 受光（左上）
    else if (u > 0.78) c = [0.62, 0.66, 0.74];      // 背光
    px(x, y, c);
  }
}
// 腰带（黑）+ 腰腹灰烬橙红（全身唯一高饱和）
const beltY = cy - 62 * S;
rect(cx - 30 * S, beltY - 7 * S, cx + 30 * S, beltY + 7 * S, [0.17, 0.18, 0.22]);
rect(cx - 30 * S, beltY - 7 * S, cx + 30 * S, beltY - 4 * S, [0.26, 0.28, 0.34]);
for (let i = 0; i < 26; i++) {
  const a = 0.5 * (1 - i / 26);
  ell(cx + (i % 7 - 3) * 2 * S, beltY + Math.sin(i) * 3 * S, (14 - i * 0.35) * S, (7 - i * 0.18) * S, [0.93, 0.55, 0.25], a);
}
ell(cx - 6 * S, beltY + 2 * S, 5 * S, 3 * S, [1.0, 0.78, 0.42]);
// 袖（大袖，两条）
for (const sgn of [-1, 1]) {
  const ax = cx + sgn * 34 * S;
  ell(ax, cy - 74 * S, 17 * S, 26 * S, [0.86, 0.87, 0.90]);
  ell(ax + sgn * 4 * S, cy - 74 * S, 12 * S, 22 * S, [0.60, 0.64, 0.72]);
  ell(ax, cy - 52 * S, 9 * S, 7 * S, [0.94, 0.85, 0.80]);   // 手
}
// 头（大，动画比例）+ 黑发 + 眼睛
const hy = cy - 132 * S;
ell(cx, hy, 30 * S, 33 * S, [0.13, 0.15, 0.20]);                    // 头发外轮廓
ell(cx, hy + 6 * S, 24 * S, 26 * S, [0.94, 0.87, 0.81]);            // 脸
ell(cx, hy - 16 * S, 29 * S, 20 * S, [0.13, 0.15, 0.20]);           // 刘海大块
ell(cx - 26 * S, hy - 2 * S, 7 * S, 24 * S, [0.13, 0.15, 0.20]);    // 两侧垂发
ell(cx + 26 * S, hy - 2 * S, 7 * S, 24 * S, [0.13, 0.15, 0.20]);
ell(cx - 12 * S, hy - 24 * S, 12 * S, 5 * S, [0.30, 0.34, 0.44]);   // 发丝高光
ell(cx + 10 * S, hy - 26 * S, 9 * S, 4 * S, [0.26, 0.30, 0.40]);
for (const sgn of [-1, 1]) {                                        // 眼睛（动画感的第一来源）
  const ex = cx + sgn * 11 * S;
  ell(ex, hy + 6 * S, 6.5 * S, 8 * S, [0.10, 0.12, 0.18]);
  ell(ex, hy + 7 * S, 4.6 * S, 6 * S, [0.32, 0.42, 0.52]);
  ell(ex - 2 * S, hy + 3 * S, 2.4 * S, 2.8 * S, [1.0, 1.0, 1.0]);
  rect(ex - 7 * S, hy + 1 * S, ex + 7 * S, hy + 2 * S, [0.10, 0.12, 0.18]);
}
rect(cx - 15 * S, hy - 4 * S, cx - 6 * S, hy - 3 * S, [0.16, 0.18, 0.24]);   // 眉
rect(cx + 6 * S, hy - 4 * S, cx + 15 * S, hy - 3 * S, [0.16, 0.18, 0.24]);
ell(cx - 7 * S, hy + 14 * S, 5 * S, 3 * S, [0.90, 0.72, 0.68], 0.5);        // 腮

// ---------------- HUD ----------------
rect(0, BH - 56 * S, BW, BH, [0.06, 0.07, 0.10], 0.72);
rect(28 * S, BH - 40 * S, 320 * S, BH - 24 * S, [0.18, 0.10, 0.12]);
rect(28 * S, BH - 40 * S, 300 * S, BH - 24 * S, [0.78, 0.22, 0.20]);
rect(28 * S, BH - 40 * S, 300 * S, BH - 36 * S, [0.92, 0.42, 0.38]);
rect(28 * S, BH - 19 * S, 320 * S, BH - 7 * S, [0.10, 0.20, 0.28]);
rect(28 * S, BH - 19 * S, 250 * S, BH - 7 * S, [0.28, 0.68, 0.92]);
rect(28 * S, BH - 19 * S, 250 * S, BH - 15 * S, [0.56, 0.86, 0.98]);

// ---------------- 降采样输出 ----------------
const out = Buffer.alloc(W * H * 4);
for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
  let r = 0, g = 0, b = 0, a = 0;
  for (let sy = 0; sy < S; sy++) for (let sx = 0; sx < S; sx++) {
    const i = ((y * S + sy) * BW + (x * S + sx)) * 4;
    r += buf[i]; g += buf[i + 1]; b += buf[i + 2]; a += buf[i + 3];
  }
  const n = S * S, o = (y * W + x) * 4;
  out[o] = Math.round(Math.min(1, r / n) * 255); out[o + 1] = Math.round(Math.min(1, g / n) * 255);
  out[o + 2] = Math.round(Math.min(1, b / n) * 255); out[o + 3] = 255;
}
const TBL = (() => { const t = new Int32Array(256); for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; t[n] = c; } return t; })();
const crc32 = (b) => { let c = -1; for (let i = 0; i < b.length; i++) c = TBL[(c ^ b[i]) & 0xFF] ^ (c >>> 8); return (c ^ -1) >>> 0; };
const chunk = (type, data) => { const len = Buffer.alloc(4); len.writeUInt32BE(data.length, 0); const bb = Buffer.concat([Buffer.from(type, "ascii"), Buffer.from(data)]); const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(bb), 0); return Buffer.concat([len, bb, crc]); };
const raw = Buffer.alloc((W * 4 + 1) * H);
for (let y = 0; y < H; y++) { raw[y * (W * 4 + 1)] = 0; out.copy(raw, y * (W * 4 + 1) + 1, y * W * 4, (y + 1) * W * 4); }
const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(W, 0); ihdr.writeUInt32BE(H, 4); ihdr[8] = 8; ihdr[9] = 6;
const p = path.join(here, "mock_style.png");
fs.writeFileSync(p, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", zlib.deflateSync(raw, { level: 9 })), chunk("IEND", new Uint8Array(0))]));
console.log("画风示意: " + p + " " + W + "x" + H + "（" + S + "× 超采样）");
