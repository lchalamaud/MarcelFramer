local addonName, ns = ...

-- ============================================================================
--  Elements.lua — Briques reutilisables (barres, textes, couleurs, auras, cast)
--  Utilisees par UnitFrame.lua.
-- ============================================================================

local Elements = {}
ns.Elements = Elements

-- Bord noir 1px autour du cadre + separateur 1px entre vie et ressource
-- (maquette v2 : border:1px solid #000). Le fond noir opaque du cadre apparait
-- la ou les barres sont en retrait de INSET.
local INSET = 1

-- Detection du support des masques (MaskTexture) : moteur retail moderne (MoP
-- 5.5.4) -> disponible. Traduction de border-radius/clip CSS. Repli propre si
-- absent (badge carre, pas de coins arrondis) plutot qu'une erreur.
local HAS_MASK
do
    local probe = CreateFrame("Frame")
    HAS_MASK = type(probe.CreateMaskTexture) == "function"
end

local PORTRAIT_MASK = "Interface\\CHARACTERFRAME\\TempPortraitAlphaMask" -- masque rond (cercle)
local ROUND_MASK    = "Interface\\Common\\common-iconmask"               -- masque coins arrondis

-- Ajoute un masque ROND a une texture (border-radius:50% du badge de combat).
local function AddCircleMask(tex)
    if not HAS_MASK then return end
    local m = tex:GetParent():CreateMaskTexture()
    m:SetTexture(PORTRAIT_MASK)
    m:SetAllPoints(tex)
    tex:AddMaskTexture(m)
end

-- Applique des coins arrondis (border-radius:3px) au cadre : masque partage sur
-- les textures de barre. EXPERIMENTAL (cf. ns.config.roundedCorners).
local function ApplyRoundedCorners(frame)
    if not HAS_MASK then return end
    local mask = frame:CreateMaskTexture()
    mask:SetTexture(ROUND_MASK, "CLAMPTOWHITE", "CLAMPTOWHITE")
    mask:SetAllPoints(frame)
    frame.cornerMask = mask
    local function addTo(tex) if tex then tex:AddMaskTexture(mask) end end
    addTo(frame.bg)
    if frame.health then addTo(frame.health:GetStatusBarTexture()); addTo(frame.health.bg) end
    if frame.power  then addTo(frame.power:GetStatusBarTexture());  addTo(frame.power.bg)  end
end

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

-- Couleur unie (r,g,b) choisie a la main pour un joueur de classe connue
-- (ns.classBarColors), ou nil. Pas de gate de style.
function Elements.GetClassColors(unit, cfg)
    if cfg and cfg.classColor == false then return nil end
    if not ns.classBarColors then return nil end
    if not UnitIsPlayer(unit) then return nil end
    local _, class = UnitClass(unit)
    local c = class and ns.classBarColors[class]
    if c then return c[1], c[2], c[3] end
    return nil
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

-- Peint une barre d'un degrade VERTICAL (bas -> haut). Traduction CSS de
-- linear-gradient(to bottom, top, bottom) : top = clair (haut), bottom = fonce.
-- WoW SetGradient("VERTICAL", minColor, maxColor) : min = bas, max = haut.
local function PaintBarVertical(bar, br, bg_, bb, tr, tg, tb)
    bar:SetStatusBarColor(tr, tg, tb)
    local tex = bar:GetStatusBarTexture()
    if tex and tex.SetGradient then
        tex:SetGradient("VERTICAL", CreateColor(br, bg_, bb, 1), CreateColor(tr, tg, tb, 1))
    end
end
Elements.PaintBarVertical = PaintBarVertical

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

-- Couleur unie d'une ressource : ns.powerColors (editable /mf config) puis repli
-- PowerBarColor Blizzard, puis defaut bleute.
local function ResolvePowerColor(ptype, ptoken)
    local cc = ptoken and ns.powerColors and ns.powerColors[ptoken]
    if cc then return cc[1], cc[2], cc[3] end
    local c = (ptoken and PowerBarColor[ptoken]) or PowerBarColor[ptype]
    if c then return c.r, c.g, c.b end
    return 0.3, 0.3, 0.8
end

-- Peint la barre de ressource. En style "gradient" : degrade VERTICAL (maquette).
-- Priorite au degrade explicite ns.powerGradients[jeton], SAUF si l'utilisateur a
-- personnalise la couleur du jeton via /mf config (MarcelFramerDB.powerColors) :
-- on derive alors le degrade vertical de cette couleur unie (respect du choix).
local function PaintResource(bar, ptype, ptoken)
    if ns.config.barStyle ~= "gradient" then
        SetBarColor(bar, ResolvePowerColor(ptype, ptoken))
        return
    end
    local userColor = ptoken and MarcelFramerDB and MarcelFramerDB.powerColors
        and MarcelFramerDB.powerColors[ptoken]
    local g = ptoken and ns.powerGradients and ns.powerGradients[ptoken]
    if g and not userColor then
        PaintBarVertical(bar, g.bottom[1], g.bottom[2], g.bottom[3], g.top[1], g.top[2], g.top[3])
        return
    end
    local r, gg, b = ResolvePowerColor(ptype, ptoken)
    local grad = ns.config.barGradient
    local dk = (grad and grad.dark) or 0.72
    PaintBarVertical(bar, r * dk, gg * dk, b * dk, r, gg, b)
end
Elements.PaintResource = PaintResource

-- ----------------------------------------------------------------------------
--  Construction visuelle
-- ----------------------------------------------------------------------------
local function BarTexture()
    if ns.config.barStyle == "blizzard" then
        return "Interface\\TargetingFrame\\UI-StatusBar"
    end
    return ns.media.statusbar
end

-- trackColor : couleur de la piste (barre vide), {r,g,b}. CSS background du track.
local function CreateBar(parent, trackColor)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar:SetStatusBarTexture(BarTexture())
    bar:SetMinMaxValues(0, 1)
    bar:SetValue(1)
    local bg = bar:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture(ns.media.statusbar)
    local tc = trackColor
    if tc then bg:SetVertexColor(tc[1], tc[2], tc[3], 1) else bg:SetVertexColor(0, 0, 0, 0.15) end
    bar.bg = bg

    -- Ombre interne haute (box-shadow: inset 0 1px) : fine bande sombre degradee.
    if ns.config.glossy then
        local sh = bar:CreateTexture(nil, "BORDER")
        sh:SetTexture(ns.media.statusbar)
        sh:SetPoint("TOPLEFT")
        sh:SetPoint("TOPRIGHT")
        sh:SetHeight(2)
        if sh.SetGradient then
            sh:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0.55))
        else
            sh:SetVertexColor(0, 0, 0, 0.4)
        end
        bar.topShadow = sh
    end
    return bar
