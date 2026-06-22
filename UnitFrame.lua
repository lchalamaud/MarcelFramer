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
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        Elements.UpdateCombat(self)
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
    -- Barre de cast : reservee a player / target. On la cree toujours pour ces
    -- deux cadres (meme si desactivee) afin que la bascule via /mf config soit
    -- live, sans /reload. Son etat actif derive de cfg.showCastBar.
    if key == "player" or key == "target" then Elements.CreateCastBar(frame) end
    Elements.CreateAuras(frame)
    Elements.EnableTooltip(frame)
    ns:ApplyPosition(frame, key)
    ns:RegisterFrame(key, frame)

    -- Evenements
    Elements.RegisterUnitEvents(frame)
    frame:SetScript("OnEvent", OnEvent)
    frame:SetScript("OnShow", OnShow)

    if key == "player" then
        frame:RegisterEvent("PLAYER_ENTERING_WORLD")
        frame:RegisterEvent("PLAYER_REGEN_DISABLED")
        frame:RegisterEvent("PLAYER_REGEN_ENABLED")
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
    -- La police custom se charge de maniere asynchrone sur ce client : on la
    -- re-applique apres un court delai pour rattraper les textes crees avant
    -- qu'elle soit prete (typiquement le 1er : le nom).
    if C_Timer and C_Timer.After then
        C_Timer.After(0.2, function() ns:RefreshFonts() end)
        C_Timer.After(1.0, function() ns:RefreshFonts() end)
    end
end
