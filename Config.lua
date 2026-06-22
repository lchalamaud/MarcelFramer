local addonName, ns = ...

-- ============================================================================
--  Config.lua — Reglages editables de MarcelFramer
--  Edite ces valeurs a la main puis /reload pour appliquer.
--  Les positions deplacees a la souris (/mf unlock) sont sauvegardees dans
--  MarcelFramerDB.positions et ont priorite sur les "point" ci-dessous.
-- ============================================================================

-- Medias partages (textures / police)
-- statusbar = texture de base des barres. WHITE8X8 = aplat propre, sert aussi
-- de support au degrade doux (voir barStyle). Le style "blizzard" ignore ceci.
--
-- Police : Rajdhani (celle de la maquette), embarquee dans media/ (licence OFL,
-- voir media/OFL.txt). 3 graisses fournies ; on en choisit UNE pour tout l'addon
-- (WoW ne gere pas le font-weight : l'emphase passe par le flag "OUTLINE").
-- Si le fichier est introuvable au chargement, Core.lua bascule automatiquement
-- sur STANDARD_TEXT_FONT (repli propre).
local FONT_PATH = "Interface\\AddOns\\MarcelFramer\\media\\"
ns.media = {
    statusbar = "Interface\\Buttons\\WHITE8X8",
    fonts = {
        medium   = FONT_PATH .. "Rajdhani-Medium.ttf",
        semibold = FONT_PATH .. "Rajdhani-SemiBold.ttf",
        bold     = FONT_PATH .. "Rajdhani-Bold.ttf",
    },
}
-- Graisse utilisee partout (medium / semibold / bold). Defaut : semibold.
ns.media.font = ns.media.fonts.semibold

-- Couleur de la barre de vie des JOUEURS : UNE teinte par classe (r,g,b en 0-1).
-- Le relief vient du gloss vertical (plus de degrade 2 teintes). Prise telle
-- quelle (pas d'adoucissement colorAdjust). Editable via /mf config (onglet Classes).
ns.classBarColors = {
    WARRIOR     = {0.596, 0.431, 0.224}, -- 986E39
    PALADIN     = {0.882, 0.494, 0.596}, -- E17E98
    DEATHKNIGHT = {0.616, 0.114, 0.220}, -- 9D1D38
    MONK        = {0.000, 0.690, 0.522}, -- 00B085
    PRIEST      = {1.000, 1.000, 1.000}, -- FFFFFF
    DRUID       = {0.808, 0.478, 0.196}, -- CE7A32
    SHAMAN      = {0.000, 0.369, 0.733}, -- 005EBB
    MAGE        = {0.216, 0.682, 0.808}, -- 37AECE
    WARLOCK     = {0.463, 0.467, 0.820}, -- 7677D1
    HUNTER      = {0.557, 0.714, 0.412}, -- 8EB669
    ROGUE       = {0.875, 0.808, 0.400}, -- DFCE66
}

-- Couleurs des barres de RESSOURCE, par type de pouvoir (jeton renvoye par
-- UnitPowerType). Couleur unie {r,g,b} en 0-1 ; le degrade eventuel est derive
-- par luminosite (voir barStyle/barGradient). Les jetons absents ici (CHI,
-- HOLY_POWER, COMBO_POINTS, ...) retombent sur PowerBarColor Blizzard.
-- Editable aussi via la fenetre /mf config (onglet "Ressources & PNJ").
ns.powerColors = {
    MANA        = {0.20, 0.40, 0.95}, -- 3366F2
    RAGE        = {0.78, 0.20, 0.20}, -- C73333
    ENERGY      = {0.90, 0.82, 0.25}, -- E6D140
    FOCUS       = {0.90, 0.55, 0.30}, -- E68C4D
    RUNIC_POWER = {0.30, 0.70, 0.85}, -- 4DB3D9
}

-- Degrades VERTICAUX explicites de la barre de ressource (stops de la maquette,
-- CSS linear-gradient(to bottom, top -> bottom)). top = bord clair (haut),
-- bottom = bord fonce (bas). Utilises tels quels en mode "gradient" tant que la
-- couleur du jeton n'a PAS ete personnalisee via /mf config : dans ce cas on
-- derive plutot un degrade vertical de la couleur unie editee (ns.powerColors),
-- pour respecter le choix de l'utilisateur. Jetons absents -> ns.powerColors.
ns.powerGradients = {
    MANA        = { top = {0.290, 0.569, 0.910}, bottom = {0.122, 0.373, 0.722} }, -- 4A91E8 -> 1F5FB8
    RAGE        = { top = {0.878, 0.337, 0.294}, bottom = {0.639, 0.165, 0.133} }, -- E0564B -> A32A22
    ENERGY      = { top = {0.910, 0.812, 0.341}, bottom = {0.710, 0.573, 0.122} }, -- E8CF57 -> B5921F
    FOCUS       = { top = {0.937, 0.573, 0.333}, bottom = {0.749, 0.369, 0.149} }, -- EF9255 -> BF5E26
    RUNIC_POWER = { top = {0.322, 0.776, 0.902}, bottom = {0.122, 0.541, 0.698} }, -- 52C6E6 -> 1F8AB2
}

-- Couleurs de reaction des PNJ (et de toute unite sans couleur de classe).
-- Categorie derivee de UnitReaction (1-8) : <=2 hostile, 3 non amical (unfriendly),
-- 4 neutre, >=5 amical. Couleur unie {r,g,b} prise telle quelle (WYSIWYG, pas
-- d'adoucissement colorAdjust). Editable via /mf config.
ns.reactionColors = {
    hostile    = {0.878, 0.196, 0.180}, -- E0322E (maquette v2)
    unfriendly = {0.910, 0.400, 0.122}, -- E8661F
    neutral    = {0.847, 0.839, 0.243}, -- D8D63E
    friendly   = {0.306, 0.824, 0.341}, -- 4ED257
}

-- Couleurs de la barre d'incantation, selon l'interruptibilite du sort.
-- WoW expose `notInterruptible` (8e retour de UnitCastingInfo/UnitChannelInfo) et
-- bascule en direct via UNIT_SPELLCAST_(NOT_)INTERRUPTIBLE : la barre se recolore
-- meme si l'etat change en plein cast.
--   distinguish = true  : deux couleurs distinctes (interruptible vs non).
--   distinguish = false : une seule couleur (`interruptible`) pour tous les sorts.
-- Couleur unie {r,g,b} en 0-1 ; le style global (barStyle) derive le degrade.
-- Convention frequente (reprise ici) : jaune = interruptible, gris = non.
-- Editable aussi via la fenetre /mf config (onglet "Barre de cast").
ns.castColors = {
    distinguish      = true,
    interruptible    = {0.937, 0.788, 0.341}, -- EFC957 (jaune)
    notInterruptible = {0.60, 0.60, 0.60},    -- 999999 (gris)
}

-- Mappe une valeur de UnitReaction (1-8) vers une cle de ns.reactionColors.
function ns.ReactionCategory(reaction)
    if not reaction then return nil end
    if reaction <= 2 then return "hostile"
    elseif reaction == 3 then return "unfriendly"
    elseif reaction == 4 then return "neutral"
    else return "friendly" end
end

-- Comportement global
ns.config = {
    -- Masquage des cadres Blizzard par defaut.
    -- player/target/tot/pet/focus uniquement. Le groupe et le raid utilisent
    -- l'interface Blizzard de base (non masques par MarcelFramer).
    hideBlizzard     = true,

    -- Adoucissement des couleurs de classe / reaction (moins flashy).
    -- saturation 1 = couleur pure ; 0 = gris. brightness 1 = normal ; < 1 = plus sombre.
    colorAdjust = { saturation = 0.78, brightness = 0.88 },

    -- Style des barres de ressource / cast / PNJ : "gradient" (degrade derive),
    -- "flat" (aplat uni) ou "blizzard" (texture brillante d'origine).
    barStyle = "gradient",

    -- Reglage du degrade (style linear-gradient, derive de la couleur de classe).
    -- dark/light = facteurs de LUMINOSITE (on reste dans la teinte, pas de blanc) :
    --   dark        : ton fonce  = couleur * dark   (plus bas = plus fonce)
    --   light       : ton clair  = couleur * light  (1.0 = la couleur telle quelle ;
    --                 > 1 pour eclaircir un peu, ex. 1.1)
    --   orientation : "HORIZONTAL" (gauche->droite, comme linear-gradient 90deg)
    --                 ou "VERTICAL" (bas->haut)
    -- Rapport dark/light ~= 0.72 reproduit l'ecart de l'exemple (145,105,64)->(199,145,84).
    barGradient = { dark = 0.72, light = 1.0, orientation = "HORIZONTAL" },

    -- ----------------------------------------------------------------------
    --  Style "maquette" : couleurs de piste + reflets (gloss) + badge combat
    -- ----------------------------------------------------------------------
    -- Couleur de fond (piste) des barres vide, {r,g,b} en 0-1 (maquette).
    healthTrack = { 0.141, 0.122, 0.106 }, -- 241F1B
    powerTrack  = { 0.098, 0.086, 0.106 }, -- 19161B
    -- Reflets glossy sur la barre de vie (overlay vertical + liseres) et reflet
    -- haut sur la ressource. Traduction des linear-gradient/box-shadow CSS.
    glossy = true,
    -- Indicateur de combat : la maquette v2 utilise la simple icone d'epees
    -- croisees (atlas) en coin, PAS le badge circulaire. false = icone plate.
    combatBadge = false,
    -- Coins arrondis (masque applique aux textures de barre). EXPERIMENTAL :
    -- depend de la presence du masque "common-iconmask" sur le client. Si les
    -- barres disparaissent apres activation, le masque est absent : remettre a
    -- false. Desactive par defaut par securite (non testable hors du jeu).
    roundedCorners = false,

    -- ----------------------------------------------------------------------
    --  Cadres simples
    -- ----------------------------------------------------------------------
    player = {
        enabled       = true,
        width         = 190, height = 45, scale = 1,
        point         = { point = "CENTER", relPoint = "CENTER", x = -213, y = -127 },
        powerRatio    = 0.22,              -- ~10/45 (barre de ressource fine, maquette)
        classColor    = true,              -- true = couleur de classe / reaction ; sinon color = {r,g,b}
        -- color      = { 0.2, 0.6, 0.2 },
        showPower     = true,
        showName      = true,
        showLevel     = true,
        showPercent   = true,              -- pourcentage de PV
        showHealthValue = true,            -- PV en valeur (actuel/max)
        showPowerText = true,              -- valeur de ressource
        showCastBar   = true,              -- barre d'incantation
        castHeight    = 18,
        showCombat    = true,              -- icone de combat (coin haut)
        combatSize    = 18,
        -- combatStyle : design de l'icone (sprite plat transparent, facon emoji).
        -- Valeurs : "combat" (defaut, epees croisees rouges de l'atlas),
        --           "swords", "skull", "cross", "star", "diamond", "triangle".
        -- combatStyle = "skull",
        -- Overrides libres : combatAtlas = "NomDAtlasBlizzard", ou
        --   combatTexture = "Interface\\...\\Truc" (+ combatTexCoord = {l,r,h,b}).
        -- combatColor = {r,g,b} : teinte l'icone (defaut du preset "combat" = rouge doux).
        showBuffs     = true,
        showDebuffs   = true,
        numAuras      = 6,
        auraSize      = 20,
        fontSize      = 12,
    },
    target = {
        enabled       = true,
        width         = 190, height = 45, scale = 1,
        point         = { point = "CENTER", relPoint = "CENTER", x = 213, y = -127 },
        powerRatio    = 0.22,              -- ~10/45 (barre de ressource fine, maquette)
        classColor    = true,
        showPower     = true,
        showName      = true,
        showLevel     = true,
        levelDifficultyColor = true,       -- niveau colore selon l'ecart de niveau
        showPercent   = true,
        showHealthValue = true,
        showPowerText = true,
        showCastBar   = true,
        castHeight    = 18,
        showCombat    = true,              -- icone de combat (coin haut)
        combatSize    = 18,
        showBuffs     = true,
        showDebuffs   = true,
        numAuras      = 6,
        auraSize      = 20,
        fontSize      = 12,
    },
    focus = {
        enabled       = true,
        width         = 190, height = 45, scale = 1,
        point         = { point = "CENTER", relPoint = "CENTER", x = 0, y = 220 },
        powerRatio    = 0.22,              -- ~10/45 (barre de ressource fine, maquette)
        classColor    = true,
        showPower     = true,
        showName      = true,
        showLevel     = true,
        levelDifficultyColor = true,       -- niveau colore selon l'ecart de niveau
        showPercent   = true,
        showHealthValue = true,
        showPowerText = true,
        showCastBar   = true,              -- barre d'incantation (activable via /mf config)
        castHeight    = 18,
        showCombat    = true,              -- icone de combat (coin haut)
        combatSize    = 18,
        showBuffs     = true,
        showDebuffs   = true,
        numAuras      = 6,
        auraSize      = 20,
        fontSize      = 12,
    },
    targettarget = {
        enabled    = true,
        width      = 100, height = 20, scale = 1,
        point      = { point = "RIGHT", relPoint = "RIGHT", x = -350, y = -140 },
        classColor = true,
        showPower  = false,
        showName   = true,
        showLevel  = false,
        showPercent= false,
        showBuffs  = false,
        showDebuffs= false,
        numAuras   = 0,
        fontSize   = 10,
    },
    pet = {
        enabled    = true,
        width      = 125, height = 25, scale = 1,
        point      = { point = "LEFT", relPoint = "LEFT", x = 339, y = -188 },
        powerRatio = 0.30,
        classColor = false, color = { 0.45, 0.55, 0.75 },
        showPower  = true,
        showName   = true,
        showLevel  = false,
        showPercent= true,
        showBuffs  = false,
        showDebuffs= false,
        numAuras   = 0,
        fontSize   = 10,
    },
}
