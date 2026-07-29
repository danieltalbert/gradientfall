class_name GaitProfile
extends RefCounted
## One named way of moving on two legs — walk, jog, run, sprint, crouch-walk,
## limp — expressed as measurable biomechanics rather than animation curves.
##
## **Why a profile and not a keyframed clip.** Gradientfall generates every
## asset in code (CLAUDE.md § Conventions), so there are no motion-capture
## clips to blend. Instead each gait is a small set of numbers taken from real
## gait analysis — stride length, duty factor, pelvic oscillation — and
## `gait_engine.gd` integrates them into a pose. Two payoffs: gaits blend
## CONTINUOUSLY by speed (no pops at a walk/run threshold, because there is no
## threshold), and a new creature is a new set of numbers, not a new art task.
##
## **Where the numbers come from.** Defaults are human gait-lab figures for a
## ~1.78 m adult: walking cadence near 110 steps/min at 1.4 m/s with a 62% duty
## factor and ~45 mm of pelvic rise; running crossing to a sub-50% duty factor
## (a real flight phase) with the pelvis LOWEST at midstance instead of highest.
## Preserving that inversion is a surprising amount of why running reads as
## running and not as fast walking.
##
## **Architecture.** Pure data + blending; depends only on `anim_math.gd`.
## Authored by `locomotion_profile.gd` per creature and consumed by
## `gait_engine.gd`. See `docs/ARCHITECTURE.md` § "Procedural animation".

## Human-readable name, for debug overlays and the locomotion lab's reports.
var name: String = "walk"

# --- Ground contract --------------------------------------------------------

## Ground speed this gait is authored at, m/s. Blending between profiles is
## keyed on this.
var speed: float = 1.4

## Metres of ground covered by one full cycle (two steps — left and right).
## Together with `speed` this fixes the cadence, so it is the single most
## important number here: `cadence = speed / stride`.
var stride: float = 1.50

## Fraction of the cycle each foot spends planted. Above 0.5 both feet are
## sometimes down (a walk's double support); below 0.5 neither sometimes is
## (a run's flight phase). Crossing 0.5 IS the walk/run transition.
var duty: float = 0.62

# --- Foot swing -------------------------------------------------------------

## Peak clearance of the swinging foot above its plant height, metres.
var step_height: float = 0.075

## Where in the swing the clearance peaks, 0..1. Real feet snap up fast at
## toe-off and glide down to heel-strike, so this sits well before the middle.
var step_peak: float = 0.38

## Ankle pitch range through the step, radians — toes-up at heel-strike,
## toes-down at toe-off. Without it feet land flat and read as stilts.
var foot_roll: float = 0.32

## How far the swinging foot reaches PAST its landing spot before settling
## back, as a fraction of the step. A small overshoot reads as a real reach.
var step_overshoot: float = 0.06

## Distance from the ankle joint back to the heel and forward to the toe, in
## metres — the two levers the body rocks over during a stance.
##
## These are real anatomy, not tuning knobs, and `gait_engine.gd` derives the
## ankle's whole stance trajectory from them by treating the foot as a rigid
## body rotating about whichever end is currently touching the ground. That is
## what makes the contact patch EXACTLY stationary through heel-strike, flat
## foot and toe-off alike: the ankle rises and advances by precisely the amount
## the geometry demands, rather than by a fudge factor that only approximately
## agrees with the ankle roll being animated on top.
var heel_lever: float = 0.060
var toe_lever: float = 0.160

# --- Pelvis -----------------------------------------------------------------

## Vertical pelvis oscillation, metres (peak to centre). Runs at twice the
## cycle frequency — one rise per step.
var pelvis_bob: float = 0.022

## Phase offset of the bob, in cycles. 0.0 puts the pelvis HIGHEST at midstance
## (a walk vaulting over a straight stance leg); 0.5 puts it LOWEST there (a
## run compressing into the stance leg). This is the walk/run inversion.
var pelvis_bob_phase: float = 0.0

## Lateral pelvis shift toward the stance foot, metres. Once per cycle.
var pelvis_sway: float = 0.028

## Constant lowering of the whole body, metres — how crouched this gait is.
var pelvis_drop: float = 0.0

## Transverse pelvic rotation (the hip leading the swing leg), radians.
var pelvis_yaw: float = 0.09

