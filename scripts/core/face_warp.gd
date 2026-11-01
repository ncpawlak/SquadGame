class_name FaceWarp
extends RefCounted
## Face morph: moves anchor points on a baked head (eyes, brows, nose, mouth, head width) and returns a grid mesh whose
## texture coordinates follow the moving-least-squares warp. Port of tools/portraits/warp.py (control_points + mls_map),
## minus the ear sliders, with thinned rings so it is cheap enough to run per portrait.

const L_EYE := [33, 161, 159, 157, 133, 154, 145, 163]
const R_EYE := [362, 384, 386, 388, 263, 390, 374, 381]
const L_BROW := [70, 105, 107, 65, 53]
const R_BROW := [300, 334, 336, 295, 283]
const NOSE := [168, 6, 197, 195, 5, 4, 1, 98, 327, 129, 358, 48, 278, 2]
const NOSE_WIDE := [98, 327, 129, 358, 48, 278, 2, 1]
const MOUTH := [61, 91, 84, 314, 321, 291, 270, 267, 37, 40]
const OVAL := [10, 297, 284, 389, 454, 361, 397, 379, 400, 152, 176, 150, 172, 132, 234, 162, 54, 67]
const ALPHA := 1.2


## `head` is one entry of heads.json, `indices` the file's landmark index list. Returns an ArrayMesh in head-image pixels.
static func build_mesh(head: Dictionary, indices: Array, morph: Dictionary, flip: bool, gx: int, gy: int) -> ArrayMesh:
	var lm := {}
	var pts: Array = head["pts"]
	for i in indices.size():
		lm[int(indices[i])] = Vector2(pts[i][0], pts[i][1])
	var w := float(head["w"])
	var h := float(head["h"])
	var pq := _control_points(lm, head, morph, w, h)
	var src: PackedVector2Array = pq[0]
	var dst: PackedVector2Array = pq[1]
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for j in gy + 1:
		for i in gx + 1:
			var v := Vector2(w * i / gx, h * j / gy)
			var f := _source_pos(v, src, dst)
			verts.append(Vector2(w - v.x, v.y) if flip else v)
			uvs.append(Vector2(f.x / w, f.y / h))
	var idx := PackedInt32Array()
	for j in gy:
		for i in gx:
			var a := j * (gx + 1) + i
			var b := a + 1
			var c := a + gx + 1
			var d := c + 1
			idx.append_array([a, b, c, b, d, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _control_points(lm: Dictionary, head: Dictionary, p: Dictionary, w: float, h: float) -> Array:
	var fw: float = head["fw"]
	var top: float = head["brow_top"]
	var fh: float = lm[152].y - top
	var cx: float = lm[1].x
	var head_w: float = p.get("head_w", 0.0)
	var P := PackedVector2Array()
	var Q := PackedVector2Array()

	for side in [-1.0, 1.0]:
		# Eyes: spread, height, size.
		var ring: Array = L_EYE if side < 0.0 else R_EYE
		var c := _centroid(lm, ring)
		var sz: float = 1.0 + p.get("eye_size", 0.0)
		for i in ring:
			var s: Vector2 = lm[i]
			var d := c + (s - c) * sz + Vector2(side * p.get("eye_x", 0.0) * fw, p.get("eye_y", 0.0) * fh)
			P.append(s)
			Q.append(_head_x(d, cx, head_w))
		# Brows: height only (brow size is not a slider).
		for i in (L_BROW if side < 0.0 else R_BROW):
			var s: Vector2 = lm[i]
			P.append(s)
			Q.append(_head_x(s + Vector2(0.0, p.get("brow_y", 0.0) * fh), cx, head_w))
	# Nose: height and width.
	for i in NOSE:
		var s: Vector2 = lm[i]
		var d := s + Vector2(0.0, p.get("nose_y", 0.0) * fh)
		if NOSE_WIDE.has(i):
			d.x = cx + (s.x - cx) * (1.0 + p.get("nose_w", 0.0))
		P.append(s)
		Q.append(_head_x(d, cx, head_w))
	# Mouth: height, width, lip height.
	var mc := _centroid(lm, MOUTH)
	for i in MOUTH:
		var s: Vector2 = lm[i]
		var d := mc + Vector2((s.x - mc.x) * (1.0 + p.get("mouth_w", 0.0)), (s.y - mc.y) * (1.0 + p.get("mouth_len", 0.0)))
		d.y += p.get("mouth_y", 0.0) * fh
		P.append(s)
		Q.append(_head_x(d, cx, head_w))
	# Head outline, plus a wider ring of anchors so the hair follows the head width.
	var oc := _centroid(lm, OVAL)
	for i in OVAL:
		var s: Vector2 = lm[i]
		P.append(s)
		Q.append(_head_x(s, cx, head_w))
		var r := oc + (s - oc) * 1.3
		P.append(r)
		Q.append(_head_x(r, cx, head_w))
	# Ear and jaw pins: ears are not morphed, but they ride with the head width.
	var ec_y: float = (top + lm[2].y) / 2.0
	for side in [-1.0, 1.0]:
		var jaw: Vector2 = lm[234] if side < 0.0 else lm[454]
		var ex: float = jaw.x + side * 0.05 * fw
		for s in [Vector2(ex + side * 0.07 * fw, ec_y), Vector2(ex + side * 0.02 * fw, ec_y - 0.16 * fh),
				Vector2(ex + side * 0.02 * fw, ec_y + 0.16 * fh), jaw, jaw + Vector2(side * 0.02 * fw, -0.1 * fh)]:
			P.append(s)
			Q.append(_head_x(s, cx, head_w))
	# Pin the image border so the backdrop and jersey stay put.
	for k in 6:
		var x := w * k / 5.0
		for y in [0.0, h]:
			P.append(Vector2(x, y))
			Q.append(Vector2(x, y))
	for k in range(1, 5):
		var y := h * k / 5.0
		for x in [0.0, w]:
			P.append(Vector2(x, y))
			Q.append(Vector2(x, y))
	return [P, Q]


static func _head_x(pt: Vector2, cx: float, head_w: float) -> Vector2:
	return Vector2(cx + (pt.x - cx) * (1.0 + head_w), pt.y)


static func _centroid(lm: Dictionary, ring: Array) -> Vector2:
	var s := Vector2.ZERO
	for i in ring:
		s += lm[i]
	return s / ring.size()


## Where (in the source image) output point `v` samples from: affine moving least squares over the anchors.
static func _source_pos(v: Vector2, P: PackedVector2Array, Q: PackedVector2Array) -> Vector2:
	var n := P.size()
	var ws := PackedFloat32Array()
	ws.resize(n)
	var wsum := 0.0
	var qs := Vector2.ZERO
	var ps := Vector2.ZERO
	for k in n:
		var wk := 1.0 / pow(v.distance_squared_to(Q[k]) + 0.001, ALPHA)
		ws[k] = wk
		wsum += wk
		qs += Q[k] * wk
		ps += P[k] * wk
	qs /= wsum
	ps /= wsum
	var a00 := 1e-6
	var a01 := 0.0
	var a11 := 1e-6
	var b00 := 0.0
	var b01 := 0.0
	var b10 := 0.0
	var b11 := 0.0
	for k in n:
		var q: Vector2 = Q[k] - qs
		var pp: Vector2 = P[k] - ps
		var wk := ws[k]
		a00 += wk * q.x * q.x
		a01 += wk * q.x * q.y
		a11 += wk * q.y * q.y
		b00 += wk * q.x * pp.x
		b01 += wk * q.x * pp.y
		b10 += wk * q.y * pp.x
		b11 += wk * q.y * pp.y
	var det := a00 * a11 - a01 * a01
	if absf(det) < 1e-12:
		return v - qs + ps
	# M = A^-1 B for the symmetric 2x2 A.
	var m00 := (a11 * b00 - a01 * b10) / det
	var m01 := (a11 * b01 - a01 * b11) / det
	var m10 := (-a01 * b00 + a00 * b10) / det
	var m11 := (-a01 * b01 + a00 * b11) / det
	var d := v - qs
	return Vector2(d.x * m00 + d.y * m10, d.x * m01 + d.y * m11) + ps
