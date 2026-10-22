// 物品像素素材（M30.5b）：**一套配方，两种尺寸**
//   art/items/<id>.png       32×32  面板 / 背包图标（原生分辨率 1:1 画）
//   art/items/<id>_drop.png   8×8   地上的掉落物（世界像素 1:1 → 屏幕 16px，和原来那个 14px 菱形相当）
//
// ⭐ 为什么一套配方两种尺寸：8×8 是 32×32 的**整数降采样**，不是另画一套 ——
//    这样「背包里看到的」和「地上捡到的」永远是同一个东西，不会各画各的。
// ⭐ 颜色一律取自 GameData.MATERIALS[*].color（改数据表 → 重跑本脚本）。
// ⚠️ **灵印没有掉落 token**：纹理没法按印染色，而地上那枚印必须一眼看出是哪一枚 ——
//    所以地上的印继续用**形状语言**画（菱形 + 外环 + 印色），这是有意的例外，见 Pickup.gd。
//
// 跑法：node art/tools/gen_items.mjs
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const outDir = path.resolve(here, "..", "items");
const ICON = 32, DROP = 8;

const mk = (S) => new Uint8Array(S * S * 4);
const setP = (b, S, x, y, c) => { x = Math.round(x); y = Math.round(y); if (x < 0 || y < 0 || x >= S || y >= S) return; const i = (y * S + x) * 4; b[i] = c[0]; b[i + 1] = c[1]; b[i + 2] = c[2]; b[i + 3] = c.length > 3 ? c[3] : 255; };
const shade = (c, k) => [Math.min(255, Math.round(c[0] * k)), Math.min(255, Math.round(c[1] * k)), Math.min(255, Math.round(c[2] * k))];

/** 0..1 空间的偶奇扫描线填充；0.5 → 像素中心（和手绘像素的 .5 重心一致） */
const poly = (b, S, pts01, c) => {
  const pts = pts01.map(([x, y]) => [x * S - 0.5, y * S - 0.5]);
  let minY = S, maxY = -1;
  for (const p of pts) { minY = Math.min(minY, p[1]); maxY = Math.max(maxY, p[1]); }
  for (let y = Math.floor(minY); y <= Math.ceil(maxY); y++) {
    const xs = [];
    for (let i = 0; i < pts.length; i++) {
      const [x1, y1] = pts[i], [x2, y2] = pts[(i + 1) % pts.length];
      if ((y1 <= y && y2 > y) || (y2 <= y && y1 > y)) xs.push(x1 + (y - y1) / (y2 - y1) * (x2 - x1));
    }
    xs.sort((a, z) => a - z);
    for (let k = 0; k + 1 < xs.length; k += 2) for (let x = Math.ceil(xs[k]); x <= Math.floor(xs[k + 1]); x++) setP(b, S, x, y, c);
  }
};
const ell = (b, S, cx, cy, r, c) => {
  const P = [];
  for (let a = 0; a < 20; a++) P.push([cx + Math.cos(a * Math.PI / 10) * r, cy + Math.sin(a * Math.PI / 10) * r]);
  poly(b, S, P, c);
};
const outline = (b, S, c) => {
  const src = Uint8Array.from(b);
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
    if (src[(y * S + x) * 4 + 3] !== 0) continue;
    for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
      const nx = x + dx, ny = y + dy;
      if (nx < 0 || ny < 0 || nx >= S || ny >= S) continue;
      if (src[(ny * S + nx) * 4 + 3] !== 0) { setP(b, S, x, y, c); break; }
    }
  }
};
/** 贴边压深 + 左上高光：小尺寸下这一步是「有没有立体感」的分水岭 */
const dress = (b, S, base, dark, light) => {
  const src = Uint8Array.from(b);
  for (let y = 0; y < S; y++) for (let x = 0; x < S; x++) {
    const i = (y * S + x) * 4;
    if (src[i + 3] === 0) continue;
    const c = [src[i], src[i + 1], src[i + 2]];
    if (c[0] !== base[0] || c[1] !== base[1] || c[2] !== base[2]) continue;   // 只处理底层色，不动细节层
    let edge = false;
    for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
      const nx = x + dx, ny = y + dy;
      if (nx < 0 || ny < 0 || nx >= S || ny >= S || src[(ny * S + nx) * 4 + 3] === 0) { edge = true; break; }
    }
    const t = (x + y) / (S * 2.0);
    setP(b, S, x, y, edge ? dark : (t < 0.34 ? light : base));
  }
};

