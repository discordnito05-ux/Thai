-- WordChain Helper | v3.8 (Verify-before-send + mobile/iPad typing fix)

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

    -- ความเร็วในการพิมพ์ (วินาทีต่อ 1 ตัวอักษร) ยิ่งน้อยยิ่งพิมพ์ไว
    TYPING_SPEED_MIN = 0.02,
    TYPING_SPEED_MAX = 0.12,

    SUBMIT_DELAY         = 3,    -- รอกี่วินาทีหลังพิมพ์เสร็จก่อนส่ง (เดิม task.wait(3))
    VERIFY_RETRIES       = 4,    -- ถ้าข้อความในช่องไม่ตรง ให้ลบแล้วพิมพ์ใหม่ได้สูงสุดกี่ครั้ง
    MOBILE_HIDE_KEYBOARD = true, -- มือถือ/ไอแพด: ไม่เปิดคีย์บอร์ดจริงตอนออโต้พิมพ์ (กัน IME ตีกับสคริปต์)

    KEY_REMOVE   = Enum.KeyCode.LeftAlt, 
    KEY_RESET    = Enum.KeyCode.Delete,
    KEY_AUTOFILL = Enum.KeyCode.Tab, 
    KEY_DUMP     = Enum.KeyCode.Insert, 

    TRACK_USED           = true,  
    HISTORY_VISIBLE_ONLY = true,  
    CLEAR_AFTER_EMPTY    = 8,     
    LOG_STRIP_PREFIX     = true,  
}

local CURRENT_SPEED_DELAY = 0.05 -- ค่าเริ่มต้นความหน่วงต่อตัวอักษร

local PATH_WHITELIST = { "InputBar", "Match", "GameWord", "CurrentWord", "WordDisplay" }
local PATH_BLACKLIST = { "Menu", "Settings", "Lobby", "Profile", "Button", "Mode", "Code" }

local HISTORY_KEYWORDS = { "History", "UsedWords", "WordLog", "WordList" }

local SOURCE_URL = "https://raw.githubusercontent.com/PyThaiNLP/pythainlp/dev/pythainlp/corpus/words_th.txt"
local CACHE_PATH = "WordDB_ptnlp.txt"
local FREQ_SOURCE_URL = "https://raw.githubusercontent.com/PyThaiNLP/pythainlp/dev/pythainlp/corpus/tnc_freq.txt"
local FREQ_CACHE_PATH = "WordFreq_tnc.txt"

local function firstChar(str)
    if #str == 0 then return nil end
    local b = str:byte(1)
    if     b >= 0xF0 then return str:sub(1, 4)
    elseif b >= 0xE0 then return str:sub(1, 3)
    elseif b >= 0xC0 then return str:sub(1, 2)
    else                   return str:sub(1, 1) end
end

local function isThaiOnlyWord(word)
    local len = #word
    if len == 0 or len % 3 ~= 0 then return false end
    for i = 1, len, 3 do
        local b1, b2, b3 = word:byte(i, i + 2)
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
            local n = 0; for _, v in pairs(db) do n = n + #v end
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
WORD_FREQ = loadFreqDB()

local blacklisted = {}
local usedWords = {}
local usedCount = 0
local isAutoFillON = false 
local isTyping = false     

local function utf8Len(str)
    local n = 0
    for i = 1, #str do
        local b = str:byte(i)
        if b < 0x80 or b >= 0xC0 then n = n + 1 end
    end
    return n
end

