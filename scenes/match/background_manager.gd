class_name BackgroundManager
extends Node
## Manages the animated sky background environment.
## Call set_environment() to switch between the three location themes.
## The default environment on startup is MEADOW.

enum EnvironmentType { MEADOW, OCEAN, VOLCANIC }

const MEADOW_SHADER   := preload("res://assets/shaders/sky_meadow.gdshader")
const OCEAN_SHADER    := preload("res://assets/shaders/sky_ocean.gdshader")
const VOLCANIC_SHADER := preload("res://assets/shaders/sky_volcanic.gdshader")

var current_environment: EnvironmentType = EnvironmentType.MEADOW

var _sky_material: ShaderMaterial
var _sky: Sky
var _env: Environment

@onready var _world_env: WorldEnvironment = $"../WorldEnvironment"


func _ready() -> void:
	_sky_material = ShaderMaterial.new()
	_sky = Sky.new()
	_sky.sky_material = _sky_material

	_env = Environment.new()
	_env.background_mode = Environment.BG_SKY
	_env.sky = _sky
	## Subtle sky-tinted ambient so board objects pick up environment colour.
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	_env.ambient_light_sky_contribution = 0.25

	_world_env.environment = _env
	set_environment(EnvironmentType.MEADOW)


## Switch the background to one of the three available environments.
func set_environment(env_type: EnvironmentType) -> void:
	current_environment = env_type
	match env_type:
		EnvironmentType.MEADOW:
			_sky_material.shader = MEADOW_SHADER
		EnvironmentType.OCEAN:
			_sky_material.shader = OCEAN_SHADER
		EnvironmentType.VOLCANIC:
			_sky_material.shader = VOLCANIC_SHADER
