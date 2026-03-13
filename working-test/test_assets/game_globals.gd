extends Node

const VERSION = "0.2.0"
var score: int = 0
var lives: int = 3

func reset() -> void:
	score = 0
	lives = 3
	print("[GameGlobals] Reset to defaults")

func add_score(points: int) -> void:
	score += points
	print("[GameGlobals] Score: ", score)
