-- WordChain Helper | v4.1 (Auto Ranked Queue)
-- Changes from v4.0:
--   • isAutoFillON = true by default
--   • TYPING_SPEED_MAX = 0.99, default delay 0.20
--   • AUTO_RANK = true by default, toggle ได้
--   • เพิ่ม AUTO_RANK system (กด ranked + 1v1 อัตโนมัติหลังชนะ)

local Players       = game:GetService("Players")
local TweenService  = game:GetService("TweenService")
local UIS           = game:GetService("UserInputService")
local VIM           = game:GetService("VirtualInputManager")
local LP            = Players.LocalPlayer
local PGui          = LP:WaitForChild("PlayerGui")

local CFG = {
    SCAN_RATE   = 0.4,
    MIN_TXTSIZE = 14,
    MIN_LEN     = 1,
    MAX_LEN     = 40,
    MAX_SUGGEST = 30,
    MIN_SUGGEST_CHARS = 6,

    TYPING_SPEED_MIN = 0.02,
    TYPING_SPEED_MAX = 0.99,

    SUBMIT_DELAY         = 0.1,
    VERIFY_RETRIES       = 4,
    MOBILE_HIDE_KEYBOARD = true,

    KEY_REMOVE   = Enum.KeyCode.LeftAlt,
    KEY_RESET    = Enum.KeyCode.Delete,
    KEY_AUTOFILL = Enum.KeyCode.Tab,
    KEY_DUMP     = Enum.KeyCode.Insert,

    TRACK_USED           = true,
    HISTORY_VISIBLE_ONLY = true,
    CLEAR_AFTER_EMPTY    = 8,
    LOG_STRIP_PREFIX     = true,

    TYPO_CHANCE_T1  = 22,
    TYPO_CHANCE_T2  = 10,
    TYPO_NOTICE_LO  = 220,
    TYPO_NOTICE_HI  = 580,
    TYPO_FIX_LO     = 80,
    TYPO_FIX_HI     = 200,

    DIACRITIC_MULT  = 1.85,

    AUTO_RANK        = true,
    RANK_QUEUE_DELAY = 2.5,
    RANK_MODE_DELAY  = 1.2,
    RANK_FIND_TIMEOUT = 10,
}

local CURRENT_SPEED_DELAY = 0.20

-- ════════════════════════════════════════════
--  THAI DIACRITIC / TYPO TABLES
-- ════════════════════════════════════════════
local THAI_DIACRITICS = {}
for _, cp in ipairs({
    0x0E31, 0x0E34, 0x0E35, 0x0E36, 0x0E37,
    0x0E38, 0x0E39, 0x0E47, 0x0E48, 0x0E49,
    0x0E4A, 0x0E4B, 0x0E4C, 0x0E4D, 0x0E4E,
}) do THAI_DIACRITICS[cp] = true end

local TYPO_POOL = {
    "ก","ข","ค","ง","จ","ช","ด","ต","ท","น",
    "บ","ป","พ","ม","ย","ร","ล","ว","ส","ห","อ",
}

local PATH_WHITELIST    = { "InputBar", "Match", "GameWord", "CurrentWord", "WordDisplay" }
local PATH_BLACKLIST    = { "Menu", "Settings", "Lobby", "Profile", "Button", "Mode", "Code" }
local HISTORY_KEYWORDS  = { "History", "UsedWords", "WordLog", "WordList" }

local SOURCE_URL      = "https://raw.githubusercontent.com/PyThaiNLP/pythainlp/dev/pythainlp/corpus/words_th.txt"
local CACHE_PATH      = "WordDB_ptnlp.txt"
local FREQ_SOURCE_URL = "https://raw.githubusercontent.com/PyThaiNLP/pythainlp/dev/pythainlp/corpus/tnc_freq.txt"
local FREQ_CACHE_PATH = "WordFreq_tnc.txt"

local COLORS = {
    bg       = Color3.fromHex("0D0D0D"),
    border   = Color3.fromHex("2A2A2A"),
    accent   = Color3.fromHex("4CFFE8"),
    text     = Color3.fromHex("EAEAEA"),
    dim      = Color3.fromHex("888888"),
    del_bg   = Color3.fromHex("1E1010"),
    del_txt  = Color3.fromHex("FF6B6B"),
    rst_bg   = Color3.fromHex("101E1A"),
    rst_txt  = Color3.fromHex("4CFFE8"),
    set_bg   = Color3.fromHex("14181C"),
    set_txt  = Color3.fromHex("AEB4BA"),
    auto_txt = Color3.fromHex("44FF77"),
    auto_on  = Color3.fromHex("2E7D32"),
    ice      = Color3.fromHex("88CCFF"),
    rank_on  = Color3.fromHex("7B2FBE"),
    rank_txt = Color3.fromHex("D4AAFF"),
}

-- ════════════════════════════════════════════
--  DYNAMIC ISLAND MODULE  (inlined IIFE)
-- ════════════════════════════════════════════
local DynamicIsland = (function()
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local DynamicIsland = {}
DynamicIsland.__index = DynamicIsland
local STATES = { Hidden = true, Compact = true, Minimal = true, Expanded = true }
local DEFAULT_CONFIG = {
    CompactSize = UDim2.fromOffset(200, 38),
    MinimalSize = UDim2.fromOffset(38, 38),
    ExpandedSize = UDim2.fromOffset(340, 180),
    ExpandedCornerRadius = 36,
    ExpandedPadding = 18,
    TopOffset = 12,
    SlotPadding = 14,
    MinimalSide = "Right",
    MinimalGap = 8,
    BackgroundColor = Color3.new(0, 0, 0),
    TextColor = Color3.new(1, 1, 1),
    AccentColor = Color3.fromRGB(10, 132, 255),
    Font = Enum.Font.GothamMedium,
    ZIndex = 100,
    InitialState = "Compact",
    ExpandOnClick = true,
    CollapseOnOutsideClick = true,
    PressEffect = true,
}
local EASE = Enum.EasingStyle
local OUT = Enum.EasingDirection.Out
local TWEENS = {
    Grow = TweenInfo.new(0.55, EASE.Back, OUT),
    Shrink = TweenInfo.new(0.45, EASE.Quint, OUT),
    Radius = TweenInfo.new(0.45, EASE.Quint, OUT),
    Fade = TweenInfo.new(0.3, EASE.Quint, OUT),
    LayerOut = TweenInfo.new(0.14, EASE.Quint, OUT),
    LayerIn = TweenInfo.new(0.28, EASE.Quint, OUT, 0, false, 0.12),
    Spring = TweenInfo.new(0.3, EASE.Back, OUT),
    Hover = TweenInfo.new(0.18, EASE.Quint, OUT),
    Progress = TweenInfo.new(0.6, EASE.Quint, OUT),
}
DynamicIsland.Tweens = TWEENS
DynamicIsland.DefaultConfig = DEFAULT_CONFIG
local HOVER_SCALE = 1.05
local PRESS_SCALE = 0.94
local WHITE = Color3.new(1, 1, 1)
local SECONDARY_TEXT = Color3.fromRGB(152, 152, 157)
local SURFACE = Color3.fromRGB(44, 44, 46)
local function create(className, props, parent)
    local instance = Instance.new(className)
    for key, value in props do instance[key] = value end
    if parent then instance.Parent = parent end
    return instance
end
local function area(size) return size.X.Offset * size.Y.Offset end
local function radiusFor(size) return math.min(size.X.Offset, size.Y.Offset) / 2 end
local function mergeConfig(overrides)
    local config = table.clone(DEFAULT_CONFIG)
    if overrides then for key, value in overrides do config[key] = value end end
    return config
end
local function clearHolder(holder)
    for _, child in holder:GetChildren() do
        if not child:IsA("UIPadding") then child:Destroy() end
    end
end
local function newLayer(name, parent, size)
    return create("CanvasGroup", {
        Name = name, AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.fromScale(0.5, 0), Size = size,
        BackgroundTransparency = 1, BorderSizePixel = 0,
        GroupTransparency = 1, Visible = false, ZIndex = 2,
    }, parent)
end
local function newSlot(parent, side, config)
    local isLeft = side == "Left"
    local slot = create("Frame", {
        Name = side .. "Slot", BackgroundTransparency = 1, BorderSizePixel = 0,
        AnchorPoint = Vector2.new(isLeft and 0 or 1, 0.5),
        Position = UDim2.new(isLeft and 0 or 1, isLeft and config.SlotPadding or -config.SlotPadding, 0.5, 0),
        Size = UDim2.new(0, 0, 1, -12), AutomaticSize = Enum.AutomaticSize.X,
    }, parent)
    create("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal,
        HorizontalAlignment = if isLeft then Enum.HorizontalAlignment.Left else Enum.HorizontalAlignment.Right,
        VerticalAlignment = Enum.VerticalAlignment.Center,
        SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6),
    }, slot)
    return slot
end
local function ensureIcon(island, side)
    local slot = island._slots[side]
    if not slot.Icon then
        local size = math.max(12, island._config.CompactSize.Y.Offset - 16)
        slot.Icon = create("ImageLabel", {
            Name = "Icon", BackgroundTransparency = 1, LayoutOrder = 1,
            ScaleType = Enum.ScaleType.Fit, Size = UDim2.fromOffset(size, size), ImageColor3 = WHITE,
        }, slot.Frame)
    end
    return slot.Icon
end
local function ensureText(island, side)
    local slot = island._slots[side]
    if not slot.Text then
        slot.Text = create("TextLabel", {
            Name = "Text", BackgroundTransparency = 1, LayoutOrder = 2,
            Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X,
            Font = island._config.Font, TextSize = 14, TextColor3 = island._config.TextColor,
            TextXAlignment = if side == "Left" then Enum.TextXAlignment.Left else Enum.TextXAlignment.Right,
            Text = "",
        }, slot.Frame)
    end
    return slot.Text
end
local function patchIcon(island, side, image, color)
    local icon = ensureIcon(island, side)
    icon.Image = image or ""; icon.Visible = image ~= nil
    if color then icon.ImageColor3 = color end
end
local function patchText(island, side, text, color)
    local label = ensureText(island, side)
    label.Text = text or ""; label.Visible = text ~= nil
    if color then label.TextColor3 = color end
