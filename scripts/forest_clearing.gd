extends Node3D

## Primeira cena: clareira na floresta. O menino (WASD / setas) está escondido
## atrás de uma moita. Quando ele chega perto, Brasatã percebe, se assusta
## e foge voando por cima das árvores.
## No celular (ou com o mouse), segure o dedo na tela: o menino anda até aquele ponto.
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

var cam: Camera3D
var pointer_down := false
var pointer_pos := Vector2.ZERO
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


func _unhandled_input(event: InputEvent) -> void:
	# O toque na tela chega como mouse (emulação padrão do Godot).
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		pointer_down = event.pressed
		pointer_pos = event.position
	elif event is InputEventMouseMotion and pointer_down:
		pointer_pos = event.position


func _process(delta: float) -> void:
	delta = minf(delta, 0.05)  # evita saltos em quedas de FPS
	_update_boy(delta)
	_update_faun(delta)


# --- Menino --------------------------------------------------------------

func _update_boy(delta: float) -> void:
	var input := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if input.length() < 0.1 and pointer_down:
		input = _pointer_direction()
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


## Direção do menino até o ponto do chão sob o dedo/mouse (zero se já chegou).
func _pointer_direction() -> Vector2:
	var origin := cam.project_ray_origin(pointer_pos)
	var normal := cam.project_ray_normal(pointer_pos)
	if absf(normal.y) < 0.001:
		return Vector2.ZERO
	var hit := origin + normal * (-origin.y / normal.y)
	var to := Vector2(hit.x - boy.position.x, hit.z - boy.position.z)
	return to.normalized() if to.length() > 0.25 else Vector2.ZERO


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


# --- Cenário (estilo maquete de brinquedo) --------------------------------
# Cores quentes e terrosas, sombreamento de desenho (toon), contorno escuro
# grosso nas formas e um filtro de fita VHS por cima da tela.

const BG_CREAM := Color(0.93, 0.89, 0.8)
const OUTLINE_COLOR := Color(0.16, 0.11, 0.09)


## Material toon com contorno escuro (técnica do "casco invertido").
func _toon(color: Color, outline := 0.04) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.roughness = 1.0
	if outline > 0.0:
		var o := StandardMaterial3D.new()
		o.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		o.cull_mode = BaseMaterial3D.CULL_FRONT
		o.grow = true
		o.grow_amount = outline
		o.albedo_color = OUTLINE_COLOR
		m.next_pass = o
	return m


func _mesh(mesh: Mesh, mat: Material, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	add_child(mi)
	return mi


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BG_CREAM
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.95, 0.88, 0.78)
	env.ambient_light_energy = 0.45
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, -35, 0)
	sun.light_color = Color(1.0, 0.94, 0.84)
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.6
	sun.shadow_blur = 2.0
	add_child(sun)

	# Filtro VHS por cima de tudo
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/vhs.gdshader")
	rect.material = sm
	layer.add_child(rect)


func _build_clearing() -> void:
	# A clareira é uma "maquete": uma base grossa com grama por cima,
	# uma faixa de terra na lateral e uma borda decorada, como um tatame.
	var base_size := Vector3(22, 1.2, 18)
	_mesh(_box(base_size), _toon(Color(0.55, 0.38, 0.24), 0.05), Vector3(0, -0.6, 0))
	_mesh(_box(Vector3(base_size.x + 0.01, 0.08, base_size.z + 0.01)), _toon(Color(0.45, 0.5, 0.24), 0.0), Vector3(0, -0.04, 0))
	_mesh(_box(Vector3(17, 0.06, 13)), _toon(Color(0.66, 0.55, 0.34), 0.0), Vector3(0, -0.01, 0))  # terra clara da clareira
	# Faixa decorada na frente da base, como a borda de um tatame
	_mesh(_box(Vector3(base_size.x + 0.04, 0.35, 0.06)), _toon(Color(0.42, 0.47, 0.22), 0.0), Vector3(0, -0.45, base_size.z / 2.0 + 0.01))

	# Árvores roliças em volta: tronco curto e copa redonda de poucos polígonos
	var spots := [
		Vector3(-9, 0, -7), Vector3(-6, 0, -7.8), Vector3(-2.5, 0, -8), Vector3(1.5, 0, -7.6),
		Vector3(5, 0, -7.9), Vector3(8.5, 0, -7), Vector3(-9.5, 0, -3.5), Vector3(9.5, 0, -3.2),
		Vector3(-9.6, 0, 0.5), Vector3(9.7, 0, 1.0), Vector3(-9.2, 0, 4.5), Vector3(9.0, 0, 5.5),
	]
	var greens := [Color(0.32, 0.45, 0.2), Color(0.4, 0.5, 0.22), Color(0.28, 0.4, 0.2)]
	for i in spots.size():
		var p: Vector3 = spots[i]
		var trunk := CylinderMesh.new()
		trunk.top_radius = 0.28
		trunk.bottom_radius = 0.38
		trunk.height = 1.4
		trunk.radial_segments = 8
		_mesh(trunk, _toon(Color(0.5, 0.33, 0.2)), p + Vector3(0, 0.7, 0))
		var crown := SphereMesh.new()
		var r := 1.5 + (i % 3) * 0.25
		crown.radius = r
		crown.height = r * 1.8
		crown.radial_segments = 10
		crown.rings = 6
		_mesh(crown, _toon(greens[i % 3]), p + Vector3(0, 1.4 + r * 0.8, 0))


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _build_bush() -> void:
	# Moita entre a câmera e o menino: ele fica escondido até sair de trás dela.
	# Três bolas de folhas juntas, para ter cara de moita.
	var mat := _toon(Color(0.3, 0.45, 0.2))
	for b in [[Vector3(2.2, 0.75, 3.2), 1.1], [Vector3(1.3, 0.55, 3.4), 0.8], [Vector3(3.1, 0.55, 3.3), 0.85]]:
		var sphere := SphereMesh.new()
		sphere.radius = b[1]
		sphere.height = b[1] * 1.7
		sphere.radial_segments = 10
		sphere.rings = 6
		_mesh(sphere, mat, b[0])


func _build_camera() -> void:
	cam = Camera3D.new()
	cam.fov = 36.0
	cam.position = Vector3(0, 10, 15.5)
	cam.rotation_degrees = Vector3(-33, 0, 0)
	add_child(cam)
	cam.current = true


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
