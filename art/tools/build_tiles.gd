## ⭐ M32：**地表瓦片构建脚本** —— 把美术的「分层件」合成成「MATCH_SIDES 成品」，
##    并做 256 → 128 → 64 的两步高质量降采样。
##
## 跑法（本机）：
##   "C:/Users/Administrator/Desktop/gu_tools/Godot_v4.7.2-stable_win64_console.exe" \
##     --headless --path "C:/Users/Administrator/Desktop/yunling" --script res://art/tiles/build_tiles.gd 2>/dev/null
##     ⚠️ 若路径写成 res://art/tools/build_tiles.gd 会命中同名文件解析失败，用 --path 的绝对路径更稳。
##
## 参数（全部可选）：
##   --src=<dir>      分层件母版目录（默认 res://art/tiles/src）
##   --out=<dir>      产物目录（默认 res://art/tiles/built）
##   --bleed=<px>     源图外扩像素（默认 4 = atlas 上 1px @4x；0 = 关闭）
##   --step2=<mode>   第二步重采样：lanczos（默认）/ trilinear
##   --terrain=<NAME> 只构建一个地形（可重复给）
##   --phase=<n>      **自动生成边带相位变体**：由 1 张母版沿边循环平移出 n 个变体（默认 1 = 不生成）
##   --selfcheck      用内置合成母版跑管线自检（**美术件没到位时的唯一可用模式**）
##
## ⚠️⚠️ 两条纪律：
##   ① **绝不回写 `src/`** —— 256 母版是唯一真相，产物一律进 `built/`。
##   ② 产物是 PNG，**跑完必须手动 `--import`**，否则 Godot 不重新导入、地形全读 0
##      （项目踩过一次，碎了 12 条自测断言）。
##
## ⭐ bleed（2026 定稿，**这一节全部是实测推出来的，改前先看下面的实测记录**）
##
## 实测 1：**不透明件的边缘会被采成 0**（不是 clamp-to-edge）。
##   真·无缝底块（6px 墨线横跨左右边界）单独降采样：左列 0.035，而源墨线 0.071、底块 0.447
##   ⇒ 边缘被额外拉暗约一半。原因：4× 降采样时最外侧目标像素的卷积核有一半落在画布外，
##      引擎按 **0（黑）** 采样，不是按边缘像素 clamp。
##   ⇒ 所以「底块严格无缝就不需要 bleed」是**错的**，底块同样需要 bleed。
##
## 实测 2：**均匀区域看不出这个 bug** —— 采到 0 后权重也被归一化掉了（实测四外圈-内部 = -0.0044，
##   在噪声内）。所以只有**边缘有内容**的件才会露馅，这正是最难发现的一类缺陷。
##
## 实测 3：bleed 的**取源必须是「对边」不是「对侧中心」**。
##   第一版我用 `+S/2` 取中心内容，实测把跨边界的墨线洗成了纯底色（0.447）——
##   无缝件的正确延续是**对边**（x=0 的外面是 x=S-1），不是正对面的中心。
##
## ⚠️ 两套模式不能共用：
##   - **wrap bleed（不透明 / 无缝件，如 BASE）**：外扩区填**对边**内容
##   - **clamp bleed（带 alpha 件，如 BAND/CORNER）**：外扩区填**最近的有效内容**
##
## ⭐ N 取多少：Lanczos 在 4× 下的核支撑 ≈ **12 源px**，一半落在画布外 ≈ 6；取 **8** 留余量。
##   （甄塑之建议 ≥6，实测 6 已够，8 更稳 —— 代价只是降采样慢一点。）
##
## ⭐ 两种实现，几何不同：
##   - `wrap`（默认）：原尺寸原地环绕填充，**缩放比 = 4 精确**，只是环绕内容可能与实际邻格不符
##   - `crop`（--bleedmode=crop）：先外扩画布 → 降采样 → 裁回 64。
##     缩放比 = (256+2N)/64（N=8 → 4.0625），**有极轻微重采样**，但环绕内容总是真实邻格内容
##     优点：**无论内容是否紧贴外缘都成立**，不要求画布内留透明环
##
## 合成规则（与美术约定，改这里等于改合同）：
##   底块 → 边带（掩码包含的边）→ 角件（**两条相邻边都在**才叠该角，角件在最上层）
##   掩码位：bit0=N(上) bit1=E(右) bit2=S(下) bit3=W(左)，与现有 `Game._auto_tile()` 一致。
##
## ⭐ 变体规则（2026 定稿，避免笛卡尔积爆炸）：
##   ① BASE 变体**只作用于 mask=0**（内部格，占屏面积 90%+）
##   ② 带边格一律只用 BASE_01（边格本身已有边带变化，再乘 base 变体组合数会失控）
##   ③ BAND 相位变体：同一掩码的**四条边用同一个变体号**（不做每边独立，否则 4^4 爆炸）
##   ⇒ 每地形张数 = n_base（仅 mask0） + 15 × n_band，不是笛卡尔积。
##   ④ 变体如何落到格子上：**构建期按格坐标哈希选定，写死进 atlas 的 alternative id**，
##      运行时绝不改格（项目红线：`set_cell`/`update_internals` 不得出现在 `_process`/`_draw*`）。
##
extends SceneTree

