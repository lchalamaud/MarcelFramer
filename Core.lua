local addonName, ns = ...

-- ============================================================================
--  Core.lua — Initialisation, masquage Blizzard, slash, movers, menu d'unite
-- ============================================================================

local noop = function() end
ns.noop = noop

ns.registry = {}   -- key -> { frame = <frame> }
ns.movers   = {}   -- key -> mover overlay frame
ns.unlocked = false
ns.pendingSizes = {}       -- key -> true : tailles a appliquer a la sortie de combat
ns.pendingPositions = {}   -- key -> true : positions a appliquer a la sortie de combat

-- Tailles par defaut (Config.lua), capturees avant toute fusion DB (pour /reset)
ns.sizeDefaults = {}
for _, key in ipairs({ "player", "target", "focus", "targettarget", "pet" }) do
    local c = ns.config[key]
    if c then
        ns.sizeDefaults[key] = { width = c.width, height = c.height, scale = c.scale or 1 }
    end
end

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

-- Synchronise le mover d'un cadre sur sa position courante (cadre non securise).
local function SyncMover(key)
    local mover = ns.movers[key]
    if not mover then return end
    local p = ns:GetPosition(key)
    if not p then return end
    mover:ClearAllPoints()
    mover:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x or 0, p.y or 0)
end

-- Applique a chaud la position d'un cadre (+ son mover) depuis la DB/config.
-- Differe en combat : SetPoint est protege sur un cadre securise pendant le
-- lockdown (rejoue a PLAYER_REGEN_ENABLED).
function ns:ApplyPositionByKey(key)
    local data = ns.registry[key]
    if not data then return false end
    if InCombatLockdown() then
        ns.pendingPositions[key] = true
        return false
    end
    ns:ApplyPosition(data.frame, key)
    SyncMover(key)
    return true
end

