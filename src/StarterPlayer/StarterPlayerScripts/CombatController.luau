-- CombatController: mouse aim, facing, and attack/ability *requests*.
-- The server validates everything; local cooldown checks only avoid spam.

-- Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"))
local Util = require(Shared:WaitForChild("Util"))
local ItemDefinitions = require(Shared:WaitForChild("ItemDefinitions"))
local ClassDefinitions = require(Shared:WaitForChild("ClassDefinitions"))
local CollectionService = game:GetService("CollectionService")

-- Constants
local STATE = Constants.MatchState
local AIM_PLANE_HEIGHT = 3
local ATTACK_ANIMATION = nil -- swings are procedural now (AttackAnimationController)
local player = Players.LocalPlayer
local TARGET_TAGS = { "RF_Hero", "RF_Monster", "RF_Creep" }
local SLOT_INDEX = { E = 1, R = 2, M2 = 3 } -- M2 = right mouse = the separate boot slot
local function emptySlotMessage(key)
	if key == "M2" then
		return "Right mouse: your boot slot is empty - buy boots in the shop [B]"
	end
	return string.format("%s: mythic slot %d is empty - buy a Mythic item in the shop [B]", key, SLOT_INDEX[key])
end

-- State
local CombatController = {}
CombatController.AttackFired = Util.Signal.new()
CombatController.AbilityFired = Util.Signal.new()
CombatController.AbilityDenied = Util.Signal.new() -- (reason)
CombatController.MoveOrdered = Util.Signal.new() -- (position)
CombatController.TargetingChanged = Util.Signal.new() -- (targeting table or nil)
CombatController.Targeting = nil -- { Key, Ability } while choosing a unit target

local ClientState = nil
local remotes = nil
local aimPoint = Vector3.zero
local attackHeld = false
local lastAttackRequest = 0
local lastAbilityRequest = 0
local alignOrientation = nil
local attackTrack = nil
-- Touch (mobile) aiming: there is no mouse, so aim comes from the mobile buttons
-- (auto-target / drag-aim) or, when idle, from the movement direction.
local touchMode = false
local aimOverride = nil
local aimOverrideUntil = 0

-- Functions
local function computeTouchAim()
	if aimOverride and os.clock() < aimOverrideUntil then
		return aimOverride
	end
	local character = ClientState.GetLocalCharacter()
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root then
		return aimPoint
	end
	local move = humanoid and Util.Flat(humanoid.MoveDirection) or Vector3.zero
	if move.Magnitude > 0.1 then
		return Vector3.new(root.Position.X, AIM_PLANE_HEIGHT, root.Position.Z) + move.Unit * 10
	end
	-- idle: keep facing where we last aimed (but stay attached to the hero)
	local previous = Util.Flat(aimPoint - root.Position)
	local facing = previous.Magnitude > 0.5 and previous.Unit or Util.Flat(root.CFrame.LookVector)
	if facing.Magnitude < 0.1 then
		facing = Vector3.new(0, 0, -1)
	end
	return Vector3.new(root.Position.X, AIM_PLANE_HEIGHT, root.Position.Z) + facing.Unit * 10
end

local function computeAim()
	if touchMode then
		return computeTouchAim()
	end
	local camera = workspace.CurrentCamera
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	if math.abs(ray.Direction.Y) < 1e-4 then
		return aimPoint
	end
	local distance = (AIM_PLANE_HEIGHT - ray.Origin.Y) / ray.Direction.Y
	if distance < 0 then
		return aimPoint
	end
	return ray.Origin + ray.Direction * distance
end

local function getControllableCharacter()
	local character = ClientState.GetLocalCharacter()
	if not character then
		return nil
	end
	if (character:GetAttribute("StunnedUntil") or 0) > workspace:GetServerTimeNow() then
		return nil
	end
	return character
end

