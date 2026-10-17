// 立绘接入工具（批 A）：读 AI 出的 PNG → 抠底 → 裁到内容 → 缩到目标高 → 底部锚定 → 输出帧
//
// ⭐ 为什么自带 PNG 解码：项目里其它生成器只会**写** PNG（Node 无内置解码，
//    而这里要**读**用户的图）。只支持 8bit 非隔行的 RGB / RGBA —— AI 出的图基本都是这两种。
//
// ⭐ 锚点约定（和 GameData / 自测绑死）：**内容底边 = 画布高 − 8**。
//    192 高 → offset.y = -(192/2 - 8) = -88。
//
// 用法：node art/tools/import_art.mjs <源图.png> <输出名> [--cols N --rows M]
//   不带 cols/rows：整张图算一帧；带了就按等分格子切。
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";
import { fileURLToPath } from "node:url";
const here = path.dirname(fileURLToPath(import.meta.url));
const outDir = path.resolve(here, "..", "units_hd");

export function decodePNG(buf) {
  if (buf.readUInt32BE(0) !== 0x89504E47) throw new Error("不是 PNG 文件");
  let off = 8, w = 0, h = 0, depth = 0, ctype = 0, interlace = 0;
  const idat = [];
  while (off + 8 <= buf.length) {
    const len = buf.readUInt32BE(off);
    const type = buf.toString("ascii", off + 4, off + 8);
    const data = buf.subarray(off + 8, off + 8 + len);
    if (type === "IHDR") { w = data.readUInt32BE(0); h = data.readUInt32BE(4); depth = data[8]; ctype = data[9]; interlace = data[12]; }
    else if (type === "IDAT") idat.push(data);
    else if (type === "IEND") break;
    off += 12 + len;
  }
  if (depth !== 8 || interlace !== 0) throw new Error("只支持 8bit 非隔行（depth=" + depth + " interlace=" + interlace + "）");
  if (ctype !== 2 && ctype !== 6) throw new Error("只支持 RGB / RGBA（ctype=" + ctype + "，请存成 PNG-24/32）");
  const ch = ctype === 6 ? 4 : 3;
  const raw = zlib.inflateSync(Buffer.concat(idat));
  const stride = w * ch;
  const out = Buffer.alloc(w * h * 4);
  const cur = Buffer.alloc(stride), prev = Buffer.alloc(stride);
  let p = 0;
  for (let y = 0; y < h; y++) {
    const f = raw[p++];
    raw.copy(cur, 0, p, p + stride); p += stride;
    for (let i = 0; i < stride; i++) {
      const a = i >= ch ? cur[i - ch] : 0, b = prev[i], c = i >= ch ? prev[i - ch] : 0;
      let v = cur[i];
      if (f === 1) v = (v + a) & 255;
      else if (f === 2) v = (v + b) & 255;
      else if (f === 3) v = (v + ((a + b) >> 1)) & 255;
      else if (f === 4) { const pa = Math.abs(b - c), pb = Math.abs(a - c), pc = Math.abs(a + b - 2 * c); v = (v + ((pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c))) & 255; }
      cur[i] = v;
    }
    for (let x = 0; x < w; x++) { const s = x * ch, d = (y * w + x) * 4; out[d] = cur[s]; out[d + 1] = cur[s + 1]; out[d + 2] = cur[s + 2]; out[d + 3] = ch === 4 ? cur[s + 3] : 255; }
    cur.copy(prev);
  }
  return { w, h, rgba: out };
}

// 抠底：取四角平均当底色，距离小于容差的像素变透明（AI 图常给纯色底）
export function removeBackground(img, tol = 30) {
  const { w, h, rgba } = img;
  const corners = [[0, 0], [w - 1, 0], [0, h - 1], [w - 1, h - 1]];
  let br = 0, bg = 0, bb = 0;
  for (const [x, y] of corners) { const i = (y * w + x) * 4; br += rgba[i] / 4; bg += rgba[i + 1] / 4; bb += rgba[i + 2] / 4; }
  for (let i = 0; i < rgba.length; i += 4) {
    const d = Math.sqrt((rgba[i] - br) ** 2 + (rgba[i + 1] - bg) ** 2 + (rgba[i + 2] - bb) ** 2);
    if (d < tol) rgba[i + 3] = 0;
  }
  return img;
}

export function contentBox(img, x0 = 0, y0 = 0, x1 = -1, y1 = -1) {
  const { w, h, rgba } = img;
  if (x1 < 0) x1 = w - 1; if (y1 < 0) y1 = h - 1;
  let ax = x1, ay = y1, bx = x0, by = y0, found = false;
  for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) {
    if (rgba[(y * w + x) * 4 + 3] < 8) continue;
    found = true;
    if (x < ax) ax = x; if (x > bx) bx = x; if (y < ay) ay = y; if (y > by) by = y;
  }
  if (!found) throw new Error("这一帧里没有不透明像素（图是空的 / 容差抠过头了）");
  return { x0: ax, y0: ay, x1: bx, y1: by, w: bx - ax + 1, h: by - ay + 1 };
}

