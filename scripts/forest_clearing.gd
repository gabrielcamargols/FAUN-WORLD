extends Node3D

## Primeira cena: clareira na floresta. O menino (WASD / setas) está escondido
## atrás de uma moita. Quando ele chega perto, Brasatã percebe e foge.
## Placeholders: árvores, moita e alerta são formas simples.

const BOY_SPEED := 3.0
const FAUN_FLEE_SPEED := 6.0
const DETECT_RADIUS := 4.5
const BOY_CELL_UNITS := 1.1    # altura de uma célula de frame, em unidades do mundo
const FAUN_CELL_UNITS := 2.0
const WALK_FPS := 8.0
const BOY_BOUNDS := 8.0
const FAUN_DESPAWN_DISTANCE := 14.0

var boy: Sprite3D
var faun: Sprite3D
var boy_walk_tex: Texture2D
var boy_idle_tex: Texture2D
var boy_walking := false
var fleeing := false
var walk_time := 0.0


func _ready() -> void:
	boy_walk_tex = load("res://assets/sprites/boy_walk.png")
	boy_idle_tex = load("res://assets/sprites/boy_idle.png")
	var faun_tex: Texture2D = load("res://assets/sprites/brasata.png")

	_build_environment()
	_build_clearing()
	_build_bush()
	_build_camera()

	boy = Sprite3D.new()
	add_child(boy)
	_set_boy_idle()
	boy.position.x = 2.5
	boy.position.z = 1.5

	faun = Sprite3D.new()
	add_child(faun)
	_apply_layout(faun, faun_tex, 1, 1, FAUN_CELL_UNITS)
	faun.position.x = -1.0
	faun.position.z = -2.0


func _process(delta: float) -> void:
	_update_boy(delta)
	_update_faun(delta)


# --- Movimento do menino -------------------------------------------------

func _update_boy(delta: float) -> void:
	var input := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	if input.length() > 0.1:
		boy.position.x = clampf(boy.position.x + input.x * BOY_SPEED * delta, -BOY_BOUNDS, BOY_BOUNDS)
		boy.position.z = clampf(boy.position.z + input.y * BOY_SPEED * delta, -BOY_BOUNDS, BOY_BOUNDS)
		if not boy_walking:
			_set_boy_walk()
		walk_time += delta * WALK_FPS
		boy.frame = int(walk_time) % 4  # linha 0 = de frente; outras direções ainda não ligadas
	elif boy_walking:
		_set_boy_idle()


# --- Brasatã: percebe o menino e foge ------------------------------------

func _update_faun(delta: float) -> void:
	if faun == null:
		return
	if not fleeing and _flat_distance(boy.position, faun.position) < DETECT_RADIUS:
		fleeing = true
		_show_alert()

	if fleeing:
		var away := faun.position - boy.position
		away.y = 0.0
		away = away.normalized()
		faun.position += away * FAUN_FLEE_SPEED * delta
		if faun.position.length() > FAUN_DESPAWN_DISTANCE:
			faun.queue_free()
			faun = null


func _show_alert() -> void:
	var alert := Label3D.new()
	alert.text = "!"
	alert.font_size = 96
	alert.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	alert.modulate = Color(1.0, 0.3, 0.2)
	alert.position = Vector3(0, FAUN_CELL_UNITS + 0.4, 0)
	faun.add_child(alert)


# --- Sprites -------------------------------------------------------------

func _apply_layout(sprite: Sprite3D, tex: Texture2D, hframes: int, vframes: int, cell_units: float) -> void:
	sprite.texture = tex
	sprite.hframes = hframes
	sprite.vframes = vframes
	sprite.pixel_size = cell_units / (float(tex.get_height()) / vframes)
	sprite.position.y = cell_units / 2.0   # pés na altura do chão
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS


func _set_boy_idle() -> void:
	boy_walking = false
	_apply_layout(boy, boy_idle_tex, 4, 2, BOY_CELL_UNITS)
	boy.frame = 0


func _set_boy_walk() -> void:
	boy_walking = true
	_apply_layout(boy, boy_walk_tex, 4, 8, BOY_CELL_UNITS)


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
	ground_mat.albedo_color = Color(0.35, 0.6, 0.3)
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
	# Moita entre a câmera e o menino: ele fica escondido até entrar na frente dela
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
	cam.fov = 45.0
	cam.position = Vector3(0, 9, 11)
	cam.rotation_degrees = Vector3(-38, 0, 0)
	add_child(cam)
	cam.current = true


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