const SRC := 256
const MID := 128
const DST := 64

const TERRAINS := ["GRASS", "FOREST", "ROCK", "FIELD", "MARSH", "WATER"]
const SIDES := ["N", "E", "S", "W"]
const CORNERS := ["NE", "SE", "SW", "NW"]

var _src_dir := "res://art/tiles/src"
var _out_dir := "res://art/tiles/built"
var _bleed := 8
var _bleed_crop := true
var _step2 := Image.INTERPOLATE_LANCZOS
var _only: Array = []
var _selfcheck := false
var _phase := 1

# ---------------------------------------------------------------- 入口

func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--src="):
			_src_dir = a.substr(6)
		elif a.begins_with("--out="):
			_out_dir = a.substr(6)
		elif a.begins_with("--bleed="):
			_bleed = int(a.substr(8))
		elif a == "--bleedmode=crop":
			_bleed_crop = true
		elif a.begins_with("--step2="):
			_step2 = Image.INTERPOLATE_TRILINEAR if a.substr(8) == "trilinear" else Image.INTERPOLATE_LANCZOS
		elif a.begins_with("--terrain="):
			_only.append(a.substr(10))
		elif a.begins_with("--phase="):
			_phase = maxi(1, int(a.substr(8)))
		elif a == "--selfcheck":
			_selfcheck = true


func _initialize() -> void:
	_parse_args()
	print("---- build_tiles ----")
	print("  src  = ", _src_dir)
	print("  out  = ", _out_dir)
	print("  bleed= ", _bleed, " 源px（", "crop" if _bleed_crop else "wrap", "）   第二步= ",
			"trilinear" if _step2 == Image.INTERPOLATE_TRILINEAR else "lanczos", "   相位变体= ", _phase)
	var out_abs := ProjectSettings.globalize_path(_out_dir)
	DirAccess.make_dir_recursive_absolute(out_abs)
	if _selfcheck:
		_run_selfcheck(out_abs)
		quit()
		return
	var src_abs := ProjectSettings.globalize_path(_src_dir)
	if not DirAccess.dir_exists_absolute(src_abs):
		print("  ⚠️ 源目录不存在（美术还没交件）→ 自动转自检模式")
		_run_selfcheck(out_abs)
		quit()
		return
	var manifest := {}
	for t in TERRAINS:
		if not _only.is_empty() and not _only.has(t):
			continue
		var built := _build_terrain(t, src_abs, out_abs)
		if built.is_empty():
			print("  ⏭️  ", t, " 无件，跳过")
			continue
		manifest[t] = built
	_write_manifest(manifest, out_abs)
	print("---- 完成 ----")
	quit()


func _list_png(dir: String) -> Dictionary:
	var d := {}
	for f in DirAccess.get_files_at(dir):
		d[f] = true
	return d

