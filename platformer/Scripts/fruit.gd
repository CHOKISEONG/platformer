extends Area2D

# 먹으면 플레이어를 해당 색 상태로 바꾸는 보석.
# 이미지는 상태에 따라 자동으로 정해지므로
# 새로 배치할 때는 fruitState만 지정하면 된다.
# 먹혀도 삭제되지 않고 숨겨진다 — 플레이어가 사망하면 다시 나타난다.

@export var fruitState: ColorPlayer.ColorState = ColorPlayer.ColorState.RED

# 상태별 보석 이미지
const TEXTURES = {
	ColorPlayer.ColorState.RED: preload("res://extra_source/gem_red.png"),
	ColorPlayer.ColorState.BLUE: preload("res://extra_source/gem_blue.png"),
	ColorPlayer.ColorState.GREEN: preload("res://extra_source/gem_green.png"),
}

@onready var sprite = $Sprite

var time = 0.0
var eaten = false

func _ready():

	add_to_group("fruits")

	if TEXTURES.has(fruitState):
		sprite.texture = TEXTURES[fruitState]

	time = position.x * 0.05 # 보석마다 흔들림 위상을 다르게

func _process(delta):

	if eaten:
		return

	time += delta
	sprite.position.y = sin(time * 3) * 2
	sprite.scale = Vector2(0.25, 0.25) * (1.0 + sin(time * 5) * 0.08)

func _on_body_entered(body):

	if eaten:
		return

	if body.has_method("eatFruit"):

		body.eatFruit(fruitState, global_position)

		eaten = true
		visible = false
		set_deferred("monitoring", false)

# 플레이어 사망 시 "fruits" 그룹 호출로 되살아난다

func respawn():

	if !eaten:
		return

	eaten = false
	visible = true
	set_deferred("monitoring", true)