// 缩放：**面积平均**（平滑降采样 = 动画该有的柔边；像素风才要最近邻）
export function resizeArea(img, box, dw, dh) {
  const { w, rgba } = img;
  const out = Buffer.alloc(dw * dh * 4);
  for (let y = 0; y < dh; y++) for (let x = 0; x < dw; x++) {
    const sx0 = box.x0 + Math.floor(x * box.w / dw), sx1 = box.x0 + Math.max(Math.floor((x + 1) * box.w / dw), Math.floor(x * box.w / dw) + 1);
    const sy0 = box.y0 + Math.floor(y * box.h / dh), sy1 = box.y0 + Math.max(Math.floor((y + 1) * box.h / dh), Math.floor(y * box.h / dh) + 1);
    let r = 0, g = 0, b = 0, a = 0, n = 0;
    for (let sy = sy0; sy < sy1 && sy < box.y0 + box.h; sy++) for (let sx = sx0; sx < sx1 && sx < box.x0 + box.w; sx++) {
      const i = (sy * w + sx) * 4, al = rgba[i + 3] / 255;
      r += rgba[i] * al; g += rgba[i + 1] * al; b += rgba[i + 2] * al; a += al; n++;
    }
    const d = (y * dw + x) * 4;
    if (n === 0 || a === 0) { out[d + 3] = 0; continue; }
    out[d] = Math.round(r / a); out[d + 1] = Math.round(g / a); out[d + 2] = Math.round(b / a);
    out[d + 3] = Math.round(Math.min(1, a / n) * 255);
  }
  return { w: dw, h: dh, rgba: out };
}

// 底部锚定到固定画布（脚底留 MARGIN px）
export const MARGIN = 8;
export function anchorBottom(img, targetH, canvasW = 0) {
  const cw = canvasW > 0 ? canvasW : Math.max(img.w, Math.round(targetH * 0.75));
  const out = Buffer.alloc(cw * targetH * 4);
  const ox = Math.round((cw - img.w) / 2), oy = targetH - MARGIN - img.h;
  for (let y = 0; y < img.h; y++) for (let x = 0; x < img.w; x++) {
    const dy = y + oy, dx = x + ox;
    if (dy < 0 || dy >= targetH || dx < 0 || dx >= cw) continue;
    const si = (y * img.w + x) * 4, di = (dy * cw + dx) * 4;
    const a = img.rgba[si + 3] / 255;
    out[di] = Math.round(img.rgba[si] * a + out[di] * (1 - a));
    out[di + 1] = Math.round(img.rgba[si + 1] * a + out[di + 1] * (1 - a));
    out[di + 2] = Math.round(img.rgba[si + 2] * a + out[di + 2] * (1 - a));
    out[di + 3] = Math.max(out[di + 3], img.rgba[si + 3]);
  }
  return { w: cw, h: targetH, rgba: out };
}

const TBL = (() => { const t = new Int32Array(256); for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; t[n] = c; } return t; })();
const crc32 = (b) => { let c = -1; for (let i = 0; i < b.length; i++) c = TBL[(c ^ b[i]) & 0xFF] ^ (c >>> 8); return (c ^ -1) >>> 0; };
const chunk = (type, data) => { const len = Buffer.alloc(4); len.writeUInt32BE(data.length, 0); const bb = Buffer.concat([Buffer.from(type, "ascii"), Buffer.from(data)]); const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(bb), 0); return Buffer.concat([len, bb, crc]); };
export function encodePNG(rgba, w, h) {
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) { raw[y * (w * 4 + 1)] = 0; Buffer.from(rgba.buffer, y * w * 4, w * 4).copy(raw, y * (w * 4 + 1) + 1); }
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 6;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", zlib.deflateSync(raw, { level: 9 })), chunk("IEND", new Uint8Array(0))]);
}

export function importSheet(srcPath, name, targetH = 192, cols = 1, rows = 1, log = console.log) {
  const img = decodePNG(fs.readFileSync(srcPath));
  removeBackground(img);
  fs.mkdirSync(outDir, { recursive: true });
  const made = [];
  for (let r = 0; r < rows; r++) for (let c = 0; c < cols; c++) {
    const cw = Math.floor(img.w / cols), chh = Math.floor(img.h / rows);
    const box = contentBox(img, c * cw, r * chh, (c + 1) * cw - 1, (r + 1) * chh - 1);
    const dh = targetH, dw = Math.max(1, Math.round(box.w * dh / box.h));
    const scaled = resizeArea(img, box, dw, dh);
    const framed = anchorBottom(scaled, targetH);
    const fn = (cols * rows === 1 ? name : name + String(r * cols + c)) + ".png";
    fs.writeFileSync(path.join(outDir, fn), encodePNG(framed.rgba, framed.w, framed.h));
    made.push({ file: fn, w: framed.w, h: framed.h, srcBox: box });
    log(fn.padEnd(24) + framed.w + "x" + framed.h + "  源图内容 " + box.w + "x" + box.h);
  }
  log("锚点约定：内容底边 = 高 − " + MARGIN + " → 192 高时 visual.offset.y = " + (-(targetH / 2 - MARGIN)));
  return made;
}

if (process.argv[1] && process.argv[1].endsWith("import_art.mjs")) {
  const [src, name, cols, rows] = process.argv.slice(2);
  importSheet(src, name || "hd_out", 192, Number(cols) || 1, Number(rows) || 1);
}
