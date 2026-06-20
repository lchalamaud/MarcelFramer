local addonName, ns = ...

-- ============================================================================
--  Elements.lua — Briques reutilisables (barres, textes, couleurs, auras, cast)
--  Utilisees par UnitFrame.lua.
-- ============================================================================

local Elements = {}
ns.Elements = Elements

local INSET = 0   -- 0 = pas de contour (barres bord a bord) ; >0 = liseré sombre

-- ----------------------------------------------------------------------------
--  Detection de l'API d'auras (MoP 5.5.4) avec repli
-- ----------------------------------------------------------------------------
local GetAura
if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
    GetAura = function(unit, index, filter)
        local data = C_UnitAuras.GetAuraDataByIndex(unit, index, filter)
        if not data then return nil end
        return data.name, data.icon, data.applications, data.dispelName, data.duration, data.expirationTime
    end
else
    GetAura = function(unit, index, filter)
        return UnitAura(unit, index, filter)  -- name, icon, count, dispelType, duration, expirationTime, ...
    end
end

-- ----------------------------------------------------------------------------
--  Helpers
-- ----------------------------------------------------------------------------
local function FormatNumber(v)
    if v >= 1e6 then
        return string.format("%.1fM", v / 1e6)
    elseif v >= 1e4 then
        return string.format("%.0fk", v / 1e3)
    end
    return tostring(v)
end

local function hex(c) return math.floor(c * 255 + 0.5) end

-- Adoucit une couleur : desature vers sa luminance puis ajuste la luminosite
local function AdjustColor(r, g, b)
    local adj = ns.config.colorAdjust
    if not adj then return r, g, b end
    local sat = adj.saturation or 1
    local bri = adj.brightness or 1
    if sat ~= 1 then
        local lum = 0.3 * r + 0.59 * g + 0.11 * b
        r = lum + (r - lum) * sat
        g = lum + (g - lum) * sat
        b = lum + (b - lum) * sat
    end
    return r * bri, g * bri, b * bri
end

-- Paire de couleurs {left={r,g,b}, right={r,g,b}} choisie a la main pour un
-- joueur de classe connue (table ns.classBarColors), ou nil. Pas de gate de style.
function Elements.GetClassColors(unit, cfg)
    if cfg and cfg.classColor == false then return nil end
    if not ns.classBarColors then return nil end
    if not UnitIsPlayer(unit) then return nil end
    local _, class = UnitClass(unit)
    return class and ns.classBarColors[class] or nil
end

function Elements.GetUnitColor(unit, cfg)
    -- Couleur personnalisee explicite : on la respecte telle quelle
    if cfg and cfg.classColor == false and cfg.color then
        return cfg.color[1], cfg.color[2], cfg.color[3]
    end
    if UnitIsPlayer(unit) then
        local _, class = UnitClass(unit)
        local c = class and RAID_CLASS_COLORS[class]
        if c then return AdjustColor(c.r, c.g, c.b) end
    else
        -- PNJ : couleur de reaction configurable (prise telle quelle, WYSIWYG)
        local cat = ns.ReactionCategory(UnitReaction(unit, "player"))
        local c = cat and ns.reactionColors and ns.reactionColors[cat]
        if c then return c[1], c[2], c[3] end
        -- Repli ultime sur la table Blizzard si la categorie est inconnue
        local fc = FACTION_BAR_COLORS and FACTION_BAR_COLORS[UnitReaction(unit, "player") or 0]
        if fc then return AdjustColor(fc.r, fc.g, fc.b) end
    end
    return 0.7, 0.7, 0.7
end

-- Coeur du rendu : peint une barre d'un degrade left -> right (paires r,g,b).
-- left == right => barre unie. Toujours via SetGradient pour ecraser un eventuel
-- degrade precedent ; repli SetStatusBarColor si SetGradient absent.
local function PaintBar(bar, lr, lg, lb, rr, rg, rb)
    bar:SetStatusBarColor(rr, rg, rb)
    local tex = bar:GetStatusBarTexture()
    if tex and tex.SetGradient then
        local orient = (ns.config.barGradient and ns.config.barGradient.orientation) or "HORIZONTAL"
        tex:SetGradient(orient, CreateColor(lr, lg, lb, 1), CreateColor(rr, rg, rb, 1))
    end
