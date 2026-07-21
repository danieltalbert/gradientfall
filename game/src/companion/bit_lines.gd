class_name BitLines
extends RefCounted
## Bit's voice, kept as data so the companion logic stays about behavior.
##
## Canon (WORLDBOOK Part IV): Bit is curious, loyal, a little vain about being
## luminous, afraid of deep water, and names things eagerly. All-ages, warm,
## wry. The single "Hey! Listen!" the whole game is allowed lives in the Citadel
## — it must NEVER appear here.

const GREETING: Array[String] = [
	"There you are, Kern! Try not to wander off without your light.",
	"Up and glowing! Well — I'm glowing. You're mostly just up.",
	"Morning, Vaultborn. The meadow's been waiting, and so have I.",
]

const IDLE: Array[String] = [
	"I could light a whole cellar, you know. Not that anyone's asked.",
	"Do you ever wonder who tended all this before the town did? I do. Constantly.",
	"If you ever get lost, just find the brightest thing nearby. That's me.",
	"The bees down by the mill keep a very strict schedule. I admire that.",
	"You walk, I hover. Between us, we make one complete adventurer.",
	"The iris out here grow with the tidiest little measurements. Collectors go silly for them.",
	"I'm not saying I'm the prettiest thing in this field. I'm just not saying I'm not.",
]

const HINT: Array[String] = [
	"Anything that looks interesting from far off usually is. Out here, that's a promise.",
	"See something worth a closer look? I'll name it — naming's my favorite part.",
	"Tokens in your pocket, questions in the town. Somebody always needs a hand.",
]

const WATER_FEAR: Array[String] = [
	"Nope. Nope nope. You paddle — I'll supervise from up here, thank you.",
	"Deep water and I have an understanding: I stay dry, it stays quiet.",
	"Careful at that edge! If I go out, I go OUT, and I don't mean the door.",
]

const QUIZ_CORRECT: Array[String] = [
	"Yes! I knew you had it. Mostly. I knew it mostly.",
	"Right again. Keep this up and you'll be lighting your own way.",
]

const QUIZ_WRONG: Array[String] = [
	"Close! Wrong, but close. We'll circle back to those.",
	"Hm. We'll call that one a rehearsal. On to the next.",
]

const ITEM_PICKUP: Array[String] = [
	"Ooh, a keeper. Into the pack it goes.",
	"That'll be worth something to the right person.",
]

# The knowledge channel (milestone 7): Kern calls Bit in to combine power,
# and questions forge the strike. Start / it lands / it fizzles.
const CHANNEL_START: Array[String] = [
	"Together, then! Think fast and think TRUE.",
	"Focus! I'll hold the light steady — you hold the answers.",
	"Combining power! Don't overthink it. Or under-think it.",
]

const CHANNEL_SUCCESS: Array[String] = [
	"THAT'S the stuff! Did you feel that?!",
	"Ha! We are unreasonably good at this.",
]

const CHANNEL_FIZZLE: Array[String] = [
	"Whoop — lost the thread. We'll catch it next time.",
	"The spark slipped. Shake it off, Kern.",
]


static func any(pool: Array[String]) -> String:
	if pool.is_empty():
		return ""
	return pool[randi() % pool.size()]
