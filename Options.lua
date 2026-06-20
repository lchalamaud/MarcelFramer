local addonName, ns = ...

-- ============================================================================
--  Options.lua — Fenetre de configuration des couleurs par classe (/mf config)
--  API pure : frame maison + ColorPickerFrame Blizzard. Chaque teinte est
--  editable via une pastille (color picker) OU un champ hexa. Sauvegarde dans
--  MarcelFramerDB ; apercu live via ns:RefreshAll().
-- ============================================================================

ns.Options = {}

local CLASS_ORDER = {
    "WARRIOR", "PALADIN", "DEATHKNIGHT", "MONK", "PRIEST", "DRUID",
    "SHAMAN", "MAGE", "WARLOCK", "HUNTER", "ROGUE",
}

-- Copie profonde des defauts (pour /reset), prise avant toute fusion DB
local DEFAULTS = {}
for class, sides in pairs(ns.classBarColors or {}) do
    DEFAULTS[class] = {
        left  = { sides.left[1],  sides.left[2],  sides.left[3] },
        right = { sides.right[1], sides.right[2], sides.right[3] },
    }
end

local frame
local swatches = {}   -- class -> { left, right, leftHex, rightHex, label }

-- Conversions hexa <-> rgb (0-1)
local function RGBToHex(r, g, b)
    return string.format("%02X%02X%02X",
        math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local function HexToRGB(hex)
    hex = (hex or ""):gsub("#", ""):gsub("%s", "")
    if #hex ~= 6 then return nil end
    local r = tonumber(hex:sub(1, 2), 16)
    local g = tonumber(hex:sub(3, 4), 16)
    local b = tonumber(hex:sub(5, 6), 16)
    if not (r and g and b) then return nil end
    return r / 255, g / 255, b / 255
end

-- Recharge l'affichage (pastilles, hexa, label) depuis ns.classBarColors
local function refreshSwatches()
    for class, row in pairs(swatches) do
        local c = ns.classBarColors[class]
        if c then
            row.left.tex:SetColorTexture(c.left[1], c.left[2], c.left[3])
            row.right.tex:SetColorTexture(c.right[1], c.right[2], c.right[3])
            row.label:SetTextColor(c.right[1], c.right[2], c.right[3])
            if not row.leftHex:HasFocus() then
                row.leftHex:SetText(RGBToHex(c.left[1], c.left[2], c.left[3]))
            end
            if not row.rightHex:HasFocus() then
                row.rightHex:SetText(RGBToHex(c.right[1], c.right[2], c.right[3]))
            end
        end
    end
end

-- Ecrit une teinte (runtime + DB) puis rafraichit tout
local function saveColor(class, side, r, g, b)
    local col = ns.classBarColors[class][side]
    col[1], col[2], col[3] = r, g, b
    MarcelFramerDB.classBarColors[class] = MarcelFramerDB.classBarColors[class] or {}
    MarcelFramerDB.classBarColors[class][side] = { r, g, b }
    refreshSwatches()
    ns:RefreshAll()
end

-- Selecteur de couleur Blizzard (API moderne, repli ancien systeme)
local function openPicker(r, g, b, apply)
    local function swatchFunc()
        apply(ColorPickerFrame:GetColorRGB())
    end
    if ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = r, g = g, b = b, hasOpacity = false,
            swatchFunc = swatchFunc,
            cancelFunc = function() apply(r, g, b) end,
        })
    else
        ColorPickerFrame.func       = swatchFunc
        ColorPickerFrame.cancelFunc = function() apply(r, g, b) end
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame:SetColorRGB(r, g, b)
        ColorPickerFrame:Hide()
        ColorPickerFrame:Show()
    end
end

