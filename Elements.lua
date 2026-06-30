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
        return data.name, data.icon, data.applications, data.dispelName, data.duration,
            data.expirationTime, data.sourceUnit
    end
else
    GetAura = function(unit, index, filter)
        -- name, icon, count, dispelType, duration, expirationTime, source(unitCaster), ...
        local name, icon, count, dispelType, duration, expiration, source = UnitAura(unit, index, filter)
        return name, icon, count, dispelType, duration, expiration, source
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

-- Segment "bouclier d'absorption" facon UI Blizzard. Le max LOGIQUE de la barre
-- de vie est agrandi a (PV max + absorb) dans UpdateHealth, sans changer sa largeur
-- physique : la vie occupe alors cur/total et ce segment clair occupe la portion
-- absorb/total JUSTE APRES le remplissage de vie. On l'ancre au bord meneur du
-- remplissage (sa droite en normal, sa gauche en miroir) pour qu'il suive
-- automatiquement la position de la vie ; seule sa largeur est (re)posee a chaque
-- UpdateHealth. Texture translucide blanc-bleute + fin lisere brillant sur le bord
-- exterieur. Masque tant qu'il n'y a pas d'absorption.
local function BuildAbsorb(frame)
    local bar = frame.health
    local fill = bar:GetStatusBarTexture()
    if not fill then return end
    local mirror = frame.config.mirror

    local seg = bar:CreateTexture(nil, "ARTWORK", nil, 5)
    seg:SetTexture(ns.media.statusbar)
    seg:SetVertexColor(0.85, 0.90, 1.0, 0.45)
    if mirror then
        seg:SetPoint("TOPRIGHT", fill, "TOPLEFT", 0, 0)
        seg:SetPoint("BOTTOMRIGHT", fill, "BOTTOMLEFT", 0, 0)
    else
        seg:SetPoint("TOPLEFT", fill, "TOPRIGHT", 0, 0)
        seg:SetPoint("BOTTOMLEFT", fill, "BOTTOMRIGHT", 0, 0)
    end
    seg:Hide()
    frame.absorb = seg

    -- lisere 1px brillant sur le bord exterieur du segment (cote oppose a la vie)
    local edge = bar:CreateTexture(nil, "ARTWORK", nil, 6)
    edge:SetColorTexture(1, 1, 1, 0.6)
    local outer = mirror and "LEFT" or "RIGHT"
    edge:SetPoint("TOP" .. outer, seg, "TOP" .. outer, 0, 0)
    edge:SetPoint("BOTTOM" .. outer, seg, "BOTTOM" .. outer, 0, 0)
    edge:SetWidth(1)
    edge:Hide()
    frame.absorbEdge = edge
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
    -- On garde le balayage radial (duree du buff/debuff) mais on masque le
    -- texte de temps restant : a la place on affiche le nombre de stacks.
    cd:SetHideCountdownNumbers(true)
    -- Inverse le sens clair/sombre du balayage (sans changer la rotation) :
    -- aura claire quand il reste toute la duree, qui s'assombrit en se terminant.
    cd:SetReverse(true)
    btn.cd = cd

    -- Compteur de stacks : enfant du cooldown pour rester visible au-dessus du
    -- balayage.
    local count = cd:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    count:SetPoint("BOTTOMRIGHT", 1, -1)
    btn.count = count

    -- Tooltip au survol : l'unite, l'index reel de l'aura et le filtre sont
    -- (re)stockes a chaque UpdateAuras (cf. FillAuras). GameTooltip n'est pas
    -- protege : utilisable meme en combat.
    btn:EnableMouse(true)
    btn:SetScript("OnEnter", function(self)
        if not self.auraIndex or not self.unit then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetUnitAura(self.unit, self.auraIndex, self.filter)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

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

-- Filet de securite (maquette v3, disposition empilee) : reduit la police du nom
-- jusqu'a ce qu'il tienne dans la largeur disponible (de fontSize jusqu'a 7px), au
-- lieu d'etre tronque par l'ellipsis. N'agit qu'en disposition empilee (le nom y a
-- deux ancres horizontales -> GetWidth() donne la largeur dispo). Sans cout si le
-- nom tient deja a sa taille nominale. Si la mise en page n'est pas encore resolue
-- (GetWidth ~ 0), on s'abstient : l'ellipsis sert de repli en attendant le prochain
-- UpdateName (changement de cible / nom), ou la passe differee de ns:SetTextLayout.
local NAME_MIN_FONT = 7
local function FitNameToWidth(frame)
    local name = frame.nameText
    if not name then return end
    local avail = name:GetWidth()
    if not avail or avail <= 1 then return end
    local maxS = frame.config.fontSize or 11
    ns.ApplyFont(name, maxS, "OUTLINE")
    local size = maxS
    while size > NAME_MIN_FONT and name:GetStringWidth() > avail do
        size = size - 0.5
        ns.ApplyFont(name, size, "OUTLINE")
    end
end
Elements.FitNameToWidth = FitNameToWidth

-- (Re)pose les ancres horizontales du NOM des cadres riches selon la disposition ET
-- la presence de l'icone de classification : icone visible => le nom commence apres
-- elle ; sinon il s'aligne sur le bord gauche du cadre (meme x que les cadres sans
-- icone, ex. player). Source unique de verite, appelee par LayoutRichText (mise en
-- page) ET par UpdateClassification (apparition/disparition de l'icone) — c'est ce
-- qui evite le decalage du nom sur les unites sans dragon.
local function AnchorRichName(frame)
    local name = frame.nameText
    if not name then return end
    local health = frame.health
    local hasIcon = frame.classIcon and frame.classIcon:IsShown()
    name:ClearAllPoints()
    if frame.stackedText then
        if hasIcon then
            name:SetPoint("LEFT", frame.classIcon, "RIGHT", 2, 0)
        else
            name:SetPoint("LEFT", health, "LEFT", 7, 7)
        end
        name:SetPoint("RIGHT", frame.levelText, "LEFT", -4, 0)
        FitNameToWidth(frame)   -- la largeur dispo a change : re-ajuste la taille
    else
        if hasIcon then
            name:SetPoint("LEFT", frame.classIcon, "RIGHT", 3, 0)
        else
            name:SetPoint("LEFT", health, "LEFT", 7, 6)
        end
    end
end
Elements.AnchorRichName = AnchorRichName

-- Place/dimensionne les FontStrings du layout riche (nom / niveau / % / PV) selon
-- ns.config.textLayout. RE-JOUABLE A CHAUD (bascule de disposition sans /reload) :
-- on efface les ancres et on re-applique tailles + points. Les deux dispositions
-- reutilisent les MEMES FontStrings ; seules positions/tailles/justifications
-- different (le CONTENU est identique, donc UpdateHealth/UpdateName/UpdatePower
-- restent inchangees). Les couleurs sont posees une fois a la construction.
-- frame.stackedText memorise le mode (auto-fit du nom dans UpdateName).
--
--   "stacked" (maquette v3) : nom pleine largeur en haut + niveau a droite ;
--                             pourcentage (gauche) et PV (droite) sur la ligne du bas.
--   "classic" (historique)  : nom+niveau a gauche, pourcentage centre, PV a droite.
-- modeOverride (optionnel) : force "classic"/"stacked" sans toucher au reglage
-- global (utilise par les cartes d'apercu de /mf config qui montrent les DEUX
-- dispositions cote a cote). Absent => suit ns.config.textLayout.
function Elements.LayoutRichText(frame, modeOverride)
    if not frame.richText then return end
    local cfg = frame.config
    local fontSize = cfg.fontSize or 11
    local stacked = ((modeOverride or ns.config.textLayout) == "stacked")
    frame.stackedText = stacked

    local name, level = frame.nameText, frame.levelText
    local hp, hpmax, pct = frame.healthText, frame.healthMaxText, frame.percentText
    local health = frame.health

    for _, fs in ipairs({ name, level, hp, hpmax, pct }) do
        fs:ClearAllPoints()
        fs:SetWidth(0)
    end

    if stacked then
        -- row = decalage vertical (depuis le centre de la barre) de chaque ligne :
        -- ligne du haut a +row, ligne du bas a -row => espacement inter-lignes = 2*row.
        local pad, row = 7, 7
        -- Taille des PV bas-droite : un cran sous le nom/% (suit cfg.fontSize).
        local hpSize = math.max(9, fontSize - 2)
        -- Niveau : haut-droite, petit (9px, ffdf9b)
        ns.ApplyFont(level, 9, "OUTLINE")
        level:SetJustifyH("RIGHT")
        level:SetPoint("RIGHT", health, "RIGHT", -pad, row)
        -- Nom : ligne du haut, de la gauche jusqu'a la gauche du niveau (ellipsis ou
        -- auto-fit via FitNameToWidth). Deux ancres horizontales => largeur implicite.
        ns.ApplyFont(name, fontSize, "OUTLINE")
        name:SetJustifyH("LEFT")
        -- Icone de classification a gauche du nom (bord gauche de la ligne du haut).
        if frame.classIcon then
            frame.classIcon:ClearAllPoints()
            frame.classIcon:SetPoint("LEFT", health, "LEFT", pad, row)
        end
        -- Ancres du nom (LEFT selon icone visible, RIGHT avant le niveau) : centralise
        -- dans AnchorRichName pour rester coherent avec UpdateClassification.
        AnchorRichName(frame)
        -- Pourcentage : bas-gauche (12px, maquette)
        ns.ApplyFont(pct, 12, "OUTLINE")
        pct:SetJustifyH("LEFT")
        pct:SetPoint("LEFT", health, "LEFT", pad, -row)
        -- PV : bas-droite, "actuel" suivi de "/ max" cote a cote
        ns.ApplyFont(hpmax, hpSize, "OUTLINE")
        hpmax:SetJustifyH("RIGHT")
        hpmax:SetPoint("RIGHT", health, "RIGHT", -pad, -row)
        ns.ApplyFont(hp, hpSize, "OUTLINE")
        hp:SetJustifyH("RIGHT")
        hp:SetPoint("RIGHT", hpmax, "LEFT", -3, 0)
    else
        -- Colonne nom (blanc) + niveau (or) a gauche, calee autour du centre vertical.
        -- Icone de classification a gauche du nom : on reserve sa largeur en
        -- retrecissant un peu le nom (largeur fixe a ellipsis) pour ne pas empieter
        -- sur le pourcentage centre.
        ns.ApplyFont(name, fontSize, "OUTLINE")
        name:SetJustifyH("LEFT")
        name:SetWidth((cfg.width or 190) * 0.44 - (frame.classIcon and 18 or 0))
        if frame.classIcon then
            frame.classIcon:ClearAllPoints()
            frame.classIcon:SetPoint("LEFT", health, "LEFT", 6, 6)
        end
        -- Ancre gauche du nom (apres l'icone si visible, sinon bord du cadre).
        AnchorRichName(frame)

        ns.ApplyFont(level, math.max(8, fontSize - 2), "OUTLINE")
        level:SetJustifyH("LEFT")
        level:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -1)

        -- Colonne PV actuel (blanc) + / max (creme) a droite
        ns.ApplyFont(hp, fontSize, "OUTLINE")
        hp:SetJustifyH("RIGHT")
        hp:SetPoint("RIGHT", health, "RIGHT", -7, 6)

        ns.ApplyFont(hpmax, math.max(8, fontSize - 2), "OUTLINE")
        hpmax:SetJustifyH("RIGHT")
        hpmax:SetPoint("TOPRIGHT", hp, "BOTTOMRIGHT", 0, -1)

        -- Pourcentage centre (plus gros)
        ns.ApplyFont(pct, fontSize + 4, "OUTLINE")
        pct:SetJustifyH("CENTER")
        pct:SetPoint("CENTER", health, "CENTER", 0, 0)
    end
end

-- ----------------------------------------------------------------------------
--  Icone de classification (dragon facon nameplate) — posee A GAUCHE du nom.
--  Reprend l'artwork "dragon" Blizzard via les atlas de nameplate :
--    worldboss -> dragon OR + halo scintillant (star4)  [le seul a pulser]
--    elite     -> dragon OR
--    rare/rareelite -> dragon ARGENT
--    normal/minus   -> rien (icone masquee)
-- ----------------------------------------------------------------------------
local CLASS_GOLD       = "nameplates-icon-elite-gold"
local CLASS_SILVER     = "nameplates-icon-elite-silver"
local CLASS_GLOW_TEX   = "Interface\\Cooldown\\star4"   -- etoile 4 branches (scintille)
local CLASS_GLOW_COLOR = { 1, 0.82, 0.25 }              -- teinte or du halo
local CLASSIFICATIONS  = {
    worldboss = { atlas = CLASS_GOLD,   glow = true },
    elite     = { atlas = CLASS_GOLD },
    rareelite = { atlas = CLASS_SILVER },
    rare      = { atlas = CLASS_SILVER },
}

-- Scintillement DOUX du halo worldboss : simple pulsation d'alpha de faible
-- amplitude (PAS de rotation). Pilote par une frame-ticker (frame.classAnim) active
-- seulement quand le halo est affiche (cf. UpdateClassification) : aucun cout hors
-- worldboss.
local CLASS_PULSE_PERIOD = 2.0   -- secondes par cycle de pulsation
local CLASS_ALPHA_MIN    = 0.38  -- bornes d'alpha resserrees autour de 0.55
local CLASS_ALPHA_MAX    = 0.62
local TWO_PI = math.pi * 2
local function ClassGlow_OnUpdate(self, elapsed)
    local t = (self.t or 0) + elapsed
    self.t = t
    local k = 0.5 * (1 + math.sin(t / CLASS_PULSE_PERIOD * TWO_PI))
    self.glow:SetAlpha(CLASS_ALPHA_MIN + (CLASS_ALPHA_MAX - CLASS_ALPHA_MIN) * k)
end

-- Cree la texture du dragon (+ son halo star4). Posee sur la barre de vie, son
-- placement exact (avant le niveau) est gere par LayoutRichText. Masquee tant que
-- UpdateClassification n'a pas valide une classification "interessante".
local function BuildClassIcon(frame)
    local size = frame.config.classSize or 16

    -- Halo scintillant (sous le dragon), additif et teinte or. Fige (le "C4"
    -- choisi). N'apparait que pour les worldboss (cf. UpdateClassification).
    local glow = frame.health:CreateTexture(nil, "OVERLAY", nil, 1)
    glow:SetTexture(CLASS_GLOW_TEX)
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(CLASS_GLOW_COLOR[1], CLASS_GLOW_COLOR[2], CLASS_GLOW_COLOR[3])
    glow:SetAlpha(0.55)
    glow:SetSize(size * 1.9, size * 1.9)
    glow:Hide()
    frame.classGlow = glow

    local icon = frame.health:CreateTexture(nil, "OVERLAY", nil, 2)
    icon:SetSize(size, size)
    icon:Hide()
    frame.classIcon = icon

    glow:SetPoint("CENTER", icon, "CENTER")

    -- Ticker d'animation du halo (rotation + pulsation douces). Une frame ne
    -- declenche OnUpdate que tant qu'elle est affichee : on l'active/desactive via
    -- Show/Hide (UpdateClassification).
    local anim = CreateFrame("Frame", nil, frame.health)
    anim.glow = glow
    anim:SetScript("OnUpdate", ClassGlow_OnUpdate)
    anim:Hide()
    frame.classAnim = anim
end

-- Layout texte des cadres riches (player/target/focus). Cree les FontStrings
-- (couleurs + word-wrap communs aux deux dispositions) puis delegue le
-- positionnement a LayoutRichText selon ns.config.textLayout.
local function BuildRichText(frame)
    local cfg = frame.config
    local health = frame.health
    local fontSize = cfg.fontSize or 11

    local name = NewText(health, fontSize)
    name:SetTextColor(1, 1, 1)
    name:SetWordWrap(false)
    frame.nameText = name
    if cfg.showName == false then name:Hide() end

    local level = NewText(health, fontSize)
    level:SetTextColor(1.0, 0.875, 0.608)           -- ffdf9b
    level:SetWordWrap(false)
    frame.levelText = level

    local hp = NewText(health, fontSize)
    hp:SetTextColor(1, 1, 1)
    frame.healthText = hp

    local hpmax = NewText(health, fontSize)
    hpmax:SetTextColor(0.914, 0.886, 0.847)         -- e9e2d8
    frame.healthMaxText = hpmax

    local pct = NewText(health, fontSize)
    pct:SetTextColor(1, 1, 1)
    frame.percentText = pct

    -- Textes de ressource : cur/max a gauche, % a droite (communs aux 2 dispositions)
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

    -- Icone de classification (dragon elite/rare) avant le niveau, si demandee.
    if cfg.showClassification then BuildClassIcon(frame) end

    frame.richText = true
    Elements.LayoutRichText(frame)
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

    -- Segment bouclier d'absorption (masque tant qu'il n'y a pas d'absorb)
    BuildAbsorb(frame)

    -- Coins arrondis (best-effort, opt-in)
    if ns.config.roundedCorners then ApplyRoundedCorners(frame) end

    -- Textes : layout 3 zones pour player/target/focus, condense sinon
    if frame.unitType == "player" or frame.unitType == "target" or frame.unitType == "focus" then
        BuildRichText(frame)
    else
        BuildSimpleText(frame)
    end

    -- Indicateur de combat (badge circulaire ou icone plate)
    if cfg.showCombat then BuildCombat(frame) end