local function getSuggestions(prefix)
    local plen = #prefix
    local out  = {}
    local fc   = firstChar(prefix)
    if not fc then return out end
    local bucket = WORD_DB[fc]
    if not bucket then return out end

    local minChars = CFG.MIN_SUGGEST_CHARS
    for _, w in ipairs(bucket) do
        if #w > plen and w:sub(1, plen) == prefix and not blacklisted[w] and not usedWords[w] and utf8Len(w) >= minChars then
            table.insert(out, w)
        end
    end

    table.sort(out, function(a, b)
        local fa = WORD_FREQ[a] or 0
        local fb = WORD_FREQ[b] or 0
        if fa ~= fb then return fa > fb end
        return #a < #b
    end)

    local result = {}
    for i = 1, math.min(#out, CFG.MAX_SUGGEST) do result[i] = out[i] end
    return result
end

local lastWord           = ""
local currentSuggestions = {}
local currentIndex       = 1

-- ════════════════════════════════════════════
--  GUI & STYLING
-- ════════════════════════════════════════════
local COLORS = {
    bg        = Color3.fromHex("0D0D0D"),
    border    = Color3.fromHex("2A2A2A"),
    accent    = Color3.fromHex("4CFFE8"),
    text      = Color3.fromHex("EAEAEA"),
    dim       = Color3.fromHex("888888"),
    del_bg    = Color3.fromHex("1E1010"),
    del_txt   = Color3.fromHex("FF6B6B"),
    rst_bg    = Color3.fromHex("101E1A"),
    rst_txt   = Color3.fromHex("4CFFE8"),
    set_bg    = Color3.fromHex("14181C"),
    set_txt   = Color3.fromHex("AEB4BA"),
    auto_txt  = Color3.fromHex("44FF77"),
    auto_on   = Color3.fromHex("2E7D32"),
    popup_bg  = Color3.fromHex("161616"),
}

if PGui:FindFirstChild("WC_Helper") then PGui:FindFirstChild("WC_Helper"):Destroy() end
local gui = Instance.new("ScreenGui", PGui)
gui.Name, gui.ResetOnSpawn, gui.ZIndexBehavior, gui.IgnoreGuiInset = "WC_Helper", false, Enum.ZIndexBehavior.Sibling, true

local island = Instance.new("Frame", gui)
island.AnchorPoint, island.Position, island.Size, island.AutomaticSize = Vector2.new(0.5, 0), UDim2.new(0.5, 0, 0, -100), UDim2.new(0, 0, 0, 52), Enum.AutomaticSize.X
island.BackgroundColor3 = COLORS.bg
Instance.new("UICorner", island).CornerRadius = UDim.new(0, 26)
local stroke = Instance.new("UIStroke", island); stroke.Color, stroke.Thickness = COLORS.border, 1
local pad = Instance.new("UIPadding", island); pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 14), UDim.new(0, 14)
local layout = Instance.new("UIListLayout", island)
layout.FillDirection, layout.VerticalAlignment, layout.Padding, layout.SortOrder = Enum.FillDirection.Horizontal, Enum.VerticalAlignment.Center, UDim.new(0, 12), Enum.SortOrder.LayoutOrder

local badge = Instance.new("Frame", island)
badge.Size, badge.BackgroundColor3, badge.LayoutOrder = UDim2.new(0, 36, 0, 36), COLORS.accent, 1
Instance.new("UICorner", badge).CornerRadius = UDim.new(1, 0)
local badgeScale = Instance.new("UIScale", badge)
local badgeLabel = Instance.new("TextLabel", badge)
badgeLabel.Size, badgeLabel.BackgroundTransparency, badgeLabel.Font, badgeLabel.TextSize, badgeLabel.TextColor3, badgeLabel.Text = UDim2.new(1, 0, 1, 0), 1, Enum.Font.GothamBold, 16, COLORS.bg, "W"

local textStack = Instance.new("Frame", island)
textStack.BackgroundTransparency, textStack.Size, textStack.AutomaticSize, textStack.LayoutOrder = 1, UDim2.new(0, 0, 0, 42), Enum.AutomaticSize.X, 2
local stackLayout = Instance.new("UIListLayout", textStack); stackLayout.FillDirection, stackLayout.SortOrder = Enum.FillDirection.Vertical, Enum.SortOrder.LayoutOrder

local subtitleLabel = Instance.new("TextLabel", textStack)
subtitleLabel.Size, subtitleLabel.AutomaticSize, subtitleLabel.BackgroundTransparency, subtitleLabel.Font, subtitleLabel.TextSize, subtitleLabel.TextColor3, subtitleLabel.Text = UDim2.new(0, 0, 0, 14), Enum.AutomaticSize.X, 1, Enum.Font.Gotham, 11, COLORS.dim, "สถานะ"

local wordRow = Instance.new("Frame", textStack)
wordRow.BackgroundTransparency, wordRow.Size, wordRow.AutomaticSize = 1, UDim2.new(0, 0, 0, 24), Enum.AutomaticSize.X
local wordRowLayout = Instance.new("UIListLayout", wordRow); wordRowLayout.FillDirection, wordRowLayout.Padding = Enum.FillDirection.Horizontal, UDim.new(0, 6)