end
Elements.PaintBar = PaintBar

-- Peint une barre a partir d'UNE couleur (ressource, cast, PNJ). En mode
-- "gradient" on derive un degrade par luminosite (dark->light) ; sinon uni.
local function SetBarColor(bar, r, g, b)
    if ns.config.barStyle == "gradient" then
        local grad = ns.config.barGradient
        local dk = grad and grad.dark or 0.72
        local lt = grad and grad.light or 1.0
        PaintBar(bar, r * dk, g * dk, b * dk,
            math.min(r * lt, 1), math.min(g * lt, 1), math.min(b * lt, 1))
    else
        PaintBar(bar, r, g, b, r, g, b)
    end
end

-- ----------------------------------------------------------------------------
--  Construction visuelle
-- ----------------------------------------------------------------------------
local function BarTexture()
    if ns.config.barStyle == "blizzard" then
        return "Interface\\TargetingFrame\\UI-StatusBar"
    end
    return ns.media.statusbar
end

local function CreateBar(parent)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(BarTexture())
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(ns.media.statusbar)
    bg:SetVertexColor(0, 0, 0, 0.15)
    bar.bg = bg
    return bar
end

local function CreateAuraIcon(parent, size)
    local btn = CreateFrame("Frame", nil, parent)
    btn:SetSize(size, size)

    local bd = btn:CreateTexture(nil, "BACKGROUND")
    bd:SetPoint("TOPLEFT", -1, 1)
    bd:SetPoint("BOTTOMRIGHT", 1, -1)
    bd:SetColorTexture(0, 0, 0, 1)
    btn.bd = bd

    local tex = btn:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints()
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn.tex = tex

    local cd = CreateFrame("Cooldown", nil, btn, "CooldownFrameTemplate")
    cd:SetAllPoints()
    btn.cd = cd

    local count = btn:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    count:SetPoint("BOTTOMRIGHT", 1, -1)
    btn.count = count

    btn:Hide()
    return btn
end

-- Presets d'icone de combat : des sprites PLATS transparents facon "emoji"
-- (pas des icones carrees a bordure). { texture, l, r, haut, bas }.
-- Choix via cfg.combatStyle. Les marqueurs de raid partagent une meme texture
-- atlas 4x4 (UI-RaidTargetingIcons) ; on cible la bonne case par texcoords.
local RAID_ICONS = "Interface\\TargetingFrame\\UI-RaidTargetingIcons"
local COMBAT_PRESETS = {
    -- atlas Blizzard : epees croisees (variante "Map", plus coloree). Un peu
    -- agrandie (scale) et teintee de rouge discret pour evoquer le combat.
    combat   = { atlas = "ShipMissionIcon-Combat-Map", scale = 1.2, color = {1, 0.5, 0.5} },
    swords   = { tex = "Interface\\CharacterFrame\\UI-StateIcon", coords = {0.5, 1.0, 0.0, 0.494} },
    skull    = { tex = RAID_ICONS, coords = {0.75, 1.00, 0.25, 0.50} },  -- crane blanc
    cross    = { tex = RAID_ICONS, coords = {0.50, 0.75, 0.25, 0.50} },  -- croix rouge
    star     = { tex = RAID_ICONS, coords = {0.00, 0.25, 0.00, 0.25} },  -- etoile jaune
    diamond  = { tex = RAID_ICONS, coords = {0.50, 0.75, 0.00, 0.25} },  -- losange violet
    triangle = { tex = RAID_ICONS, coords = {0.75, 1.00, 0.00, 0.25} },  -- triangle vert
}
ns.combatPresets = COMBAT_PRESETS

