extends Node2D

# 간단한 2D 맵 제작 툴.
#
#  [1] 바닥 타일   [2] 벽 타일
#  [3] 빨간 과일   [4] 파란 과일   [5] 초록 과일
#  [6] 플레이어 시작 지점
#  [7] 물 (가득)   [8] 물 (수면 높게)   [9] 물 (수면 낮게)
#  [0] 원웨이 블럭 (칸 위) — 아래에서는 통과, 위에서는 착지
#  [Q] 용암 (가득)   [W] 용암 (수면 높게)   [E] 용암 (수면 낮게)
#  [R] 매달림 원웨이 — 칸 아래쪽에 붙는 얇은 발판. 점프로 통과하고, 매달린 채 지나갈 수 있다
#  [T] 초록 인간 — 초록 플레이어가 닿으면 껴안았다 3블럭 위로 띄워 주고, 다른 색이 밟으면 1블럭 튕겨 낸다
#
#  좌클릭: 배치 / 우클릭: 삭제 (오브젝트가 있으면 오브젝트 먼저)
#  휠: 확대·축소 / 휠 버튼 드래그: 화면 이동
#  방향키: 맵 전체를 1칸씩 이동 (경계 밖으로 나간 타일/오브젝트는 잘린다)
#  좌측 패널 팔레트(5x3 격자): 아이콘을 클릭해 도구 선택 — 위 단축키와 병행.
#  타일셋(tilemap.png)의 모든 타일이 도구로 자동 등록되고,
#  지형(충돌 타일) -> 장식(통과 타일) -> 오브젝트 묶음 순으로 정렬된다. ◀ ▶로 페이지 넘기기
#  TAB: 에디터 <-> 플레이 모드 전환 (ESC: 플레이 종료)
#  F11: 전체화면 <-> 창 모드 전환
#
# 에디터는 EDITOR_RESOLUTION(1920x1080) 해상도로 동작한다.
# 플레이 모드로 전환하면 게임 해상도(project.godot 설정)로 되돌려 실제 게임과 같은 시야로 테스트한다.
#
# 맵은 maps/<이름>.json 파일로 저장/불러오기 된다.
# 에디터에서 실행할 때는 프로젝트 안(res://maps)이라 git으로 공유되고,
# export된 게임에서는 res://가 읽기 전용이므로 user://maps에 저장된다.
# 플레이 모드로 전환하면 현재 맵이 자동 저장된다 (이름이 비어 있으면 autosave).
# 에디터를 열면 가장 최근에 저장한 맵이 자동으로 불러와진다.

const FRUIT_SCENE = preload("res://Fruit/Fruit.tscn")
const WATER_SCENE = preload("res://water/Water.tscn")
const LAVA_SCENE = preload("res://lava/Lava.tscn")
const CLING_PLATFORM_SCENE = preload("res://platform/ClingPlatform.tscn")
const GREEN_HUMAN_SCENE = preload("res://npc/GreenHuman.tscn")
const PLAYER_SCENE = preload("res://Player/ColorPlayer.tscn")

# 팔레트 아이콘용 리소스 — 오브젝트가 실제로 쓰는 텍스처를 아이콘으로 재사용한다
const FRUIT_SCRIPT = preload("res://Scripts/fruit.gd") # class_name이 없어 스크립트로 텍스처 테이블(TEXTURES)을 참조
const TILESET_TEXTURE = preload("res://Sprites/tilemap.png")
const PLAYER_FRAMES = preload("res://Sprites/player.tres")

const CELL = 16
const TILE_SOURCE = 0
const MIN_SIZE = 4
const MAX_SIZE = 1000 # 격자 오버레이가 매 프레임 (가로+세로)줄을 그리므로 무한정 키우지 않는다

# 에디터 작업 해상도 — 게임 해상도(project.godot 설정)와 무관하게 고정해
# 한 화면에서 넓은 맵을 보며 작업한다.
# 플레이 모드에서는 게임 해상도로 되돌린다 — 실제 게임과 같은 시야로 테스트하기 위해 (startPlay/stopPlay)
const EDITOR_RESOLUTION = Vector2i(1920, 1080)

# 이름 있는 기본 타일 -> 타일셋 아틀라스 좌표. 저장 포맷(type 문자열)과 도구 단축키가 이 이름을 쓴다.
# 타일셋의 나머지 타일 전부는 buildTileTools()가 "tile_x_y" 이름으로 tileTypes에 자동 추가한다
const TILE_TYPES = {
	"floor": Vector2i(4, 0), # 풀이 덮인 바닥
	"wall": Vector2i(4, 2), # 속이 채워진 벽
	"platform": Vector2i(7, 1), # 얇은 잔디 발판 — 칸 상단만 차지하는 원웨이 플랫폼
}

# 과일 종류 -> 플레이어 색 상태
const FRUIT_STATES = {
	"red": ColorPlayer.ColorState.RED,
	"blue": ColorPlayer.ColorState.BLUE,
	"green": ColorPlayer.ColorState.GREEN,
}

# 물 종류 -> 수위
const WATER_LEVELS = {
	"full": Water.Level.FULL,
	"high": Water.Level.HIGH,
	"low": Water.Level.LOW,
}

# 용암 종류 -> 수위
const LAVA_LEVELS = {
	"full": Lava.Level.FULL,
	"high": Lava.Level.HIGH,
	"low": Lava.Level.LOW,
}

enum Mode { EDIT, PLAY }
enum Tool { FLOOR, WALL, FRUIT_RED, FRUIT_BLUE, FRUIT_GREEN, PLAYER_START, WATER_FULL, WATER_HIGH, WATER_LOW, PLATFORM, LAVA_FULL, LAVA_HIGH, LAVA_LOW, CLING_PLATFORM, GREEN_HUMAN }

