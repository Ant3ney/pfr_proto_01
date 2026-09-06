@tool
extends RefCounted

enum Profile {
	NONE,
	MESH,
	BOX,
	TRUNK,
}

const COLLISIONLESS_ASSET_IDS := {
	# Thin ground decoration should use the supporting terrain's collision.
	"field_item401": true,
	"t1_lb_cracked_ground": true,
	# Grass and flowers are deliberately soft/pass-through dressing.
	"t1_pl001": true,
	"t1_pl002": true,
	"t1_pl018": true,
	"t1_pl019": true,
	"t1_pl020": true,
	"t1_pl021": true,
	"t1_pl023": true,
}

const BOX_ASSET_IDS := {
	# These volumes should block the player without colliding against every leaf plane.
	"t1_pl003": true,
	"t1_pl011": true,
	"t1_pl012": true,
	"t1_pl013": true,
	"t1_pl014": true,
	"t1_pl022": true,
	"t1_pl032": true,
	"t1_pl039": true,
}

const TRUNK_ASSET_IDS := {
	# Trunk/central-stem volumes keep canopies and branches pass-through.
	"t1_pl009": true,
	"t1_pl010": true,
	"t1_pl015": true,
	"t1_pl024": true,
	"t1_pl025": true,
	"t1_pl033": true,
	"t1_pl035": true,
}


static func profile_for_asset(asset_id: String) -> Profile:
	if asset_id.ends_with("_water") or COLLISIONLESS_ASSET_IDS.has(asset_id):
		return Profile.NONE
	if BOX_ASSET_IDS.has(asset_id):
		return Profile.BOX
	if TRUNK_ASSET_IDS.has(asset_id):
		return Profile.TRUNK
	return Profile.MESH


static func profile_name(profile: Profile) -> String:
	match profile:
		Profile.NONE:
			return "Pass-through decoration"
		Profile.BOX:
			return "Simplified solid volume"
		Profile.TRUNK:
			return "Simplified trunk volume"
		_:
			return "Accurate static mesh"


static func asset_profile_name(asset_id: String) -> String:
	return profile_name(profile_for_asset(asset_id))
