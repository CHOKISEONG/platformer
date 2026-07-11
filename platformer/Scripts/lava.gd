class_name Lava
extends Area2D

# 밟으면 사망하는 용암. 한 칸(16px) 단위로 배치한다 — 물(water.gd)과 같은 패턴.
# lavaWalk 능력(RED) 플레이어에게는 단단한 바닥이 되어 밟고 건널 수 있다.
# 얼음과 달리 남는 상태가 없다 — 플레이어 상태를 매 프레임 확인해 바닥/사망 판정을 전환하므로
# 밟은 채로 빨간색이 풀리면 바닥이 사라져 빠져 죽는다.

enum Level { FULL, HIGH, LOW }

# 수위별 이미지 / 사망 판정 영역 / 바닥 영역 (셀 중심 기준 로컬 좌표).
# 텍스처는 물 텍스처의 색상만 빨간색으로 돌린 것이라 판정 수치도 water.gd와 동일하다.
const LEVELS = {
	Level.FULL: {
		"texture": preload("res://lava/lava.png"),
		"rect": Rect2(-8, -7, 16, 15),
		"solidRect": Rect2(-8, -8, 16, 16), # 셀 전체 — 위아래로 쌓인 용암과 이음새가 없도록
	},
	Level.HIGH: {
		"texture": preload("res://lava/lava_top.png"),
		"rect": Rect2(-8, -5, 16, 13), # 물결 수면(-8 ~ -6) 바로 아래부터
		"solidRect": Rect2(-8, -6, 16, 14), # 바닥 표면 = 물결 바로 아래 수면 높이
	},
	Level.LOW: {
		"texture": preload("res://lava/lava_top_low.png"),
		"rect": Rect2(-8, 2, 16, 6), # 셀 아래쪽 절반부터
		"solidRect": Rect2(-8, 2, 16, 6),
	},
}

@export var lavaLevel: Level = Level.FULL

@onready var sprite = $Sprite
@onready var collision = $Collision
@onready var solidCollision = $SolidBody/SolidCollision

var walkable = false

func _ready():

	var info = LEVELS[lavaLevel]

	sprite.texture = info.texture

	var shape = RectangleShape2D.new()
	shape.size = info.rect.size

	collision.shape = shape
	collision.position = info.rect.get_center()

	var solidShape = RectangleShape2D.new()
	solidShape.size = info.solidRect.size

	solidCollision.shape = solidShape
	solidCollision.position = info.solidRect.get_center()

func _physics_process(_delta):

	# 플레이어 상태는 과일/부활로 언제든 바뀌므로 매 프레임 확인한다
	var player = get_tree().get_first_node_in_group("player")

	setWalkable(player != null and player.has_method("hasAbility") and player.hasAbility("lavaWalk"))

func setWalkable(value):

	if walkable == value:
		return

	walkable = value
	collision.disabled = value # 사망 판정 <-> 밟을 수 있는 바닥 전환
	solidCollision.disabled = !value

func _on_body_entered(body):

	if body.has_method("die"):
		body.die()