const TOOL_INFO = {
	Tool.FLOOR: { "name": "바닥 타일", "tile": "floor" },
	Tool.WALL: { "name": "벽 타일", "tile": "wall" },
	Tool.FRUIT_RED: { "name": "빨간 과일", "fruit": "red" },
	Tool.FRUIT_BLUE: { "name": "파란 과일", "fruit": "blue" },
	Tool.FRUIT_GREEN: { "name": "초록 과일", "fruit": "green" },
	Tool.PLAYER_START: { "name": "시작 지점" },
	Tool.WATER_FULL: { "name": "물 (가득)", "water": "full" },
	Tool.WATER_HIGH: { "name": "물 (수면 높게)", "water": "high" },
	Tool.WATER_LOW: { "name": "물 (수면 낮게)", "water": "low" },
	Tool.PLATFORM: { "name": "원웨이 블럭 (칸 위)", "tile": "platform" },
	Tool.LAVA_FULL: { "name": "용암 (가득)", "lava": "full" },
	Tool.LAVA_HIGH: { "name": "용암 (수면 높게)", "lava": "high" },
	Tool.LAVA_LOW: { "name": "용암 (수면 낮게)", "lava": "low" },
	Tool.CLING_PLATFORM: { "name": "매달림 원웨이 (칸 아래)", "clingPlatform": "bottom" },
	Tool.GREEN_HUMAN: { "name": "초록 인간", "greenHuman": "default" },
}

# 도구 팔레트 — 5 x 3 격자. 도구가 격자보다 많아지면 ◀ ▶로 줄 단위 스크롤
const PALETTE_COLUMNS = 5
const PALETTE_ROWS = 3
const PALETTE_ICON_SIZE = 40 # 아이콘 버튼 한 변 px

# 맵 저장 폴더 — 에디터 실행 시에는 프로젝트 폴더, export 빌드에서는 사용자 데이터 폴더
var mapsDir = "res://maps" if OS.has_feature("editor") else "user://maps"

# Public

@onready var tileMap = $TileMap
@onready var objectsRoot = $Objects
@onready var camera = $Camera

# Private

var mode = Mode.EDIT
var currentTool = Tool.FLOOR

# 타일셋의 모든 타일을 도구로 쓰기 위한 런타임 확장 테이블 (buildTileTools에서 채움).
# 코드 곳곳에서는 상수 대신 이쪽을 쓴다 — 이름 있는 항목(TILE_TYPES/TOOL_INFO) + 자동 생성된 타일 항목
var tileTypes = {}
var toolInfo = {}

var mapWidth = 40
var mapHeight = 15
var playerStartCell = Vector2i(2, 11)

# 셀 좌표(Vector2i) -> { "type": "fruit"|"water"|"lava"|"clingPlatform", "variant": "red"|"full"|..., "node": 인스턴스 }
# 오브젝트의 원본 데이터. 노드는 이 데이터로부터 언제든 다시 만들어진다.
var objects = {}

var player = null
var zoomLevel = 2.0
var hoverCell = Vector2i(-1, -1)
var overlay

# 프로젝트 설정의 게임 해상도 — 플레이 모드에서 복원할 값 (_ready에서 기억)
var gameResolution

# UI
var uiPanel
var widthBox
var heightBox
var fileEdit
var toolLabel
var statusLabel
var playHint
var fullscreenButton
var paletteButtons = {} # 도구 id -> 팔레트 아이콘 버튼 (선택 강조/스크롤 갱신용)
var paletteSlots = [] # 격자 칸 순서대로의 도구 id, -1은 빈 칸 — 묶음 줄맞춤용 (buildTileTools에서 채움)
var paletteSlotControls = [] # paletteSlots와 같은 순서의 버튼/빈 칸 컨트롤 (buildUI에서 채움)
var paletteStartRow = 0 # 팔레트 격자에 보이는 첫 줄 (도구가 격자보다 많을 때만 의미 있다)
var paletteLeft
var paletteRight

# 격자·시작 지점 등을 타일 위에 겹쳐 그리는 오버레이
class EditorOverlay extends Node2D:

	func _draw():
		get_parent().drawOverlay(self)

# Methods

func _ready():

	# 에디터는 전체화면으로 시작 (F11 또는 버튼으로 창 모드 전환)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

	# 게임보다 큰 해상도로 작업 — 플레이 모드에서 복원할 게임 해상도를 먼저 기억해 둔다
	gameResolution = get_window().content_scale_size
	get_window().content_scale_size = EDITOR_RESOLUTION

	overlay = EditorOverlay.new()
	overlay.z_index = 100
	add_child(overlay)

	# 에디터 카메라는 마우스로 직접 움직이므로 물리 보간에서 제외
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

	buildTileTools()
	buildUI()

	# 가장 최근에 저장한 맵이 있으면 자동으로 불러온다
	var latest = latestMapName()

	if latest != "":
		fileEdit.text = latest

	if latest == "" or !loadMap():
		newMap(mapWidth, mapHeight)

	selectTool(Tool.FLOOR)

# 도구 목록 — 타일셋 아틀라스에 정의된 모든 타일을 도구로 등록하고 팔레트 순서를 정한다.
# TILE_TYPES에 이름이 있는 타일은 그 이름 그대로(저장 포맷·단축키 유지),
# 나머지는 "tile_x_y" 이름과 이어지는 도구 id로 팔레트에만 추가된다 (단축키 없음).
# 팔레트는 지형(충돌 타일) -> 장식(통과 타일) -> 오브젝트 묶음 순이고,
# 묶음이 끝나면 빈 칸(-1)으로 채워 다음 묶음이 새 줄에서 시작한다

