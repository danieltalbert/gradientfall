class_name KernBoneMap
extends RefCounted
## Bridges Kern's procedural animation to an imported base-mesh rig.
##
## `kern_visual.gd` drives bones by the names the code-built skeleton uses
## (Hips, Chest, UpperArmR, ...). An imported MPFB/MakeHuman character uses the
## **GameEngine** rig instead — 53 deform bones with Unreal-style names
## (pelvis, spine_01, upperarm_r, ...). This maps one onto the other so the
## same gait / idle / combat code drives either body, and so the code-built
## gear (cloak, belt, boots, sword, hand-mark) attaches to the right joints.
##
## Lookup is resolved once against the actual skeleton, and every entry is
## optional: a rig missing a bone simply doesn't get driven, so a slightly
## different export still animates instead of erroring.

## Our animation name -> candidate names on an imported rig, best first.
## Several of ours collapse onto the same spine chain; that's intentional —
## the GameEngine rig has three spine joints where we author two.
const CANDIDATES: Dictionary = {
	"Hips": ["pelvis", "Hips", "hips", "mixamorig:Hips"],
	"Spine": ["spine_01", "Spine", "spine", "mixamorig:Spine"],
	"Chest": ["spine_03", "spine_02", "Chest", "chest", "mixamorig:Spine2"],
	"Neck": ["neck_01", "Neck", "neck", "mixamorig:Neck"],
	"Head": ["head", "Head", "mixamorig:Head"],

	"ClavicleL": ["clavicle_l", "shoulder_l", "LeftShoulder", "mixamorig:LeftShoulder"],
	"UpperArmL": ["upperarm_l", "LeftArm", "mixamorig:LeftArm"],
	"ForearmL": ["lowerarm_l", "forearm_l", "LeftForeArm", "mixamorig:LeftForeArm"],
	"HandL": ["hand_l", "LeftHand", "mixamorig:LeftHand"],

	"ClavicleR": ["clavicle_r", "shoulder_r", "RightShoulder", "mixamorig:RightShoulder"],
	"UpperArmR": ["upperarm_r", "RightArm", "mixamorig:RightArm"],
	"ForearmR": ["lowerarm_r", "forearm_r", "RightForeArm", "mixamorig:RightForeArm"],
	"HandR": ["hand_r", "RightHand", "mixamorig:RightHand"],

	"ThighL": ["thigh_l", "LeftUpLeg", "mixamorig:LeftUpLeg"],
	"ShinL": ["calf_l", "shin_l", "LeftLeg", "mixamorig:LeftLeg"],
	"FootL": ["foot_l", "LeftFoot", "mixamorig:LeftFoot"],

	"ThighR": ["thigh_r", "RightUpLeg", "mixamorig:RightUpLeg"],
	"ShinR": ["calf_r", "shin_r", "RightLeg", "mixamorig:RightLeg"],
	"FootR": ["foot_r", "RightFoot", "mixamorig:RightFoot"],
}

## Cloak bones don't exist on a body rig — the cloak is code-built, so its
## chain is appended to the imported skeleton at runtime and hangs off Chest.
const APPENDED_BONES: Array[String] = ["CloakA", "CloakB", "CloakC"]


## Resolve { our_name: bone_index } against a real skeleton. Names we can't
## find are simply omitted (the animation skips them).
static func resolve(skeleton: Skeleton3D) -> Dictionary:
	var out: Dictionary = {}
	for our_name in CANDIDATES:
		var idx: int = -1
		for candidate in (CANDIDATES[our_name] as Array):
			idx = skeleton.find_bone(String(candidate))
			if idx >= 0:
				break
		if idx >= 0:
			out[our_name] = idx
	return out


## True if the skeleton looks like a usable humanoid (has the joints the gait
## and gear attachment actually need).
static func is_usable(bones: Dictionary) -> bool:
	for required in ["Hips", "Head", "UpperArmL", "UpperArmR", "ThighL", "ThighR"]:
		if not bones.has(required):
			return false
	return true


## Human-readable report of what mapped — printed once on load so a mismatched
## export is obvious in the output panel instead of silently half-animating.
static func report(skeleton: Skeleton3D, bones: Dictionary) -> String:
	var missing: Array[String] = []
	for our_name in CANDIDATES:
		if not bones.has(our_name):
			missing.append(String(our_name))
	var text: String = "KernBoneMap: matched %d/%d bones on '%s' (%d total)" % [
		bones.size(), CANDIDATES.size(), skeleton.name, skeleton.get_bone_count()]
	if not missing.is_empty():
		text += " | unmapped: " + ", ".join(missing)
	return text