local function makeSwatch(parent, class, side)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(24, 16)
    local border = b:CreateTexture(nil, "BACKGROUND")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetColorTexture(0, 0, 0, 1)
    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    b.tex = tex
    b:SetScript("OnEnter", function(s) s:SetAlpha(0.8) end)
    b:SetScript("OnLeave", function(s) s:SetAlpha(1) end)
    b:SetScript("OnClick", function()
        local col = ns.classBarColors[class] and ns.classBarColors[class][side]
        if not col then return end
        openPicker(col[1], col[2], col[3], function(nr, ng, nb)
            saveColor(class, side, nr, ng, nb)
        end)
    end)
    return b
end

local function makeHexBox(parent, class, side)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(58, 18)
    e:SetAutoFocus(false)
    e:SetMaxLetters(7)             -- tolere un '#' en plus des 6 chiffres
    e:SetFontObject("GameFontHighlightSmall")
    local function commit()
        local r, g, b = HexToRGB(e:GetText())
        if r then
            saveColor(class, side, r, g, b)
        else
            refreshSwatches()      -- entree invalide : on restaure l'affichage
        end
        e:ClearFocus()
    end
    e:SetScript("OnEnterPressed", commit)
    e:SetScript("OnEditFocusLost", commit)
    e:SetScript("OnEscapePressed", function(self) refreshSwatches(); self:ClearFocus() end)
    return e
end

local function resetAll()
    wipe(MarcelFramerDB.classBarColors)
    for class, def in pairs(DEFAULTS) do
        local entry = ns.classBarColors[class] or {}
        entry.left  = { def.left[1],  def.left[2],  def.left[3] }
        entry.right = { def.right[1], def.right[2], def.right[3] }
        ns.classBarColors[class] = entry
    end
    refreshSwatches()
    ns:RefreshAll()
end

local function build()
    frame = CreateFrame("Frame", "MarcelFramerOptions", UIParent, "BackdropTemplate")
    frame:SetSize(420, 426)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetBackdrop({
        bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 16,
        insets = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    tinsert(UISpecialFrames, "MarcelFramerOptions")   -- fermeture avec Echap

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -14)
    title:SetText("MarcelFramer \226\128\148 Couleurs par classe")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local cb = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    cb:SetSize(24, 24)
    cb:SetPoint("TOPLEFT", 14, -40)
    cb:SetChecked(ns.config.classGradient ~= false)
    local cblbl = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cblbl:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cblbl:SetText("Vie en degrade (sinon couleur unie = teinte de droite)")
    cb:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or false
        ns.config.classGradient = on
        MarcelFramerDB.classGradient = on
        ns:RefreshAll()
    end)

    -- colonnes : pastille a x=150 / 285, champ hexa juste a droite
    local hF = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hF:SetPoint("TOPLEFT", 150, -72); hF:SetText("Fonce")
    local hC = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hC:SetPoint("TOPLEFT", 285, -72); hC:SetText("Clair")

    local y = -88
    for _, class in ipairs(CLASS_ORDER) do
        if ns.classBarColors[class] then
            local lbl = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            lbl:SetPoint("TOPLEFT", 18, y)
            lbl:SetText((LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class)

            local lSw  = makeSwatch(frame, class, "left")
            lSw:SetPoint("TOPLEFT", 150, y + 1)
            local lHex = makeHexBox(frame, class, "left")
            lHex:SetPoint("LEFT", lSw, "RIGHT", 8, 0)

            local rSw  = makeSwatch(frame, class, "right")
            rSw:SetPoint("TOPLEFT", 285, y + 1)
            local rHex = makeHexBox(frame, class, "right")
            rHex:SetPoint("LEFT", rSw, "RIGHT", 8, 0)

            swatches[class] = { left = lSw, right = rSw, leftHex = lHex, rightHex = rHex, label = lbl }
            y = y - 26
        end
    end

    local reset = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    reset:SetSize(130, 22)
    reset:SetPoint("BOTTOM", 0, 14)
    reset:SetText("Reinitialiser")
    reset:SetScript("OnClick", resetAll)

    refreshSwatches()
end

function ns.Options.Toggle()
    if not frame then build() end
    if frame:IsShown() then
        frame:Hide()
    else
        refreshSwatches()
        frame:Show()
    end
end