end
function DynamicIsland.AddHoverEffect(button, options)
    options = options or {}
    local baseColor = button.BackgroundColor3
    local hoverColor = options.HoverColor or baseColor:Lerp(WHITE, 0.16)
    local hoverScale = options.HoverScale or 1.06
    local pressScale = options.PressScale or 0.92
    local uiScale = button:FindFirstChildOfClass("UIScale")
    if not uiScale then uiScale = Instance.new("UIScale"); uiScale.Parent = button end
    local hovering = false
    local function apply(scale, color)
        TweenService:Create(uiScale, TWEENS.Spring, { Scale = scale }):Play()
        TweenService:Create(button, TWEENS.Hover, { BackgroundColor3 = color }):Play()
    end
    local connections = {
        button.MouseEnter:Connect(function() hovering = true; apply(hoverScale, hoverColor) end),
        button.MouseLeave:Connect(function() hovering = false; apply(1, baseColor) end),
        button.MouseButton1Down:Connect(function() apply(pressScale, baseColor) end),
        button.MouseButton1Up:Connect(function()
            if hovering then apply(hoverScale, hoverColor) else apply(1, baseColor) end
        end),
    }
    return function()
        for _, connection in connections do connection:Disconnect() end
        uiScale.Scale = 1
    end
end
function DynamicIsland.new(screenGui, config)
    assert(typeof(screenGui) == "Instance" and screenGui:IsA("LayerCollector"), "DynamicIsland.new expects a ScreenGui")
    local self = setmetatable({}, DynamicIsland)
    local c = mergeConfig(config)
    self._config = c; self._screenGui = screenGui; self._connections = {}; self._tweens = {}
    self._transitionId = 0; self._destroyed = false; self._state = "Hidden"
    self._targetSize = UDim2.fromOffset(0, 0); self._primarySize = c.ExpandedSize
    self._expandedSize = c.ExpandedSize; self._hovering = false; self._minimalExplicit = false
    self._notifActive = false; self._notifToken = 0; self._returnState = nil
    local stateChanged = Instance.new("BindableEvent")
    local activated = Instance.new("BindableEvent")
    self._stateChangedEvent = stateChanged; self._activatedEvent = activated
    self.StateChanged = stateChanged.Event; self.Activated = activated.Event
    local holder = create("Frame", {
        Name = "DynamicIsland", BackgroundTransparency = 1, BorderSizePixel = 0,
        Size = UDim2.fromScale(1, 1), ZIndex = c.ZIndex,
    }, screenGui)
    self._holder = holder
    self._backdrop = create("TextButton", {
        Name = "Backdrop", Text = "", AutoButtonColor = false, BackgroundTransparency = 1,
        BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 1,
    }, holder)
    local body = create("CanvasGroup", {
        Name = "Body", AnchorPoint = Vector2.new(0.5, 0),
        Position = UDim2.new(0.5, 0, 0, c.TopOffset), Size = UDim2.fromOffset(0, 0),
        BackgroundColor3 = c.BackgroundColor, BorderSizePixel = 0,
        GroupTransparency = 1, Visible = false, ZIndex = 2,
    }, holder)
    self._body = body
    self._corner = create("UICorner", { CornerRadius = UDim.new(0, radiusFor(c.CompactSize)) }, body)
    self._uiScale = create("UIScale", { Scale = 1 }, body)
    self._hitbox = create("TextButton", {
        Name = "Hitbox", Text = "", AutoButtonColor = false, BackgroundTransparency = 1,
        BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), ZIndex = 1,
    }, body)
    local compact = newLayer("Compact", body, c.CompactSize)
    local minimal = newLayer("Minimal", body, c.MinimalSize)
    local expanded = newLayer("Expanded", body, c.ExpandedSize)
    self._layers = { Compact = compact, Minimal = minimal, Expanded = expanded }
    self._expandedLayer = expanded
    self._slots = {
        Left  = { Frame = newSlot(compact, "Left",  c) },
        Right = { Frame = newSlot(compact, "Right", c) },
    }
    self._minimalIcon = create("ImageLabel", {
        Name = "Icon", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(math.max(12, c.MinimalSize.Y.Offset - 18), math.max(12, c.MinimalSize.Y.Offset - 18)),
        BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Fit, Visible = false,
    }, minimal)
    self._minimalLabel = create("TextLabel", {
        Name = "Label", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1,
        Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = c.TextColor, Text = "", Visible = false,
    }, minimal)
    local function newHolder(name, visible)
        local frame = create("Frame", {
            Name = name, BackgroundTransparency = 1, BorderSizePixel = 0,
            Size = UDim2.fromScale(1, 1), Visible = visible,
        }, expanded)
        create("UIPadding", {
            PaddingTop = UDim.new(0, c.ExpandedPadding), PaddingBottom = UDim.new(0, c.ExpandedPadding),
            PaddingLeft = UDim.new(0, c.ExpandedPadding), PaddingRight = UDim.new(0, c.ExpandedPadding),
        }, frame)
        return frame
    end
    self._contentHolder = newHolder("Content", true)
    self._notifHolder   = newHolder("Notification", false)
    local function connect(signal, callback)
        table.insert(self._connections, signal:Connect(callback))
    end
    local hitbox = self._hitbox
    local function canHover() return c.PressEffect and UserInputService.MouseEnabled end
    connect(hitbox.MouseEnter,       function() self._hovering = true;  if canHover() then self:_setPressScale(HOVER_SCALE) end end)
    connect(hitbox.MouseLeave,       function() self._hovering = false; self:_setPressScale(1) end)
    connect(hitbox.MouseButton1Down, function() if c.PressEffect then self:_setPressScale(PRESS_SCALE) end end)
    connect(hitbox.MouseButton1Up,   function() self:_setPressScale((self._hovering and canHover()) and HOVER_SCALE or 1) end)
    connect(hitbox.Activated,        function() activated:Fire(self._state); if c.ExpandOnClick then self:Expand() end end)
    connect(self._backdrop.Activated, function() self:Collapse() end)
    assert(STATES[c.InitialState], "DynamicIsland: invalid InitialState")
    self:_goto(c.InitialState, false)
    return self
end
function DynamicIsland:_getTarget(state)
    local c = self._config; local top = c.TopOffset
    if state == "Compact" then
        return { Size = c.CompactSize, Position = UDim2.new(0.5,0,0,top), Radius = radiusFor(c.CompactSize) }
    elseif state == "Minimal" then
        local direction = if c.MinimalSide == "Left" then -1 else 1
        local x = direction * (c.CompactSize.X.Offset/2 + c.MinimalGap + c.MinimalSize.X.Offset/2)
        return { Size = c.MinimalSize, Position = UDim2.new(0.5,x,0,top), Radius = radiusFor(c.MinimalSize) }
    elseif state == "Expanded" then
        return { Size = self._expandedSize, Position = UDim2.new(0.5,0,0,top), Radius = c.ExpandedCornerRadius }
    end
    return { Size = UDim2.fromOffset(0,0), Position = UDim2.new(0.5,0,0,top + c.CompactSize.Y.Offset/2), Radius = radiusFor(c.CompactSize) }
end
function DynamicIsland:_animate(instance, info, props, animated)
    if not animated then for key, value in props do instance[key] = value end; return nil end
    local tween = TweenService:Create(instance, info, props)
    table.insert(self._tweens, tween); tween:Play(); return tween
end
function DynamicIsland:_cancelTweens()
    for _, tween in self._tweens do tween:Cancel() end; table.clear(self._tweens)
end
function DynamicIsland:_setPressScale(scale)
    TweenService:Create(self._uiScale, TWEENS.Spring, { Scale = scale }):Play()
end
function DynamicIsland:_goto(state, animated)
    self._transitionId += 1; local id = self._transitionId
    self:_cancelTweens()
    local target = self:_getTarget(state)
    local growing = area(target.Size) > area(self._targetSize)
    self._targetSize = target.Size; self._state = state
    local body = self._body
    if state ~= "Hidden" then body.Visible = true end
    self:_animate(body, growing and TWEENS.Grow or TWEENS.Shrink, { Size = target.Size, Position = target.Position }, animated)
    self:_animate(self._corner, TWEENS.Radius, { CornerRadius = UDim.new(0, target.Radius) }, animated)
    local fade = self:_animate(body, TWEENS.Fade, { GroupTransparency = if state == "Hidden" then 1 else 0 }, animated)
    if state == "Hidden" then
        if fade then
            fade.Completed:Connect(function(ps)
                if id == self._transitionId and ps == Enum.PlaybackState.Completed then body.Visible = false end
            end)
        else body.Visible = false end
    end
    local interactive = state == "Compact" or state == "Minimal"
    self._hitbox.Visible   = interactive
    self._backdrop.Visible = state == "Expanded" and self._config.CollapseOnOutsideClick
    if not interactive then self._hovering = false; self:_setPressScale(1) end
    for name, layer in self._layers do
        if name == state then
            layer.Visible = true
            self:_animate(layer, TWEENS.LayerIn, { GroupTransparency = 0 }, animated)
        elseif layer.Visible then
            local function retire()
                layer.Visible = false
                if name == "Expanded" and self._notifActive then self:_endNotification() end
            end
            local tween = self:_animate(layer, TWEENS.LayerOut, { GroupTransparency = 1 }, animated)
            if tween then
                tween.Completed:Connect(function(ps)
                    if id == self._transitionId and ps == Enum.PlaybackState.Completed then retire() end
                end)
            else retire() end
        end
    end
end
function DynamicIsland:_endNotification()
    if not self._notifActive then return end
    self._notifActive = false; self._returnState = nil
    clearHolder(self._notifHolder); self._notifHolder.Visible = false
    self._contentHolder.Visible = true
    self._expandedSize = self._primarySize; self._expandedLayer.Size = self._primarySize
end
function DynamicIsland:SetState(state)
    if not STATES[state] then error(("DynamicIsland: invalid state '%s'"):format(tostring(state)), 2) end
    if self._destroyed or state == self._state then return end
    if state == "Expanded" and self._notifActive and self._state ~= "Expanded" then self:_endNotification() end
    local previous = self._state; self:_goto(state, true); self._stateChangedEvent:Fire(state, previous)
end
function DynamicIsland:GetState() return self._state end
function DynamicIsland:Show()    self:SetState("Compact")  end
function DynamicIsland:Hide()    self:SetState("Hidden")   end
function DynamicIsland:Expand()  self:SetState("Expanded") end
function DynamicIsland:Collapse()
    if self._state ~= "Expanded" then return end
    local target = "Compact"
    if self._notifActive and self._returnState and self._returnState ~= "Expanded" then target = self._returnState end
    self:SetState(target)
