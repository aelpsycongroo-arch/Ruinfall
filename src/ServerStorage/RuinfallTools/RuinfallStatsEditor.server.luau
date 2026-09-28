--[[
	RUINFALL STATS EDITOR  v1.0  -  Roblox Studio plugin (Plugins tab > Ruinfall Stats > Stats Editor)

	Change item / skill / hero numbers from simple tabs instead of hunting through scripts.

	  Items     Mythic, Boots and Passive items: price and stat bonuses (add or remove a stat)
	  Passives  the numbers of each item's automatic effect (Passive, PassiveSplash, PassiveReflect)
	  Skills    item-granted E / R / RMB abilities: cooldown, mana, damage scaling, range, radius ...
	  Heroes    each class's base stats and its own Q ability

	Every item shows its gold value next to its price (SharedGameRules: value within 10g of price);
	items outside that range are flagged with a warning but can still be saved.

	Edit mode    a change is written into ReplicatedStorage.Shared.ItemDefinitions / ClassDefinitions
	             right away - only the edited number changes, the rest of the script (comments,
	             layout) is left as it is. The Undo button reverts your recent edits one by one.
	Playtest     the change is applied to the running game at once (Shared.StatPatch,
	             ServerScriptService.StatsHotSwap, StarterPlayerScripts.StatsHotSwapClient: heroes'
	             stats are refreshed) and saved into the scripts as well.
]]

--------------------------------------------------------------------------------------------------
-- Services
--------------------------------------------------------------------------------------------------
local ChangeHistoryService = game:GetService("ChangeHistoryService")
local CoreGui = game:GetService("CoreGui")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local ScriptEditorService = game:GetService("ScriptEditorService")
local ServerStorage = game:GetService("ServerStorage")
local Studio = settings().Studio

local plugin = plugin

--------------------------------------------------------------------------------------------------
-- Constants
--------------------------------------------------------------------------------------------------
local VERSION = "1.0"
local PATCH_FOLDER = "RuinfallStatPatches"
local PRICE_TOLERANCE = 10 -- SharedGameRules: item value within 10g of its price
local BACKUP_FOLDER = "StatsEditorBackups"
local MAX_BACKUPS = 6

-- plugin settings shared by the Edit / Server / Client copies of this plugin
local KEY_PENDING = "RSE_PendingSaves" -- edits made in a playtest copy, waiting to be saved by the Edit copy
local KEY_REQUESTS = "RSE_LiveRequests" -- edits to apply live, for the playtest server copy
local KEY_RESULTS = "RSE_LiveResults"
local KEY_LIVE = "RSE_LiveHeartbeat" -- unix ms, written by the playtest server copy
local LIVE_TIMEOUT_MS = 6000

local MODULE_PATHS = {
	Item = { "ReplicatedStorage", "Shared", "ItemDefinitions" },
	Ability = { "ReplicatedStorage", "Shared", "ItemDefinitions" },
	Class = { "ReplicatedStorage", "Shared", "ClassDefinitions" },
}

local TABS = {
	{ Key = "Items", Title = "Item stats" },
	{ Key = "Passives", Title = "Item passives" },
	{ Key = "Skills", Title = "Item skills" },
	{ Key = "Heroes", Title = "Hero classes" },
}
local ROLES = { "All", "General", "Assassin", "Mage", "Marksman", "Tank", "Fighter" }
local ITEM_TYPES = { "All", "Mythic", "Boots", "Passive" }

-- fields that are identity / art / wiring, never shown as editable values
local IDENTITY = { Id = true, Key = true, Color = true, SecondaryColor = true, Icon = true, IconImage = true, Glyph = true }
local HIDDEN = { Rarity = true, SlotType = true, Class = true, Ability = true } -- top level of an entry only
-- strings that the game code switches on: shown, but read-only
local READ_ONLY = { Effect = true, Targeting = true, AttackType = true, BootType = true, Style = true, Kind = true }
local LONG_TEXT = { Summary = true, Description = true, Details = true }

-- preferred row order (anything else follows alphabetically)
local ORDER = {
	"Name", "DisplayName", "Role", "Price", "Value", "Cooldown", "ManaCost", "Damage", "Shield", "Heal", "Stun",
	"MaxHealth", "Armor", "MagicPower", "AttackDamage", "AttackSpeed", "AttackCooldown", "AttackRange", "MoveSpeed",
	"HealthRegen", "Range", "CastRange", "Radius", "Arc", "Width", "Speed", "Duration", "Delay",
}
local ORDER_INDEX = {}
for index, key in ipairs(ORDER) do
	ORDER_INDEX[key] = index
end

local STAT_SUGGESTIONS = {
	"AttackDamage", "MagicPower", "MaxHealth", "Armor", "MagicDefense", "AttackSpeed", "MoveSpeed", "MoveSpeedPercent",
	"HealthRegen", "Mana", "CooldownReduction", "CritChance", "Lifesteal",
}

--------------------------------------------------------------------------------------------------
-- Small helpers
--------------------------------------------------------------------------------------------------
local function role()
	if not RunService:IsRunning() then
		return "Edit"
	end
	return RunService:IsServer() and "Server" or "Client"
end

local function nowMs()
	return DateTime.now().UnixTimestampMillis
end

local function getSetting(key)
	local ok, value = pcall(function()
		return plugin:GetSetting(key)
	end)
	return ok and value or nil
end

local function setSetting(key, value)
	pcall(function()
		plugin:SetSetting(key, value)
	end)
end

local function liveSessionActive()
	local beat = getSetting(KEY_LIVE)
	return type(beat) == "number" and nowMs() - beat < LIVE_TIMEOUT_MS
end

local function resolvePath(path)
	local ok, current = pcall(function()
		return game:GetService(path[1])
	end)
	if not ok or not current then
		return nil
	end
	for index = 2, #path do
		current = current:FindFirstChild(path[index])
		if not current then
			return nil
		end
	end
	return current
end

local function moduleFor(kind)
	return resolvePath(MODULE_PATHS[kind])
end

-- loads a ModuleScript's CURRENT source (the plugin's require cache would keep old versions)
local function freshRequire(module)
	local ok, result = pcall(function()
		local fn, err = loadstring(module.Source, "=" .. module:GetFullName())
		if not fn then
			error(err, 0)
		end
		setfenv(fn, setmetatable({ script = module }, { __index = getfenv(0) }))
		return fn()
	end)
	if ok then
		return result
	end
	-- loadstring is not available in playtest data models: the plugin's own copy is still fresh there
	return require(module)
end

local function pathText(path)
	return table.concat(path, ".")
end

local function splitPath(text)
	local path = {}
	for part in string.gmatch(text, "[^%.]+") do
		table.insert(path, part)
	end
	return path
end

local function isIdentifier(text)
	return type(text) == "string" and string.match(text, "^[%a_][%w_]*$") ~= nil
end

local function formatNumber(value)
	if value == math.floor(value) and math.abs(value) < 1e15 then
		return string.format("%d", value)
	end
	local text = string.format("%.4f", value)
	text = string.gsub(text, "0+$", "")
	text = string.gsub(text, "%.$", "")
	return text
end

local function quote(text)
	local escaped = string.gsub(text, '[\\"\n\r\t%c]', function(char)
		if char == "\\" then
			return "\\\\"
		elseif char == '"' then
			return '\\"'
		elseif char == "\n" then
			return "\\n"
		elseif char == "\r" then
			return "\\r"
		elseif char == "\t" then
			return "\\t"
		end
		return string.format("\\%03d", string.byte(char))
	end)
	return '"' .. escaped .. '"'
end

local function literal(value)
	local kind = type(value)
	if kind == "number" then
		return formatNumber(value)
	elseif kind == "boolean" then
		return tostring(value)
	elseif kind == "string" then
		return quote(value)
	end
	error("cannot write a " .. kind .. " value", 0)
end

local function displayValue(value)
	if type(value) == "number" then
		return formatNumber(value)
	end
	return tostring(value)
end

-- parses what was typed in a value box, keeping the kind of the current value
local function parseInput(text, current)
	text = string.match(text, "^%s*(.-)%s*$")
	if type(current) == "number" or current == nil then
		local percent = string.match(text, "^(-?[%d%.]+)%s*%%$")
		local number = tonumber(percent or text)
		if number then
			return true, percent and number / 100 or number
		end
		if current == nil then
			if text == "true" or text == "false" then
				return true, text == "true"
			end
			local quoted = string.match(text, '^"(.*)"$')
			if quoted then
				return true, quoted
			end
		end
		return false, "enter a number"
	elseif type(current) == "boolean" then
		local lower = string.lower(text)
		if lower == "true" or lower == "yes" or lower == "1" then
			return true, true
		elseif lower == "false" or lower == "no" or lower == "0" then
			return true, false
		end
		return false, "enter true or false"
	end
	return true, text
