// 四分区地面（**128×128 无缝**大块）—— ⭐ M30.12：修仙风纹样
//
// 为什么从 32×32 改成 128×128：一张 32 的图在 640×360 的区里要重复 20×11 次，
// **重复感本身就是「难看」的一部分**。128 之后周期变 4 倍，纹样才像「地」而不是壁纸。
//
// ⚠️ 无缝的两条纪律：
//   ①（旧版）细节不许跨边缘 —— ⭐ 现在**不再需要**：所有像素都过 wrap()，
//     跨边的纹样会从对面接上来，接缝处是「连续的纹样」而不是「一圈空边」。
//   ② 细节与底色的**亮度差要小**（10~20）。地面是背景，它一抢眼，敌人和灵印就读不出来了。
//
// ⭐ 修仙味靠**纹样**而不是靠亮：草原=灵草纹/灵芝/灵光点，岩区=错缝石板/裂纹/灵石微光，
//    雷区=雷纹折线/电弧点，热区=熔脉裂纹/余烬点。
// ⭐ 固定种子 —— 每次跑出来完全一样（可复现，截图能对比）。
//
// 跑法：node art/tools/gen_tiles.mjs   →  art/tiles/*.png + art/tools/preview_tiles.png
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";
import { fileURLToPath } from "node:url";

const N = 128;
const here = path.dirname(fileURLToPath(import.meta.url));
const outDir = path.resolve(here, "..", "tiles");

const mk = () => new Uint8Array(N * N * 4);
const w1 = (v) => ((v % N) + N) % N;
const px = (b, x, y, c) => {
  x = w1(Math.round(x)); y = w1(Math.round(y));
  const i = (y * N + x) * 4;
  b[i] = c[0]; b[i + 1] = c[1]; b[i + 2] = c[2]; b[i + 3] = 255;
};
const add = (b, x, y, c, a) => {                      // 带透明度：灵光点要柔，不能是硬像素
  x = w1(Math.round(x)); y = w1(Math.round(y));
  const i = (y * N + x) * 4;
  b[i] = Math.round(b[i] * (1 - a) + c[0] * a);
  b[i + 1] = Math.round(b[i + 1] * (1 - a) + c[1] * a);
  b[i + 2] = Math.round(b[i + 2] * (1 - a) + c[2] * a);
  b[i + 3] = 255;
};
// 底色 + 大尺度明暗。用三角函数当噪声 → **天然无缝**（周期的整数倍）
const base = (b, dark, mid, light, freq) => {
  for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
    const u = Math.sin(x / N * Math.PI * 2 * freq) * Math.cos(y / N * Math.PI * 2 * freq)
      + 0.5 * Math.sin(x / N * Math.PI * 2 * freq * 2.3 + 1.7) * Math.cos(y / N * Math.PI * 2 * freq * 1.7)
      + 0.25 * Math.sin(x / N * Math.PI * 2 * freq * 3.0 + 3.1) * Math.sin(y / N * Math.PI * 2 * freq * 3.0);
    const t = (u + 1.5) / 3.0;
    const c = [0, 0, 0];
    for (let k = 0; k < 3; k++) c[k] = Math.round(t < 0.5 ? dark[k] + (mid[k] - dark[k]) * (t * 2) : mid[k] + (light[k] - mid[k]) * ((t - 0.5) * 2));
    px(b, x, y, c);
  }
};
// 固定种子（可复现比「随机好看」重要）
const rng = (seed) => () => { seed |= 0; seed = seed + 0x6D2B79F5 | 0; let t = Math.imul(seed ^ seed >>> 15, 1 | seed); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; };