end
function DynamicIsland:Toggle()
    if self._state == "Expanded" then self:Collapse() else self:Expand() end
end
function DynamicIsland:SetSlot(side, spec)
    local slot = self._slots[side]; assert(slot, "side must be 'Left' or 'Right'"); spec = spec or {}
    if spec.Icon ~= nil then patchIcon(self, side, spec.Icon, spec.IconColor or WHITE)
    elseif slot.Icon then slot.Icon.Visible = false end
    if spec.Text ~= nil then patchText(self, side, spec.Text, spec.TextColor or self._config.TextColor)
    elseif slot.Text then slot.Text.Visible = false end
    if slot.Custom and slot.Custom ~= spec.Content then slot.Custom.Parent = nil; slot.Custom = nil end
    if spec.Content then slot.Custom = spec.Content; spec.Content.LayoutOrder = 3; spec.Content.Parent = slot.Frame end
end
function DynamicIsland:SetCompactContent(content)
    content = content or {}
    for _, side in { "Left", "Right" } do
        local spec = {
            Icon      = content[side.."Icon"],     IconColor = content[side.."IconColor"],
            Text      = content[side.."Text"],     TextColor = content[side.."TextColor"],
            Content   = content[side.."Content"],
        }
        if next(spec) ~= nil then self:SetSlot(side, spec) end
    end
    if content.LeftIcon and not self._minimalExplicit then
        self:_applyMinimal({ Icon = content.LeftIcon, IconColor = content.LeftIconColor })
    end
end
function DynamicIsland:ClearCompactContent() self:SetSlot("Left",nil); self:SetSlot("Right",nil) end
function DynamicIsland:SetLeftIcon(image,color)  patchIcon(self,"Left",image,color); if not self._minimalExplicit then self:_applyMinimal({Icon=image,IconColor=color}) end end
function DynamicIsland:SetLeftText(text,color)   patchText(self,"Left",text,color) end
function DynamicIsland:SetRightIcon(image,color) patchIcon(self,"Right",image,color) end
function DynamicIsland:SetRightText(text,color)  patchText(self,"Right",text,color) end
function DynamicIsland:SetLeftContent(instance)  self:SetSlot("Left",{Content=instance}) end
function DynamicIsland:SetRightContent(instance) self:SetSlot("Right",{Content=instance}) end
function DynamicIsland:_applyMinimal(spec)
    local icon,label = self._minimalIcon, self._minimalLabel
    icon.Visible = spec.Icon ~= nil
    if spec.Icon ~= nil then icon.Image = spec.Icon; icon.ImageColor3 = spec.IconColor or WHITE end
    label.Visible = spec.Text ~= nil
    if spec.Text ~= nil then label.Text = spec.Text; label.TextColor3 = spec.TextColor or self._config.TextColor end
end
function DynamicIsland:SetMinimalContent(spec) self._minimalExplicit = true; self:_applyMinimal(spec or {}) end
function DynamicIsland:ClearExpandedContent()
    if self._contentCleanup then local c = self._contentCleanup; self._contentCleanup = nil; c() end
    if self._ownedContent then self._ownedContent:Destroy(); self._ownedContent = nil end
    if self._userContent  then self._userContent.Parent = nil; self._userContent = nil end
end
function DynamicIsland:SetExpandedContent(content, expandedSize)
    self:ClearExpandedContent(); local holder = self._contentHolder
    if typeof(content) == "function" then
        local box = create("Frame",{Name="Custom",BackgroundTransparency=1,BorderSizePixel=0,Size=UDim2.fromScale(1,1)},holder)
        self._ownedContent = box; local cleanup = content(box,self)
        if typeof(cleanup) == "function" then self._contentCleanup = cleanup end
    elseif typeof(content) == "Instance" and content:IsA("GuiObject") then
        content.AnchorPoint = Vector2.zero; content.Position = UDim2.fromScale(0,0)
        content.Size = UDim2.fromScale(1,1); content.Parent = holder; self._userContent = content
    end
    if expandedSize then self:SetExpandedSize(expandedSize) end
end
function DynamicIsland:SetExpandedSize(size)
    self._primarySize = size
    if self._notifActive then return end
    self._expandedSize = size; self._expandedLayer.Size = size
    if self._state == "Expanded" then self:_goto("Expanded",true) end
end
function DynamicIsland:CreateButton(props)
    props = props or {}
    local button = create("TextButton",{
        Name = props.Name or "Button", AutoButtonColor = false,
        Text = props.Text or "", Font = props.Font or self._config.Font,
        TextSize = props.TextSize or 16, TextColor3 = props.TextColor3 or self._config.TextColor,
        BackgroundColor3 = props.BackgroundColor3 or SURFACE, BorderSizePixel = 0,
        Size = props.Size or UDim2.fromOffset(44,44), Position = props.Position or UDim2.new(),
        AnchorPoint = props.AnchorPoint or Vector2.zero, LayoutOrder = props.LayoutOrder or 0,
    }, props.Parent)
    create("UICorner",{CornerRadius = props.CornerRadius or UDim.new(1,0)},button)
    if props.Callback then button.Activated:Connect(props.Callback) end
    DynamicIsland.AddHoverEffect(button,{HoverColor=props.HoverColor})
    return button
end
local NODE_SIZE = 32; local BAR_HEIGHT = 24
local DEFAULT_STEPS = {{Glyph="📦"},{Glyph="🚗"},{Glyph="🏠"}}
local function addIcon(parent,image,glyph,size,color)
    if image and image ~= "" then
        return create("ImageLabel",{Name="Icon",AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5),Size=UDim2.fromOffset(size,size),BackgroundTransparency=1,ScaleType=Enum.ScaleType.Fit,Image=image,ImageColor3=color or WHITE},parent)
    end
    return create("TextLabel",{Name="Icon",Size=UDim2.fromScale(1,1),BackgroundTransparency=1,Font=Enum.Font.GothamMedium,TextSize=math.floor(size*0.85),TextColor3=color or WHITE,Text=glyph or ""},parent)
end
local function fillSize(alpha) return UDim2.new(alpha, NODE_SIZE*(0.5-alpha), 1, 0) end
local function buildDeliveryTracker(island,box,options,controller)
    local color = options.Color or Color3.fromRGB(187,107,242)
    local black = Color3.new(0,0,0); local trackColor = color:Lerp(black,0.58); local offColor = color:Lerp(black,0.42)
    local steps = options.Steps or DEFAULT_STEPS; local count = #steps; local progress = math.clamp(options.Progress or 0,0,1)
    local title = create("TextLabel",{Name="Title",BackgroundTransparency=1,Size=UDim2.new(1,0,0,22),Font=Enum.Font.GothamMedium,TextSize=16,TextColor3=color:Lerp(WHITE,0.15),TextXAlignment=Enum.TextXAlignment.Left,TextTruncate=Enum.TextTruncate.AtEnd,Text=options.Title or ""},box)
    local track = create("Frame",{Name="Progress",BackgroundTransparency=1,Position=UDim2.fromOffset(0,32),Size=UDim2.new(1,0,0,NODE_SIZE)},box)
    local bar = create("Frame",{Name="Bar",AnchorPoint=Vector2.new(0,0.5),Position=UDim2.fromScale(0,0.5),Size=UDim2.new(1,0,0,BAR_HEIGHT),BackgroundColor3=trackColor,BorderSizePixel=0,ZIndex=1},track)
    create("UICorner",{CornerRadius=UDim.new(1,0)},bar)
    local fill = create("Frame",{Name="Fill",BackgroundColor3=color,BorderSizePixel=0,Size=fillSize(progress)},bar)
    create("UICorner",{CornerRadius=UDim.new(1,0)},fill)
    local nodes = {}
    for index,step in steps do
        local alpha = if count > 1 then (index-1)/(count-1) else 0
        local node = create("Frame",{Name="Node"..index,AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.new(alpha,NODE_SIZE*(0.5-alpha),0.5,0),Size=UDim2.fromOffset(NODE_SIZE,NODE_SIZE),BackgroundColor3=offColor,BorderSizePixel=0,ZIndex=2},track)
        create("UICorner",{CornerRadius=UDim.new(1,0)},node); addIcon(node,step.Icon,step.Glyph,18); nodes[index]={Frame=node,Alpha=alpha}
    end
    local function renderNodes(animated)
        for _,node in nodes do
            local lit = progress >= node.Alpha - 0.001; local goal = if lit then color else offColor
            if animated then TweenService:Create(node.Frame,TWEENS.Progress,{BackgroundColor3=goal}):Play()
            else node.Frame.BackgroundColor3 = goal end
        end
    end
    renderNodes(false)
    local row = create("Frame",{Name="Contact",BackgroundTransparency=1,AnchorPoint=Vector2.new(0,1),Position=UDim2.fromScale(0,1),Size=UDim2.new(1,0,0,40)},box)
    local avatar = create("ImageLabel",{Name="Avatar",BackgroundColor3=SURFACE,BorderSizePixel=0,Image=options.Avatar or "",ScaleType=Enum.ScaleType.Crop,Size=UDim2.fromOffset(40,40)},row)
    create("UICorner",{CornerRadius=UDim.new(1,0)},avatar)
    local name = create("TextLabel",{Name="Name",BackgroundTransparency=1,Position=UDim2.fromOffset(52,0),Size=UDim2.new(1,-(52+182),1,0),Font=Enum.Font.GothamMedium,TextSize=17,TextColor3=island._config.TextColor,TextXAlignment=Enum.TextXAlignment.Left,TextTruncate=Enum.TextTruncate.AtEnd,Text=options.ContactName or ""},row)
    local buttons = create("Frame",{Name="Buttons",BackgroundTransparency=1,AnchorPoint=Vector2.new(1,0),Position=UDim2.fromScale(1,0),Size=UDim2.new(0,178,1,0)},row)
    create("UIListLayout",{FillDirection=Enum.FillDirection.Horizontal,HorizontalAlignment=Enum.HorizontalAlignment.Right,VerticalAlignment=Enum.VerticalAlignment.Center,SortOrder=Enum.SortOrder.LayoutOrder,Padding=UDim.new(0,10)},buttons)
    local function contactButton(order,buttonName,image,glyph,callback)
        local button = island:CreateButton({Name=buttonName,Text="",Size=UDim2.fromOffset(84,40),BackgroundColor3=Color3.fromRGB(58,58,60),LayoutOrder=order,Parent=buttons,Callback=callback})
        addIcon(button,image,glyph,20); return button
    end
    contactButton(1,"Call",options.CallIcon,"📞",options.OnCall)
    contactButton(2,"Message",options.MessageIcon,"💬",options.OnMessage)
    function controller.SetProgress(alpha)
        progress = math.clamp(alpha,0,1); TweenService:Create(fill,TWEENS.Progress,{Size=fillSize(progress)}):Play(); renderNodes(true)
    end
    function controller.SetTitle(text) title.Text = text end
    function controller.SetContact(info)
        if info.Name then name.Text = info.Name end
        if info.Avatar then avatar.Image = info.Avatar end
    end
