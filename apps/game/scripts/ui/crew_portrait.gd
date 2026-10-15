class_name LFCrewPortrait
extends Control
## Any crew member drawn at any size: Home mascot, banner faces, win card, collection, previews.
## Animates only while `animate` is on (off for reduced motion / animations disabled), so a
## static portrait costs one draw.

signal tapped

var char_id := "naps"
var state := LFCrewAnim.IDLE
var expression := ""          # fixed expression instead of an animated state
var cosmetic := ""            # art key
var animate := true
var cycle: Array = []         # preview: states to loop through
var cycle_time := 1.3
var anim_seed := 0
var _t := 0.0
var _age := 0.0
var _ci := 0


static func make(id: String, px: float, p_animate := true) -> LFCrewPortrait:
	var p := LFCrewPortrait.new()
	p.char_id = id
	p.custom_minimum_size = Vector2(px, px)
	p.animate = p_animate
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


func _ready() -> void:
	set_process(animate or not cycle.is_empty())


func play_state(s: int) -> void:
	state = s
	expression = ""
	_age = 0.0
	queue_redraw()


func set_animate(on: bool) -> void:
	animate = on
	set_process(on or not cycle.is_empty())
	queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	_age += delta
	if not cycle.is_empty() and _age >= cycle_time:
		_ci = (_ci + 1) % cycle.size()
		state = int(cycle[_ci])
		_age = 0.0
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		tapped.emit()
		accept_event()


func _draw() -> void:
	var def := LFCrew.get_def(char_id)
	var kind := str(def.get("kind", "package"))
	var m := minf(size.x, size.y)
	var package := kind == "package"
	var sz := m * (0.6 if package else 0.82)
	var center := size / 2.0 + Vector2(0, sz * (0.08 if package else 0.0))
	var opts := {"motion": animate, "cosmetic": cosmetic, "seed": anim_seed}
	if expression != "":
		opts["expression"] = expression
	LFCrewPainter.draw_character(self, def, center, sz, state, _age, _t, opts)