func buildTileTools():

	tileTypes = TILE_TYPES.duplicate()
	toolInfo = TOOL_INFO.duplicate()

	var source = tileMap.tile_set.get_source(TILE_SOURCE)

	# 빈(전부 투명) 칸을 걸러내기 위해 아틀라스 이미지를 읽어 둔다
	var image = TILESET_TEXTURE.get_image()
	if image.is_compressed():
		image.decompress()

	# 타일 도구를 충돌 유무로 나눠 모은다 — [아틀라스 좌표, 도구 id] 쌍 (좌표순 정렬용)
	var solidTiles = []
	var decorTiles = []

	var nextId = Tool.size() # 생성 도구 id는 enum 값(0부터 연속)과 겹치지 않게 그 다음부터

	for i in source.get_tiles_count():

		var coords = source.get_tile_id(i)

		if tileIsEmpty(image, coords):
			continue

		# 충돌 폴리곤이 없는 타일은 밟을 수 없는 배경 장식 — 묶음과 툴팁으로 구분해 준다
		var solid = source.get_tile_data(coords, 0).get_collision_polygons_count(0) > 0
		var toolId = namedTileTool(coords)

		if toolId == -1:
			toolId = nextId
			nextId += 1

			var typeName = "tile_%d_%d" % [coords.x, coords.y]
			tileTypes[typeName] = coords
			toolInfo[toolId] = { "name": "타일 (%d, %d)%s" % [coords.x, coords.y, "" if solid else " — 장식(통과)"], "tile": typeName }

		if solid:
			solidTiles.append([coords, toolId])
		else:
			decorTiles.append([coords, toolId])

	# 시트에서 보이는 위치(위->아래, 왼->오른쪽) 순으로 — 상자 조각들이 흩어지지 않게
	var byCoords = func(a, b): return a[0].y < b[0].y or (a[0].y == b[0].y and a[0].x < b[0].x)
	solidTiles.sort_custom(byCoords)
	decorTiles.sort_custom(byCoords)

	# 오브젝트 묶음 — 비슷한 것끼리. 목록에 빠진 새 오브젝트 도구가 있으면 뒤에 자동으로 붙는다
	var objectTools = [
		Tool.FRUIT_RED, Tool.FRUIT_BLUE, Tool.FRUIT_GREEN,
		Tool.WATER_FULL, Tool.WATER_HIGH, Tool.WATER_LOW,
		Tool.LAVA_FULL, Tool.LAVA_HIGH, Tool.LAVA_LOW,
		Tool.CLING_PLATFORM, Tool.GREEN_HUMAN, Tool.PLAYER_START,
	]

	for toolId in Tool.values():
		if !TOOL_INFO[toolId].has("tile") and !objectTools.has(toolId):
			objectTools.append(toolId)

	paletteSlots = []

	for group in [solidTiles.map(func(entry): return entry[1]), decorTiles.map(func(entry): return entry[1]), objectTools]:

		paletteSlots.append_array(group)

		# 남은 칸을 비워 다음 묶음이 새 줄에서 시작하게
		while paletteSlots.size() % PALETTE_COLUMNS != 0:
			paletteSlots.append(-1)

# 이름 있는 타일(TILE_TYPES)을 쓰는 기존 enum 도구 id — 없으면 -1

func namedTileTool(coords):

	for toolId in TOOL_INFO:

		var info = TOOL_INFO[toolId]

		if info.has("tile") and TILE_TYPES[info.tile] == coords:
			return toolId

	return -1

# 아틀라스의 한 칸이 전부 투명한지 — 팔레트에 빈 도구가 생기지 않게 거른다

func tileIsEmpty(image, coords):

	for y in CELL:
		for x in CELL:
			if image.get_pixel(coords.x * CELL + x, coords.y * CELL + y).a > 0:
				return false

	return true

# 맵 관리

func newMap(width, height):

	mapWidth = clampi(width, MIN_SIZE, MAX_SIZE)
	mapHeight = clampi(height, MIN_SIZE, MAX_SIZE)

	tileMap.clear()
	clearObjects()

	# 시작용 바닥 두 줄
	for x in range(mapWidth):
		tileMap.set_cell(Vector2i(x, mapHeight - 2), TILE_SOURCE, tileTypes["floor"])
		tileMap.set_cell(Vector2i(x, mapHeight - 1), TILE_SOURCE, tileTypes["wall"])

	playerStartCell = Vector2i(2, mapHeight - 4)

	centerCamera()
	syncUI()
	refresh()

func resizeMap(width, height):

	mapWidth = clampi(width, MIN_SIZE, MAX_SIZE)
	mapHeight = clampi(height, MIN_SIZE, MAX_SIZE)

	# 새 크기 밖으로 벗어난 타일과 오브젝트는 제거
	for cell in tileMap.get_used_cells():
		if !isInside(cell):
			tileMap.erase_cell(cell)

	for cell in objects.keys():
		if !isInside(cell):
			removeObject(cell)

	playerStartCell = playerStartCell.clamp(Vector2i(0, 0), Vector2i(mapWidth - 1, mapHeight - 1))

	syncUI()
	refresh()
	setStatus("맵 크기: %d x %d" % [mapWidth, mapHeight])

