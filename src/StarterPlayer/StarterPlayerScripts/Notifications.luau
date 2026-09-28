-- Notifications: toast feed (right side) and large center banners.

-- Services
local TweenService = game:GetService("TweenService")

local UITheme = require(script.Parent:WaitForChild("UITheme"))

-- Constants
local COLORS = UITheme.Colors
local FONTS = UITheme.Fonts
local New, Label = UITheme.New, UITheme.Label
local TOAST_DURATION = 4
local MAX_TOASTS = 6
local BANNER_DURATION = 3

-- State
local Notifications = {}
Notifications.__index = Notifications

function Notifications.new(screen)
	local self = setmetatable({}, Notifications)
	self.Toasts = {}
	self.Counter = 0
	self.BannerToken = 0

	self.Feed = New("Frame", { Name = "Feed", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 250), Size = UDim2.fromOffset(360, 300), BackgroundTransparency = 1, ZIndex = 30, Parent = screen })
	New("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, HorizontalAlignment = Enum.HorizontalAlignment.Right, Parent = self.Feed })
	local feedScale = New("UIScale", { Parent = self.Feed })
	local bannerScale = New("UIScale", { Parent = nil })
	local function rescale()
		local viewport = workspace.CurrentCamera.ViewportSize
		local value = math.clamp(math.min(viewport.X / 1280, viewport.Y / 720), 0.55, 1)
		feedScale.Scale = value
		bannerScale.Scale = value
	end
	rescale()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	self.BannerScale = bannerScale

	self.Banner = New("Frame", { Name = "Banner", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3), Size = UDim2.fromOffset(900, 110), BackgroundTransparency = 1, Visible = false, ZIndex = 40, Parent = screen })
	self.BannerTitle = Label({ Text = "", Font = FONTS.Title, TextSize = 48, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.35, Size = UDim2.new(1, 0, 0, 56), ZIndex = 41, Parent = self.Banner })
	self.BannerSub = Label({ Text = "", Font = FONTS.Bold, TextSize = 19, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.45, TextWrapped = true, Position = UDim2.fromOffset(0, 58), Size = UDim2.new(1, 0, 0, 44), ZIndex = 41, Parent = self.Banner })
	self.BannerScale.Parent = self.Banner
	return self
end

function Notifications:ShowToast(text, style, color)
	self.Counter += 1
	local accent = color or UITheme.StyleColors[style] or COLORS.Accent
	local frame = New("Frame", { Name = "Toast", Size = UDim2.fromOffset(360, 34), BackgroundColor3 = COLORS.Panel, BackgroundTransparency = 0.12, LayoutOrder = -self.Counter, ZIndex = 30, Parent = self.Feed })
	UITheme.Corner(frame, 8)
	local bar = New("Frame", { Size = UDim2.fromOffset(4, 34), BackgroundColor3 = accent, ZIndex = 31, Parent = frame })
	UITheme.Corner(bar, 2)
	local label = Label({ Text = text, Font = FONTS.Bold, TextSize = 14, TextColor3 = style == "Info" and COLORS.Text or accent, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -22, 1, 0), ZIndex = 31, Parent = frame })
	table.insert(self.Toasts, frame)
	while #self.Toasts > MAX_TOASTS do
		local oldest = table.remove(self.Toasts, 1)
		oldest:Destroy()
	end
	task.delay(TOAST_DURATION, function()
		if not frame.Parent then
			return
		end
		local fade = TweenInfo.new(0.4)
		TweenService:Create(frame, fade, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(bar, fade, { BackgroundTransparency = 1 }):Play()
		TweenService:Create(label, fade, { TextTransparency = 1 }):Play()
		task.wait(0.45)
		local index = table.find(self.Toasts, frame)
		if index then
			table.remove(self.Toasts, index)
		end
		frame:Destroy()
	end)
end

function Notifications:ShowBanner(title, sub, style, color)
	self.BannerToken += 1
	local token = self.BannerToken
	local accent = color or UITheme.StyleColors[style] or COLORS.Text
	self.BannerTitle.Text = title
	self.BannerTitle.TextColor3 = accent
	self.BannerSub.Text = sub or ""
	self.BannerTitle.TextTransparency = 0
	self.BannerSub.TextTransparency = 0
	self.Banner.Visible = true
	self.Banner.Position = UDim2.fromScale(0.5, 0.28)
	TweenService:Create(self.Banner, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Position = UDim2.fromScale(0.5, 0.3) }):Play()
	task.delay(BANNER_DURATION, function()
		if self.BannerToken ~= token then
			return
		end
		local fade = TweenInfo.new(0.5)
		TweenService:Create(self.BannerTitle, fade, { TextTransparency = 1 }):Play()
		TweenService:Create(self.BannerSub, fade, { TextTransparency = 1 }):Play()
		task.wait(0.5)
		if self.BannerToken == token then
			self.Banner.Visible = false
		end
	end)
end

function Notifications:Push(payload)
	if type(payload) ~= "table" or type(payload.Text) ~= "string" then
		return
	end
	local options = payload.Options or {}
	if options.Banner then
		self:ShowBanner(payload.Text, options.Sub, payload.Style, options.Color)
	else
		local text = options.Sub and (payload.Text .. " - " .. options.Sub) or payload.Text
		self:ShowToast(text, payload.Style, options.Color)
	end
end

return Notifications