end

-- Gloss de la barre de VIE : overlay vertical (clair haut -> sombre bas) sur le
-- remplissage + liseré brillant 1px en haut + liseré sombre 1px sur le bord
-- meneur du remplissage. Traduction des linear-gradient/box-shadow de la maquette.
local function AddHealthGloss(bar, mirror)
    if not ns.config.glossy then return end
    local fill = bar:GetStatusBarTexture()
    if not fill then return end

    local gloss = bar:CreateTexture(nil, "ARTWORK", nil, 2)
    gloss:SetTexture(ns.media.statusbar)
    gloss:SetAllPoints(fill)
    if gloss.SetGradient then
        gloss:SetGradient("VERTICAL", CreateColor(0, 0, 0, 0.26), CreateColor(1, 1, 1, 0.14))
    end
    bar.gloss = gloss

    local hi = bar:CreateTexture(nil, "ARTWORK", nil, 3)
    hi:SetColorTexture(1, 1, 1, 0.32)
    hi:SetPoint("TOPLEFT", fill, "TOPLEFT", 0, 0)
    hi:SetPoint("TOPRIGHT", fill, "TOPRIGHT", 0, 0)
    hi:SetHeight(1)
    bar.glossHi = hi

    -- bord meneur du remplissage : droite en normal, gauche en miroir (reverse fill)
    local lead = mirror and "LEFT" or "RIGHT"
    local edge = bar:CreateTexture(nil, "ARTWORK", nil, 3)
    edge:SetColorTexture(0, 0, 0, 0.30)
    edge:SetPoint("TOP" .. lead, fill, "TOP" .. lead, 0, 0)
    edge:SetPoint("BOTTOM" .. lead, fill, "BOTTOM" .. lead, 0, 0)
    edge:SetWidth(1)
    bar.glossEdge = edge
