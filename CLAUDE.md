# CLAUDE.md — MarcelFramer

> Indications spécifiques à l'addon **MarcelFramer**. Le `CLAUDE.md` parent
> (`AddOns/CLAUDE.md`) s'applique aussi pour tout ce qui est générique WoW
> (format TOC, codes version, taint, conventions API). Ce fichier ne le duplique
> pas : il couvre uniquement ce projet. **Répondre en français.**

## Ce qu'est MarcelFramer

Addon **maison de unit frames** pour **WoW Classic — MoP 5.5.4** (`## Interface: 50504`).
Il **remplace ShadowedUnitFrames** et devient le **système principal de cadres
d'unités** : il doit fonctionner **en combat**, gérer la **sélection au clic**, et
**masquer les frames Blizzard** par défaut. Ce ne sont pas des maquettes : c'est
l'UI d'unités réelle du joueur.

Frames gérées : **player, target, targettarget, pet, party, raid**.
Caractéristiques (selon le type) : couleur de classe (ou couleur perso), barre de
vie, textes (nom, classe, PV, pourcentage), barre de ressource (mana/énergie/rage),
buffs/debuffs.

## Sources de vérité

- **Plan approuvé** (fait foi pour tous les détails) : `C:\Users\Louis\.claude\plans\tidy-conjuring-salamander.md`
- En cas de doute sur un détail, relire le plan **avant** de coder.

## Workflow Git — IMPORTANT

- **Ne JAMAIS pousser sur `main` ni `develop`** (ni y committer directement).
  Ces branches sont réservées ; toute modification passe **systématiquement par
  une Pull Request**.
- Cycle : créer une **branche dédiée** (`feature/…`, `fix/…`, `docs/…`) →
  committer dessus → pousser **la branche** → ouvrir une **PR** (cible `develop`
  par défaut).

## Décisions verrouillées — NE PAS rediscuter

- **Autonome, zéro dépendance.** API WoW pure. **Aucune** bibliothèque externe
  (pas d'Ace3, pas d'oUF, pas de LibStub). Partage d'état entre fichiers via
  `local addonName, ns = ...` (la table `ns`), pas de globaux superflus.
- **Frames Blizzard masquées/remplacées** par défaut.
- **Config principalement via table Lua éditable** (`Config.lua`) + déplacement
  des frames à la souris via slash. Une **petite fenêtre d'options** existe
  (`Options.lua`, `/mf config`) limitée aux **couleurs par classe** (sélecteur
  Blizzard, sauvegarde `MarcelFramerDB`, aperçu live `ns:RefreshAll()`). Garder
  toute UI d'options minimale et optionnelle.
- **Nom de l'addon : `MarcelFramer`** (nom verrouillé ; le plan/prompt d'origine
  parlait de « MesFrames », un placeholder désormais abandonné). Slash
  `/marcelframer` et `/mf`, `## SavedVariables: MarcelFramerDB`.

## Structure des fichiers & ordre de chargement

Ordre dans le `.toc` (à respecter, dépendances de chargement) :

```
MarcelFramer.toc   ## Interface: 50504   ## SavedVariables: MarcelFramerDB
Config.lua         Table ns.config : un bloc de réglages par frame + defaults
Core.lua           Init (PLAYER_LOGIN), SavedVariables, masquage Blizzard, slash, mode déplacement
Elements.lua       Briques réutilisables : barre de vie, barre de ressource, textes, couleur, auras
UnitFrame.lua      Frames simples : player / target / targettarget / pet
GroupFrames.lua    party + raid via SecureGroupHeaderTemplate
Options.lua        Fenêtre /mf config : couleurs par classe (ColorPickerFrame)
```

## Conventions par fichier

- **Config.lua** — `ns.config` avec une entrée par frame (`player`, `target`,
  `targettarget`, `pet`, `party`, `raid`). Champs : `enabled`, `width`, `height`,
  `point = {anchor, relPoint, x, y}`, `scale`, drapeaux d'éléments (`showPower`,
  `showName`, `showLevel`, `showPercent`, `showBuffs`, `showDebuffs`, `numAuras`),
  couleur (`classColor = true` ou `color = {r,g,b}`). Éditable à la main puis `/reload`.
- **Elements.lua** — fonctions **partagées** appelées par `UnitFrame` ET
  `GroupFrames` (ne pas dupliquer la logique de barres/textes/auras) :
  `CreateHealthBar`/`UpdateHealth`, `CreatePowerBar`/`UpdatePower`, `UpdateText`,
  `UpdateAuras(frame, unit, filter)`.
- **UnitFrame.lua** — frames simples player/target/targettarget/pet.
- **GroupFrames.lua** — `header.initialConfigFunction` construit chaque bouton en
  **réutilisant les briques d'`Elements.lua`**.