local wordLabel = Instance.new("TextLabel", wordRow)
wordLabel.Size, wordLabel.AutomaticSize, wordLabel.BackgroundTransparency, wordLabel.Font, wordLabel.TextSize, wordLabel.TextColor3, wordLabel.Text = UDim2.new(0, 0, 1, 0), Enum.AutomaticSize.X, 1, Enum.Font.GothamBold, 18, COLORS.text, "รอคำจากเกม..."

local autoHintChip = Instance.new("TextLabel", wordRow)
autoHintChip.Size, autoHintChip.AutomaticSize, autoHintChip.BackgroundTransparency, autoHintChip.Font, autoHintChip.TextSize, autoHintChip.TextColor3, autoHintChip.Text = UDim2.new(0, 0, 1, 0), Enum.AutomaticSize.X, 1, Enum.Font.GothamBold, 14, COLORS.auto_txt, ""

local function makeIconButton(iconAssetId, fallbackText, bgColor, iconColor, order)
    local btn = Instance.new("ImageButton", island)
    btn.Size, btn.BackgroundColor3, btn.AutoButtonColor, btn.LayoutOrder, btn.Visible = UDim2.new(0, 34, 0, 34), bgColor, false, order, false
    Instance.new("UICorner", btn).CornerRadius = UDim.new(1, 0)
    local scale = Instance.new("UIScale", btn)
    local txt
    if iconAssetId and iconAssetId ~= "" then
        local img = Instance.new("ImageLabel", btn)
        img.Size, img.AnchorPoint, img.Position, img.BackgroundTransparency, img.Image, img.ImageColor3 = UDim2.new(0, 16, 0, 16), Vector2.new(0.5, 0.5), UDim2.new(0.5, 0, 0.5, 0), 1, iconAssetId, iconColor
    else
        txt = Instance.new("TextLabel", btn)
        txt.Size, txt.BackgroundTransparency, txt.Font, txt.TextSize, txt.TextColor3, txt.Text = UDim2.new(1, 0, 1, 0), 1, Enum.Font.GothamBold, 14, iconColor, fallbackText
    end
    btn.MouseEnter:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 1.1}):Play() end)
    btn.MouseLeave:Connect(function() TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 1.0}):Play() end)
    btn.MouseButton1Down:Connect(function() TweenService:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 0.9}):Play() end)
    btn.MouseButton1Up:Connect(function() TweenService:Create(scale, TweenInfo.new(0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Scale = 1.1}):Play() end)
    return btn, scale, txt
end

local lenMinusBtn, lenMinusScale = makeIconButton("", "-", COLORS.set_bg, COLORS.set_txt, 3); lenMinusBtn.Visible = true
local lenLabel = Instance.new("TextLabel", island)
lenLabel.Size, lenLabel.BackgroundTransparency, lenLabel.Font, lenLabel.TextSize, lenLabel.TextColor3, lenLabel.Text, lenLabel.LayoutOrder = UDim2.new(0, 20, 0, 34), 1, Enum.Font.GothamBold, 14, COLORS.text, tostring(CFG.MIN_SUGGEST_CHARS), 4
local lenPlusBtn, lenPlusScale = makeIconButton("", "+", COLORS.set_bg, COLORS.set_txt, 5); lenPlusBtn.Visible = true

local resetBtn, resetScale   = makeIconButton("rbxassetid://10747373176", "↺", COLORS.rst_bg, COLORS.rst_txt, 6)
local removeBtn, removeScale = makeIconButton("rbxassetid://10747384394", "✕", COLORS.del_bg, COLORS.del_txt, 7)
local speedBtn, speedScale, speedTxt = makeIconButton("", "⚡", COLORS.set_bg, COLORS.set_txt, 8); speedBtn.Visible = true
local autoBtn, autoScale, autoTxt = makeIconButton("", "A", COLORS.set_bg, COLORS.set_txt, 9); autoBtn.Visible = true