-- Applique un preset (atlas ou texture+texcoords) a la texture donnee.
local function ApplyCombatPreset(tex, p)
    if p.atlas then
        tex:SetAtlas(p.atlas)
    else
        tex:SetTexture(p.tex)
        tex:SetTexCoord(unpack(p.coords))
    end
end

-- (Re)calcule la hauteur des barres vie/ressource selon cfg.height / powerRatio.
-- Logique partagee : appelee a la construction ET lors d'un changement de taille
-- a chaud (ns:ApplySize). La largeur suit toute seule via les ancres TOPLEFT/RIGHT.
function Elements.LayoutBars(frame)
    local cfg = frame.config
    local h = cfg.height
    local powerH = 0
    if frame.power then
        powerH = math.max(4, math.floor(h * (cfg.powerRatio or 0.25)))
        frame.power:SetHeight(powerH)
    end
    if frame.health then
        frame.health:SetHeight(h - powerH - (powerH > 0 and INSET or 0) - INSET)
    end
end

-- Construit barres + textes (appele a la creation de chaque frame/bouton)
function Elements.BuildVisuals(frame)
    local cfg = frame.config
    local mirror = cfg.mirror

    -- Fond / bordure sombre
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", -INSET, INSET)
    bg:SetPoint("BOTTOMRIGHT", INSET, -INSET)
    bg:SetColorTexture(0, 0, 0, 0.15)
    frame.bg = bg

    -- Barre de vie
    local health = CreateBar(frame)
    health:SetPoint("TOPLEFT", INSET, -INSET)
    health:SetPoint("TOPRIGHT", -INSET, -INSET)
    if mirror and health.SetReverseFill then health:SetReverseFill(true) end
    frame.health = health

    -- Barre de ressource
    if cfg.showPower then
        local power = CreateBar(frame)
        power:SetPoint("BOTTOMLEFT", INSET, INSET)
        power:SetPoint("BOTTOMRIGHT", -INSET, INSET)
        if mirror and power.SetReverseFill then power:SetReverseFill(true) end
        frame.power = power
    end

    -- Hauteurs des deux barres (calcul partage, re-jouable a chaud)
    Elements.LayoutBars(frame)

    -- Textes : nom du cote "exterieur", valeurs du cote "interieur"
    local fontSize = cfg.fontSize or 11
    local inner = mirror and "LEFT" or "RIGHT"
    local outer = mirror and "RIGHT" or "LEFT"

    local htext = health:CreateFontString(nil, "OVERLAY")
    htext:SetFont(ns.media.font, fontSize, "OUTLINE")
    htext:SetPoint(inner, health, inner, mirror and 3 or -3, 0)
    htext:SetJustifyH(inner)
    frame.healthText = htext

    local name = health:CreateFontString(nil, "OVERLAY")
    name:SetFont(ns.media.font, fontSize, "OUTLINE")
    name:SetPoint(outer, health, outer, mirror and -3 or 3, 0)
    name:SetPoint(inner, htext, outer, mirror and 2 or -2, 0)
    name:SetJustifyH(outer)
    name:SetWordWrap(false)
    frame.nameText = name
    if cfg.showName == false then name:Hide() end

    -- Icone de combat : coin interieur-haut (oppose aux debuffs, donc pas de
    -- collision). Texture d'etat Blizzard (epees croisees), masquee par defaut.
    if cfg.showCombat then
        local size = cfg.combatSize or 18
        local color
        local ci = health:CreateTexture(nil, "OVERLAY")
        -- Design choisi via cfg.combatStyle (preset, defaut "combat"). Overrides
        -- prioritaires : cfg.combatAtlas (atlas Blizzard) puis cfg.combatTexture
        -- (+ cfg.combatTexCoord optionnel).
        if cfg.combatAtlas then
            ci:SetAtlas(cfg.combatAtlas)
        elseif cfg.combatTexture then
            ci:SetTexture(cfg.combatTexture)
            ci:SetTexCoord(unpack(cfg.combatTexCoord or {0, 1, 0, 1}))
        else
            local p = COMBAT_PRESETS[cfg.combatStyle or "combat"] or COMBAT_PRESETS.combat
            ApplyCombatPreset(ci, p)
            if p.scale then size = size * p.scale end
            color = p.color
        end
        -- Teinte : cfg.combatColor a priorite sur celle du preset.
        color = cfg.combatColor or color
        if color then ci:SetVertexColor(color[1], color[2], color[3]) end
        ci:SetSize(size, size)
        ci:SetPoint("CENTER", frame, mirror and "TOPLEFT" or "TOPRIGHT", 0, 0)
        ci:Hide()
        frame.combatIcon = ci
    end

    -- Texte de ressource
    if frame.power and cfg.showPowerText then
        local ptext = frame.power:CreateFontString(nil, "OVERLAY")
        ptext:SetFont(ns.media.font, math.max(8, fontSize - 1), "OUTLINE")
        ptext:SetPoint(inner, frame.power, inner, mirror and 3 or -3, 0)
        ptext:SetJustifyH(inner)
        frame.powerText = ptext
    end