end
function DynamicIsland:SetDeliveryTracker(options)
    options = options or {}; local controller = {}
    self:SetExpandedContent(function(box) buildDeliveryTracker(self,box,options,controller) end, UDim2.fromOffset(self._config.ExpandedSize.X.Offset,170))
    return controller
end
local function buildNotification(island,holder,options)
    local config = island._config; local textX = options.Icon and 56 or 0
    if options.Icon then
        local icon = create("ImageLabel",{Name="Icon",BackgroundColor3=options.IconBackground or SURFACE,BorderSizePixel=0,Image=options.Icon,ScaleType=Enum.ScaleType.Crop,Size=UDim2.fromOffset(44,44)},holder)
        create("UICorner",{CornerRadius=UDim.new(0,12)},icon)
    end
    create("TextLabel",{Name="Title",BackgroundTransparency=1,Position=UDim2.fromOffset(textX,0),Size=UDim2.new(1,-textX,0,22),Font=Enum.Font.GothamBold,TextSize=16,TextColor3=config.TextColor,TextXAlignment=Enum.TextXAlignment.Left,TextTruncate=Enum.TextTruncate.AtEnd,Text=options.Title or ""},holder)
    create("TextLabel",{Name="Message",BackgroundTransparency=1,Position=UDim2.fromOffset(textX,24),Size=UDim2.new(1,-textX,0,38),Font=Enum.Font.Gotham,TextSize=14,TextColor3=SECONDARY_TEXT,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Top,TextWrapped=true,TextTruncate=Enum.TextTruncate.AtEnd,Text=options.Message or ""},holder)
    if options.ButtonText then
        island:CreateButton({Name="Action",Text=options.ButtonText,TextSize=14,BackgroundColor3=config.AccentColor,AnchorPoint=Vector2.new(1,1),Position=UDim2.fromScale(1,1),Size=UDim2.fromOffset(120,34),Parent=holder,Callback=function() if options.OnButton then options.OnButton() end; island:Collapse() end})
    end
end
function DynamicIsland:Notify(options)
    if self._destroyed then return end; options = options or {}
    local hasButton = options.ButtonText ~= nil
    local size = UDim2.fromOffset(self._config.ExpandedSize.X.Offset, if hasButton then 146 else 100)
    if not self._notifActive then self._returnState = self._state end
    clearHolder(self._notifHolder); buildNotification(self,self._notifHolder,options)
    self._notifActive = true; self._contentHolder.Visible = false; self._notifHolder.Visible = true
    self._expandedSize = size; self._expandedLayer.Size = size
    local previous = self._state; self._notifToken += 1; local token = self._notifToken
    self:_goto("Expanded",true)
    if previous ~= "Expanded" then self._stateChangedEvent:Fire("Expanded",previous) end
    local duration = options.Duration or 4
    if duration > 0 then
        task.delay(duration, function()
            if self._destroyed or self._notifToken ~= token or not self._notifActive then return end
            if self._returnState == "Expanded" then self:_endNotification(); self:_goto("Expanded",true)
            elseif self._state == "Expanded" then self:SetState(self._returnState or "Compact") end
        end)
    end
end
function DynamicIsland:Destroy()
    if self._destroyed then return end; self._destroyed = true; self._transitionId += 1; self:_cancelTweens()
    for _,connection in self._connections do connection:Disconnect() end; table.clear(self._connections)
    self:ClearExpandedContent()
    for _,slot in self._slots do if slot.Custom then slot.Custom.Parent = nil; slot.Custom = nil end end
    self._holder:Destroy(); self._stateChangedEvent:Destroy(); self._activatedEvent:Destroy()
end
return DynamicIsland
end)()

-- ════════════════════════════════════════════
--  WORD DATABASE
-- ════════════════════════════════════════════
local function firstChar(str)
    if #str == 0 then return nil end
    local b = str:byte(1)
    if     b >= 0xF0 then return str:sub(1,4)
    elseif b >= 0xE0 then return str:sub(1,3)
    elseif b >= 0xC0 then return str:sub(1,2)
    else                   return str:sub(1,1) end
end
local function isThaiOnlyWord(word)
    local len = #word
    if len == 0 or len % 3 ~= 0 then return false end
    for i = 1, len, 3 do
        local b1,b2,b3 = word:byte(i, i+2)
        if b1 ~= 0xE0 or (b2 ~= 0xB8 and b2 ~= 0xB9) or not b3 or b3 < 0x80 or b3 > 0xBF then return false end
    end
    return true
end
local function buildDB(text)
    local db = {}
    for line in text:gmatch("[^\n\r]+") do
        local word = line:match("^%s*(.-)%s*$")
        if word and #word >= 2 and isThaiOnlyWord(word) then
            local fc = firstChar(word)
            if fc then
                if not db[fc] then db[fc] = {} end
                table.insert(db[fc], word)
            end
        end
    end
    return db
end
local function buildFreqDB(text)
    local freq = {}
    for line in text:gmatch("[^\n\r]+") do
        local word, countStr = line:match("^(.-)\t(%d+)%s*$")
        if word and countStr then freq[word] = tonumber(countStr) end
    end
    return freq
end
local function loadWordDB()
    if isfile and isfile(CACHE_PATH) then
        local ok, cached = pcall(readfile, CACHE_PATH)
        if ok and cached and #cached > 500 then
            local db = buildDB(cached)
            local n = 0; for _,v in pairs(db) do n = n + #v end
            if n > 1000 then return db end
        end
    end
    local ok, body = pcall(function() return game:HttpGet(SOURCE_URL) end)
    if not ok or not body or #body < 500 then return {} end
    if writefile then pcall(writefile, CACHE_PATH, body) end
    return buildDB(body)
end
local function loadFreqDB()
    if isfile and isfile(FREQ_CACHE_PATH) then
        local ok, cached = pcall(readfile, FREQ_CACHE_PATH)
        if ok and cached and #cached > 500 then
            local freq = buildFreqDB(cached)
            local n = 0; for _ in pairs(freq) do n = n + 1 end
            if n > 1000 then return freq end
        end
    end
    local ok, body = pcall(function() return game:HttpGet(FREQ_SOURCE_URL) end)
    if not ok or not body or #body < 500 then return {} end
    if writefile then pcall(writefile, FREQ_CACHE_PATH, body) end
    return buildFreqDB(body)
end
local WORD_DB   = loadWordDB()
local WORD_FREQ = loadFreqDB()

-- ════════════════════════════════════════════
--  GAME STATE
-- ════════════════════════════════════════════
local blacklisted        = {}
local usedWords          = {}
local usedCount          = 0
local isAutoFillON       = true
local isTyping           = false
local lastWord           = ""
local currentSuggestions = {}
local currentIndex       = 1
local currentTypeCycle   = 0
local lastHistorySeen    = os.clock()
local IS_TOUCH           = UIS.TouchEnabled

-- ════════════════════════════════════════════
--  HELPERS
-- ════════════════════════════════════════════
local function utf8Len(str)
    local n = 0
    for i = 1, #str do
        local b = str:byte(i)
        if b < 0x80 or b >= 0xC0 then n = n + 1 end
    end
    return n
end