-- ════════════════════════════════════════════
--  SPEED POPUP PANEL (หน้าต่างปรับความเร็ว)
-- ════════════════════════════════════════════
local speedPopup = Instance.new("Frame", gui)
speedPopup.Size, speedPopup.Position, speedPopup.BackgroundColor3 = UDim2.new(0, 160, 0, 95), UDim2.new(0.5, -80, 0, 78), COLORS.popup_bg
speedPopup.Visible, speedPopup.BackgroundTransparency = false, 0.1
Instance.new("UICorner", speedPopup).CornerRadius = UDim.new(0, 14)
local popupStroke = Instance.new("UIStroke", speedPopup); popupStroke.Color, popupStroke.Thickness = COLORS.border, 1

local popupLayout = Instance.new("UIListLayout", speedPopup)
popupLayout.HorizontalAlignment, popupLayout.VerticalAlignment, popupLayout.SortOrder, popupLayout.Padding = Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center, Enum.SortOrder.LayoutOrder, UDim.new(0, 6)
local popupPad = Instance.new("UIPadding", speedPopup); popupPad.PaddingTop, popupPad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8)

local popupTitle = Instance.new("TextLabel", speedPopup)
popupTitle.Size, popupTitle.BackgroundTransparency, popupTitle.Font, popupTitle.TextSize, popupTitle.TextColor3, popupTitle.Text = UDim2.new(1, 0, 0, 18), 1, Enum.Font.GothamBold, 12, COLORS.dim, "ความเร็วพิมพ์ (Speed)"

local speedValLabel = Instance.new("TextLabel", speedPopup)
speedValLabel.Size, speedValLabel.BackgroundTransparency, speedValLabel.Font, speedValLabel.TextSize, speedValLabel.TextColor3 = UDim2.new(1, 0, 0, 22), 1, Enum.Font.GothamBold, 15, COLORS.accent

local function updateSpeedLabel()
    speedValLabel.Text = string.format("%.2fs / ตัวอักษร", CURRENT_SPEED_DELAY)
end
updateSpeedLabel()

-- แถบเลื่อนปรับความเร็ว (Slider UI)
local sliderBg = Instance.new("Frame", speedPopup)
sliderBg.Size, sliderBg.BackgroundColor3 = UDim2.new(0, 130, 0, 8), Color3.fromHex("222222")
Instance.new("UICorner", sliderBg).CornerRadius = UDim.new(1, 0)

local sliderFill = Instance.new("Frame", sliderBg)
sliderFill.Size, sliderFill.BackgroundColor3 = UDim2.new(0.5, 0, 1, 0), COLORS.accent
Instance.new("UICorner", sliderFill).CornerRadius = UDim.new(1, 0)

local sliderBtn = Instance.new("TextButton", sliderBg)
sliderBtn.Size, sliderBtn.AnchorPoint, sliderBtn.Position, sliderBtn.BackgroundColor3, sliderBtn.Text = UDim2.new(0, 14, 0, 14), Vector2.new(0.5, 0.5), UDim2.new(0.5, 0, 0.5, 0), Color3.new(1, 1, 1), ""
Instance.new("UICorner", sliderBtn).CornerRadius = UDim.new(1, 0)

local function updateSliderPos(val)
    local alpha = math.clamp((val - CFG.TYPING_SPEED_MIN) / (CFG.TYPING_SPEED_MAX - CFG.TYPING_SPEED_MIN), 0, 1)
    sliderFill.Size = UDim2.new(alpha, 0, 1, 0)
    sliderBtn.Position = UDim2.new(alpha, 0, 0.5, 0)
end

local isDraggingSlider = false
local function isPress(input) return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch end
sliderBtn.InputBegan:Connect(function(input) if isPress(input) then isDraggingSlider = true end end)
UIS.InputEnded:Connect(function(input) if isPress(input) then isDraggingSlider = false end end)

UIS.InputChanged:Connect(function(input)
    if isDraggingSlider and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local mousePos = input.Position.X
        local absPos = sliderBg.AbsolutePosition.X
        local absSize = sliderBg.AbsoluteSize.X
        local alpha = math.clamp((mousePos - absPos) / absSize, 0, 1)
        
        -- คำนวณค่า Delay ใหม่ (สลับด้าน: ซ้ายเร็ว ขวาช้า หรือ ซ้ายช้า ขวาเร็ว ตามชอบ เลือกให้ซ้ายเร็วขวาช้า)
        CURRENT_SPEED_DELAY = CFG.TYPING_SPEED_MIN + (alpha * (CFG.TYPING_SPEED_MAX - CFG.TYPING_SPEED_MIN))
        updateSliderPos(CURRENT_SPEED_DELAY)
        updateSpeedLabel()
    end
end)

