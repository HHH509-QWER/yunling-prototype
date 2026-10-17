// 占位像素素材生成器（32×32）
//
// ⭐ 它存在的意义：在真美术到位之前，把「色块 → 像素贴图」这条管线跑通并肉眼可见。
//    《像素美术规范》里说的一切（32×32、脚在 y=30、颜色取自 GameData）都由这个文件演示。
//    真美术一进 art/units/，这个脚本就可以删 —— 数据表里的路径不用改。
//
// 跑法：node art/tools/gen_units.mjs
import fs from "node:fs";
import path from "node:path";
import zlib from "node:zlib";
import { fileURLToPath } from "node:url";

const W = 32, H = 32;
const here = path.dirname(fileURLToPath(import.meta.url));
const outDir = path.resolve(here, "..", "units");

const mk = () => new Uint8Array(W * H * 4);
const set = (b, x, y, c) => { if (x < 0 || y < 0 || x >= W || y >= H) return; const i = (y * W + x) * 4; b[i] = c[0]; b[i + 1] = c[1]; b[i + 2] = c[2]; b[i + 3] = c.length > 3 ? c[3] : 255; };
const L = (b, x, y, c) => { if (x >= 0 && x < 16) set(b, x, y, c); };          // 只画左半，随后镜像 —— 左右绝对对称
const rectL = (b, x0, y0, x1, y1, c) => { for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) L(b, x, y, c); };
const ellL = (b, cx, cy, rx, ry, c) => {
  for (let y = Math.floor(cy - ry); y <= Math.ceil(cy + ry); y++)
    for (let x = Math.floor(cx - rx); x <= Math.ceil(cx + rx); x++) {
      const dx = (x + 0.5 - cx) / rx, dy = (y + 0.5 - cy) / ry;
      if (dx * dx + dy * dy <= 1) L(b, x, y, c);
    }
};
// 逐行按宽度收放 —— 菱（ym 居中）和三角（ym = y1）共用它。
// ⭐ 形状语言要的是**外轮廓**：贴图画得再细，远看糊成一片时能认出的还是这个轮廓。
const taperL = (b, y0, y1, ym, hw, c) => {
  for (let y = y0; y <= y1; y++) {
    const t = y <= ym ? (y - y0) / Math.max(ym - y0, 1) : (y1 - y) / Math.max(y1 - ym, 1);
    const w = Math.round(hw * t);
    for (let x = 15; x >= 15 - w; x--) L(b, x, y, c);
  }
};
const mirror = (b) => { for (let y = 0; y < H; y++) for (let x = 0; x < 16; x++) { const i = (y * W + x) * 4, j = (y * W + 31 - x) * 4; b[j] = b[i]; b[j + 1] = b[i + 1]; b[j + 2] = b[i + 2]; b[j + 3] = b[i + 3]; } };
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
const blit = (dst, src) => { for (let i = 0; i < dst.length; i += 4) if (src[i + 3] !== 0) { dst[i] = src[i]; dst[i + 1] = src[i + 1]; dst[i + 2] = src[i + 2]; dst[i + 3] = src[i + 3]; } };
// 整张内容水平平移 —— 走路时拿来做「重心左右倒」。
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
// 整张内容垂直平移 —— 走路「并拢帧下沉」用它做重心起伏（M30.5b）
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
// 绝对坐标的矩形：脚要画在右半（21~22），L() 只认左半
const rect = (b, x0, y0, x1, y1, c) => { for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) set(b, x, y, c); };

const shadow = (b, rx) => { for (let y = 26; y <= 31; y++) for (let x = 0; x < W; x++) { const dx = (x + 0.5 - 16) / rx, dy = (y + 0.5 - 29) / 2.6; if (dx * dx + dy * dy <= 1) { if (b[(y * W + x) * 4 + 3] === 0) set(b, x, y, [0, 0, 0, 70]); } } };