end

-- Reflet haut de la barre de RESSOURCE : overlay sur la moitie haute du
-- remplissage (blanc .16 -> transparent). CSS linear-gradient top 50%.
local function AddPowerGloss(bar)
    if not ns.config.glossy then return end
    local fill = bar:GetStatusBarTexture()
    if not fill then return end
    local hi = bar:CreateTexture(nil, "ARTWORK", nil, 2)
    hi:SetTexture(ns.media.statusbar)
    hi:SetPoint("TOPLEFT", fill, "TOPLEFT", 0, 0)
    hi:SetPoint("TOPRIGHT", fill, "TOPRIGHT", 0, 0)
    hi:SetPoint("BOTTOM", fill, "CENTER", 0, 0)
    if hi.SetGradient then
        hi:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.16))
    end
    bar.gloss = hi
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

-- Badge de combat circulaire (maquette) : lueur orange + anneau + fond sombre
-- (masques ronds) + epees croisees. Traduction de border-radius:50% +
-- radial-gradient + border + box-shadow. Statique (pas de pulse, choix retenu).
-- Renvoie un Frame masque par defaut (Show/Hide via UpdateCombat).
local function BuildCombatBadge(frame)
    local cfg = frame.config
    local size = cfg.combatSize or 18
    local mirror = cfg.mirror
    local badge = CreateFrame("Frame", nil, frame)
    badge:SetSize(size, size)
    badge:SetPoint("CENTER", frame, mirror and "TOPLEFT" or "TOPRIGHT", 0, 0)
    badge:SetFrameLevel(frame:GetFrameLevel() + 5)

    -- box-shadow 0 0 6px rgba(255,90,20,.6) : lueur orange un peu plus grande
    local glow = badge:CreateTexture(nil, "BACKGROUND")
    glow:SetColorTexture(1.0, 0.35, 0.08, 0.45)
    glow:SetPoint("CENTER")
    glow:SetSize(size * 1.5, size * 1.5)
    AddCircleMask(glow)

    -- border:1px solid #ff6a2b : anneau orange (cercle plein, le fond le recouvre)
    local ring = badge:CreateTexture(nil, "BORDER")
    ring:SetColorTexture(1.0, 0.416, 0.169, 1)
    ring:SetAllPoints(badge)
    AddCircleMask(ring)

    -- radial-gradient(#401409 -> #190703) : fond sombre (aplat, approx)
    local fill = badge:CreateTexture(nil, "ARTWORK")
    fill:SetColorTexture(0.16, 0.05, 0.02, 1)
    fill:SetPoint("CENTER")
    fill:SetSize(size - 2, size - 2)
    AddCircleMask(fill)

    -- epees croisees (atlas) au centre
    local swords = badge:CreateTexture(nil, "ARTWORK", nil, 2)
    local p = COMBAT_PRESETS.combat
    ApplyCombatPreset(swords, p)
    if p.color then swords:SetVertexColor(p.color[1], p.color[2], p.color[3]) end
    swords:SetSize(size * 0.72, size * 0.72)
    swords:SetPoint("CENTER")

    badge:Hide()
    return badge
end

-- Construit l'indicateur de combat : badge circulaire (cfg.combatBadge + masques
-- dispo) ou, a defaut, l'icone plate historique (presets cfg.combatStyle).
local function BuildCombat(frame)
    local cfg = frame.config
    local mirror = cfg.mirror
    if cfg.combatBadge and ns.config.combatBadge and HAS_MASK then
        frame.combatIcon = BuildCombatBadge(frame)
        return
    end

    -- Repli : icone plate (comportement existant)
    local size = cfg.combatSize or 18
    local color
    local ci = frame.health:CreateTexture(nil, "OVERLAY")
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
    color = cfg.combatColor or color
    if color then ci:SetVertexColor(color[1], color[2], color[3]) end
    ci:SetSize(size, size)
    ci:SetPoint("CENTER", frame, mirror and "TOPLEFT" or "TOPRIGHT", 0, 0)
    ci:Hide()
    frame.combatIcon = ci