end

-- Construit les rangees de buffs/debuffs (sous le cadre / au-dessus, en miroir si besoin)
function Elements.CreateAuras(frame)
    local cfg = frame.config
    local max = cfg.numAuras or 0
    if max <= 0 then return end
    local size = cfg.auraSize or 18
    local mirror = cfg.mirror
    local below = frame.castBar or frame   -- buffs sous la barre de cast si presente

    if cfg.showBuffs then
        frame.buffIcons = {}
        for i = 1, max do
            local btn = CreateAuraIcon(frame, size)
            if i == 1 then
                if mirror then btn:SetPoint("TOPRIGHT", below, "BOTTOMRIGHT", 0, -3)
                else btn:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, -3) end
            else
                if mirror then btn:SetPoint("RIGHT", frame.buffIcons[i - 1], "LEFT", -3, 0)
                else btn:SetPoint("LEFT", frame.buffIcons[i - 1], "RIGHT", 3, 0) end
            end
            frame.buffIcons[i] = btn
        end
    end

    if cfg.showDebuffs then
        frame.debuffIcons = {}
        for i = 1, max do
            local btn = CreateAuraIcon(frame, size)
            if i == 1 then
                if mirror then btn:SetPoint("BOTTOMRIGHT", frame, "TOPRIGHT", 0, 3)
                else btn:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 3) end
            else
                if mirror then btn:SetPoint("RIGHT", frame.debuffIcons[i - 1], "LEFT", -3, 0)
                else btn:SetPoint("LEFT", frame.debuffIcons[i - 1], "RIGHT", 3, 0) end
            end
            frame.debuffIcons[i] = btn
        end
    end
end

-- ----------------------------------------------------------------------------
--  Tooltip au survol
-- ----------------------------------------------------------------------------
local function Unit_OnEnter(self)
    local unit = self.unit
    if not unit or not UnitExists(unit) then return end
    -- GameTooltip_SetDefaultAnchor est le point surcharge par les addons de
    -- tooltip (TipTac, etc.) : on respecte ainsi leur position. Repli sur
    -- ANCHOR_RIGHT si la fonction Blizzard est absente.
    if GameTooltip_SetDefaultAnchor then
        GameTooltip_SetDefaultAnchor(GameTooltip, self)
    else
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    end
    GameTooltip:SetUnit(unit)
    GameTooltip:Show()
    self.isMouseOver = true
end

local function Unit_OnLeave(self)
    self.isMouseOver = nil
    GameTooltip:Hide()
end