// 调色板：每一种都直接取自 GameData 里该原型已有的 color —— 色块换像素，颜色不换，玩家认得出是同一个东西
const P = {
  ink: [16, 17, 22],
  // ⭐ M30.8：主角五色按**用户给的参考图**重定（水墨白袍 / 黑凌乱短发 / 黑腰带 / 腰腹灰烬火光 / 胸口日晷）
  robe: [234, 235, 239],       // 袍白（参考图的袍是冷白，不是暖白）
  robeDark: [176, 180, 191],   // 袍的暗部（袖子内折、下摆中段）
  robeHem: [92, 96, 106],      // ⭐ 下摆深灰（参考图是水墨渐变：上白下黑）
  robeHem2: [54, 57, 66],      // ⭐ 下摆最底一档（接近黑）
  collar: [40, 43, 52],        // ⭐ 交领内衬的黑（参考图领口有黑边）
  skin: [236, 216, 198],       // 皮肤：比原来更苍白（设定「皮肤苍白」）
  hair: [28, 32, 42],          // 黑发
  hairHi: [58, 64, 78],        // ⭐ 发丝高光：没有它，黑发在深色背景上糊成一坨
  sash: [46, 48, 57],          // ⭐ **黑腰带**（参考图就是黑的 —— 原来那抹橙红挪去做腰腹火光了）
  sashGlow: [236, 138, 62],    // ⭐ 腰腹的灰烬火光：**全身唯一的高饱和**（本命印伏笔，§四）
  dial: [252, 246, 214],       // ⭐ 胸口的日晷光（「隐约透出」→ 32×32 里就是两个亮点）
  stone: [140, 148, 158], stoneDark: [58, 62, 69], target: [200, 80, 70],
  beast: [199, 89, 77], beastDark: [138, 58, 50], beastInk: [60, 26, 24], eyeY: [255, 210, 77],
  cast: [97, 204, 219], castLight: [180, 235, 245], castGlow: [159, 232, 240], castInk: [30, 90, 105],
  hunt: [140, 115, 204], huntDark: [90, 74, 134], huntInk: [55, 42, 86], eyeP: [232, 210, 77],
  charge: [219, 143, 61], chargeDark: [160, 100, 40], chargeInk: [80, 45, 18],
  spirit: [140, 217, 242], spiritLight: [206, 242, 252],   // 和采集点同一套灵光色
  shoe: [40, 42, 50],                                      // ⭐ M30.8：黑鞋（参考图）+ 比袍摆更深，走路看得见
};

// ⭐ 形状语言的落点：**轮廓**决定「这是什么」，**颜色**决定「这是什么阵营」。
//    脚统一画在 y=30，配合数据表 offset = (0, -14) 让脚正好踩在碰撞圆心上。
// 躯干 + 头（**不含手臂**）—— 手臂必须能单独画：动作帧是左右不对称的。
// ⭐ M30.8：主角按用户参考图重画（白袍黑发少年，水墨风）。
//    32×32 装不下「大袖 / 交领细节 / 日晷刻度 / 水墨渐变」，所以只留最抓眼的 5 件事：
//      ① 黑色凌乱短发（额前碎发 + 两侧垂发）② 黑腰带 ③ 腰腹一点灰烬橙红
//      ④ 下摆上白下黑（三档渐变）⑤ 胸口一点日晷光
//    ⚠️ 袍摆仍然收在 y=26：脚要露得出来，走路才看得见（M30.5b 的教训）
const playerTorso = (b) => {
  // ---- 袍身：胸腹是白的（参考图）----
  ellL(b, 15.5, 22, 7, 4.6, P.robe);        // 袍摆（下缘 y=26）
  rectL(b, 9, 14, 15, 17, P.robe);          // 袍身：胸（领口以下）
  // ---- 下摆：上白下黑的三档水墨渐变（腰带以下越来越深）----
  rectL(b, 9, 22, 15, 23, P.robeDark);
  rectL(b, 9, 24, 15, 25, P.robeHem);
  rectL(b, 9, 26, 15, 26, P.robeHem2);
  // ---- 交领：白袍领口下的黑内衬（参考图最显眼的一处）----
  rectL(b, 11, 14, 15, 14, P.collar);
  rectL(b, 13, 15, 15, 15, P.robe);         // 交领的 V：白压黑
  // ---- 胸口：日晷（「隐约透出」→ 两个亮点，不是刻度）----
  set(b, 13, 16, P.dial); set(b, 14, 16, P.dial);
  // ---- 黑腰带 + 腰腹的灰烬火光（全身唯一的高饱和）----
  rectL(b, 9, 18, 15, 20, P.sash);
  set(b, 12, 19, P.sashGlow); set(b, 13, 19, P.sashGlow); set(b, 14, 19, P.sashGlow);
  set(b, 13, 17, P.sashGlow);                // 火光往上舔一点
  // ---- 头 + 黑凌乱短发（原来那个发髻去掉）----
  // ⚠️ 第一版头发画太重 → 变成「黑色大头盔」，脸只剩一条缝。收紧：
  //    短发**只盖头顶 + 额头一两行**，鬓角稀疏（1~2px），脸留出 4 行。
  ellL(b, 15.5, 11, 4.6, 3.8, P.skin);       // 头
  ellL(b, 15.5, 8.6, 5.0, 3.2, P.hair);      // 头顶（短）
  rectL(b, 11, 9, 15, 10, P.hair);           // 额前碎发：只压两行
  set(b, 10, 11, P.hair); set(b, 10, 12, P.hair);   // 鬓角：稀疏，不包住脸
  set(b, 11, 7, P.hairHi); set(b, 13, 8, P.hairHi); // 发丝高光（凌乱感）
  set(b, 13, 12, P.ink); set(b, 12, 12, P.ink);     // 眼
  set(b, 14, 13, P.robeDark);                       // 一点鼻影/嘴影
  set(b, 9, 13, P.hair);                            // 鬓角再垂一格（左边）
};

