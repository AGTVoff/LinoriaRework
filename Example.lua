--[[
    ============================================================================
    LinoriaLib Modernized - Exemple complet
    ============================================================================

    Ce script demontre TOUTES les fonctionnalites publiques de la bibliotheque :
    fenetre, onglets, tabboxes, groupboxes, sections, boutons, toggles, sliders,
    dropdowns, multi-dropdowns, inputs, keybinds, color pickers, dependency
    boxes, notifications, tooltips, watermark, ThemeManager, SaveManager,
    systeme de configuration, callbacks, ainsi que les nouvelles options
    d'animation ajoutees par la version modernisee.

    NOTE IMPORTANTE SUR LES CALLBACKS :
    passer `Callback = function(Value) ... end` dans les options fonctionne,
    mais la methode RECOMMANDEE reste `Toggles/Options.INDEX:OnChanged(...)`.
    Il est preferable de creer d'abord l'interface, puis de brancher la logique.
    ============================================================================
]]

local repo = 'https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/'

local Library = loadstring(game:HttpGet(repo .. 'Library.lua'))()
local ThemeManager = loadstring(game:HttpGet(repo .. 'addons/ThemeManager.lua'))()
local SaveManager = loadstring(game:HttpGet(repo .. 'addons/SaveManager.lua'))()

--[[ ==========================================================================
     1. REGLAGES GLOBAUX (optionnels, nouveaux dans la version modernisee)
     ========================================================================== ]]

-- Systeme d'animation : tout est regroupe dans Library.Animations.
-- Mettre Enabled a false desactive completement les tweens de la bibliotheque
-- (utile sur des machines tres peu puissantes).
Library.Animations.Enabled = true
Library.Animations.Fast = 0.12         -- hover, feedback de clic
Library.Animations.Normal = 0.18       -- transitions standard
Library.Animations.Slow = 0.28         -- transitions longues
Library.Animations.Window = 0.24       -- ouverture / fermeture de la fenetre
Library.Animations.TabFade = true      -- fondu lors du changement d'onglet
Library.Animations.TabSlide = 14       -- glissement horizontal (en pixels)
Library.Animations.TabScale = 0.99     -- leger zoom a l'apparition de l'onglet
Library.Animations.TabDuration = 0.2   -- duree de la transition d'onglet

