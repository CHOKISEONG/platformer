class_name Water
extends Area2D

# 닿으면 플레이어가 사망하는 물. 한 칸(16px) 단위로 배치한다.
# 수위(Level)에 따라 이미지와 사망 판정 영역이 달라진다.
# freeze 능력(BLUE) 플레이어가 닿으면 상하좌우로 연결된 물 전체가 한 번에 얼음이 된다
# — 사망 판정이 꺼지고 밟을 수 있다.
# 플레이어가 죽으면 call_group("water", "unfreeze")로 다시 물이 된다 (player_color.gd).

enum Level { FULL, HIGH, LOW }

# 수위별 이미지 / 사망 판정 영역 / 얼음 바닥 영역 (셀 중심 기준 로컬 좌표).
# 사망 판정은 물결 수면보다 1~2px 아래부터 시작해 살짝 관대하게 잡고,
# 얼음 바닥은 반대로 눈에 보이는 수면 높이까지 채워 그 위에 설 수 있게 한다.
const LEVELS = {
	Level.FULL: {
		"texture": preload("res://water/water.png"),
		"rect": Rect2(-8, -7, 16, 15),
		"solidRect": Rect2(-8, -8, 16, 16), # 셀 전체 — 위아래로 쌓인 얼음과 이음새가 없도록
	},
	Level.HIGH: {
		"texture": preload("res://water/water_top.png"),
		"rect": Rect2(-8, -5, 16, 13), # 물결 수면(-8 ~ -6) 바로 아래부터
		"solidRect": Rect2(-8, -6, 16, 14), # 얼음 표면 = 물결 바로 아래 수면 높이
	},
	Level.LOW: {
		"texture": preload("res://water/water_top_low.png"),
		"rect": Rect2(-8, 2, 16, 6), # 셀 아래쪽 절반의 물부터
		"solidRect": Rect2(-8, 2, 16, 6),
	},
}

# 얼음 색: 텍스처 모양은 그대로 두고 밝기만 끌어올린다.
# 1을 넘긴 채널이 클램프되며 채도가 옅어져 얼음처럼 하얗게 보인다.
const ICE_TINT = Color(1.8, 1.8, 1.8)

# 얼리기 판정을 사망 판정보다 이만큼(px) 사방으로 크게 잡는다 —
# 파란색이 사망 판정에 잠기기 전에, 스치기만 해도 먼저 얼릴 수 있다
const FREEZE_MARGIN = 2.0

# 셀 한 칸 크기 px — 연결된 물 탐색에 사용 (맵 에디터의 셀 크기와 같다)
const CELL_SIZE = 16.0

@export var waterLevel: Level = Level.FULL

@onready var sprite = $Sprite
@onready var collision = $Collision
@onready var solidCollision = $SolidBody/SolidCollision
@onready var freezeCollision = $FreezeArea/FreezeCollision

var frozen = false

func _ready():

	var info = LEVELS[waterLevel]

	sprite.texture = info.texture

	var shape = RectangleShape2D.new()
	shape.size = info.rect.size

	collision.shape = shape
	collision.position = info.rect.get_center()

	var solidShape = RectangleShape2D.new()
	solidShape.size = info.solidRect.size

	solidCollision.shape = solidShape
	solidCollision.position = info.solidRect.get_center()

	var freezeShape = RectangleShape2D.new()
	freezeShape.size = info.rect.size + Vector2(FREEZE_MARGIN, FREEZE_MARGIN) * 2

	freezeCollision.shape = freezeShape
	freezeCollision.position = info.rect.get_center()

func _on_body_entered(body):

	if body.has_method("hasAbility") and body.hasAbility("freeze"):
		freezeConnected()
	elif body.has_method("die"):
		body.die()

# 얼리기 전용 판정 — 사망 판정보다 FREEZE_MARGIN만큼 커서 물에 잠기기 전에 먼저 얼린다

func _on_freeze_area_body_entered(body):

	if frozen:
		return

	if body.has_method("hasAbility") and body.hasAbility("freeze"):
		freezeConnected()

# 연결된 물 전체 얼리기: 그룹의 물을 셀 좌표로 색인한 뒤 상하좌우로 BFS 전파한다

func freezeConnected():

	var waterByCell = {}
	for water in get_tree().get_nodes_in_group("water"):
		waterByCell[cellOf(water)] = water

	var queue = [cellOf(self)]
	var visited = {}

	while queue:
		var cell = queue.pop_back()

		if visited.has(cell) or !waterByCell.has(cell):
			continue

		visited[cell] = true
		waterByCell[cell].freeze()

		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			queue.push_back(cell + direction)

func cellOf(water):

	return Vector2i((water.global_position / CELL_SIZE).floor())

# 얼음 전환 — 물리 콜백(body_entered) 중에 호출되므로 충돌 변경은 set_deferred로 미룬다

func freeze():

	if frozen:
		return

	frozen = true
	sprite.modulate = ICE_TINT
	collision.set_deferred("disabled", true) # 사망 판정 끄기
	solidCollision.set_deferred("disabled", false) # 밟을 수 있는 바닥 켜기

func unfreeze():

	if !frozen:
		return

	frozen = false
	sprite.modulate = Color.WHITE
	collision.set_deferred("disabled", false)
	solidCollision.set_deferred("disabled", true)
