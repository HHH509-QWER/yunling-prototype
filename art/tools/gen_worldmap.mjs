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
const COLS = 448, ROWS = 384;         // ⭐ M31 Step 0：448×8 = 3584, 384×8 = 3072（世界容器 3584×3072）
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
// ⭐ M31.3 重烘焙：新增 `marsh`（泥沼）—— 同心层第四带：水体 → 泥沼 → 草 → 林 → 山。
//    ⚠️ id 顺序必须和 `GameData.WORLD_TERRAINS` 完全一致（R 通道 = id × 50）。
const T = { water: 0, grass: 1, forest: 2, ridge: 3, field: 4, marsh: 5 };
const h0 = (cx, cy) => {                       // 高度场：山脊靠 fbm 的脊化（1-|2n-1|）
  const x = cx / COLS * 6, y = cy / ROWS * 6;
  const n = fbm(x, y, 5);
  const ridge = 1 - Math.abs(2 * fbm(x * 0.6 + 11, y * 0.6 + 7, 4) - 1);
  return 0.55 * n + 0.45 * ridge;
};
const map = new Uint8Array(COLS * ROWS);
// ⭐⭐ M31.3 重烘焙：**高度场归一化**（这是 slow_area% 与总落差双双不达标的根因）。
//    `h0 = 0.55·n + 0.45·ridge`，而 `ridge = 1-|2·fbm-1|` —— 这个「脊化」把均值从 0.5 抬到 **0.84**，
//    于是 h0 本身是个**均值 0.65、很窄的钟形**（实测 90% 的格落在 11~16/20 之间）。
//    后果：① 量化成 21 级后实际只占用 13 级，总落差只有 120 而不是 200；
//          ② 减速阈值 13/20 落在钟形中心的**左侧** → 减速区 64.5%，远超 30~45%。
//    归一化的作用：把测到的实际 [lo,hi] 拉满到 [0,1]，让 21 级**真的都用上**。
//    ⚠️ 只改**映射**，不改噪声场本身 —— 山脊/河流的**形状与位置**一格都不动。
const HN = (() => {
  let lo = Infinity, hi = -Infinity;
  for (let cy = 0; cy < ROWS; cy++) for (let cx = 0; cx < COLS; cx++) {
    const v = h0(cx, cy); if (v < lo) lo = v; if (v > hi) hi = v;
  }
  return { lo, hi, span: Math.max(1e-6, hi - lo) };
})();
const hN = (cx, cy) => Math.max(0, Math.min(1, (h0(cx, cy) - HN.lo) / HN.span));
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
  // ⭐ M31.3 重烘焙：步长 ×5.5。原来 150 步只走了 (82,51) —— 地图是 (448,384)，
  //    河**只走了全长的 22%** 就停了（注释写着"从西北往东南"，实际没走到东南）。
  //    这是水面只有 0.3% 的**头号原因**，比河宽重要得多。
  rx += 3.00 + 1.90 * Math.sin(s * 0.09);
  ry += 1.87 + 1.65 * Math.sin(s * 0.13 + 2.1);
  // ⭐ M31.3 重烘焙：河宽 1.1→3.5 格太细（水面只占 0.3%，等于没有水）→ 2.4→6.9 格
  const wd = 2.4 + s * 0.03;
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
  // ⭐ M31.3：清障半径 40 → 64 布局格（= 16 个 32px 世界格），与中心平台 ±16 对齐
  if (Math.hypot(cx - cx0, cy - cy0) < 64 && map[cy * COLS + cx] !== T.grass) map[cy * COLS + cx] = T.grass;
}
// ⭐ M31.3：**低洼汇水成湖** —— 规则①「水往低处流」的另一半：光有一条河，
//    世界上没有湖，水面凑不到 8~12%。hN 是平滑场，低处自然连成**几片洼地**，
//    阈值一压就是形状自然的湖，不需要额外美术。
{
  const LAKE_E = 0.28;                       // 归一化海拔低于它 → 积水。调到水面 8~12%
  for (let cy = 0; cy < ROWS; cy++) for (let cx = 0; cx < COLS; cx++) {
    const i = cy * COLS + cx;
    if (Math.hypot(cx - cx0, cy - cy0) < 64) continue;    // 出生点不许淹（主城要干地）
    if (hN(cx, cy) < LAKE_E) map[i] = T.water;
  }
}
// ⭐ M31.3：**泥沼（同心层第四带）** —— 水体往外 1~2 格且低洼的草地变湿地。
//    为什么要有它：水陆直接硬切会让岸线像刀切的；湿地是自然界水体与陆地之间那一圈。
//    玩法上它也是「看得见的减速带」—— 和高地减速一起构成两层移动阻力。
{
  const near = new Uint8Array(COLS * ROWS);      // 到最近水格的步数（0 = 水）
  for (let i = 0; i < COLS * ROWS; i++) near[i] = map[i] === T.water ? 0 : 255;
  for (let pass = 0; pass < 3; pass++) {
    const prev = Uint8Array.from(near);
    for (let cy = 0; cy < ROWS; cy++) for (let cx = 0; cx < COLS; cx++) {
      const i = cy * COLS + cx;
      if (prev[i] === 0) continue;
      let m = prev[i];
      for (const [dx, dy] of [[1,0],[-1,0],[0,1],[0,-1]]) {
        const x = Math.min(COLS-1, Math.max(0, cx+dx)), y = Math.min(ROWS-1, Math.max(0, cy+dy));
        if (prev[y * COLS + x] + 1 < m) m = prev[y * COLS + x] + 1;
      }
      near[i] = m;
    }
  }
  for (let cy = 0; cy < ROWS; cy++) for (let cx = 0; cx < COLS; cx++) {
    const i = cy * COLS + cx;
    if (map[i] !== T.grass) continue;             // 只改造草地（林/山/灵田不动）
    // ⚠️ 这里必须用 **hN** 不能用 h0：湖的阈值 LAKE_E 是 hN 空间的，两个空间混用
    //    会让判定整条落空（第一版就是这么烘出「泥沼 0 格」的）。
    if (near[i] >= 1 && near[i] <= 2 && hN(cx, cy) < 0.45) map[i] = T.marsh;    // 高处的岸仍是干草地
  }
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
  let e = hN(cx, cy);          // ⭐ 只有**海拔通道**用归一化后的值；地形分类仍按原始 h0（山/林/草占比不变）
  // 水是低处；泥沼贴着水面（只比水高一级），否则岸线会出现一大级落差
  if (map[cy * COLS + cx] === T.water) e = Math.min(e, 0.30);
  else if (map[cy * COLS + cx] === T.marsh) e = Math.min(e, 0.36);
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
  [T.ridge]: [122, 116, 110], [T.field]: [130, 142, 92], [T.marsh]: [96, 100, 64],
};
// ---- ⭐ M31.3：**从 GameData.gd 读回常量**，避免烘焙脚本与运行时各说各话 ----
const gdPath = path.resolve(here, "..", "..", "scripts", "GameData.gd");
const gdSrc = fs.existsSync(gdPath) ? fs.readFileSync(gdPath, "utf8") : "";
const gdNum = (re, dflt) => { const m = gdSrc.match(re); return m ? parseFloat(m[1]) : dflt; };
const ELEV_LIFT = gdNum(/const ELEV_LIFT\s*:?=\s*([\d.]+)/, 200);                 // 海拔 1.0 抬高多少像素
const SLOW_E = gdNum(/elev_at_pos\(pos\)\s*>=\s*([\d.]+)/, 0.65);                 // 高地减速阈值
const inRange = (v, n, a, b) => v / n >= a && v / n <= b;