# ---------------------------------------------------------------- 构建

func _build_terrain(t: String, src_abs: String, out_abs: String) -> Array:
	var bases := _load_variants(src_abs, "TIL_%s_BASE_%%02d.png" % t)
	if bases.is_empty():
		return []
	var bands: Dictionary = {}
	var corners: Dictionary = {}
	for s in SIDES:
		var v := _load_variants(src_abs, "TIL_%s_BAND_%s_%%02d.png" % [t, s])
		if not v.is_empty():
			bands[s] = v
	for c in CORNERS:
		var v := _load_variants(src_abs, "TIL_%s_CORNER_%s_%%02d.png" % [t, c])
		if not v.is_empty():
			corners[c] = v
	var n_band: int = (bands.values()[0] as Array).size() if not bands.is_empty() else 1
	print("  ▶ ", t, "  底块 ", bases.size(), " / 边带 ", bands.size(), " 向 × ", n_band, " / 角件 ", corners.size())
	for s in bands:
		_check_band_along_edge_seamless(t, s, (bands[s] as Array)[0])
		_check_band_corner_empty(t, s, (bands[s] as Array)[0])
		## ⭐ 周期性检查必须在**相位展开之前**：母版若有 64/128 的周期子结构，
		##    平移后得到的分段会和母版雷同 ⇒ 4 个变体退化成 2 个（甄塑之提的失效模式）。
		_check_band_no_period(t, s, (bands[s] as Array)[0])
	## ⭐ BAND 只取中段：角区强制清空（硬规矩第 4 条，脚本侧兜底）。
	##    ⚠️ 上面已经对"角区有内容"点了名，这里仍然清 —— 因为双重压暗是**隐蔽**缺陷，
	##       而裁剪导致的露空是**显性**缺陷，宁可要显性的（team-lead 裁定）。
	for s in bands:
		bands[s] = (bands[s] as Array).map(func(im): return _crop_band_corners(im, s))
	## ⭐ 相位变体：由 1 张母版**沿边循环平移**自动生成，美术不必手画 4 张。
	##    ⚠️ 依赖「沿边方向无缝」（周期 256 源px），已在上面校验。
	if _phase > 1:
		for s in bands:
			var arr: Array = bands[s]
			if arr.size() >= _phase:
				continue
			var master: Image = arr[0]
			var horizontal: bool = (s == "N" or s == "S")
			for k in range(1, _phase):
				arr.append(_shift_wrap(master, SRC * k / _phase, horizontal))
	## ⚠️ 相位展开后**必须重算** n_band —— 第一版漏了这行，n_band 停在展开前的 1，
	##    结果 bv 取到 1..3 而 arr 只有 1 个元素 → 运行时报 "Invalid access of index '3'"。
	n_band = (bands.values()[0] as Array).size() if not bands.is_empty() else 1
	var out := []
	for m in range(16):
		var name := _mask_name(m)
		var bv_list: Array = [0]
		if m == 0:
			bv_list = []
			for i in range(bases.size()):
				bv_list.append(i)
		elif not bands.is_empty():
			bv_list = []
			var nb: int = (bands.values()[0] as Array).size()
			for i in range(nb):
				bv_list.append(i)
		for bv in bv_list:
			## ⭐ 变体规则②：带边格**一律只用 BASE_01** —— bv 在带边掩码下是「边带相位号」，
			##    不是 base 变体号。第一版写成 `bases[bv]`，phase=4 时 bv=3 而 BASE 只有 3 张
			##    → 运行时 "Invalid access of index '3'"。
			var im: Image = (bases[bv] if m == 0 else bases[0]).duplicate()
			im.convert(Image.FORMAT_RGBA8)
			## ⚠️ bleed 必须**逐件**做、且在做合成之前：
			##    合成产物是不透明无缝块（底块托底），整图没有 alpha → 再 bleed 就是空转
			##    （这一版之前就是这么写的，实测 bleed 4 / 0 数值完全一样，属实无效）。
			for i in range(4):
				if (m & (1 << i)) != 0 and bands.has(SIDES[i]):
					var arr2: Array = bands[SIDES[i]]
					im.blend_rect(_bleed_wrap(arr2[bv % arr2.size()], _bleed), Rect2i(0, 0, SRC, SRC), Vector2i(0, 0))
			for i in range(4):
				var a := i
				var b := (i + 1) % 4
				if (m & (1 << a)) != 0 and (m & (1 << b)) != 0 and corners.has(CORNERS[i]):
					var arr3: Array = corners[CORNERS[i]]
					im.blend_rect(_bleed_wrap(arr3[0], _bleed), Rect2i(0, 0, SRC, SRC), Vector2i(0, 0))
			var d := _downsample_2step(im)
			var fn := "TIL_%s_M%02d_V%02d.png" % [t, m, bv]
			var fp := _join(out_abs, fn)
			var err := d.save_png(fp)
			if err != OK:
				push_error("[build_tiles] 写盘失败: " + fp)
			_verify(fp)
			_probe("%s M%02d V%02d" % [t, m, bv], d)
			out.append({"mask": m, "variant": bv, "file": fn, "base_variant": bv if m == 0 else 0})
	print("    → ", t, " 共 ", out.size(), " 张（mask0 用 ", bases.size(),
			" 个 base 变体；其余 15 个掩码各 ", n_band, " 个边带变体）")
	return out