# 맵 전체(타일/오브젝트/시작 지점)를 1칸 이동. 경계 밖으로 나간 것은 잘리며 상태줄에 알린다.
func shiftMap(offset):

	var movedTiles = {}
	var clippedTiles = 0

	for cell in tileMap.get_used_cells():

		var target = cell + offset

		if isInside(target):
			movedTiles[target] = tileMap.get_cell_atlas_coords(cell)
		else:
			clippedTiles += 1

	tileMap.clear()

	for cell in movedTiles:
		tileMap.set_cell(cell, TILE_SOURCE, movedTiles[cell])

	var movedObjects = {}
	var clippedObjects = 0

	for cell in objects:

		var data = objects[cell]
		var target = cell + offset

		if isInside(target):
			movedObjects[target] = data
			if is_instance_valid(data.node):
				data.node.position = cellCenter(target)
				data.node.reset_physics_interpolation() # 순간이동이 잔상처럼 보간되지 않도록
		else:
			clippedObjects += 1
			if is_instance_valid(data.node):
				data.node.queue_free()

	objects = movedObjects

	playerStartCell = (playerStartCell + offset).clamp(Vector2i(0, 0), Vector2i(mapWidth - 1, mapHeight - 1))

	refresh()

	var directionNames = {
		Vector2i.LEFT: "왼쪽", Vector2i.RIGHT: "오른쪽",
		Vector2i.UP: "위", Vector2i.DOWN: "아래",
	}
	var message = "맵 이동: " + directionNames.get(offset, str(offset))

	if clippedTiles > 0 or clippedObjects > 0:
		message += " — 경계 밖으로 잘림: 타일 %d, 오브젝트 %d" % [clippedTiles, clippedObjects]

	setStatus(message)

func isInside(cell):
	return cell.x >= 0 and cell.y >= 0 and cell.x < mapWidth and cell.y < mapHeight

func cellCenter(cell):
	return Vector2(cell) * CELL + Vector2(CELL, CELL) * 0.5

# 입력 처리

func _unhandled_input(event):

	if event is InputEventKey and event.pressed and !event.echo:
		handleKey(event)
		return

	if mode != Mode.EDIT:
		return

	if event is InputEventMouseButton and event.pressed:

		# 캔버스를 클릭하면 UI 포커스를 해제 (TAB 전환이 막히지 않도록)
		var focus = get_viewport().gui_get_focus_owner()
		if focus:
			focus.release_focus()

		match event.button_index:
			MOUSE_BUTTON_LEFT: paint(mouseCell(), false)
			MOUSE_BUTTON_RIGHT: paint(mouseCell(), true)
			MOUSE_BUTTON_WHEEL_UP: applyZoom(1.25)
			MOUSE_BUTTON_WHEEL_DOWN: applyZoom(0.8)

	if event is InputEventMouseMotion:

		hoverCell = mouseCell()

		if event.button_mask & MOUSE_BUTTON_MASK_MIDDLE:
			camera.position -= event.relative / zoomLevel
		elif event.button_mask & MOUSE_BUTTON_MASK_LEFT:
			paint(hoverCell, false)
		elif event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			paint(hoverCell, true)

		overlay.queue_redraw()

func handleKey(event):

	if event.physical_keycode == KEY_TAB:
		toggleMode()
		return

	if event.physical_keycode == KEY_ESCAPE and mode == Mode.PLAY:
		stopPlay()
		return

	if event.physical_keycode == KEY_F11:
		toggleFullscreen()
		return

	if mode != Mode.EDIT:
		return

	match event.physical_keycode:
		KEY_1: selectTool(Tool.FLOOR)
		KEY_2: selectTool(Tool.WALL)
		KEY_3: selectTool(Tool.FRUIT_RED)
		KEY_4: selectTool(Tool.FRUIT_BLUE)
		KEY_5: selectTool(Tool.FRUIT_GREEN)
		KEY_6: selectTool(Tool.PLAYER_START)
		KEY_7: selectTool(Tool.WATER_FULL)
		KEY_8: selectTool(Tool.WATER_HIGH)
		KEY_9: selectTool(Tool.WATER_LOW)
		KEY_0: selectTool(Tool.PLATFORM)
		KEY_Q: selectTool(Tool.LAVA_FULL)
		KEY_W: selectTool(Tool.LAVA_HIGH)
		KEY_E: selectTool(Tool.LAVA_LOW)
		KEY_R: selectTool(Tool.CLING_PLATFORM)
		KEY_T: selectTool(Tool.GREEN_HUMAN)
		KEY_LEFT: shiftMap(Vector2i.LEFT)
		KEY_RIGHT: shiftMap(Vector2i.RIGHT)
		KEY_UP: shiftMap(Vector2i.UP)
		KEY_DOWN: shiftMap(Vector2i.DOWN)

func mouseCell():
	return tileMap.local_to_map(tileMap.get_local_mouse_position())

func selectTool(newTool):

	currentTool = newTool
	toolLabel.text = "도구: " + toolInfo[newTool].name

	# 단축키로 선택해도 팔레트가 따라가도록 — 선택 도구가 격자 밖이면 보이는 줄로 스크롤
	@warning_ignore("integer_division")
	var row = paletteSlots.find(newTool) / PALETTE_COLUMNS
	paletteStartRow = clampi(paletteStartRow, row - PALETTE_ROWS + 1, row)
	syncPalette()

# 배치 / 삭제

func paint(cell, erase):

	if !isInside(cell):
		return

	if erase:
		if objects.has(cell):
			removeObject(cell)
		else:
			tileMap.erase_cell(cell)
		refresh()
		return

	var info = toolInfo[currentTool]

	if info.has("tile"):
		tileMap.set_cell(cell, TILE_SOURCE, tileTypes[info.tile])
	elif info.has("fruit"):
		placeObject(cell, "fruit", info.fruit)
	elif info.has("water"):
		placeObject(cell, "water", info.water)
	elif info.has("lava"):
		placeObject(cell, "lava", info.lava)
	elif info.has("clingPlatform"):
		placeObject(cell, "clingPlatform", info.clingPlatform)
	elif info.has("greenHuman"):
		placeObject(cell, "greenHuman", info.greenHuman)
	elif currentTool == Tool.PLAYER_START:
		playerStartCell = cell

	refresh()