## Frontal-plane pelvic drop toward the SWING side, radians. The Trendelenburg
## dip; small, but its absence is why stiff rigs look like they are on rails.
var pelvis_roll: float = 0.045

# --- Spine and torso --------------------------------------------------------

## Constant forward lean of the torso, radians. Grows with speed — sprinting
## upright is one of the loudest tells of a rig that has never been tuned.
var torso_lean: float = 0.03

## Shoulder-girdle counter-rotation against the pelvis, radians.
var chest_counter: float = 0.10

## How far the chest LAGS the pelvis, in cycles. Real spines transmit rotation
## with a delay; matching them exactly makes the torso read as one rigid block.
var spine_lag: float = 0.09

## Residual head pitch left after the neck stabilises the gaze, radians. Real
## heads are not perfectly stabilised, and perfect stabilisation looks uncanny.
var head_bob: float = 0.012

# --- Arms -------------------------------------------------------------------

## Shoulder flexion amplitude, radians — the arm swing.
var arm_swing: float = 0.42

## Constant shoulder abduction, radians. At speed the arms ride out from the
## body so they clear the torso.
var arm_lift: float = 0.05

## Baseline elbow flexion, radians. Walkers hang near-straight; runners hold
## close to a right angle and keep it there.
var elbow_bend: float = 0.22

## Extra elbow flexion added on the forward half of the swing, radians.
var elbow_swing: float = 0.30

# --- Legs -------------------------------------------------------------------

## Knee flexion at midstance, radians — the loading response that absorbs
## bodyweight. Straight-legged stance is the "marching toy soldier" look.
var stance_knee: float = 0.09

## How far in front of the knee the IK pole sits, metres. Larger values push
## the knees further forward and stop them from wandering toward each other.
var knee_pole_ahead: float = 0.85


## Deep copy — profiles get blended into scratch instances every frame, and
## sharing a preset by reference would let one frame's blend corrupt the preset.
func duplicate_profile() -> GaitProfile:
	var copy: GaitProfile = GaitProfile.new()
	copy.copy_from(self)
	return copy


## Overwrite every field from `other`.
func copy_from(other: GaitProfile) -> void:
	name = other.name
	speed = other.speed
	stride = other.stride
	duty = other.duty
	step_height = other.step_height
	step_peak = other.step_peak
	foot_roll = other.foot_roll
	step_overshoot = other.step_overshoot
	heel_lever = other.heel_lever
	toe_lever = other.toe_lever
	pelvis_bob = other.pelvis_bob
	pelvis_bob_phase = other.pelvis_bob_phase
	pelvis_sway = other.pelvis_sway
	pelvis_drop = other.pelvis_drop
	pelvis_yaw = other.pelvis_yaw
	pelvis_roll = other.pelvis_roll
	torso_lean = other.torso_lean
	chest_counter = other.chest_counter
	spine_lag = other.spine_lag
	head_bob = other.head_bob
	arm_swing = other.arm_swing
	arm_lift = other.arm_lift
	elbow_bend = other.elbow_bend
	elbow_swing = other.elbow_swing
	stance_knee = other.stance_knee
	knee_pole_ahead = other.knee_pole_ahead


