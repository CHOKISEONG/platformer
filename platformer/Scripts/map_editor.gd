extends Node2D

# 간단한 2D 맵 제작 툴.
#
#  [1] 바닥 타일   [2] 벽 타일
#  [3] 빨간 과일   [4] 파란 과일   [5] 초록 과일
#  [6] 플레이어 시작 지점
#  [7] 물 (가득)   [8] 물 (수면 높게)   [9] 물 (수면 낮게)
#  [0] 원웨이 플랫폼 (아래에서는 통과, 위에서는 착지)
#
#  좌클릭: 배치 / 우클릭: 삭제 (오브젝트가 있으면 오브젝트 먼저)
#  휠: 확대·축소 / 휠 버튼 드래그: 화면 이동
#  TAB: 에디터 <-> 플레이 모드 전환 (ESC: 플레이 종료)
#  F11: 전체화면 <-> 창 모드 전환
#
# 맵은 maps/<이름>.json 파일로 저장/불러오기 된다.
# 에디터에서 실행할 때는 프로젝트 안(res://maps)이라 git으로 공유되고,
# export된 게임에서는 res://가 읽기 전용이므로 user://maps에 저장된다.
# 플레이 모드로 전환하면 현재 맵이 자동 저장된다 (이름이 비어 있으면 autosave).
# 에디터를 열면 가장 최근에 저장한 맵이 자동으로 불러와진다.

const FRUIT_SCENE = preload("res://Fruit/Fruit.tscn")
const WATER_SCENE = preload("res://water/Water.tscn")
const PLAYER_SCENE = preload("res://Player/ColorPlayer.tscn")

const CELL = 16
const TILE_SOURCE = 0
const MIN_SIZE = 4
const MAX_SIZE = 200

# 타일 종류 -> 타일셋 아틀라스 좌표
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

enum Mode { EDIT, PLAY }
enum Tool { FLOOR, WALL, FRUIT_RED, FRUIT_BLUE, FRUIT_GREEN, PLAYER_START, WATER_FULL, WATER_HIGH, WATER_LOW, PLATFORM }

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
	Tool.PLATFORM: { "name": "원웨이 플랫폼", "tile": "platform" },
}

# 맵 저장 폴더 — 에디터 실행 시에는 프로젝트 폴더, export 빌드에서는 사용자 데이터 폴더
var mapsDir = "res://maps" if OS.has_feature("editor") else "user://maps"

# Public

@onready var tileMap = $TileMap
@onready var objectsRoot = $Objects
@onready var camera = $Camera

# Private

var mode = Mode.EDIT
var currentTool = Tool.FLOOR

var mapWidth = 40
var mapHeight = 15
var playerStartCell = Vector2i(2, 11)

# 셀 좌표(Vector2i) -> { "type": "fruit"|"water", "variant": "red"|"full"|..., "node": 인스턴스 }
# 오브젝트의 원본 데이터. 노드는 이 데이터로부터 언제든 다시 만들어진다.
var objects = {}

var player = null
var zoomLevel = 2.0
var hoverCell = Vector2i(-1, -1)
var overlay

# UI
var uiPanel
var widthBox
var heightBox
var fileEdit
var toolLabel
var statusLabel
var playHint
var fullscreenButton

# 격자·시작 지점 등을 타일 위에 겹쳐 그리는 오버레이
class EditorOverlay extends Node2D:

	func _draw():
		get_parent().drawOverlay(self)

# Methods

func _ready():

	# 에디터는 전체화면으로 시작 (F11 또는 버튼으로 창 모드 전환)
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

	overlay = EditorOverlay.new()
	overlay.z_index = 100
	add_child(overlay)

	# 에디터 카메라는 마우스로 직접 움직이므로 물리 보간에서 제외
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

	buildUI()

	# 가장 최근에 저장한 맵이 있으면 자동으로 불러온다
	var latest = latestMapName()

	if latest != "":
		fileEdit.text = latest

	if latest == "" or !loadMap():
		newMap(mapWidth, mapHeight)

	selectTool(Tool.FLOOR)

# 맵 관리

