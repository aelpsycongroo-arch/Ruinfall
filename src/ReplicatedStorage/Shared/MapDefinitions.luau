-- MapDefinitions: procedural generation parameters and palette

local MapDefinitions = {}

MapDefinitions.Generation = {
	BASE_RING_OFFSET = 30, -- bases sit at Radius - offset
	BASE_RESERVED_RADIUS = 30,
	BASE_PLATFORM_RADIUS = 15,
	SPAWN_RING_RADIUS = 8,
	CENTER_RESERVED_RADIUS = 18,
	CAMP_RING_FACTOR = 0.58, -- camps at Radius * factor
	CAMP_RESERVED_RADIUS = 16,
	MIN_CAMPS = 4,
	LANE_WIDTH = 10,
	TOTAL_WALLS = 26,
	WALL_MIN_LENGTH = 14,
	WALL_MAX_LENGTH = 30,
	WALL_THICKNESS = 3,
	WALL_SPACING = 9, -- minimum corridor between walls
	TOTAL_ROCKS = 14,
	TOTAL_BRUSH = 16,
	BRUSH_MIN_SIZE = 10,
	BRUSH_MAX_SIZE = 16,
	BRUSH_HEIGHT = 3.2,
	BOUNDARY_SEGMENTS = 48,
	BOUNDARY_HEIGHT = 14,
	RUIN_MIN_BASE_DISTANCE = 40,
	RUIN_MIN_CAMP_DISTANCE = 20,
	RUIN_MIN_RUIN_DISTANCE = 30,
	RUIN_WALL_CLEARANCE = 7,
}

MapDefinitions.Palette = {
	Ground = Color3.fromRGB(62, 59, 74),
	GroundMaterial = Enum.Material.Slate,
	OuterGround = Color3.fromRGB(20, 19, 27),
	Lane = Color3.fromRGB(78, 72, 84),
	LaneMaterial = Enum.Material.Cobblestone,
	Wall = Color3.fromRGB(88, 84, 100),
	WallCap = Color3.fromRGB(120, 115, 135),
	WallMaterial = Enum.Material.Rock,
	Boundary = Color3.fromRGB(36, 34, 44),
	Rock = Color3.fromRGB(96, 90, 104),
	Brush = Color3.fromRGB(40, 110, 60),
	BrushTop = Color3.fromRGB(60, 150, 80),
	Camp = Color3.fromRGB(78, 52, 44),
	Center = Color3.fromRGB(70, 60, 95),
	InactiveBase = Color3.fromRGB(70, 70, 76),
	RuinStone = Color3.fromRGB(170, 150, 110),
	RuinRune = Color3.fromRGB(255, 200, 90),
}

return MapDefinitions
