extends Node2D

# 초록 인간의 얼굴. 표정에 따라 눈·눈썹·볼을 직접 그린다 (eyes.gd와 같은 방식).
# 표정은 부모(green_human.gd)가 setMood로 바꾼다.

# 표정 종류 — Expression은 Godot 내장 클래스라 못 쓴다
enum Mood { NORMAL, HUG, ANGRY }

# 플레이어의 밝은 상태 눈동자와 같은 색 (eyes.gd 참고)
const EYE_COLOR = Color(0.1, 0.08, 0.12)
const BLUSH_COLOR = Color(1, 0.5, 0.55, 0.35)

var mood = Mood.NORMAL

func setMood(newMood):

	mood = newMood
	queue_redraw()

func _draw():

	match mood:

		Mood.NORMAL:

			draw_circle(Vector2(-2.5, -2), 1.2, EYE_COLOR)
			draw_circle(Vector2(2.5, -2), 1.2, EYE_COLOR)

		Mood.HUG:

			# 웃으며 감은 눈(위로 볼록한 호) + 발그레한 볼
			drawClosedEye(Vector2(-2.5, -2))
			drawClosedEye(Vector2(2.5, -2))
			draw_circle(Vector2(-4.5, 0.5), 1.4, BLUSH_COLOR)
			draw_circle(Vector2(4.5, 0.5), 1.4, BLUSH_COLOR)

		Mood.ANGRY:

			# 치켜뜬 눈 + 미간 쪽으로 내려오는 눈썹
			draw_circle(Vector2(-2.5, -1.5), 1.2, EYE_COLOR)
			draw_circle(Vector2(2.5, -1.5), 1.2, EYE_COLOR)
			draw_line(Vector2(-4, -4.5), Vector2(-1, -3), EYE_COLOR, 1.0)
			draw_line(Vector2(1, -3), Vector2(4, -4.5), EYE_COLOR, 1.0)

func drawClosedEye(center):

	# 각도 PI~TAU 구간이 y가 음수인 위쪽 반원 — ∩ 모양의 감은 눈이 된다
	draw_arc(center + Vector2(0, 0.5), 1.6, PI + 0.4, TAU - 0.4, 6, EYE_COLOR, 1.0)