## Linear blend of every field, written into `out` to avoid a per-frame
## allocation. `t` of 0 gives `a`, 1 gives `b`.
##
## Every field blends linearly INCLUDING `duty`, which is what makes the
## walk-to-run transition continuous: duty slides through 0.5 rather than
## jumping, so double-support shortens to nothing and the flight phase opens up
## over a few tenths of a second the way a real gait transition does.
static func blend_into(out: GaitProfile, a: GaitProfile, b: GaitProfile,
		t: float) -> void:
	var k: float = clampf(t, 0.0, 1.0)
	out.name = a.name if k < 0.5 else b.name
	out.speed = lerpf(a.speed, b.speed, k)
	out.stride = lerpf(a.stride, b.stride, k)
	out.duty = lerpf(a.duty, b.duty, k)
	out.step_height = lerpf(a.step_height, b.step_height, k)
	out.step_peak = lerpf(a.step_peak, b.step_peak, k)
	out.foot_roll = lerpf(a.foot_roll, b.foot_roll, k)
	out.step_overshoot = lerpf(a.step_overshoot, b.step_overshoot, k)
	out.heel_lever = lerpf(a.heel_lever, b.heel_lever, k)
	out.toe_lever = lerpf(a.toe_lever, b.toe_lever, k)
	out.pelvis_bob = lerpf(a.pelvis_bob, b.pelvis_bob, k)
	out.pelvis_bob_phase = lerpf(a.pelvis_bob_phase, b.pelvis_bob_phase, k)
	out.pelvis_sway = lerpf(a.pelvis_sway, b.pelvis_sway, k)
	out.pelvis_drop = lerpf(a.pelvis_drop, b.pelvis_drop, k)
	out.pelvis_yaw = lerpf(a.pelvis_yaw, b.pelvis_yaw, k)
	out.pelvis_roll = lerpf(a.pelvis_roll, b.pelvis_roll, k)
	out.torso_lean = lerpf(a.torso_lean, b.torso_lean, k)
	out.chest_counter = lerpf(a.chest_counter, b.chest_counter, k)
	out.spine_lag = lerpf(a.spine_lag, b.spine_lag, k)
	out.head_bob = lerpf(a.head_bob, b.head_bob, k)
	out.arm_swing = lerpf(a.arm_swing, b.arm_swing, k)
	out.arm_lift = lerpf(a.arm_lift, b.arm_lift, k)
	out.elbow_bend = lerpf(a.elbow_bend, b.elbow_bend, k)
	out.elbow_swing = lerpf(a.elbow_swing, b.elbow_swing, k)
	out.stance_knee = lerpf(a.stance_knee, b.stance_knee, k)
	out.knee_pole_ahead = lerpf(a.knee_pole_ahead, b.knee_pole_ahead, k)


# --- Human presets ----------------------------------------------------------
# Authored for a 1.78 m adult. `locomotion_profile.gd` rescales these for
# creatures of other sizes rather than duplicating the table.

## Standing-still reference. Stride and duty still matter: they are what the
## blend interpolates toward as a character slows to a stop, so a bad idle
## profile shows up as a stutter in the last half-step before standing.
static func human_idle() -> GaitProfile:
	var p: GaitProfile = GaitProfile.new()
	p.name = "idle"
	p.speed = 0.0
	p.stride = 0.90
	p.duty = 0.75
	p.step_height = 0.018
	p.step_peak = 0.42
	p.foot_roll = 0.10
	p.step_overshoot = 0.0
	p.pelvis_bob = 0.004
	p.pelvis_bob_phase = 0.0
	p.pelvis_sway = 0.012
	p.pelvis_drop = 0.0
	p.pelvis_yaw = 0.02
	p.pelvis_roll = 0.012
	p.torso_lean = 0.0
	p.chest_counter = 0.02
	p.spine_lag = 0.10
	p.head_bob = 0.004
	p.arm_swing = 0.06
	p.arm_lift = 0.0
	p.elbow_bend = 0.16
	p.elbow_swing = 0.05
	p.stance_knee = 0.05
	p.knee_pole_ahead = 0.85
	return p


## Unhurried walk. 1.4 m/s at a 1.5 m stride is ~112 steps/min — the textbook
## comfortable human cadence.
static func human_walk() -> GaitProfile:
	var p: GaitProfile = GaitProfile.new()
	p.name = "walk"
	p.speed = 1.40
	p.stride = 1.50
	p.duty = 0.62
	p.step_height = 0.075
	p.step_peak = 0.38
	p.foot_roll = 0.32
	p.step_overshoot = 0.06
	p.pelvis_bob = 0.022
	p.pelvis_bob_phase = 0.0     # highest at midstance: vaulting
	p.pelvis_sway = 0.030
	p.pelvis_drop = 0.0
	p.pelvis_yaw = 0.09
	p.pelvis_roll = 0.045
	p.torso_lean = 0.025
	p.chest_counter = 0.10
	p.spine_lag = 0.09
	p.head_bob = 0.012
	p.arm_swing = 0.42
	p.arm_lift = 0.03
	p.elbow_bend = 0.22
	p.elbow_swing = 0.30
	p.stance_knee = 0.09
	p.knee_pole_ahead = 0.85
	return p