end

-- (Re)calcule la hauteur des barres vie/ressource selon cfg.height / powerRatio.
-- Logique partagee : appelee a la construction ET lors d'un changement de taille
-- a chaud (ns:ApplySize). La largeur suit toute seule via les ancres TOPLEFT/RIGHT.
function Elements.LayoutBars(frame)
    local cfg = frame.config
    local h = cfg.height
    local powerH = 0
    local sep = 0
    -- La barre de ressource ne compte que si elle est presente ET affichee
    -- (masquee pour les unites sans pouvoir : voir UpdatePower / hasRes v2).
    if frame.power and frame.powerShown ~= false then
        powerH = math.max(4, math.floor(h * (cfg.powerRatio or 0.25)))
        sep = INSET                       -- separateur 1px entre vie et ressource
        frame.power:SetHeight(powerH)
    end
    if frame.health then
        -- hauteur restante apres bords haut/bas (2*INSET) et separateur
        frame.health:SetHeight(h - powerH - 2 * INSET - sep)
    end
end

-- Applique la police de l'addon a un FontString SANS se fier a la valeur de
-- retour de SetFont (peu fiable sur ce client). Filet de securite : on pose
-- d'abord STANDARD_TEXT_FONT (police valide garantie -> jamais d'erreur "Font not
-- set"), puis on tente ns.media.font. Si elle ne charge pas, la precedente reste.
-- On enregistre le FontString (+ taille/flags) pour pouvoir RE-appliquer la police
-- une fois qu'elle est chargee : sur ce client, la police custom se charge de
-- maniere asynchrone, et le 1er texte cree (le nom) rate souvent l'application.
ns.fontStrings = ns.fontStrings or {}
local function ApplyFont(fs, size, flags)
    fs.mfSize, fs.mfFlags = size, flags or "OUTLINE"
    fs:SetFont(STANDARD_TEXT_FONT, size, fs.mfFlags)
    fs:SetFont(ns.media.font, size, fs.mfFlags)
    ns.fontStrings[fs] = true
end
ns.ApplyFont = ApplyFont

-- Re-applique la police a tous les FontStrings connus (apres chargement asynchrone).
function ns:RefreshFonts()
    for fs in pairs(ns.fontStrings) do
        if fs.mfSize then
            fs:SetFont(STANDARD_TEXT_FONT, fs.mfSize, fs.mfFlags)
            fs:SetFont(ns.media.font, fs.mfSize, fs.mfFlags)
        end
    end
end

-- Cree un FontString style "maquette" : OUTLINE (font-weight 700) + ombre
-- (text-shadow 0 1px 2px). Couleur posee par l'appelant.
local function NewText(parent, size)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    ApplyFont(fs, size, "OUTLINE")
    fs:SetShadowColor(0, 0, 0, 0.95)
    fs:SetShadowOffset(1, -1)
    return fs
end

-- Layout texte CONDENSE (tot/pet et tout cadre non player/target) : nom du cote
-- "exterieur", valeur du cote "interieur", sur une ligne.
local function BuildSimpleText(frame)
    local cfg = frame.config
    local mirror = cfg.mirror
    local health = frame.health
    local fontSize = cfg.fontSize or 11
    local inner = mirror and "LEFT" or "RIGHT"
    local outer = mirror and "RIGHT" or "LEFT"

    local htext = NewText(health, fontSize)
    htext:SetPoint(inner, health, inner, mirror and 3 or -3, 0)
    htext:SetJustifyH(inner)
    frame.healthText = htext

    local name = NewText(health, fontSize)
    name:SetPoint(outer, health, outer, mirror and -3 or 3, 0)
    name:SetPoint(inner, htext, outer, mirror and 2 or -2, 0)
    name:SetJustifyH(outer)
    name:SetWordWrap(false)
    frame.nameText = name
    if cfg.showName == false then name:Hide() end

    if frame.power and cfg.showPowerText then
        local ptext = NewText(frame.power, math.max(8, fontSize - 1))
        ptext:SetPoint(inner, frame.power, inner, mirror and 3 or -3, 0)
        ptext:SetJustifyH(inner)
        frame.powerText = ptext
    end