local function setupCharacter(character)
	alignOrientation = nil
	attackTrack = nil
	local humanoid = character:WaitForChild("Humanoid", 10)
	local root = character:WaitForChild("HumanoidRootPart", 10)
	if not humanoid or not root then
		return
	end
	humanoid.AutoRotate = false
	local attachment = root:FindFirstChild("RootAttachment") or root:FindFirstChild("RootRigAttachment")
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "AimAttachment"
		attachment.Parent = root
	end
	local align = Instance.new("AlignOrientation")
	align.Name = "AimAlign"
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.Attachment0 = attachment
	align.RigidityEnabled = false
	align.MaxTorque = 1e6
	align.Responsiveness = 45
	align.CFrame = root.CFrame.Rotation
	align.Parent = root
	alignOrientation = align

	local animator = ATTACK_ANIMATION and humanoid:WaitForChild("Animator", 5)
	if animator then
		local animation = Instance.new("Animation")
		animation.AnimationId = ATTACK_ANIMATION
		local ok, track = pcall(function()
			return animator:LoadAnimation(animation)
		end)
		if ok and track then
			track.Priority = Enum.AnimationPriority.Action
			attackTrack = track
		end
	end
end

-- Public API
function CombatController.GetAim()
	return aimPoint
end

function CombatController.SetTouchMode(enabled)
	touchMode = enabled == true
	if touchMode then
		CombatController.CancelTargeting()
	end
end

function CombatController.IsTouchMode()
	return touchMode
end

-- Mobile buttons steer the aim point directly for a short time.
function CombatController.SetAimOverride(point, duration)
	if point then
		aimOverride = Vector3.new(point.X, AIM_PLANE_HEIGHT, point.Z)
		aimOverrideUntil = os.clock() + (duration or 0.3)
		aimPoint = aimOverride
	else
		aimOverride = nil
	end
end

function CombatController.SetAttackHeld(held)
	attackHeld = held
end

function CombatController.TryAttack()
	if ClientState.GetMatchState() ~= STATE.ACTIVE then
		return
	end
	local character = getControllableCharacter()
	if not character then
		return
	end
	local now = workspace:GetServerTimeNow()
	local cooldown = character:GetAttribute("AttackCooldown") or 0.6
	if now - lastAttackRequest < cooldown then
		return
	end
	lastAttackRequest = now
	remotes.AttackRequest:FireServer(aimPoint)
	if attackTrack then
		attackTrack:Play(0.05, 1, 1.6)
	end
	CombatController.AttackFired:Fire(cooldown)
end

-- Item abilities (E/R) -------------------------------------------------------------------
-- The equipped item in mythic slot 1 drives E and slot 2 drives R; nothing is hardcoded.
local targetingRing = nil
local targetHighlight = nil
local hoveredModel = nil

function CombatController.GetSlotItem(key)
	local me = ClientState.GetMe()
	local index = SLOT_INDEX[key]
	local itemId
	if index == 3 then
		itemId = me and me.Boots
	else
		itemId = me and me.Mythics and me.Mythics[index]
	end
	if not itemId or itemId == "" then
		return nil, nil
	end
	return ItemDefinitions.GetItem(itemId), ItemDefinitions.GetItemAbility(itemId)
end

function CombatController.GetItemReadyAt(itemId)
	local me = ClientState.GetMe()
	return me and me.ItemReadyAt and me.ItemReadyAt[itemId] or 0
end

local function isTargetable(model)
	if not model or not model.Parent or model:GetAttribute("Dead") then
		return false
	end
	local kind = model:GetAttribute("Kind")
	if kind ~= "Hero" and kind ~= "Monster" and kind ~= "Creep" then
		return false
	end
	if model:GetAttribute("Team") == ClientState.GetMyTeam() then
		return false
	end
	if kind == "Hero" and ((model:GetAttribute("Stealthed") and not ClientState.IsRevealed(model)) or not ClientState.IsHeroVisible(model)) then
		return false
	end
	return true
end

local function findHoveredTarget()
	-- nearest valid enemy to the cursor on the ground plane (forgiving for small units)
	local best, bestDistance = nil, 5
	for _, tag in ipairs(TARGET_TAGS) do
		for _, model in ipairs(CollectionService:GetTagged(tag)) do
			local root = model:IsA("Model") and (model.PrimaryPart or model:FindFirstChild("HumanoidRootPart"))
			if root and isTargetable(model) then
				local distance = Util.FlatDistance(root.Position, aimPoint)
				if distance < bestDistance then
					best, bestDistance = model, distance
				end
			end
		end
	end
	return best
end

local function clearTargetingVisuals()
	if targetingRing then
		targetingRing:Destroy()
		targetingRing = nil
	end
	if targetHighlight then
		targetHighlight:Destroy()
		targetHighlight = nil
	end
	hoveredModel = nil
end

