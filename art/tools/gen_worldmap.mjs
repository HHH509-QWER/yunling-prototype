// 世界地图布局（第一批：只定「哪里是山、哪里是水、哪里是林」）
//
// ⭐ 为什么先做这个再做地块拼图：autotile 的地块要按**真实的邻居关系**去画接缝，
//    布局没定就画 16 个变体 = 白画。所以顺序是：布局 → 确认 → 拼图 → 接线。
//
// ⭐ 自然界的三条硬规则（上一版就是因为全违反了才像拼贴棋盘）：
//   ① 水**往低处流**：河必须是连通的曲线，不能是方块
//   ② 林**成片**：树冠是团簇，不是均匀撒点
//   ③ 山**成脊**：等高线一样的长条，不是色块
// 跑法：node art/tools/gen_worldmap.mjs
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";
import { fileURLToPath } from "node:url";

const CELL = 8;                       // 布局格子（预览用 8px；真地块集用 32px，比例一致）
const COLS = 640, ROWS = 360;         // ⭐ M30.25：×4 → 640×8 = 5120, 360×8 = 2880（4×4 屏的大世界）
const here = path.dirname(fileURLToPath(import.meta.url));

const mk = () => new Uint8Array(COLS * CELL * ROWS * CELL * 4);
const W = COLS * CELL, H = ROWS * CELL;
const set = (b, x, y, c) => { if (x < 0 || y < 0 || x >= W || y >= H) return; const i = (y * W + x) * 4; b[i] = c[0]; b[i + 1] = c[1]; b[i + 2] = c[2]; b[i + 3] = 255; };

// 固定种子 + 值噪声（分形叠加）—— 可复现
let seed = 20261015;
const rnd = () => { seed = (seed * 1664525 + 1013904223) & 0x7fffffff; return seed / 0x7fffffff; };
const G = 64;
const grid = new Float32Array(G * G);
for (let i = 0; i < G * G; i++) grid[i] = rnd();
const sm = (t) => t * t * (3 - 2 * t);
const noise = (x, y) => {
  const gx = x % G, gy = y % G;
  const x0 = Math.floor(gx), y0 = Math.floor(gy), fx = sm(gx - x0), fy = sm(gy - y0);
  const at = (a, b2) => grid[(((b2 % G) + G) % G) * G + (((a % G) + G) % G)];
  return (at(x0, y0) * (1 - fx) + at(x0 + 1, y0) * fx) * (1 - fy) + (at(x0, y0 + 1) * (1 - fx) + at(x0 + 1, y0 + 1) * fx) * fy;
};
const fbm = (x, y, oct) => { let v = 0, a = 1, f = 1, s = 0; for (let i = 0; i < oct; i++) { v += a * noise(x * f, y * f); s += a; a *= 0.5; f *= 2; } return v / s; };

