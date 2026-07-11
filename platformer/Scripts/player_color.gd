class_name ColorPlayer
extends CharacterBody2D

# 과일을 먹어 상태가 바뀔 때마다 발신 (UI, 사운드 등에서 연결해서 사용)
signal stateChanged(newState)

# 색 상태. 새 과일을 추가하려면 여기에 항목을 추가하고 STATS에 수치를 넣으면 된다.
enum ColorState { DARK, RED, BLUE, GREEN }

# 상태별 실루엣 색 / 이동 수치 / 능력.
# 눈동자 색은 Eyes 노드가 따로 그리므로 여기 색과 무관하게 유지된다.
const STATS = {
	ColorState.DARK: {
		"color": Color(0.04, 0.04, 0.06), # 배경과 같은 색 — 어둠 속에서 보이지 않음
		"moveSpeed": 7,
		"jumpPower": 0,       # 점프 불가 — 걷기만 가능
		"ability": "",
	},
	ColorState.RED: {
		"color": Color(0.87, 0.22, 0.22),
		"moveSpeed": 10,
		"jumpPower": 26,      # 3블럭(48px) 점프 — 최고점 약 54px, 4블럭은 못 넘는다
		"ability": "",
	},
	ColorState.BLUE: {
		"color": Color(0.27, 0.52, 0.93),
		"moveSpeed": 10,
		"jumpPower": 13,      # 점프력 낮음
		"ability": "freeze",  # 물 얼리기 (추후 구현)
	},
	ColorState.GREEN: {
		"color": Color(0.32, 0.78, 0.36),
		"moveSpeed": 11,
		"jumpPower": 22,      # 2블럭(32px) 점프 — 최고점 약 38px, 3블럭은 못 넘는다
		"ability": "cling",   # 천장에 닿으면 매달린다 (applyCling)
	},
}

# 초록 상태 천장 밀착: 매달린 동안 천장 쪽으로 눌러주는 속도 px/s.
# 바닥 밀착(gravity = 10)과 대칭 — 접촉이 끊기지 않을 만큼만 누른다.
const CLING_PUSH = 10.0

# 수평 가감속 px/s² — lerp와 달리 목표 속도와 0에 정확히 도달해
# 서브픽셀 속도로 기어가는 구간이 없다
const WALK_ACCELERATION = 900.0

# 코요테 타임: 바닥에서 떨어진 뒤에도 이 시간(초) 안에는 점프가 된다.
# 블럭 모서리 끝에서의 극한 점프가 한 프레임 차이로 씹히지 않게 해준다.
const COYOTE_TIME = 0.1

# 점프 버퍼: 착지 직전에 미리 누른 점프 입력을 이 시간(초) 동안 기억했다가
# 착지하는 순간 바로 점프로 이어준다. 연타 없이도 착지-점프가 부드럽게 이어진다.
const JUMP_BUFFER_TIME = 0.1

# Public

@onready var sprite = $Sprite
@onready var eyes = $Eyes

@export var gravityPower = 10

# Private

var state = ColorState.DARK
var moveSpeed = 0
var jumpPower = 0

var moveInput = 0.0 # -1(왼쪽) ~ +1(오른쪽)
var walkSpeed = 0.0 # 현재 수평 속도 px/s
var gravity = 0
var clinging = false
var coyoteTimer = 0.0 # 남은 코요테 타임 — 바닥 위에서는 항상 가득 채워진다
var jumpBufferTimer = 0.0 # 남은 점프 버퍼 — 점프 키를 누른 순간 가득 채워진다

var initialPosition

# 사망 시 부활 지점 — 마지막으로 먹은 과일의 위치 (없으면 시작 지점)
var respawnPosition

# 낙사 판정 y 좌표 (맵 에디터가 맵 높이에 맞춰 조정한다)
var resetY = 200

# Methods

func _ready():

	initialPosition = position
	respawnPosition = initialPosition
	setState(ColorState.DARK)

func _physics_process(delta):

	# is_on_floor()는 지난 프레임 move_and_slide 결과 — 점프 판정 전에 갱신한다
	if is_on_floor():
		coyoteTimer = COYOTE_TIME
	else:
		coyoteTimer = maxf(coyoteTimer - delta, 0.0)

	jumpBufferTimer = maxf(jumpBufferTimer - delta, 0.0)

	applyControls()
	applyGravity()
	applyCling()
	applyAnimation()

	# Out of bounds

	if position.y > resetY:
		position = initialPosition
		reset_physics_interpolation() # 순간이동이 잔상처럼 보간되지 않도록

	# Apply movement

	walkSpeed = move_toward(walkSpeed, moveInput * moveSpeed * 10, WALK_ACCELERATION * delta)
	velocity = Vector2(walkSpeed, gravity)
	move_and_slide()