// 手臂：⭐ 动作帧左右不对称，所以左右手要能分开画。
// armL 收绝对坐标；armR 收的是**左半的镜像坐标**（省得每次手算 31-x）。
const armL = (b, x0, y0, x1, y1, c) => { for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) set(b, x, y, c || P.robe); };
const armR = (b, x0, y0, x1, y1, c) => { for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) set(b, 31 - x, y, c || P.robe); };
const ARM_X0 = 7, ARM_Y0 = 15, ARM_X1 = 10, ARM_Y1 = 19;    // 站定时的肩袖位置

// 对称的完整身体（静止帧、走路帧用）
const playerBody = (b) => {
  playerTorso(b);
  mirror(b);
  armL(b, ARM_X0, ARM_Y0, ARM_X1, ARM_Y1);
  armR(b, ARM_X0, ARM_Y0, ARM_X1, ARM_Y1);
};

// ⭐ M30.5b：脚。**露得出来的脚**才是走路的第一信号（原来只点 3 个像素、藏在袍摆里）。
//    位置说明：袍摆下缘在 y=26，所以脚画在 27~30；影子的上缘在 26，正好接上。
const playerFeet = (b, mode) => {
  const leg = P.robeHem, shoe = P.shoe;      // ⭐ M30.8：腿用深灰（袍摆以下要分得出来）
  if (mode === "left") {                     // 左脚前踏：前脚更长（露出一整只鞋）
    rect(b, 9, 27, 11, 29, leg); rect(b, 9, 30, 11, 30, shoe);
    rect(b, 13, 27, 14, 28, leg);
  } else if (mode === "right") {
    rect(b, 20, 27, 22, 29, leg); rect(b, 20, 30, 22, 30, shoe);
    rect(b, 17, 27, 18, 28, leg);
  } else if (mode === "low") {               // 并拢 + 重心低：两只脚都踩实但短一格
    rect(b, 12, 27, 13, 28, leg); rect(b, 12, 29, 13, 29, shoe);
    rect(b, 18, 27, 19, 28, leg); rect(b, 18, 29, 19, 29, shoe);
  } else {                                   // 站定：两脚齐
    rect(b, 12, 27, 13, 29, leg); rect(b, 12, 30, 13, 30, shoe);
    rect(b, 18, 27, 19, 29, leg); rect(b, 18, 30, 19, 30, shoe);
  }
};

