extends CanvasLayer

# 화면 중앙 조작 안내. 첫 과일을 먹으면 점프 안내로 바꾼 뒤 서서히 사라진다.

@onready var hint = $Hint

func _on_player_state_changed(state):

	if state == ColorPlayer.ColorState.DARK:
		return

	hint.text = "A, D  +  Space"

	var tween = create_tween()
	tween.tween_interval(2.0)
	tween.tween_property(hint, "modulate:a", 0.0, 1.5)
