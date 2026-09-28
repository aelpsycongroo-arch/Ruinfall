--[[
	AnimationEvents - client-side "animation markers" for audio (and anything else).

	Procedural animation controllers fire named events at the exact frame something happens,
	so sounds line up with the motion instead of a guessed delay:
		AnimationEvents.Fire("Footstep", model, { Volume = 1 })   -- a foot plants
		AnimationEvents.Fire("AttackHit", model)                    -- strike frame of an attack
	Listeners:  AnimationEvents.Event:Connect(function(name, model, data) ... end)
	For Animator-based (keyframe) animations use AnimationTrack:GetMarkerReachedSignal(name)
	and forward it here with the same event names.
]]

local AnimationEvents = {}
local bindable = Instance.new("BindableEvent")
AnimationEvents.Event = bindable.Event

function AnimationEvents.Fire(name, model, data)
	bindable:Fire(name, model, data)
end

return AnimationEvents
