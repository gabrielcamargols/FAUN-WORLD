extends Node3D

## Primeira cena: clareira na floresta. O menino (WASD / setas) está escondido
## atrás de uma moita. Quando ele chega perto, Brasatã percebe, se assusta
## e foge voando por cima das árvores.
## Placeholders: árvores, moita e chão são formas simples.

# Ordem das linhas nas folhas de sprite (8 direções, como vistas pela câmera):
# 0 frente, 1 frente-direita, 2 direita, 3 costas-direita,
# 4 costas, 5 costas-esquerda, 6 esquerda, 7 frente-esquerda.
# Cada entrada: [linha da folha, espelhar horizontalmente].
const BOY_ROWS := [[0, false], [1, false], [2, false], [3, false], [4, false], [5, false], [6, false], [7, false]]
# Na folha do Brasatã, a linha 1 olha para a esquerda (igual à linha 7),
# então a frente-direita usa a linha 7 espelhada.
const FAUN_ROWS := [[0, false], [7, true], [2, false], [3, false], [4, false], [5, false], [6, false], [7, false]]

const BOY_SPEED := 3.0
const BOY_CELL_UNITS := 1.6      # altura de uma célula de frame, em unidades do mundo
const BOY_BOUNDS := 8.0
const WALK_FPS := 8.0

const FAUN_CELL_UNITS := 2.4
const FAUN_WANDER_SPEED := 0.8
const FAUN_FLY_SPEED := 6.5
const FAUN_CLIMB_SPEED := 2.2
const FAUN_FLY_FPS := 10.0
const FAUN_STARTLE_TIME := 0.7   # pausa assustado antes de levantar voo
const DETECT_RADIUS := 4.5
const FAUN_DESPAWN_DISTANCE := 18.0

enum FaunState { WANDER, STARTLED, FLYING }

var boy: Sprite3D
var faun: Sprite3D
var boy_walk_tex: Texture2D
var boy_idle_tex: Texture2D
var faun_walk_tex: Texture2D
var faun_fly_tex: Texture2D

var boy_walking := false
var boy_dir := 0
var boy_anim := 0.0

var faun_state := FaunState.WANDER
var faun_dir := 0
var faun_anim := 0.0
var faun_timer := 0.0
var faun_home := Vector3(-2.0, 0.0, -3.0)  # longe o bastante para não detectar o menino no início
var faun_target := Vector3.ZERO
var faun_flee_dir := Vector3.ZERO
var faun_alert: Label3D


func _ready() -> void:
	boy_walk_tex = load("res://assets/sprites/boy_walk.png")
	boy_idle_tex = load("res://assets/sprites/boy_idle.png")
	faun_walk_tex = load("res://assets/sprites/brasata_walk.png")
	faun_fly_tex = load("res://assets/sprites/brasata_fly.png")

	_build_environment()
	_build_clearing()
	_build_bush()
	_build_camera()

	boy = _make_sprite()
	boy.position = Vector3(2.5, 0.0, 1.5)
	boy_dir = 4  # de costas para a câmera, espiando a clareira
	_set_boy_idle()

	faun = _make_sprite()
	faun.position = faun_home
	_apply_layout(faun, faun_walk_tex, 4, 8, FAUN_CELL_UNITS)
	_pick_wander_target()


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)  # evita saltos em quedas de FPS
	_update_boy(delta)
	_update_faun(delta)


# --- Menino --------------------------------------------------------------

func _update_boy(delta: float) -> void:
	var input := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if input.length() > 0.1:
		boy.position.x = clampf(boy.position.x + input.x * BOY_SPEED * delta, -BOY_BOUNDS, BOY_BOUNDS)
		boy.position.z = clampf(boy.position.z + input.y * BOY_SPEED * delta, -BOY_BOUNDS, BOY_BOUNDS)
		boy_dir = _dir_index(input.x, input.y)
		if not boy_walking:
			boy_walking = true
			_apply_layout(boy, boy_walk_tex, 4, 8, BOY_CELL_UNITS)
		boy_anim += delta * WALK_FPS
		_show_frame(boy, BOY_ROWS, boy_dir, int(boy_anim) % 4)
	elif boy_walking:
		_set_boy_idle()


func _set_boy_idle() -> void:
	boy_walking = false
	_apply_layout(boy, boy_idle_tex, 4, 2, BOY_CELL_UNITS)
	# A folha parada tem as 8 direções em sequência (4 por linha), sem espelhamento.
	boy.flip_h = false
	boy.frame = boy_dir


# --- Brasatã -------------------------------------------------------------

func _update_faun(delta: float) -> void:
	if faun == null:
		return

	if faun_state == FaunState.WANDER and _flat_distance(boy.position, faun.position) < DETECT_RADIUS:
		_startle()

	match faun_state:
		FaunState.WANDER:
			_faun_wander(delta)
		FaunState.STARTLED:
			faun_timer -= delta
			if faun_timer <= 0.0:
				_take_off()
		FaunState.FLYING:
			_faun_fly(delta)


func _faun_wander(delta: float) -> void:
	var to_target := faun_target - faun.position
	to_target.y = 0.0
	if to_target.length() < 0.1:
		faun_timer -= delta
		_show_frame(faun, FAUN_ROWS, faun_dir, 0)
		if faun_timer <= 0.0:
			_pick_wander_target()
		return
	var step := to_target.normalized() * FAUN_WANDER_SPEED * delta
	faun.position += step if step.length() < to_target.length() else to_target
	faun_dir = _dir_index(to_target.x, to_target.z)
	faun_anim += delta * WALK_FPS * 0.6
	_show_frame(faun, FAUN_ROWS, faun_dir, int(faun_anim) % 4)


