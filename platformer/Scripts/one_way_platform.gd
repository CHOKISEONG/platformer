class_name OneWayPlatform
extends StaticBody2D

# 칸 '사이' 경계선을 중심으로 위·아래 2px씩 걸치는 총 4px 두께의 원웨이 발판.
# 충돌체는 위·아래 2px 영역에 하나씩 있고 역할이 다르다:
#
# - 하단 2px(현재 칸의 상단, Collision): 원웨이 착지 판정(one_way_collision, 씬에서 설정).
#   아래에서 점프하면 통과하고 위에서는 밟고 선다. 윗면이 경계선과 일치해
#   옆 칸 타일 윗면과 단차 없이 걸어서 건너갈 수 있다
# - 상단 2px(윗 칸의 하단, ClingCollision): 매달림 전용 천장. 평소에는 꺼져 있다가
#   플레이어가 매달린 채 머리 높이로 지나는 동안만 양방향 충돌로 켜진다.
#   밑면이 경계선과 일치해 옆 칸 천장 타일 밑면과 단차 없이 이어지므로,
#   윗 칸이 비어 있어도 천장 판정(플레이어의 위쪽 test_move 프로브)이 끊기지 않아 매달림이 유지된다
#   (발판 폭 16px를 건너는 데 CLING_GRACE_TIME 0.05s로는 모자라 떨어지던 버그의 수정)
#
# 상태 판별은 매 프레임 플레이어를 확인한다 (lava.gd와 같은 방식):
#
# - 매달림(clinging) + 몸 중심이 경계선 아래 = 머리 높이 통과 —
#   하단 원웨이를 끄고(발끝·머리가 걸리지 않게) 상단 천장을 켠다(매달림 유지)
# - 매달림 + 몸 중심이 경계선 위 = 윗 칸을 발끝 높이로 통과 — 둘 다 끈다.
#   상단 천장이 이때 켜져 있으면 발끝이 걸리므로 머리 높이일 때만 켜는 것
# - 비매달림 + 몸 중심이 경계선 아래 = 아래에서 접근/상승 — 하단 원웨이도 꺼서
#   원웨이 오판(경계선 스침을 착지로 인식)까지 막는다. 매달림 접촉이 이음새에서
#   순간 끊긴 프레임에도 이 조건이 남아 있어 통과가 보장된다
# - 비매달림 + 몸 중심이 경계선 위 = 서 있거나 낙하 — 하단 원웨이만 켜진 기본 상태
#
# 매달림이 풀릴 때(천장 끝·상태 변화) 발판과 겹쳐 있어도: 상단 천장은 즉시 꺼지고
# 하단은 원웨이라 튕기지 않는다. 발판 바로 위에서 풀리면 그대로 착지한다

# 충돌 영역 (셀 중심 기준 로컬 좌표). 얇지만 move_and_slide가 이동 경로를
# 스윕으로 검사해 빠른 낙하에도 뚫리지 않는다
const SOLID_RECT = Rect2(-8, -8, 16, 2) # 하단: 원웨이 착지 판정
const CLING_RECT = Rect2(-8, -10, 16, 2) # 상단: 매달림 전용 천장

# 경계선(= 하단 윗면 = 상단 밑면 = 배치 칸 위쪽 가장자리)의 로컬 y
const BOUNDARY_Y = -8.0

@onready var collision = $Collision
@onready var clingCollision = $ClingCollision

func _ready():

	var solidShape = RectangleShape2D.new()
	solidShape.size = SOLID_RECT.size

	collision.shape = solidShape
	collision.position = SOLID_RECT.get_center()

	var clingShape = RectangleShape2D.new()
	clingShape.size = CLING_RECT.size

	clingCollision.shape = clingShape
	clingCollision.position = CLING_RECT.get_center()

func _physics_process(_delta):

	# clinging이 없는 노드(템플릿 플레이어 등)에서는 get이 null을 돌려줘 일반 원웨이로 동작한다
	var player = get_tree().get_first_node_in_group("player")

	if player == null:
		collision.disabled = false
		clingCollision.disabled = true
		return

	var clinging = player.get("clinging") == true
	var headLevel = to_local(player.global_position).y > BOUNDARY_Y # 몸 중심이 경계선 아래

	collision.disabled = clinging or headLevel
	clingCollision.disabled = !(clinging and headLevel)
