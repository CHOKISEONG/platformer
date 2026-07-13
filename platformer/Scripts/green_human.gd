extends Area2D

# 초록 인간 NPC. 플레이어와 같은 실루엣이지만 충돌체가 없어 몸을 뚫고 지나갈 수 있다.
# - 초록(cling) 플레이어가 닿으면: 잠깐 껴안아 붙잡았다가 위로 3블럭 높이로 띄워 준다
# - 다른 색 플레이어는 양옆으로 그냥 지나가고, 위에서 밟으면(낙하 중 머리 접촉)
#   화난 표정으로 바뀌며 플레이어를 1블럭 높이로 튕겨 낸다
# 플레이어 쪽 훅은 player_color.gd의 hold()/launch() — 덕 타이핑으로 호출한다.

# 몸 색 — 플레이어 GREEN(0.32, 0.78, 0.36)보다 어두운 초록. 둘 다 초록일 때 구분되도록
const BODY_COLOR = Color(0.2, 0.55, 0.28)

const HUG_TIME = 0.6 # 껴안고 있는 시간(초) — "잠깐"의 길이
const ANGRY_TIME = 2.0 # 밟힌 뒤 화난 표정이 풀리기까지의 시간(초)

# 띄운 직후 재포옹 금지 시간. 발사 초속 208px/s면 이 시간 안에 겹침 범위(반 칸)를
# 확실히 벗어나므로, 같은 접촉으로 곧바로 다시 안기는 일이 없다
const HUG_COOLDOWN = 0.3

# 띄우기/튕기기 세기 — 플레이어 jumpPower와 같은 단위 (launch가 jump와 같은 공식을 쓴다)
const LAUNCH_POWER = 26 # 3블럭(48px) 띄우기 — RED 점프와 같은 수치, 4블럭은 못 넘는다
const BOUNCE_POWER = 17 # 1블럭(16px) 튕기기 — BLUE 점프와 같은 수치, 2블럭은 못 넘는다

# 밟기 판정: 낙하 중이고 몸 중심이 이보다 위에 있으면(로컬 y) 머리를 밟은 것으로 본다.
# 옆에서 걸어서 지나갈 때는 중심 높이가 비슷해 이 값에 못 미친다
const STOMP_HEIGHT = -6.0

@onready var sprite = $Sprite
@onready var face = $Face
@onready var light = $Light

var hugTimer = 0.0
var angryTimer = 0.0
var cooldownTimer = 0.0
var huggedPlayer = null

func _ready():

	sprite.material.set_shader_parameter("tint", BODY_COLOR)
	sprite.play("idle")

	# 어두운 맵에서도 보이도록 은은한 초록 빛 (과일과 같은 이유, fruit.gd 참고)
	light.color = ColorPlayer.STATS[ColorPlayer.ColorState.GREEN].color

func _physics_process(delta):

	cooldownTimer = maxf(cooldownTimer - delta, 0.0)

	# 껴안는 중 — 시간이 다 되면 위로 띄운다
	if huggedPlayer != null:

		hugTimer -= delta

		if hugTimer <= 0.0:
			releaseHug()

		return

	if angryTimer > 0.0:

		angryTimer = maxf(angryTimer - delta, 0.0)

		if angryTimer == 0.0:
			face.setMood(face.Mood.NORMAL)

	# 플레이어 쪽을 바라본다 (lava.gd처럼 매 프레임 그룹 조회)
	var player = get_tree().get_first_node_in_group("player")

	if player != null:
		sprite.flip_h = player.global_position.x < global_position.x

	if cooldownTimer > 0.0:
		return

	for body in get_overlapping_bodies():

		if !body.has_method("hasAbility"): # ColorPlayer만 반응 (덕 타이핑)
			continue

		if body.hasAbility("cling"): # 초록 상태 — 닿기만 하면 어느 방향이든 껴안는다
			startHug(body)
		elif isStomp(body):
			stomp(body)

		break

# 포옹: 플레이어를 품으로 끌어와 붙잡고, HUG_TIME 뒤에 releaseHug에서 띄운다

func startHug(player):

	huggedPlayer = player
	hugTimer = HUG_TIME
	angryTimer = 0.0
	face.setMood(face.Mood.HUG)

	# hold의 여유분 0.2s는 안전장치 — 정상 경로에서는 releaseHug의 launch가 먼저 풀어 준다
	player.hold(HUG_TIME + 0.2)
	player.global_position = global_position + Vector2(0, -2) # 살짝 들어 올린 품 위치
	player.reset_physics_interpolation() # 순간이동이 잔상처럼 보간되지 않도록

func releaseHug():

	# heldTimer가 남아 있어야 아직 품에 있는 것 — 도중에 죽어 부활했다면 띄우지 않는다
	if is_instance_valid(huggedPlayer) and huggedPlayer.heldTimer > 0.0:
		huggedPlayer.launch(LAUNCH_POWER)

	huggedPlayer = null
	cooldownTimer = HUG_COOLDOWN
	face.setMood(face.Mood.NORMAL)

# 밟기: 위에서 떨어져 머리에 닿은 다른 색 플레이어를 튕겨 내고 화를 낸다

func isStomp(player):

	return player.gravity > 0 and player.global_position.y < global_position.y + STOMP_HEIGHT

func stomp(player):

	player.launch(BOUNCE_POWER)
	angryTimer = ANGRY_TIME
	face.setMood(face.Mood.ANGRY)
