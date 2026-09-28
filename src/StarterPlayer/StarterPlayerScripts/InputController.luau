-- InputController: desktop bindings.
--   WASD        move (Roblox character controls, camera-relative)
--   Left click  basic attack toward cursor (hold to keep attacking)
--   Q           signature ability
--   E / R       item abilities from Mythic slot 1 / slot 2 (dynamic, follow the slots)
--   Right click boot skill (the separate boot slot) - movement is WASD only
--   B           item shop (ShopUI)
--   While choosing a unit target: left click confirms; the same key again or Esc cancels
--   (right click also cancels an E/R target selection).

-- Services
local UserInputService = game:GetService("UserInputService")

-- State
local InputController = {}
local CombatController = nil

-- Public API
function InputController.Init(combatController)
	CombatController = combatController
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			if CombatController.Targeting then
				CombatController.ConfirmTarget()
				return
			end
			CombatController.SetAttackHeld(true)
			CombatController.TryAttack()
		elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
			if CombatController.Targeting and CombatController.Targeting.Key ~= "M2" then
				CombatController.CancelTargeting()
				return
			end
			CombatController.TryAbility("M2") -- boot skill (pressing again cancels its targeting)
		elseif input.KeyCode == Enum.KeyCode.Escape then
			CombatController.CancelTargeting()
		elseif input.KeyCode == Enum.KeyCode.Q then
			CombatController.TryAbility("Q")
		elseif input.KeyCode == Enum.KeyCode.E then
			CombatController.TryAbility("E")
		elseif input.KeyCode == Enum.KeyCode.R then
			CombatController.TryAbility("R")
		end
	end)
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
