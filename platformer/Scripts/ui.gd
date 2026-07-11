extends CanvasLayer

# Public

@onready var count = $Counter/Count

# Private

var gems = 0

# Methods

func addGem():

	gems += 1
	count.text = str(gems)
