local addonName = ...

local DEFAULTS = {
    point = { x = 500, y = 500 },
    scale = 1,
    fontSize = 16,
    rowSpacing = 4,
    fontPath = "Fonts\\FRIZQT__.TTF",
    unlocked = false,
    useClassColors = true,
    defaultColor = { r = 0.85, g = 0.95, b = 1 },
    drinkingColor = { r = 0.25, g = 0.85, b = 1 },
    deadColor = { r = 0.8, g = 0.2, b = 0.2 },
    classColors = {},
}

local FONT_OPTIONS = {}

local BUILTIN_FONT_CANDIDATES = {
    { name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
    { name = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
    { name = "Morpheus", path = "Fonts\\MORPHEUS.TTF" },
    { name = "Skurri", path = "Fonts\\skurri.ttf" },
    { name = "2002", path = "Fonts\\2002.TTF" },
    { name = "Accidental Presidency", path = "Fonts\\Accidental Presidency.ttf" },
    { name = "Action Man", path = "Fonts\\Action_Man.ttf" },
    { name = "Bazooka", path = "Fonts\\Bazooka.ttf" },
    { name = "Big Noodle Titling", path = "Fonts\\BigNoodleTitling.ttf" },
    { name = "Continuum", path = "Fonts\\Continuum_Medium.ttf" },
    { name = "Doris PP", path = "Fonts\\DORISPP.TTF" },
    { name = "Expressway", path = "Fonts\\Expressway.ttf" },
    { name = "Fritz", path = "Fonts\\Fritz Quadrata TT.ttf" },
    { name = "Prototype", path = "Fonts\\PROTOTYPE.ttf" },
    { name = "Roboto", path = "Fonts\\Roboto-Regular.ttf" },
}

local DRINKING_KEYWORDS = {
    "Drink",
    "Refreshment",
    "Conjured",
}

local DRINKING_SPELL_IDS = {
    [43183] = true, -- Drink
    [57073] = true, -- Drink
    [80167] = true, -- Drink
    [104270] = true, -- Drink
}

local trackedUnits = {}
local rows = {}
local configPanel
local sliderCounter = 0
local previewMode = nil

local PREVIEW_GROUPS = {
    party = {
        { name = "Holypriest", classToken = "PRIEST", manaPct = 88, drinking = false, dead = false },
        { name = "Rshammy", classToken = "SHAMAN", manaPct = 46, drinking = true, dead = false },
        { name = "Hpal", classToken = "PALADIN", manaPct = 12, drinking = false, dead = false },
    },
    raid = {
        { name = "Treebuddy", classToken = "DRUID", manaPct = 73, drinking = false, dead = false },
        { name = "Discangel", classToken = "PRIEST", manaPct = 52, drinking = false, dead = false },
        { name = "Hpal", classToken = "PALADIN", manaPct = 28, drinking = true, dead = false },
        { name = "Mistweave", classToken = "MONK", manaPct = 67, drinking = false, dead = false },
        { name = "Evokefriend", classToken = "EVOKER", manaPct = 94, drinking = false, dead = false },
        { name = "Dedhealz", classToken = "SHAMAN", manaPct = 0, drinking = false, dead = true },
    },
}

local frame = CreateFrame("Frame", "HMTMainFrame", UIParent)
frame:SetSize(220, 20)
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")

local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
title:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 6)
title:SetText("Healer Mana")

local moverTexture = frame:CreateTexture(nil, "BACKGROUND")
moverTexture:SetAllPoints(frame)
moverTexture:SetColorTexture(0, 0, 0, 0.12)

local function deepcopy(src)
    local out = {}
    for k, v in pairs(src) do
        if type(v) == "table" then
            out[k] = deepcopy(v)
        else
            out[k] = v
        end
    end
    return out
end

local function initDB()
    if type(HMTDB) ~= "table" then
        HMTDB = {}
    end

    for k, v in pairs(DEFAULTS) do
        if HMTDB[k] == nil then
            HMTDB[k] = type(v) == "table" and deepcopy(v) or v
        end
    end

    if not HMTDB.classColors or not next(HMTDB.classColors) then
        HMTDB.classColors = {}
        for classToken, color in pairs(RAID_CLASS_COLORS) do
            HMTDB.classColors[classToken] = { r = color.r, g = color.g, b = color.b }
        end
    end
end

local function colorForClass(classToken)
    local color = HMTDB.classColors and HMTDB.classColors[classToken]
    if color then
        return color.r, color.g, color.b
    end

    local raidColor = RAID_CLASS_COLORS[classToken]
    if raidColor then
        return raidColor.r, raidColor.g, raidColor.b
    end

    local fallback = HMTDB.defaultColor
    return fallback.r, fallback.g, fallback.b
end

local function isUnitDrinking(unit)
    if not UnitExists(unit) then
        return false
    end

    local i = 1
    while true do
        local name, _, _, _, _, _, _, _, _, spellID = UnitBuff(unit, i)
        if not name then
            break
        end

        if DRINKING_SPELL_IDS[spellID] then
            return true
        end

        for _, keyword in ipairs(DRINKING_KEYWORDS) do
            if string.find(name, keyword) then
                return true
            end
        end

        i = i + 1
    end

    return false
end

local function getGroupUnits()
    wipe(trackedUnits)

    local count = GetNumGroupMembers()
    if count == 0 then
        if UnitGroupRolesAssigned("player") == "HEALER" then
            trackedUnits[#trackedUnits + 1] = "player"
        end
        return
    end

    local unitPrefix = IsInRaid() and "raid" or "party"
    local limit = IsInRaid() and count or (count - 1)

    for i = 1, limit do
        local unit = unitPrefix .. i
        if UnitExists(unit) and UnitGroupRolesAssigned(unit) == "HEALER" then
            trackedUnits[#trackedUnits + 1] = unit
        end
    end

    if not IsInRaid() and UnitGroupRolesAssigned("player") == "HEALER" then
        trackedUnits[#trackedUnits + 1] = "player"
    end
end

local function ensureRows(count)
    while #rows < count do
        local row = frame:CreateFontString(nil, "OVERLAY")
        rows[#rows + 1] = row
    end
end

local function setupFontOptions()
    local seen = {}

    local function addOption(name, path)
        if not path or path == "" or seen[path] then
            return
        end
        seen[path] = true
        FONT_OPTIONS[#FONT_OPTIONS + 1] = {
            name = name or path,
            path = path,
        }
    end

    for _, option in ipairs(BUILTIN_FONT_CANDIDATES) do
        addOption(option.name, option.path)
    end

    local fallbackFonts = {
        { name = "Standard", path = STANDARD_TEXT_FONT },
        { name = "Damage", path = DAMAGE_TEXT_FONT },
        { name = "Quest", path = UNIT_NAME_FONT },
    }

    for _, option in ipairs(fallbackFonts) do
        addOption(option.name, option.path)
    end

    addOption("Current font", HMTDB and HMTDB.fontPath)

    table.sort(FONT_OPTIONS, function(a, b)
        return a.name < b.name
    end)
end

local function applyLayout()
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", HMTDB.point.x, HMTDB.point.y)
    frame:SetScale(HMTDB.scale)

    moverTexture:SetShown(HMTDB.unlocked)
    title:SetShown(HMTDB.unlocked)

    for _, row in ipairs(rows) do
        row:SetFont(HMTDB.fontPath, HMTDB.fontSize, "OUTLINE")
        row:SetJustifyH("LEFT")
    end
end

local function updateDisplay()
    if previewMode then
        local previewRows = PREVIEW_GROUPS[previewMode] or {}
        ensureRows(#previewRows)

        local y = 0
        local maxWidth = 0
        for i, entry in ipairs(previewRows) do
            local row = rows[i]
            local text

            if entry.dead then
                text = string.format("Dead: %s", entry.name)
                row:SetTextColor(HMTDB.deadColor.r, HMTDB.deadColor.g, HMTDB.deadColor.b)
            else
                text = string.format("%s - %d%%", entry.name, entry.manaPct)
                if entry.drinking then
                    text = text .. " (Drinking)"
                    row:SetTextColor(HMTDB.drinkingColor.r, HMTDB.drinkingColor.g, HMTDB.drinkingColor.b)
                elseif HMTDB.useClassColors and entry.classToken then
                    row:SetTextColor(colorForClass(entry.classToken))
                else
                    row:SetTextColor(HMTDB.defaultColor.r, HMTDB.defaultColor.g, HMTDB.defaultColor.b)
                end
            end

            row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, y)
            row:SetText(text)
            row:Show()

            y = y - (HMTDB.fontSize + HMTDB.rowSpacing)
            maxWidth = math.max(maxWidth, row:GetStringWidth())
        end

        for i = #previewRows + 1, #rows do
            rows[i]:Hide()
        end

        frame:SetSize(math.max(120, maxWidth + 8), math.max(20, -y))
        return
    end

    getGroupUnits()
    ensureRows(#trackedUnits)

    local y = 0
    local maxWidth = 0
    for i, unit in ipairs(trackedUnits) do
        local row = rows[i]
        local classToken = select(2, UnitClass(unit))
        local name = GetUnitName(unit, true) or unit
        local isDead = UnitIsDeadOrGhost(unit)
        local drinking = isUnitDrinking(unit)

        local text
        if isDead then
            text = string.format("Dead: %s", name)
            row:SetTextColor(HMTDB.deadColor.r, HMTDB.deadColor.g, HMTDB.deadColor.b)
        else
            local mana = UnitPower(unit, 0)
            local maxMana = UnitPowerMax(unit, 0)
            local percent = maxMana > 0 and math.floor((mana / maxMana) * 100 + 0.5) or 0
            text = string.format("%s - %d%%", name, percent)

            if drinking then
                text = text .. " (Drinking)"
                row:SetTextColor(HMTDB.drinkingColor.r, HMTDB.drinkingColor.g, HMTDB.drinkingColor.b)
            elseif HMTDB.useClassColors and classToken then
                row:SetTextColor(colorForClass(classToken))
            else
                row:SetTextColor(HMTDB.defaultColor.r, HMTDB.defaultColor.g, HMTDB.defaultColor.b)
            end
        end

        row:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, y)
        row:SetText(text)
        row:Show()

        y = y - (HMTDB.fontSize + HMTDB.rowSpacing)
        maxWidth = math.max(maxWidth, row:GetStringWidth())
    end

    for i = #trackedUnits + 1, #rows do
        rows[i]:Hide()
    end

    frame:SetSize(math.max(120, maxWidth + 8), math.max(20, -y))
end

frame:SetScript("OnDragStart", function(self)
    if HMTDB and HMTDB.unlocked then
        self:StartMoving()
    end
end)

frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local left, top = self:GetLeft(), self:GetTop()
    if left and top then
        HMTDB.point.x = left
        HMTDB.point.y = top
    end
end)

local function createSlider(parent, text, minVal, maxVal, step, getValue, setValue, y)
    sliderCounter = sliderCounter + 1
    local sliderName = "HMTSlider" .. sliderCounter
    local slider = CreateFrame("Slider", sliderName, parent, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", 20, y)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider:SetWidth(220)

    _G[sliderName .. "Low"]:SetText(tostring(minVal))
    _G[sliderName .. "High"]:SetText(tostring(maxVal))
    _G[sliderName .. "Text"]:SetText(text)

    slider:SetScript("OnShow", function(self)
        self:SetValue(getValue())
    end)

    slider:SetScript("OnValueChanged", function(_, value)
        setValue(value)
        updateDisplay()
    end)

    return slider
end

local function createCheckbox(parent, text, getValue, setValue, x, y)
    local cb = CreateFrame("CheckButton", nil, parent, "ChatConfigCheckButtonTemplate")
    cb:SetPoint("TOPLEFT", x, y)
    cb.Text:SetText(text)
    cb:SetScript("OnShow", function(self)
        self:SetChecked(getValue())
    end)
    cb:SetScript("OnClick", function(self)
        setValue(self:GetChecked())
        applyLayout()
        updateDisplay()
    end)
    return cb
end

local function openColorPicker(initial, onColor)
    local previous = { r = initial.r, g = initial.g, b = initial.b }

    ColorPickerFrame:Hide()
    ColorPickerFrame.func = function()
        local r, g, b = ColorPickerFrame:GetColorRGB()
        onColor(r, g, b)
        updateDisplay()
    end
    ColorPickerFrame.cancelFunc = function()
        onColor(previous.r, previous.g, previous.b)
        updateDisplay()
    end

    ColorPickerFrame:SetColorRGB(initial.r, initial.g, initial.b)
    ColorPickerFrame:Show()
end

local function createColorButton(parent, label, getColor, setColor, x, y)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetPoint("TOPLEFT", x, y)
    btn:SetSize(150, 22)
    btn:SetText(label)

    local swatch = btn:CreateTexture(nil, "ARTWORK")
    swatch:SetSize(16, 16)
    swatch:SetPoint("RIGHT", btn, "RIGHT", -6, 0)

    btn:SetScript("OnShow", function()
        local c = getColor()
        swatch:SetColorTexture(c.r, c.g, c.b)
    end)

    btn:SetScript("OnClick", function()
        local c = getColor()
        openColorPicker(c, function(r, g, b)
            setColor(r, g, b)
            swatch:SetColorTexture(r, g, b)
        end)
    end)

    return btn
end

local function createClassColorButtons(parent)
    local classes = {}
    for classToken in pairs(RAID_CLASS_COLORS) do
        classes[#classes + 1] = classToken
    end
    table.sort(classes)

    local startY = -560
    local col, row = 0, 0

    for _, classToken in ipairs(classes) do
        local x = 20 + (col * 180)
        local y = startY - (row * 28)

        local className = LOCALIZED_CLASS_NAMES_MALE[classToken] or classToken
        createColorButton(
            parent,
            className,
            function()
                return HMTDB.classColors[classToken]
            end,
            function(r, g, b)
                HMTDB.classColors[classToken].r = r
                HMTDB.classColors[classToken].g = g
                HMTDB.classColors[classToken].b = b
            end,
            x,
            y
        )

        col = col + 1
        if col == 2 then
            col = 0
            row = row + 1
        end
    end
end

local function createConfigPanel()
    if configPanel then
        return
    end

    configPanel = CreateFrame("Frame", "HMTConfigPanel", UIParent, "BasicFrameTemplateWithInset")
    configPanel:SetSize(460, 660)
    configPanel:SetResizable(true)
    configPanel:SetMinResize(420, 520)
    configPanel:SetMaxResize(700, 900)
    configPanel:SetPoint("CENTER")
    configPanel:SetFrameStrata("DIALOG")
    configPanel:Hide()

    configPanel.title = configPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    configPanel.title:SetPoint("LEFT", configPanel.TitleBg, "LEFT", 8, 0)
    configPanel.title:SetText("Healer Mana Tracker")

    local subtitle = configPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", 20, -36)
    subtitle:SetText("Appearance + layout")

    local resizeHandle = CreateFrame("Button", nil, configPanel)
    resizeHandle:SetPoint("BOTTOMRIGHT", -6, 6)
    resizeHandle:SetSize(16, 16)
    resizeHandle:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeHandle:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeHandle:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeHandle:SetScript("OnMouseDown", function()
        configPanel:StartSizing("BOTTOMRIGHT")
    end)
    resizeHandle:SetScript("OnMouseUp", function()
        configPanel:StopMovingOrSizing()
    end)

    createCheckbox(configPanel, "Unlock tracker (drag to move)", function()
        return HMTDB.unlocked
    end, function(v)
        HMTDB.unlocked = v
    end, 20, -58)

    createCheckbox(configPanel, "Use class colors", function()
        return HMTDB.useClassColors
    end, function(v)
        HMTDB.useClassColors = v
    end, 20, -86)

    local previewButton = CreateFrame("Button", nil, configPanel, "UIPanelButtonTemplate")
    previewButton:SetPoint("TOPLEFT", 20, -118)
    previewButton:SetSize(200, 24)

    local function syncPreviewButtonText()
        if previewMode == "party" then
            previewButton:SetText("Preview: Party")
        elseif previewMode == "raid" then
            previewButton:SetText("Preview: Raid")
        else
            previewButton:SetText("Preview: Off")
        end
    end

    previewButton:SetScript("OnClick", function()
        if previewMode == nil then
            previewMode = "party"
        elseif previewMode == "party" then
            previewMode = "raid"
        else
            previewMode = nil
        end

        syncPreviewButtonText()
        updateDisplay()
    end)

    createSlider(configPanel, "Scale", 0.6, 2.0, 0.05, function()
        return HMTDB.scale
    end, function(v)
        HMTDB.scale = v
        applyLayout()
    end, -160)

    createSlider(configPanel, "Font size", 8, 32, 1, function()
        return HMTDB.fontSize
    end, function(v)
        HMTDB.fontSize = v
    end, -220)

    createSlider(configPanel, "Row spacing", 0, 16, 1, function()
        return HMTDB.rowSpacing
    end, function(v)
        HMTDB.rowSpacing = v
    end, -280)

    createColorButton(configPanel, "Default text color", function()
        return HMTDB.defaultColor
    end, function(r, g, b)
        HMTDB.defaultColor = { r = r, g = g, b = b }
    end, 20, -320)

    createColorButton(configPanel, "Drinking color", function()
        return HMTDB.drinkingColor
    end, function(r, g, b)
        HMTDB.drinkingColor = { r = r, g = g, b = b }
    end, 20, -350)

    createColorButton(configPanel, "Dead color", function()
        return HMTDB.deadColor
    end, function(r, g, b)
        HMTDB.deadColor = { r = r, g = g, b = b }
    end, 20, -380)

    local fontLabel = configPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fontLabel:SetPoint("TOPLEFT", 230, -324)
    fontLabel:SetText("Font")

    local fontDrop = CreateFrame("Frame", "HMTFontDropdown", configPanel, "UIDropDownMenuTemplate")
    fontDrop:SetPoint("TOPLEFT", 200, -344)

    UIDropDownMenu_Initialize(fontDrop, function(self, level)
        for _, option in ipairs(FONT_OPTIONS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = option.name
            info.checked = HMTDB.fontPath == option.path
            info.func = function()
                HMTDB.fontPath = option.path
                UIDropDownMenu_SetSelectedName(fontDrop, option.name)
                updateDisplay()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)

    local function syncDropdown()
        for _, option in ipairs(FONT_OPTIONS) do
            if option.path == HMTDB.fontPath then
                UIDropDownMenu_SetSelectedName(fontDrop, option.name)
                return
            end
        end
        UIDropDownMenu_SetSelectedName(fontDrop, FONT_OPTIONS[1].name)
    end

    configPanel:SetScript("OnShow", syncDropdown)

    local xSlider = createSlider(configPanel, "X position", 0, 2000, 1, function()
        return HMTDB.point.x
    end, function(v)
        HMTDB.point.x = v
        applyLayout()
    end, -450)

    local ySlider = createSlider(configPanel, "Y position", 0, 2000, 1, function()
        return HMTDB.point.y
    end, function(v)
        HMTDB.point.y = v
        applyLayout()
    end, -520)

    configPanel:SetScript("OnShow", function()
        syncPreviewButtonText()
        syncDropdown()
        xSlider:SetValue(HMTDB.point.x)
        ySlider:SetValue(HMTDB.point.y)
    end)

    createClassColorButtons(configPanel)
end

SLASH_HMT1 = "/hmt"
SLASH_HMT2 = "/healermana"

local function printHelp()
    print("HealerManaTracker commands:")
    print("  /hmt - Open/close the settings window")
    print("  /hmt unlock - Unlock tracker so you can drag it")
    print("  /hmt lock - Lock tracker in place")
    print("  /hmt help - Show this help text")
end

SlashCmdList.HMT = function(msg)
    msg = string.lower((msg or ""):gsub("^%s+", ""))

    if msg == "help" or msg == "?" then
        printHelp()
        return
    end

    if msg == "unlock" then
        HMTDB.unlocked = true
        applyLayout()
        print("HealerManaTracker: tracker unlocked.")
        return
    end

    if msg == "lock" then
        HMTDB.unlocked = false
        applyLayout()
        print("HealerManaTracker: tracker locked.")
        return
    end

    createConfigPanel()
    if configPanel:IsShown() then
        configPanel:Hide()
    else
        configPanel:Show()
    end

    if msg ~= "" then
        print(string.format("HealerManaTracker: unknown command '%s'.", msg))
        printHelp()
    end
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("GROUP_ROSTER_UPDATE")
frame:RegisterEvent("PLAYER_ROLES_ASSIGNED")
frame:RegisterEvent("UNIT_POWER_UPDATE")
frame:RegisterEvent("UNIT_AURA")
frame:RegisterEvent("UNIT_FLAGS")

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        initDB()
        setupFontOptions()
        applyLayout()
        updateDisplay()
        print("HealerManaTracker loaded. Type /hmt for options.")
        return
    end

    if not HMTDB then
        return
    end

    if event == "UNIT_POWER_UPDATE" or event == "UNIT_AURA" or event == "UNIT_FLAGS" then
        if arg1 and not UnitInParty(arg1) and not UnitInRaid(arg1) and arg1 ~= "player" then
            return
        end
    end

    updateDisplay()
end)