func placeObject(cell, type, variant):

	if objects.has(cell):
		if objects[cell].type == type and objects[cell].variant == variant:
			return
		removeObject(cell)

	objects[cell] = { "type": type, "variant": variant, "node": spawnObject(cell, type, variant) }

func spawnObject(cell, type, variant):

	var node

	match type:
		"fruit":
			node = FRUIT_SCENE.instantiate()
			node.fruitState = FRUIT_STATES[variant]
		"water":
			node = WATER_SCENE.instantiate()
			node.waterLevel = WATER_LEVELS[variant]
		"lava":
			node = LAVA_SCENE.instantiate()
			node.lavaLevel = LAVA_LEVELS[variant]
		"clingPlatform":
			node = CLING_PLATFORM_SCENE.instantiate() # 변형은 아직 bottom 하나뿐
		"greenHuman":
			node = GREEN_HUMAN_SCENE.instantiate() # 변형은 아직 default 하나뿐

	node.position = cellCenter(cell)
	objectsRoot.add_child(node)

	return node

func removeObject(cell):

	var node = objects[cell].node
	if is_instance_valid(node):
		node.queue_free()

	objects.erase(cell)

func clearObjects():

	for cell in objects.keys():
		removeObject(cell)

# 데이터(objects)를 기준으로 오브젝트 노드를 다시 생성.
# 플레이 중 먹혀서 사라진 과일도 여기서 복원된다.
func rebuildObjects():

	for cell in objects:

		var data = objects[cell]

		if is_instance_valid(data.node):
			data.node.queue_free()

		data.node = spawnObject(cell, data.type, data.variant)

# 에디터 <-> 플레이 모드

func toggleMode():

	if mode == Mode.EDIT:
		startPlay()
	else:
		stopPlay()

func startPlay():

	mode = Mode.PLAY

	# 실제 게임과 같은 시야로 테스트하도록 게임 해상도로 되돌린다
	get_window().content_scale_size = gameResolution

	var saved = autoSave()

	rebuildObjects()

	player = PLAYER_SCENE.instantiate()
	player.position = cellCenter(playerStartCell)
	player.resetY = mapHeight * CELL + 100 # 맵 아래로 떨어지면 시작 지점으로
	add_child(player)
	player.reset_physics_interpolation()
	player.get_node("Camera").make_current()

	# 바로 점프까지 테스트하려면 아래 줄의 주석을 해제 (기본은 게임과 같은 어둠 상태)
	# player.setState(ColorPlayer.ColorState.RED)

	uiPanel.visible = false
	playHint.visible = true

	# 저장 실패 시에는 writeMap이 남긴 실패 메시지를 그대로 둔다
	if saved:
		setStatus("플레이 모드 — 자동 저장됨: %s.json" % fileEdit.text.strip_edges())

	refresh()

func stopPlay():

	mode = Mode.EDIT

	get_window().content_scale_size = EDITOR_RESOLUTION # 에디터 작업 해상도로 복귀

	if is_instance_valid(player):
		player.queue_free()
	player = null

	rebuildObjects()
	camera.make_current()

	uiPanel.visible = true
	playHint.visible = false
	setStatus("에디터 모드")
	refresh()

# 전체화면 <-> 창 모드

func toggleFullscreen():

	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

		# 창 크기를 에디터 해상도에 맞춘다 — 프로젝트 기본 창(1024x600)에 캔버스가
		# 짓눌려 보이지 않도록. 모니터(작업 표시줄 제외)보다 크면 그만큼 줄여서 중앙에 놓는다
		var usable = DisplayServer.screen_get_usable_rect()
		var windowSize = EDITOR_RESOLUTION.min(usable.size)

		get_window().size = windowSize
		get_window().position = usable.position + (usable.size - windowSize) / 2
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

	syncFullscreenButton()

# 버튼에는 지금 누르면 바뀔 모드를 표시한다
func syncFullscreenButton():

	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		fullscreenButton.text = "창 모드 (F11)"
	else:
		fullscreenButton.text = "전체화면 (F11)"

# 저장 / 불러오기

func mapPath(fileName):
	return "%s/%s.json" % [mapsDir, fileName]

func saveMap():

	var fileName = fileEdit.text.strip_edges()

	if fileName == "":
		setStatus("파일 이름을 입력하세요")
		return

	if writeMap(fileName):
		setStatus("저장됨: " + ProjectSettings.globalize_path(mapPath(fileName)))

# 플레이 전환 시 호출. 파일 이름이 비어 있으면 autosave라는 이름으로 저장한다.
func autoSave():

	var fileName = fileEdit.text.strip_edges()

	if fileName == "":
		fileName = "autosave"
		fileEdit.text = fileName

	return writeMap(fileName)