func newMap(width, height):

	mapWidth = clampi(width, MIN_SIZE, MAX_SIZE)
	mapHeight = clampi(height, MIN_SIZE, MAX_SIZE)

	tileMap.clear()
	clearObjects()

	# 시작용 바닥 두 줄
	for x in range(mapWidth):
		tileMap.set_cell(Vector2i(x, mapHeight - 2), TILE_SOURCE, TILE_TYPES["floor"])
		tileMap.set_cell(Vector2i(x, mapHeight - 1), TILE_SOURCE, TILE_TYPES["wall"])

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

func mouseCell():
	return tileMap.local_to_map(tileMap.get_local_mouse_position())

func selectTool(newTool):

	currentTool = newTool
	toolLabel.text = "도구: " + TOOL_INFO[newTool].name

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

	var info = TOOL_INFO[currentTool]

	if info.has("tile"):
		tileMap.set_cell(cell, TILE_SOURCE, TILE_TYPES[info.tile])
	elif info.has("fruit"):
		placeObject(cell, "fruit", info.fruit)
	elif info.has("water"):
		placeObject(cell, "water", info.water)
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

		for typeName in TILE_TYPES:
			if TILE_TYPES[typeName] == atlas:
				data.tiles.append({ "x": cell.x, "y": cell.y, "type": typeName })
				break

	for cell in objects:
		var object = objects[cell]
		var entry = { "x": cell.x, "y": cell.y, "type": object.type }
		entry[object.type] = object.variant # "fruit" 또는 "water" 필드에 종류 저장
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

		if isInside(cell) and TILE_TYPES.has(tile.get("type", "")):
			tileMap.set_cell(cell, TILE_SOURCE, TILE_TYPES[tile.type])

	for object in data.get("objects", []):

		var cell = Vector2i(int(object.x), int(object.y))

		if !isInside(cell):
			continue

		var type = object.get("type", "fruit")

		if type == "fruit" and FRUIT_STATES.has(object.get("fruit", "")):
			placeObject(cell, "fruit", object.fruit)
		elif type == "water" and WATER_LEVELS.has(object.get("water", "")):
			placeObject(cell, "water", object.water)

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

	# 편집 패널
	uiPanel = PanelContainer.new()
	uiPanel.position = Vector2(10, 10)
	ui.add_child(uiPanel)

	var box = VBoxContainer.new()
	box.custom_minimum_size.x = 220
	uiPanel.add_child(box)

	box.add_child(makeLabel("맵 크기", 13))

	var sizeRow = HBoxContainer.new()
	box.add_child(sizeRow)

	widthBox = SpinBox.new()
	widthBox.min_value = MIN_SIZE
	widthBox.max_value = MAX_SIZE
	widthBox.value = mapWidth
	widthBox.custom_minimum_size.x = 64
	sizeRow.add_child(widthBox)

	sizeRow.add_child(makeLabel("x", 13))

	heightBox = SpinBox.new()
	heightBox.min_value = MIN_SIZE
	heightBox.max_value = MAX_SIZE
	heightBox.value = mapHeight
	heightBox.custom_minimum_size.x = 64
	sizeRow.add_child(heightBox)

	var applyButton = makeButton("적용")
	applyButton.pressed.connect(func(): resizeMap(int(widthBox.value), int(heightBox.value)))
	sizeRow.add_child(applyButton)

	box.add_child(HSeparator.new())
	box.add_child(makeLabel("파일 이름 (%s/)" % mapsDir, 13))

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
	clearButton.pressed.connect(func(): newMap(int(widthBox.value), int(heightBox.value)))
	fileRow.add_child(clearButton)

	box.add_child(HSeparator.new())

	toolLabel = makeLabel("", 14)
	box.add_child(toolLabel)

	var help = makeLabel("[1] 바닥  [2] 벽  [0] 플랫폼
[3] 빨강  [4] 파랑  [5] 초록
[6] 시작 지점
[7] 물 가득  [8] 물 높게  [9] 물 낮게
좌클릭 배치 · 우클릭 삭제
휠 줌 · 휠 드래그 이동", 12)
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
	statusLabel = makeLabel("좌클릭 배치 · 우클릭 삭제 · TAB 플레이", 13)
	statusLabel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, 10)
	ui.add_child(statusLabel)

	# 플레이 모드 안내
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

func syncUI():
	widthBox.value = mapWidth
	heightBox.value = mapHeight

func setStatus(text):
	statusLabel.text = text