export function generate(log = console.log) {
  const diag = { t: {}, lv: {}, lo: 1, hi: 0, slow: 0, n: 0 };
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
  // ⭐⭐ 导出游戏用的世界数据：**112×96 格（每格 32px）**
  //    R = 地形 id ×50 / G = 海拔 / B = 水深 —— 一张 112×96 的小 PNG，
  //    渲染与玩法都读它（**同一个真相**，绝不在 GDScript 里重算噪声）。
  //    ⚠️ 112×32 = 3584、96×32 = 3072 —— 必须与 GameData.WORLD["size"] 完全一致。
  const CW = 112, CH = 96, K = COLS / CW;   // K = 448/112 = 4（1 个 32px 格 = 4×4 个 8px 布局格）
  const LEVELS = 21;
  // ⭐ 出生点高度**派生**，不写死：LEVELS 再改也不会把出生点甩出量化网格
  const SPAWN_E01 = Math.round(0.4 * (LEVELS - 1)) / (LEVELS - 1);
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
    // ⭐ M31.3 重烘焙（水面第二只手）：水/沼改用**加权下限**而非多数表决。
    //    majority-vote 要求 16 个子格里占 8 个 —— 细河流在 32px 格上永远凑不够，
    //    于是整条河被抹掉（这就是水面只有 0.3% 的另一半原因）。
    //    改成 **≥2/16 即判**：只要这一格里踩到 2 个子格的水/沼，整格就是水/沼。
    const nw = tally[T.water] ?? 0, nm = tally[T.marsh] ?? 0;
    if (nw >= 2) best = T.water;
    else if (nm >= 2) best = T.marsh;
    const i = (cy * CW + cx) * 4;
    wb[i] = Math.round(best * 50);
    // ⭐⭐ 海拔**量化成 6 级台地**：自然地貌本来就是台地/梯田 —— 台面内部是平的（能走），
    //    只有台缘才有高差（= 崖）。
    //    ⚠️ 第一版导出的是**连续噪声**，结果 32px 的相邻格高差几乎都 ≥ 阈值 →
    //    「每条格线都是崖」，人物寸步难行（自测里翻滚从 70px 被截成 30px 就是这么来的）。
    //
    // ⭐⭐ M31.3 重烘焙：6 → **21 级**。三条硬约束同时成立才算数：
    //   ① **级差 ≤ 12 世界单位**：1/20 × ELEV_LIFT(200) = **10** ✓
    //      （>12 就会被 `CLIFF_STEP=0.06` 判成崖 —— 而 `can_step` 对高差放行 →
    //        「画面看着是墙、人却能走上去」，正是用户否决过的观感）
    //   ② **总落差 ≥ 96**（约 2 个身高，肉眼确实读得出「山」）
    //   ③ **`(LEVELS-1) % 5 == 0`**：21-1=20 能被 5 整除，出生点 0.4（=8/20）
    //      才正好落在量化网格上。否则出生点平台是一级「谁都不属于」的中间高度。
    let e01 = Math.max(0, Math.min(1, es / n));
    e01 = Math.round(e01 * (LEVELS - 1)) / (LEVELS - 1);
    // ⭐ 出生点（灵田中心）周围压成**同一级平坝** —— 驻地本来就该是平的。
    //    ±9 格 = 608×608 只有半屏多，不够放主城 → **±16 格 = 1056×1056**（与清障半径 64 布局格对齐）
    if (Math.abs(cx - Math.floor(CW / 2)) <= 16 && Math.abs(cy - Math.floor(CH / 2)) <= 16) e01 = SPAWN_E01;
    wb[i + 1] = Math.round(e01 * 255);
    wb[i + 2] = Math.round(Math.max(0, Math.min(1, ds / n)) * 255);
    wb[i + 3] = 255;
    diag.t[best] = (diag.t[best] ?? 0) + 1;
    diag.lo = Math.min(diag.lo, e01); diag.hi = Math.max(diag.hi, e01);
    diag.lv[e01] = (diag.lv[e01] ?? 0) + 1;
    if (e01 >= SLOW_E) diag.slow++;
    diag.n++;
  }
  // ---- ⭐ M31.3：**烘焙诊断** —— 硬约束不靠人肉看，脚本自己报数 ----
  //    `ELEV_LIFT` / 减速阈值**从 GameData.gd 里读**，不回抄常量 ——
  //    回抄就等于埋了一颗「改了一边忘了另一边」的雷。
  {
    const pct = (v) => (v / diag.n * 100).toFixed(1) + "%";
    const stepW = (1 / 20) * ELEV_LIFT;                 // 相邻级差（世界单位）
    const dropW = (diag.hi - diag.lo) * ELEV_LIFT;      // 总落差（世界单位）
    log("---- 烘焙诊断 ----");
    log("  档位数        " + Object.keys(diag.lv).length + " / 21 级（量化网格 21，实际占用如上）");
    log("  相邻级差      " + stepW.toFixed(0) + " 世界单位   " + (stepW <= 12 ? "✅ ≤12" : "❌ >12（会被 CLIFF_STEP 判成崖）"));
    log("  总落差        " + dropW.toFixed(0) + " 世界单位 = " + (dropW / 48).toFixed(1) + "× 身高   " + (dropW >= 96 ? "✅ ≥96" : "❌ <96"));
    log("  水面占比      " + pct(diag.t[T.water] ?? 0) + "   " + (inRange(diag.t[T.water] ?? 0, diag.n, 0.08, 0.12) ? "✅ 8~12%" : "⚠️ 目标 8~12%"));
    log("  泥沼占比      " + pct(diag.t[T.marsh] ?? 0));
    log("  slow_area%    " + pct(diag.slow) + "（elev ≥ " + SLOW_E + " 的减速区）   " + (inRange(diag.slow, diag.n, 0.30, 0.45) ? "✅ 30~45%" : "❌ 不在 30~45%"));
    log("  出生点档位    " + SPAWN_E01 + " = 第 " + Math.round(SPAWN_E01 * 20) + "/20 级" + (Math.abs(SPAWN_E01 * 20 - Math.round(SPAWN_E01 * 20)) < 1e-9 ? " ✅ 落在网格上" : " ❌ 不在网格上"));
    log("  ELEV_LIFT     " + ELEV_LIFT + "（读自 GameData.gd）");
    // 海拔直方图（k/20 → 占比 / 累计）—— 减速阈值、崖线密度全靠它调，不靠猜
    const ks = Object.keys(diag.lv).map(Number).sort((a, b) => a - b);
    let cum = 0, lines = [];
    for (const k of ks) {
      cum += diag.lv[k];
      const lv = Math.round(k * 20);
      lines.push(lv + "/20:" + pct(diag.lv[k]) + "(累计" + pct(cum) + ")");
    }
    log("  海拔直方图    " + lines.join("  "));
    log("  → 若 slow_area% 不在 30~45%，把阈值挪到累计≈62%那一级（仍须是 k/20）");
  }
  const wraw = Buffer.alloc((CW * 4 + 1) * CH);
  for (let y = 0; y < CH; y++) { wraw[y * (CW * 4 + 1)] = 0; wb.copy(wraw, y * (CW * 4 + 1) + 1, y * CW * 4, (y + 1) * CW * 4); }
  const wihdr = Buffer.alloc(13); wihdr.writeUInt32BE(CW, 0); wihdr.writeUInt32BE(CH, 4); wihdr[8] = 8; wihdr[9] = 6;
  const wpath = path.join(wdir, "worldmap.png");
  fs.writeFileSync(wpath, Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", wihdr), chunk("IDAT", zlib.deflateSync(wraw, { level: 9 })), chunk("IEND", new Uint8Array(0))]));
  log("世界数据: " + wpath + " " + CW + "x" + CH + " 格（每格 32px）");

  const counts = {};
  for (const v of map) counts[v] = (counts[v] ?? 0) + 1;
  log("布局: 水 " + counts[T.water] + " / 草 " + counts[T.grass] + " / 林 " + counts[T.forest] + " / 山 " + counts[T.ridge] + " / 灵田 " + counts[T.field] + " / 泥沼 " + (counts[T.marsh] ?? 0));
  log("预览: " + out + " " + W + "x" + H);
  return { out, counts };
}
if (process.argv[1] && process.argv[1].endsWith("gen_worldmap.mjs")) generate();
