// 主角（48×48）—— ⭐ M30.11：按用户第二版参考图重做（大袖长袍）
//
// 参考图的**标志性三层结构**（这是上一版最缺的东西）：
//   ① 白色外袍（宽大、从肩一直垂到地，分左右两片）
//   ② 中间一条**深色长裙**（水墨，从上往下越来越黑）
//   ③ **黑腰带打结**（中间垂下一截带子）+ 腰腹一点灰烬橙红
//   另有：胸口日晷光 / 袖口内侧的黑内衬 / 黑色长袍拖地只露出鞋尖
//
// ⚠️ 两条与用户前几轮要求冲突的地方，已在对话里说明并取了折中：
//   · 「能看到四肢」→ 参考图里手臂被大袖包住、腿被长袍盖住，**只有手和鞋露出来**（按参考图）
//   · 「头大身体小」→ 参考图是 1:6.5，前一轮要 1:1，这里取**中间 ≈1:2**
//
// ⭐ 精致靠四条：左上打光 / 每个材质至少两级色 / 1px 描边 / 头发分缕
// 跑法：node art/tools/gen_player.mjs
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";
import { fileURLToPath } from "node:url";

const W = 48, H = 48;
const FEET_Y = 46;
const here = path.dirname(fileURLToPath(import.meta.url));
const outDir = path.resolve(here, "..", "units");

const mk = (w = W, h = H) => new Uint8Array(w * h * 4);
const setW = (b, w, h, x, y, c) => {
  x = Math.round(x); y = Math.round(y);
  if (x < 0 || y < 0 || x >= w || y >= h) return;
  const i = (y * w + x) * 4;
  b[i] = c[0]; b[i + 1] = c[1]; b[i + 2] = c[2]; b[i + 3] = c.length > 3 ? c[3] : 255;
};
const rectW = (b, w, h, x0, y0, x1, y1, c) => { for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) setW(b, w, h, x, y, c); };
const ellW = (b, w, h, cx, cy, rx, ry, c) => {
  for (let y = Math.floor(cy - ry); y <= Math.ceil(cy + ry); y++)
    for (let x = Math.floor(cx - rx); x <= Math.ceil(cx + rx); x++) {
      const dx = (x + 0.5 - cx) / rx, dy = (y + 0.5 - cy) / ry;
      if (dx * dx + dy * dy <= 1) setW(b, w, h, x, y, c);
    }
};
const set = (b, x, y, c) => setW(b, W, H, x, y, c);
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
const shadow = (b, rx) => {
  for (let y = 42; y <= 47; y++) for (let x = 8; x <= 39; x++) {
    const dx = (x + 0.5 - 24) / rx, dy = (y + 0.5 - 45.5) / 2.6;
    if (dx * dx + dy * dy <= 1 && b[(y * W + x) * 4 + 3] === 0) set(b, x, y, [0, 0, 0, 72]);
  }
};
const blit = (dst, src) => { for (let i = 0; i < dst.length; i += 4) if (src[i + 3] !== 0) { dst[i] = src[i]; dst[i + 1] = src[i + 1]; dst[i + 2] = src[i + 2]; dst[i + 3] = src[i + 3]; } };
const shiftY = (b, dy) => {
  if (dy === 0) return b;
  const out = mk();
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const sy = y - dy;
    if (sy < 0 || sy >= H) continue;
    const si = (sy * W + x) * 4, di = (y * W + x) * 4;
    out[di] = b[si]; out[di + 1] = b[si + 1]; out[di + 2] = b[si + 2]; out[di + 3] = b[si + 3];
  }
  return out;
};
const shiftX = (b, dx) => {
  if (dx === 0) return b;
  const out = mk();
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
    const sx = x - dx;
    if (sx < 0 || sx >= W) continue;
    const si = (y * W + sx) * 4, di = (y * W + x) * 4;
    out[di] = b[si]; out[di + 1] = b[si + 1]; out[di + 2] = b[si + 2]; out[di + 3] = b[si + 3];
  }
  return out;
};

