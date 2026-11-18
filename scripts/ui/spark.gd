class_name Spark
extends Control
## A row of small bars for the advisor's trend lines (buyers, profit, satisfaction by day).
## Bars below zero hang from the baseline in the loss colour; the last day is the brightest.

var values: Array[float] = []
var tint := Color("3f7a57")

func _init(series: Array[float] = [], color: Color = Color("3f7a57")) -> void:
	values = series
	tint = color
	custom_minimum_size = Vector2(170, 36)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	if values.is_empty():
		return
	var top := 0.0001
	var low := 0.0
	for v in values:
		top = maxf(top, v)
		low = minf(low, v)
	var span := top - low
	var zero := size.y * (top / span)
	var step := size.x / values.size()
	var width := maxf(2.0, step - 3.0)
	# In right-to-left layouts the newest day sits on the left, as the eye expects.
	var rtl := is_layout_rtl()
	for i in range(values.size()):
		var v := values[i]
		var h := absf(v) / span * size.y
		var slot := (values.size() - 1 - i) if rtl else i
		var rect := Rect2(slot * step + (step - width) * 0.5, zero - h if v >= 0.0 else zero, width, maxf(h, 1.5))
		var c := tint if v >= 0.0 else Color("c0513f")
		c.a = 1.0 if i == values.size() - 1 else 0.55
		draw_rect(rect, c)
	draw_line(Vector2(0, zero), Vector2(size.x, zero), Color(0, 0, 0, 0.18), 1.0)