func writeMap(fileName):

	var data = {
		"version": 1,
		"width": mapWidth,
		"height": mapHeight,
		"playerStart": { "x": playerStartCell.x, "y": playerStartCell.y },
		"tiles": [],
		"objects": [],
	}

	for cell in tileMap.get_used_cells():

		var atlas = tileMap.get_cell_atlas_coords(cell)

		for typeName in tileTypes:
			if tileTypes[typeName] == atlas:
				data.tiles.append({ "x": cell.x, "y": cell.y, "type": typeName })
				break

	for cell in objects:
		var object = objects[cell]
		var entry = { "x": cell.x, "y": cell.y, "type": object.type }
		entry[object.type] = object.variant # "fruit"/"water"/"lava" 필드에 종류 저장
		data.objects.append(entry)

	DirAccess.make_dir_recursive_absolute(mapsDir)

	var path = mapPath(fileName)
	var file = FileAccess.open(path, FileAccess.WRITE)

	if file == null:
		setStatus("저장 실패: " + str(FileAccess.get_open_error()))
		return false

	file.store_string(JSON.stringify(data, "\t"))
	file.close()

	return true

func loadMap():

	var fileName = fileEdit.text.strip_edges()
	var path = mapPath(fileName)

	if !FileAccess.file_exists(path):
		setStatus("파일이 없습니다: " + ProjectSettings.globalize_path(path))
		return false

	var file = FileAccess.open(path, FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()

	if typeof(data) != TYPE_DICTIONARY:
		setStatus("JSON을 읽을 수 없습니다")
		return false

	tileMap.clear()
	clearObjects()

	mapWidth = clampi(int(data.get("width", 40)), MIN_SIZE, MAX_SIZE)
	mapHeight = clampi(int(data.get("height", 15)), MIN_SIZE, MAX_SIZE)

	for tile in data.get("tiles", []):

		var cell = Vector2i(int(tile.x), int(tile.y))

		if isInside(cell) and tileTypes.has(tile.get("type", "")):
			tileMap.set_cell(cell, TILE_SOURCE, tileTypes[tile.type])

	for object in data.get("objects", []):

		var cell = Vector2i(int(object.x), int(object.y))

		if !isInside(cell):
			continue

		var type = object.get("type", "fruit")

		if type == "fruit" and FRUIT_STATES.has(object.get("fruit", "")):
			placeObject(cell, "fruit", object.fruit)
		elif type == "water" and WATER_LEVELS.has(object.get("water", "")):
			placeObject(cell, "water", object.water)
		elif type == "lava" and LAVA_LEVELS.has(object.get("lava", "")):
			placeObject(cell, "lava", object.lava)
		elif type == "clingPlatform":
			placeObject(cell, "clingPlatform", "bottom") # 변형은 아직 bottom 하나뿐
		elif type == "greenHuman":
			placeObject(cell, "greenHuman", "default") # 변형은 아직 default 하나뿐

	var start = data.get("playerStart", {})
	playerStartCell = Vector2i(int(start.get("x", 2)), int(start.get("y", mapHeight - 4)))
	playerStartCell = playerStartCell.clamp(Vector2i(0, 0), Vector2i(mapWidth - 1, mapHeight - 1))

	centerCamera()
	syncUI()
	refresh()
	setStatus("불러옴: %s.json" % fileName)

	return true

# 맵 폴더에서 가장 최근에 수정된 맵 파일 이름 (없으면 "")

func latestMapName():

	var dir = DirAccess.open(mapsDir)

	if dir == null:
		return ""

	var latestName = ""
	var latestTime = 0

	for fileName in dir.get_files():

		if fileName.get_extension() != "json":
			continue

		var time = FileAccess.get_modified_time(mapsDir + "/" + fileName)

		if time > latestTime:
			latestTime = time
			latestName = fileName.get_basename()

	return latestName

# 카메라

func centerCamera():
	camera.position = Vector2(mapWidth, mapHeight) * CELL * 0.5

func applyZoom(factor):

	var mouse = get_global_mouse_position()
	var previous = zoomLevel

	zoomLevel = clampf(zoomLevel * factor, 0.5, 8.0)
	camera.zoom = Vector2(zoomLevel, zoomLevel)

	# 마우스가 가리키던 지점이 그대로 유지되도록 보정
	camera.position = mouse + (camera.position - mouse) * (previous / zoomLevel)

# 그리기

func _draw():

	# 맵 영역 배경 (타일 아래)
	draw_rect(Rect2(Vector2.ZERO, Vector2(mapWidth, mapHeight) * CELL), Color(0.16, 0.15, 0.22))

func drawOverlay(c):

	if mode != Mode.EDIT:
		return

	var mapSize = Vector2(mapWidth, mapHeight) * CELL
	var lineColor = Color(1, 1, 1, 0.07)

	# 격자
	for x in range(mapWidth + 1):
		c.draw_line(Vector2(x * CELL, 0), Vector2(x * CELL, mapSize.y), lineColor)
	for y in range(mapHeight + 1):
		c.draw_line(Vector2(0, y * CELL), Vector2(mapSize.x, y * CELL), lineColor)

	# 맵 경계
	c.draw_rect(Rect2(Vector2.ZERO, mapSize), Color(1, 1, 1, 0.4), false)

	# 시작 지점 표시 (플레이어 크기의 유령 상자 + 눈)
	var start = cellCenter(playerStartCell)
	c.draw_rect(Rect2(start - Vector2(6, 8), Vector2(12, 16)), Color(1, 0.95, 0.6, 0.15))
	c.draw_rect(Rect2(start - Vector2(6, 8), Vector2(12, 16)), Color(1, 0.95, 0.6, 0.9), false)
	c.draw_circle(start + Vector2(-2.5, -3), 1.2, Color(1, 0.95, 0.7))
	c.draw_circle(start + Vector2(2.5, -3), 1.2, Color(1, 0.95, 0.7))

	# 마우스가 가리키는 셀 강조
	if isInside(hoverCell):
		c.draw_rect(Rect2(Vector2(hoverCell) * CELL, Vector2(CELL, CELL)), Color(1, 1, 1, 0.08))
		c.draw_rect(Rect2(Vector2(hoverCell) * CELL, Vector2(CELL, CELL)), Color(1, 1, 1, 0.25), false)

func refresh():
	queue_redraw()
	overlay.queue_redraw()

# UI 구성

func buildUI():

	# 화면 전체 배경 (카메라와 무관하게 고정)
	var bgLayer = CanvasLayer.new()
	bgLayer.layer = -10
	add_child(bgLayer)

	var bg = ColorRect.new()
	bg.color = Color(0.1, 0.09, 0.13)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bgLayer.add_child(bg)

	var ui = CanvasLayer.new()
	ui.layer = 10
	add_child(ui)

	# 이하 글자 크기는 1024x600 시절 값의 약 1.3배 —
	# 에디터 해상도(1920x1080)에서도 체감 크기가 비슷하게 유지되도록 키운 것

	# 편집 패널
	uiPanel = PanelContainer.new()
	uiPanel.position = Vector2(10, 10)
	ui.add_child(uiPanel)

	var box = VBoxContainer.new()
	box.custom_minimum_size.x = 280
	uiPanel.add_child(box)

	box.add_child(makeLabel("맵 크기", 16))

	var sizeRow = HBoxContainer.new()
	box.add_child(sizeRow)

	widthBox = SpinBox.new()
	widthBox.min_value = MIN_SIZE
	widthBox.max_value = MAX_SIZE
	widthBox.value = mapWidth
	widthBox.custom_minimum_size.x = 80
	sizeRow.add_child(widthBox)

	sizeRow.add_child(makeLabel("x", 16))

	heightBox = SpinBox.new()
	heightBox.min_value = MIN_SIZE
	heightBox.max_value = MAX_SIZE
	heightBox.value = mapHeight
	heightBox.custom_minimum_size.x = 80
	sizeRow.add_child(heightBox)

	var applyButton = makeButton("적용")
	applyButton.pressed.connect(func():
		commitSizeBoxes()
		resizeMap(int(widthBox.value), int(heightBox.value)))
	sizeRow.add_child(applyButton)

	box.add_child(makeLabel("맵 전체 이동 (방향키)", 16))

	var shiftRow = HBoxContainer.new()
	box.add_child(shiftRow)

	for entry in [["◀", Vector2i.LEFT], ["▲", Vector2i.UP], ["▼", Vector2i.DOWN], ["▶", Vector2i.RIGHT]]:
		var shiftButton = makeButton(entry[0])
		shiftButton.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		shiftButton.pressed.connect(func(): shiftMap(entry[1]))
		shiftRow.add_child(shiftButton)

	box.add_child(HSeparator.new())
	box.add_child(makeLabel("파일 이름 (%s/)" % mapsDir, 16))

	fileEdit = LineEdit.new()
	fileEdit.text = "map1"
	fileEdit.text_submitted.connect(func(_text): fileEdit.release_focus())
	box.add_child(fileEdit)

	var fileRow = HBoxContainer.new()
	box.add_child(fileRow)

	var saveButton = makeButton("저장")
	saveButton.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	saveButton.pressed.connect(saveMap)
	fileRow.add_child(saveButton)

	var loadButton = makeButton("불러오기")
	loadButton.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loadButton.pressed.connect(loadMap)
	fileRow.add_child(loadButton)

	var clearButton = makeButton("새 맵")
	clearButton.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clearButton.pressed.connect(func():
		commitSizeBoxes()
		newMap(int(widthBox.value), int(heightBox.value)))
	fileRow.add_child(clearButton)

	box.add_child(HSeparator.new())

	toolLabel = makeLabel("", 18)
	box.add_child(toolLabel)

	# 도구 팔레트 — 5x3 격자에서 아이콘을 클릭해 도구 선택 (아래 단축키와 병행).
	# 타일셋의 모든 타일이 도구라 격자에 다 안 들어간다 — ◀ ▶로 페이지 넘기기 (scrollPalette)
	var paletteRow = HBoxContainer.new()
	box.add_child(paletteRow)

	paletteLeft = makeButton("◀")
	paletteLeft.pressed.connect(func(): scrollPalette(-1))
	paletteRow.add_child(paletteLeft)

	var paletteGrid = GridContainer.new()
	paletteGrid.columns = PALETTE_COLUMNS
	paletteRow.add_child(paletteGrid)

	for slotId in paletteSlots:

		if slotId == -1:
			# 묶음 줄맞춤용 빈 칸
			var spacer = Control.new()
			spacer.custom_minimum_size = Vector2(PALETTE_ICON_SIZE, PALETTE_ICON_SIZE)
			paletteGrid.add_child(spacer)
			paletteSlotControls.append(spacer)
			continue

		var toolButton = makePaletteButton(slotId)
		paletteButtons[slotId] = toolButton
		paletteGrid.add_child(toolButton)
		paletteSlotControls.append(toolButton)

	paletteRight = makeButton("▶")
	paletteRight.pressed.connect(func(): scrollPalette(1))
	paletteRow.add_child(paletteRight)

	var help = makeLabel("[1] 바닥  [2] 벽
[3] 빨강  [4] 파랑  [5] 초록
[6] 시작 지점
[7] 물 가득  [8] 물 높게  [9] 물 낮게
[Q] 용암 가득  [W] 용암 높게  [E] 용암 낮게
[0] 원웨이 블럭 (칸 위)
[R] 매달림 원웨이 (칸 아래)
[T] 초록 인간
[방향키] 맵 전체 1칸 이동
좌클릭 배치 · 우클릭 삭제
휠 줌 · 휠 드래그 이동", 15)
	help.modulate = Color(1, 1, 1, 0.6)
	box.add_child(help)

	box.add_child(HSeparator.new())

	var playButton = makeButton("▶  플레이 (TAB)")
	playButton.pressed.connect(toggleMode)
	box.add_child(playButton)

	fullscreenButton = makeButton("")
	fullscreenButton.pressed.connect(toggleFullscreen)
	box.add_child(fullscreenButton)
	syncFullscreenButton()

	# 상태 표시줄
	statusLabel = makeLabel("좌클릭 배치 · 우클릭 삭제 · TAB 플레이", 16)
	statusLabel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 10)
	ui.add_child(statusLabel)

	# 플레이 모드 안내
	# 플레이 모드 전용이라 게임 해상도(1024x600) 기준 크기 그대로 둔다
	playHint = makeLabel("플레이 모드  —  TAB: 에디터로 돌아가기", 15)
	playHint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 12)
	playHint.visible = false
	ui.add_child(playHint)