// ⭐ 走路帧必须**打破左右对称** —— 所以不能整张走 mirror()。
//    先用 mirror() 把对称的头身钉好，再单独画两条腿；脚落在袍摆下缘（y=28~29）。
//    front: -1 左腿踏出 / 0 并拢 / +1 右腿踏出；sink: 重心下沉（中立帧的两个相位）。
// ⭐ M30.5b：走路帧重做。原来 4 帧只差「整身平移 1px + 3 个脚像素」，预览图像没在走。
//    让人一眼看出「在走」的三件事，按重要性排：
//      ① **两脚交替**（袍摆收短后才看得见）
//      ② **手臂反向摆**（左腿在前 → 左臂向后抬）
//      ③ **并拢帧重心下沉 1px**
//    再加上原有的「整身左右倒 1px」—— 四帧下来才是一条真的步态。
const playerStep = (front, sink) => {
  const b = mk();
  playerTorso(b);
  mirror(b);
  const sL = front < 0 ? -1 : (front > 0 ? 1 : 0);   // 左腿在前 → 左臂后摆
  armL(b, ARM_X0, ARM_Y0 + sL, ARM_X1, ARM_Y1 + sL);
  armR(b, ARM_X0, ARM_Y0 - sL, ARM_X1, ARM_Y1 - sL);
  playerFeet(b, front < 0 ? "left" : (front > 0 ? "right" : (sink ? "low" : "stand")));
  outline(b, P.ink);
  const body = shiftX(b, front < 0 ? -1 : (front > 0 ? 1 : 0));
  const bobbed = shiftY(body, sink ? 1 : 0);         // 并拢帧下沉：重心起伏
  const f2 = mk(); shadow(f2, 8); blit(f2, bobbed); return f2;
};

// 放印 4 帧：抬手 → 聚灵光 → 推出 → 收势。
// ⭐ **只有一手在动**，另一手垂着 —— 不对称正是动作可读性的来源：一眼看出这是在施法，不是在走路。
const playerCast = (stage) => {
  const b = mk();
  playerTorso(b);
  mirror(b);
  armR(b, ARM_X0, ARM_Y0, ARM_X1, ARM_Y1);        // 右手始终不动
  if (stage === 0) {
    armL(b, 6, 12, 9, 17);                        // 抬起来
  } else if (stage === 1) {
    armL(b, 5, 10, 8, 16);
    set(b, 6, 11, P.spirit); set(b, 6, 12, P.spirit);          // 手上聚起灵光
  } else if (stage === 2) {
    armL(b, 4, 15, 8, 20);                        // 推出去
    set(b, 5, 16, P.spirit); set(b, 5, 17, P.spirit); set(b, 6, 16, P.spiritLight);
  } else {
    armL(b, ARM_X0, ARM_Y0, ARM_X1, ARM_Y1);      // 收势
  }
  playerFeet(b, "stand");            // ⭐ M30.5b：动作帧也要有脚（袍摆收短后不画就悬空了）
  outline(b, P.ink);
  const f2 = mk(); shadow(f2, 8); blit(f2, b); return f2;
};

// 结印 6 帧：起手 → 结印 → 换印 → 双手合拢 → 推出 → 收势。
// ⭐ 「一连串动作」的关键是**每一帧的手位都不同**，而且节奏要走「慢起、快推、缓收」。
const playerCombo = (stage) => {
  const b = mk();
  playerTorso(b); mirror(b);
  if (stage === 0) {                                  // 起手：双手抬到胸前
    armL(b, 8, 13, 11, 17); armR(b, 8, 13, 11, 17);
  } else if (stage === 1) {                           // 左手先结
    armL(b, 10, 14, 13, 18); armR(b, 8, 13, 11, 17);
  } else if (stage === 2) {                           // 换右手
    armL(b, 8, 13, 11, 17); armR(b, 10, 14, 13, 18);
  } else if (stage === 3) {                           // 双手合拢，掌心起光
    armL(b, 11, 15, 14, 19); armR(b, 11, 15, 14, 19);
    set(b, 14, 16, P.spirit); set(b, 17, 16, P.spirit);
  } else if (stage === 4) {                           // 推出 + 强光
    armL(b, 5, 16, 9, 20); armR(b, 5, 16, 9, 20);
    set(b, 6, 17, P.spirit); set(b, 6, 18, P.spirit); set(b, 7, 17, P.spiritLight);
    set(b, 25, 17, P.spirit); set(b, 25, 18, P.spirit); set(b, 24, 17, P.spiritLight);
  } else {                                            // 收势
    armL(b, ARM_X0, ARM_Y0, ARM_X1, ARM_Y1); armR(b, ARM_X0, ARM_Y0, ARM_X1, ARM_Y1);
  }
  playerFeet(b, "stand");                             // ⭐ M30.5b
  outline(b, P.ink);
  const f2 = mk(); shadow(f2, 8); blit(f2, b); return f2;
};

