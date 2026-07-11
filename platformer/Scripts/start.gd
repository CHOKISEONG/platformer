extends Node2D

# 시작 씬 연출: 첫 보석을 먹으면 어둠에 잠겨 있던 맵을 즉시 밝힌다.

@onready var tileMap = $TileMap
@onready var background = $Background

var lit = false

func _on_player_state_changed(state):

	if state == ColorPlayer.ColorState.DARK or lit:
		return

	lit = true

	tileMap.modulate = Color(1, 1, 1)
	background.color = Color(0.16, 0.15, 0.22)
