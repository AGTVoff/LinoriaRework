# LinoriaLib Modernized

Version modernisée de la bibliothèque d'interface Roblox **LinoriaLib**
(basée sur [violin-suzutsuki/LinoriaLib](https://github.com/violin-suzutsuki/LinoriaLib)).

L'objectif de cette version est purement visuel et ergonomique : un design plus
propre, plus contrasté et animé, **sans casser l'API publique existante**.
Tous les scripts écrits pour LinoriaLib continuent de fonctionner tels quels.

---

## Sommaire

- [Installation](#installation)
- [Utilisation rapide](#utilisation-rapide)
- [Ce qui a changé](#ce-qui-a-changé)
- [Système d'animations](#système-danimations)
- [Jetons de design](#jetons-de-design)
- [API publique](#api-publique)
- [Nouvelles fonctions optionnelles](#nouvelles-fonctions-optionnelles)
- [Thèmes](#thèmes)
- [Configurations](#configurations)
- [Exemple complet](#exemple-complet)
- [Compatibilité avec l'ancienne API](#compatibilité-avec-lancienne-api)
- [Structure recommandée](#structure-recommandée)

---

## Installation

### 1. Chargement distant (Raw GitHub) — recommandé

```lua
local repo = 'https://raw.githubusercontent.com/<utilisateur>/<depot>/main/'

local Library      = loadstring(game:HttpGet(repo .. 'Library.lua'))()
local ThemeManager = loadstring(game:HttpGet(repo .. 'addons/ThemeManager.lua'))()
local SaveManager  = loadstring(game:HttpGet(repo .. 'addons/SaveManager.lua'))()
```

`Library.lua` se termine par `return Library` **et** définit `getgenv().Library`,
donc les deux styles d'accès fonctionnent.

### 2. Utilisation locale (ModuleScript dans Roblox Studio)

Placez `Library.lua` comme `ModuleScript` puis :

```lua
local Library = require(script.Parent.Library)
local ThemeManager = require(script.Parent.addons.ThemeManager)
local SaveManager = require(script.Parent.addons.SaveManager)
```

> Attention : `ThemeManager` et `SaveManager` utilisent les fonctions de système
> de fichiers des exécuteurs (`writefile`, `isfolder`, ...). En Studio, ces
> fonctions n'existent pas : les thèmes et configurations ne seront pas
> persistants, mais la bibliothèque elle-même fonctionne.

### 3. Fichier local via un exécuteur

```lua
local Library = loadstring(readfile('LinoriaLib/Library.lua'))()
```

### Différences entre les méthodes

| Méthode | Avantages | Inconvénients |
| --- | --- | --- |
| Raw GitHub (`HttpGet`) | Mise à jour automatique, un seul fichier à distribuer | Nécessite une connexion, dépend de GitHub |
| `require()` en Studio | Pas de réseau, débogage et autocomplétion | Pas de sauvegarde de fichiers, mise à jour manuelle |
| `readfile()` local | Fonctionne hors ligne, très rapide | L'utilisateur doit installer les fichiers |

---

## Utilisation rapide

```lua
local Window = Library:CreateWindow({
    Title = 'Mon menu',
    Center = true,
    AutoShow = true,
    TabPadding = 8,
    MenuFadeTime = 0.2,
})

local Tab = Window:AddTab('Main')
local Box = Tab:AddLeftGroupbox('Général')

Box:AddToggle('MyToggle', { Text = 'Activer', Default = false })
Box:AddSlider('MySlider', { Text = 'Vitesse', Default = 1, Min = 0, Max = 10, Rounding = 1 })

Toggles.MyToggle:OnChanged(function()
    print(Toggles.MyToggle.Value)
end)
```

---

## Ce qui a changé

### Fenêtre
- Coins arrondis, halo d'élévation sombre derrière la fenêtre, contour fin.
- Barre de titre de 36 px avec police *Gotham Bold*, point d'accentuation et séparateur.
- Panneau de contenu « encastré » (fond plus sombre) → hiérarchie visuelle sur 3 niveaux.
- Animation d'ouverture/fermeture : fondu + échelle + léger décalage vertical.

### Onglets
- Boutons d'onglet en forme de pilule, avec **indicateur d'accentuation animé** qui
  glisse d'un onglet à l'autre.
- Le changement d'onglet n'est plus instantané : fondu (via `CanvasGroup` quand
  l'exécuteur le supporte), glissement horizontal et micro-zoom.
- Retour visuel au survol des onglets inactifs.

### Groupboxes et Tabboxes
- Groupbox = carte surélevée arrondie avec en-tête de 34 px et petite barre
  d'accentuation devant le titre.
- Tabbox = *segmented control* moderne avec segment actif animé et fondu du contenu.

### Composants
- **Toggles** : véritable interrupteur à pilule avec pouce animé (easing `Back`),
  transition de couleur, survol et retour de clic.
- **Sliders** : piste arrondie, remplissage animé, poignée circulaire qui grossit
  au survol, drag très réactif (piloté par les événements, **pas** de `RenderStepped` permanent).
- **Dropdowns / multi-dropdowns** : ouverture/fermeture animée (hauteur), flèche
  qui tourne, survol des lignes, barre d'accentuation sur les éléments sélectionnés.
- **Inputs** : champ arrondi avec anneau de focus animé.
- **Boutons** : coins arrondis, voile de survol, feedback de clic par mise à l'échelle.
- **Color picker** : fenêtre arrondie 244 px, carte saturation/valeur 200×200,
  barre de teinte en pilule, curseur en anneau, animation d'apparition.
- **Key picker** : pastille en pilule, menu de mode animé.
- **Notifications** : cartes arrondies avec barre d'accentuation, titre optionnel,
  animation d'entrée et de sortie, empilement propre.
- **Watermark et liste de raccourcis** : arrondis, contour d'accentuation, meilleur espacement.
- **Tooltips** : affichage/masquage animé, gestion par événements.

### Performance
- La boucle `RenderStepped` permanente de l'effet arc-en-ciel est devenue un
  `Heartbeat` limité à ~30 Hz.
- Les trois boucles de glissement du color picker et celle du slider utilisent
  désormais `Library:BindDrag` (connexions créées à l'appui, déconnectées au relâchement).
- `Library:MakeDraggable` et `Library:AddToolTip` sont pilotés par événements.
- Le curseur personnalisé (`Drawing.new`) est encapsulé dans un `pcall` et peut
  être désactivé (`Library.ShowCustomCursor = false`).
- Toutes les connexions passent par `Library:GiveSignal` / `Library:Unload`.

---

## Système d'animations

Toute la motion est centralisée dans `Library.Animations` :

| Clé | Défaut | Rôle |
| --- | --- | --- |
| `Enabled` | `true` | Coupe **tous** les tweens de la bibliothèque si `false` |
| `Fast` | `0.12` | Survol, feedback de clic |
| `Normal` | `0.18` | Transitions standard |
| `Slow` | `0.28` | Transitions longues |
| `Window` | `0.24` | Ouverture / fermeture de la fenêtre |
| `Easing` | `Enum.EasingStyle.Quart` | Style d'interpolation par défaut |
| `Direction` | `Enum.EasingDirection.Out` | Direction par défaut |
| `TabFade` | `true` | Fondu lors du changement d'onglet |
| `TabSlide` | `14` | Glissement horizontal de l'onglet (px) |
| `TabScale` | `0.99` | Échelle de départ de l'onglet |
| `TabDuration` | `0.2` | Durée de la transition d'onglet |

```lua
Library.Animations.Enabled = false      -- interface entièrement instantanée
Library.Animations.TabDuration = 0.12   -- transitions d'onglet plus vives
```

---

## Jetons de design

Exposés directement sur `Library`, modifiables **avant** `CreateWindow` :

| Jeton | Défaut |
| --- | --- |
| `Font` | `Enum.Font.GothamMedium` |
| `FontHeavy` | `Enum.Font.GothamBold` |
| `FontRegular` | `Enum.Font.Gotham` |
| `TextSize` | `14` |
| `TitleTextSize` | `15` |
| `TextStrokes` | `false` |
| `CornerRadius` | `UDim.new(0, 6)` |
| `SmallCornerRadius` | `UDim.new(0, 4)` |
| `PillCornerRadius` | `UDim.new(1, 0)` |
| `StrokeThickness` | `1` |
| `Spacing` | `{ XS=2, SM=4, MD=8, LG=12, XL=16 }` |
| `HoverTransparency` | `0.88` |
| `PressedTransparency` | `0.76` |
| `ShowCustomCursor` | `true` |
| `NotificationSide` | `'Left'` |

Palette par défaut : `FontColor` `#EBEDF5`, `MainColor` `#1A1B21`,
`BackgroundColor` `#111217`, `AccentColor` `#6080FF`, `OutlineColor` `#2D2F3A`,
`RiskColor` `#FF5454`.

---

## API publique

Inchangée par rapport à LinoriaLib. Résumé :

**Fenêtre / onglets**
`Library:CreateWindow(Config)`, `Window:SetWindowTitle(Titre)`, `Window:AddTab(Nom)`,
`Tab:SetLayoutOrder(N)`, `Tab:ShowTab()`, `Tab:HideTab()`,
`Tab:AddLeftGroupbox(Nom)`, `Tab:AddRightGroupbox(Nom)`, `Tab:AddGroupbox(Info)`,
`Tab:AddLeftTabbox(Nom)`, `Tab:AddRightTabbox(Nom)`, `Tab:AddTabbox(Info)`,
`Tabbox:AddTab(Nom)`, `Tab:Show()`, `Tab:Hide()`, `Tab:Resize()`, `Groupbox:Resize()`.

**Éléments** (sur un Groupbox ou un onglet de Tabbox)
`AddToggle(Idx, Info)`, `AddSlider(Idx, Info)`, `AddDropdown(Idx, Info)`,
`AddInput(Idx, Info)`, `AddButton(Info)`, `AddLabel(Texte, Wrap)`,
`AddDivider()`, `AddBlank(Taille)`, `AddDependencyBox()`,
et sur un Label ou un Toggle : `AddColorPicker(Idx, Info)`, `AddKeyPicker(Idx, Info)`.

**Objets**
`Toggles[Idx]` → `.Value`, `:SetValue(bool)`, `:OnChanged(fn)`
`Options[Idx]` → `.Value`, `:SetValue(...)`, `:OnChanged(fn)`, `:SetValues(liste)` (dropdown),
`:SetValueRGB(Color3)` / `:SetHSVFromRGB(Color3)` (color picker),
`:GetState()`, `:OnClick(fn)` (key picker).

**Divers**
`Library:Notify(Texte, Durée)`, `Library:SetWatermark(Texte)`,
`Library:SetWatermarkVisibility(bool)`, `Library:Toggle()`, `Library:Unload()`,
`Library:OnUnload(fn)`, `Library:GiveSignal(signal)`, `Library.KeybindFrame`,
`Library.ToggleKeybind`, `Library:UpdateColorsUsingRegistry()`.

---

## Nouvelles fonctions optionnelles

Toutes sont **additives** : aucun script existant n'a besoin de les utiliser.

### Composants

```lua
-- Titre de section à l'intérieur d'un groupbox
local Section = Groupbox:AddSection('Général')
Section:SetText('Nouveau titre')
-- Section.TextLabel / Section.Container sont également exposés
```

### Notifications enrichies

```lua
Library:Notify('Texte simple', 4)                     -- forme historique
Library:Notify({                                        -- forme étendue
    Title = 'Succès',
    Description = 'Configuration appliquée.',
    Time = 5,
})
```

### Helpers de motion et de forme

| Fonction | Description |
| --- | --- |
| `Library:TweenInfo(durée, easing?, direction?)` | Construit un `TweenInfo` avec les valeurs par défaut de la bibliothèque |
| `Library:Tween(objet, props, durée?, easing?, direction?)` | Tween sécurisé (`pcall`) ; renvoie `nil` si `Library.Animations.Enabled == false` |
| `Library:AddCorner(objet, rayon?)` | Ajoute un `UICorner` |
| `Library:AddStroke(objet, clefCouleur?, épaisseur?, transparence?)` | Ajoute un `UIStroke` enregistré dans le registre de thème |
| `Library:AddPadding(objet, padding)` | Ajoute un `UIPadding` uniforme |
| `Library:AddScale(objet, échelle?)` | Ajoute un `UIScale` (utilisé pour les animations de pression) |
| `Library:AddClickFeedback(zoneSurvol, cible, échellePressée?)` | Ajoute un retour de clic ; renvoie le `UIScale` |
| `Library:AddHoverWash(zoneSurvol, cible, transpIdle?, transpSurvol?)` | Voile de survol animé |
| `Library:BindDrag(cible, onUpdate, onRelease?)` | Glissement piloté par événements ; renvoie une fonction d'arrêt |
| `Library:GetLighterColor(couleur, facteur?)` | Éclaircit une couleur |
| `Library:Blend(a, b, alpha?)` | Interpole deux `Color3` |
| `Library:GetSurfaceColor()` | Renvoie la couleur de surface dérivée de `MainColor` |

> `Library:AddScale` doit être préféré à une modification de `Size` pour les
> animations de pression : `Groupbox:Resize()` additionne les `Size.Y.Offset`
> des éléments, donc modifier `Size` casserait la mise en page.

---

## Thèmes

`ThemeManager` conserve exactement les 5 champs d'origine
(`FontColor`, `MainColor`, `AccentColor`, `BackgroundColor`, `OutlineColor`)
et toutes ses méthodes (`SetLibrary`, `SetFolder`, `ApplyTheme`, `ApplyToTab`,
`ApplyToGroupbox`, `ThemeUpdate`, ...).

Thèmes intégrés : `Default` (nouvelle palette moderne), `Classic` (palette
Linoria d'origine), `Graphite`, `Aurora`, `Sunset`, `Violet`, ainsi que les
thèmes historiques `BBot`, `Fatality`, `Jester`, `Mint`, `Tokyo Night`,
`Ubuntu`, `Quartz`.

```lua
ThemeManager:SetLibrary(Library)
ThemeManager:SetFolder('MonHub')
ThemeManager:ApplyToTab(Tabs['Réglages'])
```

---

## Configurations

`SaveManager` est inchangé :

```lua
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ 'MenuKeybind' })
SaveManager:SetFolder('MonHub/mon-jeu')
SaveManager:BuildConfigSection(Tabs['Réglages'])
SaveManager:LoadAutoloadConfig()
```

---

## Exemple complet

[`Example.lua`](Example.lua) démontre **toutes** les fonctionnalités publiques :
fenêtre, onglets, tabboxes, groupboxes, sections, boutons et sous-boutons,
toggles (dont `Risky`), sliders (dont `Compact`), inputs, dropdowns,
multi-dropdowns, dropdowns `Player`/`Team`, color pickers, key pickers,
dependency boxes imbriquées, notifications (deux formes), watermark dynamique,
liste de raccourcis, ThemeManager, SaveManager et les nouveaux réglages d'animation.

---

## Compatibilité avec l'ancienne API

- **Aucune** fonction publique n'a été supprimée ou renommée.
- Aucune signature n'a changé ; `Library:Notify` accepte en plus une table.
- Les tables globales `Library`, `Toggles` et `Options` sont identiques.
- Le registre de thème (`AddToRegistry` / `UpdateColorsUsingRegistry`) et les
  5 clés de couleur sont préservés.
- Les callbacks (`Callback`, `OnChanged`, `OnClick`, `ChangedCallback`),
  les dépendances et le système de configuration fonctionnent à l'identique.
- Les modifications sont internes : structure des frames, arrondis, contours,
  animations. Un script écrit pour LinoriaLib fonctionne sans aucune retouche.

Nouveaux comportements par défaut (désactivables) :
animations activées, contour de texte désactivé (`Library.TextStrokes = true`
pour retrouver le rendu d'origine), palette moderne (thème `Classic` pour
retrouver l'ancienne).

---

## Structure recommandée

```
MonProjet/
├── Library.lua              -- la bibliothèque
├── Example.lua              -- exemple / documentation vivante
├── README.md
├── LICENSE
└── addons/
    ├── ThemeManager.lua
    └── SaveManager.lua
```

Pour un hébergement GitHub, conservez cette arborescence à la racine du dépôt :
l'URL `raw.githubusercontent.com/<utilisateur>/<depot>/main/addons/ThemeManager.lua`
reste alors valide, exactement comme pour le dépôt d'origine.

---

## Crédits

- **Inori** : développeur principal de LinoriaLib.
- **Wally** : nettoyage du code, extension des fonctionnalités.
- **Stefanuk** : extension des fonctionnalités.
- **matas3535** : créateur de Splix.
- Version modernisée : refonte visuelle et système d'animations, API préservée.