// 普攻 3 帧：抬手 → 挥出（带一道弧光）→ 收势。
const playerAttack = (stage) => {
  const b = mk();
  playerTorso(b); mirror(b);
  armR(b, ARM_X0, ARM_Y0, ARM_X1, ARM_Y1);            // 右手持械不动
  if (stage === 0) {
    armL(b, 5, 12, 9, 17);                            // 抬手
  } else if (stage === 1) {
    armL(b, 3, 16, 8, 21);                            // 挥出
    for (let i = 0; i < 6; i++) set(b, 2 + i, 15 + i, P.robeDark);   // 弧光
  } else {
    armL(b, ARM_X0, ARM_Y0, ARM_X1, ARM_Y1);          // 收势
  }
  playerFeet(b, "stand");                             // ⭐ M30.5b
  outline(b, P.ink);
  const f2 = mk(); shadow(f2, 8); blit(f2, b); return f2;
};

const sprites = {
  // ⛔ 主角（18 帧）**已移到 `gen_player.mjs`（48×48）**。
  //    为什么挪走：48 的画布才画得下五官与衣褶；而敌人/假人仍然 32×32。
  //    ⚠️ 别再在这里加 player_* —— 这里跑一次会把 48×48 的图**覆盖回 32×32**。
  // 假人：木桩 + 横木 + 靶心。训练场的道具，不参与形象语言。
  dummy: () => {
    const b = mk();
    rectL(b, 12, 12, 15, 29, P.stone);
    rectL(b, 10, 11, 15, 13, P.stone);
    set(b, 14, 12, P.target); set(b, 13, 12, P.target); set(b, 14, 11, P.target); set(b, 13, 11, P.target);
    rectL(b, 11, 27, 13, 29, P.stoneDark);
    mirror(b); outline(b, P.stoneDark);
    const f = mk(); shadow(f, 9); blit(f, b); return f;
  },
  // ---- 四个敌人：**外轮廓分别读作 圆 / 菱 / 方 / 三角**（ShapeData.SHAPES）----
  // ⭐ 路线②下贴图要接住的，正是形状语言原来承担的那件事：远看糊成一片也分得清是谁。
  //    所以先定轮廓、再往里面填细节；反过来做就会变成「四坨差不多的红蓝紫」。

  // 猛兽 melee → 圆：圆滚滚的兽身，耳朵收在圆里
  enemy_beast: () => {
    const b = mk();
    ellL(b, 15.5, 20, 10, 9.5, P.beast);       // 主体就是那个圆
    ellL(b, 15.5, 25, 9.5, 4.5, P.beastDark);  // 腹下暗部
    ellL(b, 10.5, 11, 3, 3, P.beastDark);      // 耳（贴着圆顶，不破坏轮廓）
    ellL(b, 10.5, 11, 1.6, 1.6, P.beastInk);
    rectL(b, 11, 18, 13, 20, P.eyeY);          // 眼
    rectL(b, 13, 24, 15, 25, P.beastInk);      // 嘴
    mirror(b); outline(b, P.beastInk);
    const f = mk(); shadow(f, 10); blit(f, b); return f;
  },

  // 灵师 caster → 菱：上尖（冠）下尖（袍角），最宽处在中段
  enemy_caster: () => {
    const b = mk();
    taperL(b, 3, 29, 17, 10.5, P.cast);        // 菱形外轮廓（画到 29：描边会补出第 30 行）
    taperL(b, 20, 29, 29, 6.5, P.castInk);     // 下摆压深（仍是尖的）
    ellL(b, 15.5, 12, 3.8, 3.2, P.castLight);  // 头
    set(b, 13, 12, P.castInk); set(b, 12, 12, P.castInk);
    for (let x = 12; x < 16; x++) set(b, x, 6, P.castGlow);   // 光环压在尖顶下
    mirror(b); outline(b, P.castInk);
    const f = mk(); shadow(f, 9); blit(f, b); return f;
  },

  // 智谋 hunter → 方：头身同宽，整体就是一个方块（兜帽不再尖）
  enemy_hunter: () => {
    const b = mk();
    rectL(b, 5, 12, 15, 29, P.hunt);           // 躯干
    rectL(b, 5, 3, 15, 12, P.huntDark);        // 头：和躯干同宽 —— 轮廓才是方的
    rectL(b, 11, 7, 13, 9, P.eyeP);            // 眼
    rectL(b, 5, 24, 15, 29, P.huntInk);        // 下摆压深
    mirror(b); outline(b, P.huntInk);
    const f = mk(); shadow(f, 10); blit(f, b); return f;
  },

  // 蛮兽 charger → 三角：顶点在上、底边在下，斜坡 = 冲刺感
  enemy_charger: () => {
    const b = mk();
    taperL(b, 4, 29, 29, 11.5, P.charge);      // 三角外轮廓
    rectL(b, 8, 20, 15, 21, P.chargeDark);     // 甲片分节
    rectL(b, 5, 26, 15, 27, P.chargeDark);
    ellL(b, 15.5, 24, 5, 4, P.chargeDark);     // 低着的头
    rectL(b, 11, 23, 13, 25, P.eyeY);          // 眼
    mirror(b); outline(b, P.chargeInk);
    const f = mk(); shadow(f, 11); blit(f, b); return f;
  },
};

