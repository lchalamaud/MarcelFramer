local addonName, ns = ...

-- ============================================================================
--  Core.lua — Initialisation, masquage Blizzard, slash, movers, menu d'unite
-- ============================================================================

local noop = function() end
ns.noop = noop

ns.registry = {}   -- key -> { frame = <frame> }
ns.movers   = {}   -- key -> mover overlay frame
ns.unlocked = false

local function MF_Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffMarcelFramer|r : " .. msg)
end
ns.Print = MF_Print

-- ----------------------------------------------------------------------------
--  Positions (SavedVariables + defauts de Config)
-- ----------------------------------------------------------------------------
function ns:GetPosition(key)
    local saved = MarcelFramerDB and MarcelFramerDB.positions and MarcelFramerDB.positions[key]
    if saved then return saved end
    local cfg = ns.config[key]
    return cfg and cfg.point
end

function ns:ApplyPosition(frame, key)
    local p = ns:GetPosition(key)
    if not p then return end
    frame:ClearAllPoints()
    frame:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x or 0, p.y or 0)
end

-- ----------------------------------------------------------------------------
--  Movers (overlays de deplacement, /mf unlock)
-- ----------------------------------------------------------------------------
local function MoverDragStart(self)
    if InCombatLockdown() then return end
    self:StartMoving()
end

local function MoverDragStop(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint()
    x, y = math.floor(x + 0.5), math.floor(y + 0.5)
    MarcelFramerDB.positions[self.mfKey] = { point = point, relPoint = relPoint, x = x, y = y }
    ns:ApplyPosition(self.mfTarget, self.mfKey)
    self:ClearAllPoints()
    self:SetPoint(point, UIParent, relPoint, x, y)
end

local function CreateMover(key, target)
    local cfg = ns.config[key]

    local mover = CreateFrame("Frame", nil, UIParent)
    mover:SetSize(cfg.width, cfg.height)
    mover:SetFrameStrata("DIALOG")
    mover:SetMovable(true)
    mover:SetClampedToScreen(true)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    mover.mfKey = key
    mover.mfTarget = target

    local bg = mover:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.5, 1, 0.40)

    local label = mover:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER")
    label:SetText(key)

    mover:SetScript("OnDragStart", MoverDragStart)
    mover:SetScript("OnDragStop", MoverDragStop)
    mover:Hide()

    ns.movers[key] = mover
end

function ns:RegisterFrame(key, frame)
    frame.mfKey = key
    ns.registry[key] = { frame = frame }
    CreateMover(key, frame)
end

function ns:Unlock()
    if InCombatLockdown() then MF_Print("impossible de deverrouiller en combat."); return end
    ns.unlocked = true
    for key, mover in pairs(ns.movers) do
        local p = ns:GetPosition(key)
        mover:ClearAllPoints()
        mover:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x or 0, p.y or 0)
        mover:Show()
    end
    MF_Print("cadres deverrouilles. Glissez-les, puis |cffffff00/mf lock|r.")
end

function ns:Lock()
    ns.unlocked = false
    for _, mover in pairs(ns.movers) do mover:Hide() end
    MF_Print("cadres verrouilles.")
end

function ns:Reset()
    if InCombatLockdown() then MF_Print("impossible de reinitialiser en combat."); return end
    MarcelFramerDB.positions = {}
    for key, data in pairs(ns.registry) do
        ns:ApplyPosition(data.frame, key)
    end
    if ns.unlocked then ns:Unlock() end
    MF_Print("positions reinitialisees.")
end

-- Menu contextuel d'unite : gere directement par l'action securisee
-- "togglemenu" (*type2) des boutons SecureUnitButtonTemplate. Pas de code
-- custom : c'est le menu Blizzard natif, fonctionnel en combat.

-- ----------------------------------------------------------------------------
--  Masquage des cadres Blizzard
-- ----------------------------------------------------------------------------
local function killFrame(frame)
    if not frame then return end
    frame:UnregisterAllEvents()
    frame.Show = noop
    frame:Hide()
end

