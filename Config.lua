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
ns.media = {
    statusbar = "Interface\\Buttons\\WHITE8X8",
    font      = STANDARD_TEXT_FONT,
}

-- Degrade explicite par classe pour la barre de vie des JOUEURS (r,g,b en 0-1).
-- Utilise quand barStyle == "gradient" et classColor ~= false ; left = bord fonce
-- (0%), right = bord clair (100%). Mettre a nil pour revenir au degrade derive.
-- Ces valeurs sont prises telles quelles (pas d'adoucissement colorAdjust).
ns.classBarColors = {
    WARRIOR     = { left = {0.431, 0.267, 0.165}, right = {0.596, 0.431, 0.224} }, -- 6E442A -> 986E39
    PALADIN     = { left = {0.957, 0.475, 0.635}, right = {0.882, 0.494, 0.596} }, -- F479A2 -> E17E98
    DEATHKNIGHT = { left = {0.455, 0.059, 0.122}, right = {0.616, 0.114, 0.220} }, -- 740F1F -> 9D1D38
    MONK        = { left = {0.000, 0.431, 0.314}, right = {0.000, 0.690, 0.522} }, -- 006E50 -> 00B085
    PRIEST      = { left = {0.843, 0.808, 0.784}, right = {1.000, 1.000, 1.000} }, -- D7CEC8 -> FFFFFF
    DRUID       = { left = {0.769, 0.337, 0.000}, right = {0.808, 0.478, 0.196} }, -- C45600 -> CE7A32
    SHAMAN      = { left = {0.000, 0.255, 0.647}, right = {0.000, 0.369, 0.733} }, -- 0041A5 -> 005EBB
    MAGE        = { left = {0.075, 0.475, 0.584}, right = {0.216, 0.682, 0.808} }, -- 137995 -> 37AECE
    WARLOCK     = { left = {0.267, 0.267, 0.667}, right = {0.463, 0.467, 0.820} }, -- 4444AA -> 7677D1
    HUNTER      = { left = {0.392, 0.506, 0.290}, right = {0.557, 0.714, 0.412} }, -- 64814A -> 8EB669
    ROGUE       = { left = {0.780, 0.714, 0.231}, right = {0.875, 0.808, 0.400} }, -- C7B63B -> DFCE66
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

-- Couleurs de reaction des PNJ (et de toute unite sans couleur de classe).
-- Categorie derivee de UnitReaction (1-8) : <=2 hostile, 3 non amical (unfriendly),
-- 4 neutre, >=5 amical. Couleur unie {r,g,b} prise telle quelle (WYSIWYG, pas
-- d'adoucissement colorAdjust). Editable via /mf config.
ns.reactionColors = {
    hostile    = {0.75, 0.24, 0.24}, -- C73D3D
    unfriendly = {0.80, 0.52, 0.26}, -- CC8542
    neutral    = {0.80, 0.72, 0.26}, -- CCB842
    friendly   = {0.34, 0.63, 0.34}, -- 57A157
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

    -- Barres de vie des joueurs : true = degrade 2 teintes (left->right de
    -- ns.classBarColors) ; false = couleur unie (la teinte "right"). Reglable
    -- aussi via la fenetre /mf config.
    classGradient = true,

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
    --  Cadres simples
    -- ----------------------------------------------------------------------
    player = {
        enabled       = true,
        width         = 190, height = 45, scale = 1,
        point         = { point = "CENTER", relPoint = "CENTER", x = -213, y = -127 },
        powerRatio    = 0.26,
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
        powerRatio    = 0.26,
        classColor    = true,
        mirror        = true,              -- cadre en miroir du joueur
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
