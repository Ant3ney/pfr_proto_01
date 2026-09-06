@tool
class_name PlayerCharacter
extends PFRCharacter

## A PFRCharacter configured to use player input.

const DEFAULT_ART_PACK: PFRCharacterArtAssetPack = preload(
	"res://game/actors/character/art_packs/za_city_driver.tres"
)


func _init() -> void:
	controller = PlayerController.new()
	character_art_asset_pack = DEFAULT_ART_PACK
