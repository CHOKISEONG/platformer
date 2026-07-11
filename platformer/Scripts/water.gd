class_name Water
extends Area2D

# 닿으면 플레이어가 사망하는 물. 한 칸(16px) 단위로 배치한다.
# 수위(Level)에 따라 이미지와 사망 판정 영역이 달라진다.

enum Level { FULL, HIGH, LOW }

# 수위별 이미지 / 사망 판정 영역 (셀 중심 기준 로컬 좌표).
# 판정은 물결 수면보다 1~2px 아래부터 시작해 살짝 관대하게 잡는다.
const LEVELS = {
	Level.FULL: {
		"texture": preload("res://water/water.png"),
		"rect": Rect2(-8, -7, 16, 15),
	},
	Level.HIGH: {
		"texture": preload("res://water/water_top.png"),
		"rect": Rect2(-8, -5, 16, 13), # 물결 수면(-8 ~ -6) 바로 아래부터
	},
	Level.LOW: {
		"texture": preload("res://water/water_top_low.png"),
		"rect": Rect2(-8, 2, 16, 6), # 셀 아래쪽 절반의 물부터
	},
}

@export var waterLevel: Level = Level.FULL

@onready var sprite = $Sprite
@onready var collision = $Collision

func _ready():

	var info = LEVELS[waterLevel]

	sprite.texture = info.texture

	var shape = RectangleShape2D.new()
	shape.size = info.rect.size

	collision.shape = shape
	collision.position = info.rect.get_center()

func _on_body_entered(body):

	if body.has_method("die"):
		body.die()
