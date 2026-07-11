class_name ClingPlatform
extends StaticBody2D

# 칸 아래쪽에 붙는 가로로 얇은 원웨이 플랫폼.
# 평소에는 위에서만 밟히는 원웨이라 아래에서 점프하면 통과해 위로 올라갈 수 있다.
# 초록(cling) 플레이어가 천장에 매달린 동안에는 양방향 충돌로 바뀌어 밑면이 천장이 된다
# — 옆 천장에서 매달린 채 좌우로 끊김 없이 지나갈 수 있다.
# 단, 여기서 매달리기를 시작할 수는 없다: 아래에서 올라올 때는 원웨이라 천장 충돌 자체가 없다.

# 판정 영역 (셀 중심 기준 로컬 좌표) — 칸 아래쪽 4px.
# 상단 원웨이 타일(아틀라스 7,1)의 두께와 같고, 밑면이 셀 바닥과 같은 높이라
# 옆 벽 타일의 밑면과 이어져 매달려 건너갈 때 단차가 없다.
const RECT = Rect2(-8, 4, 16, 4)

@onready var collision = $Collision

func _ready():

	var shape = RectangleShape2D.new()
	shape.size = RECT.size

	collision.shape = shape
	collision.position = RECT.get_center()

func _physics_process(_delta):

	# 매달림 상태는 언제든 바뀌므로 매 프레임 확인한다 (lava.gd와 같은 방식).
	# clinging이 없는 노드(템플릿 플레이어 등)에서는 get이 null을 돌려줘 원웨이로 남는다
	var player = get_tree().get_first_node_in_group("player")

	collision.one_way_collision = !(player != null and player.get("clinging") == true)
