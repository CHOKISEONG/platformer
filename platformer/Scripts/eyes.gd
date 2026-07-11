extends Node2D

# 플레이어의 눈동자.
# 어둠 상태(glowing = true)에서는 가산 블렌드로 밝게 빛나며 깜빡이고,
# 밝아진 뒤(glowing = false)에는 빛나지 않는 어두운 눈동자로 그려진다.

var glowing = true
var time = 0.0

@onready var glowMaterial = material

func _process(delta):

	if !glowing:
		return

	time += delta
	queue_redraw()

func setGlow(enabled):

	glowing = enabled

	if enabled:
		material = glowMaterial
	else:
		material = null

	queue_redraw()

func _draw():

	if glowing:

		var glow = 0.8 + sin(time * 3) * 0.2
		var eyeColor = Color(1, 0.95, 0.7, glow)

		# 은은한 광륜 + 눈동자
		draw_circle(Vector2(-2.5, -2), 2.4, Color(eyeColor.r, eyeColor.g, eyeColor.b, glow * 0.25))
		draw_circle(Vector2( 2.5, -2), 2.4, Color(eyeColor.r, eyeColor.g, eyeColor.b, glow * 0.25))
		draw_circle(Vector2(-2.5, -2), 1.2, eyeColor)
		draw_circle(Vector2( 2.5, -2), 1.2, eyeColor)

	else:

		var eyeColor = Color(0.1, 0.08, 0.12)

		draw_circle(Vector2(-2.5, -2), 1.2, eyeColor)
		draw_circle(Vector2( 2.5, -2), 1.2, eyeColor)