func makeLabel(text, fontSize):

	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", fontSize)

	return label

func makeButton(text):

	var button = Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE

	return button

# 도구 팔레트

func makePaletteButton(toolId):

	var button = Button.new()
	button.toggle_mode = true # 선택된 도구를 눌린 상태로 강조 (실제 토글은 syncPalette가 관리)
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(PALETTE_ICON_SIZE, PALETTE_ICON_SIZE)
	button.icon = toolIconTexture(toolId)
	button.expand_icon = true
	button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST # 16px 픽셀아트가 확대돼도 흐려지지 않게
	button.tooltip_text = toolInfo[toolId].name
	button.pressed.connect(func(): selectTool(toolId))

	var tint = toolIconTint(toolId)

	if tint != Color.WHITE:
		for colorName in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color"]:
			button.add_theme_color_override(colorName, tint)

	return button

# 도구 -> 아이콘 텍스처. 게임 오브젝트가 실제로 쓰는 텍스처를 그대로 가져와
# 에디터에 보이는 모습과 항상 일치한다 (타일/매달림 발판은 아틀라스에서 잘라 쓴다)
func toolIconTexture(toolId):

	var info = toolInfo[toolId]

	if info.has("tile"):
		return atlasIcon(Rect2(Vector2(tileTypes[info.tile] * CELL), Vector2(CELL, CELL)))
	if info.has("fruit"):
		return FRUIT_SCRIPT.TEXTURES[FRUIT_STATES[info.fruit]]
	if info.has("water"):
		return Water.LEVELS[WATER_LEVELS[info.water]].texture
	if info.has("lava"):
		return Lava.LEVELS[LAVA_LEVELS[info.lava]].texture
	if info.has("clingPlatform"):
		return atlasIcon(Rect2(112, 16, 16, 4)) # ClingPlatform.tscn 스프라이트와 같은 영역

	return PLAYER_FRAMES.get_frame_texture("idle", 0) # 시작 지점 / 초록 인간 — 플레이어 모습

