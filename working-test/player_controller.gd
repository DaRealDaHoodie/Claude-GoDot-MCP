extends CharacterBody3D

func _ready():
	print("[PlayerController] Ready")

func _on_body_entered(body: Node) -> void:
	print("[PlayerController] Body entered: ", body.name)

func _on_rigid_sleep_changed() -> void:
	print("[PlayerController] Rigid body sleep changed")