func _pick_wander_target() -> void:
	var offset := Vector3(randf_range(-1.2, 1.2), 0.0, randf_range(-0.8, 0.8))
	faun_target = faun_home + offset
	faun_timer = randf_range(1.0, 2.5)  # tempo parado ao chegar


func _startle() -> void:
	faun_state = FaunState.STARTLED
	faun_timer = FAUN_STARTLE_TIME
	var to_boy := boy.position - faun.position
	faun_dir = _dir_index(to_boy.x, to_boy.z)  # vira para o menino
	_show_frame(faun, FAUN_ROWS, faun_dir, 0)
	_show_alert()


func _take_off() -> void:
	faun_state = FaunState.FLYING
	if faun_alert:
		faun_alert.queue_free()
		faun_alert = null
	faun_anim = 0.0
	faun_flee_dir = faun.position - boy.position
	faun_flee_dir.y = 0.0
	faun_flee_dir = faun_flee_dir.normalized()
	faun_dir = _dir_index(faun_flee_dir.x, faun_flee_dir.z)
	_apply_layout(faun, faun_fly_tex, 4, 8, FAUN_CELL_UNITS * 1.3)


func _faun_fly(delta: float) -> void:
	faun.position += faun_flee_dir * FAUN_FLY_SPEED * delta
	faun.position.y += FAUN_CLIMB_SPEED * delta
	faun_anim += delta * FAUN_FLY_FPS
	_show_frame(faun, FAUN_ROWS, faun_dir, int(faun_anim) % 4)
	if Vector2(faun.position.x, faun.position.z).length() > FAUN_DESPAWN_DISTANCE:
		faun.queue_free()
		faun = null


func _show_alert() -> void:
	var alert := Label3D.new()
	alert.text = "!"
	alert.font_size = 160
	alert.outline_size = 28
	alert.outline_modulate = Color(0.1, 0.05, 0.05)
	alert.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	alert.modulate = Color(1.0, 0.3, 0.2)
	alert.position = Vector3(0, FAUN_CELL_UNITS * 1.05, 0)
	alert.no_depth_test = true
	alert.render_priority = 10
	faun.add_child(alert)
	faun_alert = alert


# --- Sprites -------------------------------------------------------------

func _make_sprite() -> Sprite3D:
	var s := Sprite3D.new()
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	s.shaded = false
	add_child(s)
	return s


func _apply_layout(sprite: Sprite3D, tex: Texture2D, hframes: int, vframes: int, cell_units: float) -> void:
	sprite.texture = tex
	sprite.hframes = hframes
	sprite.vframes = vframes
	sprite.pixel_size = cell_units / (float(tex.get_height()) / vframes)
	sprite.offset.y = (float(tex.get_height()) / vframes) / 2.0  # pés no chão


func _show_frame(sprite: Sprite3D, rows: Array, dir: int, col: int) -> void:
	var entry: Array = rows[dir]
	sprite.flip_h = entry[1]
	sprite.frame = int(entry[0]) * sprite.hframes + col


## Converte um vetor no plano (x = direita da tela, y = em direção à câmera)
## no índice de direção 0..7 (0 = frente, 2 = direita, 4 = costas, 6 = esquerda).
func _dir_index(x: float, y: float) -> int:
	var angle := atan2(x, y)
	return posmod(roundi(angle / (PI / 4.0)), 8)


# --- Cenário -------------------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.45, 0.6, 0.5)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.7, 0.6)
	env.glow_enabled = true
	env.fog_enabled = true
	env.fog_light_color = Color(0.6, 0.7, 0.65)
	env.fog_density = 0.01

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.shadow_enabled = true
	add_child(sun)


func _build_clearing() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30, 30)
	ground.mesh = plane
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.28, 0.48, 0.22)
	ground.material_override = ground_mat
	add_child(ground)

	# Anel de árvores em volta da clareira (placeholders)
	var tree_count := 14
	for i in tree_count:
		var angle := TAU * i / tree_count
		var pos := Vector3(cos(angle) * 13.0, 2.0, sin(angle) * 13.0)

		var trunk := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.4
		cyl.bottom_radius = 0.5
		cyl.height = 4.0
		trunk.mesh = cyl
		var trunk_mat := StandardMaterial3D.new()
		trunk_mat.albedo_color = Color(0.35, 0.22, 0.12)
		trunk.material_override = trunk_mat
		trunk.position = pos
		add_child(trunk)

		var crown := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 2.2
		sphere.height = 4.4
		crown.mesh = sphere
		var crown_mat := StandardMaterial3D.new()
		crown_mat.albedo_color = Color(0.15, 0.4, 0.2)
		crown.material_override = crown_mat
		crown.position = pos + Vector3(0, 3.2, 0)
		add_child(crown)


func _build_bush() -> void:
	# Moita entre a câmera e o menino: ele fica escondido até sair de trás dela
	var bush := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 1.5
	sphere.height = 2.2
	bush.mesh = sphere
	var bush_mat := StandardMaterial3D.new()
	bush_mat.albedo_color = Color(0.12, 0.42, 0.18)
	bush.material_override = bush_mat
	bush.position = Vector3(2.2, 0.8, 3.2)
	add_child(bush)


func _build_camera() -> void:
	var cam := Camera3D.new()
	cam.fov = 40.0
	cam.position = Vector3(0, 7, 9.5)
	cam.rotation_degrees = Vector3(-34, 0, 0)
	add_child(cam)
	cam.current = true


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