## Brisk jog — the first gait with a genuine flight phase (duty below 0.5).
static func human_jog() -> GaitProfile:
	var p: GaitProfile = GaitProfile.new()
	p.name = "jog"
	p.speed = 3.20
	p.stride = 2.30
	p.duty = 0.44
	p.step_height = 0.155
	p.step_peak = 0.34
	p.foot_roll = 0.40
	p.step_overshoot = 0.05
	p.pelvis_bob = 0.042
	p.pelvis_bob_phase = 0.5     # lowest at midstance: spring compression
	p.pelvis_sway = 0.022
	p.pelvis_drop = 0.015
	p.pelvis_yaw = 0.12
	p.pelvis_roll = 0.055
	p.torso_lean = 0.085
	p.chest_counter = 0.16
	p.spine_lag = 0.07
	p.head_bob = 0.022
	p.arm_swing = 0.70
	p.arm_lift = 0.10
	p.elbow_bend = 0.95
	p.elbow_swing = 0.34
	p.stance_knee = 0.22
	p.knee_pole_ahead = 0.95
	return p


## Committed run.
static func human_run() -> GaitProfile:
	var p: GaitProfile = GaitProfile.new()
	p.name = "run"
	p.speed = 5.60
	p.stride = 3.20
	p.duty = 0.36
	p.step_height = 0.235
	p.step_peak = 0.31
	p.foot_roll = 0.46
	p.step_overshoot = 0.04
	p.pelvis_bob = 0.055
	p.pelvis_bob_phase = 0.5
	p.pelvis_sway = 0.016
	p.pelvis_drop = 0.030
	p.pelvis_yaw = 0.15
	p.pelvis_roll = 0.060
	p.torso_lean = 0.145
	p.chest_counter = 0.20
	p.spine_lag = 0.06
	p.head_bob = 0.028
	p.arm_swing = 0.92
	p.arm_lift = 0.16
	p.elbow_bend = 1.28
	p.elbow_swing = 0.30
	p.stance_knee = 0.30
	p.knee_pole_ahead = 1.05
	return p


## Flat-out sprint — knees high, torso well forward, arms driving.
static func human_sprint() -> GaitProfile:
	var p: GaitProfile = GaitProfile.new()
	p.name = "sprint"
	p.speed = 7.50
	p.stride = 3.95
	p.duty = 0.29
	p.step_height = 0.320
	p.step_peak = 0.29
	p.foot_roll = 0.50
	p.step_overshoot = 0.03
	p.pelvis_bob = 0.062
	p.pelvis_bob_phase = 0.5
	p.pelvis_sway = 0.012
	p.pelvis_drop = 0.042
	p.pelvis_yaw = 0.18
	p.pelvis_roll = 0.062
	p.torso_lean = 0.200
	p.chest_counter = 0.24
	p.spine_lag = 0.05
	p.head_bob = 0.032
	p.arm_swing = 1.15
	p.arm_lift = 0.21
	p.elbow_bend = 1.45
	p.elbow_swing = 0.26
	p.stance_knee = 0.36
	p.knee_pole_ahead = 1.15
	return p


## Crouched movement — short shuffling stride, body low, arms tucked and quiet.
static func human_crouch_walk() -> GaitProfile:
	var p: GaitProfile = GaitProfile.new()
	p.name = "crouch_walk"
	p.speed = 1.70
	p.stride = 1.05
	p.duty = 0.68
	p.step_height = 0.050
	p.step_peak = 0.40
	p.foot_roll = 0.18
	p.step_overshoot = 0.03
	p.pelvis_bob = 0.012
	p.pelvis_bob_phase = 0.0
	p.pelvis_sway = 0.024
	p.pelvis_drop = 0.340
	p.pelvis_yaw = 0.06
	p.pelvis_roll = 0.030
	p.torso_lean = 0.230
	p.chest_counter = 0.06
	p.spine_lag = 0.10
	p.head_bob = 0.008
	p.arm_swing = 0.20
	p.arm_lift = 0.06
	p.elbow_bend = 0.85
	p.elbow_swing = 0.12
	p.stance_knee = 0.70
	p.knee_pole_ahead = 1.05
	return p


## Crouched and still.
static func human_crouch_idle() -> GaitProfile:
	var p: GaitProfile = GaitProfile.new()
	p.copy_from(human_crouch_walk())
	p.name = "crouch_idle"
	p.speed = 0.0
	p.stride = 0.80
	p.duty = 0.80
	p.step_height = 0.014
	p.pelvis_bob = 0.003
	p.pelvis_sway = 0.008
	p.pelvis_yaw = 0.015
	p.pelvis_roll = 0.010
	p.arm_swing = 0.04
	p.elbow_swing = 0.03
	return p