-- ฟังก์ชันเปิด/ปิด Popup ความเร็ว
speedBtn.MouseButton1Click:Connect(function()
    speedPopup.Visible = not speedPopup.Visible
    updateSliderPos(CURRENT_SPEED_DELAY)
end)

local function pulse(scaleObj)
    scaleObj.Scale = 0.8
    TweenService:Create(scaleObj, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local function toggleButtons(visible)
    if visible and not resetBtn.Visible then
        resetBtn.Visible, removeBtn.Visible = true, true
        resetScale.Scale, removeScale.Scale = 0, 0
        TweenService:Create(resetScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
        task.wait(0.05)
        TweenService:Create(removeScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {Scale = 1}):Play()
    elseif not visible and resetBtn.Visible then
        resetBtn.Visible, removeBtn.Visible = false, false
    end
end

-- ════════════════════════════════════════════
--  AUTO FILL & HUMAN TYPING SYSTEM
-- ════════════════════════════════════════════
local currentTypeCycle = 0
local IS_TOUCH = UIS.TouchEnabled

-- หาช่องพิมพ์ของเกม + คำนำหน้าที่เกมแสดงไว้
local function getInputBox()
    local gameUI = LP.PlayerGui:FindFirstChild("GameUI")
    local root   = gameUI and gameUI:FindFirstChild("Root")
    local match  = root and root:FindFirstChild("Match")
    local bar    = match and match:FindFirstChild("InputBar")
    if not bar then return nil end
    local wBox = bar:FindFirstChild("WordBox")
    if not (wBox and wBox:IsA("TextBox")) then return nil end
    local pLbl  = bar:FindFirstChild("PrefixLabel")
    local pText = (pLbl and pLbl:IsA("TextLabel")) and pLbl.Text or ""
    pText = pText:gsub("<[^>]*>", ""):gsub("%s+", "")
    return wBox, pText
end

-- ส่งคำ: ทัช (มือถือ/ไอแพด) ใช้ ReleaseFocus(true) เพราะ VIM ส่ง Enter ไม่ค่อยติด / PC ใช้ Enter
local function submitBox(wBox)
    if IS_TOUCH then
        local ok = pcall(function() wBox:ReleaseFocus(true) end)
        if ok then return end
    end
    VIM:SendKeyEvent(true, Enum.KeyCode.Return, false, game)
    task.wait(0.05)
    VIM:SendKeyEvent(false, Enum.KeyCode.Return, false, game)
end

-- ลบช่องแล้วพิมพ์ใหม่ ใช้ buffer ของเราเอง (ไม่อ่านกลับจาก wBox.Text ระหว่างพิมพ์
-- เพราะบนมือถือ IME อาจแก้ข้อความทำให้ตัวอักษรเพี้ยน/ซ้ำ)
local function fillBox(wBox, text, instant, cancelled)
    wBox.Text = ""
    task.wait(0.1)
    if cancelled() then return false end

    if instant then
        wBox.Text = text
    else
        local buf = ""
        for _, c in utf8.codes(text) do
            if cancelled() then return false end
            buf = buf .. utf8.char(c)
            wBox.Text = buf
            if not IS_TOUCH then wBox.CursorPosition = #buf + 1 end
            task.wait(math.max(0.01, CURRENT_SPEED_DELAY + math.random(-10, 10) / 1000))
        end
    end
    wBox.CursorPosition = #wBox.Text + 1
    return true
end

local function doAutoFill()
    if isTyping then return end
    local word = currentSuggestions[currentIndex]
    if not word then return end

    local wBox, pText = getInputBox()
    if not wBox then return end

    -- ส่วนที่ต้องพิมพ์จริง (ตัดคำนำหน้าที่เกมใส่ให้แล้วออก)
    local suffix = word
    if pText ~= "" and word:sub(1, #pText) == pText then
        suffix = word:sub(#pText + 1)
    elseif lastWord ~= "" and lastWord ~= "__none__" and word:sub(1, #lastWord) == lastWord then
        suffix = word:sub(#lastWord + 1)
    end
    if suffix == "" then return end

    isTyping = true
    currentTypeCycle = currentTypeCycle + 1
    local myCycle = currentTypeCycle
    local function cancelled() return myCycle ~= currentTypeCycle end

    local oldClear, oldNative
    local ok, err = pcall(function()
        oldClear = wBox.ClearTextOnFocus
        wBox.ClearTextOnFocus = false
        if IS_TOUCH and CFG.MOBILE_HIDE_KEYBOARD then
            oldNative = wBox.ShowNativeInput
            wBox.ShowNativeInput = false
        end

        wBox:CaptureFocus()
        pulse(badgeScale)

        local submitted = false
        local waitBefore = CFG.SUBMIT_DELAY -- ครั้งแรกรอตามที่ตั้งไว้ รอบพิมพ์ใหม่รอสั้น ๆ

        for attempt = 1, CFG.VERIFY_RETRIES + 1 do
            if cancelled() then return end
            if attempt > 1 then autoHintChip.Text = "⟳ พิมพ์ใหม่ " .. (attempt - 1) end

            -- รอบแรกพิมพ์ทีละตัวตาม Speed / รอบที่ลองใหม่ใส่ทั้งคำทีเดียว (ไม่ผ่าน IME ทีละตัว)
            if not fillBox(wBox, suffix, attempt > 1, cancelled) then return end

            task.wait(waitBefore)
            waitBefore = 0.2
            if cancelled() then return end

            if not wBox:IsFocused() then wBox:CaptureFocus() end

            -- เช็คก่อนส่ง: ข้อความในช่องต้องตรงกับคำที่แนะนำเป๊ะ ๆ
            if wBox.Text == suffix then
                submitBox(wBox)
                submitted = true
                break
            end
        end

        if not submitted and not cancelled() then
            wBox.Text = ""
            autoHintChip.Text = "✕ พิมพ์ไม่ตรง"
        end
    end)
    if not ok then warn("[WC_Helper] autofill error: " .. tostring(err)) end

    -- คืนค่าที่ปรับไว้ชั่วคราว
    pcall(function()
        if oldClear ~= nil then wBox.ClearTextOnFocus = oldClear end
        if oldNative ~= nil then wBox.ShowNativeInput = oldNative end
    end)
    if myCycle == currentTypeCycle then isTyping = false end
end

local function checkAutoTrigger(targetWord)
    if not isAutoFillON or isTyping then return end
    
    task.spawn(function()
        task.wait(math.random(4, 10) / 10) 
        if not isAutoFillON or isTyping then return end
        if lastWord ~= targetWord then return end 
        doAutoFill()
    end)
end

local function showCurrent()
    local word = currentSuggestions[currentIndex]
    local hasWord = (lastWord ~= "" and lastWord ~= "__none__")

    if hasWord then
        subtitleLabel.Text = "ต่อจาก " .. lastWord .. "  ·  ใช้แล้ว " .. usedCount
        if word then
            wordLabel.Text     = word
            autoHintChip.Text  = isAutoFillON and "[Auto Mode]" or "[Tab] พิมพ์คำนี้"
        else
            wordLabel.Text     = "ไม่มีคำแนะนำ"
            autoHintChip.Text  = ""
            isTyping = false 
            currentTypeCycle = currentTypeCycle + 1 
        end
        toggleButtons(true)
    else
        subtitleLabel.Text = "สถานะ"
        wordLabel.Text     = "รอคำจากเกม..."
        autoHintChip.Text  = ""
        isTyping = false
        currentTypeCycle = currentTypeCycle + 1
        toggleButtons(false)
    end
    pulse(badgeScale)
end

local function refreshSuggestions(prefix)
    currentSuggestions = getSuggestions(prefix)
    currentIndex       = 1
    showCurrent()
end

-- ════════════════════════════════════════════
--  UI CONTROLS
-- ════════════════════════════════════════════
autoBtn.MouseButton1Click:Connect(function()
    isAutoFillON = not isAutoFillON
    if isAutoFillON then
        TweenService:Create(autoBtn, TweenInfo.new(0.2), {BackgroundColor3 = COLORS.auto_on}):Play()
        autoTxt.TextColor3 = Color3.new(1, 1, 1)
    else
        TweenService:Create(autoBtn, TweenInfo.new(0.2), {BackgroundColor3 = COLORS.set_bg}):Play()
        autoTxt.TextColor3 = COLORS.set_txt
    end
    showCurrent() 
    pulse(autoScale)
end)

local function doRemove()
    local word = currentSuggestions[currentIndex]
    if word then
        blacklisted[word] = true
        refreshSuggestions(lastWord)
        pulse(removeScale)
    end
end

local function doReset()
    blacklisted = {}
    if lastWord ~= "" and lastWord ~= "__none__" then refreshSuggestions(lastWord)
    else currentSuggestions, currentIndex = {}, 1; showCurrent() end
    pulse(resetScale)
end

removeBtn.MouseButton1Click:Connect(doRemove)
resetBtn.MouseButton1Click:Connect(doReset)
lenMinusBtn.MouseButton1Click:Connect(function() CFG.MIN_SUGGEST_CHARS = math.clamp(CFG.MIN_SUGGEST_CHARS - 1, 1, 15) lenLabel.Text = tostring(CFG.MIN_SUGGEST_CHARS) refreshSuggestions(lastWord) pulse(lenMinusScale) end)
lenPlusBtn.MouseButton1Click:Connect(function() CFG.MIN_SUGGEST_CHARS = math.clamp(CFG.MIN_SUGGEST_CHARS + 1, 1, 15) lenLabel.Text = tostring(CFG.MIN_SUGGEST_CHARS) refreshSuggestions(lastWord) pulse(lenPlusScale) end)

UIS.InputBegan:Connect(function(input, gameProcessed)
    if input.KeyCode == CFG.KEY_REMOVE then doRemove()
    elseif input.KeyCode == CFG.KEY_RESET then doReset()
    elseif input.KeyCode == CFG.KEY_AUTOFILL and not isTyping then doAutoFill()
    end
end)

-- ════════════════════════════════════════════
--  SCANNER (PromptBox Path)
-- ════════════════════════════════════════════
local function isValidWord(str)
    if str:match("[%a%d]") then return true end
    for i = 1, #str do
        local b = str:byte(i)
        if b == 0xE0 then
            local b2 = str:byte(i + 1)
            if b2 == 0xB8 or b2 == 0xB9 then return true end
        end
    end
    return false
end

local function pathAllowed(path)
    for _, kw in ipairs(PATH_BLACKLIST) do if path:find(kw, 1, true) then return false end end
    for _, kw in ipairs(PATH_WHITELIST) do if path:find(kw, 1, true) then return true end end
    return false
end

local lastHistorySeen = os.clock()
local function extractThaiRuns(text)
    local runs, buf = {}, {}
    local i, n = 1, #text
    while i <= n do
        local b1, b2, b3 = text:byte(i, i + 2)
        if b1 == 0xE0 and (b2 == 0xB8 or b2 == 0xB9) and b3 and b3 >= 0x80 and b3 <= 0xBF then
            buf[#buf + 1] = text:sub(i, i + 2); i = i + 3
        else
            if #buf > 0 then runs[#runs + 1] = table.concat(buf); buf = {} end
            i = i + 1
        end
    end
    if #buf > 0 then runs[#runs + 1] = table.concat(buf) end
    return runs
end

local function extractWords(text)
    local words = {}
    text = text:gsub("<[^>]*>", "")
    for line in text:gmatch("[^\n\r]+") do
        if CFG.LOG_STRIP_PREFIX then
            local after = line:match(".*:%s*(.*)$")
            if after then line = after end
        end
        for _, run in ipairs(extractThaiRuns(line)) do
            if utf8Len(run) >= 2 then words[#words + 1] = run end
        end
    end
    return words
end

local function isShown(obj)
    local cur = obj
    while cur do
        if cur:IsA("GuiObject") and not cur.Visible then return false end
        if cur:IsA("LayerCollector") and not cur.Enabled then return false end
        cur = cur.Parent
    end
    return true
end

local function classifyHistory(path)
    for _, kw in ipairs(PATH_BLACKLIST) do if path:find(kw, 1, true) then return nil end end
    for _, kw in ipairs(HISTORY_KEYWORDS) do if path:find(kw, 1, true) then return "unknown" end end
    return nil
end

local function updateUsedWords(hits)
    if #hits == 0 then
        if CFG.CLEAR_AFTER_EMPTY > 0 and usedCount > 0 and os.clock() - lastHistorySeen >= CFG.CLEAR_AFTER_EMPTY then
            usedWords, usedCount = {}, 0
            return true
        end
        return false
    end
    lastHistorySeen = os.clock()
    local changed = false
    for _, h in ipairs(hits) do
        for _, w in ipairs(extractWords(h.text)) do
            if not usedWords[w] then
                usedWords[w] = h.owner
                usedCount = usedCount + 1
                changed = true
            end
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
            local promptLbl = matchUI.Root.Match:FindFirstChild("PromptBox") and matchUI.Root.Match.PromptBox:FindFirstChild("Prompt")
            if promptLbl and promptLbl:IsA("TextLabel") then
                if promptLbl.Text:find("ตาคุณ") and isShown(promptLbl) then
                    myTurn = true
                end
            end
        end
    end)
    
    local function recurse(root)
        for _, obj in ipairs(root:GetDescendants()) do
            if (obj:IsA("TextLabel") or obj:IsA("TextBox")) and not obj:IsDescendantOf(gui) then
                local txt = obj.Text or ""
                if txt ~= "" then
                    local path = obj:GetFullName()
                    local ts = obj.TextSize or 0
                    if #txt >= CFG.MIN_LEN and #txt <= CFG.MAX_LEN and ts >= CFG.MIN_TXTSIZE and isValidWord(txt) and pathAllowed(path) then
                        table.insert(candidates, { text = txt, size = ts, path = path })
                    end
                    if CFG.TRACK_USED then
                        local owner = classifyHistory(path)
                        if owner and (not CFG.HISTORY_VISIBLE_ONLY or isShown(obj)) then
                            table.insert(history, { text = txt, owner = owner, path = path })
                        end
                    end
                end
            end
        end
    end
    recurse(game:GetService("Workspace"))
    recurse(LP.PlayerGui)

    if CFG.TRACK_USED then
        pcall(function()
            local matchUI = LP.PlayerGui:FindFirstChild("GameUI")
            if matchUI and matchUI:FindFirstChild("Root") and matchUI.Root:FindFirstChild("Match") then
                local matchNode = matchUI.Root.Match
                local inputBar = matchNode:FindFirstChild("InputBar")
                if inputBar then
                    local pLbl = inputBar:FindFirstChild("PrefixLabel")
                    local wBox = inputBar:FindFirstChild("WordBox")
                    local pText = (pLbl and pLbl:IsA("TextLabel")) and pLbl.Text or ""
                    local wText = (wBox and wBox:IsA("TextBox")) and wBox.Text or ""
                    pText = pText:gsub("<[^>]*>", ""):gsub("%s+", "")
                    wText = wText:gsub("<[^>]*>", ""):gsub("%s+", "")
                    if #(pText .. wText) >= 3 then table.insert(history, { text = (pText .. wText), owner = "me", path = "Custom_Prefix" }) end
                end
                local feedback = matchNode:FindFirstChild("Feedback")
                if feedback and feedback:IsA("TextLabel") and feedback.Text ~= "" then 
                    table.insert(history, { text = feedback.Text, owner = "other", path = feedback:GetFullName() }) 
                end
            end
        end)
    end
    table.sort(candidates, function(a, b) return a.size > b.size end)
    
    return candidates, history, myTurn
end

TweenService:Create(island, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 0, 16) }):Play()

task.spawn(function()
    local wasMyTurn = false

    while true do
        task.wait(CFG.SCAN_RATE)
        local results, history, isMyTurn = scanAll()
        local top = results[1]
        local usedChanged = updateUsedWords(history)
        local wordChanged = false

        if top and top.text ~= lastWord then
            lastWord = top.text
            refreshSuggestions(top.text)
            wordChanged = true
        elseif not top and lastWord ~= "__none__" then
            lastWord, currentSuggestions, currentIndex = "__none__", {}, 1
            showCurrent()
            wordChanged = true
        elseif usedChanged and lastWord ~= "" and lastWord ~= "__none__" then
            refreshSuggestions(lastWord)
        end

        if isAutoFillON and isMyTurn and currentSuggestions[1] then
            if (not wasMyTurn) or wordChanged then
                checkAutoTrigger(lastWord)
            end
        end

        wasMyTurn = isMyTurn
    end
end)