end

-- Layout texte 3 ZONES (player/target, maquette) : nom+niveau a GAUCHE,
-- pourcentage CENTRE, PV actuel / max a DROITE. Ordre identique pour le joueur
-- ET la cible (on n'inverse PAS selon mirror : seules les barres/badge suivent
-- le miroir, pas l'ordre des colonnes de texte).
local function BuildRichText(frame)
    local cfg = frame.config
    local health = frame.health
    local fontSize = cfg.fontSize or 11

    -- Colonne nom (blanc) + niveau (or) a gauche, calee autour du centre vertical
    local name = NewText(health, fontSize)
    name:SetTextColor(1, 1, 1)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    name:SetWidth((cfg.width or 190) * 0.44)        -- text-overflow:ellipsis -> troncature
    name:SetPoint("LEFT", health, "LEFT", 7, 6)
    frame.nameText = name
    if cfg.showName == false then name:Hide() end

    local level = NewText(health, math.max(8, fontSize - 2))
    level:SetTextColor(1.0, 0.875, 0.608)           -- ffdf9b
    level:SetJustifyH("LEFT")
    level:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -1)
    frame.levelText = level

    -- Colonne PV actuel (blanc) + / max (creme) a droite
    local hp = NewText(health, fontSize)
    hp:SetTextColor(1, 1, 1)
    hp:SetJustifyH("RIGHT")
    hp:SetPoint("RIGHT", health, "RIGHT", -7, 6)
    frame.healthText = hp

    local hpmax = NewText(health, math.max(8, fontSize - 2))
    hpmax:SetTextColor(0.914, 0.886, 0.847)         -- e9e2d8
    hpmax:SetJustifyH("RIGHT")
    hpmax:SetPoint("TOPRIGHT", hp, "BOTTOMRIGHT", 0, -1)
    frame.healthMaxText = hpmax

    -- Pourcentage centre (plus gros)
    local pct = NewText(health, fontSize + 4)
    pct:SetTextColor(1, 1, 1)
    pct:SetPoint("CENTER", health, "CENTER", 0, 0)
    frame.percentText = pct

    -- Textes de ressource : cur/max a gauche, % a droite
    if frame.power then
        local psize = math.max(8, fontSize - 3)
        local pcur = NewText(frame.power, psize)
        pcur:SetTextColor(0.933, 0.945, 0.965)      -- eef1f6
        pcur:SetJustifyH("LEFT")
        pcur:SetPoint("LEFT", frame.power, "LEFT", 7, 0)
        frame.powerText = pcur

        local ppct = NewText(frame.power, psize)
        ppct:SetTextColor(0.933, 0.945, 0.965)
        ppct:SetJustifyH("RIGHT")
        ppct:SetPoint("RIGHT", frame.power, "RIGHT", -7, 0)
        frame.powerPctText = ppct
    end

    frame.richText = true
end