// ---- 调色板：白 → 浅灰 → 中灰 → 深灰 → 近黑（**五档**，上一版只有两档，这是「看着平」的主因）----
const P = {
  ink: [18, 19, 25],
  robe: [240, 241, 245], robeLit: [252, 252, 255], robeDark: [206, 210, 219], robeMid: [176, 181, 192],
  robeHem: [118, 122, 133], robeHem2: [76, 80, 90], skirt: [58, 61, 70], skirtDark: [40, 43, 51],
  collar: [40, 43, 52],
  sash: [50, 52, 61], sashGlow: [237, 139, 63],
  dial: [252, 246, 214],
  skin: [240, 221, 204], skinShade: [212, 188, 170],
  hair: [30, 34, 45], hairHi: [70, 76, 94], hairMid: [48, 53, 66], hairWhite: [230, 233, 239],
  shoe: [34, 36, 44],
  eye: [26, 28, 38], eyeHi: [250, 250, 255],
  spirit: [140, 217, 242], spiritLight: [206, 242, 252],
};

const S2 = (b, x, y, c) => set(b, x, y, c);
const stamp = (w, h, draw) => {
  const b = mk(w, h);
  const api = {
    S: (x, y, c) => setW(b, w, h, x, y, c),
    R: (x0, y0, x1, y1, c) => rectW(b, w, h, x0, y0, x1, y1, c),
    E: (cx, cy, rx, ry, c) => ellW(b, w, h, cx, cy, rx, ry, c),
  };
  draw(api);
  return { w, h, buf: b };
};
const put = (dst, s, x0, y0, flip = false) => {
  for (let y = 0; y < s.h; y++) for (let x = 0; x < s.w; x++) {
    const si = (y * s.w + x) * 4;
    if (s.buf[si + 3] === 0) continue;
    const dx = flip ? x0 + s.w - 1 - x : x0 + x;
    set(dst, dx, y0 + y, [s.buf[si], s.buf[si + 1], s.buf[si + 2], s.buf[si + 3]]);
  }
};

// ==================== 四块印章（头 ≈ 身高的 1/3，取中间比例）====================

// 头：20×20（放 x14, y2）
const HEAD = stamp(20, 20, ({ S, R, E }) => {
  E(10, 8, 9.5, 6.6, P.hair);                 // 头发一大团
  E(10, 13, 7, 6.4, P.skin);                  // 脸
  R(2, 10, 18, 12, P.hair);                   // 额前碎发
  S(3, 13, P.hair); S(7, 13, P.hair); S(12, 13, P.hair); S(16, 13, P.hair);
  R(1, 13, 2, 18, P.hair); R(18, 13, 19, 18, P.hair);        // 两侧垂发
  S(2, 17, P.hairWhite); S(2, 18, P.hairWhite);              // ⭐ 设定 §4.1：鬓角几缕白发
  S(18, 17, P.hairWhite); S(18, 18, P.hairWhite);
  R(5, 3, 11, 4, P.hairHi);                   // ⭐ 左上打光：头发高光带
  S(4, 8, P.hairMid); S(5, 7, P.hairMid);     // 分缕
  S(16, 8, P.hairMid); S(15, 7, P.hairMid);
  R(5, 14, 8, 14, P.hair); R(12, 14, 15, 14, P.hair);        // 眉
  R(5, 15, 7, 16, P.eye); R(12, 15, 14, 16, P.eye);          // 眼 3×2
  S(6, 15, P.eyeHi); S(13, 15, P.eyeHi);                     // 眼里高光
  S(5, 17, P.skinShade); S(12, 17, P.skinShade);             // 眼下阴影
  S(10, 18, P.skinShade);                     // 鼻影
  R(9, 19, 10, 19, P.skinShade);              // 嘴
});

