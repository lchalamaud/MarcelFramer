local addonName, ns = ...

-- ============================================================================
--  GroupFrames.lua — Cadres de groupe (party) et de raid
--  Via SecureGroupHeaderTemplate : chaque bouton est cree par le header puis
--  configure par initialConfigFunction en reutilisant Elements.lua.
-- ============================================================================

local Elements = ns.Elements
ns.GroupFrames = {}

-- Le header (re)assigne dynamiquement l'attribut "unit" de chaque bouton :
-- on suit ces changements pour rafraichir le bouton.
local function ChildOnAttributeChanged(self, name, value)
    if name == "unit" then
        self.unit = value
        if value and UnitExists(value) then
            Elements.FullUpdate(self)
        end
    end
end

local function ChildOnShow(self)
    if self.unit then Elements.FullUpdate(self) end
end

-- Construit chaque bouton du header (contexte non securise, OK au chargement)
local function InitButton(button)
    local header = button:GetParent()
    local key = header.unitType
    local cfg = ns.config[key]

    button.unitType = key
    button.config = cfg

    -- Taille appliquee par le header securise via les attributs initial-*
    -- (ne pas appeler SetWidth/SetHeight directement sur un bouton securise)
    button:SetAttribute("initial-width", cfg.width)
    button:SetAttribute("initial-height", cfg.height)
    button:SetAttribute("initial-scale", cfg.scale or 1)

    -- Securise : clic gauche cible, clic droit menu
    button:RegisterForClicks("AnyUp")
    button:SetAttribute("*type1", "target")
    button:SetAttribute("*type2", "togglemenu")   -- menu d'unite Blizzard natif (securise, OK combat)

    Elements.BuildVisuals(button)
    Elements.CreateAuras(button)
    Elements.RegisterUnitEvents(button)

    button:SetScript("OnEvent", Elements.OnEvent)
    button:SetScript("OnAttributeChanged", ChildOnAttributeChanged)
    button:SetScript("OnShow", ChildOnShow)

    button.unit = button:GetAttribute("unit")
end

local function CreateHeader(key)
    local cfg = ns.config[key]
    if not cfg or cfg.enabled == false then return end

    local headerName = "MarcelFramer" .. key:gsub("^%l", string.upper) .. "Header"
    local header = CreateFrame("Frame", headerName, UIParent, "SecureGroupHeaderTemplate")
    header.unitType = key

    header:SetAttribute("template", "SecureUnitButtonTemplate")
    header:SetAttribute("initial-unitWatch", true)
    header.initialConfigFunction = InitButton
    header:UnregisterEvent("UNIT_NAME_UPDATE")

    -- Sens de croissance dans une colonne
    local attribPoint = cfg.attribPoint or "TOP"
    local spacing = cfg.spacing or 6
    local xOff, yOff = 0, 0
    if attribPoint == "TOP" then
        yOff = -spacing
    elseif attribPoint == "BOTTOM" then
        yOff = spacing
    elseif attribPoint == "LEFT" then
        xOff = spacing
    elseif attribPoint == "RIGHT" then
        xOff = -spacing
    end
    header:SetAttribute("point", attribPoint)
    header:SetAttribute("xOffset", xOff)
    header:SetAttribute("yOffset", yOff)

    if key == "party" then
        header:SetAttribute("showParty", true)
        header:SetAttribute("showPlayer", cfg.showPlayer and true or false)
        header:SetAttribute("showRaid", false)
        header:SetAttribute("showSolo", false)
    else -- raid
        header:SetAttribute("showRaid", true)
        header:SetAttribute("showParty", false)
        header:SetAttribute("showPlayer", true)
        header:SetAttribute("showSolo", false)
        header:SetAttribute("groupFilter", cfg.groupFilter or "1,2,3,4,5,6,7,8")
        header:SetAttribute("groupBy", "GROUP")
        header:SetAttribute("groupingOrder", "1,2,3,4,5,6,7,8")
        header:SetAttribute("maxColumns", cfg.maxColumns or 8)
        header:SetAttribute("unitsPerColumn", cfg.unitsPerColumn or 5)
        header:SetAttribute("columnSpacing", cfg.columnSpacing or 6)
        header:SetAttribute("columnAnchorPoint", cfg.columnAnchorPoint or "LEFT")
    end

    ns:ApplyPosition(header, key)
    ns:RegisterFrame(key, header, true)
    header:Show()
    return header
end

function ns.GroupFrames.CreateAll()
    CreateHeader("party")
    CreateHeader("raid")
end