-- Active le tooltip natif au survol (sur tout cadre/bouton d'unite)
function Elements.EnableTooltip(frame)
    frame:HookScript("OnEnter", Unit_OnEnter)
    frame:HookScript("OnLeave", Unit_OnLeave)
end

-- ----------------------------------------------------------------------------
--  Barre de cast (player / target)
-- ----------------------------------------------------------------------------
local CAST_EVENTS = {
    "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
    "UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED",
    "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_CHANNEL_UPDATE",
    "UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
}

local function CastBar_Reset(cb)
    cb.casting, cb.channeling = nil, nil
    cb:Hide()
end

local function CastBar_Color(cb)
    if cb.notInterruptible then
        cb:SetStatusBarColor(0.6, 0.6, 0.6)
    else
        cb:SetStatusBarColor(0.2, 0.5, 1.0)
    end
end

function Elements.CastBarCheck(frame)
    local cb = frame.castBar
    if not cb then return end
    local unit = frame.unit
    if not unit or not UnitExists(unit) then CastBar_Reset(cb); return end

    local name, _, texture, startMS, endMS, _, _, notInterruptible = UnitCastingInfo(unit)
    local channel = false
    if not name then
        name, _, texture, startMS, endMS, _, notInterruptible = UnitChannelInfo(unit)
        channel = true
    end
    if not name or not startMS or not endMS then CastBar_Reset(cb); return end

    cb.startTime = startMS / 1000
    cb.endTime   = endMS / 1000
    cb.casting     = not channel
    cb.channeling  = channel
    cb.notInterruptible = notInterruptible
    cb:SetMinMaxValues(0, cb.endTime - cb.startTime)
    cb:SetValue(channel and (cb.endTime - cb.startTime) or 0)
    cb.icon:SetTexture(texture)
    cb.text:SetText(name)
    CastBar_Color(cb)
    cb:Show()
end

local function CastBar_OnUpdate(self)
    local t = GetTime()
    if self.casting then
        if t >= self.endTime then CastBar_Reset(self); return end
        self:SetValue(t - self.startTime)
    elseif self.channeling then
        if t >= self.endTime then CastBar_Reset(self); return end
        self:SetValue(self.endTime - t)
    end
end

local function CastBar_OnEvent(self, event, arg1)
    local frame = self.owner
    if event == "PLAYER_TARGET_CHANGED" then
        Elements.CastBarCheck(frame)
        return
    end
    if arg1 ~= frame.unit then return end
    if event == "UNIT_SPELLCAST_START" or event == "UNIT_SPELLCAST_CHANNEL_START"
        or event == "UNIT_SPELLCAST_DELAYED" or event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
        Elements.CastBarCheck(frame)
    elseif event == "UNIT_SPELLCAST_INTERRUPTIBLE" then
        self.notInterruptible = false
        CastBar_Color(self)
    elseif event == "UNIT_SPELLCAST_NOT_INTERRUPTIBLE" then
        self.notInterruptible = true
        CastBar_Color(self)
    else
        CastBar_Reset(self)
    end
end

function Elements.CreateCastBar(frame)
    local cfg = frame.config
    local mirror = cfg.mirror
    local height = cfg.castHeight or 16

    local cb = CreateFrame("StatusBar", nil, frame)
    cb:SetStatusBarTexture(BarTexture())
    cb:SetHeight(height)
    cb:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, -3)
    cb:SetPoint("TOPRIGHT", frame, "BOTTOMRIGHT", 0, -3)
    if mirror and cb.SetReverseFill then cb:SetReverseFill(true) end

    local bg = cb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.15)

    local icon = cb:CreateTexture(nil, "ARTWORK")
    icon:SetSize(height, height)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    if mirror then
        icon:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    else
        icon:SetPoint("RIGHT", cb, "LEFT", -2, 0)
    end
    cb.icon = icon

    local text = cb:CreateFontString(nil, "OVERLAY")
    text:SetFont(ns.media.font, cfg.fontSize or 11, "OUTLINE")
    text:SetPoint("LEFT", cb, "LEFT", 3, 0)
    text:SetPoint("RIGHT", cb, "RIGHT", -3, 0)
    text:SetJustifyH(mirror and "RIGHT" or "LEFT")
    text:SetWordWrap(false)
    cb.text = text

    cb.owner = frame
    cb:Hide()
    cb:SetScript("OnUpdate", CastBar_OnUpdate)
    cb:SetScript("OnEvent", CastBar_OnEvent)
    for _, ev in ipairs(CAST_EVENTS) do cb:RegisterEvent(ev) end
    if frame.unit == "target" then
        cb:RegisterEvent("PLAYER_TARGET_CHANGED")
    end

    frame.castBar = cb
    Elements.CastBarCheck(frame)
    return cb
