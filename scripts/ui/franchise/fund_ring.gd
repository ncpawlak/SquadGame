class_name FundRing
extends Control
## Club fund ring for the Facilities page (issue #73): the whole circle is the fund the club started the
## period with, each spent slice is drawn clockwise from 12 o'clock in its colour, and the unfilled track is
## what is left. The amount left is printed in the middle.

const WIDTH := 26.0
const TRACK := Color("#1a2640")

var total: float
## [[amount ($K), colour], ...] in draw order.
var slices: Array
var left: float
var _sweep := 1.0


func _init(fund_total: float, spent_slices: Array, fund_left: float, diameter := 240.0) -> void:
	total = fund_total
	slices = spent_slices
	left = fund_left
	custom_minimum_size = Vector2(diameter, diameter)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if total > 0.0 and not Fx.is_reduced() and Fx.memo("fund:%d:%d" % [roundi(total), roundi(left)], true) == null:
		_sweep = 0.0
		UiKit._when_ready(self, func():
			Fx.tween(self).tween_method(func(x: float):
				_sweep = x
				queue_redraw(), 0.0, 1.0, 0.9).set_delay(0.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT))


func _draw() -> void:
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0 - WIDTH / 2.0 - 2.0
	draw_arc(c, r, 0.0, TAU, 96, TRACK, WIDTH, true)
	var a := -PI / 2.0
	if total > 0.0:
		for s in slices:
			var sweep := TAU * clampf(float(s[0]) / total, 0.0, 1.0) * _sweep
			sweep = minf(sweep, -PI / 2.0 + TAU - a)
			if sweep <= 0.001:
				continue
			draw_arc(c, r, a, a + sweep, maxi(4, int(96.0 * sweep / TAU)), s[1], WIDTH, true)
			a += sweep
	UiKit.install_fonts()
	var big := UiKit.font_heavy
	var small := UiKit.font_display
	var amount := Contracts.money(roundi(left))
	var bs := 40
	var bw := big.get_string_size(amount, HORIZONTAL_ALIGNMENT_LEFT, -1, bs).x
	draw_string(big, Vector2(c.x - bw / 2.0, c.y + 8.0), amount, HORIZONTAL_ALIGNMENT_LEFT, -1, bs,
		UiKit.BAD if left < 0.0 else Color.WHITE)
	var sub := "LEFT OF %s" % Contracts.money(roundi(total))
	var sw := small.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	draw_string(small, Vector2(c.x - sw / 2.0, c.y + 34.0), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UiKit.MUTED)
	var head := "CLUB FUND"
	var hw := small.get_string_size(head, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
	draw_string(small, Vector2(c.x - hw / 2.0, c.y - 32.0), head, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, UiKit.MUTED)