end

-- ----------------------------------------------------------------------------
--  Ancrage des rangees d'auras (buffs / debuffs) — parametrable PAR CADRE et
--  PAR TYPE via cfg.buffAnchor / cfg.debuffAnchor (voir Config.lua). Chaque bloc
--  d'ancrage est optionnel ; les champs absents retombent sur le defaut ci-dessous
--  (lui-meme derive de cfg.mirror pour rester coherent avec le reste du cadre).
-- ----------------------------------------------------------------------------

-- Pas entre deux icones consecutives, selon la direction de croissance demandee.
-- Les rangees horizontales (RIGHT/LEFT) chainent par le bord BAS : toutes les
-- icones partagent une meme ligne de base, donc une icone plus grosse (option
-- "les miennes plus grosses") depasse vers le HAUT au lieu de decentrer la rangee.
-- Idem pour les rangees verticales (DOWN/UP) qui s'alignent sur le bord GAUCHE.
-- Pour des icones de meme taille, l'ancrage par bord est identique a un ancrage
-- centre : aucun changement de rendu dans le cas courant.
local AURA_GROWTH = {
    RIGHT = { point = "BOTTOMLEFT",  rel = "BOTTOMRIGHT", x = 3,  y = 0  },
    LEFT  = { point = "BOTTOMRIGHT", rel = "BOTTOMLEFT",  x = -3, y = 0  },
    DOWN  = { point = "TOPLEFT",     rel = "BOTTOMLEFT",  x = 0,  y = -3 },
    UP    = { point = "BOTTOMLEFT",  rel = "TOPLEFT",     x = 0,  y = 3  },
}