end

-- ----------------------------------------------------------------------------
--  Mises a jour
-- ----------------------------------------------------------------------------
function Elements.UpdateHealth(frame)
    local unit = frame.unit
    if not unit or not UnitExists(unit) then return end
    local cur, max = UnitHealth(unit), UnitHealthMax(unit)
    local bar = frame.health
    bar:SetMinMaxValues(0, max > 0 and max or 1)
    bar:SetValue(cur)
    local cc = Elements.GetClassColors(unit, frame.config)
    if cc then
        if ns.config.classGradient ~= false then
            PaintBar(bar, cc.left[1], cc.left[2], cc.left[3], cc.right[1], cc.right[2], cc.right[3])
        else
            PaintBar(bar, cc.right[1], cc.right[2], cc.right[3], cc.right[1], cc.right[2], cc.right[3])
        end
    else
        SetBarColor(bar, Elements.GetUnitColor(unit, frame.config))
    end

    if frame.healthText then
        local cfg = frame.config
        local txt = ""
        if cfg.showHealthValue and max > 0 then
            txt = FormatNumber(cur) .. "/" .. FormatNumber(max)
        end
        if cfg.showPercent and max > 0 then
            local pct = string.format("%d%%", math.floor(cur / max * 100 + 0.5))
            txt = (txt ~= "") and (txt .. "  " .. pct) or pct
        end
        if txt == "" then txt = FormatNumber(cur) end
        frame.healthText:SetText(txt)
    end
end

function Elements.UpdatePower(frame)
    if not frame.power then return end
    local unit = frame.unit
    if not unit or not UnitExists(unit) then return end
    local cur, max = UnitPower(unit), UnitPowerMax(unit)
    local bar = frame.power
    bar:SetMinMaxValues(0, max > 0 and max or 1)
    bar:SetValue(cur)
    local ptype, ptoken = UnitPowerType(unit)
    -- Couleur configurable par jeton (ns.powerColors) ; repli PowerBarColor.
    local cc = ptoken and ns.powerColors and ns.powerColors[ptoken]
    if cc then
        SetBarColor(bar, cc[1], cc[2], cc[3])
    else
        local c = (ptoken and PowerBarColor[ptoken]) or PowerBarColor[ptype]
        if c then
            SetBarColor(bar, c.r, c.g, c.b)
        else
            SetBarColor(bar, 0.3, 0.3, 0.8)
        end
    end
    if frame.powerText then
        frame.powerText:SetText(max > 0 and FormatNumber(cur) or "")
    end
end

function Elements.UpdateName(frame)
    local unit = frame.unit
    if not unit or not UnitExists(unit) then return end
    if not frame.nameText then return end
    local cfg = frame.config
    local nameStr = UnitName(unit) or ""
    local prefix = ""
    if cfg.showLevel then
        local lvl = UnitLevel(unit)
        local lvlStr = (lvl and lvl > 0) and tostring(lvl) or "??"
        if cfg.levelDifficultyColor and GetQuestDifficultyColor then
            local col = GetQuestDifficultyColor((lvl and lvl > 0) and lvl or 999)
            prefix = string.format("|cff%02x%02x%02x%s|r ", hex(col.r), hex(col.g), hex(col.b), lvlStr)
        else
            prefix = lvlStr .. " "
        end
    end
    frame.nameText:SetText(prefix .. nameStr)
    local cc = Elements.GetClassColors(unit, cfg)
    if cc then
        frame.nameText:SetTextColor(cc.right[1], cc.right[2], cc.right[3])
    else
        frame.nameText:SetTextColor(Elements.GetUnitColor(unit, cfg))
    end
end

