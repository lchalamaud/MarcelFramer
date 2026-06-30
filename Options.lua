local addonName, ns = ...

-- ============================================================================
--  Options.lua — Fenetre de configuration (/mf config), en onglets :
--    1. Classes            : couleur de la barre de vie par classe (une teinte)
--    2. Ressources & PNJ   : couleurs des ressources + couleurs de reaction PNJ
--    3. Cadres             : tailles et positions des cadres
--    4. Barre de cast      : distinction (non) interruptible + couleurs
--  API pure : frame maison + ColorPickerFrame Blizzard. Chaque teinte est
--  editable via une pastille (color picker) OU un champ hexa. Sauvegarde dans
--  MarcelFramerDB ; apercu live via ns:RefreshAll().
-- ============================================================================

ns.Options = {}

local CLASS_ORDER = {
    "WARRIOR", "PALADIN", "DEATHKNIGHT", "MONK", "PRIEST", "DRUID",
    "SHAMAN", "MAGE", "WARLOCK", "HUNTER", "ROGUE",
}

-- Jetons de ressource exposes (ordre d'affichage). Les autres retombent sur
-- PowerBarColor Blizzard et ne sont pas editables ici.
local POWER_ORDER = {
    { key = "MANA",        label = "Mana"              },
    { key = "RAGE",        label = "Rage"              },
    { key = "ENERGY",      label = "Energie"           },
    { key = "FOCUS",       label = "Focalisation"      },
    { key = "RUNIC_POWER", label = "Puissance runique" },
}

-- Categories de reaction PNJ (cf. ns.ReactionCategory).
local REACTION_ORDER = {
    { key = "hostile",    label = "Hostile"    },
    { key = "unfriendly", label = "Non amical" },
    { key = "neutral",    label = "Neutre"     },
    { key = "friendly",   label = "Amical"     },
}

-- Copie profonde des defauts (pour /reset), prise AVANT toute fusion DB
-- (ce fichier s'execute au chargement, donc avant ApplySavedColors @ PLAYER_LOGIN).
local CLASS_DEFAULTS = {}
for class, c in pairs(ns.classBarColors or {}) do
    CLASS_DEFAULTS[class] = { c[1], c[2], c[3] }
end
local POWER_DEFAULTS = {}
for k, c in pairs(ns.powerColors or {}) do POWER_DEFAULTS[k] = { c[1], c[2], c[3] } end
local REACTION_DEFAULTS = {}
for k, c in pairs(ns.reactionColors or {}) do REACTION_DEFAULTS[k] = { c[1], c[2], c[3] } end
local CAST_DEFAULTS = {
    distinguish      = (ns.castColors == nil) or (ns.castColors.distinguish ~= false),
    interruptible    = { unpack(ns.castColors and ns.castColors.interruptible    or { 0.937, 0.788, 0.341 }) },
    notInterruptible = { unpack(ns.castColors and ns.castColors.notInterruptible or { 0.60, 0.60, 0.60 }) },
}

local frame
local panels      = {}   -- onglet index -> frame conteneur
local tabButtons  = {}
local lockBtn            -- bouton bascule verrouiller/deverrouiller les cadres
local swatches    = {}   -- class -> { sw, hex, label } (une couleur par classe)
local singleRows  = {}   -- liste { tex, hex, label?, get } (ressources + PNJ)

-- ----------------------------------------------------------------------------
--  Conversions hexa <-> rgb (0-1)
-- ----------------------------------------------------------------------------
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

-- ----------------------------------------------------------------------------
--  Selecteur de couleur Blizzard (API moderne, repli ancien systeme)
-- ----------------------------------------------------------------------------
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

-- ----------------------------------------------------------------------------
--  Briques reutilisables : pastille + champ hexa (lies par get/apply/restore)
-- ----------------------------------------------------------------------------
-- Retire le focus de tous les champs hexa (classes + couleurs unies). A appeler
-- avant d'ouvrir un ColorPicker : sinon le champ encore focus re-committe son
-- ancienne valeur (via OnEditFocusLost) par-dessus la couleur choisie au picker.
-- Meme logique que pour les champs X/Y des positions de cadre.
local function clearColorFocus()
    for _, row in pairs(swatches) do
        if row.hex then row.hex:ClearFocus() end
    end
    for _, row in ipairs(singleRows) do
        if row.hex then row.hex:ClearFocus() end
    end
end

-- Pastille cliquable (bordure + aplat). get() -> r,g,b ; apply(r,g,b).
local function createSwatch(parent, get, apply)
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
        clearColorFocus()          -- valide/abandonne toute saisie hexa en cours
        local r, g, b2 = get()
        if not r then return end
        openPicker(r, g, b2, apply)
    end)
    return b
end

-- Champ hexa. apply(r,g,b) si valide ; restore() sinon (et a l'echap).
local function createHexBox(parent, apply, restore)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(58, 18)
    e:SetAutoFocus(false)
    e:SetMaxLetters(7)             -- tolere un '#' en plus des 6 chiffres
    e:SetFontObject("GameFontHighlightSmall")
    local function commit()
        local r, g, b = HexToRGB(e:GetText())
        if r then apply(r, g, b) else restore() end
        e:ClearFocus()
    end
    e:SetScript("OnEnterPressed", commit)
    e:SetScript("OnEditFocusLost", commit)
    e:SetScript("OnEscapePressed", function(self) restore(); self:ClearFocus() end)
    return e
end

-- ----------------------------------------------------------------------------
--  Rafraichissement de l'affichage des pastilles / champs hexa
-- ----------------------------------------------------------------------------
-- Couleurs de classe (une teinte par classe)
local function refreshSwatches()
    for class, row in pairs(swatches) do
        local c = ns.classBarColors[class]
        if c then
            row.sw.tex:SetColorTexture(c[1], c[2], c[3])
            row.label:SetTextColor(c[1], c[2], c[3])
            if not row.hex:HasFocus() then
                row.hex:SetText(RGBToHex(c[1], c[2], c[3]))
            end
        end
    end
end

-- Couleurs unies (ressources + PNJ)
local function refreshSingleRows()
    for _, row in ipairs(singleRows) do
        local r, g, b = row.get()
        if r then
            row.tex:SetColorTexture(r, g, b)
            if row.label then row.label:SetTextColor(r, g, b) end
            if row.hex and not row.hex:HasFocus() then
                row.hex:SetText(RGBToHex(r, g, b))
            end
        end
    end
end

local function refreshColors()
    refreshSwatches()
    refreshSingleRows()
end

-- ----------------------------------------------------------------------------
--  Sauvegarde d'une teinte (runtime + DB) puis apercu live
-- ----------------------------------------------------------------------------
-- Classe : une couleur unie
local function saveClassColor(class, r, g, b)
    local col = ns.classBarColors[class]
    col[1], col[2], col[3] = r, g, b
    MarcelFramerDB.classBarColors[class] = { r, g, b }
    refreshColors()
    ns:RefreshAll()
end

-- Couleur unie : runtimeTbl[key] = {r,g,b}, persiste dans MarcelFramerDB[dbName][key]
local function saveSingleColor(runtimeTbl, dbName, key, r, g, b)
    local col = runtimeTbl[key]
    col[1], col[2], col[3] = r, g, b
    MarcelFramerDB[dbName][key] = { r, g, b }
    refreshColors()
    ns:RefreshAll()
end

-- ----------------------------------------------------------------------------
--  Reinitialisations
-- ----------------------------------------------------------------------------
local function resetClassColors()
    wipe(MarcelFramerDB.classBarColors)
    for class, def in pairs(CLASS_DEFAULTS) do
        ns.classBarColors[class] = { def[1], def[2], def[3] }
    end
    refreshColors()
    ns:RefreshAll()
end

local function resetSingleColors()
    wipe(MarcelFramerDB.powerColors)
    wipe(MarcelFramerDB.reactionColors)
    for k, def in pairs(POWER_DEFAULTS)    do ns.powerColors[k]    = { def[1], def[2], def[3] } end
    for k, def in pairs(REACTION_DEFAULTS) do ns.reactionColors[k] = { def[1], def[2], def[3] } end
    refreshColors()
    ns:RefreshAll()
end

-- ----------------------------------------------------------------------------
--  Barre de cast : distinction (non) interruptible + couleurs (onglet dedie)
-- ----------------------------------------------------------------------------
-- Widgets de l'onglet, renseignes a la construction (refreshCastState les lit).
local castState = { check = nil, notInterRow = nil }

-- Active/grise la ligne "non interruptible" selon l'etat du toggle.
local function setRowEnabled(row, enabled)
    if not row then return end
    local a = enabled and 1 or 0.35
    if row.sw then
        row.sw:SetEnabled(enabled)
        row.sw:SetAlpha(a)
    end
    if row.hex then
        if row.hex.SetEnabled then row.hex:SetEnabled(enabled) end
        row.hex:EnableMouse(enabled)
        row.hex:SetAlpha(a)
    end
    if row.label then row.label:SetAlpha(a) end
end

-- Reflete l'etat du toggle sur la case + le grisage de la ligne "non interruptible".
local function refreshCastState()
    local on = ns.castColors.distinguish ~= false
    if castState.check then castState.check:SetChecked(on) end
    setRowEnabled(castState.notInterRow, on)
end

local function saveCastDistinguish(on)
    ns.castColors.distinguish = on
    MarcelFramerDB.castColors.distinguish = on
    refreshCastState()
    ns:RefreshAll()
end

local function resetCastColors()
    wipe(MarcelFramerDB.castColors)
    ns.castColors.distinguish      = CAST_DEFAULTS.distinguish
    ns.castColors.interruptible    = { unpack(CAST_DEFAULTS.interruptible) }
    ns.castColors.notInterruptible = { unpack(CAST_DEFAULTS.notInterruptible) }
    refreshColors()
    refreshCastState()
    ns:RefreshAll()
end

-- ============================================================================
--  Section TAILLES / POSITIONS (onglet "Cadres")
-- ============================================================================
local SIZE_KEYS = {
    { key = "player",       label = "Joueur"        },
    { key = "target",       label = "Cible"         },
    { key = "focus",        label = "Focalisation"  },
    { key = "pet",          label = "Familier"      },
    { key = "targettarget", label = "Cible-cible"   },
}
local SIZE_SLIDERS = {
    { field = "width",  label = "Largeur", min = 60,  max = 400, step = 1    },
    { field = "height", label = "Hauteur", min = 16,  max = 140, step = 1    },
    { field = "scale",  label = "Echelle", min = 0.5, max = 2.0, step = 0.05 },
}
local sizeState = { currentKey = "player", sliders = {}, selButtons = {} }

local function fmtSize(field, v)
    if field == "scale" then return string.format("%.2f", v) end
    return tostring(math.floor(v + 0.5))
end

-- Recharge les sliders + le bouton actif depuis ns.config[currentKey]
-- (sans declencher de sauvegarde : flag suppress).
local function refreshSizeSliders()
    local cfg = ns.config[sizeState.currentKey]
    if not cfg then return end
    for _, s in ipairs(sizeState.sliders) do
        local info = s.info
        local v = (info.field == "scale") and (cfg.scale or 1) or (cfg[info.field] or info.min)
        s.suppress = true
        s:SetValue(v)
        s.suppress = false
        s.valueLabel:SetText(info.label .. " : " .. fmtSize(info.field, v))
    end
    for key, btn in pairs(sizeState.selButtons) do
        if key == sizeState.currentKey then btn:LockHighlight() else btn:UnlockHighlight() end
    end
    -- Case "Barre de cast" : active seulement pour joueur / cible
    if sizeState.castCheck then
        local key = sizeState.currentKey
        local applicable = (key == "player" or key == "target" or key == "focus")
        sizeState.castCheck:SetEnabled(applicable)
        local g = applicable and 1 or 0.5
        sizeState.castLabel:SetTextColor(g, g, g)
        sizeState.castCheck:SetChecked(applicable and (ns.config[key].showCastBar ~= false))
    end
    -- Champs de position X/Y (depuis la position courante du cadre)
    if sizeState.posX then
        local p = ns:GetPosition(sizeState.currentKey)
        local px = p and (p.x or 0) or 0
        local py = p and (p.y or 0) or 0
        if not sizeState.posX:HasFocus() then sizeState.posX:SetText(tostring(math.floor(px + 0.5))) end
        if not sizeState.posY:HasFocus() then sizeState.posY:SetText(tostring(math.floor(py + 0.5))) end
    end
end

-- Lit les deux champs X/Y et enregistre la position du cadre selectionne.
local function commitPos()
    local key = sizeState.currentKey
    local x = tonumber(((sizeState.posX:GetText() or ""):gsub(",", ".")))
    local y = tonumber(((sizeState.posY:GetText() or ""):gsub(",", ".")))
    if x and y then
        ns:SavePosition(key, math.floor(x + 0.5), math.floor(y + 0.5))
    end
    refreshSizeSliders()   -- restaure l'affichage (valide ou non)
end

-- Champ numerique de coordonnee (X ou Y), repris du style hexa.
local function makePosBox(parent)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(56, 18)
    e:SetAutoFocus(false)
    e:SetNumeric(false)            -- on tolere le signe '-' (et la virgule)
    e:SetMaxLetters(6)
    e:SetFontObject("GameFontHighlightSmall")
    e:SetScript("OnEnterPressed", function(self) commitPos(); self:ClearFocus() end)
    e:SetScript("OnEditFocusLost", commitPos)
    e:SetScript("OnEscapePressed", function(self) refreshSizeSliders(); self:ClearFocus() end)
    return e
end

-- Change le cadre en cours de parametrage. On retire d'abord le focus des
-- champs X/Y : ClearFocus declenche OnEditFocusLost -> commitPos pendant que
-- currentKey designe encore l'ANCIEN cadre, donc l'edition en cours est validee
-- sur le bon cadre avant la bascule (sinon elle ecraserait le nouveau).
local function selectSizeKey(key)
    if sizeState.posX then sizeState.posX:ClearFocus() end
    if sizeState.posY then sizeState.posY:ClearFocus() end
    sizeState.currentKey = key
    refreshSizeSliders()
end

-- Reflete l'etat verrouille/deverrouille sur le bouton bascule.
local function updateLockButton()
    if not lockBtn then return end
    if ns.unlocked then
        lockBtn:SetText("Verrouiller les cadres")
    else
        lockBtn:SetText("Deplacer les cadres")
    end
end

local function makeSizeSlider(parent, name, info)
    local s = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    s:SetWidth(200)
    s:SetMinMaxValues(info.min, info.max)
    s:SetValueStep(info.step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    local low  = s.Low  or _G[name .. "Low"]
    local high = s.High or _G[name .. "High"]
    if low  then low:SetText("")  end   -- min/max masques : le label central suffit
    if high then high:SetText("") end
    s.valueLabel = s.Text or _G[name .. "Text"]
    if not s.valueLabel then   -- repli si le template ne nomme pas sa region
        s.valueLabel = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        s.valueLabel:SetPoint("BOTTOM", s, "TOP", 0, 2)
    end
    s.info = info
    s:SetScript("OnValueChanged", function(self, value)
        if self.suppress then return end
        if info.field == "scale" then
            value = math.floor(value / info.step + 0.5) * info.step
        else
            value = math.floor(value + 0.5)
        end
        local key = sizeState.currentKey
        ns.config[key][info.field] = value
        MarcelFramerDB.sizes[key] = MarcelFramerDB.sizes[key] or {}
        MarcelFramerDB.sizes[key][info.field] = value
        self.valueLabel:SetText(info.label .. " : " .. fmtSize(info.field, value))
        ns:ApplySize(key)
    end)
    return s
end

-- ============================================================================
--  Construction des onglets
-- ============================================================================
-- Onglet 1 : couleurs de classe (une teinte par classe)
local function buildClassPanel(panel)
    local intro = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", 8, -10)
    intro:SetWidth(380)
    intro:SetJustifyH("LEFT")
    intro:SetText("Couleur de la barre de vie par classe. Le relief (gloss) est ajoute automatiquement.")

    local y = -40
    for _, class in ipairs(CLASS_ORDER) do
        if ns.classBarColors[class] then
            local lbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            lbl:SetPoint("TOPLEFT", 8, y)
            lbl:SetText((LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class]) or class)

            local sw = createSwatch(panel,
                function() local c = ns.classBarColors[class]; return c[1], c[2], c[3] end,
                function(r, g, b) saveClassColor(class, r, g, b) end)
            sw:SetPoint("TOPLEFT", 180, y + 1)
            local hex = createHexBox(panel,
                function(r, g, b) saveClassColor(class, r, g, b) end, refreshColors)
            hex:SetPoint("LEFT", sw, "RIGHT", 8, 0)

            swatches[class] = { sw = sw, hex = hex, label = lbl }
            y = y - 26
        end
    end

    local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    reset:SetSize(150, 22)
    reset:SetPoint("BOTTOMLEFT", 4, 4)
    reset:SetText("Reinit. couleurs")
    reset:SetScript("OnClick", resetClassColors)
end

-- Cree une rangee "couleur unie" : label + pastille + champ hexa, liee a
-- runtimeTbl[key]. Enregistre la rangee pour le rafraichissement.
local function addSingleRow(panel, x, y, labelText, runtimeTbl, dbName, key)
    local lbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", x, y)
    lbl:SetText(labelText)

    local function get() local c = runtimeTbl[key]; return c[1], c[2], c[3] end
    local function apply(r, g, b) saveSingleColor(runtimeTbl, dbName, key, r, g, b) end

    local sw = createSwatch(panel, get, apply)
    sw:SetPoint("TOPLEFT", x + 170, y + 1)
    local hex = createHexBox(panel, apply, refreshColors)
    hex:SetPoint("LEFT", sw, "RIGHT", 8, 0)

    local row = { tex = sw.tex, sw = sw, hex = hex, label = lbl, get = get }
    singleRows[#singleRows + 1] = row
    return row
end

-- Onglet 2 : couleurs de ressource + couleurs de reaction PNJ
local function buildResourcePanel(panel)
    local pTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pTitle:SetPoint("TOPLEFT", 4, -8)
    pTitle:SetText("Couleurs des ressources")

    local y = -34
    for _, e in ipairs(POWER_ORDER) do
        addSingleRow(panel, 8, y, e.label, ns.powerColors, "powerColors", e.key)
        y = y - 26
    end

    y = y - 16
    local rTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rTitle:SetPoint("TOPLEFT", 4, y)
    rTitle:SetText("Couleurs des PNJ (reaction)")
    y = y - 26

    for _, e in ipairs(REACTION_ORDER) do
        addSingleRow(panel, 8, y, e.label, ns.reactionColors, "reactionColors", e.key)
        y = y - 26
    end

    local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    reset:SetSize(180, 22)
    reset:SetPoint("BOTTOMLEFT", 4, 4)
    reset:SetText("Reinit. ressources & PNJ")
    reset:SetScript("OnClick", resetSingleColors)
end

-- Onglet 3 : tailles et positions des cadres
local function buildFramesPanel(panel)
    local sTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sTitle:SetPoint("TOPLEFT", 4, -8)
    sTitle:SetText("Tailles des cadres")

    -- Selecteur de cadre (grille 2x2)
    for i, e in ipairs(SIZE_KEYS) do
        local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        b:SetSize(112, 22)
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        b:SetPoint("TOPLEFT", 8 + col * 118, -30 - row * 26)
        b:SetText(e.label)
        b:SetScript("OnClick", function() selectSizeKey(e.key) end)
        sizeState.selButtons[e.key] = b
    end

    -- Sliders Largeur / Hauteur / Echelle. Demarre sous la grille de selection
    -- des cadres (3 lignes depuis l'ajout du focus -> derniere ligne a y=-104),
    -- pour que le label "Largeur" ne chevauche pas le 3e bouton.
    wipe(sizeState.sliders)
    for i, info in ipairs(SIZE_SLIDERS) do
        local s = makeSizeSlider(panel, "MarcelFramerSizeSlider" .. info.field, info)
        s:SetPoint("TOPLEFT", 16, -128 - (i - 1) * 50)
        sizeState.sliders[i] = s
    end

    -- Position du cadre (coordonnees X / Y par rapport a l'ancrage courant)
    local posTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    posTitle:SetPoint("TOPLEFT", 4, -266)
    posTitle:SetText("Position")

    local xLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    xLbl:SetPoint("TOPLEFT", 16, -288)
    xLbl:SetText("X :")
    sizeState.posX = makePosBox(panel)
    sizeState.posX:SetPoint("LEFT", xLbl, "RIGHT", 6, 0)

    local yLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    yLbl:SetPoint("LEFT", sizeState.posX, "RIGHT", 16, 0)
    yLbl:SetText("Y :")
    sizeState.posY = makePosBox(panel)
    sizeState.posY:SetPoint("LEFT", yLbl, "RIGHT", 6, 0)

    -- Bouton bascule : deverrouiller pour deplacer les cadres a la souris
    lockBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    lockBtn:SetSize(160, 22)
    lockBtn:SetPoint("TOPLEFT", 16, -314)
    lockBtn:SetScript("OnClick", function()
        if ns.unlocked then ns:Lock() else ns:Unlock() end
        updateLockButton()
        refreshSizeSliders()   -- les positions ont pu bouger
    end)

    local note = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", 4, -346)
    note:SetWidth(280)
    note:SetJustifyH("LEFT")
    note:SetText("Ajuste hors combat (differe pendant le combat). |cffffff00/mf reset|r remet les positions par defaut.")

    -- Section "Barre de cast" (colonne de droite) : activable pour joueur / cible
    -- uniquement. Les autres cadres n'ont pas de barre de cast (case grisee).
    local cbTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    cbTitle:SetPoint("TOPLEFT", 260, -8)
    cbTitle:SetText("Barre de cast")

    local cbHint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    cbHint:SetPoint("TOPLEFT", 260, -28)
    cbHint:SetWidth(150)
    cbHint:SetJustifyH("LEFT")
    cbHint:SetText("Joueur, cible et focalisation")

    local cast = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    cast:SetSize(24, 24)
    cast:SetPoint("TOPLEFT", 258, -46)
    local castLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    castLabel:SetPoint("LEFT", cast, "RIGHT", 2, 0)
    castLabel:SetText("Afficher")
    cast:SetScript("OnClick", function(self)
        local key = sizeState.currentKey
        if key ~= "player" and key ~= "target" and key ~= "focus" then
            self:SetChecked(false)
            return
        end
        ns:SetCastBarEnabled(key, self:GetChecked())
    end)
    sizeState.castCheck = cast
    sizeState.castLabel = castLabel
    refreshSizeSliders()   -- reflete l'etat de la case pour le cadre courant

    local resetSize = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetSize:SetSize(150, 22)
    resetSize:SetPoint("BOTTOMRIGHT", -4, 4)
    resetSize:SetText("Reinit. tailles")
    resetSize:SetScript("OnClick", function()
        ns:ResetSizes()
        refreshSizeSliders()
    end)
end

-- Onglet 4 : barre de cast (distinction interruptible + couleurs)
local function buildCastPanel(panel)
    local intro = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", 8, -10)
    intro:SetWidth(390)
    intro:SetJustifyH("LEFT")
    intro:SetText("Couleur de la barre d'incantation selon l'interruptibilite du sort. "
        .. "L'etat bascule en direct : la barre se recolore meme en plein cast.")

    -- Toggle : distinguer ou non les sorts (non) interruptibles.
    local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("TOPLEFT", 6, -52)
    local checkLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    checkLabel:SetPoint("LEFT", check, "RIGHT", 2, 0)
    checkLabel:SetText("Distinguer interruptible / non interruptible")
    check:SetScript("OnClick", function(self)
        saveCastDistinguish(self:GetChecked() and true or false)
    end)
    castState.check = check

    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 30, -76)
    hint:SetWidth(360)
    hint:SetJustifyH("LEFT")
    hint:SetText("Decoche : tous les sorts utilisent la couleur \"Interruptible\".")

    -- Couleurs (label + pastille + champ hexa, comme les autres onglets).
    addSingleRow(panel, 8, -108, "Interruptible", ns.castColors, "castColors", "interruptible")
    castState.notInterRow =
        addSingleRow(panel, 8, -134, "Non interruptible", ns.castColors, "castColors", "notInterruptible")

    local reset = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    reset:SetSize(170, 22)
    reset:SetPoint("BOTTOMLEFT", 4, 4)
    reset:SetText("Reinit. barre de cast")
    reset:SetScript("OnClick", resetCastColors)

    refreshCastState()
end

-- ============================================================================
--  Section AURAS (onglet "Auras") : affichage (on/off) + ancrage par type
--  Reglages PAR CADRE et PAR TYPE (buffs / debuffs). La position passe par un
--  "Placement" (cote + alignement) + un "Sens" de croissance + un decalage X/Y.
--  Sauvegarde via ns:SetAuraShown / ns:SetAuraAnchor (DB + apercu live).
-- ============================================================================
local AURA_FRAME_ORDER = {
    { key = "player",       label = "Joueur"       },
    { key = "target",       label = "Cible"        },
    { key = "focus",        label = "Focalisation" },
    { key = "pet",          label = "Familier"     },
    { key = "targettarget", label = "Cible-cible"  },
}

-- Presets de placement : chaque entree fixe le coin de la 1re icone (point) et le
-- coin du cadre/barre de cast auquel on l'accroche (relPoint). Le "Sens" (growth)
-- et le decalage X/Y sont des reglages independants.
local PLACEMENTS = {
    { key = "below_left",  label = "Dessous - gauche", point = "TOPLEFT",     relPoint = "BOTTOMLEFT"  },
    { key = "below_right", label = "Dessous - droite", point = "TOPRIGHT",    relPoint = "BOTTOMRIGHT" },
    { key = "above_left",  label = "Dessus - gauche",  point = "BOTTOMLEFT",  relPoint = "TOPLEFT"     },
    { key = "above_right", label = "Dessus - droite",  point = "BOTTOMRIGHT", relPoint = "TOPRIGHT"    },
    { key = "left_top",    label = "Gauche - haut",    point = "TOPRIGHT",    relPoint = "TOPLEFT"     },
    { key = "left_bottom", label = "Gauche - bas",     point = "BOTTOMRIGHT", relPoint = "BOTTOMLEFT"  },
    { key = "right_top",   label = "Droite - haut",    point = "TOPLEFT",     relPoint = "TOPRIGHT"    },
    { key = "right_bottom",label = "Droite - bas",     point = "BOTTOMLEFT",  relPoint = "BOTTOMRIGHT" },
}
local PLACEMENT_BY_KEY     = {}   -- placementKey -> entry
local PLACEMENT_BY_CORNERS = {}   -- "point|relPoint" -> entry
for _, p in ipairs(PLACEMENTS) do
    PLACEMENT_BY_KEY[p.key] = p
    PLACEMENT_BY_CORNERS[p.point .. "|" .. p.relPoint] = p
end

local GROWTH_OPTIONS = {
    { key = "RIGHT", label = "Droite" },
    { key = "LEFT",  label = "Gauche" },
    { key = "DOWN",  label = "Bas"    },
    { key = "UP",    label = "Haut"   },
}

local auraState = { currentKey = nil, keys = {}, selButtons = {}, buffs = nil, debuffs = nil, gridSliders = {} }

-- Grille d'auras du cadre courant : taille des icones + icones par ligne + lignes
-- max. Reglage PAR CADRE (partage buffs et debuffs, comme le modele auraSize /
-- numAuras / maxAuraRows de Config.lua). Applique a chaud via ns:SetAuraGrid.
local AURA_GRID_SLIDERS = {
    { field = "auraSize",    label = "Taille",     min = 10, max = 40, step = 1, default = 18 },
    { field = "numAuras",    label = "Par ligne",  min = 1,  max = 12, step = 1, default = 6  },
    { field = "maxAuraRows", label = "Lignes max", min = 1,  max = 6,  step = 1, default = 1  },
}

-- Recharge les sliders de grille depuis ns.config[currentKey] (sans declencher de
-- sauvegarde : flag suppress). Borne l'affichage a l'echelle du slider au cas ou
-- Config.lua sortirait des limites.
local function refreshAuraGridSliders()
    local cfg = auraState.currentKey and ns.config[auraState.currentKey]
    for _, s in ipairs(auraState.gridSliders) do
        local info = s.info
        local v = (cfg and cfg[info.field]) or info.default
        if v < info.min then v = info.min elseif v > info.max then v = info.max end
        s.suppress = true
        s:SetValue(v)
        s.suppress = false
        s.valueLabel:SetText(info.label .. " : " .. math.floor(v + 0.5))
    end
end

-- Liste deroulante generique (UIDropDownMenu). onSelect(key) au choix.
local function makeDropdown(name, parent, width, options, onSelect)
    local dd = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
    dd.options = options
    UIDropDownMenu_SetWidth(dd, width)
    UIDropDownMenu_Initialize(dd, function(_, level)
        for _, opt in ipairs(options) do
            local info = UIDropDownMenu_CreateInfo()
            info.text  = opt.label
            info.value = opt.key
            info.checked = (UIDropDownMenu_GetSelectedValue(dd) == opt.key)
            info.func = function()
                UIDropDownMenu_SetSelectedValue(dd, opt.key)
                UIDropDownMenu_SetText(dd, opt.label)
                if onSelect then onSelect(opt.key) end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    return dd
end

-- Reflete une valeur courante dans une liste. key = nil + fallback => libelle libre
-- (cas d'un ancrage "personnalise" via Config.lua qui ne matche aucun preset).
local function setDropdown(dd, key, fallback)
    UIDropDownMenu_SetSelectedValue(dd, key)
    local label = fallback or tostring(key)
    if key ~= nil then
        for _, opt in ipairs(dd.options) do
            if opt.key == key then label = opt.label break end
        end
    end
    UIDropDownMenu_SetText(dd, label)
end

-- Remet une colonne (buffs ou debuffs) a l'etat du cadre courant.
local function refreshAuraColumn(kind)
    local W = auraState[kind]
    local key = auraState.currentKey
    local cfg = key and ns.config[key]
    if not W or not W.show or not cfg then return end

    local shown
    if kind == "buffs" then shown = (cfg.showBuffs ~= false) else shown = (cfg.showDebuffs ~= false) end
    W.show:SetChecked(shown)

    -- Filtres par type : seulement les miennes / les miennes plus grosses.
    local prefix = (kind == "buffs") and "buff" or "debuff"
    if W.onlyMine then W.onlyMine:SetChecked(cfg[prefix .. "OnlyMine"] and true or false) end
    if W.bigMine  then W.bigMine:SetChecked(cfg[prefix .. "BigMine"] and true or false) end

    local a = ns.Elements.GetResolvedAuraAnchor(cfg, kind)
    local entry = PLACEMENT_BY_CORNERS[(a.point or "") .. "|" .. (a.relPoint or "")]
    if entry then setDropdown(W.placement, entry.key) else setDropdown(W.placement, nil, "Personnalise") end
    setDropdown(W.growth, a.growth or "RIGHT")

    if W.x and not W.x:HasFocus() then W.x:SetText(tostring(a.x or 0)) end
    if W.y and not W.y:HasFocus() then W.y:SetText(tostring(a.y or 0)) end

    -- Case "Suivre barre de cast" : la barre etant SOUS le cadre, la suivre n'a de
    -- sens que pour un placement "Dessous" (rangee qui pend dessous) et un cadre
    -- dote d'une barre (joueur / cible / focalisation). Grisee sinon, avec un
    -- tooltip explicatif via le "cover" (cf. buildAuraColumn).
    if W.cast then
        local hasCastBar = (key == "player" or key == "target" or key == "focus")
        local hangsBelow = (a.point or ""):sub(1, 3) == "TOP" and (a.relPoint or ""):sub(1, 6) == "BOTTOM"
        local applicable = hasCastBar and hangsBelow
        W.cast:SetEnabled(applicable)
        if W.castLabel then local g = applicable and 1 or 0.5; W.castLabel:SetTextColor(g, g, g) end
        W.cast:SetChecked(applicable and (a.relTo == "castbar"))
        if W.castCover then
            if applicable then
                W.castCover:Hide()
            else
                W.castCover.reason = (not hasCastBar)
                    and "Indisponible : ce cadre n'a pas de barre de cast."
                    or  "Indisponible avec ce placement : la barre de cast est sous le cadre, "
                        .. "le suivi ne vaut que pour un placement \194\171 Dessous \194\187."
                W.castCover:Show()
            end
        end
    end
end

local function refreshAurasPanel()
    if auraState.updatePreviewLabel then auraState.updatePreviewLabel() end
    refreshAuraGridSliders()
    if not auraState.currentKey then return end
    for key, btn in pairs(auraState.selButtons) do
        if key == auraState.currentKey then btn:LockHighlight() else btn:UnlockHighlight() end
    end
    refreshAuraColumn("buffs")
    refreshAuraColumn("debuffs")
end

-- Change le cadre en cours de parametrage (valide d'abord les saisies X/Y en
-- cours sur l'ANCIEN cadre via ClearFocus -> commit, comme l'onglet Cadres).
local function selectAuraKey(key)
    for _, kind in ipairs({ "buffs", "debuffs" }) do
        local W = auraState[kind]
        if W then
            if W.x then W.x:ClearFocus() end
            if W.y then W.y:ClearFocus() end
        end
    end
    auraState.currentKey = key
    refreshAurasPanel()
end

-- Champ de decalage X/Y d'un type d'aura.
local function makeAuraOffsetBox(parent, kind, field)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(44, 18)
    e:SetAutoFocus(false)
    e:SetNumeric(false)            -- tolere le signe '-' (et la virgule)
    e:SetMaxLetters(5)
    e:SetFontObject("GameFontHighlightSmall")
    local function commit()
        local v = tonumber(((e:GetText() or ""):gsub(",", ".")))
        if v and auraState.currentKey then
            ns:SetAuraAnchor(auraState.currentKey, kind, field, math.floor(v + 0.5))
        end
        refreshAurasPanel()
        e:ClearFocus()
    end
    e:SetScript("OnEnterPressed", commit)
    e:SetScript("OnEditFocusLost", commit)
    e:SetScript("OnEscapePressed", function(self) refreshAurasPanel(); self:ClearFocus() end)
    return e
end

-- Tooltip de la case "Suivre barre de cast". reason (optionnel) = motif du grisage.
local function castFollowTooltip(owner, reason)
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine("Suivre barre de cast", 1, 1, 1)
    GameTooltip:AddLine(
        "Place la rangee sous la barre de cast quand elle est affichee (repli sous le cadre sinon).",
        0.9, 0.9, 0.9, true)
    if reason then GameTooltip:AddLine(reason, 1, 0.55, 0.55, true) end
    GameTooltip:Show()
end

-- Construit une colonne (buffs ou debuffs). withCast = case "Suivre barre de cast".
local function buildAuraColumn(panel, x, kind, title, withCast)
    local W = {}
    auraState[kind] = W

    local t = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t:SetPoint("TOPLEFT", x, -118)
    t:SetText(title)

    local show = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    show:SetSize(24, 24)
    show:SetPoint("TOPLEFT", x - 2, -134)
    local showLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    showLbl:SetPoint("LEFT", show, "RIGHT", 2, 0)
    showLbl:SetText("Afficher")
    show:SetScript("OnClick", function(self)
        if auraState.currentKey then ns:SetAuraShown(auraState.currentKey, kind, self:GetChecked()) end
    end)
    W.show = show

    if withCast then
        local cast = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        cast:SetSize(22, 22)
        cast:SetPoint("TOPLEFT", x - 1, -160)
        local castLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        castLbl:SetPoint("LEFT", cast, "RIGHT", 2, 0)
        castLbl:SetText("Suivre barre de cast")
        cast:SetScript("OnClick", function(self)
            if auraState.currentKey then
                ns:SetAuraAnchor(auraState.currentKey, kind, "relTo", self:GetChecked() and "castbar" or "frame")
            end
        end)
        -- Tooltip quand la case est ACTIVE (decrit l'option).
        cast:SetScript("OnEnter", function(self) castFollowTooltip(self, nil) end)
        cast:SetScript("OnLeave", GameTooltip_Hide)

        -- Zone de survol posee par-dessus : une checkbox desactivee ne recoit plus
        -- les events souris, donc pas de tooltip. Ce "cover" capte le survol (et
        -- bloque le clic) UNIQUEMENT quand la case est grisee, pour afficher le
        -- motif du grisage. Masque (donc transparent au clic) quand la case est active.
        local cover = CreateFrame("Button", nil, panel)
        cover:SetPoint("TOPLEFT", cast, "TOPLEFT")
        cover:SetPoint("BOTTOM", cast, "BOTTOM")
        cover:SetPoint("RIGHT", castLbl, "RIGHT", 2, 0)
        cover:SetFrameLevel(cast:GetFrameLevel() + 10)
        cover:EnableMouse(true)
        cover:Hide()
        cover:SetScript("OnEnter", function(self) castFollowTooltip(self, self.reason) end)
        cover:SetScript("OnLeave", GameTooltip_Hide)

        W.cast = cast
        W.castLabel = castLbl
        W.castCover = cover
    end

    -- Filtre "seulement les miennes" : n'affiche que les auras lancees par le joueur.
    local onlyMine = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    onlyMine:SetSize(22, 22)
    onlyMine:SetPoint("TOPLEFT", x - 1, -184)
    local onlyMineLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    onlyMineLbl:SetPoint("LEFT", onlyMine, "RIGHT", 2, 0)
    onlyMineLbl:SetText("Seulement les miennes")
    onlyMine:SetScript("OnClick", function(self)
        if auraState.currentKey then ns:SetAuraFlag(auraState.currentKey, kind, "onlyMine", self:GetChecked()) end
    end)
    W.onlyMine = onlyMine

    -- "Les miennes plus grosses" : agrandit mes auras (facteur auraMineScale).
    local bigMine = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    bigMine:SetSize(22, 22)
    bigMine:SetPoint("TOPLEFT", x - 1, -208)
    local bigMineLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bigMineLbl:SetPoint("LEFT", bigMine, "RIGHT", 2, 0)
    bigMineLbl:SetText("Les miennes plus grosses")
    bigMine:SetScript("OnClick", function(self)
        if auraState.currentKey then ns:SetAuraFlag(auraState.currentKey, kind, "bigMine", self:GetChecked()) end
    end)
    W.bigMine = bigMine

    local pLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pLbl:SetPoint("TOPLEFT", x, -236)
    pLbl:SetText("Placement :")
    local pdd = makeDropdown("MarcelFramerAuraPlace" .. kind, panel, 120, PLACEMENTS, function(k)
        if not auraState.currentKey then return end
        local p = PLACEMENT_BY_KEY[k]
        if p then
            ns:SetAuraAnchor(auraState.currentKey, kind, "point", p.point)
            ns:SetAuraAnchor(auraState.currentKey, kind, "relPoint", p.relPoint)
            refreshAurasPanel()   -- met a jour le grisage + le tooltip de "Suivre barre de cast"
        end
    end)
    pdd:SetPoint("TOPLEFT", x - 16, -252)
    W.placement = pdd

    local gLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    gLbl:SetPoint("TOPLEFT", x, -288)
    gLbl:SetText("Sens :")
    local gdd = makeDropdown("MarcelFramerAuraGrow" .. kind, panel, 90, GROWTH_OPTIONS, function(k)
        if auraState.currentKey then ns:SetAuraAnchor(auraState.currentKey, kind, "growth", k) end
    end)
    gdd:SetPoint("TOPLEFT", x - 16, -304)
    W.growth = gdd

    local xLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    xLbl:SetPoint("TOPLEFT", x, -340)
    xLbl:SetText("X :")
    W.x = makeAuraOffsetBox(panel, kind, "x")
    W.x:SetPoint("LEFT", xLbl, "RIGHT", 6, 0)
    local yLbl = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    yLbl:SetPoint("LEFT", W.x, "RIGHT", 14, 0)
    yLbl:SetText("Y :")
    W.y = makeAuraOffsetBox(panel, kind, "y")
    W.y:SetPoint("LEFT", yLbl, "RIGHT", 6, 0)
end

-- Slider compact d'un parametre de grille d'auras (taille / par ligne / lignes
-- max), applique au cadre courant via ns:SetAuraGrid (apercu live immediat).
local function makeAuraGridSlider(panel, name, info)
    local s = CreateFrame("Slider", name, panel, "OptionsSliderTemplate")
    s:SetWidth(106)
    s:SetMinMaxValues(info.min, info.max)
    s:SetValueStep(info.step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    local low  = s.Low  or _G[name .. "Low"]
    local high = s.High or _G[name .. "High"]
    if low  then low:SetText("")  end   -- min/max masques : le label central suffit
    if high then high:SetText("") end
    s.valueLabel = s.Text or _G[name .. "Text"]
    if not s.valueLabel then
        s.valueLabel = s:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        s.valueLabel:SetPoint("BOTTOM", s, "TOP", 0, 2)
    end
    s.info = info
    s:SetScript("OnValueChanged", function(self, value)
        if self.suppress then return end
        value = math.floor(value + 0.5)
        self.valueLabel:SetText(info.label .. " : " .. value)
        if auraState.currentKey then
            ns:SetAuraGrid(auraState.currentKey, info.field, value)
        end
    end)
    return s
end

-- Onglet 5 : auras (affichage + ancrage par type)
local function buildAurasPanel(panel)
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 4, -8)
    title:SetText("Affichage des auras")

    -- Bouton apercu : remplit les rangees d'auras factices (meme effet que
    -- /mf auratest) pour visualiser la disposition sans cible chargee d'auras.
    local preview = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    preview:SetSize(130, 22)
    preview:SetPoint("TOPRIGHT", -4, -4)
    local function updatePreviewLabel()
        preview:SetText(ns.auraPreview and "Apercu auras : ON" or "Apercu auras : OFF")
    end
    preview:SetScript("OnClick", function()
        ns:AuraTest()
        updatePreviewLabel()
    end)
    preview:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Remplit les cadres visibles d'auras factices", 1, 1, 1, 1, true)
        GameTooltip:AddLine("Cible n'importe quoi pour voir le cadre cible.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    preview:SetScript("OnLeave", function() GameTooltip:Hide() end)
    auraState.updatePreviewLabel = updatePreviewLabel

    -- Cadres proposes : ceux qui ont au moins une case d'aura (numAuras > 0).
    wipe(auraState.keys)
    for _, e in ipairs(AURA_FRAME_ORDER) do
        local c = ns.config[e.key]
        if c and (c.numAuras or 0) > 0 then auraState.keys[#auraState.keys + 1] = e end
    end

    for i, e in ipairs(auraState.keys) do
        local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        b:SetSize(112, 22)
        local col = (i - 1) % 2
        local row = math.floor((i - 1) / 2)
        b:SetPoint("TOPLEFT", 8 + col * 118, -34 - row * 26)
        b:SetText(e.label)
        b:SetScript("OnClick", function() selectAuraKey(e.key) end)
        auraState.selButtons[e.key] = b
    end
    auraState.currentKey = auraState.keys[1] and auraState.keys[1].key or nil

    buildAuraColumn(panel, 8,   "buffs",   "Buffs",   true)
    buildAuraColumn(panel, 210, "debuffs", "Debuffs", true)

    -- Grille du cadre courant (taille / par ligne / lignes max), bande horizontale
    -- en bas du panneau. Reglage PAR CADRE, partage buffs et debuffs.
    local gTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    gTitle:SetPoint("TOPLEFT", 8, -364)
    gTitle:SetText("Grille du cadre selectionne (buffs |cffaaaaaaet|r debuffs)")

    wipe(auraState.gridSliders)
    for i, info in ipairs(AURA_GRID_SLIDERS) do
        local s = makeAuraGridSlider(panel, "MarcelFramerAuraGrid" .. info.field, info)
        s:SetPoint("TOPLEFT", 22 + (i - 1) * 134, -398)
        auraState.gridSliders[i] = s
    end

    refreshAurasPanel()
end

-- ============================================================================
--  Section AFFICHAGE (onglet "Affichage") : disposition des textes des cadres
--  riches (player / target / focus). Reglage GLOBAL, applique a chaud via
--  ns:SetTextLayout. Au lieu d'un menu, on montre les DEUX dispositions sous forme
--  de mini-cadres d'apercu CLIQUABLES (rendus avec les vraies briques d'Elements,
--  donc fideles). Un clic selectionne la disposition ; la carte active a un liseré
--  doré.
-- ============================================================================
local displayState = { cards = {} }
local refreshDisplayPanel   -- forward-declare (reference par buildLayoutCard ci-dessous)

-- Remplit un mini-cadre d'apercu avec des valeurs d'exemple statiques (pas d'unite
-- reelle : on pose directement barres + textes, sans passer par Update*).
local function fillLayoutPreview(pf)
    local col = (ns.classBarColors and ns.classBarColors.MAGE) or { 0.22, 0.68, 0.81 }
    pf.health:SetMinMaxValues(0, 1)
    pf.health:SetValue(0.65)
    ns.Elements.PaintBar(pf.health, col[1], col[2], col[3], col[1], col[2], col[3])
    if pf.power then
        pf.power:SetMinMaxValues(0, 1)
        pf.power:SetValue(0.80)
        ns.Elements.PaintResource(pf.power, 0, "MANA")
    end
    if pf.nameText      then pf.nameText:SetText("Aethwyn")    end
    if pf.levelText     then pf.levelText:SetText("70")        end
    if pf.percentText   then pf.percentText:SetText("65%")     end
    if pf.healthText    then pf.healthText:SetText("2.4k")     end
    if pf.healthMaxText then pf.healthMaxText:SetText("/ 3.6k") end
    if pf.powerText     then pf.powerText:SetText("2.4k / 3.0k") end
    if pf.powerPctText  then pf.powerPctText:SetText("80%")    end
end

-- Couleurs de bordure de carte selon l'etat.
local CARD_BORDER = {
    selected = { 1, 0.82, 0, 1 },      -- doré = disposition active
    hover    = { 1, 1, 1, 0.7 },
    idle     = { 0.4, 0.4, 0.4, 0.8 },
}
local function setCardBorder(card, state)
    local c = CARD_BORDER[state]
    card:SetBackdropBorderColor(c[1], c[2], c[3], c[4])
end

-- Construit une carte d'apercu cliquable pour une disposition donnee (mode).
local function buildLayoutCard(panel, mode, label, anchorY)
    local card = CreateFrame("Button", nil, panel, "BackdropTemplate")
    card:SetSize(232, 78)
    card:SetPoint("TOPLEFT", 12, anchorY)
    card.mode = mode
    card:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    card:SetBackdropColor(0.06, 0.05, 0.04, 0.9)
    setCardBorder(card, "idle")

    -- Mini-cadre rendu avec les vraies briques (BuildVisuals) + mode force.
    local pf = CreateFrame("Frame", nil, card)
    pf.unitType = "player"
    pf.config = {
        width = 190, height = 45, fontSize = 12,
        powerRatio = 0.22, classColor = true,
        showPower = true, showName = true, showLevel = true,
        showPercent = true, showHealthValue = true, showPowerText = true,
    }
    pf:SetSize(190, 45)
    pf:SetPoint("LEFT", card, "LEFT", 6, 0)
    ns.Elements.BuildVisuals(pf)
    ns.Elements.LayoutRichText(pf, mode)     -- force la disposition de CETTE carte
    fillLayoutPreview(pf)

    local lbl = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lbl:SetPoint("TOPLEFT", pf, "BOTTOMLEFT", 0, -6)
    lbl:SetText(label)

    card:SetScript("OnClick", function(self)
        ns:SetTextLayout(self.mode)
        refreshDisplayPanel()
    end)
    card:SetScript("OnEnter", function(self)
        if not self.selected then setCardBorder(self, "hover") end
    end)
    card:SetScript("OnLeave", function(self)
        if not self.selected then setCardBorder(self, "idle") end
    end)

    displayState.cards[#displayState.cards + 1] = card
    return card
end

refreshDisplayPanel = function()
    local mode = (ns.config.textLayout == "stacked") and "stacked" or "classic"
    for _, card in ipairs(displayState.cards) do
        card.selected = (card.mode == mode)
        setCardBorder(card, card.selected and "selected" or "idle")
    end
end

local function buildDisplayPanel(panel)
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 4, -8)
    title:SetText("Disposition des textes")

    local intro = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    intro:SetPoint("TOPLEFT", 8, -30)
    intro:SetWidth(390)
    intro:SetJustifyH("LEFT")
    intro:SetText("Cliquez sur la disposition souhaitee (cadres Joueur / Cible / Focalisation). "
        .. "Apercu live, applique immediatement.")

    buildLayoutCard(panel, "classic", "Classique", -70)
    buildLayoutCard(panel, "stacked", "Empilee",   -174)

    refreshDisplayPanel()
end

-- ----------------------------------------------------------------------------
--  Onglets : affichage / bascule
-- ----------------------------------------------------------------------------
local function showTab(idx)
    for i, p in ipairs(panels) do
        if i == idx then p:Show() else p:Hide() end
    end
    for i, b in ipairs(tabButtons) do
        if i == idx then b:LockHighlight() else b:UnlockHighlight() end
    end
end

-- Bouton de la barre latérale gauche (menu vertical, extensible)
local function makeMenuButton(text, idx)
    local b = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    b:SetSize(134, 24)
    b:SetPoint("TOPLEFT", 12, -44 - (idx - 1) * 28)
    b:SetText(text)
    b:SetScript("OnClick", function() showTab(idx) end)
    tabButtons[idx] = b
    return b
end

local function makePanel()
    local p = CreateFrame("Frame", nil, frame)
    p:SetPoint("TOPLEFT", 162, -44)
    p:SetPoint("BOTTOMRIGHT", -12, 12)
    panels[#panels + 1] = p
    return p
end

local function build()
    frame = CreateFrame("Frame", "MarcelFramerOptions", UIParent, "BackdropTemplate")
    frame:SetSize(580, 480)
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
    -- Apercu d'auras lie a la fenetre : on coupe les auras factices a la fermeture
    -- (close, Echap ou /mf config) pour ne pas laisser de buffs fantomes.
    frame:SetScript("OnHide", function()
        if ns.auraPreview then ns:AuraTest(false) end
    end)
    tinsert(UISpecialFrames, "MarcelFramerOptions")   -- fermeture avec Echap

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -14)
    title:SetText("MarcelFramer \226\128\148 Configuration")

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    -- Barre latérale gauche : menu vertical (séparé du contenu par un trait)
    makeMenuButton("Classes", 1)
    makeMenuButton("Ressources & PNJ", 2)
    makeMenuButton("Cadres", 3)
    makeMenuButton("Barre de cast", 4)
    makeMenuButton("Auras", 5)
    makeMenuButton("Affichage", 6)

    local divider = frame:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(1, 1, 1, 0.12)
    divider:SetWidth(1)
    divider:SetPoint("TOPLEFT", 152, -40)
    divider:SetPoint("BOTTOMLEFT", 152, 12)

    -- Panneaux (un par onglet, dans l'ordre des index)
    buildClassPanel(makePanel())
    buildResourcePanel(makePanel())
    buildFramesPanel(makePanel())
    buildCastPanel(makePanel())
    buildAurasPanel(makePanel())
    buildDisplayPanel(makePanel())

    refreshColors()
    refreshSizeSliders()
    refreshCastState()
    refreshAurasPanel()
    refreshDisplayPanel()
    updateLockButton()
    showTab(1)

    -- Une frame fraichement creee est affichee par defaut : on la masque pour
    -- que le premier /mf config (qui appelle build) passe par la branche "show"
    -- de Toggle (sinon il faudrait deux appels pour l'ouvrir).
    frame:Hide()
end

function ns.Options.Toggle()
    if not frame then build() end
    if frame:IsShown() then
        frame:Hide()
    else
        refreshColors()
        refreshSizeSliders()
        refreshCastState()
        refreshAurasPanel()
        refreshDisplayPanel()
        updateLockButton()
        frame:Show()
    end
end
