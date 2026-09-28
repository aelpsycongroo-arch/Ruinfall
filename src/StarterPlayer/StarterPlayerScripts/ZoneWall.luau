-- ZoneWall: the Royale storm wall, drawn on the client and moved EVERY FRAME (the server
-- only says where each shrink starts / ends and when - see Shared.ZoneMath), so the zone
-- closes in one continuous glide instead of jumping with each server update.
--   * a tall shimmering storm wall (force field + tinted glow sheet)
--   * a bright glowing line on the ground where the safe area ends
--   * a white ground ring marking the NEXT zone
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ZoneMath = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ZoneMath"))

local SEGMENTS = 96
local HEIGHT = 160
local ZONE_COLOR = Color3.fromRGB(170, 80, 255)
local EDGE_COLOR = Color3.fromRGB(220, 150, 255)
local NEXT_COLOR = Color3.fromRGB(245, 245, 255)

local ZoneWall = {}
ZoneWall.__index = ZoneWall

local function newPart(parent, name, material, color, transparency)
	local part = Instance.new("Part")
	part.Name = name
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = material
	part.Color = color
	part.Transparency = transparency
	part.Parent = parent
	return part
end

function ZoneWall.new()
	return setmetatable({ Folder = nil, Segments = {}, Last = nil, LastNext = nil }, ZoneWall)
end

function ZoneWall:Build()
	local folder = Instance.new("Folder")
	folder.Name = "ZoneWall"
	folder.Parent = workspace
	self.Folder = folder
	for index = 1, SEGMENTS do
		self.Segments[index] = {
			Field = newPart(folder, "ZoneField", Enum.Material.ForceField, ZONE_COLOR, 0),
			Sheet = newPart(folder, "ZoneSheet", Enum.Material.Neon, ZONE_COLOR, 0.8),
			Edge = newPart(folder, "ZoneEdge", Enum.Material.Neon, EDGE_COLOR, 0),
			Next = newPart(folder, "NextZoneEdge", Enum.Material.Neon, NEXT_COLOR, 0.35),
		}
	end
end

function ZoneWall:Destroy()
	if self.Folder then
		self.Folder:Destroy()
	end
	self.Folder = nil
	table.clear(self.Segments)
	self.Last, self.LastNext = nil, nil
end

local function place(segments, key, cx, cz, radius, height, thickness, y, visibleTransparency)
	local width = 2 * math.pi * math.max(radius, 0.5) / SEGMENTS + 0.6
	local center = Vector3.new(cx, y, cz)
	for index, segment in ipairs(segments) do
		local part = segment[key]
		if radius < 1 then
			part.Transparency = 1
		else
			local angle = (index - 0.5) * 2 * math.pi / SEGMENTS
			local position = Vector3.new(cx + math.sin(angle) * radius, y, cz + math.cos(angle) * radius)
			part.Size = Vector3.new(width, height, thickness)
			part.CFrame = CFrame.lookAt(position, center)
			part.Transparency = visibleTransparency
		end
	end
end

-- zone: the snapshot zone (nil hides the wall); now: server time
function ZoneWall:Render(zone, now)
	if not zone then
		if self.Folder then
			self:Destroy()
		end
		return
	end
	if not self.Folder or not self.Folder.Parent then
		self:Destroy()
		self:Build()
	end
	local x, z, radius = ZoneMath.At(zone, now)
	local key = string.format("%.2f|%.2f|%.2f", x, z, radius)
	if key ~= self.Last then -- only touch the parts while the zone actually moves
		self.Last = key
		place(self.Segments, "Field", x, z, radius, HEIGHT, 1, HEIGHT / 2 - 1, 0)
		place(self.Segments, "Sheet", x, z, radius - 0.6, HEIGHT, 0.4, HEIGHT / 2 - 1, 0.8)
		place(self.Segments, "Edge", x, z, radius - 0.4, 0.6, 1.6, 0.3, 0)
	end
	local showNext = zone.State ~= "Final" and zone.NextRadius and zone.NextRadius < radius - 1
	local nextKey = showNext and string.format("%.2f|%.2f|%.2f", zone.NextX, zone.NextZ, zone.NextRadius) or "hidden"
	if nextKey ~= self.LastNext then
		self.LastNext = nextKey
		if showNext then
			place(self.Segments, "Next", zone.NextX, zone.NextZ, zone.NextRadius, 0.35, 0.9, 0.2, 0.35)
		else
			for _, segment in ipairs(self.Segments) do
				segment.Next.Transparency = 1
			end
		end
	end
	return x, z, radius
end

return ZoneWall