end

--------------------------------------------------------------------------------------------------
-- Source editing: a small Lua table-constructor reader, so an edit rewrites exactly one value
--------------------------------------------------------------------------------------------------
local Src = {}

function Src.Lex(src)
	local tokens = {}
	local count = 0
	local index, length = 1, #src
	local function add(kind, value, first, last)
		count += 1
		tokens[count] = { t = kind, v = value, s = first, e = last }
	end
	while index <= length do
		local char = string.sub(src, index, index)
		if string.match(char, "%s") then
			index += 1
		elseif string.sub(src, index, index + 1) == "--" then
			local equals = string.match(src, "^%[(=*)%[", index + 2)
			if equals then
				local close = "]" .. equals .. "]"
				local found = string.find(src, close, index + 4 + #equals, true)
				index = found and found + #close or length + 1
			else
				local found = string.find(src, "\n", index, true)
				index = found and found + 1 or length + 1
			end
		elseif char == '"' or char == "'" or char == "`" then
			local j = index + 1
			while j <= length do
				local d = string.sub(src, j, j)
				if d == "\\" then
					j += 2
				elseif d == char or (d == "\n" and char ~= "`") then
					break
				else
					j += 1
				end
			end
			add("string", string.sub(src, index, j), index, j)
			index = j + 1
		elseif char == "[" and string.match(src, "^%[=*%[", index) then
			local equals = string.match(src, "^%[(=*)%[", index)
			local close = "]" .. equals .. "]"
			local found = string.find(src, close, index + 2 + #equals, true)
			local j = found and found + #close - 1 or length
			add("string", string.sub(src, index, j), index, j)
			index = j + 1
		elseif string.match(char, "[%a_]") then
			local j = string.find(src, "[^%w_]", index) or length + 1
			add("name", string.sub(src, index, j - 1), index, j - 1)
			index = j
		elseif string.match(char, "%d") or (char == "." and string.match(string.sub(src, index + 1, index + 1), "%d")) then
			local number = string.match(src, "^0[xXbB][%x_]+", index)
				or string.match(src, "^%d[%d_]*%.?[%d_]*[eE][%+%-]?%d+", index)
				or string.match(src, "^%d[%d_]*%.?[%d_]*", index)
				or string.match(src, "^%.%d+[eE][%+%-]?%d+", index)
				or string.match(src, "^%.%d+", index)
			add("number", number, index, index + #number - 1)
			index += #number
		else
			local three = string.sub(src, index, index + 2)
			local two = string.sub(src, index, index + 1)
			if three == "..." or three == "..=" or three == "//=" then
				add("sym", three, index, index + 2)
				index += 3
			elseif two == "==" or two == "~=" or two == "<=" or two == ">=" or two == ".." or two == "+=" or two == "-="
				or two == "*=" or two == "/=" or two == "%=" or two == "^=" or two == "::" or two == "->" or two == "//" then
				add("sym", two, index, index + 1)
				index += 2
			else
				add("sym", char, index, index)
				index += 1
			end
		end
	end
	add("eof", "", length + 1, length)
	return tokens
end

local BLOCK_OPEN = { ["function"] = true, ["if"] = true, ["do"] = true }

-- returns every table constructor at statement level (its fields, and each field's nested table)
function Src.Parse(src)
	local tokens = Src.Lex(src)
	local pos = 1
	local roots = {}
	local parseTable

	local function isSym(token, value)
		return token.t == "sym" and token.v == value
	end

	-- skips a `function ... end` body starting at pos
	local function skipFunction()
		local depth = 0
		while tokens[pos].t ~= "eof" do
			local token = tokens[pos]
			if token.t == "name" then
				if BLOCK_OPEN[token.v] or token.v == "repeat" then
					depth += 1
				elseif token.v == "end" or token.v == "until" then
					depth -= 1
					if depth == 0 then
						pos += 1
						return
					end
				end
			end
			pos += 1
		end
	end

	-- one table field value; returns first / last token index and the nested table if the value is one
	local function parseValue(context)
		local first = pos
		local child = nil
		local depth = 0
		local startsWithTable = isSym(tokens[pos], "{")
		while tokens[pos].t ~= "eof" do
			local token = tokens[pos]
			if depth == 0 and token.t == "sym" and (token.v == "," or token.v == ";" or token.v == "}") then
				break
			end
			if isSym(token, "{") then
				local node = parseTable(context)
				if startsWithTable and child == nil and pos - 1 >= first then
					child = node
				else
					child = false
				end
			elseif token.t == "name" and token.v == "function" then
				skipFunction()
				child = false
			elseif token.t == "sym" and (token.v == "(" or token.v == "[") then
				depth += 1
				pos += 1
			elseif token.t == "sym" and (token.v == ")" or token.v == "]") then
				depth -= 1
				pos += 1
			else
				pos += 1
			end
		end
		local last = pos - 1
		if child and not (isSym(tokens[first], "{") and tokens[last].e == child.e) then
			child = nil
		end
		return first, last, child or nil
	end

	parseTable = function(context)
		local open = tokens[pos]
		pos += 1
		local node = { s = open.s, e = nil, ctx = context, fields = {}, byKey = {} }
		while true do
			local token = tokens[pos]
			if token.t == "eof" then
				node.e = #src
				break
			end
			if isSym(token, "}") then
				node.e = token.s
				pos += 1
				break
			end
			if isSym(token, ",") or isSym(token, ";") then
				pos += 1
				continue
			end
			local field = {}
			if token.t == "name" and isSym(tokens[pos + 1], "=") then
				field.key = token.v
				field.keyS = token.s
				pos += 2
			elseif isSym(token, "[") and tokens[pos + 1].t == "string" and isSym(tokens[pos + 2], "]") and isSym(tokens[pos + 3], "=") then
				field.key = string.sub(tokens[pos + 1].v, 2, -2)
				field.keyS = token.s
				pos += 4
			end
			local childContext = field.key and ((context and context ~= "") and (context .. "." .. field.key) or field.key) or nil
			local first, last, child = parseValue(childContext)
			if last < first then
				pos = math.max(pos, first + 1)
				continue
			end
			field.vS = tokens[first].s
			field.vE = tokens[last].e
			field.node = child
			field.token = (first == last) and tokens[first] or nil
			table.insert(node.fields, field)
			if field.key then
				node.byKey[field.key] = field
			end
		end
		return node
	end

	local function contextBefore(index)
		local previous = tokens[index - 1]
		local chain = {}
		local j
		if previous and isSym(previous, "=") then
			j = index - 2
		elseif previous and isSym(previous, "(") then
			j = index - 2
		else
			return nil
		end
		while tokens[j] and tokens[j].t == "name" do
			table.insert(chain, 1, tokens[j].v)
			if tokens[j - 1] and isSym(tokens[j - 1], ".") then
				j -= 2
			else
				break
			end
		end
		if #chain == 0 then
			return nil
		end
		local name = table.concat(chain, ".")
		return isSym(previous, "(") and ("call:" .. name) or name
	end

	while tokens[pos].t ~= "eof" do
		if isSym(tokens[pos], "{") then
			table.insert(roots, parseTable(contextBefore(pos)))
		else
			pos += 1
		end
	end
	return roots
end

local function tokenString(token)
	if not token or token.t ~= "string" then
		return nil
	end
	local body = string.match(token.v, "^[\"'`](.*)[\"'`]$") or string.match(token.v, "^%[=*%[(.*)%]=*%]$")
	return body
end

function Src.FindEntity(roots, kind, key)
	local wanted = kind == "Ability" and "ItemDefinitions.Abilities" or kind == "Class" and "ClassDefinitions.Classes" or "ItemDefinitions.Items"
	for _, root in ipairs(roots) do
		if root.ctx == wanted then
			local field = root.byKey[key]
			if field and field.node then
				return field.node
			end
		end
	end
	if kind == "Item" then
		-- addItem({ Id = "X", ... }) / addBoots({ ... }) / A({ ... }) style definitions
		for _, root in ipairs(roots) do
			if root.ctx and string.sub(root.ctx, 1, 5) == "call:" then
				local id = root.byKey.Id
				if id and tokenString(id.token) == key then
					return root
				end
			end
		end
	end
	return nil
end

local function lineStart(text, index)
	local start = index
	while start > 1 and string.sub(text, start - 1, start - 1) ~= "\n" do
		start -= 1
	end
	return start
end

local function insertField(src, node, key, valueText)
	local entry = key .. " = " .. valueText
	local last = node.fields[#node.fields]
	if not last then
		return string.sub(src, 1, node.s) .. " " .. entry .. " " .. string.sub(src, node.e)
	end
	local after = string.sub(src, last.vE + 1, node.e - 1)
	local comma = string.match(after, "^[ \t]*[,;]")
	if string.find(after, "\n", 1, true) then
		local indentFrom = lineStart(src, last.keyS or last.vS)
		local indent = string.match(string.sub(src, indentFrom), "^[ \t]*")
		local text, closing = src, node.e
		if not comma then
			text = string.sub(text, 1, last.vE) .. "," .. string.sub(text, last.vE + 1)
			closing += 1
		end
		local newline = string.find(text, "\n", last.vE + 1, true)
		if newline and newline < closing then
			return string.sub(text, 1, newline - 1) .. "\n" .. indent .. entry .. "," .. string.sub(text, newline)
		end
	end
	if comma then
		local at = last.vE + #comma
		return string.sub(src, 1, at) .. " " .. entry .. "," .. string.sub(src, at + 1)
	end
	return string.sub(src, 1, last.vE) .. ", " .. entry .. string.sub(src, last.vE + 1)
end

local function removeField(src, field)
	local first, last = field.keyS or field.vS, field.vE
	local trailing = string.match(string.sub(src, last + 1), "^[ \t]*[,;][ \t]*")
	if trailing then
		last += #trailing
	else
		local before = string.sub(src, 1, first - 1)
		local leading = string.match(before, "[,;][ \t]*$") or string.match(before, "[,;]%s*$")
		if leading then
			first -= #leading
		end
	end
	local out = string.sub(src, 1, first - 1) .. string.sub(src, last + 1)
	local from = lineStart(out, math.max(1, first))
	local to = string.find(out, "\n", first, true)
	if to and string.match(string.sub(out, from, to - 1), "^%s*$") and from > 1 then
		out = string.sub(out, 1, from - 1) .. string.sub(out, to + 1)
	end
	return out
end

-- returns the new source, or nil + reason
function Src.Edit(src, kind, key, path, value, remove)
	local node = Src.FindEntity(Src.Parse(src), kind, key)
	if not node then
		return nil, "could not find " .. kind .. " " .. key .. " in the script"
	end
	for index, part in ipairs(path) do
		if not isIdentifier(part) then
			return nil, "'" .. tostring(part) .. "' is not a valid field name"
		end
		if index == #path then
			break
		end
		local field = node.byKey[part]
		if field and field.node then
			node = field.node
		elseif field then
			return nil, part .. " is not a { } table in the script, so it cannot hold " .. path[index + 1]
		else
			if remove then
				return src
			end
			local text = literal(value)
			for j = #path, index + 1, -1 do
				text = "{ " .. path[j] .. " = " .. text .. " }"
			end
			return insertField(src, node, part, text)
		end
	end
	local field = node.byKey[path[#path]]
	if remove then
		return field and removeField(src, field) or src
	end
	local text = literal(value)
	if field then
		return string.sub(src, 1, field.vS - 1) .. text .. string.sub(src, field.vE + 1)
	end
	return insertField(src, node, path[#path], text)
end

-- the literal text currently written for a path (used to verify an edit)
function Src.Read(src, kind, key, path)
	local node = Src.FindEntity(Src.Parse(src), kind, key)
	for index, part in ipairs(path) do
		if not node then
			return nil
		end
		local field = node.byKey[part]
		if not field then
			return nil
		end
		if index == #path then
			return string.sub(src, field.vS, field.vE)
		end
		node = field.node
	end
	return nil
end

--------------------------------------------------------------------------------------------------
-- Model: the definitions as the plugin shows them (fresh from the scripts + edits made since)
--------------------------------------------------------------------------------------------------
local Model = { ItemDefs = nil, ClassDefs = nil, Error = nil }

local function applyToTable(root, path, value, remove)
	if type(root) ~= "table" then
		return
	end
	local node = root
	for index = 1, #path - 1 do
		if type(node[path[index]]) ~= "table" then
			if remove then
				return
			end
			node[path[index]] = {}
		end
		node = node[path[index]]
	end
	if remove then
		node[path[#path]] = nil
	else
		node[path[#path]] = value
	end
end

function Model.Target(kind, key)
	if kind == "Item" then
		return Model.ItemDefs and Model.ItemDefs.Items[key]
	elseif kind == "Ability" then
		return Model.ItemDefs and Model.ItemDefs.Abilities[key]
	elseif kind == "Class" then
		return Model.ClassDefs and Model.ClassDefs.Classes[key]
	end
	return nil
end

function Model.Get(kind, key, path)
	local node = Model.Target(kind, key)
	for _, part in ipairs(path) do
		if type(node) ~= "table" then
			return nil
		end
		node = node[part]
	end
	return node
end

function Model.Apply(patch)
	applyToTable(Model.Target(patch.Kind, patch.Key), patch.Path, patch.Value, patch.Remove)
end

function Model.Load()
	Model.Error = nil
	local ok, err = pcall(function()
		Model.ItemDefs = freshRequire(moduleFor("Item"))
		Model.ClassDefs = freshRequire(moduleFor("Class"))
	end)
	if not ok then
		Model.Error = tostring(err)
		return
	end
	-- in a playtest copy, replay the edits already applied to the running game
	local folder = ReplicatedStorage:FindFirstChild(PATCH_FOLDER)
	if folder and role() ~= "Edit" then
		local children = folder:GetChildren()
		table.sort(children, function(a, b)
			return a.Name < b.Name
		end)
		for _, child in ipairs(children) do
			local okDecode, patch = pcall(HttpService.JSONDecode, HttpService, child.Value)
			if okDecode and type(patch) == "table" and type(patch.Path) == "table" then
				Model.Apply(patch)
			end
		end
	end
end

-- statGold, skillGold, passiveGold, total, price (nil for non-items)
function Model.Value(itemKey)
	local defs = Model.ItemDefs
	local item = defs and defs.Items[itemKey]
	if not (item and defs.GetItemGoldValue) then
		return nil
	end
	local ok, stats, skill, passive, total = pcall(defs.GetItemGoldValue, item)
	if not ok then
		return nil
	end
	return stats, skill, passive, total, item.Price or 0
end

function Model.PriceWarning(itemKey)
	local _, _, _, total, price = Model.Value(itemKey)
	return total ~= nil and math.abs(total - price) > PRICE_TOLERANCE
end

function Model.ItemRole(item)
	return item.Class or "General"
end

function Model.ItemType(item)
	if item.SlotType == "Passive" then
		return "Passive"
	elseif item.SlotType == "Boots" then
		return "Boots"
	end
	return "Mythic"
end

function Model.AbilityUsers(abilityKey)
	local users = {}
	for key, item in pairs(Model.ItemDefs and Model.ItemDefs.Items or {}) do
		if item.Ability == abilityKey then
			table.insert(users, key)
		end
	end
	table.sort(users)
	return users
end

function Model.AbilityRole(abilityKey)
	local roleName = nil
	for _, key in ipairs(Model.AbilityUsers(abilityKey)) do
		local item = Model.ItemDefs.Items[key]
		local itemRole = Model.ItemRole(item)
		if roleName and roleName ~= itemRole then
			return "General"
		end
		roleName = itemRole
	end
	return roleName or "General"
end

--------------------------------------------------------------------------------------------------
-- Core: save into the scripts / apply to a running playtest
--------------------------------------------------------------------------------------------------
local Core = {}

local function recorded(name, fn)
	local recording = nil
	pcall(function()
		recording = ChangeHistoryService:TryBeginRecording(name)
	end)
	local ok, a, b = pcall(fn)
	if recording then
		pcall(function()
			ChangeHistoryService:FinishRecording(recording, (ok and a) and Enum.FinishRecordingOperation.Commit or Enum.FinishRecordingOperation.Cancel)
		end)
	end
	if not ok then
		return false, tostring(a)
	end
	return a, b
end

local backedUp = {}
local function backup(module)
	if backedUp[module] then
		return
	end
	backedUp[module] = true
	pcall(function()
		local backups = ServerStorage:FindFirstChild("ScriptBackups")
		if not backups then
			backups = Instance.new("Folder")
			backups.Name = "ScriptBackups"
			backups.Parent = ServerStorage
		end
		local folder = backups:FindFirstChild(BACKUP_FOLDER)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = BACKUP_FOLDER
			folder.Parent = backups
		end
		local copy = module:Clone()
		copy.Name = module.Name .. "_" .. os.date("%Y%m%d_%H%M%S")
		copy.Parent = folder
		local copies = {}
		for _, child in ipairs(folder:GetChildren()) do
			if string.sub(child.Name, 1, #module.Name + 1) == module.Name .. "_" then
				table.insert(copies, child)
			end
		end
		table.sort(copies, function(a, b)
			return a.Name < b.Name
		end)
		for index = 1, #copies - MAX_BACKUPS do
			copies[index]:Destroy()
		end
	end)
end

-- writes one patch into its definitions script; ok, message, retryLater
function Core.SaveToSource(patch)
	local module = moduleFor(patch.Kind)
	if not module then
		return false, "definitions script not found", false
	end
	local source = module.Source
	local newSource, err = Src.Edit(source, patch.Kind, patch.Key, patch.Path, patch.Value, patch.Remove)
	if not newSource then
		return false, err, false
	end
	if newSource == source then
		return true, "already saved", false
	end
	local okCompile, compileError = pcall(function()
		local fn, message = loadstring(newSource)
		if not fn then
			error(message, 0)
		end
	end)
	if not okCompile and not string.find(tostring(compileError), "loadstring", 1, true) then
		return false, "edit would break the script: " .. tostring(compileError), false
	end
	backup(module)
	local okWrite, writeError = pcall(function()
		ScriptEditorService:UpdateSourceAsync(module, function()
			return newSource
		end)
	end)
	if not okWrite then
		return false, "could not write the script: " .. tostring(writeError), true
	end
	if not patch.Remove then
		local written = Src.Read(module.Source, patch.Kind, patch.Key, patch.Path)
		if written ~= literal(patch.Value) then
			return false, "wrote the script but could not read the value back (" .. tostring(written) .. ")", false
		end
	end
	return true, "saved to " .. module.Name, false
end

-- playtest server copy: hands the edit to the running game (see Shared.StatPatch)
local patchCounter = 0
function Core.ApplyLive(patch)
	local folder = ReplicatedStorage:FindFirstChild(PATCH_FOLDER)
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = PATCH_FOLDER
		folder.Archivable = false
		folder.Parent = ReplicatedStorage
	end
	patchCounter = math.max(patchCounter, #folder:GetChildren()) + 1
	local value = Instance.new("StringValue")
	value.Name = string.format("%05d", patchCounter)
	value.Archivable = false
	value.Value = HttpService:JSONEncode({ Kind = patch.Kind, Key = patch.Key, Path = patch.Path, Value = patch.Value, Remove = patch.Remove == true })
	value.Parent = folder
	return true, "applied to the running game"
end

local function queuePending(patch)
	local pending = getSetting(KEY_PENDING)
	if type(pending) ~= "table" then
		pending = {}
	end
	table.insert(pending, { Id = HttpService:GenerateGUID(false), Patch = patch })
	setSetting(KEY_PENDING, pending)
end

local function requestLive(patch)
	local id = HttpService:GenerateGUID(false)
	local requests = getSetting(KEY_REQUESTS)
	if type(requests) ~= "table" then
		requests = {}
	end
	table.insert(requests, { Id = id, Patch = patch })
	setSetting(KEY_REQUESTS, requests)
	local deadline = os.clock() + 6
	while os.clock() < deadline do
		task.wait(0.2)
		local results = getSetting(KEY_RESULTS)
		local result = type(results) == "table" and results[id]
		if result then
			results[id] = nil
			setSetting(KEY_RESULTS, results)
			return result.Ok == true, tostring(result.Message)
		end
	end
	return false, "the playtest server did not answer"
end

Core.History = {} -- inverse patches of the edits made from this window, newest last

-- ok, message
function Core.Commit(patch, isUndo)
	patch.Remove = patch.Remove == true
	local old = Model.Get(patch.Kind, patch.Key, patch.Path)
	local inverse = { Kind = patch.Kind, Key = patch.Key, Path = table.clone(patch.Path), Value = old, Remove = old == nil,
		Label = patch.Key .. "." .. pathText(patch.Path) }
	if type(old) == "table" then
		inverse = nil -- removing a whole sub-table is not undoable field by field
	end
	local ok, message = Core.CommitRaw(patch)
	if ok and not isUndo and inverse then
		table.insert(Core.History, inverse)
		if #Core.History > 100 then
			table.remove(Core.History, 1)
		end
	end
	return ok, message
end

function Core.Undo()
	local inverse = table.remove(Core.History)
	if not inverse then
		return false, "nothing to undo"
	end
	local ok, message = Core.Commit(inverse, true)
	if not ok then
		table.insert(Core.History, inverse)
		return false, message
	end
	return true, "undid " .. inverse.Label .. " (" .. message .. ")"
end

function Core.CommitRaw(patch)
	local current = role()
	if current == "Edit" and not liveSessionActive() then
		local ok, message = recorded("Stats Editor: " .. patch.Key .. "." .. pathText(patch.Path), function()
			return Core.SaveToSource(patch)
		end)
		if ok then
			Model.Apply(patch)
		end
		return ok, message
	end
	Model.Apply(patch)
	local liveOk, liveMessage
	if current == "Server" then
		liveOk, liveMessage = Core.ApplyLive(patch)
	else
		liveOk, liveMessage = requestLive(patch)
	end
	local saveMessage
	if current == "Edit" then
		local ok, message, retry = Core.SaveToSource(patch)
		if ok then
			saveMessage = message
		elseif retry then
			queuePending(patch)
			saveMessage = "saved into the scripts when the playtest stops"
		else
			return false, message
		end
	else
		queuePending(patch)
		saveMessage = "saved into the scripts by the Edit window (now, or when the playtest stops)"
	end
	if liveOk then
		return true, liveMessage .. "; " .. saveMessage
	end
	return true, "NOT live (" .. tostring(liveMessage) .. "); " .. saveMessage
end

-- Edit copy: saves edits made in a playtest copy
local savingPending = false
local onPendingSaved = nil
local function savePending()
	if savingPending or role() ~= "Edit" then
		return
	end
	local pending = getSetting(KEY_PENDING)
	if type(pending) ~= "table" or #pending == 0 then
		return
	end
	savingPending = true
	local done, saved, failures = {}, 0, {}
	for _, entry in ipairs(pending) do
		local ok, message, retry = Core.SaveToSource(entry.Patch)
		if ok then
			saved += 1
			done[entry.Id] = true
			Model.Apply(entry.Patch)
		elseif not retry then
			done[entry.Id] = true
			table.insert(failures, entry.Patch.Key .. "." .. pathText(entry.Patch.Path) .. ": " .. tostring(message))
		end
	end
	local remaining = {}
	for _, entry in ipairs(getSetting(KEY_PENDING) or {}) do
		if not done[entry.Id] then
			table.insert(remaining, entry)
		end
	end
	setSetting(KEY_PENDING, remaining)
	savingPending = false
	if onPendingSaved and (saved > 0 or #failures > 0) then
		onPendingSaved(saved, failures)
	end
end

-- Server copy: applies edits asked for by the Edit / Client copies, and signals it is alive
local function serveRequests()
	local requests = getSetting(KEY_REQUESTS)
	if type(requests) ~= "table" or #requests == 0 then
		return
	end
	setSetting(KEY_REQUESTS, {})
	local results = getSetting(KEY_RESULTS)
	if type(results) ~= "table" then
		results = {}
	end
	for _, request in ipairs(requests) do
		local ok, message = pcall(Core.ApplyLive, request.Patch)
		Model.Apply(request.Patch)
		results[request.Id] = { Ok = ok, Message = ok and "applied to the running game" or tostring(message) }
	end
	setSetting(KEY_RESULTS, results)
end

--------------------------------------------------------------------------------------------------
-- Rows: which fields a tab shows for an entry
--------------------------------------------------------------------------------------------------
local function sortKeys(tbl)
	local keys = {}
	for key in pairs(tbl) do
		if type(key) == "string" then
			table.insert(keys, key)
		end
	end
	table.sort(keys, function(a, b)
		local ia, ib = ORDER_INDEX[a] or 1000, ORDER_INDEX[b] or 1000
		local la, lb = LONG_TEXT[a] and 1 or 0, LONG_TEXT[b] and 1 or 0
		if la ~= lb then
			return la < lb
		end
		if ia ~= ib then
			return ia < ib
		end
		return a < b
	end)
	return keys
end

local function isScalingTable(tbl)
	if type(tbl) ~= "table" then
		return false
	end
	local count = 0
	for key, value in pairs(tbl) do
		if type(key) ~= "string" or type(value) ~= "number" then
			return false
		end
		count += 1
	end
	return count > 0
end

-- flattens a definition table into rows { Path, Value, ReadOnly, Removable, Long }
local function collectRows(rows, tbl, prefix, depth, options)
	for _, key in ipairs(sortKeys(tbl)) do
		local value = tbl[key]
		local path = table.clone(prefix)
		table.insert(path, key)
		local kind = type(value)
		if IDENTITY[key] or (depth == 1 and (HIDDEN[key] or (options.Skip and options.Skip[key]))) then
			continue
		end
		if kind == "number" or kind == "boolean" then
			table.insert(rows, { Path = path, Value = value, Removable = options.Removable and options.Removable(path, tbl) })
		elseif kind == "string" then
			table.insert(rows, { Path = path, Value = value, ReadOnly = READ_ONLY[key] or false, Long = LONG_TEXT[key] or false })
		elseif kind == "table" and depth < 3 and not (#value > 0) then
			if next(value) == nil then
				table.insert(rows, { Path = path, Value = "{ }", ReadOnly = true, Note = "empty table - add a field below" })
			else
				collectRows(rows, value, path, depth + 1, options)
			end
		end
	end
end

local function removableStatOrScaling(path, parent)
	if path[1] == "Stats" and #path == 2 then
		return true
	end
	if #path >= 2 and isScalingTable(parent) then
		local count = 0
		for _ in pairs(parent) do
			count += 1
		end
		return count > 1
	end
	return false
end

-- returns target kind, key, rows, extra info for the selected entry of a tab
local function buildRows(tab, key)
	local rows = {}
	if tab == "Items" then
		local item = Model.Target("Item", key)
		if not item then
			return "Item", key, rows
		end
		table.insert(rows, { Path = { "Price" }, Value = item.Price or 0 })
		table.insert(rows, { Header = "Stat bonuses while equipped" })
		collectRows(rows, item.Stats or {}, { "Stats" }, 2, { Removable = removableStatOrScaling })
		table.insert(rows, { Add = "Stats" })
		table.insert(rows, { Header = "Text" })
		for _, field in ipairs({ "Name", "Description" }) do
			if type(item[field]) == "string" then
				table.insert(rows, { Path = { field }, Value = item[field], Long = LONG_TEXT[field] or false })
			end
		end
		return "Item", key, rows
	elseif tab == "Passives" then
		local item = Model.Target("Item", key)
		if not item then
			return "Item", key, rows
		end
		if type(item.Passive) == "table" then
			table.insert(rows, { Header = "Passive: " .. tostring(item.Passive.Name or "") })
			collectRows(rows, item.Passive, { "Passive" }, 2, { Removable = removableStatOrScaling })
			table.insert(rows, { Add = "Passive" })
		end
		if type(item.PassiveSplash) == "table" then
			table.insert(rows, { Header = "Passive splash (basic attacks hit around the target)" })
			collectRows(rows, item.PassiveSplash, { "PassiveSplash" }, 2, {})
		end
		if item.PassiveReflect ~= nil then
			table.insert(rows, { Header = "Passive reflect (share of damage taken sent back)" })
			table.insert(rows, { Path = { "PassiveReflect" }, Value = item.PassiveReflect })
		end
		return "Item", key, rows
	elseif tab == "Skills" then
		local ability = Model.Target("Ability", key)
		if not ability then
			return "Ability", key, rows
		end
		collectRows(rows, ability, {}, 1, { Removable = removableStatOrScaling })
		table.insert(rows, { Add = "" })
		return "Ability", key, rows
	elseif tab == "Heroes" then
		local class = Model.Target("Class", key)
		if not class then
			return "Class", key, rows
		end
		table.insert(rows, { Header = "Base stats" })
		collectRows(rows, class, {}, 1, { Skip = { Ability = true, Ratings = true, Projectile = true } })
		if type(class.Projectile) == "table" then
			table.insert(rows, { Header = "Basic attack projectile" })
			collectRows(rows, class.Projectile, { "Projectile" }, 2, {})
		end
		if type(class.Ability) == "table" then
			table.insert(rows, { Header = "Q ability: " .. tostring(class.Ability.Name or class.Ability.Key or "") })
			collectRows(rows, class.Ability, { "Ability" }, 2, { Removable = removableStatOrScaling })
			table.insert(rows, { Add = "Ability" })
		end
		if type(class.Ratings) == "table" then
			table.insert(rows, { Header = "Ratings (1-5, class select screen only)" })
			collectRows(rows, class.Ratings, { "Ratings" }, 2, {})
		end
		return "Class", key, rows
	end
	return nil, key, rows
end

--------------------------------------------------------------------------------------------------
-- Entries: the list on the left
--------------------------------------------------------------------------------------------------
local function entriesFor(tab, roleFilter, typeFilter, search)
	local entries = {}
	search = string.lower(search or "")
	local function matches(key, name)
		return search == "" or string.find(string.lower(key), search, 1, true) or string.find(string.lower(name or ""), search, 1, true)
	end
	if not Model.ItemDefs then
		return entries
	end
	if tab == "Items" or tab == "Passives" then
		for key, item in pairs(Model.ItemDefs.Items) do
			local hasPassive = type(item.Passive) == "table" or type(item.PassiveSplash) == "table" or item.PassiveReflect ~= nil
			if tab == "Passives" and not hasPassive then
				continue
			end
			local itemRole, itemType = Model.ItemRole(item), Model.ItemType(item)
			if (roleFilter == "All" or roleFilter == itemRole) and (typeFilter == "All" or typeFilter == itemType) and matches(key, item.Name) then
				local subtitle = itemType .. " · " .. itemRole .. " · " .. tostring(item.Price or 0) .. "g"
				if tab == "Passives" and type(item.Passive) == "table" then
					subtitle = tostring(item.Passive.Name or "") .. " · " .. itemRole
				end
				table.insert(entries, { Key = key, Title = item.Name or key, Subtitle = subtitle, Warn = tab == "Items" and Model.PriceWarning(key),
					Sort = itemType .. itemRole .. (item.Name or key) })
			end
		end
	elseif tab == "Skills" then
		for key, ability in pairs(Model.ItemDefs.Abilities) do
			local users = Model.AbilityUsers(key)
			local abilityRole = Model.AbilityRole(key)
			if (roleFilter == "All" or roleFilter == abilityRole) and matches(key, ability.Name) then
				local names = {}
				for _, itemKey in ipairs(users) do
					table.insert(names, Model.ItemDefs.Items[itemKey].Name or itemKey)
				end
				table.insert(entries, { Key = key, Title = ability.Name or key,
					Subtitle = (#names > 0 and table.concat(names, ", ") or "not used by an item") .. " · " .. abilityRole, Sort = abilityRole .. (ability.Name or key) })
			end
		end
	elseif tab == "Heroes" then
		for index, key in ipairs(Model.ClassDefs.Order or {}) do
			local class = Model.ClassDefs.Classes[key]
			if class and (roleFilter == "All" or roleFilter == key) and matches(key, class.DisplayName) then
				table.insert(entries, { Key = key, Title = class.DisplayName or key, Subtitle = tostring(class.Role or "") .. " · Q: " .. tostring(class.Ability and class.Ability.Name or "-"),
					Sort = string.format("%02d", index) })
			end
		end
	end
	table.sort(entries, function(a, b)
		return a.Sort < b.Sort
	end)
	return entries
end

--------------------------------------------------------------------------------------------------
-- UI
--------------------------------------------------------------------------------------------------
local FALLBACK_COLORS = {
	MainBackground = Color3.fromRGB(46, 46, 46), MainText = Color3.fromRGB(220, 220, 220), DimmedText = Color3.fromRGB(140, 140, 140),
	Button = Color3.fromRGB(60, 60, 60), ButtonText = Color3.fromRGB(220, 220, 220), ButtonBorder = Color3.fromRGB(34, 34, 34),
	MainButton = Color3.fromRGB(0, 120, 215), DialogMainButtonText = Color3.fromRGB(255, 255, 255), InputFieldBackground = Color3.fromRGB(37, 37, 37),
	InputFieldBorder = Color3.fromRGB(26, 26, 26), Item = Color3.fromRGB(53, 53, 53), Border = Color3.fromRGB(34, 34, 34),
	Titlebar = Color3.fromRGB(53, 53, 53), SubText = Color3.fromRGB(170, 170, 170), ErrorText = Color3.fromRGB(255, 100, 100),
	WarningText = Color3.fromRGB(255, 190, 60), LinkText = Color3.fromRGB(80, 170, 255),
}
local GOOD = Color3.fromRGB(90, 200, 110)
local WARN = Color3.fromRGB(255, 180, 60)
local BAD = Color3.fromRGB(255, 95, 95)

local function themeColor(name, modifier)
	local ok, color = pcall(function()
		return Studio.Theme:GetColor(Enum.StudioStyleGuideColor[name], Enum.StudioStyleGuideModifier[modifier or "Default"])
	end)
	return ok and color or FALLBACK_COLORS[name] or Color3.new(1, 0, 1)
end

local themed = setmetatable({}, { __mode = "k" })
local function paint(instance, property, name, modifier)
	themed[instance] = themed[instance] or {}
	themed[instance][property] = { name, modifier }
	instance[property] = themeColor(name, modifier)
end

local function repaintAll()
	for instance, properties in pairs(themed) do
		for property, spec in pairs(properties) do
			pcall(function()
				instance[property] = themeColor(spec[1], spec[2])
			end)
		end
	end
end

local function new(className, properties)
	local instance = Instance.new(className)
	for key, value in pairs(properties or {}) do
		if key ~= "Parent" then
			instance[key] = value
		end
	end
	if properties and properties.Parent then
		instance.Parent = properties.Parent
	end
	return instance
end

local function corner(instance, radius)
	new("UICorner", { CornerRadius = UDim.new(0, radius or 4), Parent = instance })
end

local function label(properties)
	local instance = new("TextLabel", {
		BackgroundTransparency = 1, Font = Enum.Font.SourceSans, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	for key, value in pairs(properties) do
		if key ~= "Parent" and key ~= "ColorName" then
			instance[key] = value
		end
	end
	if not properties.TextColor3 then
		paint(instance, "TextColor3", properties.ColorName or "MainText")
	end
	instance.Parent = properties.Parent
	return instance
end

local function button(text, properties, main)
	local instance = new("TextButton", {
		Text = text, Font = main and Enum.Font.SourceSansBold or Enum.Font.SourceSans, TextSize = 14, AutoButtonColor = true,
		Size = UDim2.new(0, 80, 0, 24),
	})
	for key, value in pairs(properties or {}) do
		if key ~= "Parent" then
			instance[key] = value
		end
	end
	paint(instance, "BackgroundColor3", main and "MainButton" or "Button")
	paint(instance, "TextColor3", main and "DialogMainButtonText" or "ButtonText")
	corner(instance, 4)
	local stroke = new("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Thickness = 1, Parent = instance })
	paint(stroke, "Color", "ButtonBorder")
	instance.Parent = properties and properties.Parent
	return instance
end

local function textBox(properties)
	local instance = new("TextBox", {
		Font = Enum.Font.SourceSans, TextSize = 14, ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0, 120, 0, 24),
	})
	for key, value in pairs(properties) do
		if key ~= "Parent" then
			instance[key] = value
		end
	end
	paint(instance, "BackgroundColor3", "InputFieldBackground")
	paint(instance, "TextColor3", "MainText")
	paint(instance, "PlaceholderColor3", "DimmedText")
	corner(instance, 3)
	local stroke = new("UIStroke", { ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Thickness = 1, Parent = instance })
	paint(stroke, "Color", "InputFieldBorder")
	new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), Parent = instance })
	instance.Parent = properties.Parent
	return instance
end

local State = { Tab = "Items", Role = "All", Type = "All", Search = "", Selected = {}, Message = nil, MessageColor = nil, Busy = false }
local UI = {}

local function setStatus(message, color)
	State.Message = message
	State.MessageColor = color
	if UI.Status then
		UI.Status.Text = message or ""
		if color then
			UI.Status.TextColor3 = color
		else
			paint(UI.Status, "TextColor3", "SubText")
		end
	end
end

local function modeText()
	local current = role()
	if current == "Edit" then
		if liveSessionActive() then
			return "PLAYTEST RUNNING - edits apply live and save into the scripts", GOOD
		end
		return "EDIT MODE - edits save into the scripts", nil
	elseif current == "Server" then
		return "PLAYTEST (server) - edits apply live and are saved into the scripts", GOOD
	end
	return "PLAYTEST (client) - edits are sent to the server and saved into the scripts", GOOD
end

function UI.Build(container)
	local root = new("Frame", { Size = UDim2.fromScale(1, 1), BorderSizePixel = 0, Parent = container })
	paint(root, "BackgroundColor3", "MainBackground")
	UI.Root = root

	-- top bar: tabs + reload
	local top = new("Frame", { Size = UDim2.new(1, 0, 0, 36), BorderSizePixel = 0, Parent = root })
	paint(top, "BackgroundColor3", "Titlebar")
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Parent = top })
	new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = top })
	UI.TabButtons = {}
	for index, tab in ipairs(TABS) do
		local tabButton = button(tab.Title, { Size = UDim2.new(0, 110, 0, 26), LayoutOrder = index, Parent = top }, State.Tab == tab.Key)
		tabButton.MouseButton1Click:Connect(function()
			UI.SetTab(tab.Key)
		end)
		UI.TabButtons[tab.Key] = tabButton
	end
	local undo = button("Undo", { Size = UDim2.new(0, 80, 0, 26), LayoutOrder = 98, Parent = top })
	UI.UndoButton = undo
	undo.MouseButton1Click:Connect(function()
		if State.Busy then
			return
		end
		State.Busy = true
		local ok, message = Core.Undo()
		State.Busy = false
		setStatus(ok and message or ("Undo: " .. tostring(message)), ok and GOOD or WARN)
		UI.RebuildList()
		UI.RebuildDetail()
	end)
	local reload = button("Reload", { Size = UDim2.new(0, 70, 0, 26), LayoutOrder = 99, Parent = top })
	reload.MouseButton1Click:Connect(function()
		Model.Load()
		setStatus(Model.Error and ("Could not load the definitions: " .. Model.Error) or "Reloaded from the scripts", Model.Error and BAD or nil)
		UI.RebuildList()
		UI.RebuildDetail()
	end)

	-- left: filters + list
	local left = new("Frame", { Position = UDim2.new(0, 0, 0, 36), Size = UDim2.new(0, 270, 1, -60), BorderSizePixel = 0, Parent = root })
	paint(left, "BackgroundColor3", "MainBackground")
	UI.SearchBox = textBox({ PlaceholderText = "Search...", Position = UDim2.new(0, 8, 0, 8), Size = UDim2.new(1, -16, 0, 26), Text = "", Parent = left })
	UI.SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
		State.Search = UI.SearchBox.Text
		UI.RebuildList()
	end)
	local roleRow = new("Frame", { Position = UDim2.new(0, 8, 0, 40), Size = UDim2.new(1, -16, 0, 48), BackgroundTransparency = 1, Parent = left })
	new("UIGridLayout", { CellSize = UDim2.new(0, 60, 0, 20), CellPadding = UDim2.new(0, 4, 0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = roleRow })
	UI.RoleButtons = {}
	for index, roleName in ipairs(ROLES) do
		local chip = button(roleName, { TextSize = 12, LayoutOrder = index, Parent = roleRow }, State.Role == roleName)
		chip.MouseButton1Click:Connect(function()
			State.Role = roleName
			UI.RefreshChips()
			UI.RebuildList()
		end)
		UI.RoleButtons[roleName] = chip
	end
	local typeRow = new("Frame", { Position = UDim2.new(0, 8, 0, 92), Size = UDim2.new(1, -16, 0, 20), BackgroundTransparency = 1, Parent = left })
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = typeRow })
	UI.TypeButtons = {}
	for index, typeName in ipairs(ITEM_TYPES) do
		local chip = button(typeName, { TextSize = 12, Size = UDim2.new(0, 60, 0, 20), LayoutOrder = index, Parent = typeRow }, State.Type == typeName)
		chip.MouseButton1Click:Connect(function()
			State.Type = typeName
			UI.RefreshChips()
			UI.RebuildList()
		end)
		UI.TypeButtons[typeName] = chip
	end
	UI.TypeRow = typeRow
	local list = new("ScrollingFrame", {
		Position = UDim2.new(0, 0, 0, 118), Size = UDim2.new(1, 0, 1, -118), BorderSizePixel = 0, BackgroundTransparency = 1,
		ScrollBarThickness = 6, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), Parent = left,
	})
	new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
	new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 2), Parent = list })
	UI.List = list
	local divider = new("Frame", { Position = UDim2.new(0, 270, 0, 36), Size = UDim2.new(0, 1, 1, -60), BorderSizePixel = 0, Parent = root })
	paint(divider, "BackgroundColor3", "Border")

	-- right: detail
	local right = new("Frame", { Position = UDim2.new(0, 271, 0, 36), Size = UDim2.new(1, -271, 1, -60), BackgroundTransparency = 1, Parent = root })
	UI.Title = label({ Position = UDim2.new(0, 12, 0, 6), Size = UDim2.new(1, -24, 0, 24), Font = Enum.Font.SourceSansBold, TextSize = 20, Text = "", Parent = right })
	UI.Subtitle = label({ Position = UDim2.new(0, 12, 0, 30), Size = UDim2.new(1, -24, 0, 18), TextSize = 13, ColorName = "SubText", Text = "", Parent = right })
	UI.ValueLine = label({ Position = UDim2.new(0, 12, 0, 50), Size = UDim2.new(1, -24, 0, 18), TextSize = 13, RichText = true, Text = "", Parent = right })
	local detail = new("ScrollingFrame", {
		Position = UDim2.new(0, 0, 0, 74), Size = UDim2.new(1, 0, 1, -74), BorderSizePixel = 0, BackgroundTransparency = 1,
		ScrollBarThickness = 6, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), Parent = right,
	})
	new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = detail })
	new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 12), Parent = detail })
	UI.Detail = detail

	-- bottom: mode + status
	local bottom = new("Frame", { Position = UDim2.new(0, 0, 1, -24), Size = UDim2.new(1, 0, 0, 24), BorderSizePixel = 0, Parent = root })
	paint(bottom, "BackgroundColor3", "Titlebar")
	UI.Mode = label({ Position = UDim2.new(0, 8, 0, 0), Size = UDim2.new(0.45, -8, 1, 0), TextSize = 12, Font = Enum.Font.SourceSansBold, Text = "", Parent = bottom })
	UI.Status = label({ Position = UDim2.new(0.45, 0, 0, 0), Size = UDim2.new(0.55, -8, 1, 0), TextSize = 12, ColorName = "SubText", TextXAlignment = Enum.TextXAlignment.Right, Text = "", Parent = bottom })

	UI.RefreshChips()
	UI.RebuildList()
	UI.RebuildDetail()
	UI.UpdateMode()
end

function UI.UpdateMode()
	if not UI.Mode then
		return
	end
	local text, color = modeText()
	UI.Mode.Text = text
	if color then
		UI.Mode.TextColor3 = color
	else
		paint(UI.Mode, "TextColor3", "MainText")
	end
end

function UI.RefreshChips()
	for key, chip in pairs(UI.TabButtons or {}) do
		paint(chip, "BackgroundColor3", key == State.Tab and "MainButton" or "Button")
		paint(chip, "TextColor3", key == State.Tab and "DialogMainButtonText" or "ButtonText")
	end
	for key, chip in pairs(UI.RoleButtons or {}) do
		paint(chip, "BackgroundColor3", key == State.Role and "MainButton" or "Button")
		paint(chip, "TextColor3", key == State.Role and "DialogMainButtonText" or "ButtonText")
	end
	for key, chip in pairs(UI.TypeButtons or {}) do
		paint(chip, "BackgroundColor3", key == State.Type and "MainButton" or "Button")
		paint(chip, "TextColor3", key == State.Type and "DialogMainButtonText" or "ButtonText")
	end
	if UI.TypeRow then
		UI.TypeRow.Visible = State.Tab == "Items" or State.Tab == "Passives"
	end
end

function UI.SetTab(tab)
	State.Tab = tab
	if tab == "Heroes" and State.Role == "General" then
		State.Role = "All"
	end
	UI.RefreshChips()
	UI.RebuildList()
	UI.RebuildDetail()
end

function UI.Select(key)
	State.Selected[State.Tab] = key
	UI.RebuildList()
	UI.RebuildDetail()
end

function UI.RebuildList()
	if not UI.List then
		return
	end
	for _, child in ipairs(UI.List:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local entries = entriesFor(State.Tab, State.Role, State.Tab == "Heroes" and "All" or (State.Tab == "Skills" and "All" or State.Type), State.Search)
	UI.Entries = entries
	local selected = State.Selected[State.Tab]
	for index, entry in ipairs(entries) do
		local row = new("TextButton", { Text = "", AutoButtonColor = true, Size = UDim2.new(1, 0, 0, 38), LayoutOrder = index, BorderSizePixel = 0, Parent = UI.List })
		paint(row, "BackgroundColor3", "Item", entry.Key == selected and "Selected" or "Default")
		corner(row, 4)
		label({ Position = UDim2.new(0, 8, 0, 2), Size = UDim2.new(1, -30, 0, 18), Font = Enum.Font.SourceSansBold, Text = entry.Title, Parent = row,
			ColorName = entry.Key == selected and "MainText" or "MainText" })
		label({ Position = UDim2.new(0, 8, 0, 19), Size = UDim2.new(1, -16, 0, 16), TextSize = 12, ColorName = "SubText", Text = entry.Subtitle, Parent = row })
		if entry.Warn then
			label({ Position = UDim2.new(1, -24, 0, 2), Size = UDim2.new(0, 18, 0, 18), Text = "⚠", TextColor3 = WARN, TextXAlignment = Enum.TextXAlignment.Center, Parent = row })
		end
		row.MouseButton1Click:Connect(function()
			UI.Select(entry.Key)
		end)
	end
	if #entries == 0 then
		label({ Size = UDim2.new(1, 0, 0, 30), ColorName = "DimmedText", Text = Model.Error and "Could not load the definitions (see status)" or "Nothing matches the filters", Parent = UI.List })
	end
end

local function valueLineText(itemKey)
	local stats, skill, passive, total, price = Model.Value(itemKey)
	if not total then
		return ""
	end
	local delta = total - price
	local color = math.abs(delta) > PRICE_TOLERANCE and "#FFB43C" or "#5AC86E"
	local verdict = math.abs(delta) > PRICE_TOLERANCE and string.format("  ⚠ value is %s%dg from price (SharedGameRules: within ±%dg)", delta > 0 and "+" or "", delta, PRICE_TOLERANCE)
		or string.format("  ✓ within ±%dg", PRICE_TOLERANCE)
	return string.format('Value: stats %dg + skill %dg + passive %dg = <b>%dg</b> · price <b>%dg</b><font color="%s">%s</font>', stats, skill, passive, total, price, color, verdict)
end

local function commitRow(kind, key, path, value, remove)
	if State.Busy then
		setStatus("Busy - wait for the previous edit", WARN)
		return false
	end
	State.Busy = true
	setStatus("Saving " .. key .. "." .. pathText(path) .. "...", nil)
	local ok, message = Core.Commit({ Kind = kind, Key = key, Path = path, Value = value, Remove = remove })
	State.Busy = false
	if ok then
		setStatus(string.format("%s.%s %s - %s", key, pathText(path), remove and "removed" or ("= " .. displayValue(value)), message), GOOD)
	else
		setStatus("Not saved: " .. tostring(message), BAD)
	end
	UI.RebuildList()
	UI.RebuildDetail()
	return ok, message
end

local function rowFrame(order, height)
	return new("Frame", { Size = UDim2.new(1, 0, 0, height or 26), BackgroundTransparency = 1, LayoutOrder = order, Parent = UI.Detail })
end

function UI.RebuildDetail()
	if not UI.Detail then
		return
	end
	if UI.UndoButton then
		UI.UndoButton.Text = #Core.History > 0 and string.format("Undo (%d)", #Core.History) or "Undo"
	end
	for _, child in ipairs(UI.Detail:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local key = State.Selected[State.Tab]
	local kind, _, rows = buildRows(State.Tab, key or "")
	UI.Rows = rows
	UI.Title.Text, UI.Subtitle.Text, UI.ValueLine.Text = "", "", ""
	if not key or #rows == 0 then
		UI.Title.Text = key and ("'" .. key .. "' not found") or "Pick an entry on the left"
		return
	end
	if kind == "Item" then
		local item = Model.Target("Item", key)
		UI.Title.Text = item.Name or key
		local ability = item.Ability and Model.Target("Ability", item.Ability)
		UI.Subtitle.Text = string.format("%s · %s · %s%s", key, Model.ItemType(item), Model.ItemRole(item),
			ability and (" · skill: " .. tostring(ability.Name or item.Ability)) or "")
		UI.ValueLine.Text = valueLineText(key)
	elseif kind == "Ability" then
		local ability = Model.Target("Ability", key)
		UI.Title.Text = ability.Name or key
		local users = Model.AbilityUsers(key)
		UI.Subtitle.Text = key .. " · used by " .. (#users > 0 and table.concat(users, ", ") or "no item") .. " · " .. tostring(ability.Targeting or "")
		UI.ValueLine.Text = "Damage / Shield / Heal are scaling tables: AD = 2.4 means 240% of attack damage, MP = magic power, HP = max health."
	elseif kind == "Class" then
		local class = Model.Target("Class", key)
		UI.Title.Text = class.DisplayName or key
		UI.Subtitle.Text = key .. " · " .. tostring(class.Role or "") .. " · " .. tostring(class.AttackType or "")
		UI.ValueLine.Text = "Q ability Damage uses the same scaling tables (AD / MP / HP)."
	end
	for index, row in ipairs(rows) do
		local order = index * 10
		if row.Header then
			local frame = rowFrame(order, 26)
			label({ Position = UDim2.new(0, 0, 0, 6), Size = UDim2.new(1, 0, 0, 18), Font = Enum.Font.SourceSansBold, TextSize = 14, ColorName = "SubText", Text = string.upper(row.Header), Parent = frame })
		elseif row.Add ~= nil then
			local frame = rowFrame(order, 30)
			local prefix = row.Add
			local keyBox = textBox({ PlaceholderText = prefix == "" and "Field (e.g. Stun or Damage.MP)" or (prefix == "Stats" and "Stat (e.g. Armor)" or "Field (e.g. Duration)"),
				Position = UDim2.new(0, 0, 0, 3), Size = UDim2.new(0, 200, 0, 24), Text = "", Parent = frame })
			local valueBox = textBox({ PlaceholderText = "Value", Position = UDim2.new(0, 206, 0, 3), Size = UDim2.new(0, 90, 0, 24), Text = "", Parent = frame })
			local addButton = button(prefix == "Stats" and "+ Add stat" or "+ Add field", { Position = UDim2.new(0, 302, 0, 3), Size = UDim2.new(0, 90, 0, 24), Parent = frame }, true)
			addButton.MouseButton1Click:Connect(function()
				local fieldPath = splitPath(keyBox.Text)
				if #fieldPath == 0 then
					setStatus("Type a field name first", WARN)
					return
				end
				if prefix ~= "" then
					table.insert(fieldPath, 1, prefix)
				end
				local ok, value = parseInput(valueBox.Text, nil)
				if not ok or valueBox.Text == "" then
					setStatus("Type a value (number, true/false or \"text\")", WARN)
					return
				end
				commitRow(kind, key, fieldPath, value, false)
			end)
			if prefix == "Stats" then
				local chips = rowFrame(order + 5, 22)
				new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 3), Wraps = true, Parent = chips })
				chips.AutomaticSize = Enum.AutomaticSize.Y
				local item = Model.Target("Item", key)
				for _, stat in ipairs(STAT_SUGGESTIONS) do
					if not (item and item.Stats and item.Stats[stat] ~= nil) then
						local chip = button(stat, { TextSize = 11, Size = UDim2.new(0, 0, 0, 18), AutomaticSize = Enum.AutomaticSize.X, Parent = chips })
						new("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5), Parent = chip })
						chip.MouseButton1Click:Connect(function()
							keyBox.Text = stat
							valueBox:CaptureFocus()
						end)
					end
				end
			end
		else
			local long = row.Long
			local frame = rowFrame(order, long and 54 or 26)
			if long then
				frame.AutomaticSize = Enum.AutomaticSize.Y
			end
			local name = pathText(row.Path)
			label({ Position = UDim2.new(0, 0, 0, 0), Size = UDim2.new(0, 190, 0, 24), Text = name, Parent = frame })
			local hint = nil
			if type(row.Value) == "number" and row.Value > 0 and row.Value < 1 and not string.find(name, "Cooldown", 1, true) then
				hint = string.format("= %s%%", formatNumber(row.Value * 100))
			end
			local box = textBox({
				Position = UDim2.new(0, 194, 0, 0), Text = displayValue(row.Value), TextEditable = not row.ReadOnly,
				Size = long and UDim2.new(1, -194, 0, 50) or (type(row.Value) == "string" and UDim2.new(1, -224, 0, 24) or UDim2.new(0, 110, 0, 24)),
				TextWrapped = long or false, MultiLine = false, TextYAlignment = long and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center,
				Parent = frame,
			})
			if long then
				box.AutomaticSize = Enum.AutomaticSize.Y
			end
			if row.ReadOnly then
				paint(box, "TextColor3", "DimmedText")
			end
			if hint then
				label({ Position = UDim2.new(0, 338, 0, 0), Size = UDim2.new(0, 90, 0, 24), TextSize = 12, ColorName = "DimmedText", Text = hint, Parent = frame })
			end
			if row.Note then
				label({ Position = UDim2.new(0, 338, 0, 0), Size = UDim2.new(1, -338, 0, 24), TextSize = 12, ColorName = "DimmedText", Text = row.Note, Parent = frame })
			end
			if row.Removable then
				local remove = button("×", { Position = UDim2.new(0, 308, 0, 0), Size = UDim2.new(0, 24, 0, 24), Parent = frame })
				remove.MouseButton1Click:Connect(function()
					commitRow(kind, key, row.Path, nil, true)
				end)
			end
			if not row.ReadOnly then
				box.FocusLost:Connect(function()
					local text = box.Text
					if text == displayValue(row.Value) then
						return
					end
					local ok, value = parseInput(text, row.Value)
					if not ok then
						setStatus(name .. ": " .. value, BAD)
						box.Text = displayValue(row.Value)
						return
					end
					if value == row.Value then
						box.Text = displayValue(row.Value)
						return
					end
					commitRow(kind, key, row.Path, value, false)
				end)
			end
		end
	end
end

--------------------------------------------------------------------------------------------------
-- Plugin wiring
--------------------------------------------------------------------------------------------------
Model.Load()

local container = nil
local toolbar = plugin:CreateToolbar("Ruinfall Stats")
local toolbarButton = toolbar:CreateButton("RuinfallStatsEditor", "Edit RUINFALL item stats, item passives, item skills and hero classes", "", "Stats Editor")
toolbarButton.ClickableWhenViewportHidden = true
local info = DockWidgetPluginGuiInfo.new(Enum.InitialDockState.Float, false, false, 860, 620, 700, 460)
container = plugin:CreateDockWidgetPluginGui("RuinfallStatsEditor", info)
container.Title = "Ruinfall Stats Editor"
container.Name = "RuinfallStatsEditor"
UI.Build(container)
toolbarButton.Click:Connect(function()
	container.Enabled = not container.Enabled
end)
container:GetPropertyChangedSignal("Enabled"):Connect(function()
	toolbarButton:SetActive(container.Enabled)
	if container.Enabled then
		if Model.Error or role() == "Edit" then
			Model.Load()
		end
		UI.RebuildList()
		UI.RebuildDetail()
	end
end)
toolbarButton:SetActive(container.Enabled)
local themeConnection = Studio.ThemeChanged:Connect(repaintAll)
if Model.Error then
	setStatus("Could not load the definitions: " .. Model.Error, BAD)
end

onPendingSaved = function(saved, failures)
	if #failures > 0 then
		setStatus(string.format("Saved %d playtest edit(s); %d failed: %s", saved, #failures, failures[1]), BAD)
	else
		setStatus(string.format("Saved %d playtest edit(s) into the scripts", saved), GOOD)
	end
	UI.RebuildList()
	UI.RebuildDetail()
end

-- background: heartbeat + live requests (server copy), saving playtest edits (edit copy)
local alive = true
task.spawn(function()
	local beatClock = 0
	while alive do
		local current = role()
		if current == "Server" then
			if os.clock() - beatClock > 2 then
				beatClock = os.clock()
				setSetting(KEY_LIVE, nowMs())
			end
			pcall(serveRequests)
		elseif current == "Edit" then
			pcall(savePending)
		end
		pcall(UI.UpdateMode)
		task.wait(current == "Server" and 0.3 or 1.5)
	end
end)

-- automation hook (used by tooling / tests; harmless for users)
local hook = CoreGui:FindFirstChild("RuinfallStatsEditorHook")
if hook then
	hook:Destroy()
end
hook = new("BindableFunction", { Name = "RuinfallStatsEditorHook", Archivable = false })
hook.OnInvoke = function(command, a, b, c, d, e)
	if command == "version" then
		return VERSION
	elseif command == "tab" then
		UI.SetTab(a)
		local keys = {}
		for _, entry in ipairs(UI.Entries or {}) do
			table.insert(keys, entry.Key .. (entry.Warn and "!" or ""))
		end
		return keys
	elseif command == "filter" then
		State.Role, State.Type, State.Search = a or "All", b or "All", c or ""
		UI.RefreshChips()
		UI.RebuildList()
		return #(UI.Entries or {})
	elseif command == "select" then
		UI.Select(a)
		local list = {}
		for _, row in ipairs(UI.Rows or {}) do
			if row.Path then
				table.insert(list, pathText(row.Path) .. "=" .. displayValue(row.Value) .. (row.ReadOnly and "(ro)" or "") .. (row.Removable and "(x)" or ""))
			elseif row.Header then
				table.insert(list, "#" .. row.Header)
			end
		end
		return list, UI.ValueLine and UI.ValueLine.Text
	elseif command == "commit" then
		-- ("commit", kind, key, "Path.To.Field", value, remove)
		return Core.Commit({ Kind = a, Key = b, Path = splitPath(c), Value = d, Remove = false })
	elseif command == "remove" then
		return Core.Commit({ Kind = a, Key = b, Path = splitPath(c), Remove = true })
	elseif command == "edit" then
		-- dry run on a given source text: ("edit", src, kind, key, path, value) -> new source
		return Src.Edit(a, b, c, splitPath(d), e, false)
	elseif command == "undo" then
		return Core.Undo()
	elseif command == "value" then
		return Model.Value(a)
	elseif command == "status" then
		return State.Message
	elseif command == "reload" then
		Model.Load()
		return Model.Error
	end
	return nil
end
hook.Parent = CoreGui

plugin.Unloading:Connect(function()
	alive = false
	themeConnection:Disconnect()
	if hook then
		hook:Destroy()
	end
end)
