extends Node
## Locale helper: language switching, RTL flag and AED money formatting.

signal language_changed

const PREF_PATH := "user://lang.cfg"
var lang := "ar"

func _ready() -> void:
	var f := FileAccess.open(PREF_PATH, FileAccess.READ)
	if f:
		var saved := f.get_as_text().strip_edges()
		if saved in ["ar", "en"]:
			lang = saved
	TranslationServer.set_locale(lang)

func set_language(code: String) -> void:
	lang = code
	TranslationServer.set_locale(code)
	var f := FileAccess.open(PREF_PATH, FileAccess.WRITE)
	if f:
		f.store_string(code)
	language_changed.emit()

func toggle() -> void:
	set_language("en" if lang == "ar" else "ar")

func is_rtl() -> bool:
	return lang == "ar"

## "AED 25" / "25 د.إ"; decimals only when needed.
func money(v: float) -> String:
	var a := absf(v)
	var num := ("%d" % int(round(a))) if is_equal_approx(a, round(a)) else ("%.2f" % a)
	if v < -0.004:
		# U+200E keeps the minus glued to the digits inside right-to-left text
		return ("\u200e-%s د.إ" % num) if is_rtl() else ("-AED %s" % num)
	return ("%s د.إ" % num) if is_rtl() else ("AED %s" % num)

## Keeps a number-first string (e.g. "+10", "24-36", "10:00 - 22:00") in reading order inside RTL text.
func ltr(s: String) -> String:
	if not is_rtl():
		return s
	# a dash between two numbers is otherwise resolved right-to-left, so mark both sides
	return "\u200e" + s.replace(" - ", "\u200e - \u200e")
