-- Util: shared helpers (Signal, Maid, 2D geometry, instance creation)

local Util = {}

-- Signal ---------------------------------------------------------------
local Signal = {}
Signal.__index = Signal

function Signal.new()
	return setmetatable({ _handlers = {} }, Signal)
end

function Signal:Connect(callback)
	local handler = { Callback = callback, Connected = true }
	table.insert(self._handlers, handler)
	local handlers = self._handlers
	local connection = {}
	function connection:Disconnect()
		handler.Connected = false
		local index = table.find(handlers, handler)
		if index then
			table.remove(handlers, index)
		end
	end
	return connection
end

function Signal:Fire(...)
	for _, handler in ipairs(table.clone(self._handlers)) do
		if handler.Connected then
			task.spawn(handler.Callback, ...)
		end
	end
end

function Signal:DisconnectAll()
	for _, handler in ipairs(self._handlers) do
		handler.Connected = false
	end
	table.clear(self._handlers)
end

Util.Signal = Signal

-- Maid (cleanup helper) ------------------------------------------------
local Maid = {}
Maid.__index = Maid

function Maid.new()
	return setmetatable({ _tasks = {} }, Maid)
end

function Maid:Give(item)
	table.insert(self._tasks, item)
	return item
end

function Maid:Clean()
	local tasks = self._tasks
	self._tasks = {}
	for _, item in ipairs(tasks) do
		local kind = typeof(item)
		if kind == "RBXScriptConnection" then
			item:Disconnect()
		elseif kind == "Instance" then
			item:Destroy()
		elseif kind == "function" then
			pcall(item)
		elseif kind == "thread" then
			pcall(task.cancel, item)
		elseif kind == "table" then
			if item.Disconnect then
				item:Disconnect()
			elseif item.Destroy then
				item:Destroy()
			end
		end
	end
end

Util.Maid = Maid

-- Time ----------------------------------------------------------------
-- Server and clients share this clock, so timestamps can be replicated.
function Util.Now()
	return workspace:GetServerTimeNow()
end

function Util.FormatTime(seconds)
	seconds = math.max(0, math.floor(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

-- 2D (XZ plane) geometry -------------------------------------------------
function Util.Flat(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

function Util.FlatDistance(a, b)
	local dx, dz = a.X - b.X, a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

function Util.FlatDirection(from, to, fallback)
	local offset = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	if offset.Magnitude < 1e-3 then
		return fallback and Util.Flat(fallback).Unit or Vector3.new(0, 0, -1)
	end
	return offset.Unit
end

function Util.PointSegmentDistance2D(point, a, b)
	local abx, abz = b.X - a.X, b.Z - a.Z
	local lengthSq = abx * abx + abz * abz
	local t = 0
	if lengthSq > 1e-6 then
		t = math.clamp(((point.X - a.X) * abx + (point.Z - a.Z) * abz) / lengthSq, 0, 1)
	end
	local cx, cz = a.X + abx * t, a.Z + abz * t
	local dx, dz = point.X - cx, point.Z - cz
	return math.sqrt(dx * dx + dz * dz)
end

local function cross2D(ax, az, bx, bz)
	return ax * bz - az * bx
end

function Util.SegmentsIntersect2D(p1, p2, p3, p4)
	local d1x, d1z = p2.X - p1.X, p2.Z - p1.Z
	local d2x, d2z = p4.X - p3.X, p4.Z - p3.Z
	local denominator = cross2D(d1x, d1z, d2x, d2z)
	if math.abs(denominator) < 1e-9 then
		return false
	end
	local ox, oz = p3.X - p1.X, p3.Z - p1.Z
	local t = cross2D(ox, oz, d2x, d2z) / denominator
	local u = cross2D(ox, oz, d1x, d1z) / denominator
	return t >= 0 and t <= 1 and u >= 0 and u <= 1
end

function Util.SegmentDistance2D(a1, a2, b1, b2)
	if Util.SegmentsIntersect2D(a1, a2, b1, b2) then
		return 0
	end
	return math.min(
		Util.PointSegmentDistance2D(a1, b1, b2),
		Util.PointSegmentDistance2D(a2, b1, b2),
		Util.PointSegmentDistance2D(b1, a1, a2),
		Util.PointSegmentDistance2D(b2, a1, a2)
	)
end

-- Rotate a vector around the Y axis by angle (radians)
function Util.RotateY(vector, angle)
	local c, s = math.cos(angle), math.sin(angle)
	return Vector3.new(vector.X * c + vector.Z * s, vector.Y, -vector.X * s + vector.Z * c)
end

-- Point inside an oriented box (XZ only)
function Util.PointInBox2D(point, boxCFrame, boxSize)
	local localPoint = boxCFrame:PointToObjectSpace(point)
	return math.abs(localPoint.X) <= boxSize.X / 2 and math.abs(localPoint.Z) <= boxSize.Z / 2
end

function Util.IsFiniteVector(vector)
	if typeof(vector) ~= "Vector3" then
		return false
	end
	for _, component in ipairs({ vector.X, vector.Y, vector.Z }) do
		if component ~= component or math.abs(component) > 1e5 then
			return false
		end
	end
	return true
end

-- Instances -------------------------------------------------------------
function Util.Create(className, properties, children)
	local instance = Instance.new(className)
	local parent
	for key, value in pairs(properties or {}) do
		if key == "Parent" then
			parent = value
		else
			instance[key] = value
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = instance
	end
	if parent then
		instance.Parent = parent
	end
	return instance
end

return Util