const INK = [16, 17, 22];
// 一份配方 = 一个 draw(b, S, base, dark, light, accent)。所有坐标都在 0..1。
const ITEMS = {
  herb:   { color: [115, 199, 107], draw: (b, S, base, dark, light) => {            // 蕴灵草：三叶一茎
    poly(b, S, [[0.5, 0.98], [0.5, 0.30], [0.56, 0.30], [0.56, 0.98]], dark);
    poly(b, S, [[0.5, 0.52], [0.10, 0.30], [0.16, 0.10], [0.52, 0.22]], base);
    poly(b, S, [[0.5, 0.58], [0.90, 0.34], [0.84, 0.12], [0.48, 0.26]], base);
    poly(b, S, [[0.5, 0.22], [0.72, 0.02], [0.92, 0.06], [0.62, 0.30]], light);
  } },
  flower: { color: [224, 107, 77], draw: (b, S, base, dark, light) => {             // 赤炎花：五瓣 + 花心
    poly(b, S, [[0.5, 0.98], [0.5, 0.55], [0.58, 0.55], [0.58, 0.98]], dark);
    for (const [cx, cy] of [[0.5, 0.18], [0.82, 0.38], [0.70, 0.74], [0.30, 0.74], [0.18, 0.38]]) ell(b, S, cx, cy, 0.16, base);
    ell(b, S, 0.5, 0.46, 0.13, [250, 216, 120]);
  } },
  ironore:{ color: [140, 148, 168], draw: (b, S, base, dark, light) => {            // 玄铁矿：一块带棱的矿
    poly(b, S, [[0.14, 0.62], [0.34, 0.22], [0.72, 0.16], [0.90, 0.52], [0.62, 0.90], [0.26, 0.86]], base);
    poly(b, S, [[0.40, 0.44], [0.62, 0.36], [0.70, 0.54], [0.46, 0.62]], light);
  } },
  tstone: { color: [158, 140, 235], draw: (b, S, base, dark, light) => {            // 雷纹石：矿 + 雷纹
    poly(b, S, [[0.16, 0.60], [0.36, 0.20], [0.74, 0.18], [0.90, 0.54], [0.60, 0.88], [0.26, 0.84]], base);
    poly(b, S, [[0.52, 0.26], [0.36, 0.54], [0.48, 0.54], [0.42, 0.80], [0.66, 0.48], [0.54, 0.48]], [250, 250, 200]);
  } },
  bone:   { color: [209, 199, 169], draw: (b, S, base, dark, light) => {            // 兽骨：两端关节 + 骨干
    poly(b, S, [[0.30, 0.36], [0.70, 0.64], [0.64, 0.72], [0.24, 0.44]], base);
    ell(b, S, 0.24, 0.32, 0.14, base); ell(b, S, 0.38, 0.24, 0.13, base);
    ell(b, S, 0.76, 0.68, 0.14, base); ell(b, S, 0.62, 0.76, 0.13, base);
    poly(b, S, [[0.34, 0.40], [0.56, 0.56], [0.52, 0.60], [0.30, 0.44]], light);
  } },
  wisp:   { color: [179, 219, 235], draw: (b, S, base, dark, light) => {            // 灵魄：一团魂光 + 尾
    ell(b, S, 0.5, 0.40, 0.30, base);
    poly(b, S, [[0.34, 0.52], [0.66, 0.52], [0.58, 0.92], [0.42, 0.92]], base);
    ell(b, S, 0.42, 0.32, 0.12, light);
  } },
  ember:  { color: [242, 140, 64], draw: (b, S, base, dark, light) => {             // 地火芯：六边核 + 火苗
    poly(b, S, [[0.5, 0.16], [0.86, 0.40], [0.86, 0.72], [0.5, 0.96], [0.14, 0.72], [0.14, 0.40]], base);
    poly(b, S, [[0.5, 0.30], [0.68, 0.46], [0.68, 0.66], [0.5, 0.80], [0.32, 0.66], [0.32, 0.46]], [255, 232, 150]);
  } },
  marrow: { color: [184, 174, 255], draw: (b, S, base, dark, light) => {            // 雷髓：一道雷晶
    poly(b, S, [[0.60, 0.06], [0.22, 0.56], [0.46, 0.56], [0.36, 0.94], [0.80, 0.42], [0.54, 0.42]], base);
    poly(b, S, [[0.58, 0.14], [0.34, 0.52], [0.50, 0.52]], [250, 250, 255]);
  } },
  // ⭐ M33：顶层触媒补图。⚠️ 与 `art/tools/gen_items_missing.gd` 是**同一套配方**，
  //    这边是"权威版"；本机跑不了 node 时用那个 GDScript 生成，产物必须一致。
  frost:  { color: [158, 219, 242], draw: (b, S, base, dark, light) => {            // 玄霜髓：一簇霜晶
    poly(b, S, [[0.48, 0.05], [0.66, 0.34], [0.61, 0.84], [0.45, 0.95], [0.35, 0.56]], base);
    poly(b, S, [[0.32, 0.34], [0.43, 0.47], [0.37, 0.82], [0.25, 0.66]], dark);
    poly(b, S, [[0.50, 0.13], [0.59, 0.31], [0.47, 0.46]], light);
  } },
  voidcore: { color: [230, 204, 115], draw: (b, S, base, dark, light) => {          // 太虚核：金环包着空心核
    poly(b, S, [[0.50, 0.08], [0.86, 0.32], [0.86, 0.66], [0.50, 0.92], [0.14, 0.66], [0.14, 0.32]], base);
    poly(b, S, [[0.50, 0.32], [0.65, 0.42], [0.65, 0.58], [0.50, 0.68], [0.35, 0.58], [0.35, 0.42]], dark);
    poly(b, S, [[0.32, 0.24], [0.46, 0.16], [0.56, 0.20], [0.40, 0.30]], light);
  } },
  stone:  { color: [235, 209, 115], draw: (b, S, base, dark, light) => {            // 灵石：货币，一颗切面宝石
    poly(b, S, [[0.5, 0.06], [0.90, 0.42], [0.5, 0.96], [0.10, 0.42]], base);
    poly(b, S, [[0.5, 0.06], [0.68, 0.42], [0.5, 0.96], [0.32, 0.42]], light);
    poly(b, S, [[0.10, 0.42], [0.90, 0.42], [0.5, 0.52]], dark);
  } },

  // ---- M35：苍梧山材料线（色值取自 GameData.MATERIALS）----
  gallsac:    { color: [107, 168, 92],  draw: (b, S, base, dark, light) => {        // 蛇胆：一颗胆囊 + 管
    ell(b, S, 0.48, 0.58, 0.30, base);
    poly(b, S, [[0.60, 0.34], [0.78, 0.16], [0.84, 0.24], [0.68, 0.42]], dark);
    ell(b, S, 0.40, 0.48, 0.11, light);
  } },
  spiritwood: { color: [148, 128, 87],  draw: (b, S, base, dark, light) => {        // 灵木：一截带年轮的木头
    poly(b, S, [[0.16, 0.34], [0.84, 0.30], [0.86, 0.68], [0.14, 0.72]], base);
    ell(b, S, 0.30, 0.51, 0.16, dark);
    ell(b, S, 0.30, 0.51, 0.08, light);
    poly(b, S, [[0.44, 0.40], [0.80, 0.38], [0.80, 0.46], [0.44, 0.48]], light);
  } },
  ghostess:   { color: [140, 158, 184], draw: (b, S, base, dark, light) => {        // 幽魂精髓：一缕青灰魂火
    poly(b, S, [[0.5, 0.10], [0.74, 0.42], [0.66, 0.76], [0.34, 0.76], [0.26, 0.42]], base);
    poly(b, S, [[0.5, 0.34], [0.62, 0.50], [0.56, 0.70], [0.44, 0.70], [0.38, 0.50]], light);
    ell(b, S, 0.5, 0.86, 0.16, [140, 158, 184, 140]);
  } },
  gallold:    { color: [71, 133, 77],   draw: (b, S, base, dark, light) => {        // 百年蛇胆：更大的胆 + 纹
    ell(b, S, 0.48, 0.58, 0.36, base);
    poly(b, S, [[0.62, 0.24], [0.86, 0.10], [0.90, 0.22], [0.70, 0.36]], dark);
    ell(b, S, 0.38, 0.46, 0.13, light);
    for (let i = 0; i < 4; i++) poly(b, S, [[0.30 + i * 0.09, 0.42], [0.34 + i * 0.09, 0.40], [0.36 + i * 0.09, 0.72], [0.32 + i * 0.09, 0.74]], dark);
  } },
  thunderwood: { color: [168, 128, 230], draw: (b, S, base, dark, light) => {       // 天雷木：雷劈过的木头
    poly(b, S, [[0.14, 0.30], [0.86, 0.26], [0.88, 0.70], [0.12, 0.74]], base);
    poly(b, S, [[0.52, 0.26], [0.40, 0.50], [0.50, 0.50], [0.44, 0.74], [0.66, 0.44], [0.54, 0.44], [0.62, 0.26]], [255, 250, 200]);
    ell(b, S, 0.24, 0.50, 0.10, dark);
  } },
  bambooherb: { color: [97, 199, 115],  draw: (b, S, base, dark, light) => {        // 百年竹心草：三片竹叶
    poly(b, S, [[0.50, 0.92], [0.46, 0.46], [0.54, 0.46]], dark);
    poly(b, S, [[0.50, 0.46], [0.16, 0.16], [0.30, 0.10], [0.52, 0.40]], base);
    poly(b, S, [[0.52, 0.44], [0.84, 0.14], [0.90, 0.26], [0.56, 0.50]], base);
    poly(b, S, [[0.51, 0.40], [0.50, 0.08], [0.60, 0.10], [0.58, 0.42]], light);
  } },
  foxcore:    { color: [242, 168, 77],  draw: (b, S, base, dark, light) => {        // 灵狐内丹：一颗跳动金珠
    ell(b, S, 0.5, 0.5, 0.34, base);
    ell(b, S, 0.42, 0.40, 0.13, light);
    ell(b, S, 0.5, 0.5, 0.15, [255, 240, 200]);
    for (let a = 0; a < 6; a++) poly(b, S, [[0.5 + Math.cos(a * Math.PI / 3) * 0.30, 0.5 + Math.sin(a * Math.PI / 3) * 0.30],
      [0.5 + Math.cos(a * Math.PI / 3) * 0.46, 0.5 + Math.sin(a * Math.PI / 3) * 0.46],
      [0.5 + Math.cos(a * Math.PI / 3 + 0.18) * 0.44, 0.5 + Math.sin(a * Math.PI / 3 + 0.18) * 0.44]], [242, 168, 77, 150]);
  } },
  shard_common: { color: [173, 173, 179], draw: (b, S, base, dark, light) => {      // 凡印残片：一角灰色印片
    poly(b, S, [[0.20, 0.60], [0.44, 0.16], [0.82, 0.34], [0.62, 0.86]], base);
    poly(b, S, [[0.44, 0.16], [0.82, 0.34], [0.62, 0.86]], dark);
    poly(b, S, [[0.30, 0.52], [0.44, 0.26], [0.56, 0.34]], light);
  } },
  shard_fine:  { color: [140, 168, 224], draw: (b, S, base, dark, light) => {       // 精印残片：两角蓝片
    poly(b, S, [[0.12, 0.64], [0.36, 0.14], [0.62, 0.44], [0.40, 0.88]], base);
    poly(b, S, [[0.58, 0.24], [0.90, 0.32], [0.76, 0.80]], base);
    poly(b, S, [[0.58, 0.24], [0.90, 0.32], [0.76, 0.80]], dark);
    poly(b, S, [[0.22, 0.58], [0.36, 0.26], [0.46, 0.42]], light);
  } },
  shard_master: { color: [191, 148, 230], draw: (b, S, base, dark, light) => {      // 通印残片：带紫光的印片
    poly(b, S, [[0.50, 0.08], [0.92, 0.46], [0.62, 0.94], [0.18, 0.60]], base);
    poly(b, S, [[0.50, 0.08], [0.92, 0.46], [0.62, 0.94]], dark);
    poly(b, S, [[0.46, 0.22], [0.74, 0.46], [0.54, 0.74], [0.34, 0.54]], [255, 240, 255]);
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
  const made = { icons: {}, drops: {} };
  for (const [id, spec] of Object.entries(ITEMS)) {
    const base = spec.color, dark = shade(base, 0.55), light = shade(base, 1.3);
    for (const [S, suffix, bag] of [[ICON, "", "icons"], [DROP, "_drop", "drops"]]) {
      const b = mk(S);
      spec.draw(b, S, base, dark, light);
      dress(b, S, base, dark, light);
      outline(b, S, INK);
      made[bag][id] = b;
      fs.writeFileSync(path.join(outDir, id + suffix + ".png"), encodePNG(b, S, S));
    }
    log(id.padEnd(9) + " 图标 32×32 + 掉落 8×8");
  }
  // 预览：图标 32×32 放大 6 倍一行；下面是 8×8 token 放大 6 倍
  const K = 6;
  const ids = Object.keys(made.icons);
  const pw = ICON * K * Math.max(ids.length, 1), ph = (ICON + DROP) * K;
  const prev = new Uint8Array(pw * ph * 4);
  ids.forEach((id, idx) => {
    for (const [src, S, oy0] of [[made.icons[id], ICON, 0], [made.drops[id], DROP, ICON * K]]) {
      const ox = idx * ICON * K;
      for (let y = 0; y < S * K; y++) for (let x = 0; x < S * K; x++) {
        const si = (Math.floor(y / K) * S + Math.floor(x / K)) * 4, di = ((oy0 + y) * pw + (ox + x)) * 4;
        prev[di] = src[si]; prev[di + 1] = src[si + 1]; prev[di + 2] = src[si + 2]; prev[di + 3] = src[si + 3];
      }
    }
  });
  const prevPath = path.join(here, "preview_items.png");
  fs.writeFileSync(prevPath, encodePNG(prev, pw, ph));
  log("预览图: " + prevPath + " " + pw + "x" + ph);
  return { ids, preview: prevPath };
}

if (process.argv[1] && process.argv[1].endsWith("gen_items.mjs")) generate();
