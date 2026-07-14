extends Camera2D

# 룸 기반 스크린 스크롤 카메라.
# 맵을 ROOM_CELLS(20x15칸 = 320x240px) 격자로 나누고 카메라를 플레이어가 있는
# 룸의 중앙에 고정한다. 플레이어가 룸 경계를 넘으면 옆 룸으로 짧게 패닝한다.
# 화면(16:9)과 룸(4:3)의 비율이 달라 옆 룸이 비치는 좌우 여백은 검은 막대로 가린다.

# Public

# 룸 크기: 20x15칸(320x240px). 세로 15칸이 화면 높이를 꽉 채우도록 줌을 맞춘다
const ROOM_CELLS = Vector2i(20, 15)
const CELL = 16
const ROOM_SIZE = Vector2(ROOM_CELLS * CELL)

# 룸 전환 패닝 시간(초) — 전환 중에도 플레이어는 계속 움직이므로
# 너무 길면 플레이어가 화면 밖까지 나아간 채 조작하게 된다
# 0이면 패닝 없이 snapToRoom으로 즉시 컷 (보간 잔상도 끊는다)
const PAN_DURATION = 0.0

# 한 물리 프레임에 이 거리(px) 이상 움직이면 순간이동(사망·낙사 리셋)으로 보고
# 패닝 없이 즉시 새 룸으로 자른다. 최고 낙하·발사 속도도 프레임당 수 px 수준이라 안전
const TELEPORT_DISTANCE = 48.0

# 끄면 룸 스크롤 없이 씬에 설정된 대로 플레이어를 따라다닌다 (기존 카메라)
@export var roomScrolling = true

# 룸 격자의 왼쪽 위 원점. 격자에 맞춰 만들지 않은 맵에서 조정한다
# (시작 씬이 (-144, -128)을 쓴다 — 에디터 맵은 (0, 0) 기준이라 그대로 두면 된다)
@export var roomOrigin = Vector2.ZERO

# Private

var player # 부모 ColorPlayer
var currentRoom = Vector2i.ZERO
var panFrom = Vector2.ZERO # 패닝 시작 시점의 카메라 위치
var panTimer = 0.0 # 남은 패닝 시간 — 0이면 룸 중앙에 고정

# 순간이동 감지용 직전 프레임 플레이어 위치. 플레이어와 카메라가 서로를 모르는
# 결합 방식을 유지하려고 사망 시그널 대신 프레임당 이동 거리로 감지한다
var lastPlayerPosition = Vector2.ZERO

# Methods

func _ready():

	if !roomScrolling:
		set_physics_process(false)
		return

	player = get_parent()

	# 부모(플레이어)를 따라가지 않고 룸 좌표를 직접 지정한다
	top_level = true
	position_smoothing_enabled = false

	# 룸 세로(240px)가 화면 높이에 꼭 맞는 줌 — 1080 기준 4.5
	zoom = Vector2.ONE * (get_viewport_rect().size.y / ROOM_SIZE.y)

	buildSideBars()

	lastPlayerPosition = player.global_position
	currentRoom = roomAt(lastPlayerPosition)
	snapToRoom()

# 플레이어(부모)가 먼저 움직인 뒤에 실행되므로 이번 프레임 위치를 그대로 따라간다

func _physics_process(delta):

	var playerPosition = player.global_position
	var teleported = playerPosition.distance_to(lastPlayerPosition) > TELEPORT_DISTANCE
	lastPlayerPosition = playerPosition

	var room = roomAt(playerPosition)

	if room != currentRoom:
		currentRoom = room

		if teleported:
			snapToRoom() # 사망·리셋으로 다른 룸에 나타나면 맵을 가로질러 패닝하지 않는다
		elif PAN_DURATION > 0.0:
			panFrom = global_position # 패닝 도중 또 경계를 넘어도 현 위치에서 이어 간다
			panTimer = PAN_DURATION
		else:
			snapToRoom() # 패닝 시간이 0이면 물리 보간 잔상 없이 즉시 컷
	elif teleported:
		snapToRoom() # 같은 룸 안의 순간이동도 진행 중이던 패닝은 끊는다

	if panTimer > 0.0:
		panTimer = maxf(panTimer - delta, 0.0)
		# smoothstep: 짧은 패닝이 급출발·급정지 없이 미끄러지듯 움직인다
		var t = smoothstep(0.0, 1.0, 1.0 - panTimer / PAN_DURATION)
		global_position = panFrom.lerp(roomCenter(currentRoom), t)
	else:
		global_position = roomCenter(currentRoom)

# 룸 좌표 계산

func roomAt(worldPosition):

	return Vector2i(((worldPosition - roomOrigin) / ROOM_SIZE).floor())

func roomCenter(room):

	return roomOrigin + (Vector2(room) + Vector2(0.5, 0.5)) * ROOM_SIZE

func snapToRoom():

	panTimer = 0.0
	global_position = roomCenter(currentRoom)
	reset_physics_interpolation() # 순간이동이 잔상처럼 보간되지 않도록

# 화면(16:9)이 룸(4:3)보다 넓어 옆 룸이 보이는 좌우 여백을 검은 막대로 가린다.
# 1920x1080 기준 룸은 1440px(320 x 4.5)이라 양쪽에 240px씩 남는다

func buildSideBars():

	var viewSize = get_viewport_rect().size
	var barWidth = (viewSize.x - ROOM_SIZE.x * zoom.x) * 0.5

	if barWidth <= 0.0:
		return

	# 게임 화면(레이어 0)은 가리고 에디터 UI(레이어 10)는 가리지 않는 사이 값
	var layer = CanvasLayer.new()
	layer.layer = 5
	add_child(layer)

	for side in 2:
		var bar = ColorRect.new()
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.position = Vector2(0.0 if side == 0 else viewSize.x - barWidth, 0.0)
		bar.size = Vector2(barWidth, viewSize.y)
		layer.add_child(bar)