local function getSuggestions(prefix)
    local plen, out = #prefix, {}
    local fc = firstChar(prefix)
    if not fc then return out end
    local bucket = WORD_DB[fc]
    if not bucket then return out end
    local minChars = CFG.MIN_SUGGEST_CHARS
    for _, w in ipairs(bucket) do
        if #w > plen and w:sub(1,plen) == prefix
            and not blacklisted[w] and not usedWords[w]
            and utf8Len(w) >= minChars then
            table.insert(out, w)
        end
    end
    table.sort(out, function(a,b)
        local fa,fb = WORD_FREQ[a] or 0, WORD_FREQ[b] or 0
        if fa ~= fb then return fa > fb end
        return #a < #b
    end)
    local result = {}
    for i = 1, math.min(#out, CFG.MAX_SUGGEST) do result[i] = out[i] end
    return result
end

-- ════════════════════════════════════════════
--  SCREEN GUI + DYNAMIC ISLAND
-- ════════════════════════════════════════════
if PGui:FindFirstChild("WC_Helper") then PGui:FindFirstChild("WC_Helper"):Destroy() end

local screenGui = Instance.new("ScreenGui", PGui)
screenGui.Name            = "WC_Helper"
screenGui.ResetOnSpawn    = false
screenGui.IgnoreGuiInset  = true
screenGui.ZIndexBehavior  = Enum.ZIndexBehavior.Sibling
screenGui.DisplayOrder    = 10

local island = DynamicIsland.new(screenGui, {
    CompactSize            = UDim2.fromOffset(300, 44),
    MinimalSize            = UDim2.fromOffset(38, 38),
    ExpandedSize           = UDim2.fromOffset(310, 248),
    ExpandedCornerRadius   = 32,
    ExpandedPadding        = 16,
    TopOffset              = 16,
    SlotPadding            = 14,
    MinimalSide            = "Right",
    MinimalGap             = 8,
    BackgroundColor        = COLORS.bg,
    TextColor              = COLORS.text,
    AccentColor            = COLORS.accent,
    Font                   = Enum.Font.GothamMedium,
    ZIndex                 = 100,
    InitialState           = "Hidden",
    ExpandOnClick          = true,
    CollapseOnOutsideClick = true,
    PressEffect            = true,
})

-- ════════════════════════════════════════════
--  EXPANDED CONTENT
-- ════════════════════════════════════════════
local expSubtitle, expWord, expHint, expLenLabel
local expSpeedVal, expSliderFill, expSliderBtn, expSliderBg
local expAutoBtn, expRankBtn

local expandedFrame = Instance.new("Frame")
expandedFrame.BackgroundTransparency = 1
expandedFrame.BorderSizePixel        = 0

local expList = Instance.new("UIListLayout", expandedFrame)
expList.FillDirection       = Enum.FillDirection.Vertical
expList.SortOrder           = Enum.SortOrder.LayoutOrder
expList.HorizontalAlignment = Enum.HorizontalAlignment.Center
expList.Padding             = UDim.new(0, 6)

expSubtitle = Instance.new("TextLabel", expandedFrame)
expSubtitle.LayoutOrder            = 1
expSubtitle.Size                   = UDim2.new(1,0,0,13)
expSubtitle.BackgroundTransparency = 1
expSubtitle.Font                   = Enum.Font.Gotham
expSubtitle.TextSize               = 11
expSubtitle.TextColor3             = COLORS.dim
expSubtitle.TextXAlignment         = Enum.TextXAlignment.Left
expSubtitle.Text                   = "สถานะ"

expWord = Instance.new("TextLabel", expandedFrame)
expWord.LayoutOrder            = 2
expWord.Size                   = UDim2.new(1,0,0,26)
expWord.BackgroundTransparency = 1
expWord.Font                   = Enum.Font.GothamBold
expWord.TextSize               = 19
expWord.TextColor3             = COLORS.text
expWord.TextXAlignment         = Enum.TextXAlignment.Left
expWord.Text                   = "รอคำจากเกม..."

expHint = Instance.new("TextLabel", expandedFrame)
expHint.LayoutOrder            = 3
expHint.Size                   = UDim2.new(1,0,0,12)
expHint.BackgroundTransparency = 1
expHint.Font                   = Enum.Font.GothamBold
expHint.TextSize               = 11
expHint.TextColor3             = COLORS.auto_txt
expHint.TextXAlignment         = Enum.TextXAlignment.Left
expHint.Text                   = ""

local expDivider = Instance.new("Frame", expandedFrame)
expDivider.LayoutOrder      = 4
expDivider.Size             = UDim2.new(1,0,0,1)
expDivider.BackgroundColor3 = COLORS.border
expDivider.BorderSizePixel  = 0

local lenRow = Instance.new("Frame", expandedFrame)
lenRow.LayoutOrder            = 5
lenRow.Size                   = UDim2.new(1,0,0,28)
lenRow.BackgroundTransparency = 1

local lenTitle = Instance.new("TextLabel", lenRow)
lenTitle.Size                   = UDim2.new(1,-98,1,0)
lenTitle.Position               = UDim2.fromOffset(0,0)
lenTitle.BackgroundTransparency = 1
lenTitle.Font                   = Enum.Font.Gotham
lenTitle.TextSize               = 11
lenTitle.TextColor3             = COLORS.dim
lenTitle.TextXAlignment         = Enum.TextXAlignment.Left
lenTitle.Text                   = "ความยาวขั้นต่ำ"

local lenCtrl = Instance.new("Frame", lenRow)
lenCtrl.AnchorPoint            = Vector2.new(1,0.5)
lenCtrl.Position               = UDim2.new(1,0,0.5,0)
lenCtrl.Size                   = UDim2.fromOffset(94,28)
lenCtrl.BackgroundTransparency = 1

local lenCtrlList = Instance.new("UIListLayout", lenCtrl)
lenCtrlList.FillDirection       = Enum.FillDirection.Horizontal
lenCtrlList.HorizontalAlignment = Enum.HorizontalAlignment.Right
lenCtrlList.VerticalAlignment   = Enum.VerticalAlignment.Center
lenCtrlList.SortOrder           = Enum.SortOrder.LayoutOrder
lenCtrlList.Padding             = UDim.new(0,4)

local refreshSuggestions
local showCurrent

local lenMinusBtn = island:CreateButton({
    Name="LenMinus", Text="−", TextSize=16,
    Size=UDim2.fromOffset(28,28), LayoutOrder=1,
    BackgroundColor3=COLORS.set_bg, TextColor3=COLORS.set_txt,
    CornerRadius=UDim.new(1,0), Parent=lenCtrl,
    Callback=function()
        CFG.MIN_SUGGEST_CHARS = math.clamp(CFG.MIN_SUGGEST_CHARS - 1, 1, 15)
        if expLenLabel then expLenLabel.Text = tostring(CFG.MIN_SUGGEST_CHARS) end
        if refreshSuggestions then refreshSuggestions(lastWord) end
    end,
})

expLenLabel = Instance.new("TextLabel", lenCtrl)
expLenLabel.LayoutOrder            = 2
expLenLabel.Size                   = UDim2.fromOffset(22,28)
expLenLabel.BackgroundTransparency = 1
expLenLabel.Font                   = Enum.Font.GothamBold
expLenLabel.TextSize               = 13
expLenLabel.TextColor3             = COLORS.text
expLenLabel.Text                   = tostring(CFG.MIN_SUGGEST_CHARS)

local lenPlusBtn = island:CreateButton({
    Name="LenPlus", Text="+", TextSize=16,
    Size=UDim2.fromOffset(28,28), LayoutOrder=3,
    BackgroundColor3=COLORS.set_bg, TextColor3=COLORS.set_txt,
    CornerRadius=UDim.new(1,0), Parent=lenCtrl,
    Callback=function()
        CFG.MIN_SUGGEST_CHARS = math.clamp(CFG.MIN_SUGGEST_CHARS + 1, 1, 15)
        if expLenLabel then expLenLabel.Text = tostring(CFG.MIN_SUGGEST_CHARS) end
        if refreshSuggestions then refreshSuggestions(lastWord) end
    end,
})

-- Speed section
local speedSection = Instance.new("Frame", expandedFrame)
speedSection.LayoutOrder            = 6
speedSection.Size                   = UDim2.new(1,0,0,34)
speedSection.BackgroundTransparency = 1

local speedTitleRow = Instance.new("Frame", speedSection)
speedTitleRow.Size                   = UDim2.new(1,0,0,13)
speedTitleRow.Position               = UDim2.fromOffset(0,0)
speedTitleRow.BackgroundTransparency = 1

local speedTitleLbl = Instance.new("TextLabel", speedTitleRow)
speedTitleLbl.Size                   = UDim2.new(0.6,0,1,0)
speedTitleLbl.BackgroundTransparency = 1
speedTitleLbl.Font                   = Enum.Font.Gotham
speedTitleLbl.TextSize               = 11
speedTitleLbl.TextColor3             = COLORS.dim
speedTitleLbl.TextXAlignment         = Enum.TextXAlignment.Left
speedTitleLbl.Text                   = "ความเร็วพิมพ์"

expSpeedVal = Instance.new("TextLabel", speedTitleRow)
expSpeedVal.AnchorPoint            = Vector2.new(1,0)
expSpeedVal.Position               = UDim2.fromScale(1,0)
expSpeedVal.Size                   = UDim2.new(0.4,0,1,0)
expSpeedVal.BackgroundTransparency = 1
expSpeedVal.Font                   = Enum.Font.GothamBold
expSpeedVal.TextSize               = 11
expSpeedVal.TextColor3             = COLORS.accent
expSpeedVal.TextXAlignment         = Enum.TextXAlignment.Right
expSpeedVal.Text                   = string.format("%.2fs/ตัว", CURRENT_SPEED_DELAY)

expSliderBg = Instance.new("Frame", speedSection)
expSliderBg.Position         = UDim2.new(0,0,0,18)
expSliderBg.Size             = UDim2.new(1,0,0,8)
expSliderBg.BackgroundColor3 = Color3.fromHex("1E1E1E")
expSliderBg.BorderSizePixel  = 0
Instance.new("UICorner", expSliderBg).CornerRadius = UDim.new(1,0)
Instance.new("UIStroke",  expSliderBg).Color        = COLORS.border

expSliderFill = Instance.new("Frame", expSliderBg)
expSliderFill.Size             = UDim2.new(0.5,0,1,0)
expSliderFill.BackgroundColor3 = COLORS.accent
expSliderFill.BorderSizePixel  = 0
Instance.new("UICorner", expSliderFill).CornerRadius = UDim.new(1,0)

expSliderBtn = Instance.new("TextButton", expSliderBg)
expSliderBtn.Size             = UDim2.fromOffset(14,14)
expSliderBtn.AnchorPoint      = Vector2.new(0.5,0.5)
expSliderBtn.Position         = UDim2.new(0.5,0,0.5,0)
expSliderBtn.BackgroundColor3 = Color3.new(1,1,1)
expSliderBtn.AutoButtonColor  = false
expSliderBtn.Text             = ""
expSliderBtn.BorderSizePixel  = 0
Instance.new("UICorner", expSliderBtn).CornerRadius = UDim.new(1,0)

-- Button row
local btnRow = Instance.new("Frame", expandedFrame)
btnRow.LayoutOrder            = 7
btnRow.Size                   = UDim2.new(1,0,0,32)
btnRow.BackgroundTransparency = 1

local btnList = Instance.new("UIListLayout", btnRow)
btnList.FillDirection       = Enum.FillDirection.Horizontal
btnList.HorizontalAlignment = Enum.HorizontalAlignment.Left
btnList.VerticalAlignment   = Enum.VerticalAlignment.Center
btnList.SortOrder           = Enum.SortOrder.LayoutOrder
btnList.Padding             = UDim.new(0,8)

local resetBtn = island:CreateButton({
    Name="Reset", Text="↺ รีเซ็ต", TextSize=12,
    Size=UDim2.fromOffset(74,32), LayoutOrder=1,
    BackgroundColor3=COLORS.rst_bg, TextColor3=COLORS.rst_txt,
    CornerRadius=UDim.new(0,10), Parent=btnRow,
    Callback=function()
        blacklisted = {}
        if lastWord ~= "" and lastWord ~= "__none__" then
            if refreshSuggestions then refreshSuggestions(lastWord) end
        else currentSuggestions, currentIndex = {}, 1; if showCurrent then showCurrent() end end
    end,
})

local removeBtn = island:CreateButton({
    Name="Remove", Text="✕ ข้าม", TextSize=12,
    Size=UDim2.fromOffset(74,32), LayoutOrder=2,
    BackgroundColor3=COLORS.del_bg, TextColor3=COLORS.del_txt,
    CornerRadius=UDim.new(0,10), Parent=btnRow,
    Callback=function()
        local word = currentSuggestions[currentIndex]
        if word then blacklisted[word] = true; if refreshSuggestions then refreshSuggestions(lastWord) end end
    end,
})

expAutoBtn = island:CreateButton({
    Name="Auto", Text="◉ Auto", TextSize=12,
    Size=UDim2.fromOffset(74,32), LayoutOrder=3,
    BackgroundColor3=COLORS.auto_on,
    TextColor3=Color3.new(1,1,1),
    CornerRadius=UDim.new(0,10), Parent=btnRow,
    Callback=function()
        isAutoFillON = not isAutoFillON
        if isAutoFillON then
            TweenService:Create(expAutoBtn,TweenInfo.new(0.2),{BackgroundColor3=COLORS.auto_on}):Play()
            expAutoBtn.TextColor3 = Color3.new(1,1,1); expAutoBtn.Text = "◉ Auto"
        else
            TweenService:Create(expAutoBtn,TweenInfo.new(0.2),{BackgroundColor3=COLORS.set_bg}):Play()
            expAutoBtn.TextColor3 = COLORS.set_txt; expAutoBtn.Text = "A Auto"
        end
        if showCurrent then showCurrent() end
    end,
})

expRankBtn = island:CreateButton({
    Name="Rank", Text="♟ แรงค์", TextSize=12,
    Size=UDim2.fromOffset(74,32), LayoutOrder=4,
    BackgroundColor3=COLORS.rank_on,
    TextColor3=COLORS.rank_txt,
    CornerRadius=UDim.new(0,10), Parent=btnRow,
    Callback=function()
        CFG.AUTO_RANK = not CFG.AUTO_RANK
        if CFG.AUTO_RANK then
            TweenService:Create(expRankBtn,TweenInfo.new(0.2),{BackgroundColor3=COLORS.rank_on}):Play()
            expRankBtn.TextColor3 = COLORS.rank_txt; expRankBtn.Text = "♟ แรงค์"
        else
            TweenService:Create(expRankBtn,TweenInfo.new(0.2),{BackgroundColor3=COLORS.set_bg}):Play()
            expRankBtn.TextColor3 = COLORS.set_txt; expRankBtn.Text = "♙ แรงค์"
        end
    end,
})

island:SetExpandedContent(expandedFrame, UDim2.fromOffset(310, 248))

island:SetCompactContent({
    LeftText       = "W",
    LeftTextColor  = COLORS.accent,
    RightText      = "รอคำจากเกม...",
    RightTextColor = COLORS.dim,
})
island:SetMinimalContent({ Text = "W" })

-- ── Speed slider drag logic ───────────────────
local isDraggingSlider = false

local function updateSliderPos(val)
    local alpha = math.clamp(
        (val - CFG.TYPING_SPEED_MIN) / (CFG.TYPING_SPEED_MAX - CFG.TYPING_SPEED_MIN),
        0, 1
    )
    expSliderFill.Size    = UDim2.new(alpha, 0, 1, 0)
    expSliderBtn.Position = UDim2.new(alpha, 0, 0.5, 0)
end

local function updateSpeedLabel()
    expSpeedVal.Text = string.format("%.2fs/ตัว", CURRENT_SPEED_DELAY)
end

local function isPointer(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch
end

expSliderBtn.InputBegan:Connect(function(input)
    if isPointer(input) then isDraggingSlider = true end
end)
UIS.InputEnded:Connect(function(input)
    if isPointer(input) then isDraggingSlider = false end
end)
UIS.InputChanged:Connect(function(input)
    if not isDraggingSlider then return end
    if input.UserInputType ~= Enum.UserInputType.MouseMovement
        and input.UserInputType ~= Enum.UserInputType.Touch then return end
    local mouseX = input.Position.X
    local absX   = expSliderBg.AbsolutePosition.X
    local absW   = expSliderBg.AbsoluteSize.X
    local alpha  = math.clamp((mouseX - absX) / absW, 0, 1)
    CURRENT_SPEED_DELAY = CFG.TYPING_SPEED_MIN + alpha * (CFG.TYPING_SPEED_MAX - CFG.TYPING_SPEED_MIN)
    updateSliderPos(CURRENT_SPEED_DELAY)
    updateSpeedLabel()
end)

updateSliderPos(CURRENT_SPEED_DELAY)

-- ════════════════════════════════════════════
--  UI UPDATE FUNCTIONS
-- ════════════════════════════════════════════
local function setCompactRight(text, color)
    island:SetRightText(text, color or COLORS.text)
end

showCurrent = function()
    local word    = currentSuggestions[currentIndex]
    local hasWord = lastWord ~= "" and lastWord ~= "__none__"

    if hasWord then
        expSubtitle.Text = "ต่อจาก " .. lastWord .. "  ·  ใช้แล้ว " .. usedCount
        if word then
            expWord.Text       = word
            expWord.TextColor3 = COLORS.text
            if isAutoFillON then
                expHint.Text       = "[Auto Mode]"
                expHint.TextColor3 = COLORS.auto_txt
                setCompactRight("⟢ " .. word, COLORS.auto_txt)
            else
                expHint.Text       = "[Tab] พิมพ์คำนี้"
                expHint.TextColor3 = COLORS.dim
                setCompactRight(word, COLORS.text)
            end
        else
            expWord.Text       = "ไม่มีคำแนะนำ"
            expWord.TextColor3 = COLORS.dim
            expHint.Text       = ""
            setCompactRight("ไม่มีคำ", COLORS.dim)
            isTyping = false; currentTypeCycle = currentTypeCycle + 1
        end
    else
        expSubtitle.Text   = "สถานะ"
        expWord.Text       = "รอคำจากเกม..."
        expWord.TextColor3 = COLORS.dim
        expHint.Text       = ""
        setCompactRight("รอคำ...", COLORS.dim)
        isTyping = false; currentTypeCycle = currentTypeCycle + 1
    end
end

refreshSuggestions = function(prefix)
    currentSuggestions = getSuggestions(prefix)
    currentIndex       = 1
    showCurrent()
end

-- ════════════════════════════════════════════
--  INPUT BOX
-- ════════════════════════════════════════════
local function getInputBox()
    local gameUI = LP.PlayerGui:FindFirstChild("GameUI")
    local root   = gameUI and gameUI:FindFirstChild("Root")
    local match  = root  and root:FindFirstChild("Match")
    local bar    = match and match:FindFirstChild("InputBar")
    if not bar then return nil end
    local wBox = bar:FindFirstChild("WordBox")
    if not (wBox and wBox:IsA("TextBox")) then return nil end
    local pLbl  = bar:FindFirstChild("PrefixLabel")
    local pText = (pLbl and pLbl:IsA("TextLabel")) and pLbl.Text or ""
    pText = pText:gsub("<[^>]*>",""):gsub("%s+","")
    return wBox, pText
end

-- ════════════════════════════════════════════
--  LIVE TIMER READER
-- ════════════════════════════════════════════
local function getTimerValue()
    local v = math.huge
    pcall(function()
        v = tonumber(
            LP.PlayerGui:FindFirstChild("GameUI")
                :FindFirstChild("Root")
                :FindFirstChild("Match")
                :FindFirstChild("Timer")
                :FindFirstChild("TextLabel")
                .Text
        ) or math.huge
    end)
    return v
end

-- ════════════════════════════════════════════
--  TYPING PROFILE SELECTOR
-- ════════════════════════════════════════════
local function typingProfile(t, charsLeft)
    local budget = (t - 0.38) / math.max(charsLeft, 1)
    if t == math.huge or t > 8 then
        return { instant=false, burst=18, pause=7, lo=CFG.TYPING_SPEED_MIN, hi=CFG.TYPING_SPEED_MAX, jlo=-35, jhi=65, endSlow=true, hesLo=80, hesHi=160 }
    end
    if t > 5 then
        local hi = math.min(CFG.TYPING_SPEED_MAX, math.max(budget*0.9, CFG.TYPING_SPEED_MIN+0.012))
        return { instant=false, burst=24, pause=4, lo=CFG.TYPING_SPEED_MIN, hi=hi, jlo=-28, jhi=50, endSlow=true, hesLo=55, hesHi=120 }
    end
    if t > 3 then
        local hi = math.min(CFG.TYPING_SPEED_MAX*0.65, math.max(budget*0.88, CFG.TYPING_SPEED_MIN+0.010))
        return { instant=false, burst=38, pause=0, lo=CFG.TYPING_SPEED_MIN, hi=hi, jlo=-15, jhi=28, endSlow=false, hesLo=15, hesHi=45 }
    end
    if t > 1.2 then
        local lo = math.max(0.010, budget*0.75); local hi = math.max(lo+0.008, budget*0.96)
        return { instant=hi < CFG.TYPING_SPEED_MIN, burst=62, pause=0, lo=lo, hi=hi, jlo=-5, jhi=10, endSlow=false, hesLo=0, hesHi=10 }
    end
    return { instant=true }
end

-- ════════════════════════════════════════════
--  AUTOFILL SYSTEM
-- ════════════════════════════════════════════
local function submitBox(wBox)
    if IS_TOUCH then
        local ok = pcall(function() wBox:ReleaseFocus(true) end)
        if ok then return end
    end
    VIM:SendKeyEvent(true,  Enum.KeyCode.Return, false, game)
    task.wait(0.05)
    VIM:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
end

local function fillBox(wBox, text, instant, cancelled)
    local chars, codepoints = {}, {}
    for cp in utf8.codes(text) do
        codepoints[#codepoints+1] = cp
        chars[#chars+1] = utf8.char(cp)
    end
    local n = #chars
    if not instant then
        local t0 = getTimerValue()
        if t0 ~= math.huge and t0 < (n*0.016 + 0.42) then instant = true end
    end
    local typoAt = -1
    if not instant and n >= 3 then
        local t0 = getTimerValue(); local chance = 0
        if t0 == math.huge or t0 > 8 then chance = CFG.TYPO_CHANCE_T1
        elseif t0 > 5 then chance = CFG.TYPO_CHANCE_T2 end
        if chance > 0 and math.random(100) <= chance then
            local candidates = {}
            for idx = 2, n-1 do
                if not THAI_DIACRITICS[codepoints[idx]] then candidates[#candidates+1] = idx end
            end
            if #candidates > 0 then typoAt = candidates[math.random(#candidates)] end
        end
    end
    wBox.Text = ""
    if not instant then
        local prof0 = typingProfile(getTimerValue(), n)
        if prof0.instant then instant = true
        elseif prof0.hesHi > 0 then task.wait(math.random(prof0.hesLo, prof0.hesHi)/1000) end
    end
    if cancelled() then return false end
    if instant then
        wBox.Text = text
    else
        local buf = ""
        for i, ch in ipairs(chars) do
            if cancelled() then return false end
            buf = buf .. ch; wBox.Text = buf
            if not IS_TOUCH then wBox.CursorPosition = #buf + 1 end
            if i == typoAt then
                local wrongChar
                repeat wrongChar = TYPO_POOL[math.random(#TYPO_POOL)] until wrongChar ~= ch
                local wrongBuf = buf .. wrongChar; wBox.Text = wrongBuf
                if not IS_TOUCH then wBox.CursorPosition = #wrongBuf + 1 end
                task.wait(math.random(CFG.TYPO_NOTICE_LO, CFG.TYPO_NOTICE_HI)/1000)
                if cancelled() then return false end
                wBox.Text = buf
                if not IS_TOUCH then wBox.CursorPosition = #buf + 1 end
                task.wait(math.random(CFG.TYPO_FIX_LO, CFG.TYPO_FIX_HI)/1000)
                if cancelled() then return false end
            end
            if i == n then break end
            local t    = getTimerValue()
            local left = n - i
            local prof = typingProfile(t, left)
            if prof.instant then
                local rest = ""
                for j = i+1, n do rest = rest .. chars[j] end
                wBox.Text = buf .. rest
                if not IS_TOUCH then wBox.CursorPosition = n+1 end
                break
            end
            local delay; local roll = math.random(100)
            if roll <= prof.burst then
                delay = math.random(5,25)/1000
            elseif prof.pause > 0 and roll <= prof.burst + prof.pause then
                delay = math.random(180,420)/1000
            else
                local loMs = math.floor(prof.lo*1000)
                local hiMs = math.max(loMs+1, math.floor(prof.hi*1000))
                local base = math.random(loMs, hiMs)/1000
                local jit  = math.random(prof.jlo, prof.jhi)/1000
                local slow = (prof.endSlow and i >= n-1) and math.random(10,40)/1000 or 0
                delay = math.max(0.010, base + jit + slow)
            end
            local nextCp = codepoints[i+1]
            if nextCp and THAI_DIACRITICS[nextCp] then delay = delay * CFG.DIACRITIC_MULT end
            task.wait(delay)
        end
    end
    wBox.CursorPosition = #wBox.Text + 1
    return true
end

local function setStatus(text, color)
    expHint.Text       = text
    expHint.TextColor3 = color or COLORS.dim
    setCompactRight(text, color or COLORS.dim)
end

local function doAutoFill()
    if isTyping then return end
    local word = currentSuggestions[currentIndex]
    if not word then return end
    local wBox, pText = getInputBox()
    if not wBox then return end
    local suffix = word
    if pText ~= "" and word:sub(1,#pText) == pText then suffix = word:sub(#pText+1)
    elseif lastWord ~= "" and lastWord ~= "__none__" and word:sub(1,#lastWord) == lastWord then suffix = word:sub(#lastWord+1) end
    if suffix == "" then return end
    isTyping = true; currentTypeCycle = currentTypeCycle + 1
    local myCycle = currentTypeCycle
    local function cancelled() return myCycle ~= currentTypeCycle end
    local oldClear, oldNative
    local ok, err = pcall(function()
        oldClear = wBox.ClearTextOnFocus; wBox.ClearTextOnFocus = false
        if IS_TOUCH and CFG.MOBILE_HIDE_KEYBOARD then oldNative = wBox.ShowNativeInput; wBox.ShowNativeInput = false end
        wBox:CaptureFocus()
        local submitted = false; local waitBefore = CFG.SUBMIT_DELAY
        for attempt = 1, CFG.VERIFY_RETRIES + 1 do
            if cancelled() then return end
            if attempt > 1 then setStatus("⟳ พิมพ์ใหม่ "..(attempt-1), COLORS.dim) end
            if not fillBox(wBox, suffix, attempt > 1, cancelled) then return end
            task.wait(waitBefore); waitBefore = 0.2
            if cancelled() then return end
            if not wBox:IsFocused() then wBox:CaptureFocus() end
            if wBox.Text == suffix then
                while true do
                    if cancelled() then return end
                    local isFrozen = false
                    pcall(function()
                        local gameUI = LP.PlayerGui:FindFirstChild("GameUI")
                        local root   = gameUI and gameUI:FindFirstChild("Root")
                        local ice    = root  and root:FindFirstChild("IceOverlay")
                        if ice then
                            local lbl = ice:FindFirstChild("TextLabel")
                            if lbl and ice.Visible and lbl.Visible then isFrozen = true end
                        end
                    end)
                    if not isFrozen then break end
                    if getTimerValue() <= 0.45 then break end
                    setStatus("❄️ ติดน้ำแข็ง รอส่ง...", COLORS.ice)
                    task.wait(0.2)
                end
                submitBox(wBox); submitted = true; break
            end
        end
        if not submitted and not cancelled() then wBox.Text = ""; setStatus("✕ พิมพ์ไม่ตรง", COLORS.del_txt) end
    end)
    if not ok then warn("[WC_Helper] autofill error: "..tostring(err)) end
    pcall(function()
        if oldClear  ~= nil then wBox.ClearTextOnFocus = oldClear  end
        if oldNative ~= nil then wBox.ShowNativeInput  = oldNative end
    end)
    if myCycle == currentTypeCycle then isTyping = false end
end

local function checkAutoTrigger(targetWord)
    if not isAutoFillON or isTyping then return end
    task.spawn(function()
        local t = getTimerValue()
        local base, extra
        if t == math.huge or t > 6 then
            base  = math.random(60,180)/100; extra = math.random(100) <= 25 and math.random(40,120)/100 or 0
        elseif t > 3.5 then
            base  = math.random(30,90)/100;  extra = math.random(100) <= 15 and math.random(10,40)/100 or 0
        elseif t > 1.8 then
            base  = math.random(6,22)/100;   extra = 0
        else
            base  = math.random(2,8)/100;    extra = 0
        end
        task.wait(base + extra)
        if not isAutoFillON or isTyping then return end
        if lastWord ~= targetWord then return end
        doAutoFill()
    end)
end

-- ════════════════════════════════════════════
--  AUTO RANKED QUEUE
-- ════════════════════════════════════════════
local function clickGuiButton(button)
    local ok = pcall(function()
        button:FireMouseButton1Click()
    end)
    if ok then return end

    ok = pcall(function() firebutton(button) end)
    if ok then return end

    local pos = button.AbsolutePosition + button.AbsoluteSize * 0.5
    pcall(function()
        VIM:SendMouseButtonEvent(pos.X, pos.Y, 0, true,  game, 1)
        task.wait(0.05)
        VIM:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 1)
    end)
end

local function tryQueueRanked()
    if not CFG.AUTO_RANK then return end
    task.spawn(function()
        task.wait(CFG.RANK_QUEUE_DELAY)

        local function findBtn(patterns, timeout)
            local deadline = os.clock() + (timeout or 8)
            repeat
                for _, obj in ipairs(LP.PlayerGui:GetDescendants()) do
                    if obj:IsA("TextButton") then
                        local visible = true
                        local cur = obj
                        while cur and cur ~= LP.PlayerGui do
                            if cur:IsA("GuiObject") and not cur.Visible then
                                visible = false; break
                            end
                            cur = cur.Parent
                        end
                        if visible then
                            local allText = obj.Text
                            for _, desc in ipairs(obj:GetDescendants()) do
                                if desc:IsA("TextLabel") or desc:IsA("TextBox") then
                                    allText = allText .. desc.Text
                                end
                            end
                            for _, pat in ipairs(patterns) do
                                if allText:find(pat, 1, true) then
                                    return obj
                                end
                            end
                        end
                    end
                end
                task.wait(0.25)
            until os.clock() >= deadline
            return nil
        end

        local btn1 = findBtn({"แรงค์", "Ranked", "RANKED"}, CFG.RANK_FIND_TIMEOUT)
        if not btn1 then
            warn("[WC_Helper] ไม่พบปุ่มแรงค์ — dump:")
            for _, obj in ipairs(LP.PlayerGui:GetDescendants()) do
                if obj:IsA("TextButton") then
                    warn("  BTN: [" .. obj.Text .. "] @ " .. obj:GetFullName())
                end
            end
            return
        end

        warn("[WC_Helper] พบปุ่มแรงค์: " .. btn1:GetFullName() .. " pos=" .. tostring(btn1.AbsolutePosition))
        island:Notify({ Title = "Auto Ranked", Message = "กำลังกด แรงค์...", Duration = 2 })
        clickGuiButton(btn1)
        task.wait(CFG.RANK_MODE_DELAY)

        local btn2 = findBtn({"1v1", "ดวลเดี่ยว", "Solo", "SOLO"}, 6)
        if not btn2 then
            warn("[WC_Helper] ไม่พบปุ่ม 1v1 — dump:")
            for _, obj in ipairs(LP.PlayerGui:GetDescendants()) do
                if obj:IsA("TextButton") and obj.Visible then
                    warn("  BTN: [" .. obj.Text .. "] @ " .. obj:GetFullName())
                end
            end
            return
        end

        warn("[WC_Helper] พบปุ่ม 1v1: " .. btn2:GetFullName())
        island:Notify({ Title = "Auto Ranked", Message = "เลือก 1v1...", Duration = 2 })
        clickGuiButton(btn2)
    end)
end


-- ════════════════════════════════════════════
--  KEY BINDINGS
-- ════════════════════════════════════════════
UIS.InputBegan:Connect(function(input, _gameProcessed)
    if input.KeyCode == CFG.KEY_REMOVE then
        local word = currentSuggestions[currentIndex]
        if word then blacklisted[word] = true; refreshSuggestions(lastWord) end
    elseif input.KeyCode == CFG.KEY_RESET then
        blacklisted = {}
        if lastWord ~= "" and lastWord ~= "__none__" then refreshSuggestions(lastWord)
        else currentSuggestions, currentIndex = {}, 1; showCurrent() end
    elseif input.KeyCode == CFG.KEY_AUTOFILL and not isTyping then
        doAutoFill()
    end
end)

-- ════════════════════════════════════════════
--  SCANNER
-- ════════════════════════════════════════════
local function isValidWord(str)
    if str:match("[%a%d]") then return true end
    for i = 1, #str do
        local b = str:byte(i)
        if b == 0xE0 then
            local b2 = str:byte(i+1)
            if b2 == 0xB8 or b2 == 0xB9 then return true end
        end
    end
    return false
end

local function pathAllowed(path)
    for _, kw in ipairs(PATH_BLACKLIST) do if path:find(kw,1,true) then return false end end
    for _, kw in ipairs(PATH_WHITELIST) do if path:find(kw,1,true) then return true  end end
    return false
end

local function extractThaiRuns(text)
    local runs, buf = {}, {}
    local i, n = 1, #text
    while i <= n do
        local b1,b2,b3 = text:byte(i, i+2)
        if b1==0xE0 and (b2==0xB8 or b2==0xB9) and b3 and b3>=0x80 and b3<=0xBF then
            buf[#buf+1] = text:sub(i,i+2); i = i+3
        else
            if #buf > 0 then runs[#runs+1] = table.concat(buf); buf = {} end
            i = i+1
        end
    end
    if #buf > 0 then runs[#runs+1] = table.concat(buf) end
    return runs
end

local function extractWords(text)
    local words = {}; text = text:gsub("<[^>]*>","")
    for line in text:gmatch("[^\n\r]+") do
        if CFG.LOG_STRIP_PREFIX then
            local after = line:match(".*:%s*(.*)$"); if after then line = after end
        end
        for _, run in ipairs(extractThaiRuns(line)) do
            if utf8Len(run) >= 2 then words[#words+1] = run end
        end
    end
    return words
end

local function isShown(obj)
    local cur = obj
    while cur do
        if cur:IsA("GuiObject")      and not cur.Visible  then return false end
        if cur:IsA("LayerCollector") and not cur.Enabled  then return false end
        cur = cur.Parent
    end
    return true
end

local function classifyHistory(path)
    for _, kw in ipairs(PATH_BLACKLIST)   do if path:find(kw,1,true) then return nil       end end
    for _, kw in ipairs(HISTORY_KEYWORDS) do if path:find(kw,1,true) then return "unknown" end end
    return nil
end

local function updateUsedWords(hits)
    if #hits == 0 then
        if CFG.CLEAR_AFTER_EMPTY > 0 and usedCount > 0
            and os.clock() - lastHistorySeen >= CFG.CLEAR_AFTER_EMPTY then
            usedWords, usedCount = {}, 0; return true
        end
        return false
    end
    lastHistorySeen = os.clock(); local changed = false
    for _, h in ipairs(hits) do
        for _, w in ipairs(extractWords(h.text)) do
            if not usedWords[w] then usedWords[w] = h.owner; usedCount = usedCount+1; changed = true end
        end
    end
    return changed
end

local function scanAll()
    local candidates, history = {}, {}
    local myTurn = false
    pcall(function()
        local matchUI = LP.PlayerGui:FindFirstChild("GameUI")
        if matchUI and matchUI:FindFirstChild("Root") and matchUI.Root:FindFirstChild("Match") then
            local promptBox = matchUI.Root.Match:FindFirstChild("PromptBox")
            local promptLbl = promptBox and promptBox:FindFirstChild("Prompt")
            if promptLbl and promptLbl:IsA("TextLabel")
                and promptLbl.Text:find("ตาคุณ") and isShown(promptLbl) then myTurn = true end
        end
    end)
    local function recurse(root)
        for _, obj in ipairs(root:GetDescendants()) do
            if (obj:IsA("TextLabel") or obj:IsA("TextBox")) and not obj:IsDescendantOf(screenGui) then
                local txt = obj.Text or ""
                if txt ~= "" then
                    local path = obj:GetFullName(); local ts = obj.TextSize or 0
                    if #txt >= CFG.MIN_LEN and #txt <= CFG.MAX_LEN
                        and ts >= CFG.MIN_TXTSIZE and isValidWord(txt) and pathAllowed(path) then
                        table.insert(candidates, { text=txt, size=ts, path=path })
                    end
                    if CFG.TRACK_USED then
                        local owner = classifyHistory(path)
                        if owner and (not CFG.HISTORY_VISIBLE_ONLY or isShown(obj)) then
                            table.insert(history, { text=txt, owner=owner, path=path })
                        end
                    end
                end
            end
        end
    end
    recurse(game:GetService("Workspace")); recurse(LP.PlayerGui)
    if CFG.TRACK_USED then
        pcall(function()
            local matchUI = LP.PlayerGui:FindFirstChild("GameUI")
            if matchUI and matchUI:FindFirstChild("Root") and matchUI.Root:FindFirstChild("Match") then
                local matchNode = matchUI.Root.Match
                local inputBar  = matchNode:FindFirstChild("InputBar")
                if inputBar then
                    local pLbl  = inputBar:FindFirstChild("PrefixLabel")
                    local wBox  = inputBar:FindFirstChild("WordBox")
                    local pText = (pLbl and pLbl:IsA("TextLabel")) and pLbl.Text or ""
                    local wText = (wBox and wBox:IsA("TextBox"))   and wBox.Text or ""
                    pText = pText:gsub("<[^>]*>",""):gsub("%s+","")
                    wText = wText:gsub("<[^>]*>",""):gsub("%s+","")
                    if #(pText..wText) >= 3 then
                        table.insert(history, { text=pText..wText, owner="me", path="Custom_Prefix" })
                    end
                end
                local feedback = matchNode:FindFirstChild("Feedback")
                if feedback and feedback:IsA("TextLabel") and feedback.Text ~= "" then
                    table.insert(history, { text=feedback.Text, owner="other", path=feedback:GetFullName() })
                end
            end
        end)
    end
    table.sort(candidates, function(a,b) return a.size > b.size end)
    return candidates, history, myTurn
end

-- ════════════════════════════════════════════
--  WIN DETECTION + CHAIR SIT
-- ════════════════════════════════════════════
local lastWinHandled = 0
local WIN_COOLDOWN   = 5

local function findNearestSeat()
    local char = LP.Character; if not char then return nil end
    local root = char:FindFirstChild("HumanoidRootPart"); if not root then return nil end
    local nearest, minDist = nil, math.huge
    for _, obj in ipairs(workspace:GetDescendants()) do
        if (obj:IsA("Seat") or obj:IsA("VehicleSeat")) and obj.Occupant == nil then
            local d = (obj.Position - root.Position).Magnitude
            if d < minDist then minDist = d; nearest = obj end
        end
    end
    return nearest
end

local function sitIfNeeded()
    local char = LP.Character; if not char then return end
    local hum  = char:FindFirstChildOfClass("Humanoid"); if not hum then return end
    if hum.SeatPart then return end
    local seat = findNearestSeat(); if seat then seat:Sit(hum) end
end

task.spawn(function()
    local gui    = PGui:WaitForChild("GameUI")
    local root   = gui:WaitForChild("Root")
    local banner = root:WaitForChild("Banner")
    local lbl    = banner:WaitForChild("TextLabel")

    local function onWin()
        local now = os.clock()
        if not lbl.Text:find("คุณชนะ", 1, true) then return end
        if now - lastWinHandled <= WIN_COOLDOWN then return end
        lastWinHandled       = now
        usedWords, usedCount = {}, 0
        lastHistorySeen      = 0
        currentSuggestions, currentIndex = {}, 1
        showCurrent()
        task.wait(0.5)
        task.spawn(function()
            VIM:SendKeyEvent(true,  Enum.KeyCode.W, false, nil)
            VIM:SendKeyEvent(true,  Enum.KeyCode.S, false, nil)
            task.wait(0.3)
            VIM:SendKeyEvent(false, Enum.KeyCode.W, false, nil)
            VIM:SendKeyEvent(false, Enum.KeyCode.S, false, nil)
            task.wait(0.1)
            sitIfNeeded()
        end)
        tryQueueRanked()
    end

    lbl:GetPropertyChangedSignal("Text"):Connect(onWin)
    local watched = banner:IsA("GuiObject") and banner or lbl
    watched:GetPropertyChangedSignal("Visible"):Connect(function()
        if watched.Visible then onWin() end
    end)
end)

task.spawn(function()
    local gui      = PGui:WaitForChild("GameUI")
    local root     = gui:WaitForChild("Root")
    local match    = root:WaitForChild("Match")
    local feedback = match:WaitForChild("Feedback")
    local lastRejectedWord = ""

    feedback:GetPropertyChangedSignal("Text"):Connect(function()
        if not feedback.Text:find("ไม่พบคำนี้ในพจนานุกรม", 1, true) then return end
        local word = currentSuggestions[currentIndex]
        if not word or word == lastRejectedWord then return end
        lastRejectedWord  = word
        blacklisted[word] = true
        refreshSuggestions(lastWord)
        task.wait(0.3)
        if not isTyping then doAutoFill() end
    end)
end)

-- ════════════════════════════════════════════
--  ANTI AFK
-- ════════════════════════════════════════════
local VirtualUser = game:GetService("VirtualUser")
LP.Idled:Connect(function()
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.new())
end)

-- ════════════════════════════════════════════
--  MAIN LOOP + ISLAND ENTRANCE
-- ════════════════════════════════════════════
task.spawn(function()
    task.wait(0.4)
    island:Show()
end)

task.spawn(function()
    local wasMyTurn = false
    while true do
        task.wait(CFG.SCAN_RATE)
        local results, history, isMyTurn = scanAll()
        local top         = results[1]
        local usedChanged = updateUsedWords(history)
        local wordChanged = false

        if top and top.text ~= lastWord then
            lastWord = top.text; refreshSuggestions(top.text); wordChanged = true
        elseif not top and lastWord ~= "__none__" then
            lastWord, currentSuggestions, currentIndex = "__none__", {}, 1; showCurrent(); wordChanged = true
        elseif usedChanged and lastWord ~= "" and lastWord ~= "__none__" then
            refreshSuggestions(lastWord)
        end

        if isAutoFillON and isMyTurn and currentSuggestions[1] then
            if (not wasMyTurn) or wordChanged then checkAutoTrigger(lastWord) end
        end

        wasMyTurn = isMyTurn
    end
end)
task.wait(3)
tryQueueRanked()