// ---- 地形判定（唯一的真相：渲染与玩法都用它）----
const T = { water: 0, grass: 1, forest: 2, ridge: 3, field: 4 };
const h0 = (cx, cy) => {                       // 高度场：山脊靠 fbm 的脊化（1-|2n-1|）
  const x = cx / COLS * 6, y = cy / ROWS * 6;
  const n = fbm(x, y, 5);
  const ridge = 1 - Math.abs(2 * fbm(x * 0.6 + 11, y * 0.6 + 7, 4) - 1);
  return 0.55 * n + 0.45 * ridge;
};
const map = new Uint8Array(COLS * ROWS);
// ① 先铺草地，② 高处变山脊，③ 再挖一条河，④ 最后成片的林，⑤ 出生点周围是灵田
const cx0 = COLS / 2, cy0 = ROWS / 2;
for (let cy = 0; cy < ROWS; cy++) for (let cx = 0; cx < COLS; cx++) {
  const h = h0(cx, cy);
  // ⚠️ 阈值 0.62 时山占了 **72%**（整张图像碎石滩）→ 提到 0.70：山只占约 1/4，才有「盆地 + 环山」的感觉
  map[cy * COLS + cx] = h > 0.70 ? T.ridge : T.grass;
}
// 河：从西北往东南走一条蜿蜒曲线，宽度随下游变宽
let rx = 18, ry = 8;
for (let s = 0; s < 150; s++) {
  rx += 0.55 + 0.35 * Math.sin(s * 0.09);
  ry += 0.34 + 0.30 * Math.sin(s * 0.13 + 2.1);
  const wd = 1.1 + s * 0.016;
  for (let dy = -Math.ceil(wd); dy <= Math.ceil(wd); dy++) for (let dx = -Math.ceil(wd); dx <= Math.ceil(wd); dx++) {
    if (dx * dx + dy * dy > wd * wd) continue;
    const x = Math.round(rx + dx), y = Math.round(ry + dy);
    if (x < 0 || y < 0 || x >= COLS || y >= ROWS) continue;
    map[y * COLS + x] = T.water;
  }
}
// ⭐⭐ 出生点净空：把中心 10 格内的水与山清成草地 ——
//    驻地必须**干燥、平坦、可达**。这不是为了过测试：出生点挨着深水，玩家一出门就被挡，
//    那是关卡设计错了（自测里翻滚从 70px 被截成 30px 就是被门口那条河挡的）。
for (let cy = 0; cy < ROWS; cy++) for (let cx = 0; cx < COLS; cx++) {
  if (Math.hypot(cx - cx0, cy - cy0) < 40 && map[cy * COLS + cx] !== T.grass) map[cy * COLS + cx] = T.grass;
}
// 林：噪声阈值成团 + 不长在山脊和水上
for (let cy = 0; cy < ROWS; cy++) for (let cx = 0; cx < COLS; cx++) {
  const i = cy * COLS + cx;
  if (map[i] !== T.grass) continue;
  const f = fbm(cx / COLS * 9 + 31, cy / ROWS * 9 + 17, 4);
  if (f > 0.56) map[i] = T.forest;
}
// 灵田：出生点周围一圈（安全区，也是玩家认得的路标）
for (let cy = 0; cy < ROWS; cy++) for (let cx = 0; cx < COLS; cx++) {
  const d = Math.hypot(cx - cx0, cy - cy0);
  if (d < 9 && map[cy * COLS + cx] !== T.water) map[cy * COLS + cx] = T.field;
}