## 读一组变体件：`TIL_<T>_BASE_01.png / 02 / 03 …`，**缺 01 就当这族不存在**。
## ⚠️ 变体号统一放**最后一段**（team-lead 定的命名），好处是脚本用同一个模式吃三种件。
## ⭐ 索引语义 = **母版槽位**，不是变体槽位：
##    目前从 01 递增读、读到断号停（所以他交 1 个或 4 个变体脚本都认，不用改脚本）。
##    将来若要加**第二张母版**，约定用 **_05**（第三张 _09，间隔 4）——
##    那时脚本应把每个已存在的索引当作**母版**、各自再展开出后续 3 个相位
##    （即 _05 生成 _06.._08）。**这段路没堵死**，但本轮不需要实现。
func _load_variants(src_abs: String, pattern: String) -> Array:
	var arr := []
	for i in range(1, 100):
		var p := _join(src_abs, pattern % i)
		if not FileAccess.file_exists(p):
			break
		var im := _load(p)
		if im == null:
			print("    ⚠️ 存在但读不出: ", p)
			break
		arr.append(im)
	return arr


## 沿边方向**循环平移**（wrap）：把母版沿边方向挪 off 个源像素，接不上的从另一头补。
## 这就是美术说的「相位偏移法」—— 笔法/光向/墨线完全一致，只有纹样相位不同。
func _shift_wrap(im: Image, off: int, horizontal: bool) -> Image:
	var out_img := Image.create(SRC, SRC, false, Image.FORMAT_RGBA8)
	var S := SRC
	for x in range(S):
		for y in range(S):
			var sx: int = (x - off) % S if horizontal else x
			var sy: int = y if horizontal else (y - off) % S
			if sx < 0:
				sx += S
			if sy < 0:
				sy += S
			out_img.set_pixel(x, y, im.get_pixel(sx, sy))
	return out_img