function ns:HideBlizzard()
    if ns.config.hideBlizzard == false then return end

    -- Joueur (on conserve les events de vehicule pour ne pas casser l'UI montures/vehicules)
    killFrame(PlayerFrame)
    if PlayerFrame then
        PlayerFrame:RegisterEvent("UNIT_ENTERING_VEHICLE")
        PlayerFrame:RegisterEvent("UNIT_ENTERED_VEHICLE")
        PlayerFrame:RegisterEvent("UNIT_EXITING_VEHICLE")
        PlayerFrame:RegisterEvent("UNIT_EXITED_VEHICLE")
    end
    if PlayerFrameHealthBar then PlayerFrameHealthBar:UnregisterAllEvents() end
    if PlayerFrameManaBar then PlayerFrameManaBar:UnregisterAllEvents() end

    -- Cible (+ cible de la cible Blizzard)
    killFrame(TargetFrame)
    if TargetFrameHealthBar then TargetFrameHealthBar:UnregisterAllEvents() end
    if TargetFrameManaBar then TargetFrameManaBar:UnregisterAllEvents() end
    if TargetFrameToT then killFrame(TargetFrameToT) end

    -- Familier
    killFrame(PetFrame)
    if PetFrameHealthBar then PetFrameHealthBar:UnregisterAllEvents() end
    if PetFrameManaBar then PetFrameManaBar:UnregisterAllEvents() end

    -- Focus
    killFrame(FocusFrame)
    if FocusFrameHealthBar then FocusFrameHealthBar:UnregisterAllEvents() end
    if FocusFrameManaBar then FocusFrameManaBar:UnregisterAllEvents() end

    -- Groupe (party) et raid : volontairement non masques. MarcelFramer ne gere
    -- pas ces cadres ; on laisse l'interface Blizzard de base s'en charger.
end

-- ----------------------------------------------------------------------------
--  Couleurs sauvegardees (DB -> runtime) + rafraichissement live
-- ----------------------------------------------------------------------------
function ns:ApplySavedColors()
    local db = MarcelFramerDB
    if db.barStyle then ns.config.barStyle = db.barStyle end
    if db.classGradient ~= nil then ns.config.classGradient = db.classGradient end
    if db.classBarColors then
        for class, sides in pairs(db.classBarColors) do
            local entry = ns.classBarColors[class] or {}
            if sides.left then entry.left = { sides.left[1], sides.left[2], sides.left[3] } end
            if sides.right then entry.right = { sides.right[1], sides.right[2], sides.right[3] } end
            ns.classBarColors[class] = entry
        end
    end
end

-- Re-applique couleurs de vie + nom sur toutes les frames (apercu live des reglages)
function ns:RefreshAll()
    local E = ns.Elements
    for _, data in pairs(ns.registry) do
        local frame = data.frame
        if frame.health then
            E.UpdateHealth(frame)
            E.UpdateName(frame)
        end
    end
end

-- ----------------------------------------------------------------------------
--  Commandes slash
-- ----------------------------------------------------------------------------
SLASH_MARCELFRAMER1 = "/marcelframer"
SLASH_MARCELFRAMER2 = "/mf"
SlashCmdList["MARCELFRAMER"] = function(msg)
    msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "unlock" then
        ns:Unlock()
    elseif msg == "lock" then
        ns:Lock()
    elseif msg == "reset" then
        ns:Reset()
    elseif msg == "config" or msg == "colors" or msg == "couleurs" then
        if ns.Options and ns.Options.Toggle then ns.Options.Toggle() end
    else
        MF_Print("commandes : |cffffff00/mf config|r (couleurs), |cffffff00/mf unlock|r, |cffffff00/mf lock|r, |cffffff00/mf reset|r")
    end
end

-- ----------------------------------------------------------------------------
--  Cycle de vie
-- ----------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        MarcelFramerDB = MarcelFramerDB or {}
        MarcelFramerDB.positions = MarcelFramerDB.positions or {}
        MarcelFramerDB.classBarColors = MarcelFramerDB.classBarColors or {}
        ns:ApplySavedColors()
        ns:HideBlizzard()
        if ns.UnitFrame and ns.UnitFrame.CreateAll then ns.UnitFrame.CreateAll() end
    end
end)