-- Construit barres + textes (appele a la creation de chaque frame/bouton)
function Elements.BuildVisuals(frame)
    local cfg = frame.config
    local mirror = cfg.mirror

    -- Fond noir opaque couvrant tout le cadre : sert de bord 1px (autour) et de
    -- separateur 1px (entre vie et ressource), la ou les barres sont en retrait.
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetColorTexture(0, 0, 0, 1)
    frame.bg = bg

    -- Barre de vie (piste sombre maquette)
    local health = CreateBar(frame, ns.config.healthTrack)
    health:SetPoint("TOPLEFT", INSET, -INSET)
    health:SetPoint("TOPRIGHT", -INSET, -INSET)
    if mirror and health.SetReverseFill then health:SetReverseFill(true) end
    frame.health = health

    -- Barre de ressource (piste sombre maquette)
    if cfg.showPower then
        local power = CreateBar(frame, ns.config.powerTrack)
        power:SetPoint("BOTTOMLEFT", INSET, INSET)
        power:SetPoint("BOTTOMRIGHT", -INSET, INSET)
        if mirror and power.SetReverseFill then power:SetReverseFill(true) end
        frame.power = power
    end

    -- Hauteurs des deux barres (calcul partage, re-jouable a chaud)
    Elements.LayoutBars(frame)

    -- Reflets glossy (overlays + liseres), traduits des linear-gradient CSS
    AddHealthGloss(health, mirror)
    if frame.power then AddPowerGloss(frame.power) end

    -- Coins arrondis (best-effort, opt-in)
    if ns.config.roundedCorners then ApplyRoundedCorners(frame) end

    -- Textes : layout 3 zones pour player/target, condense sinon
    if frame.unitType == "player" or frame.unitType == "target" then
        BuildRichText(frame)
    else
        BuildSimpleText(frame)
    end

    -- Indicateur de combat (badge circulaire ou icone plate)
    if cfg.showCombat then BuildCombat(frame) end
end

