// 显化中的灵印（32×32）—— 7 枚各一张
//
// ⭐ 为什么先做这一批：它是《像素美术规范》§9 表里**唯一完全没接**的一类 ——
//    其它（主角/假人/敌人/地块/采集点）的占位图早就接上了。
// ⭐ 形状直接取 GameData.SEALS[*].shape（形状语言）：爪 / 六边 / 闪电 / 方 / 水滴 / 叶 / 星。
//    玩家要能「一眼认出那是哪一枚印」，而不是「一个会飘的圆球」。
// ⭐ 颜色取 GameData.SEALS[*].color。改数据表里的颜色 = 重跑一次这个脚本。
// ⚠️ **不烤影子**：影子由 Seal._draw() 用代码画（它要跟着弹跳走），烤进来会变成两层。
//
// 跑法：node art/tools/gen_seals.mjs
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";
import { fileURLToPath } from "node:url";

const W = 32, H = 32;
const here = path.dirname(fileURLToPath(import.meta.url));
const outDir = path.resolve(here, "..", "seals");

const mk = () => new Uint8Array(W * H * 4);
const set = (b, x, y, c) => { x = Math.round(x); y = Math.round(y); if (x < 0 || y < 0 || x >= W || y >= H) return; const i = (y * W + x) * 4; b[i] = c[0]; b[i + 1] = c[1]; b[i + 2] = c[2]; b[i + 3] = c.length > 3 ? c[3] : 255; };
const shade = (c, k) => [Math.min(255, Math.round(c[0] * k)), Math.min(255, Math.round(c[1] * k)), Math.min(255, Math.round(c[2] * k))];

/** 偶奇扫描线填充：任何形状都能用它画出来（比逐行写死好改） */
const fillPoly = (b, pts, c) => {
  let minY = H, maxY = 0;
  for (const p of pts) { minY = Math.min(minY, p[1]); maxY = Math.max(maxY, p[1]); }
  for (let y = Math.floor(minY); y <= Math.ceil(maxY); y++) {
    const xs = [];
    for (let i = 0; i < pts.length; i++) {
      const [x1, y1] = pts[i], [x2, y2] = pts[(i + 1) % pts.length];
      if ((y1 <= y && y2 > y) || (y2 <= y && y1 > y)) xs.push(x1 + (y - y1) / (y2 - y1) * (x2 - x1));
    }
    xs.sort((a, z) => a - z);
    for (let k = 0; k + 1 < xs.length; k += 2) for (let x = Math.ceil(xs[k]); x <= Math.floor(xs[k + 1]); x++) set(b, x, y, c);
  }
};

/** 给已经填好的形状「穿上衣服」：贴边的压深一圈，左上角一条高光 —— 2 倍放大下才有立体感 */
const dress = (b, base, dark, light) => {
  const src = Uint8Array.from(b);
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    if (src[(y * W + x) * 4 + 3] === 0) continue;
    let edge = false;
    for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
      const nx = x + dx, ny = y + dy;
      if (nx < 0 || ny < 0 || nx >= W || ny >= H || src[(ny * W + nx) * 4 + 3] === 0) { edge = true; break; }
    }
    set(b, x, y, edge ? dark : (x + y <= 21 ? light : base));
  }
};

const outline = (b, c) => {
  const src = Uint8Array.from(b);
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    if (src[(y * W + x) * 4 + 3] !== 0) continue;
    for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
      const nx = x + dx, ny = y + dy;
      if (nx < 0 || ny < 0 || nx >= W || ny >= H) continue;
      if (src[(ny * W + nx) * 4 + 3] !== 0) { set(b, x, y, c); break; }
    }
  }
};

const INK = [14, 14, 18];
const ring = (b, r, c) => { for (let a = 0; a < 360; a += 3) set(b, 16 + Math.cos(a * Math.PI / 180) * r, 16 + Math.sin(a * Math.PI / 180) * r, c); };

