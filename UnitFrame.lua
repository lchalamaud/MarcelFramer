local addonName, ns = ...

-- ============================================================================
--  UnitFrame.lua — Cadres simples : player / target / targettarget / pet
-- ============================================================================

local Elements = ns.Elements
ns.UnitFrame = {}

-- targettarget n'a pas d'evenement fiable : on poll en OnUpdate throttle (~0,25s)
local function TargetOfTargetOnUpdate(self, elapsed)
    self.elapsed = (self.elapsed or 0) + elapsed
    if self.elapsed < 0.25 then return end
    self.elapsed = 0
    if UnitExists(self.unit) then
        Elements.FullUpdate(self)
    end
end

-- OnEvent des cadres simples : gere les "declencheurs" puis delegue a Elements
local function OnEvent(self, event, arg1)
    if event == "PLAYER_ENTERING_WORLD" then
        Elements.FullUpdate(self)
    elseif event == "PLAYER_TARGET_CHANGED" then
        Elements.FullUpdate(self)
    elseif event == "UNIT_PET" then
        Elements.FullUpdate(self)
    elseif event == "UNIT_TARGET" then
        Elements.FullUpdate(self)
    else
        Elements.OnEvent(self, event, arg1)
    end
end

local function OnShow(self)
    Elements.FullUpdate(self)
end

local function CreateUnit(unit, key)
    local cfg = ns.config[key]
    if not cfg or cfg.enabled == false then return end

    local frameName = "MarcelFramer" .. key:gsub("^%l", string.upper)
    local frame = CreateFrame("Button", frameName, UIParent, "SecureUnitButtonTemplate")
    frame.unit = unit
    frame.unitType = key
    frame.config = cfg
    frame:SetSize(cfg.width, cfg.height)
    frame:SetScale(cfg.scale or 1)

    -- Securise : ciblage clic gauche / menu clic droit, fonctionne en combat
    frame:SetAttribute("unit", unit)
    frame:RegisterForClicks("AnyUp")
    frame:SetAttribute("*type1", "target")
    frame:SetAttribute("*type2", "togglemenu")   -- menu d'unite Blizzard natif (securise, OK combat)

    Elements.BuildVisuals(frame)
    if cfg.showCastBar then Elements.CreateCastBar(frame) end
    Elements.CreateAuras(frame)
    ns:ApplyPosition(frame, key)
    ns:RegisterFrame(key, frame, false)

    -- Evenements
    Elements.RegisterUnitEvents(frame)
    frame:SetScript("OnEvent", OnEvent)
    frame:SetScript("OnShow", OnShow)

    if key == "player" then
        frame:RegisterEvent("PLAYER_ENTERING_WORLD")
        frame:Show()                       -- toujours visible
    elseif key == "target" then
        frame:RegisterEvent("PLAYER_TARGET_CHANGED")
        RegisterUnitWatch(frame)           -- apparait/disparait selon l'existence
    elseif key == "targettarget" then
        frame:SetScript("OnUpdate", TargetOfTargetOnUpdate)
        RegisterUnitWatch(frame)
    elseif key == "pet" then
        frame:RegisterEvent("UNIT_PET")
        RegisterUnitWatch(frame)
    end

    Elements.FullUpdate(frame)
    return frame
end

function ns.UnitFrame.CreateAll()
    CreateUnit("player", "player")
    CreateUnit("target", "target")
    CreateUnit("targettarget", "targettarget")
    CreateUnit("pet", "pet")
end