// 袍：22×24（放 x13, y20）—— ⭐ 标志性三层：白外袍 + 中间深色长裙 + 黑腰带（打结）
const ROBE = stamp(22, 24, ({ S, R }) => {
  R(5, 0, 16, 0, P.robe);                     // 外领（白）
  R(1, 2, 5, 6, P.robe); R(16, 2, 20, 6, P.robe);           // ⭐ 加宽肩膀：和大袖接上（不然袖子像挂在窄身子上）
  R(1, 2, 1, 6, P.robeLit); R(20, 3, 20, 6, P.robeDark);    // 肩部也留打光/压暗
  R(8, 1, 13, 2, P.collar);                   // 内领（黑）—— 参考图的交领就是白压黑
  R(9, 2, 12, 2, P.robe);                     // 白 V 收口
  R(4, 3, 17, 8, P.robe);                     // 白袍前胸
  S(10, 5, P.dial); S(11, 5, P.dial);         // 胸口日晷光
  R(4, 3, 4, 8, P.robeLit);                   // ⭐ 左上打光：左缘最亮
  R(17, 4, 17, 8, P.robeDark);                // 右缘压暗
  R(7, 4, 7, 8, P.robeDark); R(14, 5, 14, 8, P.robeMid);     // 衣褶（两级灰）
  R(3, 9, 18, 12, P.sash);                    // ⭐ 黑腰带
  R(9, 13, 12, 18, P.sash);                   // ⭐ 垂下来的带结
  R(7, 10, 14, 10, P.sashGlow); S(9, 9, P.sashGlow); S(10, 9, P.sashGlow);
  // ---- 腰带以下：中间深色长裙 + 两侧白外袍（这是参考图最像的地方）----
  R(6, 13, 15, 17, P.robeHem);                // 长裙：中灰
  R(6, 18, 15, 19, P.robeHem2);               // → 深灰
  R(7, 20, 14, 22, P.skirt);                  // → 近黑
  R(8, 23, 13, 23, P.skirtDark);              // → 最底
  R(3, 13, 5, 22, P.robe);                    // 左侧白外袍
  R(16, 13, 18, 22, P.robe);
  R(2, 16, 2, 22, P.robeDark); R(19, 16, 19, 22, P.robeDark); // 外袍外缘压暗
  R(3, 23, 5, 23, P.robeMid); R(16, 23, 18, 23, P.robeMid);  // 外袍下摆
});

// 大袖：9×17（放 x5 / 镜像 x34）—— 参考图的袖子从肩垂到腰下、往外撇
// 大袖：6×15（放 x9 / 镜像 x33）—— ⚠️ 上一版 9×17 太肥：整个人横跨 38px，用户说「手臂这么大，人太宽了」
//    现在只用 6 格宽，贴着袍子垂下；**手自然垂在袖口下面**（看得出是一只垂着的手，不是袖子上的一块肉色）
const SLEEVE = stamp(6, 15, ({ S, R }) => {
  R(2, 0, 5, 2, P.robe);                      // 肩
  R(1, 2, 5, 10, P.robe);                     // 袖身（细长）
  R(0, 10, 5, 12, P.robe);                    // 袖口微微外撇
  R(4, 3, 5, 12, P.robeDark);                 // 右缘压暗（左上打光）
  R(1, 3, 1, 10, P.robeLit);                  // 左缘受光
  R(1, 11, 4, 11, P.collar);                  // 袖口内侧的黑内衬
  R(2, 12, 3, 14, P.skin);                    // ⭐ 手自然下垂
  S(2, 14, P.skinShade);
});

// 鞋：5×4（放 x19 / 镜像 x25）—— 长袍拖地，只露鞋尖
const SHOE = stamp(5, 4, ({ R }) => {
  R(0, 0, 4, 1, P.shoe);
  R(1, 2, 4, 2, P.shoe);
});