## ⭐ 输入校验 1：**BAND 沿边方向必须无缝**（周期 256 源px）。
##    仅仅「垂直边界方向无缝」不够 —— 一条长直边界上每 64 屏幕 px 断一次，比重复本身更显眼；
##    更要紧的是相位偏移变体（沿边循环平移）**全靠沿边周期性才成立**，母版不周期则变体全废。
##    N/S 查「最右列 ↔ 最左列」，E/W 查「最下行 ↔ 最上行」。
func _check_band_along_edge_seamless(t: String, s: String, im: Image) -> void:
	var horizontal: bool = (s == "N" or s == "S")
	var bad := 0.0
	var S := im.get_width()
	for i in range(S):
		var a: Color
		var b: Color
		if horizontal:
			a = im.get_pixel(S - 1, i)
			b = im.get_pixel(0, i)
		else:
			a = im.get_pixel(i, S - 1)
			b = im.get_pixel(i, 0)
		bad = maxf(bad, absf(a.a - b.a))
		if a.a > 0.01 or b.a > 0.01:
			bad = maxf(bad, (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0)
	if bad > 0.08:
		push_warning("[build_tiles] %s_BAND_%s **沿边方向不无缝**（接缝差 %.3f）→ 相位变体会废 + 长边界会断，请美术返修"
				% [t, s, bad])
	else:
		print("    BAND_", s, " 沿边无缝 ✓（接缝差 ", "%.3f" % bad, "）")


## ⭐ 输入校验 2：**BAND 的角区必须是空的**（硬规矩第 4 条）。
##    因果（team-lead 要求写进代码，别只写在文档里）：
##    BAND 与 CORNER 都是带 alpha 的半透明件，若 BAND 也覆盖角区 → 两件叠加两次
##    ⇒ **双重压暗，角上出现一块比别处深的补丁**。
##    ⇒ 这条同时是「不要放点状元素」的机械保证：角区空了，点状元素自然进不来。
func _check_band_corner_empty(t: String, s: String, im: Image) -> void:
	var S := im.get_width()
	var n := 64
	var bad := 0.0
	var horizontal: bool = (s == "N" or s == "S")
	for x in range(S):
		for y in range(S):
			var in_end: bool = (x < n or x >= S - n) if horizontal else (y < n or y >= S - n)
			if in_end:
				bad = maxf(bad, im.get_pixel(x, y).a)
	if bad > 0.01:
		push_warning("[build_tiles] %s_BAND_%s **角区有内容**（最大 alpha %.2f）→ 与 CORNER 叠加会双重压暗；脚本已强制清空，请美术回去改源图"
				% [t, s, bad])
	else:
		print("    BAND_", s, " 角区空 ✓")


## BAND 只保留中段：**沿边方向的两个端头各 64 源px 清空**，让 CORNER 去填。
##    ⚠️ 第一版写成「四个角区全清」，结果把整条边带抹没了（自检上边亮度从墨线 0.051
##       退回底块 0.452）。正确做法是**只清该边自己的两个端头**。
## ⭐ 输入校验 3：**母版不得含 64 / 128 源px 的周期子结构**（甄塑之提的失效模式）。
##    因为 `--phase` 的平移间距是**固定 64**；若母版本身有 64 或 128 周期，
##    平移后得到的分段会与母版高度相似甚至雷同 ⇒ **4 个变体退化成 2 个，等于没做变体**。
##    做法：算「沿边平移 d 后的差异」与「随机位移后的差异」之比（自相关的粗糙替身）——
##    越接近 0 说明越有周期性。比肉眼并排比对可靠。
func _check_band_no_period(t: String, s: String, im: Image) -> void:
	var horizontal: bool = (s == "N" or s == "S")
	var S := im.get_width()
	var base_diff := 0.0
	var n := 0
	for i in range(0, S, 4):
		for j in range(0, S, 4):
			var a: Color = im.get_pixel(i, j)
			var b: Color
			if horizontal:
				b = im.get_pixel((i + 37) % S, j)     # 37 与 64/128 互质 → 当作"随机位移"基准
			else:
				b = im.get_pixel(i, (j + 37) % S)
			base_diff += absf(a.a - b.a) + (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0
			n += 1
	base_diff /= float(maxi(1, n))
	if base_diff < 0.001:
		return                                        # 几乎是空图，跳过
	for d in [64, 128]:
		var diff := 0.0
		var m := 0
		for i in range(0, S, 4):
			for j in range(0, S, 4):
				var a: Color = im.get_pixel(i, j)
				var b: Color
				if horizontal:
					b = im.get_pixel((i + d) % S, j)
				else:
					b = im.get_pixel(i, (j + d) % S)
				diff += absf(a.a - b.a) + (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0
				m += 1
		diff /= float(maxi(1, m))
		var ratio := diff / base_diff
		if ratio < 0.35:
			push_warning("[build_tiles] %s_BAND_%s 疑似含 **%d 源px 周期子结构**（差异比 %.2f）→ 相位变体会退化，请改母版主尺度"
					% [t, s, d, ratio])
		else:
			print("    BAND_", s, " 无 %d 周期性 ✓（差异比 %.2f）" % [d, ratio])


func _crop_band_corners(im: Image, s: String) -> Image:
	var o := im.duplicate()
	o.convert(Image.FORMAT_RGBA8)
	var S: int = o.get_width()
	var n := 64
	var horizontal: bool = (s == "N" or s == "S")
	for x in range(S):
		for y in range(S):
			var in_end: bool = (x < n or x >= S - n) if horizontal else (y < n or y >= S - n)
			if in_end:
				o.set_pixel(x, y, Color(0, 0, 0, 0))
	return o


func _mask_name(m: int) -> String:
	if m == 0:
		return "NONE"
	var s := ""
	for i in range(4):
		if (m & (1 << i)) != 0:
			s += SIDES[i]
	return s


# ---------------------------------------------------------------- 图像处理

func _load(abs_path: String) -> Image:
	if not FileAccess.file_exists(abs_path):
		return null
	var im := Image.load_from_file(abs_path)
	if im == null:
		return null
	if im.is_compressed():
		im.decompress()
	im.convert(Image.FORMAT_RGBA8)
	if im.get_width() != SRC or im.get_height() != SRC:
		push_warning("[build_tiles] 尺寸不是 %dx%d: %s" % [SRC, SRC, abs_path])
	return im


## ⭐ 两套 bleed，**模式由「有没有 alpha」自动选**：
##   - 不透明 / 无缝件（BASE）→ **wrap**：外扩区填**对边**内容（x=0 的外面是 x=S-1）
##   - 带 alpha 件（BAND/CORNER）→ **clamp**：外扩区填**最近的有效内容**
## ⚠️ 取源必须用对边，不能用 +S/2（实测会把跨边界的墨线洗成纯底色，见文件头实测 3）。
func _bleed_wrap(src_img: Image, n: int) -> Image:
	if n <= 0:
		return src_img
	var S := src_img.get_width()
	var padded := Image.create(S + 2 * n, S + 2 * n, false, Image.FORMAT_RGBA8)
	var seamless := not src_img.detect_alpha()
	for y in range(S + 2 * n):
		for x in range(S + 2 * n):
			var sx: int = x - n
			var sy: int = y - n
			if sx < 0 or sx >= S or sy < 0 or sy >= S:
				if seamless:
					sx = (sx + S) % S
					sy = (sy + S) % S
					if sx < 0:
						sx += S
					if sy < 0:
						sy += S
				else:
					sx = clampi(sx, 0, S - 1)
					sy = clampi(sy, 0, S - 1)
			padded.set_pixel(x, y, src_img.get_pixel(sx, sy))
	if not _bleed_crop:
		## wrap 模式：把外扩的那一圈**折回原尺寸**（对角一次到位），保持缩放比 = 4 精确。
		## ⚠️ 必须先整张 copy 再覆盖 —— 只写四条边的话，四个角区会留在 create() 的初始
		##    全 0（实测出现纯黑像素，自检「最暗」指标掉到 0.000）。
		var o := src_img.duplicate()
		o.convert(Image.FORMAT_RGBA8)
		for y in range(S):
			for x in range(S):
				var sx: int = x
				var sy: int = y
				if x < n:
					sx = S + x
				elif x >= S - n:
					sx = x - S
				if y < n:
					sy = S + y
				elif y >= S - n:
					sy = y - S
				o.set_pixel(x, y, padded.get_pixel(sx + n, sy + n))
		return o
	return padded


func _downsample_2step(src_img: Image) -> Image:
	var mid := src_img.duplicate()
	mid.resize(MID, MID, Image.INTERPOLATE_LANCZOS)
	var d := mid.duplicate()
	if _bleed_crop:
		## crop 模式：256+2N → 128 → 64+? → 裁回 64（把外扩区裁掉）
		var d2 := mid.duplicate()
		d2.resize(DST, DST, _step2)
		## ⭐ 偏移量必须按**外扩后的尺寸**算（(256+2N)/64），不能按 256/64。
		##    第一版写成 `DST*n/SRC`，N=8 时算出 2 而正确值是 34 → 裁错了位置，
		##    实测把底块裁出全黑像素（最暗 0.000）。
		var off := int(float(DST) * float(_bleed) / float(SRC + 2 * _bleed) + 0.5)
		var out_img := src_img.duplicate()
		out_img.convert(Image.FORMAT_RGBA8)
		out_img.resize(DST, DST, Image.INTERPOLATE_NEAREST)   ## 占位，下一步整块覆盖
		out_img.blit_rect(d2, Rect2i(off, off, DST, DST), Vector2i(0, 0))
		return out_img
	d.resize(DST, DST, _step2)
	return d


## ⭐ 落盘后**回读校验**：尺寸必须是 64×64，且能被 Godot 正常解码。
##    不校验的话，尺寸错/编码坏的图会一路静默带到 TileSet 里，很难查。
func _verify(abs_path: String) -> void:
	var im := Image.load_from_file(abs_path)
	if im == null:
		push_error("[build_tiles] 回读失败: " + abs_path)
		return
	if im.get_width() != DST or im.get_height() != DST:
		push_error("[build_tiles] 尺寸不是 %dx%d: %s" % [DST, DST, abs_path])


# ---------------------------------------------------------------- 自检探针

## 打印三个可判读的指标：**墨线是否糊 / 有无振铃 / 边带 bleed 是否生效**。
func _probe(tag: String, d: Image) -> void:
	var base_col := d.get_pixel(4, d.get_height() / 2)
	var base_l := (base_col.r + base_col.g + base_col.b) / 3.0
	var dark := 1.0
	var bright := 0.0
	var edge_a := 0.0
	var edge_l := 0.0
	var n_l := 0
	## ⚠️ 只量**上边中段**（x 在 25%~75%）：两端 64 源px 已被 BAND 裁剪清空（给 CORNER 让位），
	##    把端头算进来会把边带的墨线读数冲淡成底块色（实测误报过 0.452 vs 0.051）。
	for x in range(d.get_width() / 4, d.get_width() * 3 / 4):
		edge_a = maxf(edge_a, d.get_pixel(x, 0).a)
		var c0 := d.get_pixel(x, 0)
		edge_l += (c0.r + c0.g + c0.b) / 3.0
		n_l += 1
	edge_l /= float(maxi(1, n_l))
	for x2 in range(d.get_width()):
		for y in range(d.get_height()):
			var c := d.get_pixel(x2, y)
			var l := (c.r + c.g + c.b) / 3.0
			dark = minf(dark, l)
			## ⚠️ 过冲只在**纯底块区域**量（避开灵光点与墨线本身）。
			##    第一次写成了「整张/下半张」，结果把 16px 灵光点（故意的高光）
			##    当成振铃，实测误报 0.353 —— 判据本身必须先排除已知亮元素。
			if x2 < d.get_width() / 2 and y > d.get_height() * 3 / 4:
				bright = maxf(bright, l)
	print("    %-18s 底块=%.3f 最暗=%.3f 纯底区过冲=%.3f 上边α=%.2f 上边亮度=%.3f"
			% [tag, base_l, dark, bright - base_l, edge_a, edge_l])


func _join(dir: String, file: String) -> String:
	return (dir + "/" + file).replace("//", "/")


func _write_manifest(m: Dictionary, out_abs: String) -> void:
	var f := FileAccess.open(_join(out_abs, "manifest.json"), FileAccess.WRITE)
	if f == null:
		push_error("[build_tiles] manifest 写盘失败")
		return
	f.store_string(JSON.stringify(m, "  "))
	f.close()
	print("  manifest.json 已写（", m.size(), " 个地形）")


# ---------------------------------------------------------------- 自检母版（临时）

## ⭐ 美术的 54 件还没画 —— 用一张**已知墨线宽度**的合成母版先把管线跑通。
##    它同时是「墨线 5~6px / 最小元素 ≥16px」这组源图规范的**可执行验收件**：
##    若 6px 墨线降采样后糊掉，说明降采样链路不合格，不用等真图。
func _run_selfcheck(out_abs: String) -> void:
	print("  == 自检模式（内置合成母版）==")
	var b := Image.create(SRC, SRC, false, Image.FORMAT_RGBA8)
	b.fill(Color(0.40, 0.62, 0.34, 1.0))
	# 6px 墨线（横 + 竖）
	for x in range(SRC):
		for y in range(60, 66):
			b.set_pixel(x, y, Color(0.07, 0.06, 0.08, 1.0))
	for y in range(SRC):
		for x in range(140, 146):
			b.set_pixel(x, y, Color(0.07, 0.06, 0.08, 1.0))
	# 16px 最小元素（灵光点）
	for x in range(96, 112):
		for y in range(180, 196):
			b.set_pixel(x, y, Color(0.86, 0.90, 0.62, 1.0))
	# 边带 N：**只画沿边方向的中段**（x 在 64~192）—— 两端 64 源px 留给 CORNER。
	#   ⚠️ 这是硬规矩第 4 条要求的结构；自检母版必须同构，否则量出来的「上边亮度」会被
	#      脚本的端头清空逻辑冲淡（实测误报过 0.443 vs 0.051）。
	var band_n := Image.create(SRC, SRC, true, Image.FORMAT_RGBA8)
	for x in range(64, 192):
		for y in range(SRC):
			if y < 4:
				pass                      # 4px 安全环：全透明
			elif y < 12:
				band_n.set_pixel(x, y, Color(0.05, 0.05, 0.06, 1.0))
			elif y < 64:
				var k := 1.0 - float(y - 12) / 52.0
				band_n.set_pixel(x, y, Color(0.05, 0.05, 0.06, 0.72 * k))
	# 角件 NE：只填右上角 64×64 区（与 BAND 端头让出的位置严丝合缝）
	var corner_ne := Image.create(SRC, SRC, true, Image.FORMAT_RGBA8)
	for x in range(192, 256):
		for y in range(0, 64):
			corner_ne.set_pixel(x, y, Color(0.05, 0.05, 0.06, 0.85))
	var im := b.duplicate()
	im.convert(Image.FORMAT_RGBA8)
	im.blend_rect(_bleed_wrap(band_n, _bleed), Rect2i(0, 0, SRC, SRC), Vector2i(0, 0))
	im.blend_rect(_bleed_wrap(corner_ne, _bleed), Rect2i(0, 0, SRC, SRC), Vector2i(0, 0))
	var d := _downsample_2step(im)
	d.save_png(_join(out_abs, "_selftest_N_NE.png"))
	var d0 := _downsample_2step(b)
	d0.save_png(_join(out_abs, "_selftest_NONE.png"))
	_verify(_join(out_abs, "_selftest_N_NE.png"))
	_verify(_join(out_abs, "_selftest_NONE.png"))
	print("  256 母版：墨线 6px / 灵光点 16px / 边带墨边 8px（内侧留 4px 安全环）")
	_probe("NONE（纯底块）", d0)
	_probe("N+NE（带边带）", d)
	print("  判据：① 最暗 ≈0.05 → 墨线没被抹平（源图 0.07，压到 0.06 以上才算糊）")
	print("        ② 纯底区过冲 <0.06 → 无可见振铃")
	print("        ③ bleed 对照：同一母版跑 `--bleed=0`，**上边亮度**应有显著变差")
	print("           实测 4→0.051（墨线到位） / 0→0.357（灰边） —— 这一步不是可选项")
