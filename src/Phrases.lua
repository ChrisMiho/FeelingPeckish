local _, ns = ...

-- The silly phrases and a picker that never repeats the previous phrase.
-- Pure: no WoW API. The list mirrors PRD.md section 5; keep the two in step.

local Phrases = {}
ns.Phrases = Phrases

Phrases.list = {
	"Your Well Fed just wandered off. Probably to find a snack.",
	"Buff gone. Stomach now filing a formal complaint.",
	"The food buff has left the building. Bring cheese.",
	"Your tummy rumbled loud enough to pull the next pack.",
	"Well Fed? More like Well Faded. Eat something.",
	"A murloc heard your stomach and replied: Mrglglgl.",
	"Snack o'clock. The clock is never wrong.",
	"You are now at 0% snack. Please recharge.",
	"Your stomach has entered combat.",
	"Somewhere, a mage is conjuring bread you are not eating.",
	"Your buff expired. So did your patience. Eat.",
	"Feast time? Feast time. Someone drop a fish feast.",
	"Hunger debuff applied. Duration: until you eat.",
	"That growl wasn't a worgen. That was you.",
	"Your inner gnome demands a sandwich.",
	"Warning: snack reserves critically low.",
	"Your stomach just rolled Need on everything.",
	"No buff, no glory. Find a picnic.",
	"Even the Defias take a lunch break. Just saying.",
	"Your belly is casting Rumble. It cannot be interrupted.",
	"Peckish detected. Deploy the cheese wheel.",
	"A wild hunger appears! It's super effective.",
	"The bread is calling. Answer the bread.",
	"Your Well Fed buff has respawned... somewhere else.",
	"Out of food buff. Into snack territory.",
	"Stomach aggro lost. Pull it back with pie.",
	'Grumble grumble. That\'s Common for "feed me."',
	"Your stats are fine. Your snack stats are not.",
	"Have you tried eating it? The food. Eat the food.",
	"The innkeeper would be very disappointed in you.",
	"Hungry like a murloc at a fish market.",
	"Even conjured muffins look tempting right now.",
	"Your belly just started its own guild. It's called Hungry.",
	"Sit down. Unpack. Eat a mutton chop.",
	"Time to raid the fridge. Need, not greed.",
	"Your belly bar is empty. No addon can fill it.",
	"Pro tip: food goes in the face.",
	'Your stomach just whispered you. It said "rude."',
	"Running on empty. Running on snacks would be better.",
	"The cheese misses you. Go say hi.",
	"Snack break! Doctor's orders. The doctor is a pandaren.",
	"Your Well Fed fell off. Pick it up with a fork.",
	"Feeling peckish? You look peckish. Eat a cracker.",
	"Your hunger has reached raid-wipe levels.",
	"Tasty fish? Spiced bread? Literally anything? Go.",
	"A goblin would sell you lunch right now. At a markup.",
	"Remember snacks? Snacks remember you.",
	"Your stomach is now louder than the raid leader.",
	"Buff down! Repeat, buff down! Requesting crumbs!",
	"Somebody pass the Moonberry Juice and a sandwich.",
}

-- Returns a function that yields a random phrase, never the same one twice
-- in a row. rand(n) must return an integer in 1..n (defaults to math.random).
function Phrases.newPicker(rand, list)
	rand = rand or math.random
	list = list or Phrases.list
	local last
	return function()
		local count = #list
		local index
		if last == nil or count < 2 then
			index = rand(count)
		else
			-- Pick from the other count - 1 slots, then step over the last one.
			index = rand(count - 1)
			if index >= last then
				index = index + 1
			end
		end
		last = index
		return list[index]
	end
end