// ==================== 摆帧 ====================
const body = (b, armL, armR, legL, legR) => {
  put(b, SHOE, 19 + legL[0], 43 + legL[1], false);
  put(b, SHOE, 25 + legR[0], 43 + legR[1], true);
  put(b, ROBE, 13, 20);
  put(b, SLEEVE, 9 + armL[0], 22 + armL[1], false);          // 左袖 x9..14（和袍缘重叠 1px）
  put(b, SLEEVE, 33 - armR[0], 22 + armR[1], true);          // 右袖 x33..38
  // ⚠️ 踩过：这里原来是 5 / 34（袖子 9 宽）→ 整个人横跨 38px，用户说「太宽了」
  put(b, HEAD, 14, 2);
};
const finish = (b, dx = 0, dy = 0) => {
  outline(b, P.ink);
  const f = mk();
  shadow(f, 13);
  blit(f, shiftX(shiftY(b, dy), dx));
  return f;
};
const A0 = [0, 0];
const stand = () => { const b = mk(); body(b, A0, A0, [0, 0], [0, 0]); return finish(b); };
const walk = (front, sink) => {
  const b = mk();
  const sw = front < 0 ? [0, -1] : (front > 0 ? [0, 1] : A0);
  const swR = front < 0 ? [0, 1] : (front > 0 ? [0, -1] : A0);
  if (front < 0) body(b, sw, swR, [-2, 0], [1, -1]);
  else if (front > 0) body(b, sw, swR, [1, -1], [-2, 0]);
  else body(b, A0, A0, [0, 0], [0, 0]);
  return finish(b, front < 0 ? -1 : (front > 0 ? 1 : 0), sink ? 1 : 0);
};
const cast = (stage) => {
  const b = mk();
  const poses = [[[-1, -3], A0], [[-2, -6], A0], [[-3, -2], A0], [A0, A0]];
  const p = poses[Math.max(0, Math.min(3, stage))];
  body(b, p[0], p[1], [0, 0], [0, 0]);
  if (stage === 1) { S2(b, 7, 17, P.spirit); S2(b, 8, 17, P.spirit); S2(b, 7, 18, P.spiritLight); }
  if (stage === 2) { S2(b, 5, 21, P.spirit); S2(b, 5, 22, P.spirit); S2(b, 6, 21, P.spiritLight); }
  return finish(b);
};
const attack = (stage) => {
  const b = mk();
  const poses = [[[-1, -2], A0], [[-5, 1], A0], [A0, A0]];
  const p = poses[Math.max(0, Math.min(2, stage))];
  body(b, p[0], p[1], [0, 0], [0, 0]);
  if (stage === 1) { for (let i = 0; i < 6; i++) S2(b, 3 + i, 21 + i, P.spirit); }
  return finish(b);
};
const combo = (stage) => {
  const b = mk();
  const poses = [[[-2, -5], [-2, -5]], [[-1, -4], [-2, -5]], [[-2, -5], [-1, -4]],
    [[-4, -2], [-4, -2]], [[-6, 0], [-6, 0]], [A0, A0]];
  const p = poses[Math.max(0, Math.min(5, stage))];
  body(b, p[0], p[1], [0, 0], [0, 0]);
  if (stage === 3) { S2(b, 9, 19, P.spirit); S2(b, 38, 19, P.spirit); }
  if (stage === 4) {
    S2(b, 9, 18, P.spirit); S2(b, 9, 19, P.spirit); S2(b, 8, 18, P.spiritLight);
    S2(b, 38, 18, P.spirit); S2(b, 38, 19, P.spirit); S2(b, 39, 18, P.spiritLight);
  }
  return finish(b);
};

const frames = {
  player: stand,
  player_walk0: () => walk(-1, false),
  player_walk1: () => walk(0, false),
  player_walk2: () => walk(1, false),
  player_walk3: () => walk(0, true),
  player_cast0: () => cast(0), player_cast1: () => cast(1),
  player_cast2: () => cast(2), player_cast3: () => cast(3),
  player_combo0: () => combo(0), player_combo1: () => combo(1), player_combo2: () => combo(2),
  player_combo3: () => combo(3), player_combo4: () => combo(4), player_combo5: () => combo(5),
  player_attack0: () => attack(0), player_attack1: () => attack(1), player_attack2: () => attack(2),
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
  const made = {};
  for (const [name, fn] of Object.entries(frames)) {
    const b = fn();
    made[name] = b;
    fs.writeFileSync(path.join(outDir, name + ".png"), encodePNG(b, W, H));
    let opaque = 0, foot = -1;
    for (let i = 3; i < b.length; i += 4) if (b[i] > 0) opaque++;
    for (let y = H - 1; y >= 0 && foot < 0; y--) for (let x = 0; x < W; x++) if (b[(y * W + x) * 4 + 3] > 200) { foot = y; break; }
    log(name.padEnd(15) + " 不透明 " + String(opaque).padStart(4) + "  脚底 y=" + foot);
  }
  const K = 5, COLS = 6;
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
  const prevPath = path.join(here, "preview_player.png");
  fs.writeFileSync(prevPath, encodePNG(prev, pw, ph));
  log("预览图: " + prevPath + " " + pw + "x" + ph);
  return { names, preview: prevPath };
}

if (process.argv[1] && process.argv[1].endsWith("gen_player.mjs")) generate();