-- Ecrit X/Y dans la DB (en conservant l'ancrage courant) puis applique.
function ns:SavePosition(key, x, y)
    local cur = ns:GetPosition(key) or {}
    local point    = cur.point or "CENTER"
    local relPoint = cur.relPoint or point
    MarcelFramerDB.positions[key] = { point = point, relPoint = relPoint, x = x, y = y }
    ns:ApplyPositionByKey(key)
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
    mover:SetScale(cfg.scale or 1)
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

    -- Focus (+ cible du focus Blizzard)
    killFrame(FocusFrame)
    if FocusFrameHealthBar then FocusFrameHealthBar:UnregisterAllEvents() end
    if FocusFrameManaBar then FocusFrameManaBar:UnregisterAllEvents() end
    if FocusFrameToT then killFrame(FocusFrameToT) end
end

-- ----------------------------------------------------------------------------
--  Couleurs sauvegardees (DB -> runtime) + rafraichissement live
-- ----------------------------------------------------------------------------
function ns:ApplySavedColors()
    local db = MarcelFramerDB
    if db.barStyle then ns.config.barStyle = db.barStyle end
    if db.classBarColors then
        for class, c in pairs(db.classBarColors) do
            -- Compat ancien format {left,right} : on conserve la teinte "right".
            local rgb = c.right or c
            if rgb[1] then ns.classBarColors[class] = { rgb[1], rgb[2], rgb[3] } end
        end
    end
    if db.powerColors then
        for token, rgb in pairs(db.powerColors) do
            ns.powerColors[token] = { rgb[1], rgb[2], rgb[3] }
        end
    end
    if db.reactionColors then
        for cat, rgb in pairs(db.reactionColors) do
            ns.reactionColors[cat] = { rgb[1], rgb[2], rgb[3] }
        end
    end
    if db.castColors and ns.castColors then
        local c = db.castColors
        if c.distinguish ~= nil then ns.castColors.distinguish = c.distinguish end
        if c.interruptible then
            ns.castColors.interruptible = { c.interruptible[1], c.interruptible[2], c.interruptible[3] }
        end
        if c.notInterruptible then
            ns.castColors.notInterruptible = { c.notInterruptible[1], c.notInterruptible[2], c.notInterruptible[3] }
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
            E.UpdatePower(frame)
            E.UpdateName(frame)
            if frame.castBar then E.CastBarCheck(frame) end
        end
    end
end

-- ----------------------------------------------------------------------------
--  Tailles des cadres (live + SavedVariables)
-- ----------------------------------------------------------------------------
-- Fusionne les tailles sauvegardees dans ns.config (AVANT creation des cadres,
-- car UnitFrame lit cfg.width/height/scale a la creation).
function ns:ApplySavedSizes()
    local sizes = MarcelFramerDB and MarcelFramerDB.sizes
    if not sizes then return end
    for key, s in pairs(sizes) do
        local c = ns.config[key]
        if c then
            if s.width  then c.width  = s.width  end
            if s.height then c.height = s.height end
            if s.scale  then c.scale  = s.scale  end
        end
    end
end

-- Applique a chaud la taille d'un cadre (+ son mover) depuis ns.config.
-- Differe en combat : SetSize/SetScale sont proteges sur un cadre securise
-- pendant le lockdown (rejoue a PLAYER_REGEN_ENABLED).
function ns:ApplySize(key)
    local data = ns.registry[key]
    if not data then return false end
    if InCombatLockdown() then
        ns.pendingSizes[key] = true
        return false
    end
    local frame = data.frame
    local cfg = ns.config[key]
    frame:SetSize(cfg.width, cfg.height)
    frame:SetScale(cfg.scale or 1)
    if ns.Elements and ns.Elements.LayoutBars then ns.Elements.LayoutBars(frame) end
    local mover = ns.movers[key]
    if mover then
        mover:SetSize(cfg.width, cfg.height)
        mover:SetScale(cfg.scale or 1)
    end
    return true
end

-- Restaure toutes les tailles aux valeurs de Config.lua
function ns:ResetSizes()
    if MarcelFramerDB.sizes then wipe(MarcelFramerDB.sizes) end
    for key, def in pairs(ns.sizeDefaults) do
        local c = ns.config[key]
        if c then c.width, c.height, c.scale = def.width, def.height, def.scale end
        ns:ApplySize(key)
    end
end

-- ----------------------------------------------------------------------------
--  Barre de cast (player / target / focus uniquement) : preference + bascule live
-- ----------------------------------------------------------------------------
-- Fusionne les preferences sauvegardees dans ns.config (AVANT creation des
-- cadres, car CreateCastBar lit cfg.showCastBar a la creation).
function ns:ApplySavedCastBars()
    local saved = MarcelFramerDB and MarcelFramerDB.castbars
    if not saved then return end
    for key, v in pairs(saved) do
        if ns.config[key] then ns.config[key].showCastBar = v end
    end
end

-- Active/desactive a chaud la barre de cast d'un cadre. Non securisee (la barre
-- est un StatusBar non protege) : sans restriction de combat. Re-ancre les auras
-- (les buffs suivent la barre de cast) pour ne pas laisser de trou a l'emplacement
-- de la barre masquee.
function ns:SetCastBarEnabled(key, enabled)
    if key ~= "player" and key ~= "target" and key ~= "focus" then return end
    enabled = enabled and true or false
    if ns.config[key] then ns.config[key].showCastBar = enabled end
    MarcelFramerDB.castbars = MarcelFramerDB.castbars or {}
    MarcelFramerDB.castbars[key] = enabled

    local data = ns.registry[key]
    if not data then return end
    local frame = data.frame
    local cb = frame.castBar
    if cb then
        cb.enabled = enabled
        if enabled then
            ns.Elements.CastBarCheck(frame)   -- reaffiche si une incantation est en cours
        else
            cb.casting, cb.channeling = nil, nil
            cb:Hide()
        end
    end
    if ns.Elements.AnchorAuras then ns.Elements.AnchorAuras(frame) end
end

-- ----------------------------------------------------------------------------
--  Auras (buffs / debuffs) : affichage + ancrage, parametrables via /mf config
-- ----------------------------------------------------------------------------
-- Champs d'un bloc d'ancrage persistes dans la DB.
local AURA_ANCHOR_FIELDS = { "point", "relTo", "relPoint", "x", "y", "growth" }

-- Fusionne les reglages d'auras sauvegardes dans ns.config (AVANT creation des
-- cadres, car CreateAuras lit showBuffs/showDebuffs + buffAnchor/debuffAnchor a
-- la creation). On copie champ par champ sur le bloc d'ancrage existant pour que
-- les valeurs par defaut de Config.lua comblent les trous.
function ns:ApplySavedAuras()
    local saved = MarcelFramerDB and MarcelFramerDB.auras
    if not saved then return end
    for key, data in pairs(saved) do
        local cfg = ns.config[key]
        if cfg then
            if data.showBuffs   ~= nil then cfg.showBuffs   = data.showBuffs   end
            if data.showDebuffs ~= nil then cfg.showDebuffs = data.showDebuffs end
            -- Filtres par type (seulement les miennes / les miennes plus grosses)
            for _, f in ipairs({ "buffOnlyMine", "debuffOnlyMine", "buffBigMine", "debuffBigMine" }) do
                if data[f] ~= nil then cfg[f] = data[f] end
            end
            for _, kind in ipairs({ "buffAnchor", "debuffAnchor" }) do
                local src = data[kind]
                if src then
                    cfg[kind] = cfg[kind] or {}
                    for _, f in ipairs(AURA_ANCHOR_FIELDS) do
                        if src[f] ~= nil then cfg[kind][f] = src[f] end
                    end
                end
            end
        end
    end
