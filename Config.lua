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

-- Comportement global
ns.config = {
    -- Masquage des cadres Blizzard par defaut
    hideBlizzard     = true,   -- player/target/tot/pet/focus/party
    hideBlizzardRaid = true,   -- cadres de raid compacts Blizzard (protege : hors combat)

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
    --  Cadres simples
    -- ----------------------------------------------------------------------
    player = {
        enabled       = true,
        width         = 220, height = 48, scale = 1,
        point         = { point = "CENTER", relPoint = "CENTER", x = -300, y = -160 },
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
        showBuffs     = true,
        showDebuffs   = true,
        numAuras      = 6,
        auraSize      = 20,
        fontSize      = 12,
    },
    target = {
        enabled       = true,
        width         = 220, height = 48, scale = 1,
        point         = { point = "CENTER", relPoint = "CENTER", x = 300, y = -160 },
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
        showBuffs     = true,
        showDebuffs   = true,
        numAuras      = 6,
        auraSize      = 20,
        fontSize      = 12,
    },
    targettarget = {
        enabled    = true,
        width      = 130, height = 26, scale = 1,
        point      = { point = "CENTER", relPoint = "CENTER", x = 300, y = -235 },
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
        width      = 150, height = 30, scale = 1,
        point      = { point = "CENTER", relPoint = "CENTER", x = -300, y = -235 },
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

    -- ----------------------------------------------------------------------
    --  Cadres de groupe (en-tetes securises)
    --  attribPoint : sens de croissance dans une colonne (TOP = vers le bas).
    -- ----------------------------------------------------------------------
    party = {
        enabled       = true,
        width         = 160, height = 40, scale = 1,
        point         = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 30, y = -250 },
        attribPoint   = "TOP",   -- empile vers le bas
        spacing       = 8,
        showPlayer    = false,   -- afficher aussi le joueur dans le cadre party
        powerRatio    = 0.24,
        classColor    = true,
        showPower     = true,
        showName      = true,
        showLevel     = false,
        showPercent   = true,
        showBuffs     = false,
        showDebuffs   = true,
        numAuras      = 3,
        auraSize      = 16,
        fontSize      = 11,
    },
    raid = {
        enabled          = true,
        width            = 90, height = 36, scale = 1,
        point            = { point = "TOPLEFT", relPoint = "TOPLEFT", x = 30, y = -250 },
        attribPoint      = "TOP",   -- empile vers le bas dans une colonne
        spacing          = 4,
        unitsPerColumn   = 5,
        maxColumns       = 8,
        columnSpacing    = 6,
        columnAnchorPoint= "LEFT",  -- les colonnes s'ajoutent vers la droite
        groupFilter      = "1,2,3,4,5,6,7,8",
        powerRatio       = 0.18,
        classColor       = true,
        showPower        = true,
        showName         = true,
        showLevel        = false,
        showPercent      = false,
        showBuffs        = false,
        showDebuffs      = false,
        numAuras         = 0,
        fontSize         = 9,
    },
}