function CombatController.CancelTargeting()
	if CombatController.Targeting then
		CombatController.Targeting = nil
		clearTargetingVisuals()
		CombatController.TargetingChanged:Fire(nil)
	end
end

local function beginTargeting(key, ability)
	CombatController.CancelTargeting()
	CombatController.Targeting = { Key = key, Ability = ability }
	local ringPart = Instance.new("Part")
	ringPart.Name = "RF_TargetRange"
	ringPart.Shape = Enum.PartType.Cylinder
	ringPart.Anchored = true
	ringPart.CanCollide = false
	ringPart.CanQuery = false
	ringPart.CanTouch = false
	ringPart.CastShadow = false
	ringPart.Material = Enum.Material.Neon
	ringPart.Color = ability.Color
	ringPart.Transparency = 0.8
	ringPart.Size = Vector3.new(0.12, ability.Range * 2, ability.Range * 2)
	ringPart.Parent = workspace.CurrentCamera
	targetingRing = ringPart
	local highlight = Instance.new("Highlight")
	highlight.Name = "RF_TargetHighlight"
	highlight.FillColor = Color3.fromRGB(255, 60, 60)
	highlight.FillTransparency = 0.6
	highlight.OutlineColor = Color3.fromRGB(255, 220, 120)
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Enabled = false
	highlight.Parent = workspace.CurrentCamera
	targetHighlight = highlight
	CombatController.TargetingChanged:Fire(CombatController.Targeting)
	ClientState.LocalMessage:Fire(string.format("%s: click an enemy (%s again / Esc to cancel)", ability.Name, key == "M2" and "right-click" or key), "Info")
end

local function updateTargeting()
	local targeting = CombatController.Targeting
	if not targeting then
		return
	end
	local character = ClientState.GetLocalCharacter()
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or ClientState.GetMatchState() ~= STATE.ACTIVE then
		CombatController.CancelTargeting()
		return
	end
	if targetingRing then
		targetingRing.CFrame = CFrame.new(root.Position.X, 0.3, root.Position.Z) * CFrame.Angles(0, 0, math.rad(90))
	end
	hoveredModel = findHoveredTarget()
	if targetHighlight then
		targetHighlight.Adornee = hoveredModel
		targetHighlight.Enabled = hoveredModel ~= nil
		if hoveredModel then
			local targetRoot = hoveredModel.PrimaryPart or hoveredModel:FindFirstChild("HumanoidRootPart")
			local inRange = targetRoot and Util.FlatDistance(targetRoot.Position, root.Position) <= targeting.Ability.Range + 2
			targetHighlight.FillColor = inRange and Color3.fromRGB(255, 60, 60) or Color3.fromRGB(120, 120, 120)
		end
	end
end

-- Called by InputController on left click while targeting.
function CombatController.ConfirmTarget()
	local targeting = CombatController.Targeting
	if not targeting then
		return false
	end
	local model = hoveredModel
	if not model or not isTargetable(model) then
		ClientState.LocalMessage:Fire("Select an enemy", "Warning")
		return true
	end
	local character = ClientState.GetLocalCharacter()
	local root = character and character:FindFirstChild("HumanoidRootPart")
	local targetRoot = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	if root and targetRoot and Util.FlatDistance(root.Position, targetRoot.Position) > targeting.Ability.Range + 2 then
		ClientState.LocalMessage:Fire("Target out of range", "Warning")
		return true
	end
	remotes.AbilityRequest:FireServer(targeting.Key, aimPoint, model:GetAttribute("EntityId"))
	lastAbilityRequest = workspace:GetServerTimeNow()
	CombatController.CancelTargeting()
	CombatController.AbilityFired:Fire()
	return true
end

-- Mobile cast entry point: fire Q/E/R toward an explicit aim point (and, for
-- unit-targeted item skills, an explicit target model). Same client checks as desktop;
-- the server still validates everything.
function CombatController.CastAbility(key, aim, targetModel)
	if aim then
		CombatController.SetAimOverride(aim, 0.45)
	end
	if key == "Q" then
		CombatController.TryAbility("Q")
		return
	end
	if ClientState.GetMatchState() ~= STATE.ACTIVE then
		return
	end
	local item, ability = CombatController.GetSlotItem(key)
	if not item or not ability then
		ClientState.LocalMessage:Fire(emptySlotMessage(key), "Info")
		return
	end
	local character = getControllableCharacter()
	if not character then
		return
	end
	local now = workspace:GetServerTimeNow()
	if now < CombatController.GetItemReadyAt(item.Id) - 0.1 then
		CombatController.AbilityDenied:Fire("Cooldown")
		return
	end
	if now - lastAbilityRequest < 0.25 then
		return
	end
	if ability.Targeting == "Unit" then
		local entityId = targetModel and targetModel:GetAttribute("EntityId")
		if not entityId then
			ClientState.LocalMessage:Fire("No enemy in range", "Warning")
			return
		end
		lastAbilityRequest = now
		remotes.AbilityRequest:FireServer(key, aimPoint, entityId)
	else
		lastAbilityRequest = now
		remotes.AbilityRequest:FireServer(key, aimPoint)
	end
	CombatController.AbilityFired:Fire()