end

-- Sous-table DB d'un cadre (creee a la demande).
local function auraDB(key)
    MarcelFramerDB.auras = MarcelFramerDB.auras or {}
    MarcelFramerDB.auras[key] = MarcelFramerDB.auras[key] or {}
    return MarcelFramerDB.auras[key]
end

-- Bascule a chaud l'affichage d'un type d'aura (kind = "buffs"/"debuffs").
function ns:SetAuraShown(key, kind, shown)
    local cfg = ns.config[key]
    if not cfg then return end
    shown = shown and true or false
    auraDB(key)[kind == "buffs" and "showBuffs" or "showDebuffs"] = shown
    local data = ns.registry[key]
    if data and ns.Elements.SetAuraTypeShown then
        ns.Elements.SetAuraTypeShown(data.frame, kind, shown)
    else
        if kind == "buffs" then cfg.showBuffs = shown else cfg.showDebuffs = shown end
    end
end

-- Modifie un champ d'ancrage (point/relPoint/relTo/x/y/growth) d'un type d'aura,
-- l'enregistre, puis re-ancre la rangee a chaud.
function ns:SetAuraAnchor(key, kind, field, value)
    local cfg = ns.config[key]
    if not cfg then return end
    local cfgKey = (kind == "buffs") and "buffAnchor" or "debuffAnchor"
    cfg[cfgKey] = cfg[cfgKey] or {}
    cfg[cfgKey][field] = value

    local db = auraDB(key)
    db[cfgKey] = db[cfgKey] or {}
    db[cfgKey][field] = value

    local data = ns.registry[key]
    if data and ns.Elements.AnchorAuras then ns.Elements.AnchorAuras(data.frame) end
end

-- Bascule un drapeau de filtre d'auras (flag = "onlyMine" | "bigMine") pour un
-- type (kind = "buffs"/"debuffs") d'un cadre. Persiste puis re-remplit la rangee
-- a chaud (le re-remplissage applique le filtre et les tailles). Pour bigMine on
-- re-ancre aussi : les icones changent de taille, l'ancrage bord-a-bord se recale.
function ns:SetAuraFlag(key, kind, flag, value)
    local cfg = ns.config[key]
    if not cfg then return end
    value = value and true or false
    local field = ((kind == "buffs") and "buff" or "debuff")
        .. ((flag == "onlyMine") and "OnlyMine" or "BigMine")
    cfg[field] = value
    auraDB(key)[field] = value

    local data = ns.registry[key]
    if data then
        if ns.Elements.UpdateAuras then ns.Elements.UpdateAuras(data.frame) end
        if flag == "bigMine" and ns.Elements.AnchorAuras then ns.Elements.AnchorAuras(data.frame) end
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
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        MarcelFramerDB = MarcelFramerDB or {}
        MarcelFramerDB.positions = MarcelFramerDB.positions or {}
        MarcelFramerDB.classBarColors = MarcelFramerDB.classBarColors or {}
        MarcelFramerDB.powerColors = MarcelFramerDB.powerColors or {}
        MarcelFramerDB.reactionColors = MarcelFramerDB.reactionColors or {}
        MarcelFramerDB.castColors = MarcelFramerDB.castColors or {}
        MarcelFramerDB.sizes = MarcelFramerDB.sizes or {}
        MarcelFramerDB.castbars = MarcelFramerDB.castbars or {}
        MarcelFramerDB.auras = MarcelFramerDB.auras or {}
        ns:ApplySavedColors()
        ns:ApplySavedSizes()
        ns:ApplySavedCastBars()
        ns:ApplySavedAuras()
        ns:HideBlizzard()
        if ns.UnitFrame and ns.UnitFrame.CreateAll then ns.UnitFrame.CreateAll() end
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Sortie de combat : applique les tailles mises en attente pendant le lockdown
        if next(ns.pendingSizes) then
            local keys = {}
            for k in pairs(ns.pendingSizes) do keys[#keys + 1] = k end
            wipe(ns.pendingSizes)
            for _, k in ipairs(keys) do ns:ApplySize(k) end
        end
        -- Idem pour les positions mises en attente
        if next(ns.pendingPositions) then
            local keys = {}
            for k in pairs(ns.pendingPositions) do keys[#keys + 1] = k end
            wipe(ns.pendingPositions)
            for _, k in ipairs(keys) do ns:ApplyPositionByKey(k) end
        end
    end
end)