-- Autres options globales facultatives :
Library.ShowCustomCursor = true        -- curseur triangulaire custom (executors)
Library.TextStrokes = false            -- contour du texte (style Linoria d'origine)
Library.NotificationSide = 'Left'      -- 'Left' ou 'Right'

--[[ ==========================================================================
     2. CREATION DE LA FENETRE
     ========================================================================== ]]

local Window = Library:CreateWindow({
    Title = 'LinoriaLib Modernized',
    Center = true,          -- centre la fenetre a l'ecran
    AutoShow = true,        -- affiche la fenetre des sa creation
    TabPadding = 8,         -- espacement entre les boutons d'onglet
    MenuFadeTime = 0.2,     -- duree du fondu d'ouverture / fermeture

    -- Position et Size sont egalement valides ici :
    -- Position = UDim2.fromOffset(175, 50),
    -- Size = UDim2.fromOffset(560, 620),
})

-- On peut changer le titre a chaud :
Window:SetWindowTitle('LinoriaLib Modernized')

--[[ ==========================================================================
     3. ONGLETS
     ========================================================================== ]]

local Tabs = {
    Main = Window:AddTab('Main'),
    Components = Window:AddTab('Composants'),
    ['UI Settings'] = Window:AddTab('Reglages'),
}

-- Ordre d'affichage des onglets (facultatif)
Tabs.Main:SetLayoutOrder(1)
Tabs.Components:SetLayoutOrder(2)
Tabs['UI Settings']:SetLayoutOrder(3)

--[[ ==========================================================================
     4. GROUPBOXES ET SECTIONS
     ========================================================================== ]]

local LeftGroupBox = Tabs.Main:AddLeftGroupbox('Groupbox')

-- Les sections permettent de structurer visuellement un groupbox.
-- (nouvelle API optionnelle : Groupbox:AddSection(Nom))
LeftGroupBox:AddSection('Elements de base')

--[[
    Groupbox:AddToggle
    Arguments : Idx, Options
    Options : Text, Default, Tooltip, Risky, Callback
]]
LeftGroupBox:AddToggle('MyToggle', {
    Text = 'Ceci est un toggle',
    Default = true,
    Tooltip = 'Infobulle affichee au survol',

    Callback = function(Value)
        print('[cb] MyToggle change :', Value)
    end,
})

-- `Toggles` est une table globale ajoutee par la bibliotheque.
Toggles.MyToggle:OnChanged(function()
    print('MyToggle change :', Toggles.MyToggle.Value)
end)

Toggles.MyToggle:SetValue(false)

-- Un toggle "Risky" affiche son texte en rouge (fonctionnalite d'origine).
LeftGroupBox:AddToggle('RiskyToggle', {
    Text = 'Option risquee',
    Default = false,
    Risky = true,
})

--[[
    Groupbox:AddButton
    Arguments : { Text, Func, DoubleClick, Tooltip }
    On peut appeler :AddButton sur un bouton pour creer un sous-bouton.
]]
local MyButton = LeftGroupBox:AddButton({
    Text = 'Bouton',
    Func = function()
        print('Bouton clique !')
    end,
    DoubleClick = false,
    Tooltip = 'Bouton principal',
})

MyButton:AddButton({
    Text = 'Sous-bouton',
    Func = function()
        print('Sous-bouton clique !')
    end,
    DoubleClick = true, -- il faut cliquer deux fois
    Tooltip = 'Sous-bouton (double-clic)',
})

-- Groupbox:AddLabel - Arguments : Text, DoesWrap
LeftGroupBox:AddLabel('Ceci est un label')
LeftGroupBox:AddLabel('Ceci est un label\n\nqui passe a la ligne !', true)

-- Groupbox:AddDivider - aucun argument
LeftGroupBox:AddDivider()

LeftGroupBox:AddSection('Valeurs')

--[[
    Groupbox:AddSlider
    Arguments : Idx, { Text, Default, Min, Max, Rounding, Suffix, Compact, HideMax }
    Text, Default, Min, Max et Rounding sont obligatoires.
    Compact masque le titre du slider, HideMax masque la valeur maximale.
]]
LeftGroupBox:AddSlider('MySlider', {
    Text = 'Mon slider',
    Default = 0,
    Min = 0,
    Max = 5,
    Rounding = 1,
    Suffix = ' s',
    Compact = false,
    HideMax = false,

    Callback = function(Value)
        print('[cb] MySlider change :', Value)
    end,
})

-- `Options` est la table globale des elements non-toggle.
Options.MySlider:OnChanged(function()
    print('MySlider change :', Options.MySlider.Value)
end)

Options.MySlider:SetValue(3)

-- Slider compact (sans label au-dessus)
LeftGroupBox:AddSlider('CompactSlider', {
    Text = 'Slider compact',
    Default = 50,
    Min = 0,
    Max = 100,
    Rounding = 0,
    Compact = true,
})

--[[
    Groupbox:AddInput
    Arguments : Idx, { Text, Default, Numeric, Finished, Placeholder, MaxLength, Tooltip }
]]
LeftGroupBox:AddInput('MyTextbox', {
    Default = 'Mon texte',
    Numeric = false,   -- true = chiffres uniquement
    Finished = false,  -- true = callback uniquement a la validation (Entree)

    Text = 'Ceci est un champ texte',
    Tooltip = 'Infobulle du champ texte',
    Placeholder = 'Texte indicatif',
    -- MaxLength = 32,

    Callback = function(Value)
        print('[cb] Texte mis a jour :', Value)
    end,
})

Options.MyTextbox:OnChanged(function()
    print('Texte mis a jour :', Options.MyTextbox.Value)
end)

--[[ ==========================================================================
     5. DROPDOWNS
     ========================================================================== ]]

local DropdownBox = Tabs.Main:AddLeftGroupbox('Dropdowns')

DropdownBox:AddDropdown('MyDropdown', {
    Values = { 'Ceci', 'est', 'un', 'dropdown' },
    Default = 1,     -- index numerique OU chaine de caracteres
    Multi = false,   -- selection unique

    Text = 'Un dropdown',
    Tooltip = 'Infobulle du dropdown',

    Callback = function(Value)
        print('[cb] Dropdown change :', Value)
    end,
})

Options.MyDropdown:OnChanged(function()
    print('Dropdown change :', Options.MyDropdown.Value)
end)

Options.MyDropdown:SetValue('Ceci')

-- Multi-dropdown : la valeur est une table { [choix] = true }
DropdownBox:AddDropdown('MyMultiDropdown', {
    Values = { 'Ceci', 'est', 'un', 'dropdown' },
    Default = 1,
    Multi = true,

    Text = 'Un multi-dropdown',
    Tooltip = 'Selection multiple',

    Callback = function(Value)
        print('[cb] Multi-dropdown change :', Value)
    end,
})

Options.MyMultiDropdown:OnChanged(function()
    print('Multi-dropdown change :')
    for Key, Value in next, Options.MyMultiDropdown.Value do
        print(Key, Value)
    end
end)

Options.MyMultiDropdown:SetValue({
    Ceci = true,
    est = true,
})

-- Dropdowns speciaux : la liste se met a jour automatiquement.
DropdownBox:AddDropdown('MyPlayerDropdown', {
    SpecialType = 'Player',
    Text = 'Dropdown joueurs',
    Tooltip = 'Liste des joueurs presents',

    Callback = function(Value)
        print('[cb] Dropdown joueur :', Value)
    end,
})

DropdownBox:AddDropdown('MyTeamDropdown', {
    SpecialType = 'Team',
    Text = 'Dropdown equipes',
})

-- On peut remplacer la liste des valeurs a tout moment :
-- Options.MyDropdown:SetValues({ 'nouvelle', 'liste' })

--[[ ==========================================================================
     6. COLOR PICKERS ET KEY PICKERS
     ========================================================================== ]]

local PickerBox = Tabs.Main:AddRightGroupbox('Pickers')

-- AddColorPicker / AddKeyPicker s'appellent sur un Label OU sur un Toggle.
PickerBox:AddLabel('Couleur'):AddColorPicker('ColorPicker', {
    Default = Color3.new(0, 1, 0),
    Title = 'Une couleur',  -- titre de la fenetre du picker
    Transparency = 0,       -- laisser nil pour desactiver la transparence

    Callback = function(Value)
        print('[cb] Couleur changee !', Value)
    end,
})

Options.ColorPicker:OnChanged(function()
    print('Couleur changee !', Options.ColorPicker.Value)
    print('Transparence changee !', Options.ColorPicker.Transparency)
end)

Options.ColorPicker:SetValueRGB(Color3.fromRGB(0, 255, 140))

PickerBox:AddLabel('Raccourci'):AddKeyPicker('KeyPicker', {
    Default = 'MB2',        -- MB1 / MB2 pour les boutons de souris
    SyncToggleState = false,-- synchronise l'etat avec le toggle parent
    Mode = 'Toggle',        -- Always, Toggle, Hold
    Text = 'Action exemple',
    NoUI = false,           -- true = masque dans la liste des raccourcis

    Callback = function(Value)
        print('[cb] Raccourci active !', Value)
    end,

    ChangedCallback = function(New)
        print('[cb] Raccourci modifie !', New)
    end,
})

Options.KeyPicker:OnClick(function()
    print('Raccourci clique !', Options.KeyPicker:GetState())
end)

Options.KeyPicker:OnChanged(function()
    print('Raccourci modifie !', Options.KeyPicker.Value)
end)

Options.KeyPicker:SetValue({ 'MB2', 'Toggle' })

-- Toggle avec un color picker ET un key picker attaches :
PickerBox:AddToggle('ComboToggle', { Text = 'Toggle avec addons' })
    :AddColorPicker('ComboColor', { Default = Color3.fromRGB(96, 128, 255) })
Toggles.ComboToggle:AddKeyPicker('ComboKey', { Default = 'F', Text = 'Toggle avec addons' })

-- Lecture de l'etat d'un keybind dans une boucle (exemple d'origine) :
task.spawn(function()
    while true do
        task.wait(1)

        if Options.KeyPicker:GetState() then
            print('KeyPicker maintenu')
        end

        if Library.Unloaded then break end
    end
end)

--[[ ==========================================================================
     7. TABBOXES
     ========================================================================== ]]

-- Un Tabbox accepte exactement les memes methodes qu'un Groupbox,
-- mais elles s'appellent sur un onglet retourne par Tabbox:AddTab(nom).
local TabBox = Tabs.Main:AddRightTabbox('Tabbox')

local Tab1 = TabBox:AddTab('Onglet 1')
Tab1:AddToggle('Tab1Toggle', { Text = 'Toggle onglet 1' })
Tab1:AddSlider('Tab1Slider', { Text = 'Slider onglet 1', Default = 25, Min = 0, Max = 100, Rounding = 0 })

local Tab2 = TabBox:AddTab('Onglet 2')
Tab2:AddToggle('Tab2Toggle', { Text = 'Toggle onglet 2' })
Tab2:AddDropdown('Tab2Dropdown', { Text = 'Dropdown', Default = 1, Values = { 'a', 'b', 'c' } })

--[[ ==========================================================================
     8. DEPENDENCY BOXES
     ========================================================================== ]]

local DependencyBox = Tabs.Components:AddLeftGroupbox('Dependances')

DependencyBox:AddToggle('ControlToggle', { Text = 'Activer la fonctionnalite' })

local Depbox = DependencyBox:AddDependencyBox()
Depbox:AddToggle('DepboxToggle', { Text = 'Sous-option' })

-- Les dependency boxes peuvent etre imbriquees.
local SubDepbox = Depbox:AddDependencyBox()
SubDepbox:AddSlider('DepboxSlider', { Text = 'Slider', Default = 50, Min = 0, Max = 100, Rounding = 0 })
SubDepbox:AddDropdown('DepboxDropdown', { Text = 'Dropdown', Default = 1, Values = { 'a', 'b', 'c' } })

Depbox:SetupDependencies({
    { Toggles.ControlToggle, true }, -- passer `false` pour l'inverse
})

SubDepbox:SetupDependencies({
    { Toggles.DepboxToggle, true },
})

--[[ ==========================================================================
     9. NOTIFICATIONS, WATERMARK ET LISTE DE RACCOURCIS
     ========================================================================== ]]

local UtilityBox = Tabs.Components:AddRightGroupbox('Utilitaires')

UtilityBox:AddSection('Notifications')

-- Forme historique : Library:Notify(Texte, Duree)
UtilityBox:AddButton({
    Text = 'Notification simple',
    Func = function()
        Library:Notify('Ceci est une notification', 4)
    end,
})

-- Forme etendue (optionnelle) : Library:Notify({ Title, Description, Time })
UtilityBox:AddButton({
    Text = 'Notification avec titre',
    Func = function()
        Library:Notify({
            Title = 'Succes',
            Description = 'La configuration a ete appliquee.',
            Time = 5,
        })
    end,
})

UtilityBox:AddSection('Watermark')

UtilityBox:AddToggle('WatermarkToggle', {
    Text = 'Afficher le watermark',
    Default = true,
    Callback = function(Value)
        Library:SetWatermarkVisibility(Value)
    end,
})

UtilityBox:AddToggle('KeybindListToggle', {
    Text = 'Afficher la liste des raccourcis',
    Default = true,
    Callback = function(Value)
        Library.KeybindFrame.Visible = Value
    end,
})

Library:SetWatermarkVisibility(true)
Library.KeybindFrame.Visible = true

-- Watermark dynamique (FPS + ping), exemple issu de la version d'origine.
local FrameTimer = tick()
local FrameCounter = 0
local FPS = 60

local WatermarkConnection = game:GetService('RunService').RenderStepped:Connect(function()
    FrameCounter += 1

    if (tick() - FrameTimer) >= 1 then
        FPS = FrameCounter
        FrameTimer = tick()
        FrameCounter = 0
    end

    Library:SetWatermark(('LinoriaLib Modernized | %s fps | %s ms'):format(
        math.floor(FPS),
        math.floor(game:GetService('Stats').Network.ServerStatsItem['Data Ping']:GetValue())
    ))
end)

--[[ ==========================================================================
     10. ONGLET REGLAGES : THEMES, CONFIGURATIONS, DECHARGEMENT
     ========================================================================== ]]

local MenuGroup = Tabs['UI Settings']:AddLeftGroupbox('Menu')

MenuGroup:AddSection('General')

MenuGroup:AddToggle('AnimationsToggle', {
    Text = 'Animations activees',
    Default = true,
    Tooltip = 'Desactive tous les tweens de la bibliotheque',
    Callback = function(Value)
        Library.Animations.Enabled = Value
    end,
})

MenuGroup:AddToggle('CustomCursorToggle', {
    Text = 'Curseur personnalise',
    Default = true,
    Callback = function(Value)
        Library.ShowCustomCursor = Value
    end,
})

MenuGroup:AddSlider('TabAnimationSpeed', {
    Text = 'Vitesse des transitions',
    Default = 0.2,
    Min = 0.05,
    Max = 0.5,
    Rounding = 2,
    Suffix = ' s',
    Callback = function(Value)
        Library.Animations.TabDuration = Value
    end,
})

MenuGroup:AddDivider()

MenuGroup:AddButton({
    Text = 'Decharger le menu',
    Func = function()
        Library:Unload()
    end,
})

MenuGroup:AddLabel('Touche du menu'):AddKeyPicker('MenuKeybind', {
    Default = 'End',
    NoUI = true, -- masque dans la liste des raccourcis
    Text = 'Touche du menu',
})

-- Permet d'utiliser un raccourci personnalise pour ouvrir / fermer le menu.
Library.ToggleKeybind = Options.MenuKeybind

Library:OnUnload(function()
    WatermarkConnection:Disconnect()

    print('Decharge !')
    Library.Unloaded = true
end)

--[[ ==========================================================================
     11. ADDONS : ThemeManager ET SaveManager
     ========================================================================== ]]

-- On transmet la bibliotheque aux gestionnaires.
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)

-- On ignore les cles utilisees par le ThemeManager
-- (on ne veut pas que les configs enregistrent le theme).
SaveManager:IgnoreThemeSettings()

-- On ignore aussi la touche du menu.
SaveManager:SetIgnoreIndexes({ 'MenuKeybind' })

-- Dossiers de sauvegarde (themes globaux, configs par jeu par exemple).
ThemeManager:SetFolder('MyScriptHub')
SaveManager:SetFolder('MyScriptHub/specific-game')

-- Construit la section de configuration (a droite de l'onglet).
SaveManager:BuildConfigSection(Tabs['UI Settings'])

-- Construit la section des themes (a gauche de l'onglet).
-- NOTE : ThemeManager:ApplyToGroupbox(groupbox) permet de la placer
-- dans un groupbox precis a la place.
ThemeManager:ApplyToTab(Tabs['UI Settings'])

-- Charge la configuration marquee comme "autoload", si elle existe.
SaveManager:LoadAutoloadConfig()

Library:Notify('Interface chargee avec succes', 4)