// ⭐ 一张表 = 一枚印。颜色与形状抄自 GameData.SEALS（改那边就重跑这个脚本）
const SEALS = {
  seal_ash:      { color: [219, 117, 77],  draw: (b, base, dark, light) => {           // 灰烬印 claw：三道斜爪痕
    for (let i = 0; i < 3; i++) fillPoly(b, [[8 + i * 6, 6], [11 + i * 6, 6], [17 + i * 6, 26], [14 + i * 6, 26]], base);
    dress(b, base, dark, light);
    for (let i = 0; i < 3; i++) fillPoly(b, [[10 + i * 6, 9], [11 + i * 6, 9], [15 + i * 6, 23], [14 + i * 6, 23]], light);
  } },
  seal_hex:      { color: [102, 158, 217], draw: (b, base, dark, light) => {           // 玄甲印 hex：六边形盾
    const pts = []; for (let a = 0; a < 6; a++) pts.push([16 + Math.cos((a * 60 - 90) * Math.PI / 180) * 12, 16 + Math.sin((a * 60 - 90) * Math.PI / 180) * 13]);
    fillPoly(b, pts, base); dress(b, base, dark, light);
    fillPoly(b, [[16, 8], [22, 16], [16, 24], [10, 16]], dark);                          // 甲心：内菱
    fillPoly(b, [[16, 11], [19, 16], [16, 21], [13, 16]], light);
  } },
  seal_bolt:     { color: [184, 158, 242], draw: (b, base, dark, light) => {           // 惊雷印 bolt：闪电
    fillPoly(b, [[19, 4], [9, 17], [15, 17], [12, 28], [23, 14], [17, 14], [21, 4]], base);
    dress(b, base, dark, light);
    fillPoly(b, [[19, 6], [12, 16], [16, 16], [17, 12]], light);
  } },
  seal_rock:     { color: [153, 179, 140], draw: (b, base, dark, light) => {           // 磐石印 square：方石
    fillPoly(b, [[6, 6], [26, 6], [26, 26], [6, 26]], base); dress(b, base, dark, light);
    fillPoly(b, [[8, 18], [14, 18], [12, 24], [8, 24]], dark);                           // 石纹
    fillPoly(b, [[18, 10], [24, 10], [24, 14], [16, 14]], dark);
  } },
  seal_rain:     { color: [115, 184, 230], draw: (b, base, dark, light) => {           // 云雨印 drop：水滴
    const pts = [[16, 4], [24, 18], [24, 21], [20, 27], [12, 27], [8, 21], [8, 18]];
    fillPoly(b, pts, base); dress(b, base, dark, light);
    fillPoly(b, [[13, 16], [16, 16], [16, 24], [13, 24]], light);                        // 水光
  } },
  seal_wind:     { color: [158, 219, 184], draw: (b, base, dark, light) => {           // 流风印 leaf：风叶
    const pts = [[6, 25], [11, 10], [17, 5], [26, 6], [25, 15], [20, 22], [13, 26]];
    fillPoly(b, pts, base); dress(b, base, dark, light);
    for (let i = 0; i < 12; i++) set(b, 8 + i * 1.4, 25 - i * 1.6, dark);                // 叶脉
  } },
  seal_light:    { color: [242, 230, 153], draw: (b, base, dark, light) => {           // 辉光印 star：星
    const pts = [];
    for (let a = 0; a < 10; a++) { const r = a % 2 ? 5.5 : 13; pts.push([16 + Math.cos((a * 36 - 90) * Math.PI / 180) * r, 16 + Math.sin((a * 36 - 90) * Math.PI / 180) * r]); }
    fillPoly(b, pts, base); dress(b, base, dark, light);
    fillPoly(b, [[16, 11], [19, 16], [13, 16]], light);
  } },
};

const TBL = (() => { const t = new Int32Array(256); for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; t[n] = c; } return t; })();
const crc32 = (buf) => { let c = -1; for (let i = 0; i < buf.length; i++) c = TBL[(c ^ buf[i]) & 0xFF] ^ (c >>> 8); return (c ^ -1) >>> 0; };
const chunk = (type, data) => {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length, 0);
  const body = Buffer.concat([Buffer.from(type, "ascii"), Buffer.from(data)]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(body), 0);
  return Buffer.concat([len, body, crc]);
};
export const encodePNG = (rgba, w, h) => {
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) { raw[y * (w * 4 + 1)] = 0; Buffer.from(rgba.buffer, y * w * 4, w * 4).copy(raw, y * (w * 4 + 1) + 1); }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 6;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", zlib.deflateSync(raw, { level: 9 })), chunk("IEND", new Uint8Array(0))]);
};

export function generate(log = console.log) {
  fs.mkdirSync(outDir, { recursive: true });
  const made = {};
  for (const [name, spec] of Object.entries(SEALS)) {
    const b = mk();
    const base = spec.color, dark = shade(base, 0.58), light = shade(base, 1.28);
    spec.draw(b, base, dark, light);
    outline(b, INK);
    made[name] = b;
    fs.writeFileSync(path.join(outDir, name + ".png"), encodePNG(b, W, H));
    let opaque = 0;
    for (let i = 3; i < b.length; i += 4) if (b[i] > 0) opaque++;
    log(name.padEnd(12) + " 不透明 " + String(opaque).padStart(4) + "/1024");
  }
  // 预览：6 倍最近邻，7 张一行
  const K = 6, COLS = 7;
  const names = Object.keys(made);
  const cw = W * K, ch = H * K, rows = Math.ceil(names.length / COLS);
  const pw = cw * COLS, ph = ch * rows;
  const prev = new Uint8Array(pw * ph * 4);
  names.forEach((n, idx) => {
    const s = made[n], ox = (idx % COLS) * cw, oy = Math.floor(idx / COLS) * ch;
    for (let y = 0; y < ch; y++) for (let x = 0; x < cw; x++) {
      const si = (Math.floor(y / K) * W + Math.floor(x / K)) * 4, di = ((oy + y) * pw + (ox + x)) * 4;
      prev[di] = s[si]; prev[di + 1] = s[si + 1]; prev[di + 2] = s[si + 2]; prev[di + 3] = s[si + 3];
    }
  });
  const prevPath = path.join(here, "preview_seals.png");
  fs.writeFileSync(prevPath, encodePNG(prev, pw, ph));
  log("预览图: " + prevPath + " " + pw + "x" + ph);
  return { made: names, preview: prevPath };
}

if (process.argv[1] && process.argv[1].endsWith("gen_seals.mjs")) generate();