end

local function tryItemAbility(key)
	if ClientState.GetMatchState() ~= STATE.ACTIVE then
		return
	end
	local item, ability = CombatController.GetSlotItem(key)
	if not item or not ability then
		ClientState.LocalMessage:Fire(emptySlotMessage(key), "Info")
		return
	end
	if CombatController.Targeting and CombatController.Targeting.Key == key then
		CombatController.CancelTargeting() -- pressing the key again cancels
		return
	end
	-- skills such as Unstoppable March can be cast while stunned (they remove the stun)
	local character = ability.UsableWhileStunned and ClientState.GetLocalCharacter() or getControllableCharacter()
	if not character then
		return
	end
	local now = workspace:GetServerTimeNow()
	if now < CombatController.GetItemReadyAt(item.Id) - 0.1 then
		CombatController.AbilityDenied:Fire("Cooldown")
		return
	end
	if ability.Targeting == "Unit" then
		beginTargeting(key, ability)
		return
	end
	if now - lastAbilityRequest < 0.3 then
		return
	end
	lastAbilityRequest = now
	remotes.AbilityRequest:FireServer(key, aimPoint)
	CombatController.AbilityFired:Fire()
end

function CombatController.TryAbility(slot)
	if slot == "E" or slot == "R" or slot == "M2" then
		tryItemAbility(slot)
		return
	elseif slot ~= "Q" then
		return
	end
	CombatController.CancelTargeting()
	if ClientState.GetMatchState() ~= STATE.ACTIVE then
		return
	end
	local character = getControllableCharacter()
	if not character then
		return
	end
	local now = workspace:GetServerTimeNow()
	if now < (character:GetAttribute("AbilityReadyAt") or 0) - 0.1 then
		CombatController.AbilityDenied:Fire("Cooldown")
		return
	end
	-- Q mana cost (class ability ManaCost, e.g. Mage Arcane Burst); the server checks it too
	local me = ClientState.GetMe()
	local classDef = me and ClassDefinitions.Get(me.ClassKey)
	local manaCost = classDef and classDef.Ability and classDef.Ability.ManaCost or 0
	if manaCost > 0 and (character:GetAttribute("Mana") or 0) < manaCost then
		ClientState.LocalMessage:Fire("Not enough mana", "Warning")
		return
	end
	if now - lastAbilityRequest < 0.3 then
		return
	end
	lastAbilityRequest = now
	remotes.AbilityRequest:FireServer("Q", aimPoint)
	CombatController.AbilityFired:Fire()
end

function CombatController.MoveToAim()
	local character = getControllableCharacter()
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and ClientState.GetMatchState() == STATE.ACTIVE then
		local target = Vector3.new(aimPoint.X, 0, aimPoint.Z)
		humanoid:MoveTo(target)
		CombatController.MoveOrdered:Fire(target)
	end
end

function CombatController.Init(clientState)
	ClientState = clientState
	remotes = ReplicatedStorage:WaitForChild("Remotes")
	player.CharacterAdded:Connect(setupCharacter)
	if player.Character then
		task.spawn(setupCharacter, player.Character)
	end
	RunService.RenderStepped:Connect(function()
		aimPoint = computeAim()
		updateTargeting()
		local character = getControllableCharacter()
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if alignOrientation and alignOrientation.Parent and root then
			local direction = Util.Flat(aimPoint - root.Position)
			if direction.Magnitude > 0.5 then
				alignOrientation.CFrame = CFrame.lookAt(Vector3.zero, direction.Unit)
			end
		end
		if attackHeld and not CombatController.Targeting then
			CombatController.TryAttack()
		end
	end)
end

return CombatController