// ---- 底色照抄 GameData.ZONES 里各分区已有的颜色，不另发明 ----
const ZONES = {
  grass: {
    out: "grass.png", dark: [22, 30, 24], mid: [28, 36, 28], light: [35, 46, 33], freq: 3.0,
    do: (b, R) => {
      for (let i = 0; i < 520; i++) { const x = R() * N, y = R() * N; px(b, x, y, [40, 54, 42]); if (R() < 0.5) px(b, x, y - 1, [34, 46, 36]); }
      for (let i = 0; i < 26; i++) { const x = R() * N, y = R() * N; px(b, x, y, [46, 34, 40]); px(b, x + 1, y, [46, 34, 40]); px(b, x, y - 1, [58, 42, 50]); }
      for (let i = 0; i < 18; i++) { const x = R() * N, y = R() * N; add(b, x, y, [110, 190, 175], 0.30); add(b, x + 1, y, [110, 190, 175], 0.12); }
    },
  },
  rock: {
    out: "rock.png", dark: [30, 29, 34], mid: [37, 36, 42], light: [45, 44, 51], freq: 2.0,
    do: (b, R) => {
      const bw = 32, bh = 16, joint = [20, 20, 24];
      for (let by = 0; by < N / bh; by++) {
        const off = (by % 2) ? bw / 2 : 0;            // ⭐ 错缝：石板才像人工铺的（修仙洞府 / 古道）
        for (let bx = -1; bx <= N / bw; bx++) {
          const x0 = bx * bw + off, y0 = by * bh, tone = Math.round((R() - 0.5) * 10);
          for (let y = y0; y < y0 + bh; y++) for (let x = x0; x < x0 + bw; x++) {
            if (y >= y0 + bh - 1 || x >= x0 + bw - 1) { px(b, x, y, joint); continue; }
            const i = (w1(y) * N + w1(x)) * 4;
            px(b, x, y, [Math.max(0, b[i] + tone), Math.max(0, b[i + 1] + tone), Math.max(0, b[i + 2] + tone)]);
          }
        }
      }
      for (let i = 0; i < 7; i++) { let x = R() * N, y = R() * N; for (let k = 0; k < 14; k++) { px(b, x, y, [24, 24, 28]); x += (R() - 0.5) * 5; y += (R() - 0.5) * 5; } }
      for (let i = 0; i < 22; i++) { const x = R() * N, y = R() * N; add(b, x, y, [130, 170, 210], 0.34); add(b, x, y + 1, [130, 170, 210], 0.12); }
    },
  },
  thunder: {
    out: "thunder.png", dark: [24, 22, 34], mid: [30, 28, 42], light: [38, 35, 52], freq: 3.0,
    do: (b, R) => {
      for (let i = 0; i < 5; i++) {
        let x = R() * N, y = R() * N, dx = R() < 0.5 ? 1 : -1;
        for (let k = 0; k < 20; k++) { px(b, x, y, [128, 112, 190]); px(b, x, y + 1, [86, 74, 132]); y += 2; x += dx * (R() < 0.5 ? 2 : 1); if (R() < 0.35) dx = -dx; }
      }
      for (let i = 0; i < 60; i++) { const x = R() * N, y = R() * N; px(b, x, y, [18, 17, 26]); }
      for (let i = 0; i < 16; i++) { const x = R() * N, y = R() * N; add(b, x, y, [170, 150, 240], 0.36); }
    },
  },
  heat: {
    out: "heat.png", dark: [34, 22, 19], mid: [41, 26, 23], light: [51, 33, 27], freq: 3.0,
    do: (b, R) => {
      for (let i = 0; i < 6; i++) {
        let x = R() * N, y = R() * N, ax = (R() - 0.5) * 2, ay = (R() - 0.5) * 2;
        for (let k = 0; k < 26; k++) { add(b, x, y, [190, 96, 42], 0.55); if (R() < 0.5) add(b, x + 1, y, [140, 70, 34], 0.30); x += ax; y += ay; ax += (R() - 0.5) * 0.6; ay += (R() - 0.5) * 0.6; }
      }
      for (let i = 0; i < 40; i++) { const x = R() * N, y = R() * N; add(b, x, y, [220, 130, 60], 0.28); }
      for (let i = 0; i < 30; i++) { const x = R() * N, y = R() * N; px(b, x, y, [26, 16, 14]); }
    },
  },
};

const TBL = (() => { const t = new Int32Array(256); for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; t[n] = c; } return t; })();
const crc32 = (buf) => { let c = -1; for (let i = 0; i < buf.length; i++) c = TBL[(c ^ buf[i]) & 0xFF] ^ (c >>> 8); return (c ^ -1) >>> 0; };
const chunk = (type, data) => {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length, 0);
  const bodyb = Buffer.concat([Buffer.from(type, "ascii"), Buffer.from(data)]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(bodyb), 0);
  return Buffer.concat([len, bodyb, crc]);
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
  const made = [];
  let seed = 0x51ED;
  for (const z of Object.values(ZONES)) {
    const b = mk();
    base(b, z.dark, z.mid, z.light, z.freq);
    z.do(b, rng(seed++));
    fs.writeFileSync(path.join(outDir, z.out), encodePNG(b, N, N));
    made.push(b);
    log(z.out.padEnd(13) + " " + N + "x" + N + " 无缝");
  }
  const K = 2;
  const pw = N * K * 2, ph = N * K * 2;
  const prev = new Uint8Array(pw * ph * 4);
  made.forEach((b, idx) => {
    const ox = (idx % 2) * N * K, oy = Math.floor(idx / 2) * N * K;
    for (let y = 0; y < N * K; y++) for (let x = 0; x < N * K; x++) {
      const si = (Math.floor(y / K) * N + Math.floor(x / K)) * 4, di = ((oy + y) * pw + (ox + x)) * 4;
      prev[di] = b[si]; prev[di + 1] = b[si + 1]; prev[di + 2] = b[si + 2]; prev[di + 3] = 255;
    }
  });
  const prevPath = path.join(here, "preview_tiles.png");
  fs.writeFileSync(prevPath, encodePNG(prev, pw, ph));
  log("预览图: " + prevPath + " " + pw + "x" + ph);
  return { preview: prevPath };
}

if (process.argv[1] && process.argv[1].endsWith("gen_tiles.mjs")) generate();