-- (Re)ancre la 1re icone de buff : sous la barre de cast si elle est active,
-- sinon directement sous le cadre. Rejouable a chaud quand on bascule la barre
-- de cast (evite un trou vide a l'emplacement de la barre masquee).
function Elements.AnchorBuffs(frame)
    local icons = frame.buffIcons
    if not icons or not icons[1] then return end
    local cb = frame.castBar
    local below = (cb and cb.enabled ~= false) and cb or frame
    local btn = icons[1]
    btn:ClearAllPoints()
    if frame.config.mirror then
        btn:SetPoint("TOPRIGHT", below, "BOTTOMRIGHT", 0, -3)
    else
        btn:SetPoint("TOPLEFT", below, "BOTTOMLEFT", 0, -3)
    end
end

-- Construit les rangees de buffs/debuffs (sous le cadre / au-dessus, en miroir si besoin)
function Elements.CreateAuras(frame)
    local cfg = frame.config
    local max = cfg.numAuras or 0
    if max <= 0 then return end
    local size = cfg.auraSize or 18
    local mirror = cfg.mirror

    if cfg.showBuffs then
        frame.buffIcons = {}
        for i = 1, max do
            local btn = CreateAuraIcon(frame, size)
            if i > 1 then
                if mirror then btn:SetPoint("RIGHT", frame.buffIcons[i - 1], "LEFT", -3, 0)
                else btn:SetPoint("LEFT", frame.buffIcons[i - 1], "RIGHT", 3, 0) end
            end
            frame.buffIcons[i] = btn
        end
        Elements.AnchorBuffs(frame)   -- ancre la 1re icone (sous la barre de cast si active)
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

-- Colore la barre de cast selon l'interruptibilite (ns.castColors). Quand la
-- distinction est desactivee, tout sort prend la couleur "interruptible". Passe
-- par SetBarColor pour respecter le style global (gradient / flat / blizzard).
local function CastBar_Color(cb)
    local cc = ns.castColors or {}
    local distinguish = cc.distinguish ~= false
    local key = (distinguish and cb.notInterruptible) and "notInterruptible" or "interruptible"
    local c = cc[key]
    if c then
        SetBarColor(cb, c[1], c[2], c[3])
    elseif cb.notInterruptible and distinguish then
        SetBarColor(cb, 0.6, 0.6, 0.6)
    else
        SetBarColor(cb, 0.937, 0.788, 0.341)
    end
end

function Elements.CastBarCheck(frame)
    local cb = frame.castBar
    if not cb then return end
    if cb.enabled == false then CastBar_Reset(cb); return end
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
    ApplyFont(text, cfg.fontSize or 11, "OUTLINE")
    text:SetPoint("LEFT", cb, "LEFT", 3, 0)
    text:SetPoint("RIGHT", cb, "RIGHT", -3, 0)
    text:SetJustifyH(mirror and "RIGHT" or "LEFT")
    text:SetWordWrap(false)
    cb.text = text

    cb.owner = frame
    -- Etat actif : derive de la config (defaut = affichee). Une barre desactivee
    -- reste creee mais ne s'affiche jamais (CastBarCheck court-circuite).
    cb.enabled = cfg.showCastBar ~= false
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
    -- Couleur unie (classe ou reaction/perso) ; le relief vient du gloss vertical.
    local r, g, b = Elements.GetClassColors(unit, frame.config)
    if not r then r, g, b = Elements.GetUnitColor(unit, frame.config) end
    PaintBar(bar, r, g, b, r, g, b)

    local cfg = frame.config
    if frame.richText then
        -- 3 zones : PV actuel / max separes + pourcentage centre
        if frame.healthText then
            frame.healthText:SetText((cfg.showHealthValue and max > 0) and FormatNumber(cur) or "")
        end
        if frame.healthMaxText then
            frame.healthMaxText:SetText((cfg.showHealthValue and max > 0) and ("/ " .. FormatNumber(max)) or "")
        end
        if frame.percentText then
            if cfg.showPercent and max > 0 then
                frame.percentText:SetText(string.format("%d%%", math.floor(cur / max * 100 + 0.5)))
            else
                frame.percentText:SetText("")
            end
        end
    elseif frame.healthText then
        -- layout condense : valeur + pourcentage sur une ligne
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

    -- hasRes (maquette v2) : masque la barre de ressource si l'unite n'a pas de
    -- pouvoir (PNJ sans mana, etc.) et agrandit la vie. Re-layout uniquement au
    -- changement d'etat (pas a chaque tick de ressource).
    local hasPower = max and max > 0
    if hasPower ~= (frame.powerShown ~= false) then
        frame.powerShown = hasPower
        if hasPower then frame.power:Show() else frame.power:Hide() end
        Elements.LayoutBars(frame)
    end
    if not hasPower then return end

    local bar = frame.power
    bar:SetMinMaxValues(0, max > 0 and max or 1)
    bar:SetValue(cur)
    local ptype, ptoken = UnitPowerType(unit)
    -- Degrade vertical (maquette) ou couleur unie selon barStyle ; respecte les
    -- couleurs personnalisees via /mf config (cf. PaintResource).
    PaintResource(bar, ptype, ptoken)

    if frame.richText then
        if frame.powerText then
            frame.powerText:SetText(max > 0 and (FormatNumber(cur) .. " / " .. FormatNumber(max)) or "")
        end
        if frame.powerPctText then
            frame.powerPctText:SetText(max > 0 and string.format("%d%%", math.floor(cur / max * 100 + 0.5)) or "")
        end
    elseif frame.powerText then
        frame.powerText:SetText(max > 0 and FormatNumber(cur) or "")
    end
end

function Elements.UpdateName(frame)
    local unit = frame.unit
    if not unit or not UnitExists(unit) then return end
    if not frame.nameText then return end
    local cfg = frame.config

    if frame.richText then
        -- Maquette : nom blanc, niveau dans une zone separee (or, ou couleur de
        -- difficulte si cfg.levelDifficultyColor).
        frame.nameText:SetText(UnitName(unit) or "")
        frame.nameText:SetTextColor(1, 1, 1)
        if frame.levelText then
            if cfg.showLevel then
                local lvl = UnitLevel(unit)
                local lvlStr = (lvl and lvl > 0) and tostring(lvl) or "??"
                frame.levelText:SetText(lvlStr)
                if cfg.levelDifficultyColor and GetQuestDifficultyColor then
                    local col = GetQuestDifficultyColor((lvl and lvl > 0) and lvl or 999)
                    frame.levelText:SetTextColor(col.r, col.g, col.b)
                else
                    frame.levelText:SetTextColor(1.0, 0.875, 0.608)
                end
            else
                frame.levelText:SetText("")
            end
        end
        return
    end

    -- Layout condense : niveau en prefixe + nom colore par classe/reaction
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
    local r, g, b = Elements.GetClassColors(unit, cfg)
    if not r then r, g, b = Elements.GetUnitColor(unit, cfg) end
    frame.nameText:SetTextColor(r, g, b)
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
