-- InputController: desktop bindings. Hotkeys come from GameSettings (rebindable in the
-- SETTINGS menu); the defaults are:
--   WASD        move (Roblox character controls, camera-relative) - fixed
--   Left click  basic attack toward cursor (hold to keep attacking) - fixed
--   Q           class ability
--   SPACE/E/R   active items from mythic slots 3 / 1 / 2 (dynamic, follow the slots)
--   Right click boot skill (the separate boot slot)
--   (Shop B, potion H and the Royale gear panel I are handled by ShopUI / RoyaleUI.)
--   While choosing a unit target: left click confirms; the same key again or Esc cancels
--   (the boots key also cancels an item target selection).

-- Services
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local GameSettings = require(script.Parent:WaitForChild("GameSettings"))

-- Constants
local COMBAT_ACTIONS = { Ability = "Q", ItemE = "E", ItemR = "R", ItemSpace = "SPACE", Boots = "M2" }

-- State
local InputController = {}
local CombatController = nil

local function runAction(action)
	local slot = COMBAT_ACTIONS[action]
	if not slot then
		return false
	end
	if slot == "M2" and CombatController.Targeting and CombatController.Targeting.Key ~= "M2" then
		CombatController.CancelTargeting()
		return true
	end
	CombatController.TryAbility(slot) -- pressing the same key again cancels its targeting
	return true
end

-- Public API
function InputController.Init(combatController)
	CombatController = combatController
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or GameSettings.Capturing then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if CombatController.Targeting then
				CombatController.ConfirmTarget()
				return
			end
			CombatController.SetAttackHeld(true)
			CombatController.TryAttack()
			return
		end
		if input.KeyCode == Enum.KeyCode.Escape then
			CombatController.CancelTargeting()
			return
		end
		if input.KeyCode == Enum.KeyCode.Space then
			return -- handled by the Space action below (it also blocks the default jump)
		end
		runAction(GameSettings.ActionFor(input))
	end)
	-- Space is Roblox's jump key: bind it above the default jump so it never jumps, and run
	-- whatever combat action is bound to it (SPACE item by default)
	ContextActionService:BindActionAtPriority("RuinfallSpaceKey", function(_, state, input)
		if state == Enum.UserInputState.Begin and not UserInputService:GetFocusedTextBox() and not GameSettings.Capturing then
			runAction(GameSettings.ActionFor(input))
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value + 10, Enum.KeyCode.Space)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			CombatController.SetAttackHeld(false)
		end
	end)
	UserInputService.WindowFocusReleased:Connect(function()
		CombatController.SetAttackHeld(false)
	end)
end

return InputController