# 플레이어 스프라이트를 쓰는 아이콘의 물들임 색 (나머지 도구는 원본 색 그대로)
func toolIconTint(toolId):

	match toolId:
		Tool.PLAYER_START:
			return Color(1, 0.95, 0.6) # 오버레이의 시작 지점 유령 상자와 같은 색
		Tool.GREEN_HUMAN:
			return Color(0.2, 0.55, 0.28) # GreenHuman.tscn 실루엣 tint와 같은 색

	return Color.WHITE

func atlasIcon(region):

	var icon = AtlasTexture.new()
	icon.atlas = TILESET_TEXTURE
	icon.region = region

	return icon

# ◀ ▶ 한 번에 한 페이지(PALETTE_ROWS 줄)씩 — 도구가 많아 줄 단위로는 너무 여러 번 눌러야 한다
func scrollPalette(direction):

	paletteStartRow += direction * PALETTE_ROWS
	syncPalette()

# 팔레트 격자 위치를 범위에 맞추고, 보이는 아이콘과 선택 강조를 갱신한다.
# 모든 도구가 격자에 들어가는 동안에는 ◀ ▶ 버튼을 숨긴다
func syncPalette():

	var totalRows = ceili(paletteSlots.size() / float(PALETTE_COLUMNS))
	var maxStartRow = maxi(totalRows - PALETTE_ROWS, 0)

	paletteStartRow = clampi(paletteStartRow, 0, maxStartRow)

	var first = paletteStartRow * PALETTE_COLUMNS
	var last = first + PALETTE_ROWS * PALETTE_COLUMNS

	for i in paletteSlotControls.size():
		paletteSlotControls[i].visible = i >= first and i < last # 숨긴 컨트롤은 격자 칸을 차지하지 않는다

	for toolId in paletteButtons:
		paletteButtons[toolId].set_pressed_no_signal(toolId == currentTool)

	paletteLeft.visible = maxStartRow > 0
	paletteRight.visible = maxStartRow > 0
	paletteLeft.disabled = paletteStartRow == 0
	paletteRight.disabled = paletteStartRow >= maxStartRow

# 타이핑 중인 크기 값을 확정한다.
# 버튼이 포커스를 가져가지 않아(FOCUS_NONE) SpinBox가 입력 텍스트를 value에
# 반영하지 않은 채 남아 있을 수 있다 — Enter 없이 바로 버튼을 눌러도 적용되도록 한다.
func commitSizeBoxes():
	widthBox.apply()
	heightBox.apply()

func syncUI():
	widthBox.value = mapWidth
	heightBox.value = mapHeight

func setStatus(text):
	statusLabel.text = text