# State management

func setState(newState):

	state = newState
	moveSpeed = STATS[state].moveSpeed
	jumpPower = STATS[state].jumpPower
	clinging = false # 천장에 매달린 채 상태가 바뀌면 떨어진다
	sprite.material.set_shader_parameter("tint", STATS[state].color)
	eyes.setGlow(state == ColorState.DARK) # 어둠 상태에서만 눈이 빛난다

	stateChanged.emit(state)

func eatFruit(fruitState, fruitPosition = null):

	setState(fruitState)

	if fruitPosition != null:
		respawnPosition = fruitPosition

# 사망: 마지막으로 먹은 과일 위치에서 부활하고 먹었던 과일을 전부 되살린다.
# 부활 지점에 되살아난 과일은 곧바로 다시 먹게 되므로 그 색으로 돌아온다.

func die():

	position = respawnPosition
	walkSpeed = 0.0
	gravity = 0
	clinging = false
	coyoteTimer = 0.0
	jumpBufferTimer = 0.0

	reset_physics_interpolation() # 순간이동이 잔상처럼 보간되지 않도록

	get_tree().call_group("fruits", "respawn")

# 상태별 능력 발동 지점 (추후 구현)

func useAbility():

	match STATS[state].ability:
		"freeze":
			pass # TODO: 물 얼리기

# Controls

func applyControls():

	moveInput = Input.get_axis("left", "right")

	if moveInput < 0:
		sprite.flip_h = true
	elif moveInput > 0:
		sprite.flip_h = false

	if Input.is_action_just_pressed("jump"):
		jumpBufferTimer = JUMP_BUFFER_TIME

	# 바닥 위(코요테 타임 가득)이거나 모서리에서 떨어진 직후,
	# 버퍼에 점프 입력이 남아 있으면 점프 — 착지 직전에 누른 입력도 여기서 소화된다
	if jumpBufferTimer > 0.0 and jumpPower > 0 and coyoteTimer > 0.0:
		jump()

# Apply gravity and jumping

func applyGravity():

	gravity += gravityPower

	if gravity > 0 and is_on_floor():
		gravity = 10

	# 천장에 부딪히면 상승 속도만 끊는다 — 점프 정점(gravity 0)과 같은 상태가 되어
	# 이후 정점에서처럼 자연스럽게 가속 하강한다.
	# 하강 중에도 계속 0으로 리셋하면 천장에 붙어 미끄러지므로 상승 중에만 적용한다.
	if is_on_ceiling() and gravity < 0:
		gravity = 0

		# 초록 상태는 떨어지는 대신 천장에 매달린다.
		# 상승 중 충돌에서만 시작하므로, 놓은 직후(gravity >= 0) 다시 붙지 않는다.
		if STATS[state].ability == "cling":
			clinging = true

func jump():

	gravity = -jumpPower * 10
	coyoteTimer = 0.0 # 남은 시간으로 공중에서 한 번 더 점프하지 못하게
	jumpBufferTimer = 0.0 # 버퍼에 남은 입력으로 연속 점프하지 못하게

# 초록 상태 천장 밀착: 상승 중 천장에 닿으면 매달린다 (applyGravity에서 시작).
# 매달린 동안에도 좌우 이동은 그대로 가능해 천장을 타고 움직일 수 있다.
# 점프 키를 다시 누르거나 천장이 끝나 접촉이 사라지면
# 점프 정점에서 내려올 때와 같은 곡선(gravity 0부터 가속)으로 떨어진다.

func applyCling():

	if !clinging:
		return

	if STATS[state].ability != "cling" or Input.is_action_just_pressed("jump") or !is_on_ceiling():
		clinging = false # 이 시점 gravity는 0 — 정점에서 내려오는 곡선으로 하강
		return

	gravity = -CLING_PUSH

# Set animations

func applyAnimation():

	if is_on_floor():
		if abs(walkSpeed) > 60:
			sprite.play("walk")
		else:
			sprite.play("idle")
	else:
		sprite.play("jump")