-- Ancre par defaut d'un type ("buffs"/"debuffs") selon le mode miroir.
-- buffs   : rangee sous la barre de cast (repli : sous le cadre), croissance laterale.
-- debuffs : rangee au-dessus du cadre, croissance laterale.
local function DefaultAuraAnchor(kind, mirror)
    if kind == "buffs" then
        if mirror then
            return { point = "TOPRIGHT", relTo = "castbar", relPoint = "BOTTOMRIGHT", x = 0, y = -3, growth = "LEFT" }
        end
        return { point = "TOPLEFT", relTo = "castbar", relPoint = "BOTTOMLEFT", x = 0, y = -3, growth = "RIGHT" }
    else
        if mirror then
            return { point = "BOTTOMRIGHT", relTo = "frame", relPoint = "TOPRIGHT", x = 0, y = 3, growth = "LEFT" }
        end
        return { point = "BOTTOMLEFT", relTo = "frame", relPoint = "TOPLEFT", x = 0, y = 3, growth = "RIGHT" }
    end
end

-- Fusionne le bloc utilisateur (cfg.buffAnchor / cfg.debuffAnchor) sur le defaut.
-- Public (utilise aussi par Options.lua pour pre-remplir l'onglet "Auras").
function Elements.GetResolvedAuraAnchor(cfg, kind)
    local def = DefaultAuraAnchor(kind, cfg and cfg.mirror)
    local user = cfg and ((kind == "buffs") and cfg.buffAnchor or cfg.debuffAnchor)
    if user then
        for k, v in pairs(user) do def[k] = v end
    end
    return def
end

local function ResolveAuraAnchor(frame, kind)
    return Elements.GetResolvedAuraAnchor(frame.config, kind)
end

-- (Re)ancre une rangee d'icones d'auras. relTo = "castbar" suit la barre de cast
-- quand elle est active (repli sur le cadre), ce qui evite un trou vide quand on
-- bascule la barre via /mf config. Rejouable a chaud.
--
-- La barre de cast est placee SOUS le cadre : la suivre n'a de sens que pour une
-- rangee qui "pend" sous sa cible (point en TOP*, relPoint en BOTTOM*). Pour tout
-- autre placement (dessus, gauche/droite...), la barre n'est pas intercalee entre
-- le cadre et la rangee : on ignore le suivi et on ancre au cadre, sinon le
-- rendu differe selon que la barre est affichee ou non (ex. "Dessus" basculait
-- les buffs a l'interieur du cadre quand la barre etait active).
function Elements.AnchorAuraRow(frame, icons, kind)
    if not icons or not icons[1] then return end
    local a = ResolveAuraAnchor(frame, kind)

    local relTarget = frame
    if a.relTo == "castbar" then
        local hangsBelow = (a.point or ""):sub(1, 3) == "TOP"
            and (a.relPoint or ""):sub(1, 6) == "BOTTOM"
        local cb = frame.castBar
        if hangsBelow and cb and cb.enabled ~= false then
            relTarget = cb
        end
    end

    local g = AURA_GROWTH[a.growth] or AURA_GROWTH.RIGHT

    -- Disposition en grille : on remplit une ligne de cfg.numAuras icones, puis on
    -- saute a la ligne suivante sur l'axe perpendiculaire a la croissance. Le sens
    -- du saut decoule du point d'ancrage : ancree en haut (TOP*) la grille empile
    -- ses lignes vers le BAS, ancree en bas (BOTTOM*) vers le HAUT ; idem
    -- lateralement pour les croissances verticales (UP/DOWN).
    local perRow = frame.config.numAuras or #icons
    if perRow < 1 then perRow = #icons end

    local horizontal = (a.growth == "RIGHT" or a.growth == "LEFT")
    -- Hauteur effective d'une ligne : avec l'option "les miennes plus grosses",
    -- une ligne peut contenir des icones agrandies (mineSize). On dimensionne donc
    -- le pas inter-lignes sur la plus grande taille possible, sinon la ligne
    -- suivante chevauche les icones agrandies de la precedente.
    local baseSize = frame.config.auraSize or 18
    local bigMine = (kind == "buffs") and frame.config.buffBigMine
        or (kind == "debuffs") and frame.config.debuffBigMine
    local rowSize = baseSize
    if bigMine then
        rowSize = math.floor(baseSize * (frame.config.auraMineScale or 1.3) + 0.5)
    end
    local rowStep = rowSize + 3
    local rdx, rdy = 0, 0
    if horizontal then
        rdy = ((a.point or ""):sub(1, 3) == "TOP") and -rowStep or rowStep
    else
        rdx = ((a.point or ""):sub(-4) == "LEFT") and rowStep or -rowStep
    end

    for i = 1, #icons do
        local icon = icons[i]
        icon:ClearAllPoints()
        if i == 1 then
            icon:SetPoint(a.point, relTarget, a.relPoint, a.x or 0, a.y or 0)
        elseif (i - 1) % perRow == 0 then
            -- premiere icone d'une nouvelle ligne : alignee sous/au-dessus (ou a
            -- cote) de la premiere icone de la ligne precedente.
            icon:SetPoint(a.point, icons[i - perRow], a.point, rdx, rdy)
        else
            icon:SetPoint(g.point, icons[i - 1], g.rel, g.x, g.y)
        end
    end
end

-- (Re)ancre les deux rangees (buffs + debuffs) d'un cadre.
function Elements.AnchorAuras(frame)
    Elements.AnchorAuraRow(frame, frame.buffIcons, "buffs")
    Elements.AnchorAuraRow(frame, frame.debuffIcons, "debuffs")
end

-- Construit / redimensionne la grille d'icones d'un type. cfg.numAuras = icones
-- PAR LIGNE ; cfg.maxAuraRows = nombre de lignes max (defaut 1). Total d'icones =
-- numAuras * maxAuraRows. cfg.numAuras = 0 => rien.
--
-- Les icones vivent dans un POOL persistant (buffIconPool / debuffIconPool) qui ne
-- fait que grandir : on ne detruit jamais une frame (impossible en WoW de toute
-- facon) et on reutilise les icones excedentaires. La liste ACTIVE (buffIcons /
-- debuffIcons) reference les `needed` premieres du pool ; le surplus est masque.
-- Rejouable a chaud autant qu'on veut (un drag de slider numAuras/maxAuraRows ne
-- cree donc pas une frame a chaque tick).
local function BuildAuraRow(frame, kind)
    local cfg = frame.config
    local perRow = cfg.numAuras or 0
    local rows = cfg.maxAuraRows or 1
    if rows < 1 then rows = 1 end
    local needed = (perRow > 0) and (perRow * rows) or 0
    local size = cfg.auraSize or 18

    local poolKey = (kind == "buffs") and "buffIconPool" or "debuffIconPool"
    local pool = frame[poolKey]
    if not pool then pool = {}; frame[poolKey] = pool end

    -- Cree les icones manquantes (le pool ne fait que grandir).
    for i = #pool + 1, needed do
        pool[i] = CreateAuraIcon(frame, size)
    end
    -- Masque le surplus au-dela du besoin courant.
    for i = needed + 1, #pool do
        pool[i]:Hide()
    end

    -- Liste active = les `needed` premieres du pool, remises a la taille courante
    -- (FillAuras la re-applique aussi, mais on la pose ici pour que l'ancrage et
    -- l'apercu soient corrects meme sans unite chargee).
    local active = {}
    for i = 1, needed do
        local ic = pool[i]
        ic:SetSize(size, size)
        active[i] = ic
    end
    if kind == "buffs" then frame.buffIcons = active else frame.debuffIcons = active end
    return active
end

-- Construit les rangees de buffs/debuffs (l'ancrage est gere par AnchorAuras).
function Elements.CreateAuras(frame)
    local cfg = frame.config
    if (cfg.numAuras or 0) <= 0 then return end
    if cfg.showBuffs   then BuildAuraRow(frame, "buffs")   end
    if cfg.showDebuffs then BuildAuraRow(frame, "debuffs") end
    Elements.AnchorAuras(frame)
end

-- Reconstruit a chaud la grille (apres un changement de numAuras / maxAuraRows /
-- auraSize via /mf config). Ne reconstruit que les types deja batis (un type
-- masque n'a pas de liste active ; il sera bati a la volee par SetAuraTypeShown).
-- Re-ancre + re-remplit pour refleter la nouvelle disposition immediatement.
function Elements.RebuildAuraGrid(frame)
    local cfg = frame.config
    if cfg.showBuffs   and frame.buffIcons   then BuildAuraRow(frame, "buffs")   end
    if cfg.showDebuffs and frame.debuffIcons then BuildAuraRow(frame, "debuffs") end
    Elements.AnchorAuras(frame)
    Elements.UpdateAuras(frame)
end

-- Bascule a chaud l'affichage d'un type d'aura (buffs/debuffs). Construit la
-- rangee a la demande si elle n'existait pas (cas ou le type etait masque a la
-- creation). Les icones d'aura sont de simples Frames non protegees : pas de
-- restriction de combat.
function Elements.SetAuraTypeShown(frame, kind, shown)
    local cfg = frame.config
    if kind == "buffs" then cfg.showBuffs = shown else cfg.showDebuffs = shown end
    local icons = (kind == "buffs") and frame.buffIcons or frame.debuffIcons
    if shown then
        -- Toujours (re)batir : BuildAuraRow est idempotent (pool) et garantit que le
        -- compte / la taille refletent ns.config, meme si numAuras / maxAuraRows /
        -- auraSize ont change pendant que le type etait masque.
        icons = BuildAuraRow(frame, kind)
        if icons then
            Elements.AnchorAuras(frame)
            Elements.UpdateAuras(frame)
        end
    elseif icons then
        for _, b in ipairs(icons) do b:Hide() end
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
    if event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_FOCUS_CHANGED" then
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
    elseif frame.unit == "focus" then
        cb:RegisterEvent("PLAYER_FOCUS_CHANGED")
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
    local cfg = frame.config
    local cur, max = UnitHealth(unit), UnitHealthMax(unit)
    local bar = frame.health

    -- Bouclier d'absorption (UI Blizzard) : on agrandit le max LOGIQUE de la barre
    -- a (PV max + absorb) sans toucher a sa largeur physique. La vie occupe alors
    -- cur/total et le segment bouclier occupe absorb/total juste apres (cf.
    -- BuildAbsorb). Le texte et le pourcentage restent calcules sur les VRAIS PV
    -- (cur/max) : 100% ne traque que les PV, jamais les boucliers.
    local absorb = 0
    if cfg.showAbsorb ~= false and UnitGetTotalAbsorbs then
        absorb = UnitGetTotalAbsorbs(unit) or 0
        if absorb < 0 then absorb = 0 end
    end
    local total = max + absorb

    bar:SetMinMaxValues(0, total > 0 and total or 1)
    bar:SetValue(cur)

    -- Largeur du segment bouclier, proportionnelle a absorb/total. Ancre deja posee
    -- (BuildAbsorb) au bord meneur du remplissage : il suit la vie automatiquement.
    if frame.absorb then
        local w = (absorb > 0 and total > 0) and bar:GetWidth() or 0
        if w and w > 0 then
            frame.absorb:SetWidth(math.max(1, w * absorb / total))
            frame.absorb:Show()
            if frame.absorbEdge then frame.absorbEdge:Show() end
        else
            frame.absorb:Hide()
            if frame.absorbEdge then frame.absorbEdge:Hide() end
        end
    end

    -- Couleur unie (classe ou reaction/perso) ; le relief vient du gloss vertical.
    local r, g, b = Elements.GetClassColors(unit, frame.config)
    if not r then r, g, b = Elements.GetUnitColor(unit, frame.config) end
    PaintBar(bar, r, g, b, r, g, b)
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
        -- Disposition empilee : ajuste la taille du nom apres avoir pose nom ET
        -- niveau (le bord droit du nom depend de la largeur du niveau).
        if frame.stackedText then FitNameToWidth(frame) end
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

-- Plafond de balayage des index d'aura : avec le filtre "seulement les miennes",
-- mes auras peuvent se trouver au-dela des premieres cases (l'unite a beaucoup
-- d'auras d'autres lanceurs). On parcourt donc tous les index et on ne remplit
-- que les cases disponibles avec les auras retenues.
local MAX_AURA_SCAN = 40

-- Une aura est "mienne" si son lanceur est le joueur (ou son vehicule).
local function AuraIsMine(source)
    return source == "player" or source == "vehicle"
end

-- Mode apercu (/mf auratest) : vraies icones de sort (existent sur ce client)
-- pour remplir les rangees sans dependre des auras reelles d'une unite. Permet
-- de tester la disposition (multi-lignes, "les miennes plus grosses") a froid.
-- On fait tourner la liste pour que chaque case ait une icone differente.
local PREVIEW_ICONS = {
    "Interface\\Icons\\Spell_Holy_PowerWordShield",
    "Interface\\Icons\\Spell_Nature_Rejuvenation",
    "Interface\\Icons\\Spell_Fire_FlameBolt",
    "Interface\\Icons\\Spell_Frost_FrostBolt02",
    "Interface\\Icons\\Ability_Warrior_BattleShout",
    "Interface\\Icons\\Spell_Holy_Renew",
    "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
    "Interface\\Icons\\Ability_Rogue_SliceDice",
    "Interface\\Icons\\Spell_Nature_Lightning",
    "Interface\\Icons\\Spell_Holy_FlashHeal",
}

-- Remplit TOUTES les cases d'une rangee avec des donnees factices, en respectant
-- les memes regles de taille que FillAuras (onlyMine => tout est mien ; sinon les
-- 4 PREMIERES cases sont miennes, comme l'affichage reel qui groupe les miennes
-- en tete : on a donc 4 icones agrandies en debut de rangee avec bigMine).
local PREVIEW_MINE_COUNT = 4
local function FillAurasPreview(icons, isDebuff, opts)
    local n = #icons
    local onlyMine = opts and opts.onlyMine
    local bigMine  = opts and opts.bigMine
    local baseSize = (opts and opts.baseSize) or 18
    local mineSize = (opts and opts.mineSize) or baseSize
    for slot = 1, n do
        local btn = icons[slot]
        local mine = onlyMine or (slot <= PREVIEW_MINE_COUNT)
        local sz = (bigMine and mine) and mineSize or baseSize
        btn:SetSize(sz, sz)
        btn.tex:SetTexture(PREVIEW_ICONS[(slot - 1) % #PREVIEW_ICONS + 1])
        -- Quelques stacks pour exercer aussi l'affichage du compteur.
        if slot % 4 == 0 then btn.count:SetText(tostring(slot % 9 + 1)) else btn.count:SetText("") end
        btn.cd:Hide()
        if isDebuff then
            local c = DEBUFF_COLORS.none
            btn.bd:SetColorTexture(c.r, c.g, c.b, 1)
        end
        -- Pas de tooltip d'aura reelle en preview.
        btn.unit = nil
        btn.auraIndex = nil
        btn:Show()
    end
end

-- Remplit une rangee d'icones. opts :
--   onlyMine : ne retient que les auras lancees par le joueur
--   bigMine  : agrandit (mineSize) les auras du joueur, les autres en baseSize
--   baseSize / mineSize : tailles d'icone (px)
local function FillAuras(icons, unit, filter, isDebuff, opts)
    local n = #icons
    local onlyMine = opts and opts.onlyMine
    local bigMine  = opts and opts.bigMine
    local baseSize = (opts and opts.baseSize) or 18
    local mineSize = (opts and opts.mineSize) or baseSize

    local slot = 0
    for i = 1, MAX_AURA_SCAN do
        if slot >= n then break end
        local name, icon, count, dispelType, duration, expiration, source = GetAura(unit, i, filter)
        if not name then break end
        local mine = AuraIsMine(source)
        if (not onlyMine) or mine then
            slot = slot + 1
            local btn = icons[slot]
            -- Memorise de quoi reconstruire le tooltip au survol (index reel i,
            -- pas le slot, car onlyMine peut sauter des index).
            btn.unit = unit
            btn.auraIndex = i
            btn.filter = filter
            local sz = (bigMine and mine) and mineSize or baseSize
            btn:SetSize(sz, sz)
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
        end
    end
    for i = slot + 1, n do icons[i]:Hide() end
end

local function HideAll(icons)
    for _, b in ipairs(icons) do b:Hide() end
end

function Elements.UpdateAuras(frame)
    local unit = frame.unit
    if not unit or not UnitExists(unit) then return end
    local cfg = frame.config
    local baseSize = cfg.auraSize or 18
    local mineSize = math.floor(baseSize * (cfg.auraMineScale or 1.3) + 0.5)
    local preview = ns.auraPreview
    if frame.buffIcons then
        if cfg.showBuffs then
            local opts = {
                onlyMine = cfg.buffOnlyMine, bigMine = cfg.buffBigMine,
                baseSize = baseSize, mineSize = mineSize,
            }
            if preview then
                FillAurasPreview(frame.buffIcons, false, opts)
            else
                FillAuras(frame.buffIcons, unit, "HELPFUL", false, opts)
            end
        else HideAll(frame.buffIcons) end
    end
    if frame.debuffIcons then
        if cfg.showDebuffs then
            local opts = {
                onlyMine = cfg.debuffOnlyMine, bigMine = cfg.debuffBigMine,
                baseSize = baseSize, mineSize = mineSize,
            }
            if preview then
                FillAurasPreview(frame.debuffIcons, true, opts)
            else
                FillAuras(frame.debuffIcons, unit, "HARMFUL", true, opts)
            end
        else HideAll(frame.debuffIcons) end
    end

    -- Les tailles varient (bigMine) : re-ancrer pour que la rangee reste alignee
    -- meme apres un changement de cible (l'ancrage bord-a-bord absorbe les tailles
    -- mixtes). Sans cout perceptible, et seulement si bigMine est actif quelque part.
    if (frame.buffIcons and cfg.buffBigMine) or (frame.debuffIcons and cfg.debuffBigMine) then
        Elements.AnchorAuras(frame)
    end
end

-- Affiche le dragon de classification (worldboss/elite/rare) a gauche du nom.
-- Quand l'unite est "normale", l'icone est masquee ET retrecie (largeur ~0) pour
-- que le nom recupere la place (le nom est ancre sur le bord droit de l'icone).
-- Le halo scintillant + son fond sombre n'apparaissent que pour le worldboss.
function Elements.UpdateClassification(frame)
    local icon = frame.classIcon
    if not icon then return end
    local glow, anim = frame.classGlow, frame.classAnim
    local unit = frame.unit
    local info
    if unit and UnitExists(unit) then
        local classification = UnitClassification(unit)
        -- Beaucoup de world boss (Sha de la colere, Galleon...) renvoient "elite"
        -- + un niveau ?? (UnitLevel == -1), PAS "worldboss". Le niveau ?? est donc
        -- le vrai signal "boss" : on le promeut au traitement worldboss (or + halo).
        if classification == "worldboss" or UnitLevel(unit) == -1 then
            info = CLASSIFICATIONS.worldboss
        else
            info = CLASSIFICATIONS[classification]
        end
    end
    if not info then
        icon:Hide()
        if glow then glow:Hide() end
        if anim then anim:Hide() end   -- coupe le ticker d'animation
        AnchorRichName(frame)          -- nom realigne sur le bord gauche (pas d'icone)
        return
    end
    local size = frame.config.classSize or 16
    icon:SetAtlas(info.atlas)     -- pas de redimensionnement auto (useAtlasSize omis)
    icon:SetSize(size, size)
    icon:Show()
    local showGlow = info.glow and true or false
    if glow then if showGlow then glow:Show() else glow:Hide() end end
    if anim then if showGlow then anim:Show() else anim:Hide() end end
    AnchorRichName(frame)          -- nom decale a droite de l'icone
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
    Elements.UpdateClassification(frame)
    Elements.UpdateAuras(frame)
    Elements.UpdateCombat(frame)
    if frame.castBar then Elements.CastBarCheck(frame) end
end

-- ----------------------------------------------------------------------------
--  Evenements unite (filtres par unite)
-- ----------------------------------------------------------------------------
local UNIT_EVENTS = {
    "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_ABSORB_AMOUNT_CHANGED",
    "UNIT_POWER_UPDATE", "UNIT_MAXPOWER", "UNIT_DISPLAYPOWER",
    "UNIT_AURA", "UNIT_NAME_UPDATE", "UNIT_LEVEL",
    "UNIT_FLAGS", "UNIT_CLASSIFICATION_CHANGED",
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
    if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH"
        or event == "UNIT_ABSORB_AMOUNT_CHANGED" then
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
    elseif event == "UNIT_CLASSIFICATION_CHANGED" then
        Elements.UpdateClassification(self)
    end
end
