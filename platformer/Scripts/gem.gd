extends Area2D

# Public

@onready var sprite = $Sprite

@export var gemTexture: Texture2D

# Private

var collected = false
var time = 0.0

# Methods

func _ready():

	if gemTexture:
		sprite.texture = gemTexture

	time = position.x * 0.05 # Desync bobbing between gems

func _process(delta):

	time += delta
	sprite.position.y = sin(time * 4) * 1.5

func _on_body_entered(body):

	if collected: return

	if body.is_in_group("player"):
		collected = true
		get_tree().call_group("ui", "addGem")
		queue_free()