-- Couleurs de bordure des debuffs par type (auto-suffisant : le global
-- DebuffTypeColor n'existe pas sur ce client). dispelName vaut "Magic" /
-- "Curse" / "Disease" / "Poison", ou nil.
local DEBUFF_COLORS = {
    Magic   = { r = 0.20, g = 0.60, b = 1.00 },
    Curse   = { r = 0.60, g = 0.00, b = 1.00 },
    Disease = { r = 0.60, g = 0.40, b = 0.00 },
    Poison  = { r = 0.00, g = 0.60, b = 0.00 },
    none    = { r = 0.80, g = 0.00, b = 0.00 },
}

local function FillAuras(icons, unit, filter, isDebuff)
    for i = 1, #icons do
        local btn = icons[i]
        local name, icon, count, dispelType, duration, expiration = GetAura(unit, i, filter)
        if name then
            btn.tex:SetTexture(icon)
            if count and count > 1 then
                btn.count:SetText(count)
            else
                btn.count:SetText("")
            end
            if duration and duration > 0 and expiration and expiration > 0 then
                btn.cd:SetCooldown(expiration - duration, duration)
                btn.cd:Show()
            else
                btn.cd:Hide()
            end
            if isDebuff then
                local c = DEBUFF_COLORS[dispelType or "none"] or DEBUFF_COLORS.none
                btn.bd:SetColorTexture(c.r, c.g, c.b, 1)
            end
            btn:Show()
        else
            btn:Hide()
        end
    end
end

function Elements.UpdateAuras(frame)
    local unit = frame.unit
    if not unit or not UnitExists(unit) then return end
    if frame.buffIcons then FillAuras(frame.buffIcons, unit, "HELPFUL", false) end
    if frame.debuffIcons then FillAuras(frame.debuffIcons, unit, "HARMFUL", true) end
end

-- Affiche/masque l'icone de combat selon l'etat de l'unite de la frame.
function Elements.UpdateCombat(frame)
    if not frame.combatIcon then return end
    local unit = frame.unit
    if unit and UnitExists(unit) and UnitAffectingCombat(unit) then
        frame.combatIcon:Show()
    else
        frame.combatIcon:Hide()
    end
end

function Elements.FullUpdate(frame)
    local unit = frame.unit
    if not unit or not UnitExists(unit) then return end
    Elements.UpdateHealth(frame)
    Elements.UpdatePower(frame)
    Elements.UpdateName(frame)
    Elements.UpdateAuras(frame)
    Elements.UpdateCombat(frame)
    if frame.castBar then Elements.CastBarCheck(frame) end
end

-- ----------------------------------------------------------------------------
--  Evenements unite (filtres par unite)
-- ----------------------------------------------------------------------------
local UNIT_EVENTS = {
    "UNIT_HEALTH", "UNIT_MAXHEALTH",
    "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
    "UNIT_AURA", "UNIT_NAME_UPDATE", "UNIT_LEVEL",
    "UNIT_FLAGS",
}

function Elements.RegisterUnitEvents(frame)
    for _, ev in ipairs(UNIT_EVENTS) do
        frame:RegisterEvent(ev)
    end
end

-- Dispatcher partage : ne traite que les events filtres sur frame.unit
function Elements.OnEvent(self, event, arg1)
    local unit = self.unit
    if not unit or arg1 ~= unit then return end
    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" then
        Elements.UpdateHealth(self)
    elseif event == "UNIT_POWER_UPDATE" or event == "UNIT_MAXPOWER" then
        Elements.UpdatePower(self)
    elseif event == "UNIT_DISPLAYPOWER" then
        Elements.UpdatePower(self)
        Elements.UpdateHealth(self)
    elseif event == "UNIT_AURA" then
        Elements.UpdateAuras(self)
    elseif event == "UNIT_NAME_UPDATE" or event == "UNIT_LEVEL" then
        Elements.UpdateName(self)
    elseif event == "UNIT_FLAGS" then
        Elements.UpdateCombat(self)
    end
end