// ---- PNG 编码：纯 Node，不依赖任何库（也就能在任何机器上重跑）----
const TBL = (() => { const t = new Int32Array(256); for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; t[n] = c; } return t; })();
const crc32 = (buf) => { let c = -1; for (let i = 0; i < buf.length; i++) c = TBL[(c ^ buf[i]) & 0xFF] ^ (c >>> 8); return (c ^ -1) >>> 0; };
const chunk = (type, data) => {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length, 0);
  const body = Buffer.concat([Buffer.from(type, "ascii"), Buffer.from(data)]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(body), 0);
  return Buffer.concat([len, body, crc]);
};
const encodePNG = (rgba, w, h) => {
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) { raw[y * (w * 4 + 1)] = 0; Buffer.from(rgba.buffer, y * w * 4, w * 4).copy(raw, y * (w * 4 + 1) + 1); }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 6;
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", ihdr), chunk("IDAT", zlib.deflateSync(raw, { level: 9 })), chunk("IEND", new Uint8Array(0))]);
};

// ---- 生成 ----
fs.mkdirSync(outDir, { recursive: true });
const made = {};
for (const [name, make] of Object.entries(sprites)) {
  const rgba = make();
  made[name] = rgba;
  fs.writeFileSync(path.join(outDir, name + ".png"), encodePNG(rgba, W, H));
  let opaque = 0, foot = -1;
  for (let i = 3; i < rgba.length; i += 4) if (rgba[i] > 0) opaque++;
  for (let y = H - 1; y >= 0 && foot < 0; y--) for (let x = 0; x < W; x++) if (rgba[(y * W + x) * 4 + 3] > 200) { foot = y; break; }
  console.log(name.padEnd(14), "不透明", String(opaque).padStart(4), "/1024  脚底 y=" + foot);
}

// ---- 预览图：6 倍最近邻放大，**8 张一行** —— 帧一多，横排成一条就什么都看不清了 ----
const K = 6, COLS = 8;
const names = Object.keys(made);
const cw = W * K, ch = H * K, rows = Math.ceil(names.length / COLS);
const pw = cw * COLS, ph = ch * rows;
const prev = new Uint8Array(pw * ph * 4);
names.forEach((n, idx) => {
  const src = made[n];
  const ox = (idx % COLS) * cw, oy = Math.floor(idx / COLS) * ch;
  for (let y = 0; y < ch; y++) for (let x = 0; x < cw; x++) {
    const sx = Math.floor(x / K), sy = Math.floor(y / K);
    const si = (sy * W + sx) * 4, di = ((oy + y) * pw + (ox + x)) * 4;
    prev[di] = src[si]; prev[di + 1] = src[si + 1]; prev[di + 2] = src[si + 2]; prev[di + 3] = src[si + 3];
  }
});
const prevPath = path.join(here, "preview_units.png");
fs.writeFileSync(prevPath, encodePNG(prev, pw, ph));
console.log("预览图:", prevPath, pw + "x" + ph);