// ---- ⭐ M30.13b：**高度模型**（后面崖面/遮挡/行走规则全长在它上面）----
//    海拔 = 归一化的 h0 场；水有**深度**（离岸越远越深）；
//    受光 = 坡向 · 光向（左上打光）—— 有它才有「山」的立体感，否则还是平涂。
const elev = new Float32Array(COLS * ROWS);
const depth = new Float32Array(COLS * ROWS);
for (let cy = 0; cy < ROWS; cy++) for (let cx = 0; cx < COLS; cx++) {
  let e = h0(cx, cy);
  if (map[cy * COLS + cx] === T.water) e = Math.min(e, 0.30);   // 水是低处
  elev[cy * COLS + cx] = e;
}
// 水的深度：从岸边往里数（几圈 BFS 就够，不是精确海岸线）
for (let pass = 0; pass < 6; pass++) {
  const prev = Float32Array.from(depth);
  for (let cy = 0; cy < ROWS; cy++) for (let cx = 0; cx < COLS; cx++) {
    const i = cy * COLS + cx;
    if (map[i] !== T.water) continue;
    const nb = [[1,0],[-1,0],[0,1],[0,-1]].map(([dx,dy]) => {
      const x = Math.min(COLS-1, Math.max(0, cx+dx)), y = Math.min(ROWS-1, Math.max(0, cy+dy));
      return map[y*COLS+x] === T.water ? prev[y*COLS+x] : 0;
    });
    depth[i] = Math.min(1, Math.max.apply(null, nb) + 0.18);
  }
}
// 受光：坡向 · 光向（光从左上）—— 这是「立体」的唯一来源
const shadeOf = (cx, cy) => {
  const i = cy * COLS + cx;
  const gx = (elev[i] - elev[cy * COLS + Math.max(0, cx - 1)]) + (elev[cy * COLS + Math.min(COLS-1, cx+1)] - elev[i]);
  const gy = (elev[i] - elev[Math.max(0, cy - 1) * COLS + cx]) + (elev[Math.min(ROWS-1, cy+1) * COLS + cx] - elev[i]);
  return 0.5 + 0.5 * Math.max(-1, Math.min(1, (gx * -0.7) + (gy * -0.7) * 1.0));
};
const COLOR = {
  [T.water]: [46, 84, 122], [T.grass]: [78, 112, 66], [T.forest]: [42, 78, 50],
  [T.ridge]: [122, 116, 110], [T.field]: [130, 142, 92],
};
export function generate(log = console.log) {
  const b = mk();
  for (let cy = 0; cy < ROWS; cy++) for (let cx = 0; cx < COLS; cx++) {
    const t = map[cy * COLS + cx];
    const i = cy * COLS + cx;
    let c = COLOR[t];
    const sh = t === T.water ? (0.62 + 0.5 * (1 - depth[i])) : (0.55 + 0.75 * shadeOf(cx, cy));   // 水按深浅、陆地按受光
    c = [Math.min(255, c[0] * sh), Math.min(255, c[1] * sh), Math.min(255, c[2] * sh)];
    // ⭐ 崖线：与邻居的高差超过 0.08 就描一条亮边 —— 这就是将来要画「崖壁」的地方
    let cliff = false;
    for (const [dx, dy] of [[1,0],[-1,0],[0,1],[0,-1]]) {
      const x = Math.min(COLS-1, Math.max(0, cx+dx)), y = Math.min(ROWS-1, Math.max(0, cy+dy));
      if (Math.abs(elev[i] - elev[y*COLS+x]) > 0.08) { cliff = true; break; }
    }
    if (cliff) c = [Math.min(255, c[0] * 1.5 + 25), Math.min(255, c[1] * 1.5 + 25), Math.min(255, c[2] * 1.5 + 22)];
    for (let y = 0; y < CELL; y++) for (let x = 0; x < CELL; x++) set(b, cx * CELL + x, cy * CELL + y, c);
  }
  const out = path.join(here, "preview_worldmap.png");
  const TBL = (() => { const t = new Int32Array(256); for (let n = 0; n < 256; n++) { let cc = n; for (let k = 0; k < 8; k++) cc = cc & 1 ? 0xEDB88320 ^ (cc >>> 1) : cc >>> 1; t[n] = cc; } return t; })();
  const crc32 = (buf) => { let c = -1; for (let i = 0; i < buf.length; i++) c = TBL[(c ^ buf[i]) & 0xFF] ^ (c >>> 8); return (c ^ -1) >>> 0; };
  const chunk = (type, data) => { const len = Buffer.alloc(4); len.writeUInt32BE(data.length, 0); const bodyb = Buffer.concat([Buffer.from(type, "ascii"), Buffer.from(data)]); const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(bodyb), 0); return Buffer.concat([len, bodyb, crc]); };
  const raw = Buffer.alloc((W * 4 + 1) * H);
  for (let y = 0; y < H; y++) { raw[y * (W * 4 + 1)] = 0; Buffer.from(b.buffer, y * W * 4, W * 4).copy(raw, y * (W * 4 + 1) + 1); }
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(W, 0); ihdr.writeUInt32BE(H, 4); ihdr[8] = 8; ihdr[9] = 6;
  fs.writeFileSync(out, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", zlib.deflateSync(raw, { level: 9 })), chunk("IEND", new Uint8Array(0))]));
  // ⭐⭐ 导出游戏用的世界数据：**40×23 格（每格 32px）**
  //    R = 地形 id ×50 / G = 海拔 / B = 水深 —— 一张 40×23 的小 PNG，
  //    渲染与玩法都读它（**同一个真相**，绝不在 GDScript 里重算噪声）。
  const CW = 160, CH = 90, K = COLS / CW;   // 1280/32 = 40, 720/32 = 22.5 → 取 23 行（最后一行半格）
  const wb = Buffer.alloc(CW * CH * 4);
  const wdir = path.resolve(here, "..", "world");
  fs.mkdirSync(wdir, { recursive: true });
  for (let cy = 0; cy < CH; cy++) for (let cx = 0; cx < CW; cx++) {
    const tally = {};
    let es = 0, ds = 0, n = 0;
    for (let y = 0; y < K; y++) for (let x = 0; x < K; x++) {
      const sx = Math.min(COLS - 1, cx * K + x), sy = Math.min(ROWS - 1, cy * K + y);
      const t = map[sy * COLS + sx];
      tally[t] = (tally[t] ?? 0) + 1;
      es += elev[sy * COLS + sx]; ds += depth[sy * COLS + sx]; n++;
    }
    let best = T.grass, bn = -1;
    for (const k of Object.keys(tally)) if (tally[k] > bn) { bn = tally[k]; best = +k; }
    const i = (cy * CW + cx) * 4;
    wb[i] = Math.round(best * 50);
    // ⭐⭐ 海拔**量化成 6 级台地**：自然地貌本来就是台地/梯田 —— 台面内部是平的（能走），
    //    只有台缘才有高差（= 崖）。
    //    ⚠️ 第一版导出的是**连续噪声**，结果 32px 的相邻格高差几乎都 ≥ 阈值 →
    //    「每条格线都是崖」，人物寸步难行（自测里翻滚从 70px 被截成 30px 就是这么来的）。
    const LEVELS = 6;
    let e01 = Math.max(0, Math.min(1, es / n));
    e01 = Math.round(e01 * (LEVELS - 1)) / (LEVELS - 1);
    // ⭐ 出生点（灵田中心）周围 5×5 格压成**同一级平坝** —— 驻地本来就该是平的
    if (Math.abs(cx - Math.floor(CW / 2)) <= 9 && Math.abs(cy - Math.floor(CH / 2)) <= 9) e01 = 0.4;
    wb[i + 1] = Math.round(e01 * 255);
    wb[i + 2] = Math.round(Math.max(0, Math.min(1, ds / n)) * 255);
    wb[i + 3] = 255;
  }
  const wraw = Buffer.alloc((CW * 4 + 1) * CH);
  for (let y = 0; y < CH; y++) { wraw[y * (CW * 4 + 1)] = 0; wb.copy(wraw, y * (CW * 4 + 1) + 1, y * CW * 4, (y + 1) * CW * 4); }
  const wihdr = Buffer.alloc(13); wihdr.writeUInt32BE(CW, 0); wihdr.writeUInt32BE(CH, 4); wihdr[8] = 8; wihdr[9] = 6;
  const wpath = path.join(wdir, "worldmap.png");
  fs.writeFileSync(wpath, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", wihdr), chunk("IDAT", zlib.deflateSync(wraw, { level: 9 })), chunk("IEND", new Uint8Array(0))]));
  log("世界数据: " + wpath + " " + CW + "x" + CH + " 格（每格 32px）");

  const counts = {};
  for (const v of map) counts[v] = (counts[v] ?? 0) + 1;
  log("布局: 水 " + counts[T.water] + " / 草 " + counts[T.grass] + " / 林 " + counts[T.forest] + " / 山 " + counts[T.ridge] + " / 灵田 " + counts[T.field]);
  log("预览: " + out + " " + W + "x" + H);
  return { out, counts };
}
if (process.argv[1] && process.argv[1].endsWith("gen_worldmap.mjs")) generate();