## Patterns techniques clés

- **Frames simples** : `CreateFrame("Button", "MarcelFramer"..nom, UIParent,
  "SecureUnitButtonTemplate")` + `SetAttribute("unit", u)`. `RegisterUnitWatch`
  pour target/targettarget/pet (player toujours visible). Clic sûr en combat :
  `RegisterForClicks("AnyUp")`, `SetAttribute("*type1","target")`,
  `SetAttribute("*type2","togglemenu")`.
- **Mises à jour pilotées par événements filtrés par unité** : `UNIT_HEALTH`,
  `UNIT_MAXHEALTH`, `UNIT_POWER_UPDATE`, `UNIT_MAXPOWER`, `UNIT_DISPLAYPOWER`,
  `UNIT_AURA`, `UNIT_NAME_UPDATE`, `UNIT_LEVEL`, `PLAYER_TARGET_CHANGED`,
  `UNIT_PET`, `UNIT_TARGET`. **Throttler** les events haute fréquence.
- **targettarget** : pas d'event fiable → polling `OnUpdate` throttlé (~0,25 s)
  en complément des events.
- **party / raid** : `SecureGroupHeaderTemplate`. party → `showParty=true`,
  `showRaid=false` ; raid → `showRaid=true`, `groupFilter="1,2,3,4,5,6,7,8"`,
  grille via `maxColumns`/`unitsPerColumn`/`columnSpacing`/`columnAnchorPoint`.
  `SetAttribute("template","SecureUnitButtonTemplate")`,
  `SetAttribute("initial-unitWatch", true)`. (Extension : pets de raid via
  `SecureGroupPetHeaderTemplate`.)
- **Masquage Blizzard** : `UnregisterAllEvents()` + `frame.Show = noop` +
  `frame:Hide()` sur `PlayerFrame`, `TargetFrame`, `TargetFrameToT`, `PetFrame`,
  `FocusFrame`, `PartyMemberFrame1..4` (+ leurs `HealthBar`/`ManaBar`). Raid
  Blizzard (**protégé**) **hors combat seulement** :
  `CompactRaidFrameManager_SetSetting("IsShown","0")` puis masquer
  `CompactRaidFrameManager` / `CompactRaidFrameContainer`.
- **Couleurs** : joueurs → `RAID_CLASS_COLORS` via `UnitClass` ; PNJ →
  `UnitReaction` ; ressource → `PowerBarColor`.
- **Auras** : détecter `C_UnitAuras.GetAuraDataByIndex` au chargement, repli sur
  `UnitAura` sinon.
- **Slash** `/marcelframer` (et `/mf`) : `unlock` / `lock` (déplacement souris,
  sauvegarde du point dans `MarcelFramerDB`), `reset` (positions par défaut).

## Taint & combat — zone sensible

- Ne **jamais** déplacer/masquer un cadre sécurisé en combat. Garder
  `InCombatLockdown()` et différer via `PLAYER_REGEN_ENABLED` au besoin.
- Le repositionnement des en-têtes sécurisés (party/raid) se fait **hors combat**.
- Le masquage du raid Blizzard est le point le plus à risque de taint.
- Menu contextuel d'unité : utiliser le menu **sécurisé** (attribut `togglemenu`)
  pour rester fonctionnel en combat.

## Références (code qui marche sur cette version — lire, ne PAS copier)

- Masquage frames Blizzard : `ShadowedUnitFrames\ShadowedUnitFrames.lua` ~440-546.
- Boutons sécurisés + en-têtes party/raid : `ShadowedUnitFrames\modules\units.lua` ~794-870.
- Lire ces extraits pour caler les détails MoP exacts, mais **écrire son propre code**.

## Ordre d'implémentation

1. **Squelette + frames simples** : `.toc`, `Config.lua`, `Core.lua` (init +
   masquage Blizzard + slash), `Elements.lua` (vie/ressource/texte/couleur),
   `UnitFrame.lua` (player/target/targettarget/pet) avec clic. → Déjà utilisable.
2. **Groupe & raid** : `GroupFrames.lua`.
3. **Buffs/debuffs** : `UpdateAuras`.
4. **Déplacement souris** (`/mf unlock`) + réglages additionnels.

Après chaque étape, indiquer **ce qui est testable en jeu**.

## Vérification

Pas de build ni de test automatisé : l'utilisateur teste **lui-même en jeu**
(`/reload`, `/console scriptErrors 1`). Livrer du code propre, sans erreur Lua, et
fournir la **checklist de test** en fin d'étape (cf. section « Vérification » du
plan). Prérequis géré par l'utilisateur : **désactiver ShadowedUnitFrames** avant
les tests (sinon double masquage Blizzard + conflits de frames).
