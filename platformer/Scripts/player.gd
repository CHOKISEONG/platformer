extends CharacterBody2D

# Public

@onready var sprite = $Sprite
@onready var camera = $Camera
@onready var dust   = $Dust

@export var movementSpeed = 10
@export var gravityPower = 10
@export var jumpPower = 20

@export var projectile: PackedScene

# Private

var walkVelocity = Vector2(0, 0)
var movementVelocity = Vector2(0, 0)
var gravity = 0

var doubleJump = true
var previouslyFloored = false
var previouslyDestroyed = false

var cameraTarget = 0.5

var initialPosition

# Methods

func _ready():

	initialPosition = position

func _physics_process(delta):

	applyControls()
	applyGravity()
	applyAnimation()

	# Out of bounds

	if position.y > 200 or Input.is_action_just_pressed("reset"):
		position = initialPosition

	# Apply movement

	walkVelocity = walkVelocity.lerp(movementVelocity * 10, delta * 15)
	velocity = walkVelocity + Vector2(0, gravity)
	move_and_slide()

	# Effects

	sprite.scale = sprite.scale.lerp(Vector2(1, 1), delta * 8)

	if is_on_floor() and !previouslyFloored:
		sprite.scale = Vector2(1.25, 0.75)

	previouslyFloored = is_on_floor()

	if !is_on_floor() and (abs(walkVelocity.x) > 20 or abs(walkVelocity.y) > 20):
		dust.emitting = true
	else:
		dust.emitting = false

# Player controls

func applyControls():

	movementVelocity = Vector2(0, 0)

	if Input.is_action_pressed("left"):

		movementVelocity.x = -movementSpeed
		sprite.flip_h = true

	elif Input.is_action_pressed("right"):

		movementVelocity.x = movementSpeed
		sprite.flip_h = false

	if Input.is_action_just_pressed("jump"):

		if is_on_floor():

			jump(1)
			doubleJump = true

		elif doubleJump:

			jump(1)
			doubleJump = false

	if Input.is_action_just_pressed("shoot"):
		shoot()

# Apply gravity and jumping

func applyGravity():

	gravity += gravityPower

	if gravity > 0 and is_on_floor():
		gravity = 10
		previouslyDestroyed = false

	# 상승 중에만 적용 — 하강 중에도 0으로 리셋하면 천장에 붙어 미끄러진다
	if is_on_ceiling() and gravity < 0: gravity = 0

func jump(multiplier):

	gravity = -jumpPower * multiplier * 10
	sprite.scale = Vector2(0.5, 1.5)

func shoot():

	var _projectile = projectile.instantiate()
	get_tree().root.add_child(_projectile)

	if !sprite.flip_h:
		_projectile.direction = 1
		_projectile.position = position + Vector2( 8, 2) # Projectile spawn position
		movementVelocity.x = -movementSpeed * 2 # Knockback
	else:
		_projectile.position = position + Vector2(-8, 2) # Projectile spawn position
		movementVelocity.x = movementSpeed * 2 # Knockback

	sprite.scale = Vector2(0.75, 1.25)

# Set animations

func applyAnimation():

	if is_on_floor():
		if abs(walkVelocity.x) > 60:
			sprite.play("walk")
		else:
			sprite.play("idle")
	else:
		sprite.play("jump")
