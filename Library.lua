local InputService = game:GetService('UserInputService');
local TextService = game:GetService('TextService');
local CoreGui = game:GetService('CoreGui');
local Teams = game:GetService('Teams');
local Players = game:GetService('Players');
local RunService = game:GetService('RunService')
local TweenService = game:GetService('TweenService');
local RenderStepped = RunService.RenderStepped;
local LocalPlayer = Players.LocalPlayer;
local Mouse = LocalPlayer:GetMouse();

local ProtectGui = protectgui or (syn and syn.protect_gui) or (function() end);

local ScreenGui = Instance.new('ScreenGui');
ProtectGui(ScreenGui);

ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global;
ScreenGui.Parent = CoreGui;

local Toggles = {};
local Options = {};

getgenv().Toggles = Toggles;
getgenv().Options = Options;

local Library = {
    Registry = {};
    RegistryMap = {};

    HudRegistry = {};

    -- < Palette (kept API-identical: same field names as the original Linoria) >
    FontColor = Color3.fromRGB(235, 237, 245);
    MainColor = Color3.fromRGB(26, 27, 33);
    BackgroundColor = Color3.fromRGB(17, 18, 23);
    AccentColor = Color3.fromRGB(96, 128, 255);
    OutlineColor = Color3.fromRGB(45, 47, 58);
    RiskColor = Color3.fromRGB(255, 84, 84),

    Black = Color3.new(0, 0, 0);
    Font = Enum.Font.GothamMedium,

    OpenedFrames = {};
    DependencyBoxes = {};

    Signals = {};
    ScreenGui = ScreenGui;
};

--[[
    ============================================================
    MODERN DESIGN SYSTEM  (new, optional, backwards compatible)
    ============================================================
    Every value below can be overridden *before* Library:CreateWindow()
    is called. Nothing here is required by the legacy API - if you leave
    it untouched you simply get the modern defaults.
]]

-- Typography
Library.FontHeavy = Enum.Font.GothamBold;       -- window / groupbox titles
Library.FontRegular = Enum.Font.Gotham;         -- secondary text
Library.TextSize = 14;                          -- base text size
Library.TitleTextSize = 15;
Library.TextStrokes = false;                    -- legacy 1px black text stroke

-- Shape
Library.CornerRadius = UDim.new(0, 6);          -- cards / panels
Library.SmallCornerRadius = UDim.new(0, 4);     -- inputs / buttons
Library.PillCornerRadius = UDim.new(1, 0);      -- toggles / indicators
Library.StrokeThickness = 1;

-- Spacing scale
Library.Spacing = {
    XS = 2;
    SM = 4;
    MD = 8;
    LG = 12;
    XL = 16;
};

-- Elevation / transparency
Library.SurfaceTransparency = 0;
Library.HoverTransparency = 0.88;               -- hover wash over a surface
Library.PressedTransparency = 0.76;
Library.DisabledTransparency = 0.55;

-- Motion
Library.Animations = {
    Enabled = true;

    Fast = 0.12;        -- hover / press micro-interactions
    Normal = 0.18;      -- most state changes
    Slow = 0.28;        -- panels, dropdowns, notifications
    Window = 0.24;      -- window open / close

    Easing = Enum.EasingStyle.Quart;
    Direction = Enum.EasingDirection.Out;

    -- Tab transition
    TabFade = true;         -- fade the outgoing/incoming tab (uses CanvasGroup)
    TabSlide = 14;          -- px of horizontal slide, 0 disables
    TabScale = 0.99;        -- starting scale, 1 disables
    TabDuration = 0.2;
};

-- Feature switches
Library.ShowCustomCursor = true;    -- legacy Drawing based cursor
Library.NotificationSide = 'Left';  -- 'Left' | 'Right'

local RainbowStep = 0
local Hue = 0

-- Initialised immediately so consumers never read a nil colour.
Library.CurrentRainbowHue = 0;
Library.CurrentRainbowColor = Color3.fromHSV(0, 0.8, 1);

-- PERF: moved off RenderStepped (which blocks the render pipeline) onto
-- Heartbeat, and throttled to ~30 Hz instead of 60 Hz. This is the only
-- per-frame connection the library keeps alive.
table.insert(Library.Signals, RunService.Heartbeat:Connect(function(Delta)
    RainbowStep = RainbowStep + Delta

    if RainbowStep >= (1 / 30) then
        RainbowStep = 0

        Hue = Hue + (1 / 200);

        if Hue > 1 then
            Hue = 0;
        end;

        Library.CurrentRainbowHue = Hue;
        Library.CurrentRainbowColor = Color3.fromHSV(Hue, 0.8, 1);
    end
end))

local function GetPlayersString()
    local PlayerList = Players:GetPlayers();

    for i = 1, #PlayerList do
        PlayerList[i] = PlayerList[i].Name;
    end;

    table.sort(PlayerList, function(str1, str2) return str1 < str2 end);

    return PlayerList;
end;

local function GetTeamsString()
    local TeamList = Teams:GetTeams();

    for i = 1, #TeamList do
        TeamList[i] = TeamList[i].Name;
    end;

    table.sort(TeamList, function(str1, str2) return str1 < str2 end);
    
    return TeamList;
end;

function Library:SafeCallback(f, ...)
    if (not f) then
        return;
    end;

    if not Library.NotifyOnError then
        return f(...);
    end;

    local success, event = pcall(f, ...);

    if not success then
        local _, i = event:find(":%d+: ");

        if not i then
            return Library:Notify(event);
        end;

        return Library:Notify(event:sub(i + 1), 3);
    end;
end;

function Library:AttemptSave()
    if Library.SaveManager then
        Library.SaveManager:Save();
    end;
end;

function Library:Create(Class, Properties)
    local _Instance = Class;

    if type(Class) == 'string' then
        _Instance = Instance.new(Class);
    end;

    for Property, Value in next, Properties do
        _Instance[Property] = Value;
    end;

    return _Instance;
end;

--[[
    ============================================================
    MOTION + SHAPE HELPERS  (new public API, all optional)
    ============================================================
]]

-- Builds a TweenInfo from the Library.Animations config.
function Library:TweenInfo(Duration, Easing, Direction)
    return TweenInfo.new(
        Duration or Library.Animations.Normal,
        Easing or Library.Animations.Easing,
        Direction or Library.Animations.Direction
    );
end;

--[[
    Library:Tween(Instance, Properties, Duration?, Easing?, Direction?)

    The single animation entry point used by every component. Honours
    Library.Animations.Enabled - when animations are disabled the target
    properties are applied instantly, so behaviour is always identical.
    Returns the Tween (or nil when applied instantly).
]]
function Library:Tween(Object, Properties, Duration, Easing, Direction)
    if typeof(Object) ~= 'Instance' then
        return;
    end;

    if (not Library.Animations.Enabled) or Duration == 0 then
        for Property, Value in next, Properties do
            pcall(function() Object[Property] = Value; end);
        end;

        return;
    end;

    local Success, Tween = pcall(function()
        return TweenService:Create(Object, Library:TweenInfo(Duration, Easing, Direction), Properties);
    end);

    if (not Success) or (not Tween) then
        for Property, Value in next, Properties do
            pcall(function() Object[Property] = Value; end);
        end;

        return;
    end;

    Tween:Play();

    return Tween;
end;

-- Rounded corners. Radius may be a UDim or a number of pixels.
function Library:AddCorner(Object, Radius)
    if typeof(Radius) == 'number' then
        Radius = UDim.new(0, Radius);
    end;

    return Library:Create('UICorner', {
        CornerRadius = Radius or Library.CornerRadius;
        Parent = Object;
    });
end;

-- 1px border replacement. Registered so themes recolour it automatically.
function Library:AddStroke(Object, ColorIdx, Thickness, Transparency)
    ColorIdx = ColorIdx or 'OutlineColor';

    local Stroke = Library:Create('UIStroke', {
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border;
        Color = (typeof(ColorIdx) == 'Color3' and ColorIdx) or Library[ColorIdx] or Library.OutlineColor;
        Thickness = Thickness or Library.StrokeThickness;
        Transparency = Transparency or 0;
        Parent = Object;
    });

    if typeof(ColorIdx) == 'string' then
        Library:AddToRegistry(Stroke, { Color = ColorIdx });
    end;

    return Stroke;
end;

function Library:AddPadding(Object, Padding)
    if typeof(Padding) == 'number' then
        Padding = { Left = Padding, Right = Padding, Top = Padding, Bottom = Padding };
    end;

    Padding = Padding or {};

    return Library:Create('UIPadding', {
        PaddingLeft = UDim.new(0, Padding.Left or 0);
        PaddingRight = UDim.new(0, Padding.Right or 0);
        PaddingTop = UDim.new(0, Padding.Top or 0);
        PaddingBottom = UDim.new(0, Padding.Bottom or 0);
        Parent = Object;
    });
end;

-- A UIScale is used for press feedback because it does not change
-- Size.Y.Offset, so groupbox auto-sizing stays exact.
function Library:AddScale(Object, Scale)
    return Library:Create('UIScale', {
        Scale = Scale or 1;
        Parent = Object;
    });
end;

--[[
    Library:AddClickFeedback(HoverInstance, Scale?, PressedScale?)

    Adds a subtle press-down / release animation. Safe to call on any
    GuiObject; creates at most one UIScale.
]]
function Library:AddClickFeedback(HoverInstance, Target, PressedScale)
    Target = Target or HoverInstance;

    local Scale = Target:FindFirstChildOfClass('UIScale') or Library:AddScale(Target, 1);
    PressedScale = PressedScale or 0.97;

    HoverInstance.InputBegan:Connect(function(Input)
        if Input.UserInputType == Enum.UserInputType.MouseButton1 then
            Library:Tween(Scale, { Scale = PressedScale }, Library.Animations.Fast);
        end;
    end);

    HoverInstance.InputEnded:Connect(function(Input)
        if Input.UserInputType == Enum.UserInputType.MouseButton1 then
            Library:Tween(Scale, { Scale = 1 }, Library.Animations.Normal, Enum.EasingStyle.Back);
        end;
    end);

    HoverInstance.MouseLeave:Connect(function()
        Library:Tween(Scale, { Scale = 1 }, Library.Animations.Fast);
    end);

    return Scale;
end;

--[[
    Library:BindDrag(Target, OnUpdate, OnRelease?)

    PERF: replaces the `while IsMouseButtonPressed do ... RenderStepped:Wait() end`
    pattern used by sliders / colour pickers in the original library. The
    InputChanged connection is created on mouse-down and destroyed on
    mouse-up, so nothing runs per-frame while the UI is idle.
]]
function Library:BindDrag(Target, OnUpdate, OnRelease)
    local Dragging = false;
    local MoveConnection, EndConnection;

    local function Stop()
        if (not Dragging) then return end;
        Dragging = false;

        if MoveConnection then MoveConnection:Disconnect(); MoveConnection = nil; end;
        if EndConnection then EndConnection:Disconnect(); EndConnection = nil; end;

        if OnRelease then
            OnRelease();
        end;
    end;

    Target.InputBegan:Connect(function(Input)
        if Input.UserInputType ~= Enum.UserInputType.MouseButton1
            and Input.UserInputType ~= Enum.UserInputType.Touch then
            return;
        end;

        Stop();
        Dragging = true;

        OnUpdate();

        MoveConnection = InputService.InputChanged:Connect(function(Moved)
            if (not Dragging) then return end;

            if Moved.UserInputType == Enum.UserInputType.MouseMovement
                or Moved.UserInputType == Enum.UserInputType.Touch then
                OnUpdate();
            end;
        end);

        EndConnection = InputService.InputEnded:Connect(function(Ended)
            if Ended.UserInputType == Enum.UserInputType.MouseButton1
                or Ended.UserInputType == Enum.UserInputType.Touch then
                Stop();
            end;
        end);
    end);

    Target.Destroying:Connect(Stop);

    return Stop;
end;

-- Hover wash: animates BackgroundTransparency on a surface.
function Library:AddHoverWash(HoverInstance, Target, IdleTransparency, HoverTransparency)
    IdleTransparency = IdleTransparency == nil and 1 or IdleTransparency;
    HoverTransparency = HoverTransparency == nil and Library.HoverTransparency or HoverTransparency;

    HoverInstance.MouseEnter:Connect(function()
        if Library:MouseIsOverOpenedFrame() then return end;
        Library:Tween(Target, { BackgroundTransparency = HoverTransparency }, Library.Animations.Fast);
    end);

    HoverInstance.MouseLeave:Connect(function()
        Library:Tween(Target, { BackgroundTransparency = IdleTransparency }, Library.Animations.Normal);
    end);
end;

-- Legacy text stroke. Now opt-in via Library.TextStrokes (default false)
-- because flat text reads much better on the modern surfaces.
function Library:ApplyTextStroke(Inst)
    Inst.TextStrokeTransparency = 1;

    if (not Library.TextStrokes) then
        return;
    end;

    Library:Create('UIStroke', {
        Color = Color3.new(0, 0, 0);
        Thickness = 1;
        LineJoinMode = Enum.LineJoinMode.Miter;
        Parent = Inst;
    });
end;

function Library:CreateLabel(Properties, IsHud)
    local _Instance = Library:Create('TextLabel', {
        BackgroundTransparency = 1;
        Font = Library.Font;
        TextColor3 = Library.FontColor;
        TextSize = Library.TextSize;
        RichText = true;
        TextStrokeTransparency = 1;
    });

    Library:ApplyTextStroke(_Instance);

    Library:AddToRegistry(_Instance, {
        TextColor3 = 'FontColor';
    }, IsHud);

    return Library:Create(_Instance, Properties);
end;

--[[
    PERF: the original implementation ran a `while IsMouseButtonPressed do
    RenderStepped:Wait() end` polling loop for the whole duration of a drag.
    This version is fully event driven - it only reacts to actual mouse
    movement and disconnects the moment the button is released.
]]
function Library:MakeDraggable(Instance, Cutoff)
    Instance.Active = true;

    local Dragging = false;
    local DragOffset = Vector2.zero;
    local MoveConnection, EndConnection;

    local function StopDragging()
        Dragging = false;

        if MoveConnection then
            MoveConnection:Disconnect();
            MoveConnection = nil;
        end;

        if EndConnection then
            EndConnection:Disconnect();
            EndConnection = nil;
        end;
    end;

    Instance.InputBegan:Connect(function(Input)
        if Input.UserInputType ~= Enum.UserInputType.MouseButton1 then
            return;
        end;

        local ObjPos = Vector2.new(
            Mouse.X - Instance.AbsolutePosition.X,
            Mouse.Y - Instance.AbsolutePosition.Y
        );

        if ObjPos.Y > (Cutoff or 40) then
            return;
        end;

        StopDragging();

        Dragging = true;
        DragOffset = ObjPos;

        MoveConnection = InputService.InputChanged:Connect(function(Moved)
            if (not Dragging) then return end;

            if Moved.UserInputType ~= Enum.UserInputType.MouseMovement
                and Moved.UserInputType ~= Enum.UserInputType.Touch then
                return;
            end;

            Instance.Position = UDim2.new(
                0,
                Mouse.X - DragOffset.X + (Instance.AbsoluteSize.X * Instance.AnchorPoint.X),
                0,
                Mouse.Y - DragOffset.Y + (Instance.AbsoluteSize.Y * Instance.AnchorPoint.Y)
            );
        end);

        EndConnection = InputService.InputEnded:Connect(function(Ended)
            if Ended.UserInputType == Enum.UserInputType.MouseButton1 then
                StopDragging();
            end;
        end);
    end);

    Instance.Destroying:Connect(StopDragging);
end;

--[[
    Modern tooltip: rounded card, drop-in fade + lift animation, and the
    Heartbeat polling loop replaced by a lazily connected InputChanged
    handler that is disconnected as soon as the cursor leaves.
]]
function Library:AddToolTip(InfoStr, HoverInstance)
    local X, Y = Library:GetTextBounds(InfoStr, Library.Font, Library.TextSize);

    local Tooltip = Library:Create('Frame', {
        BackgroundColor3 = Library.MainColor,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,

        Size = UDim2.fromOffset(X + 16, Y + 10),
        ZIndex = 300,
        Parent = Library.ScreenGui,

        Visible = false,
    })

    Library:AddCorner(Tooltip, Library.SmallCornerRadius);
    local Stroke = Library:AddStroke(Tooltip, 'OutlineColor');
    Stroke.Transparency = 1;

    local Label = Library:CreateLabel({
        Position = UDim2.fromOffset(8, 5),
        Size = UDim2.fromOffset(X, Y);
        TextSize = Library.TextSize;
        Text = InfoStr,
        TextColor3 = Library.FontColor,
        TextTransparency = 1,
        TextXAlignment = Enum.TextXAlignment.Left;
        ZIndex = Tooltip.ZIndex + 1,

        Parent = Tooltip;
    });

    Library:AddToRegistry(Tooltip, {
        BackgroundColor3 = 'MainColor';
    });

    Library:AddToRegistry(Label, {
        TextColor3 = 'FontColor',
    });

    local MoveConnection;
    local Shown = false;

    local function Follow()
        Tooltip.Position = UDim2.fromOffset(Mouse.X + 16, Mouse.Y + 14);
    end;

    local function Hide()
        if (not Shown) then return end;
        Shown = false;

        if MoveConnection then
            MoveConnection:Disconnect();
            MoveConnection = nil;
        end;

        Library:Tween(Tooltip, { BackgroundTransparency = 1 }, Library.Animations.Fast);
        Library:Tween(Stroke, { Transparency = 1 }, Library.Animations.Fast);
        Library:Tween(Label, { TextTransparency = 1 }, Library.Animations.Fast);

        task.delay(Library.Animations.Fast, function()
            if (not Shown) then
                Tooltip.Visible = false;
            end;
        end);
    end;

    HoverInstance.MouseEnter:Connect(function()
        if Library:MouseIsOverOpenedFrame() then
            return
        end

        Shown = true;

        Follow();
        Tooltip.Visible = true;
        Tooltip.BackgroundTransparency = 1;
        Label.TextTransparency = 1;

        Library:Tween(Tooltip, { BackgroundTransparency = 0.05 }, Library.Animations.Normal);
        Library:Tween(Stroke, { Transparency = 0.2 }, Library.Animations.Normal);
        Library:Tween(Label, { TextTransparency = 0 }, Library.Animations.Normal);

        if MoveConnection then MoveConnection:Disconnect() end;

        MoveConnection = InputService.InputChanged:Connect(function(Input)
            if Input.UserInputType == Enum.UserInputType.MouseMovement then
                Follow();
            end;
        end);
    end)

    HoverInstance.MouseLeave:Connect(Hide)
    HoverInstance.Destroying:Connect(Hide)
end

--[[
    Same signature and same registry semantics as the original, but Color3
    properties are now animated instead of snapping. Non-colour properties
    (ZIndex, Transparency, ...) are still applied instantly so existing
    call sites keep working unchanged.
]]
function Library:OnHighlight(HighlightInstance, Instance, Properties, PropertiesDefault)
    local function Apply(Set)
        local Reg = Library.RegistryMap[Instance];

        for Property, ColorIdx in next, Set do
            local Value = Library[ColorIdx];

            if Value == nil then
                Value = ColorIdx;
            end;

            if typeof(Value) == 'Color3' then
                Library:Tween(Instance, { [Property] = Value }, Library.Animations.Fast);
            else
                pcall(function() Instance[Property] = Value; end);
            end;

            if Reg and Reg.Properties[Property] then
                Reg.Properties[Property] = ColorIdx;
            end;
        end;
    end;

    HighlightInstance.MouseEnter:Connect(function()
        Apply(Properties);
    end)

    HighlightInstance.MouseLeave:Connect(function()
        Apply(PropertiesDefault);
    end)
end;

function Library:MouseIsOverOpenedFrame()
    for Frame, _ in next, Library.OpenedFrames do
        local AbsPos, AbsSize = Frame.AbsolutePosition, Frame.AbsoluteSize;

        if Mouse.X >= AbsPos.X and Mouse.X <= AbsPos.X + AbsSize.X
            and Mouse.Y >= AbsPos.Y and Mouse.Y <= AbsPos.Y + AbsSize.Y then

            return true;
        end;
    end;
end;

function Library:IsMouseOverFrame(Frame)
    local AbsPos, AbsSize = Frame.AbsolutePosition, Frame.AbsoluteSize;

    if Mouse.X >= AbsPos.X and Mouse.X <= AbsPos.X + AbsSize.X
        and Mouse.Y >= AbsPos.Y and Mouse.Y <= AbsPos.Y + AbsSize.Y then

        return true;
    end;
end;

function Library:UpdateDependencyBoxes()
    for _, Depbox in next, Library.DependencyBoxes do
        Depbox:Update();
    end;
end;

function Library:MapValue(Value, MinA, MaxA, MinB, MaxB)
    return (1 - ((Value - MinA) / (MaxA - MinA))) * MinB + ((Value - MinA) / (MaxA - MinA)) * MaxB;
end;

function Library:GetTextBounds(Text, Font, Size, Resolution)
    local Bounds = TextService:GetTextSize(Text, Size, Font, Resolution or Vector2.new(1920, 1080))
    return Bounds.X, Bounds.Y
end;

function Library:GetDarkerColor(Color)
    local H, S, V = Color3.toHSV(Color);
    return Color3.fromHSV(H, S, V / 1.5);
end;

-- New helpers used by the modern surfaces / elevation model.
function Library:GetLighterColor(Color, Factor)
    local H, S, V = Color3.toHSV(Color);
    return Color3.fromHSV(H, S, math.clamp(V * (Factor or 1.35), 0, 1));
end;

function Library:Blend(ColorA, ColorB, Alpha)
    Alpha = math.clamp(Alpha or 0.5, 0, 1);
    return ColorA:Lerp(ColorB, Alpha);
end;

-- Slightly raised surface, used for inputs sitting on top of a card.
function Library:GetSurfaceColor()
    return Library:Blend(Library.MainColor, Color3.new(1, 1, 1), 0.045);
end;

Library.AccentColorDark = Library:GetDarkerColor(Library.AccentColor);

function Library:AddToRegistry(Instance, Properties, IsHud)
    local Idx = #Library.Registry + 1;
    local Data = {
        Instance = Instance;
        Properties = Properties;
        Idx = Idx;
    };

    table.insert(Library.Registry, Data);
    Library.RegistryMap[Instance] = Data;

    if IsHud then
        table.insert(Library.HudRegistry, Data);
    end;
end;

function Library:RemoveFromRegistry(Instance)
    local Data = Library.RegistryMap[Instance];

    if Data then
        for Idx = #Library.Registry, 1, -1 do
            if Library.Registry[Idx] == Data then
                table.remove(Library.Registry, Idx);
            end;
        end;

        for Idx = #Library.HudRegistry, 1, -1 do
            if Library.HudRegistry[Idx] == Data then
                table.remove(Library.HudRegistry, Idx);
            end;
        end;

        Library.RegistryMap[Instance] = nil;
    end;
end;

function Library:UpdateColorsUsingRegistry()
    -- TODO: Could have an 'active' list of objects
    -- where the active list only contains Visible objects.

    -- IMPL: Could setup .Changed events on the AddToRegistry function
    -- that listens for the 'Visible' propert being changed.
    -- Visible: true => Add to active list, and call UpdateColors function
    -- Visible: false => Remove from active list.

    -- The above would be especially efficient for a rainbow menu color or live color-changing.

    for Idx, Object in next, Library.Registry do
        for Property, ColorIdx in next, Object.Properties do
            if type(ColorIdx) == 'string' then
                Object.Instance[Property] = Library[ColorIdx];
            elseif type(ColorIdx) == 'function' then
                Object.Instance[Property] = ColorIdx()
            end
        end;
    end;
end;

function Library:GiveSignal(Signal)
    -- Only used for signals not attached to library instances, as those should be cleaned up on object destruction by Roblox
    table.insert(Library.Signals, Signal)
end

function Library:Unload()
    -- Unload all of the signals
    for Idx = #Library.Signals, 1, -1 do
        local Connection = table.remove(Library.Signals, Idx)
        Connection:Disconnect()
    end

     -- Call our unload callback, maybe to undo some hooks etc
    if Library.OnUnload then
        Library.OnUnload()
    end

    ScreenGui:Destroy()
end

function Library:OnUnload(Callback)
    Library.OnUnload = Callback
end

Library:GiveSignal(ScreenGui.DescendantRemoving:Connect(function(Instance)
    if Library.RegistryMap[Instance] then
        Library:RemoveFromRegistry(Instance);
    end;
end))

local BaseAddons = {};

do
    local Funcs = {};

    function Funcs:AddColorPicker(Idx, Info)
        local ToggleLabel = self.TextLabel;
        -- local Container = self.Container;

        assert(Info.Default, 'AddColorPicker: Missing default value.');

        local ColorPicker = {
            Value = Info.Default;
            Transparency = Info.Transparency or 0;
            Type = 'ColorPicker';
            Title = type(Info.Title) == 'string' and Info.Title or 'Color picker',
            Callback = Info.Callback or function(Color) end;
        };

        function ColorPicker:SetHSVFromRGB(Color)
            local H, S, V = Color3.toHSV(Color);

            ColorPicker.Hue = H;
            ColorPicker.Sat = S;
            ColorPicker.Vib = V;
        end;

        ColorPicker:SetHSVFromRGB(ColorPicker.Value);

        local DisplayFrame = Library:Create('Frame', {
            BackgroundColor3 = ColorPicker.Value;
            BorderSizePixel = 0;
            Size = UDim2.new(0, 32, 0, 16);
            ZIndex = 6;
            Parent = ToggleLabel;
        });

        Library:AddCorner(DisplayFrame, Library.SmallCornerRadius);

        local DisplayStroke = Library:Create('UIStroke', {
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border;
            Color = Library:GetDarkerColor(ColorPicker.Value);
            Thickness = Library.StrokeThickness;
            Parent = DisplayFrame;
        });

        Library:AddClickFeedback(DisplayFrame, DisplayFrame, 0.92);

        -- Transparency image taken from https://github.com/matas3535/SplixPrivateDrawingLibrary/blob/main/Library.lua cus i'm lazy
        local CheckerFrame = Library:Create('ImageLabel', {
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 5;
            Image = 'http://www.roblox.com/asset/?id=12977615774';
            Visible = not not Info.Transparency;
            Parent = DisplayFrame;
        });

        Library:AddCorner(CheckerFrame, Library.SmallCornerRadius);

        -- 1/16/23
        -- Rewrote this to be placed inside the Library ScreenGui
        -- There was some issue which caused RelativeOffset to be way off
        -- Thus the color picker would never show

        local PickerFrameOuter = Library:Create('Frame', {
            Name = 'Color';
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            Position = UDim2.fromOffset(DisplayFrame.AbsolutePosition.X, DisplayFrame.AbsolutePosition.Y + 22),
            Size = UDim2.fromOffset(244, Info.Transparency and 304 or 282);
            Visible = false;
            ZIndex = 15;
            Parent = ScreenGui,
        });

        local PickerScale = Library:AddScale(PickerFrameOuter, 1);

        DisplayFrame:GetPropertyChangedSignal('AbsolutePosition'):Connect(function()
            PickerFrameOuter.Position = UDim2.fromOffset(DisplayFrame.AbsolutePosition.X, DisplayFrame.AbsolutePosition.Y + 22);
        end)

        local PickerFrameInner = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 16;
            Parent = PickerFrameOuter;
        });

        Library:AddCorner(PickerFrameInner, Library.CornerRadius);
        Library:AddStroke(PickerFrameInner, 'OutlineColor');

        -- Accent header pill (replaces the old full width 2px bar)
        local Highlight = Library:Create('Frame', {
            BackgroundColor3 = Library.AccentColor;
            BorderSizePixel = 0;
            Position = UDim2.fromOffset(12, 13);
            Size = UDim2.new(0, 3, 0, 14);
            ZIndex = 17;
            Parent = PickerFrameInner;
        });

        Library:AddCorner(Highlight, Library.PillCornerRadius);

        local SatVibMapOuter = Library:Create('Frame', {
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            Position = UDim2.new(0, 12, 0, 38);
            Size = UDim2.new(0, 200, 0, 200);
            ZIndex = 17;
            Parent = PickerFrameInner;
        });

        local SatVibMapInner = Library:Create('Frame', {
            BackgroundColor3 = Library.BackgroundColor;
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 18;
            ClipsDescendants = true;
            Parent = SatVibMapOuter;
        });

        Library:AddCorner(SatVibMapInner, Library.SmallCornerRadius);
        Library:AddStroke(SatVibMapInner, 'OutlineColor');

        -- NOTE: BackgroundTransparency must stay 0 - ColorPicker:Display()
        -- drives the hue through SatVibMap.BackgroundColor3.
        local SatVibMap = Library:Create('ImageLabel', {
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 18;
            Image = 'rbxassetid://4155801252';
            Parent = SatVibMapInner;
        });

        Library:AddCorner(SatVibMap, Library.SmallCornerRadius);

        -- Modern ring cursor (white ring + soft dark halo)
        local CursorOuter = Library:Create('Frame', {
            AnchorPoint = Vector2.new(0.5, 0.5);
            Size = UDim2.new(0, 12, 0, 12);
            BackgroundColor3 = Color3.new(1, 1, 1);
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            ZIndex = 19;
            Parent = SatVibMap;
        });

        Library:AddCorner(CursorOuter, Library.PillCornerRadius);

        Library:Create('UIStroke', {
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border;
            Color = Color3.new(0, 0, 0);
            Thickness = 3;
            Transparency = 0.7;
            Parent = CursorOuter;
        });

        local CursorInner = Library:Create('Frame', {
            AnchorPoint = Vector2.new(0.5, 0.5);
            Position = UDim2.fromScale(0.5, 0.5);
            Size = UDim2.new(1, 0, 1, 0);
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            ZIndex = 20;
            Parent = CursorOuter;
        })

        Library:AddCorner(CursorInner, Library.PillCornerRadius);

        Library:Create('UIStroke', {
            ApplyStrokeMode = Enum.ApplyStrokeMode.Border;
            Color = Color3.new(1, 1, 1);
            Thickness = 2;
            Parent = CursorInner;
        });

        local HueSelectorOuter = Library:Create('Frame', {
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            Position = UDim2.new(0, 220, 0, 38);
            Size = UDim2.new(0, 12, 0, 200);
            ZIndex = 17;
            Parent = PickerFrameInner;
        });

        local HueSelectorInner = Library:Create('Frame', {
            BackgroundColor3 = Color3.new(1, 1, 1);
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 18;
            ClipsDescendants = true;
            Parent = HueSelectorOuter;
        });

        Library:AddCorner(HueSelectorInner, Library.PillCornerRadius);
        Library:AddStroke(HueSelectorInner, 'OutlineColor');

        local HueCursor = Library:Create('Frame', {
            BackgroundColor3 = Color3.new(1, 1, 1);
            AnchorPoint = Vector2.new(0, 0.5);
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 0, 3);
            ZIndex = 19;
            Parent = HueSelectorInner;
        });

        Library:AddCorner(HueCursor, Library.PillCornerRadius);

        local HueBoxOuter = Library:Create('Frame', {
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            Position = UDim2.fromOffset(12, 248),
            Size = UDim2.new(0.5, -16, 0, 22),
            ZIndex = 18,
            Parent = PickerFrameInner;
        });

        local HueBoxInner = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 18,
            Parent = HueBoxOuter;
        });

        Library:AddCorner(HueBoxInner, Library.SmallCornerRadius);
        Library:AddStroke(HueBoxInner, 'OutlineColor');

        local HueBox = Library:Create('TextBox', {
            BackgroundTransparency = 1;
            Position = UDim2.new(0, 8, 0, 0);
            Size = UDim2.new(1, -12, 1, 0);
            Font = Library.Font;
            PlaceholderColor3 = Color3.fromRGB(150, 152, 165);
            PlaceholderText = 'Hex color',
            Text = '#FFFFFF',
            TextColor3 = Library.FontColor;
            TextSize = Library.TextSize - 1;
            TextStrokeTransparency = 1;
            TextXAlignment = Enum.TextXAlignment.Left;
            ClearTextOnFocus = false;
            ZIndex = 20,
            Parent = HueBoxInner;
        });

        Library:ApplyTextStroke(HueBox);

        local RgbBoxBase = Library:Create(HueBoxOuter:Clone(), {
            Position = UDim2.new(0.5, 4, 0, 248),
            Size = UDim2.new(0.5, -16, 0, 22),
            Parent = PickerFrameInner
        });

        local RgbBox = Library:Create(RgbBoxBase.Frame:FindFirstChild('TextBox'), {
            Text = '255, 255, 255',
            PlaceholderText = 'RGB color',
            TextColor3 = Library.FontColor
        });

        -- The clone carries copies of the UIStroke, so re-register them.
        do
            local ClonedStroke = RgbBoxBase.Frame:FindFirstChildOfClass('UIStroke');
            if ClonedStroke then
                Library:AddToRegistry(ClonedStroke, { Color = 'OutlineColor' });
            end;
        end;

        local TransparencyBoxOuter, TransparencyBoxInner, TransparencyCursor;

        if Info.Transparency then 
            TransparencyBoxOuter = Library:Create('Frame', {
                BackgroundTransparency = 1;
                BorderSizePixel = 0;
                Position = UDim2.fromOffset(12, 278);
                Size = UDim2.new(1, -24, 0, 14);
                ZIndex = 19;
                Parent = PickerFrameInner;
            });

            TransparencyBoxInner = Library:Create('Frame', {
                BackgroundColor3 = ColorPicker.Value;
                BorderSizePixel = 0;
                Size = UDim2.new(1, 0, 1, 0);
                ZIndex = 19;
                ClipsDescendants = true;
                Parent = TransparencyBoxOuter;
            });

            Library:AddCorner(TransparencyBoxInner, Library.PillCornerRadius);
            Library:AddStroke(TransparencyBoxInner, 'OutlineColor');

            Library:Create('ImageLabel', {
                BackgroundTransparency = 1;
                Size = UDim2.new(1, 0, 1, 0);
                Image = 'http://www.roblox.com/asset/?id=12978095818';
                ZIndex = 20;
                Parent = TransparencyBoxInner;
            });

            TransparencyCursor = Library:Create('Frame', { 
                BackgroundColor3 = Color3.new(1, 1, 1);
                AnchorPoint = Vector2.new(0.5, 0);
                BorderSizePixel = 0;
                Size = UDim2.new(0, 3, 1, 0);
                ZIndex = 21;
                Parent = TransparencyBoxInner;
            });

            Library:AddCorner(TransparencyCursor, Library.PillCornerRadius);
        end;

        local DisplayLabel = Library:CreateLabel({
            Size = UDim2.new(1, -34, 0, 16);
            Position = UDim2.fromOffset(22, 12);
            TextXAlignment = Enum.TextXAlignment.Left;
            TextSize = Library.TitleTextSize;
            Font = Library.FontHeavy;
            Text = ColorPicker.Title,--Info.Default;
            TextWrapped = false;
            TextTruncate = Enum.TextTruncate.AtEnd;
            ZIndex = 17;
            Parent = PickerFrameInner;
        });


        local ContextMenu = {}
        do
            ContextMenu.Options = {}
            ContextMenu.Container = Library:Create('Frame', {
                BackgroundTransparency = 1,
                BorderSizePixel = 0,
                ZIndex = 14,

                Visible = false,
                Parent = ScreenGui
            })

            local ContextScale = Library:AddScale(ContextMenu.Container, 1);

            ContextMenu.Inner = Library:Create('Frame', {
                BackgroundColor3 = Library.MainColor;
                BackgroundTransparency = 0;
                BorderSizePixel = 0;
                Size = UDim2.fromScale(1, 1);
                ZIndex = 15;
                Parent = ContextMenu.Container;
            });

            Library:AddCorner(ContextMenu.Inner, Library.CornerRadius);
            local ContextStroke = Library:AddStroke(ContextMenu.Inner, 'OutlineColor');

            Library:Create('UIListLayout', {
                Name = 'Layout',
                FillDirection = Enum.FillDirection.Vertical;
                SortOrder = Enum.SortOrder.LayoutOrder;
                Padding = UDim.new(0, 2);
                Parent = ContextMenu.Inner;
            });

            Library:Create('UIPadding', {
                Name = 'Padding',
                PaddingLeft = UDim.new(0, 6),
                PaddingRight = UDim.new(0, 6),
                PaddingTop = UDim.new(0, 6),
                PaddingBottom = UDim.new(0, 6),
                Parent = ContextMenu.Inner,
            });

            local function updateMenuPosition()
                ContextMenu.Container.Position = UDim2.fromOffset(
                    (DisplayFrame.AbsolutePosition.X + DisplayFrame.AbsoluteSize.X) + 6,
                    DisplayFrame.AbsolutePosition.Y - 4
                )
            end

            local function updateMenuSize()
                local menuWidth = 92
                for i, label in next, ContextMenu.Inner:GetChildren() do
                    if label:IsA('TextLabel') then
                        menuWidth = math.max(menuWidth, label.TextBounds.X + 20)
                    end
                end

                ContextMenu.Container.Size = UDim2.fromOffset(
                    menuWidth + 12,
                    ContextMenu.Inner.Layout.AbsoluteContentSize.Y + 12
                )
            end

            DisplayFrame:GetPropertyChangedSignal('AbsolutePosition'):Connect(updateMenuPosition)
            ContextMenu.Inner.Layout:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(updateMenuSize)

            task.spawn(updateMenuPosition)
            task.spawn(updateMenuSize)

            Library:AddToRegistry(ContextMenu.Inner, {
                BackgroundColor3 = 'MainColor';
            });

            function ContextMenu:Show()
                self.Container.Visible = true

                ContextScale.Scale = 0.94;
                ContextMenu.Inner.BackgroundTransparency = 1;
                ContextStroke.Transparency = 1;

                Library:Tween(ContextScale, { Scale = 1 }, Library.Animations.Normal, Enum.EasingStyle.Back);
                Library:Tween(ContextMenu.Inner, { BackgroundTransparency = 0 }, Library.Animations.Fast);
                Library:Tween(ContextStroke, { Transparency = 0 }, Library.Animations.Fast);
            end

            function ContextMenu:Hide()
                Library:Tween(ContextScale, { Scale = 0.96 }, Library.Animations.Fast);
                Library:Tween(ContextMenu.Inner, { BackgroundTransparency = 1 }, Library.Animations.Fast);
                Library:Tween(ContextStroke, { Transparency = 1 }, Library.Animations.Fast);

                local Container = self.Container;

                task.delay(Library.Animations.Fast, function()
                    if Container and Container.Parent then
                        Container.Visible = false;
                    end;
                end);
            end

            function ContextMenu:AddOption(Str, Callback)
                if type(Callback) ~= 'function' then
                    Callback = function() end
                end

                local Holder = Library:Create('Frame', {
                    BackgroundColor3 = Library.AccentColor;
                    BackgroundTransparency = 1;
                    BorderSizePixel = 0;
                    Size = UDim2.new(1, 0, 0, 20);
                    ZIndex = 16;
                    Parent = self.Inner;
                });

                Library:AddCorner(Holder, Library.SmallCornerRadius);
                Library:AddToRegistry(Holder, { BackgroundColor3 = 'AccentColor' });

                local Button = Library:CreateLabel({
                    Active = false;
                    BackgroundTransparency = 1;
                    Position = UDim2.fromOffset(8, 0);
                    Size = UDim2.new(1, -16, 1, 0);
                    TextSize = Library.TextSize - 1;
                    Text = Str;
                    ZIndex = 17;
                    Parent = Holder;
                    TextXAlignment = Enum.TextXAlignment.Left,
                });

                Library:AddHoverWash(Holder, Holder, 1, 0.82);

                Library:OnHighlight(Holder, Button, 
                    { TextColor3 = 'AccentColor' },
                    { TextColor3 = 'FontColor' }
                );

                Holder.InputBegan:Connect(function(Input)
                    if Input.UserInputType ~= Enum.UserInputType.MouseButton1 then
                        return
                    end

                    Callback()
                end)
            end

            ContextMenu:AddOption('Copy color', function()
                Library.ColorClipboard = ColorPicker.Value
                Library:Notify('Copied color!', 2)
            end)

            ContextMenu:AddOption('Paste color', function()
                if not Library.ColorClipboard then
                    return Library:Notify('You have not copied a color!', 2)
                end
                ColorPicker:SetValueRGB(Library.ColorClipboard)
            end)


            ContextMenu:AddOption('Copy HEX', function()
                pcall(setclipboard, ColorPicker.Value:ToHex())
                Library:Notify('Copied hex code to clipboard!', 2)
            end)

            ContextMenu:AddOption('Copy RGB', function()
                pcall(setclipboard, table.concat({ math.floor(ColorPicker.Value.R * 255), math.floor(ColorPicker.Value.G * 255), math.floor(ColorPicker.Value.B * 255) }, ', '))
                Library:Notify('Copied RGB values to clipboard!', 2)
            end)

        end

        Library:AddToRegistry(PickerFrameInner, { BackgroundColor3 = 'MainColor'; });
        Library:AddToRegistry(Highlight, { BackgroundColor3 = 'AccentColor'; });
        Library:AddToRegistry(SatVibMapInner, { BackgroundColor3 = 'BackgroundColor'; });

        Library:AddToRegistry(HueBoxInner, { BackgroundColor3 = 'MainColor'; });
        Library:AddToRegistry(RgbBoxBase.Frame, { BackgroundColor3 = 'MainColor'; });
        Library:AddToRegistry(RgbBox, { TextColor3 = 'FontColor', });
        Library:AddToRegistry(HueBox, { TextColor3 = 'FontColor', });

        local SequenceTable = {};

        for Hue = 0, 1, 0.1 do
            table.insert(SequenceTable, ColorSequenceKeypoint.new(Hue, Color3.fromHSV(Hue, 1, 1)));
        end;

        local HueSelectorGradient = Library:Create('UIGradient', {
            Color = ColorSequence.new(SequenceTable);
            Rotation = 90;
            Parent = HueSelectorInner;
        });

        HueBox.FocusLost:Connect(function(enter)
            if enter then
                local success, result = pcall(Color3.fromHex, HueBox.Text)
                if success and typeof(result) == 'Color3' then
                    ColorPicker.Hue, ColorPicker.Sat, ColorPicker.Vib = Color3.toHSV(result)
                end
            end

            ColorPicker:Display()
        end)

        RgbBox.FocusLost:Connect(function(enter)
            if enter then
                local r, g, b = RgbBox.Text:match('(%d+),%s*(%d+),%s*(%d+)')
                if r and g and b then
                    ColorPicker.Hue, ColorPicker.Sat, ColorPicker.Vib = Color3.toHSV(Color3.fromRGB(r, g, b))
                end
            end

            ColorPicker:Display()
        end)

        function ColorPicker:Display()
            ColorPicker.Value = Color3.fromHSV(ColorPicker.Hue, ColorPicker.Sat, ColorPicker.Vib);
            SatVibMap.BackgroundColor3 = Color3.fromHSV(ColorPicker.Hue, 1, 1);

            Library:Create(DisplayFrame, {
                BackgroundColor3 = ColorPicker.Value;
                BackgroundTransparency = ColorPicker.Transparency;
            });

            DisplayStroke.Color = Library:GetDarkerColor(ColorPicker.Value);

            if TransparencyBoxInner then
                TransparencyBoxInner.BackgroundColor3 = ColorPicker.Value;
                TransparencyCursor.Position = UDim2.new(1 - ColorPicker.Transparency, 0, 0, 0);
            end;

            CursorOuter.Position = UDim2.new(ColorPicker.Sat, 0, 1 - ColorPicker.Vib, 0);
            HueCursor.Position = UDim2.new(0, 0, ColorPicker.Hue, 0);

            HueBox.Text = '#' .. ColorPicker.Value:ToHex()
            RgbBox.Text = table.concat({ math.floor(ColorPicker.Value.R * 255), math.floor(ColorPicker.Value.G * 255), math.floor(ColorPicker.Value.B * 255) }, ', ')

            Library:SafeCallback(ColorPicker.Callback, ColorPicker.Value);
            Library:SafeCallback(ColorPicker.Changed, ColorPicker.Value);
        end;

        function ColorPicker:OnChanged(Func)
            ColorPicker.Changed = Func;
            Func(ColorPicker.Value)
        end;

        function ColorPicker:Show()
            for Frame, Val in next, Library.OpenedFrames do
                if Frame.Name == 'Color' then
                    Frame.Visible = false;
                    Library.OpenedFrames[Frame] = nil;
                end;
            end;

            PickerFrameOuter.Visible = true;
            Library.OpenedFrames[PickerFrameOuter] = true;

            -- Pop-in animation (scale only, so no layout is affected)
            PickerScale.Scale = 0.95;
            Library:Tween(PickerScale, { Scale = 1 }, Library.Animations.Normal, Enum.EasingStyle.Back);
        end;

        function ColorPicker:Hide()
            Library.OpenedFrames[PickerFrameOuter] = nil;

            if (not Library.Animations.Enabled) or (not PickerFrameOuter.Visible) then
                PickerFrameOuter.Visible = false;
                return;
            end;

            Library:Tween(PickerScale, { Scale = 0.96 }, Library.Animations.Fast);

            task.delay(Library.Animations.Fast, function()
                if PickerFrameOuter.Parent and (not Library.OpenedFrames[PickerFrameOuter]) then
                    PickerFrameOuter.Visible = false;
                    PickerScale.Scale = 1;
                end;
            end);
        end;

        function ColorPicker:SetValue(HSV, Transparency)
            local Color = Color3.fromHSV(HSV[1], HSV[2], HSV[3]);

            ColorPicker.Transparency = Transparency or 0;
            ColorPicker:SetHSVFromRGB(Color);
            ColorPicker:Display();
        end;

        function ColorPicker:SetValueRGB(Color, Transparency)
            ColorPicker.Transparency = Transparency or 0;
            ColorPicker:SetHSVFromRGB(Color);
            ColorPicker:Display();
        end;

        -- PERF: event driven drag (see Library:BindDrag)
        Library:BindDrag(SatVibMap, function()
            local MinX = SatVibMap.AbsolutePosition.X;
            local MaxX = MinX + SatVibMap.AbsoluteSize.X;
            local MouseX = math.clamp(Mouse.X, MinX, MaxX);

            local MinY = SatVibMap.AbsolutePosition.Y;
            local MaxY = MinY + SatVibMap.AbsoluteSize.Y;
            local MouseY = math.clamp(Mouse.Y, MinY, MaxY);

            ColorPicker.Sat = (MouseX - MinX) / (MaxX - MinX);
            ColorPicker.Vib = 1 - ((MouseY - MinY) / (MaxY - MinY));
            ColorPicker:Display();
        end, function()
            Library:AttemptSave();
        end);

        Library:BindDrag(HueSelectorInner, function()
            local MinY = HueSelectorInner.AbsolutePosition.Y;
            local MaxY = MinY + HueSelectorInner.AbsoluteSize.Y;
            local MouseY = math.clamp(Mouse.Y, MinY, MaxY);

            ColorPicker.Hue = ((MouseY - MinY) / (MaxY - MinY));
            ColorPicker:Display();
        end, function()
            Library:AttemptSave();
        end);

        DisplayFrame.InputBegan:Connect(function(Input)
            if Input.UserInputType == Enum.UserInputType.MouseButton1 and not Library:MouseIsOverOpenedFrame() then
                if PickerFrameOuter.Visible then
                    ColorPicker:Hide()
                else
                    ContextMenu:Hide()
                    ColorPicker:Show()
                end;
            elseif Input.UserInputType == Enum.UserInputType.MouseButton2 and not Library:MouseIsOverOpenedFrame() then
                ContextMenu:Show()
                ColorPicker:Hide()
            end
        end);

        if TransparencyBoxInner then
            Library:BindDrag(TransparencyBoxInner, function()
                local MinX = TransparencyBoxInner.AbsolutePosition.X;
                local MaxX = MinX + TransparencyBoxInner.AbsoluteSize.X;
                local MouseX = math.clamp(Mouse.X, MinX, MaxX);

                ColorPicker.Transparency = 1 - ((MouseX - MinX) / (MaxX - MinX));

                ColorPicker:Display();
            end, function()
                Library:AttemptSave();
            end);
        end;

        Library:GiveSignal(InputService.InputBegan:Connect(function(Input)
            if Input.UserInputType == Enum.UserInputType.MouseButton1 then
                local AbsPos, AbsSize = PickerFrameOuter.AbsolutePosition, PickerFrameOuter.AbsoluteSize;

                if Mouse.X < AbsPos.X or Mouse.X > AbsPos.X + AbsSize.X
                    or Mouse.Y < (AbsPos.Y - 20 - 1) or Mouse.Y > AbsPos.Y + AbsSize.Y then

                    ColorPicker:Hide();
                end;

                if not Library:IsMouseOverFrame(ContextMenu.Container) then
                    ContextMenu:Hide()
                end
            end;

            if Input.UserInputType == Enum.UserInputType.MouseButton2 and ContextMenu.Container.Visible then
                if not Library:IsMouseOverFrame(ContextMenu.Container) and not Library:IsMouseOverFrame(DisplayFrame) then
                    ContextMenu:Hide()
                end
            end
        end))

        ColorPicker:Display();
        ColorPicker.DisplayFrame = DisplayFrame

        Options[Idx] = ColorPicker;

        return self;
    end;

    function Funcs:AddKeyPicker(Idx, Info)
        local ParentObj = self;
        local ToggleLabel = self.TextLabel;
        local Container = self.Container;

        assert(Info.Default, 'AddKeyPicker: Missing default value.');

        local KeyPicker = {
            Value = Info.Default;
            Toggled = false;
            Mode = Info.Mode or 'Toggle'; -- Always, Toggle, Hold
            Type = 'KeyPicker';
            Callback = Info.Callback or function(Value) end;
            ChangedCallback = Info.ChangedCallback or function(New) end;

            SyncToggleState = Info.SyncToggleState or false;
        };

        if KeyPicker.SyncToggleState then
            Info.Modes = { 'Toggle' }
            Info.Mode = 'Toggle'
        end

        local PickOuter = Library:Create('Frame', {
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            Size = UDim2.new(0, 34, 0, 18);
            ZIndex = 6;
            Parent = ToggleLabel;
        });

        local PickInner = Library:Create('Frame', {
            BackgroundColor3 = Library.BackgroundColor;
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 7;
            Parent = PickOuter;
        });

        Library:AddCorner(PickInner, Library.SmallCornerRadius);
        local PickStroke = Library:AddStroke(PickInner, 'OutlineColor');

        Library:AddToRegistry(PickInner, {
            BackgroundColor3 = 'BackgroundColor';
        });

        Library:OnHighlight(PickOuter, PickStroke,
            { Color = 'AccentColor' },
            { Color = 'OutlineColor' }
        );

        Library:AddClickFeedback(PickOuter, PickInner, 0.93);

        local DisplayLabel = Library:CreateLabel({
            Size = UDim2.new(1, 0, 1, 0);
            TextSize = Library.TextSize - 2;
            Font = Library.FontHeavy;
            Text = Info.Default;
            TextWrapped = true;
            ZIndex = 8;
            Parent = PickInner;
        });

        local ModeSelectOuter = Library:Create('Frame', {
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            Position = UDim2.fromOffset(ToggleLabel.AbsolutePosition.X + ToggleLabel.AbsoluteSize.X + 6, ToggleLabel.AbsolutePosition.Y - 2);
            Size = UDim2.new(0, 76, 0, (#(Info.Modes or { 'Always', 'Toggle', 'Hold' }) * 20) + ((#(Info.Modes or { 'Always', 'Toggle', 'Hold' }) - 1) * 2) + 12);
            Visible = false;
            ZIndex = 14;
            Parent = ScreenGui;
        });

        local ModeSelectScale = Library:AddScale(ModeSelectOuter, 1);

        ToggleLabel:GetPropertyChangedSignal('AbsolutePosition'):Connect(function()
            ModeSelectOuter.Position = UDim2.fromOffset(ToggleLabel.AbsolutePosition.X + ToggleLabel.AbsoluteSize.X + 6, ToggleLabel.AbsolutePosition.Y - 2);
        end);

        local ModeSelectInner = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 15;
            Parent = ModeSelectOuter;
        });

        Library:AddCorner(ModeSelectInner, Library.CornerRadius);
        Library:AddStroke(ModeSelectInner, 'OutlineColor');

        Library:AddToRegistry(ModeSelectInner, {
            BackgroundColor3 = 'MainColor';
        });

        Library:Create('UIListLayout', {
            FillDirection = Enum.FillDirection.Vertical;
            SortOrder = Enum.SortOrder.LayoutOrder;
            Padding = UDim.new(0, 2);
            Parent = ModeSelectInner;
        });

        Library:AddPadding(ModeSelectInner, 6);

        -- Animated show / hide for the mode selector.
        local function ShowModeSelect()
            ModeSelectOuter.Visible = true;
            ModeSelectScale.Scale = 0.94;
            Library:Tween(ModeSelectScale, { Scale = 1 }, Library.Animations.Normal, Enum.EasingStyle.Back);
        end;

        local function HideModeSelect()
            if (not ModeSelectOuter.Visible) then return end;

            if (not Library.Animations.Enabled) then
                ModeSelectOuter.Visible = false;
                return;
            end;

            Library:Tween(ModeSelectScale, { Scale = 0.96 }, Library.Animations.Fast);

            task.delay(Library.Animations.Fast, function()
                if ModeSelectOuter.Parent then
                    ModeSelectOuter.Visible = false;
                    ModeSelectScale.Scale = 1;
                end;
            end);
        end;

        local ContainerLabel = Library:CreateLabel({
            TextXAlignment = Enum.TextXAlignment.Left;
            Size = UDim2.new(1, 0, 0, 18);
            TextSize = Library.TextSize - 1;
            Visible = false;
            ZIndex = 110;
            Parent = Library.KeybindContainer;
        },  true);

        local Modes = Info.Modes or { 'Always', 'Toggle', 'Hold' };
        local ModeButtons = {};

        for Idx, Mode in next, Modes do
            local ModeButton = {};

            local Holder = Library:Create('Frame', {
                BackgroundColor3 = Library.AccentColor;
                BackgroundTransparency = 1;
                BorderSizePixel = 0;
                Size = UDim2.new(1, 0, 0, 20);
                ZIndex = 16;
                Parent = ModeSelectInner;
            });

            Library:AddCorner(Holder, Library.SmallCornerRadius);
            Library:AddToRegistry(Holder, { BackgroundColor3 = 'AccentColor' });
            Library:AddHoverWash(Holder, Holder, 1, 0.85);

            local Label = Library:CreateLabel({
                Active = false;
                Size = UDim2.new(1, 0, 1, 0);
                TextSize = Library.TextSize - 1;
                Text = Mode;
                ZIndex = 17;
                Parent = Holder;
            });

            function ModeButton:Select()
                for _, Button in next, ModeButtons do
                    Button:Deselect();
                end;

                KeyPicker.Mode = Mode;

                Library:Tween(Label, { TextColor3 = Library.AccentColor }, Library.Animations.Fast);
                Library.RegistryMap[Label].Properties.TextColor3 = 'AccentColor';

                HideModeSelect();
            end;

            function ModeButton:Deselect()
                KeyPicker.Mode = nil;

                Library:Tween(Label, { TextColor3 = Library.FontColor }, Library.Animations.Fast);
                Library.RegistryMap[Label].Properties.TextColor3 = 'FontColor';
            end;

            Holder.InputBegan:Connect(function(Input)
                if Input.UserInputType == Enum.UserInputType.MouseButton1 then
                    ModeButton:Select();
                    Library:AttemptSave();
                end;
            end);

            if Mode == KeyPicker.Mode then
                ModeButton:Select();
            end;

            ModeButtons[Mode] = ModeButton;
        end;

        function KeyPicker:Update()
            if Info.NoUI then
                return;
            end;

            local State = KeyPicker:GetState();

            ContainerLabel.Text = string.format('[%s] %s (%s)', KeyPicker.Value, Info.Text, KeyPicker.Mode);

            ContainerLabel.Visible = true;
            ContainerLabel.TextColor3 = State and Library.AccentColor or Library.FontColor;

            Library.RegistryMap[ContainerLabel].Properties.TextColor3 = State and 'AccentColor' or 'FontColor';

            local YSize = 0
            local XSize = 0

            for _, Label in next, Library.KeybindContainer:GetChildren() do
                if Label:IsA('TextLabel') and Label.Visible then
                    YSize = YSize + 18;
                    if (Label.TextBounds.X > XSize) then
                        XSize = Label.TextBounds.X
                    end
                end;
            end;

            Library.KeybindFrame.Size = UDim2.new(0, math.max(XSize + 10, 210), 0, YSize + 23)
        end;

        function KeyPicker:GetState()
            if KeyPicker.Mode == 'Always' then
                return true;
            elseif KeyPicker.Mode == 'Hold' then
                if KeyPicker.Value == 'None' then
                    return false;
                end

                local Key = KeyPicker.Value;

                if Key == 'MB1' or Key == 'MB2' then
                    return Key == 'MB1' and InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
                        or Key == 'MB2' and InputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton2);
                else
                    return InputService:IsKeyDown(Enum.KeyCode[KeyPicker.Value]);
                end;
            else
                return KeyPicker.Toggled;
            end;
        end;

        function KeyPicker:SetValue(Data)
            local Key, Mode = Data[1], Data[2];
            DisplayLabel.Text = Key;
            KeyPicker.Value = Key;
            ModeButtons[Mode]:Select();
            KeyPicker:Update();
        end;

        function KeyPicker:OnClick(Callback)
            KeyPicker.Clicked = Callback
        end

        function KeyPicker:OnChanged(Callback)
            KeyPicker.Changed = Callback
            Callback(KeyPicker.Value)
        end

        if ParentObj.Addons then
            table.insert(ParentObj.Addons, KeyPicker)
        end

        function KeyPicker:DoClick()
            if ParentObj.Type == 'Toggle' and KeyPicker.SyncToggleState then
                ParentObj:SetValue(not ParentObj.Value)
            end

            Library:SafeCallback(KeyPicker.Callback, KeyPicker.Toggled)
            Library:SafeCallback(KeyPicker.Clicked, KeyPicker.Toggled)
        end

        local Picking = false;

        PickOuter.InputBegan:Connect(function(Input)
            if Input.UserInputType == Enum.UserInputType.MouseButton1 and not Library:MouseIsOverOpenedFrame() then
                Picking = true;

                DisplayLabel.Text = '';

                local Break;
                local Text = '';

                task.spawn(function()
                    while (not Break) do
                        if Text == '...' then
                            Text = '';
                        end;

                        Text = Text .. '.';
                        DisplayLabel.Text = Text;

                        task.wait(0.4);
                    end;
                end);

                task.wait(0.2);

                local Event;
                Event = InputService.InputBegan:Connect(function(Input)
                    local Key;

                    if Input.UserInputType == Enum.UserInputType.Keyboard then
                        Key = Input.KeyCode.Name;
                    elseif Input.UserInputType == Enum.UserInputType.MouseButton1 then
                        Key = 'MB1';
                    elseif Input.UserInputType == Enum.UserInputType.MouseButton2 then
                        Key = 'MB2';
                    end;

                    Break = true;
                    Picking = false;

                    DisplayLabel.Text = Key;
                    KeyPicker.Value = Key;

                    Library:SafeCallback(KeyPicker.ChangedCallback, Input.KeyCode or Input.UserInputType)
                    Library:SafeCallback(KeyPicker.Changed, Input.KeyCode or Input.UserInputType)

                    Library:AttemptSave();

                    Event:Disconnect();
                end);
            elseif Input.UserInputType == Enum.UserInputType.MouseButton2 and not Library:MouseIsOverOpenedFrame() then
                ShowModeSelect();
            end;
        end);

        Library:GiveSignal(InputService.InputBegan:Connect(function(Input)
            if (not Picking) then
                if KeyPicker.Mode == 'Toggle' then
                    local Key = KeyPicker.Value;

                    if Key == 'MB1' or Key == 'MB2' then
                        if Key == 'MB1' and Input.UserInputType == Enum.UserInputType.MouseButton1
                        or Key == 'MB2' and Input.UserInputType == Enum.UserInputType.MouseButton2 then
                            KeyPicker.Toggled = not KeyPicker.Toggled
                            KeyPicker:DoClick()
                        end;
                    elseif Input.UserInputType == Enum.UserInputType.Keyboard then
                        if Input.KeyCode.Name == Key then
                            KeyPicker.Toggled = not KeyPicker.Toggled;
                            KeyPicker:DoClick()
                        end;
                    end;
                end;

                KeyPicker:Update();
            end;

            if Input.UserInputType == Enum.UserInputType.MouseButton1 then
                local AbsPos, AbsSize = ModeSelectOuter.AbsolutePosition, ModeSelectOuter.AbsoluteSize;

                if Mouse.X < AbsPos.X or Mouse.X > AbsPos.X + AbsSize.X
                    or Mouse.Y < (AbsPos.Y - 20 - 1) or Mouse.Y > AbsPos.Y + AbsSize.Y then

                    HideModeSelect();
                end;
            end;
        end))

        Library:GiveSignal(InputService.InputEnded:Connect(function(Input)
            if (not Picking) then
                KeyPicker:Update();
            end;
        end))

        KeyPicker:Update();

        Options[Idx] = KeyPicker;

        return self;
    end;

    BaseAddons.__index = Funcs;
    BaseAddons.__namecall = function(Table, Key, ...)
        return Funcs[Key](...);
    end;
end;

local BaseGroupbox = {};

do
    local Funcs = {};

    function Funcs:AddBlank(Size)
        local Groupbox = self;
        local Container = Groupbox.Container;

        Library:Create('Frame', {
            BackgroundTransparency = 1;
            Size = UDim2.new(1, 0, 0, Size);
            ZIndex = 1;
            Parent = Container;
        });
    end;

    function Funcs:AddLabel(Text, DoesWrap)
        local Label = {};

        local Groupbox = self;
        local Container = Groupbox.Container;

        local TextLabel = Library:CreateLabel({
            Size = UDim2.new(1, 0, 0, 18);
            TextSize = Library.TextSize;
            Text = Text;
            TextWrapped = DoesWrap or false,
            TextXAlignment = Enum.TextXAlignment.Left;
            ZIndex = 5;
            Parent = Container;
        });

        if DoesWrap then
            local Y = select(2, Library:GetTextBounds(Text, Library.Font, Library.TextSize, Vector2.new(TextLabel.AbsoluteSize.X, math.huge)))
            TextLabel.Size = UDim2.new(1, 0, 0, Y)
        else
            -- NOTE: this layout is required - AddColorPicker / AddKeyPicker
            -- parent their controls into this label and rely on it.
            Library:Create('UIListLayout', {
                Padding = UDim.new(0, 6);
                FillDirection = Enum.FillDirection.Horizontal;
                HorizontalAlignment = Enum.HorizontalAlignment.Right;
                VerticalAlignment = Enum.VerticalAlignment.Center;
                SortOrder = Enum.SortOrder.LayoutOrder;
                Parent = TextLabel;
            });
        end

        Label.TextLabel = TextLabel;
        Label.Container = Container;

        function Label:SetText(Text)
            TextLabel.Text = Text

            if DoesWrap then
                local Y = select(2, Library:GetTextBounds(Text, Library.Font, Library.TextSize, Vector2.new(TextLabel.AbsoluteSize.X, math.huge)))
                TextLabel.Size = UDim2.new(1, 0, 0, Y)
            end

            Groupbox:Resize();
        end

        if (not DoesWrap) then
            setmetatable(Label, BaseAddons);
        end

        Groupbox:AddBlank(6);
        Groupbox:Resize();

        return Label;
    end;

    --[[
        NEW (optional) API - Funcs:AddSection(Name)

        Adds a labelled separator inside a groupbox. Purely additive: existing
        scripts are unaffected, and it is documented in README.md.
        Returns a table with :SetText(Text).
    ]]
    function Funcs:AddSection(Name)
        local Groupbox = self;
        local Container = Groupbox.Container;

        local Section = { Type = 'Section' };

        Groupbox:AddBlank(4);

        local Holder = Library:Create('Frame', {
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 0, 16);
            ZIndex = 5;
            Parent = Container;
        });

        local Bar = Library:Create('Frame', {
            BackgroundColor3 = Library.AccentColor;
            BorderSizePixel = 0;
            AnchorPoint = Vector2.new(0, 0.5);
            Position = UDim2.new(0, 0, 0.5, 0);
            Size = UDim2.new(0, 2, 0, 10);
            ZIndex = 6;
            Parent = Holder;
        });

        Library:AddCorner(Bar, Library.PillCornerRadius);
        Library:AddToRegistry(Bar, { BackgroundColor3 = 'AccentColor' });

        local Label = Library:CreateLabel({
            Position = UDim2.fromOffset(8, 0);
            Size = UDim2.new(1, -8, 1, 0);
            TextSize = Library.TextSize - 1;
            Font = Library.FontHeavy;
            Text = tostring(Name);
            TextXAlignment = Enum.TextXAlignment.Left;
            ZIndex = 6;
            Parent = Holder;
        });

        function Section:SetText(NewText)
            Label.Text = tostring(NewText);
        end;

        Section.TextLabel = Label;
        Section.Container = Holder;

        Groupbox:AddBlank(6);
        Groupbox:Resize();

        return Section;
    end;

    function Funcs:AddButton(...)
        -- TODO: Eventually redo this
        local Button = {};
        local function ProcessButtonParams(Class, Obj, ...)
            local Props = select(1, ...)
            if type(Props) == 'table' then
                Obj.Text = Props.Text
                Obj.Func = Props.Func
                Obj.DoubleClick = Props.DoubleClick
                Obj.Tooltip = Props.Tooltip
            else
                Obj.Text = select(1, ...)
                Obj.Func = select(2, ...)
            end

            assert(type(Obj.Func) == 'function', 'AddButton: `Func` callback is missing.');
        end

        ProcessButtonParams('Button', Button, ...)

        local Groupbox = self;
        local Container = Groupbox.Container;

        local function CreateBaseButton(Button)
            -- The Outer / Inner pair is preserved (element sizing + registry
            -- rely on it) but Outer is now an invisible hit-box and all the
            -- visuals live on the rounded Inner surface.
            local Outer = Library:Create('Frame', {
                BackgroundTransparency = 1;
                BorderSizePixel = 0;
                Size = UDim2.new(1, 0, 0, 26);
                ZIndex = 5;
            });

            local Inner = Library:Create('Frame', {
                BackgroundColor3 = Library:GetSurfaceColor();
                BorderSizePixel = 0;
                Size = UDim2.new(1, 0, 1, 0);
                ZIndex = 6;
                Parent = Outer;
            });

            Library:AddCorner(Inner, Library.CornerRadius);
            local Stroke = Library:AddStroke(Inner, 'OutlineColor');

            -- Hover wash sits above the surface, below the label.
            local Wash = Library:Create('Frame', {
                BackgroundColor3 = Library.AccentColor;
                BackgroundTransparency = 1;
                BorderSizePixel = 0;
                Size = UDim2.new(1, 0, 1, 0);
                ZIndex = 6;
                Parent = Inner;
            });

            Library:AddCorner(Wash, Library.CornerRadius);
            Library:AddToRegistry(Wash, { BackgroundColor3 = 'AccentColor' });

            local Label = Library:CreateLabel({
                Size = UDim2.new(1, 0, 1, 0);
                TextSize = Library.TextSize;
                Font = Library.FontHeavy;
                Text = Button.Text;
                ZIndex = 7;
                Parent = Inner;
            });

            Library:AddToRegistry(Inner, {
                BackgroundColor3 = function() return Library:GetSurfaceColor() end;
            });

            Library:AddHoverWash(Outer, Wash, 1, 0.9);

            Library:OnHighlight(Outer, Stroke,
                { Color = 'AccentColor' },
                { Color = 'OutlineColor' }
            );

            Library:AddClickFeedback(Outer, Inner, 0.97);

            return Outer, Inner, Label
        end

        local function InitEvents(Button)
            local function WaitForEvent(event, timeout, validator)
                local bindable = Instance.new('BindableEvent')
                local connection = event:Once(function(...)

                    if type(validator) == 'function' and validator(...) then
                        bindable:Fire(true)
                    else
                        bindable:Fire(false)
                    end
                end)
                task.delay(timeout, function()
                    connection:disconnect()
                    bindable:Fire(false)
                end)
                return bindable.Event:Wait()
            end

            local function ValidateClick(Input)
                if Library:MouseIsOverOpenedFrame() then
                    return false
                end

                if Input.UserInputType ~= Enum.UserInputType.MouseButton1 then
                    return false
                end

                return true
            end

            Button.Outer.InputBegan:Connect(function(Input)
                if not ValidateClick(Input) then return end
                if Button.Locked then return end

                if Button.DoubleClick then
                    Library:RemoveFromRegistry(Button.Label)
                    Library:AddToRegistry(Button.Label, { TextColor3 = 'AccentColor' })

                    Button.Label.TextColor3 = Library.AccentColor
                    Button.Label.Text = 'Are you sure?'
                    Button.Locked = true

                    local clicked = WaitForEvent(Button.Outer.InputBegan, 0.5, ValidateClick)

                    Library:RemoveFromRegistry(Button.Label)
                    Library:AddToRegistry(Button.Label, { TextColor3 = 'FontColor' })

                    Button.Label.TextColor3 = Library.FontColor
                    Button.Label.Text = Button.Text
                    task.defer(rawset, Button, 'Locked', false)

                    if clicked then
                        Library:SafeCallback(Button.Func)
                    end

                    return
                end

                Library:SafeCallback(Button.Func);
            end)
        end

        Button.Outer, Button.Inner, Button.Label = CreateBaseButton(Button)
        Button.Outer.Parent = Container

        InitEvents(Button)

        function Button:AddTooltip(tooltip)
            if type(tooltip) == 'string' then
                Library:AddToolTip(tooltip, self.Outer)
            end
            return self
        end


        function Button:AddButton(...)
            local SubButton = {}

            ProcessButtonParams('SubButton', SubButton, ...)

            self.Outer.Size = UDim2.new(0.5, -3, 0, 26)

            SubButton.Outer, SubButton.Inner, SubButton.Label = CreateBaseButton(SubButton)

            SubButton.Outer.Position = UDim2.new(1, 6, 0, 0)
            SubButton.Outer.Size = UDim2.new(1, 0, 1, 0)
            SubButton.Outer.Parent = self.Outer

            function SubButton:AddTooltip(tooltip)
                if type(tooltip) == 'string' then
                    Library:AddToolTip(tooltip, self.Outer)
                end
                return SubButton
            end

            if type(SubButton.Tooltip) == 'string' then
                SubButton:AddTooltip(SubButton.Tooltip)
            end

            InitEvents(SubButton)
            return SubButton
        end

        if type(Button.Tooltip) == 'string' then
            Button:AddTooltip(Button.Tooltip)
        end

        Groupbox:AddBlank(6);
        Groupbox:Resize();

        return Button;
    end;

    function Funcs:AddDivider()
        local Groupbox = self;
        local Container = self.Container

        local Divider = {
            Type = 'Divider',
        }

        Groupbox:AddBlank(4);

        local DividerOuter = Library:Create('Frame', {
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 0, 1);
            ZIndex = 5;
            Parent = Container;
        });

        local DividerInner = Library:Create('Frame', {
            BackgroundColor3 = Library.OutlineColor;
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 6;
            Parent = DividerOuter;
        });

        Library:AddCorner(DividerInner, Library.PillCornerRadius);

        Library:AddToRegistry(DividerInner, {
            BackgroundColor3 = 'OutlineColor';
        });

        Divider.Outer = DividerOuter;
        Divider.Inner = DividerInner;

        Groupbox:AddBlank(8);
        Groupbox:Resize();

        return Divider;
    end

    function Funcs:AddInput(Idx, Info)
        assert(Info.Text, 'AddInput: Missing `Text` string.')

        local Textbox = {
            Value = Info.Default or '';
            Numeric = Info.Numeric or false;
            Finished = Info.Finished or false;
            Type = 'Input';
            Callback = Info.Callback or function(Value) end;
        };

        local Groupbox = self;
        local Container = Groupbox.Container;

        local InputLabel = Library:CreateLabel({
            Size = UDim2.new(1, 0, 0, 16);
            TextSize = Library.TextSize;
            Text = Info.Text;
            TextXAlignment = Enum.TextXAlignment.Left;
            ZIndex = 5;
            Parent = Container;
        });

        Groupbox:AddBlank(4);

        local TextBoxOuter = Library:Create('Frame', {
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 0, 26);
            ZIndex = 5;
            Parent = Container;
        });

        local TextBoxInner = Library:Create('Frame', {
            BackgroundColor3 = Library.BackgroundColor;
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 6;
            Parent = TextBoxOuter;
        });

        Library:AddCorner(TextBoxInner, Library.CornerRadius);
        local TextBoxStroke = Library:AddStroke(TextBoxInner, 'OutlineColor');

        Library:AddToRegistry(TextBoxInner, {
            BackgroundColor3 = 'BackgroundColor';
        });

        Library:OnHighlight(TextBoxOuter, TextBoxStroke,
            { Color = 'AccentColor' },
            { Color = 'OutlineColor' }
        );

        if type(Info.Tooltip) == 'string' then
            Library:AddToolTip(Info.Tooltip, TextBoxOuter)
        end

        local Container = Library:Create('Frame', {
            BackgroundTransparency = 1;
            ClipsDescendants = true;

            Position = UDim2.new(0, 8, 0, 0);
            Size = UDim2.new(1, -14, 1, 0);

            ZIndex = 7;
            Parent = TextBoxInner;
        })

        local Box = Library:Create('TextBox', {
            BackgroundTransparency = 1;

            Position = UDim2.fromOffset(0, 0),
            Size = UDim2.fromScale(5, 1),

            Font = Library.Font;
            PlaceholderColor3 = Color3.fromRGB(150, 152, 165);
            PlaceholderText = Info.Placeholder or '';

            Text = Info.Default or '';
            TextColor3 = Library.FontColor;
            TextSize = Library.TextSize;
            TextStrokeTransparency = 1;
            TextXAlignment = Enum.TextXAlignment.Left;
            ClearTextOnFocus = false;

            ZIndex = 7;
            Parent = Container;
        });

        Library:ApplyTextStroke(Box);

        -- Focus ring: the stroke turns accent-coloured while typing.
        Box.Focused:Connect(function()
            Library:Tween(TextBoxStroke, { Color = Library.AccentColor, Thickness = Library.StrokeThickness + 0.4 }, Library.Animations.Fast);
        end);

        Box.FocusLost:Connect(function()
            Library:Tween(TextBoxStroke, { Color = Library.OutlineColor, Thickness = Library.StrokeThickness }, Library.Animations.Normal);
        end);

        function Textbox:SetValue(Text)
            if Info.MaxLength and #Text > Info.MaxLength then
                Text = Text:sub(1, Info.MaxLength);
            end;

            if Textbox.Numeric then
                if (not tonumber(Text)) and Text:len() > 0 then
                    Text = Textbox.Value
                end
            end

            Textbox.Value = Text;
            Box.Text = Text;

            Library:SafeCallback(Textbox.Callback, Textbox.Value);
            Library:SafeCallback(Textbox.Changed, Textbox.Value);
        end;

        if Textbox.Finished then
            Box.FocusLost:Connect(function(enter)
                if not enter then return end

                Textbox:SetValue(Box.Text);
                Library:AttemptSave();
            end)
        else
            Box:GetPropertyChangedSignal('Text'):Connect(function()
                Textbox:SetValue(Box.Text);
                Library:AttemptSave();
            end);
        end

        -- https://devforum.roblox.com/t/how-to-make-textboxes-follow-current-cursor-position/1368429/6
        -- thank you nicemike40 :)

        local function Update()
            local PADDING = 2
            local reveal = Container.AbsoluteSize.X

            if not Box:IsFocused() or Box.TextBounds.X <= reveal - 2 * PADDING then
                -- we aren't focused, or we fit so be normal
                Box.Position = UDim2.new(0, PADDING, 0, 0)
            else
                -- we are focused and don't fit, so adjust position
                local cursor = Box.CursorPosition
                if cursor ~= -1 then
                    -- calculate pixel width of text from start to cursor
                    local subtext = string.sub(Box.Text, 1, cursor-1)
                    local width = TextService:GetTextSize(subtext, Box.TextSize, Box.Font, Vector2.new(math.huge, math.huge)).X

                    -- check if we're inside the box with the cursor
                    local currentCursorPos = Box.Position.X.Offset + width

                    -- adjust if necessary
                    if currentCursorPos < PADDING then
                        Box.Position = UDim2.fromOffset(PADDING-width, 0)
                    elseif currentCursorPos > reveal - PADDING - 1 then
                        Box.Position = UDim2.fromOffset(reveal-width-PADDING-1, 0)
                    end
                end
            end
        end

        task.spawn(Update)

        Box:GetPropertyChangedSignal('Text'):Connect(Update)
        Box:GetPropertyChangedSignal('CursorPosition'):Connect(Update)
        Box.FocusLost:Connect(Update)
        Box.Focused:Connect(Update)

        Library:AddToRegistry(Box, {
            TextColor3 = 'FontColor';
        });

        function Textbox:OnChanged(Func)
            Textbox.Changed = Func;
            Func(Textbox.Value);
        end;

        Groupbox:AddBlank(6);
        Groupbox:Resize();

        Options[Idx] = Textbox;

        return Textbox;
    end;

    function Funcs:AddToggle(Idx, Info)
        assert(Info.Text, 'AddInput: Missing `Text` string.')

        local Toggle = {
            Value = Info.Default or false;
            Type = 'Toggle';

            Callback = Info.Callback or function(Value) end;
            Addons = {},
            Risky = Info.Risky,
        };

        local Groupbox = self;
        local Container = Groupbox.Container;

        --[[
            The toggle is now a full-width row: an animated pill switch on the
            left and the label filling the rest. ToggleOuter keeps its role as
            the sized element (Groupbox:Resize reads Size.Y.Offset) and
            ToggleLabel keeps its right-aligned horizontal UIListLayout because
            AddColorPicker / AddKeyPicker parent their controls into it.
        ]]
        local TRACK_WIDTH, TRACK_HEIGHT = 36, 20;
        local THUMB_SIZE = 14;

        local ToggleOuter = Library:Create('Frame', {
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 0, TRACK_HEIGHT);
            ZIndex = 5;
            Parent = Container;
        });

        -- ToggleInner is the switch track.
        local ToggleInner = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderSizePixel = 0;
            Size = UDim2.new(0, TRACK_WIDTH, 0, TRACK_HEIGHT);
            ZIndex = 6;
            Parent = ToggleOuter;
        });

        Library:AddCorner(ToggleInner, Library.PillCornerRadius);
        local ToggleStroke = Library:AddStroke(ToggleInner, 'OutlineColor');

        Library:AddToRegistry(ToggleInner, {
            BackgroundColor3 = 'MainColor';
        });

        local Thumb = Library:Create('Frame', {
            BackgroundColor3 = Library.FontColor;
            BorderSizePixel = 0;
            AnchorPoint = Vector2.new(0, 0.5);
            Position = UDim2.new(0, 3, 0.5, 0);
            Size = UDim2.new(0, THUMB_SIZE, 0, THUMB_SIZE);
            ZIndex = 7;
            Parent = ToggleInner;
        });

        Library:AddCorner(Thumb, Library.PillCornerRadius);

        local ToggleLabel = Library:CreateLabel({
            Size = UDim2.new(1, -(TRACK_WIDTH + 10), 1, 0);
            Position = UDim2.new(0, TRACK_WIDTH + 10, 0, 0);
            TextSize = Library.TextSize;
            Text = Info.Text;
            TextXAlignment = Enum.TextXAlignment.Left;
            ZIndex = 6;
            Parent = ToggleOuter;
        });

        Library:Create('UIListLayout', {
            Padding = UDim.new(0, 6);
            FillDirection = Enum.FillDirection.Horizontal;
            HorizontalAlignment = Enum.HorizontalAlignment.Right;
            VerticalAlignment = Enum.VerticalAlignment.Center;
            SortOrder = Enum.SortOrder.LayoutOrder;
            Parent = ToggleLabel;
        });

        -- Clickable region: switch + label text. The right-hand strip stays
        -- free so ColorPicker / KeyPicker addons remain clickable.
        local ToggleRegion = Library:Create('Frame', {
            BackgroundTransparency = 1;
            Size = UDim2.new(1, -80, 1, 0);
            ZIndex = 8;
            Parent = ToggleOuter;
        });

        Library:OnHighlight(ToggleRegion, ToggleStroke,
            { Color = 'AccentColor' },
            { Color = 'OutlineColor' }
        );

        Library:AddClickFeedback(ToggleRegion, ToggleInner, 0.92);

        function Toggle:UpdateColors()
            Toggle:Display();
        end;

        if type(Info.Tooltip) == 'string' then
            Library:AddToolTip(Info.Tooltip, ToggleRegion)
        end

        function Toggle:Display()
            local TrackColor = Toggle.Value and Library.AccentColor or Library.MainColor;
            local StrokeColor = Toggle.Value and Library.AccentColorDark or Library.OutlineColor;
            local ThumbPosition = Toggle.Value
                and UDim2.new(1, -(THUMB_SIZE + 3), 0.5, 0)
                or UDim2.new(0, 3, 0.5, 0);
            local ThumbColor = Toggle.Value and Color3.new(1, 1, 1) or Library.FontColor;

            -- Animated thumb + colour transition.
            Library:Tween(ToggleInner, { BackgroundColor3 = TrackColor }, Library.Animations.Normal);
            Library:Tween(ToggleStroke, { Color = StrokeColor }, Library.Animations.Normal);
            Library:Tween(Thumb, { Position = ThumbPosition, BackgroundColor3 = ThumbColor }, Library.Animations.Normal, Enum.EasingStyle.Back);

            Library.RegistryMap[ToggleInner].Properties.BackgroundColor3 = Toggle.Value and 'AccentColor' or 'MainColor';
            Library.RegistryMap[ToggleStroke].Properties.Color = Toggle.Value and 'AccentColorDark' or 'OutlineColor';
        end;

        function Toggle:OnChanged(Func)
            Toggle.Changed = Func;
            Func(Toggle.Value);
        end;

        function Toggle:SetValue(Bool)
            Bool = (not not Bool);

            Toggle.Value = Bool;
            Toggle:Display();

            for _, Addon in next, Toggle.Addons do
                if Addon.Type == 'KeyPicker' and Addon.SyncToggleState then
                    Addon.Toggled = Bool
                    Addon:Update()
                end
            end

            Library:SafeCallback(Toggle.Callback, Toggle.Value);
            Library:SafeCallback(Toggle.Changed, Toggle.Value);
            Library:UpdateDependencyBoxes();
        end;

        ToggleRegion.InputBegan:Connect(function(Input)
            if Input.UserInputType == Enum.UserInputType.MouseButton1 and not Library:MouseIsOverOpenedFrame() then
                Toggle:SetValue(not Toggle.Value) -- Why was it not like this from the start?
                Library:AttemptSave();
            end;
        end);

        if Toggle.Risky then
            Library:RemoveFromRegistry(ToggleLabel)
            ToggleLabel.TextColor3 = Library.RiskColor
            Library:AddToRegistry(ToggleLabel, { TextColor3 = 'RiskColor' })
        end

        Toggle:Display();
        Groupbox:AddBlank(Info.BlankSize or 7);
        Groupbox:Resize();

        Toggle.TextLabel = ToggleLabel;
        Toggle.Container = Container;
        setmetatable(Toggle, BaseAddons);

        Toggles[Idx] = Toggle;

        Library:UpdateDependencyBoxes();

        return Toggle;
    end;

    function Funcs:AddSlider(Idx, Info)
        assert(Info.Default, 'AddSlider: Missing default value.');
        assert(Info.Text, 'AddSlider: Missing slider text.');
        assert(Info.Min, 'AddSlider: Missing minimum value.');
        assert(Info.Max, 'AddSlider: Missing maximum value.');
        assert(Info.Rounding, 'AddSlider: Missing rounding value.');

        local Slider = {
            Value = Info.Default;
            Min = Info.Min;
            Max = Info.Max;
            Rounding = Info.Rounding;
            MaxSize = 232;
            Type = 'Slider';
            Callback = Info.Callback or function(Value) end;
        };

        local Groupbox = self;
        local Container = Groupbox.Container;

        if not Info.Compact then
            Library:CreateLabel({
                Size = UDim2.new(1, 0, 0, 14);
                TextSize = Library.TextSize;
                Text = Info.Text;
                TextXAlignment = Enum.TextXAlignment.Left;
                TextYAlignment = Enum.TextYAlignment.Bottom;
                ZIndex = 5;
                Parent = Container;
            });

            Groupbox:AddBlank(4);
        end

        local SLIDER_HEIGHT = 18;
        local KNOB_SIZE = 12;

        -- Transparent hitbox wrapper (keeps the historical Outer/Inner shape).
        local SliderOuter = Library:Create('Frame', {
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 0, SLIDER_HEIGHT);
            ZIndex = 5;
            Parent = Container;
        });

        -- Modern rounded track.
        local SliderInner = Library:Create('Frame', {
            BackgroundColor3 = Library.BackgroundColor;
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 1, 0);
            ClipsDescendants = false;
            ZIndex = 6;
            Parent = SliderOuter;
        });

        Library:AddCorner(SliderInner, Library.PillCornerRadius);
        local SliderStroke = Library:AddStroke(SliderInner, 'OutlineColor');

        Library:AddToRegistry(SliderInner, {
            BackgroundColor3 = 'BackgroundColor';
        });

        -- Scale-based fill so it animates smoothly at any width.
        local Fill = Library:Create('Frame', {
            BackgroundColor3 = Library.AccentColor;
            BorderSizePixel = 0;
            Size = UDim2.fromScale(0, 1);
            ZIndex = 7;
            Parent = SliderInner;
        });

        Library:AddCorner(Fill, Library.PillCornerRadius);

        Library:AddToRegistry(Fill, {
            BackgroundColor3 = 'AccentColor';
        });

        -- Rounded knob, kept fully inside the track via a dynamic AnchorPoint.
        local Knob = Library:Create('Frame', {
            BackgroundColor3 = Color3.new(1, 1, 1);
            BorderSizePixel = 0;
            AnchorPoint = Vector2.new(0, 0.5);
            Position = UDim2.new(0, 0, 0.5, 0);
            Size = UDim2.new(0, KNOB_SIZE, 0, KNOB_SIZE);
            ZIndex = 9;
            Parent = SliderInner;
        });

        Library:AddCorner(Knob, Library.PillCornerRadius);
        local KnobStroke = Library:AddStroke(Knob, 'AccentColorDark');
        local KnobScale = Library:AddScale(Knob, 1);

        local DisplayLabel = Library:CreateLabel({
            Size = UDim2.new(1, 0, 1, 0);
            TextSize = Library.TextSize - 1;
            Font = Library.FontHeavy;
            Text = 'Infinite';
            ZIndex = 10;
            Parent = SliderInner;
        });

        Library:OnHighlight(SliderOuter, SliderStroke,
            { Color = 'AccentColor' },
            { Color = 'OutlineColor' }
        );

        -- Hover feedback: the knob grows slightly.
        SliderOuter.MouseEnter:Connect(function()
            if Library:MouseIsOverOpenedFrame() then return end;
            Library:Tween(KnobScale, { Scale = 1.15 }, Library.Animations.Fast);
        end);

        SliderOuter.MouseLeave:Connect(function()
            Library:Tween(KnobScale, { Scale = 1 }, Library.Animations.Normal);
        end);

        if type(Info.Tooltip) == 'string' then
            Library:AddToolTip(Info.Tooltip, SliderOuter)
        end

        function Slider:UpdateColors()
            Fill.BackgroundColor3 = Library.AccentColor;
            KnobStroke.Color = Library.AccentColorDark;
        end;

        -- Animate = false while dragging so the slider feels perfectly responsive.
        function Slider:Display(Animate)
            local Suffix = Info.Suffix or '';

            if Info.Compact then
                DisplayLabel.Text = Info.Text .. ': ' .. Slider.Value .. Suffix
            elseif Info.HideMax then
                DisplayLabel.Text = string.format('%s', Slider.Value .. Suffix)
            else
                DisplayLabel.Text = string.format('%s/%s', Slider.Value .. Suffix, Slider.Max .. Suffix);
            end

            local Percent = 0;

            if Slider.Max ~= Slider.Min then
                Percent = math.clamp((Slider.Value - Slider.Min) / (Slider.Max - Slider.Min), 0, 1);
            end;

            local FillSize = UDim2.fromScale(Percent, 1);
            local KnobPosition = UDim2.new(Percent, 0, 0.5, 0);
            local KnobAnchor = Vector2.new(Percent, 0.5);

            if Animate == false then
                Fill.Size = FillSize;
                Knob.Position = KnobPosition;
                Knob.AnchorPoint = KnobAnchor;
            else
                Library:Tween(Fill, { Size = FillSize }, Library.Animations.Normal);
                Library:Tween(Knob, { Position = KnobPosition, AnchorPoint = KnobAnchor }, Library.Animations.Normal);
            end;
        end;

        function Slider:OnChanged(Func)
            Slider.Changed = Func;
            Func(Slider.Value);
        end;

        local function Round(Value)
            if Slider.Rounding == 0 then
                return math.floor(Value);
            end;


            return tonumber(string.format('%.' .. Slider.Rounding .. 'f', Value))
        end;

        function Slider:GetValueFromXOffset(X)
            return Round(Library:MapValue(X, 0, Slider.MaxSize, Slider.Min, Slider.Max));
        end;

        function Slider:SetValue(Str)
            local Num = tonumber(Str);

            if (not Num) then
                return;
            end;

            Num = math.clamp(Num, Slider.Min, Slider.Max);

            Slider.Value = Num;
            Slider:Display();

            Library:SafeCallback(Slider.Callback, Slider.Value);
            Library:SafeCallback(Slider.Changed, Slider.Value);
        end;

        --[[
            Event-driven drag (Library:BindDrag) instead of the old
            `while IsMouseButtonPressed do RenderStepped:Wait() end` polling
            loop: nothing runs when the slider is idle.
        ]]
        Library:BindDrag(SliderInner, function()
            if Library:MouseIsOverOpenedFrame() then return end;

            local Width = SliderInner.AbsoluteSize.X;

            if Width <= 0 then return end;

            local Rel = math.clamp((Mouse.X - SliderInner.AbsolutePosition.X) / Width, 0, 1);
            local NewValue = Slider:GetValueFromXOffset(Rel * Slider.MaxSize);
            local OldValue = Slider.Value;

            Slider.Value = math.clamp(NewValue, Slider.Min, Slider.Max);
            Slider:Display(false);

            if Slider.Value ~= OldValue then
                Library:SafeCallback(Slider.Callback, Slider.Value);
                Library:SafeCallback(Slider.Changed, Slider.Value);
            end;
        end, function()
            Library:Tween(KnobScale, { Scale = 1 }, Library.Animations.Normal);
            Library:AttemptSave();
        end);

        Slider:Display();
        Groupbox:AddBlank(Info.BlankSize or 6);
        Groupbox:Resize();

        Options[Idx] = Slider;

        return Slider;
    end;

    function Funcs:AddDropdown(Idx, Info)
        if Info.SpecialType == 'Player' then
            Info.Values = GetPlayersString();
            Info.AllowNull = true;
        elseif Info.SpecialType == 'Team' then
            Info.Values = GetTeamsString();
            Info.AllowNull = true;
        end;

        assert(Info.Values, 'AddDropdown: Missing dropdown value list.');
        assert(Info.AllowNull or Info.Default, 'AddDropdown: Missing default value. Pass `AllowNull` as true if this was intentional.')

        if (not Info.Text) then
            Info.Compact = true;
        end;

        local Dropdown = {
            Values = Info.Values;
            Value = Info.Multi and {};
            Multi = Info.Multi;
            Type = 'Dropdown';
            SpecialType = Info.SpecialType; -- can be either 'Player' or 'Team'
            Callback = Info.Callback or function(Value) end;
        };

        local Groupbox = self;
        local Container = Groupbox.Container;

        local RelativeOffset = 0;

        if not Info.Compact then
            local DropdownLabel = Library:CreateLabel({
                Size = UDim2.new(1, 0, 0, 14);
                TextSize = Library.TextSize;
                Text = Info.Text;
                TextXAlignment = Enum.TextXAlignment.Left;
                TextYAlignment = Enum.TextYAlignment.Bottom;
                ZIndex = 5;
                Parent = Container;
            });

            Groupbox:AddBlank(4);
        end

        for _, Element in next, Container:GetChildren() do
            if not Element:IsA('UIListLayout') then
                RelativeOffset = RelativeOffset + Element.Size.Y.Offset;
            end;
        end;

        local DROPDOWN_HEIGHT = 26;

        local DropdownOuter = Library:Create('Frame', {
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 0, DROPDOWN_HEIGHT);
            ZIndex = 5;
            Parent = Container;
        });

        local DropdownInner = Library:Create('Frame', {
            BackgroundColor3 = Library.BackgroundColor;
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 1, 0);
            ZIndex = 6;
            Parent = DropdownOuter;
        });

        Library:AddCorner(DropdownInner, Library.CornerRadius);
        local DropdownStroke = Library:AddStroke(DropdownInner, 'OutlineColor');

        Library:AddToRegistry(DropdownInner, {
            BackgroundColor3 = 'BackgroundColor';
        });

        local DropdownArrow = Library:Create('ImageLabel', {
            AnchorPoint = Vector2.new(0.5, 0.5);
            BackgroundTransparency = 1;
            Position = UDim2.new(1, -14, 0.5, 0);
            Size = UDim2.new(0, 12, 0, 12);
            Image = 'http://www.roblox.com/asset/?id=6282522798';
            ImageColor3 = Library.FontColor;
            ZIndex = 8;
            Parent = DropdownInner;
        });

        Library:AddToRegistry(DropdownArrow, {
            ImageColor3 = 'FontColor';
        });

        local ItemList = Library:CreateLabel({
            Position = UDim2.new(0, 9, 0, 0);
            Size = UDim2.new(1, -32, 1, 0);
            TextSize = Library.TextSize;
            Text = '--';
            TextXAlignment = Enum.TextXAlignment.Left;
            TextTruncate = Enum.TextTruncate.AtEnd;
            ZIndex = 7;
            Parent = DropdownInner;
        });

        Library:OnHighlight(DropdownOuter, DropdownStroke,
            { Color = 'AccentColor' },
            { Color = 'OutlineColor' }
        );

        if type(Info.Tooltip) == 'string' then
            Library:AddToolTip(Info.Tooltip, DropdownOuter)
        end

        local MAX_DROPDOWN_ITEMS = 8;
        local ITEM_HEIGHT = 22;

        -- The list is a clipping holder whose height is animated on open/close.
        local ListOuter = Library:Create('Frame', {
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            ClipsDescendants = true;
            ZIndex = 20;
            Visible = false;
            Parent = ScreenGui;
        });

        local Opened = false;
        local ListSizeY = MAX_DROPDOWN_ITEMS * ITEM_HEIGHT + 2;

        local function RecalculateListPosition()
            ListOuter.Position = UDim2.fromOffset(DropdownOuter.AbsolutePosition.X, DropdownOuter.AbsolutePosition.Y + DropdownOuter.Size.Y.Offset + 4);
        end;

        local ListInner;

        local function RecalculateListSize(YSize)
            ListSizeY = YSize or (MAX_DROPDOWN_ITEMS * ITEM_HEIGHT + 2);

            local Width = DropdownOuter.AbsoluteSize.X;

            ListOuter.Size = UDim2.fromOffset(Width, Opened and ListSizeY or 0);

            if ListInner then
                ListInner.Size = UDim2.new(1, 0, 0, ListSizeY);
            end;
        end;

        RecalculateListPosition();
        RecalculateListSize();

        DropdownOuter:GetPropertyChangedSignal('AbsolutePosition'):Connect(RecalculateListPosition);

        ListInner = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BorderSizePixel = 0;
            Size = UDim2.new(1, 0, 0, ListSizeY);
            ZIndex = 21;
            Parent = ListOuter;
        });

        Library:AddCorner(ListInner, Library.CornerRadius);
        Library:AddStroke(ListInner, 'OutlineColor');

        Library:AddToRegistry(ListInner, {
            BackgroundColor3 = 'MainColor';
        });

        local Scrolling = Library:Create('ScrollingFrame', {
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            CanvasSize = UDim2.new(0, 0, 0, 0);
            Position = UDim2.new(0, 0, 0, 4);
            Size = UDim2.new(1, 0, 1, -8);
            ZIndex = 21;
            Parent = ListInner;

            TopImage = 'rbxasset://textures/ui/Scroll/scroll-middle.png',
            BottomImage = 'rbxasset://textures/ui/Scroll/scroll-middle.png',

            ScrollBarThickness = 3,
            ScrollBarImageColor3 = Library.AccentColor,
        });

        Library:AddToRegistry(Scrolling, {
            ScrollBarImageColor3 = 'AccentColor'
        })

        Library:Create('UIListLayout', {
            Padding = UDim.new(0, 0);
            FillDirection = Enum.FillDirection.Vertical;
            SortOrder = Enum.SortOrder.LayoutOrder;
            Parent = Scrolling;
        });

        Library:Create('UIPadding', {
            PaddingLeft = UDim.new(0, 4);
            Parent = Scrolling;
        });

        function Dropdown:Display()
            local Values = Dropdown.Values;
            local Str = '';

            if Info.Multi then
                for Idx, Value in next, Values do
                    if Dropdown.Value[Value] then
                        Str = Str .. Value .. ', ';
                    end;
                end;

                Str = Str:sub(1, #Str - 2);
            else
                Str = Dropdown.Value or '';
            end;

            ItemList.Text = (Str == '' and '--' or Str);
        end;

        function Dropdown:GetActiveValues()
            if Info.Multi then
                local T = {};

                for Value, Bool in next, Dropdown.Value do
                    table.insert(T, Value);
                end;

                return T;
            else
                return Dropdown.Value and 1 or 0;
            end;
        end;

        function Dropdown:BuildDropdownList()
            local Values = Dropdown.Values;
            local Buttons = {};

            for _, Element in next, Scrolling:GetChildren() do
                if not Element:IsA('UIListLayout') then
                    Element:Destroy();
                end;
            end;

            local Count = 0;

            for Idx, Value in next, Values do
                local Table = {};

                Count = Count + 1;

                -- Transparent row; the hover wash is animated instead of a border.
                local Button = Library:Create('Frame', {
                    BackgroundColor3 = Library.AccentColor;
                    BackgroundTransparency = 1;
                    BorderSizePixel = 0;
                    Size = UDim2.new(1, -8, 0, ITEM_HEIGHT);
                    ZIndex = 23;
                    Active = true,
                    Parent = Scrolling;
                });

                Library:AddCorner(Button, Library.SmallCornerRadius);

                Library:AddToRegistry(Button, {
                    BackgroundColor3 = 'AccentColor';
                });

                -- Left accent bar marking the selected entry.
                local SelectedBar = Library:Create('Frame', {
                    AnchorPoint = Vector2.new(0, 0.5);
                    BackgroundColor3 = Library.AccentColor;
                    BorderSizePixel = 0;
                    Position = UDim2.new(0, 3, 0.5, 0);
                    Size = UDim2.new(0, 2, 0, 0);
                    ZIndex = 24;
                    Parent = Button;
                });

                Library:AddCorner(SelectedBar, Library.PillCornerRadius);

                Library:AddToRegistry(SelectedBar, {
                    BackgroundColor3 = 'AccentColor';
                });

                local ButtonLabel = Library:CreateLabel({
                    Active = false;
                    Size = UDim2.new(1, -12, 1, 0);
                    Position = UDim2.new(0, 10, 0, 0);
                    TextSize = Library.TextSize;
                    Text = Value;
                    TextXAlignment = Enum.TextXAlignment.Left;
                    TextTruncate = Enum.TextTruncate.AtEnd;
                    ZIndex = 25;
                    Parent = Button;
                });

                -- Manual hover wash: AddHoverWash ignores hovers over opened
                -- frames, and this row lives inside one.
                Button.MouseEnter:Connect(function()
                    Library:Tween(Button, { BackgroundTransparency = 0.9 }, Library.Animations.Fast);
                end);

                Button.MouseLeave:Connect(function()
                    Library:Tween(Button, { BackgroundTransparency = 1 }, Library.Animations.Normal);
                end);

                local Selected;

                if Info.Multi then
                    Selected = Dropdown.Value[Value];
                else
                    Selected = Dropdown.Value == Value;
                end;

                function Table:UpdateButton()
                    if Info.Multi then
                        Selected = Dropdown.Value[Value];
                    else
                        Selected = Dropdown.Value == Value;
                    end;

                    Library:Tween(ButtonLabel, {
                        TextColor3 = Selected and Library.AccentColor or Library.FontColor;
                    }, Library.Animations.Fast);

                    Library:Tween(SelectedBar, {
                        Size = Selected and UDim2.new(0, 2, 0, ITEM_HEIGHT - 8) or UDim2.new(0, 2, 0, 0);
                    }, Library.Animations.Normal);

                    ButtonLabel.Font = Selected and Library.FontHeavy or Library.Font;
                    Library.RegistryMap[ButtonLabel].Properties.TextColor3 = Selected and 'AccentColor' or 'FontColor';
                end;

                ButtonLabel.InputBegan:Connect(function(Input)
                    if Input.UserInputType == Enum.UserInputType.MouseButton1 then
                        local Try = not Selected;

                        if Dropdown:GetActiveValues() == 1 and (not Try) and (not Info.AllowNull) then
                        else
                            if Info.Multi then
                                Selected = Try;

                                if Selected then
                                    Dropdown.Value[Value] = true;
                                else
                                    Dropdown.Value[Value] = nil;
                                end;
                            else
                                Selected = Try;

                                if Selected then
                                    Dropdown.Value = Value;
                                else
                                    Dropdown.Value = nil;
                                end;

                                for _, OtherButton in next, Buttons do
                                    OtherButton:UpdateButton();
                                end;
                            end;

                            Table:UpdateButton();
                            Dropdown:Display();

                            Library:SafeCallback(Dropdown.Callback, Dropdown.Value);
                            Library:SafeCallback(Dropdown.Changed, Dropdown.Value);

                            Library:AttemptSave();
                        end;
                    end;
                end);

                Table:UpdateButton();
                Dropdown:Display();

                Buttons[Button] = Table;
            end;

            Scrolling.CanvasSize = UDim2.fromOffset(0, (Count * ITEM_HEIGHT) + 1);

            local Y = math.clamp(Count * ITEM_HEIGHT, 0, MAX_DROPDOWN_ITEMS * ITEM_HEIGHT) + 8;
            RecalculateListSize(Y);
        end;

        function Dropdown:SetValues(NewValues)
            if NewValues then
                Dropdown.Values = NewValues;
            end;

            Dropdown:BuildDropdownList();
        end;

        -- Animated open/close: the holder unrolls and the arrow rotates.
        function Dropdown:OpenDropdown()
            if Opened then return end;

            Opened = true;

            RecalculateListPosition();

            ListOuter.Visible = true;
            ListOuter.Size = UDim2.fromOffset(DropdownOuter.AbsoluteSize.X, 0);
            ListInner.BackgroundTransparency = 1;

            Library.OpenedFrames[ListOuter] = true;

            Library:Tween(ListOuter, { Size = UDim2.fromOffset(DropdownOuter.AbsoluteSize.X, ListSizeY) }, Library.Animations.Normal);
            Library:Tween(ListInner, { BackgroundTransparency = 0 }, Library.Animations.Fast);
            Library:Tween(DropdownArrow, { Rotation = 180 }, Library.Animations.Normal);
        end;

        function Dropdown:CloseDropdown()
            if (not Opened) then return end;

            Opened = false;
            Library.OpenedFrames[ListOuter] = nil;

            Library:Tween(DropdownArrow, { Rotation = 0 }, Library.Animations.Normal);
            Library:Tween(ListInner, { BackgroundTransparency = 1 }, Library.Animations.Normal);

            local Closing = Library:Tween(ListOuter, { Size = UDim2.fromOffset(DropdownOuter.AbsoluteSize.X, 0) }, Library.Animations.Fast);

            if Closing then
                Closing.Completed:Once(function()
                    if (not Opened) then
                        ListOuter.Visible = false;
                    end;
                end);
            else
                ListOuter.Visible = false;
            end;
        end;

        function Dropdown:OnChanged(Func)
            Dropdown.Changed = Func;
            Func(Dropdown.Value);
        end;

        function Dropdown:SetValue(Val)
            if Dropdown.Multi then
                local nTable = {};

                for Value, Bool in next, Val do
                    if table.find(Dropdown.Values, Value) then
                        nTable[Value] = true
                    end;
                end;

                Dropdown.Value = nTable;
            else
                if (not Val) then
                    Dropdown.Value = nil;
                elseif table.find(Dropdown.Values, Val) then
                    Dropdown.Value = Val;
                end;
            end;

            Dropdown:BuildDropdownList();

            Library:SafeCallback(Dropdown.Callback, Dropdown.Value);
            Library:SafeCallback(Dropdown.Changed, Dropdown.Value);
        end;

        DropdownOuter.InputBegan:Connect(function(Input)
            if Input.UserInputType == Enum.UserInputType.MouseButton1 and not Library:MouseIsOverOpenedFrame() then
                if Opened then
                    Dropdown:CloseDropdown();
                else
                    Dropdown:OpenDropdown();
                end;
            end;
        end);

        InputService.InputBegan:Connect(function(Input)
            if (not Opened) then return end;

            if Input.UserInputType == Enum.UserInputType.MouseButton1 then
                local AbsPos, AbsSize = ListOuter.AbsolutePosition, ListOuter.AbsoluteSize;

                if Mouse.X < AbsPos.X or Mouse.X > AbsPos.X + AbsSize.X
                    or Mouse.Y < (AbsPos.Y - DROPDOWN_HEIGHT - 5) or Mouse.Y > AbsPos.Y + AbsSize.Y then

                    Dropdown:CloseDropdown();
                end;
            end;
        end);

        Dropdown:BuildDropdownList();
        Dropdown:Display();

        local Defaults = {}

        if type(Info.Default) == 'string' then
            local Idx = table.find(Dropdown.Values, Info.Default)
            if Idx then
                table.insert(Defaults, Idx)
            end
        elseif type(Info.Default) == 'table' then
            for _, Value in next, Info.Default do
                local Idx = table.find(Dropdown.Values, Value)
                if Idx then
                    table.insert(Defaults, Idx)
                end
            end
        elseif type(Info.Default) == 'number' and Dropdown.Values[Info.Default] ~= nil then
            table.insert(Defaults, Info.Default)
        end

        if next(Defaults) then
            for i = 1, #Defaults do
                local Index = Defaults[i]
                if Info.Multi then
                    Dropdown.Value[Dropdown.Values[Index]] = true
                else
                    Dropdown.Value = Dropdown.Values[Index];
                end

                if (not Info.Multi) then break end
            end

            Dropdown:BuildDropdownList();
            Dropdown:Display();
        end

        Groupbox:AddBlank(Info.BlankSize or 5);
        Groupbox:Resize();

        Options[Idx] = Dropdown;

        return Dropdown;
    end;

    function Funcs:AddDependencyBox()
        local Depbox = {
            Dependencies = {};
        };
        
        local Groupbox = self;
        local Container = Groupbox.Container;

        local Holder = Library:Create('Frame', {
            BackgroundTransparency = 1;
            Size = UDim2.new(1, 0, 0, 0);
            Visible = false;
            Parent = Container;
        });

        local Frame = Library:Create('Frame', {
            BackgroundTransparency = 1;
            Size = UDim2.new(1, 0, 1, 0);
            Visible = true;
            Parent = Holder;
        });

        local Layout = Library:Create('UIListLayout', {
            FillDirection = Enum.FillDirection.Vertical;
            SortOrder = Enum.SortOrder.LayoutOrder;
            Parent = Frame;
        });

        function Depbox:Resize()
            Holder.Size = UDim2.new(1, 0, 0, Layout.AbsoluteContentSize.Y);
            Groupbox:Resize();
        end;

        Layout:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
            Depbox:Resize();
        end);

        Holder:GetPropertyChangedSignal('Visible'):Connect(function()
            Depbox:Resize();
        end);

        function Depbox:Update()
            for _, Dependency in next, Depbox.Dependencies do
                local Elem = Dependency[1];
                local Value = Dependency[2];

                if Elem.Type == 'Toggle' and Elem.Value ~= Value then
                    Holder.Visible = false;
                    Depbox:Resize();
                    return;
                end;
            end;

            Holder.Visible = true;
            Depbox:Resize();
        end;

        function Depbox:SetupDependencies(Dependencies)
            for _, Dependency in next, Dependencies do
                assert(type(Dependency) == 'table', 'SetupDependencies: Dependency is not of type `table`.');
                assert(Dependency[1], 'SetupDependencies: Dependency is missing element argument.');
                assert(Dependency[2] ~= nil, 'SetupDependencies: Dependency is missing value argument.');
            end;

            Depbox.Dependencies = Dependencies;
            Depbox:Update();
        end;

        Depbox.Container = Frame;

        setmetatable(Depbox, BaseGroupbox);

        table.insert(Library.DependencyBoxes, Depbox);

        return Depbox;
    end;

    BaseGroupbox.__index = Funcs;
    BaseGroupbox.__namecall = function(Table, Key, ...)
        return Funcs[Key](...);
    end;
end;

-- < Create other UI elements >
do
    Library.NotificationArea = Library:Create('Frame', {
        BackgroundTransparency = 1;
        Position = UDim2.new(0, 12, 0, 48);
        Size = UDim2.new(0, 320, 0, 400);
        ZIndex = 100;
        Parent = ScreenGui;
    });

    Library:Create('UIListLayout', {
        Padding = UDim.new(0, 8);
        FillDirection = Enum.FillDirection.Vertical;
        SortOrder = Enum.SortOrder.LayoutOrder;
        Parent = Library.NotificationArea;
    });

    -- < Watermark >
    local WatermarkOuter = Library:Create('Frame', {
        BackgroundTransparency = 1;
        BorderSizePixel = 0;
        Position = UDim2.new(0, 100, 0, -25);
        Size = UDim2.new(0, 213, 0, 26);
        ZIndex = 200;
        Visible = false;
        Parent = ScreenGui;
    });

    local WatermarkInner = Library:Create('Frame', {
        BackgroundColor3 = Library.MainColor;
        BorderSizePixel = 0;
        Size = UDim2.new(1, 0, 1, 0);
        ZIndex = 201;
        Parent = WatermarkOuter;
    });

    Library:AddCorner(WatermarkInner, Library.CornerRadius);
    Library:AddStroke(WatermarkInner, 'AccentColor', Library.StrokeThickness, 0.35);

    Library:AddToRegistry(WatermarkInner, {
        BackgroundColor3 = 'MainColor';
    });

    -- Small accent dot, replaces the old gradient bevel.
    local WatermarkDot = Library:Create('Frame', {
        AnchorPoint = Vector2.new(0, 0.5);
        BackgroundColor3 = Library.AccentColor;
        BorderSizePixel = 0;
        Position = UDim2.new(0, 9, 0.5, 0);
        Size = UDim2.new(0, 6, 0, 6);
        ZIndex = 202;
        Parent = WatermarkInner;
    });

    Library:AddCorner(WatermarkDot, Library.PillCornerRadius);

    Library:AddToRegistry(WatermarkDot, {
        BackgroundColor3 = 'AccentColor';
    });

    local WatermarkLabel = Library:CreateLabel({
        Position = UDim2.new(0, 21, 0, 0);
        Size = UDim2.new(1, -28, 1, 0);
        TextSize = Library.TextSize;
        Font = Library.FontHeavy;
        TextXAlignment = Enum.TextXAlignment.Left;
        ZIndex = 203;
        Parent = WatermarkInner;
    });

    Library.Watermark = WatermarkOuter;
    Library.WatermarkText = WatermarkLabel;
    Library:MakeDraggable(Library.Watermark);

    -- < Keybind list >
    local KeybindOuter = Library:Create('Frame', {
        AnchorPoint = Vector2.new(0, 0.5);
        BackgroundTransparency = 1;
        BorderSizePixel = 0;
        Position = UDim2.new(0, 12, 0.5, 0);
        Size = UDim2.new(0, 210, 0, 26);
        Visible = false;
        ZIndex = 100;
        Parent = ScreenGui;
    });

    local KeybindInner = Library:Create('Frame', {
        BackgroundColor3 = Library.MainColor;
        BorderSizePixel = 0;
        Size = UDim2.new(1, 0, 1, 0);
        ZIndex = 101;
        Parent = KeybindOuter;
    });

    Library:AddCorner(KeybindInner, Library.CornerRadius);
    Library:AddStroke(KeybindInner, 'OutlineColor');

    Library:AddToRegistry(KeybindInner, {
        BackgroundColor3 = 'MainColor';
    }, true);

    local ColorFrame = Library:Create('Frame', {
        AnchorPoint = Vector2.new(0, 0.5);
        BackgroundColor3 = Library.AccentColor;
        BorderSizePixel = 0;
        Position = UDim2.new(0, 9, 0, 13);
        Size = UDim2.new(0, 3, 0, 12);
        ZIndex = 102;
        Parent = KeybindInner;
    });

    Library:AddCorner(ColorFrame, Library.PillCornerRadius);

    Library:AddToRegistry(ColorFrame, {
        BackgroundColor3 = 'AccentColor';
    }, true);

    local KeybindLabel = Library:CreateLabel({
        Size = UDim2.new(1, -20, 0, 26);
        Position = UDim2.fromOffset(18, 0),
        TextXAlignment = Enum.TextXAlignment.Left,
        Font = Library.FontHeavy;

        Text = 'Keybinds';
        ZIndex = 104;
        Parent = KeybindInner;
    });

    local KeybindContainer = Library:Create('Frame', {
        BackgroundTransparency = 1;
        Size = UDim2.new(1, 0, 1, -26);
        Position = UDim2.new(0, 0, 0, 26);
        ZIndex = 1;
        Parent = KeybindInner;
    });

    Library:Create('UIListLayout', {
        Padding = UDim.new(0, 2);
        FillDirection = Enum.FillDirection.Vertical;
        SortOrder = Enum.SortOrder.LayoutOrder;
        Parent = KeybindContainer;
    });

    Library:Create('UIPadding', {
        PaddingLeft = UDim.new(0, 10),
        Parent = KeybindContainer,
    })

    Library.KeybindFrame = KeybindOuter;
    Library.KeybindContainer = KeybindContainer;
    Library:MakeDraggable(KeybindOuter);
end;

function Library:SetWatermarkVisibility(Bool)
    Library.Watermark.Visible = Bool;
end;

function Library:SetWatermark(Text)
    local X, Y = Library:GetTextBounds(Text, Library.FontHeavy, Library.TextSize);
    Library.Watermark.Size = UDim2.new(0, X + 34, 0, math.max(Y + 12, 26));
    Library:SetWatermarkVisibility(true)

    Library.WatermarkText.Text = Text;
end;

--[[
    Library:Notify(Text, Time)

    The original signature still works. As an OPTIONAL extra you may pass a
    table instead:
        Library:Notify({ Title = 'Titre', Description = 'Texte', Time = 4 })
]]
function Library:Notify(Text, Time)
    local Title, Description;

    if type(Text) == 'table' then
        Title = Text.Title;
        Description = Text.Description or Text.Text or '';
        Time = Text.Time or Time;
    else
        Description = tostring(Text);
    end;

    local MAX_WIDTH = 300;
    local TextWidth = select(1, Library:GetTextBounds(Description, Library.Font, Library.TextSize));
    local Width = math.clamp(TextWidth + 40, 170, MAX_WIDTH);

    local _, TextHeight = Library:GetTextBounds(Description, Library.Font, Library.TextSize);
    local Height = math.max(TextHeight + 20, 34) + (Title and 16 or 0);

    --[[
        NotifyOuter is placed by the UIListLayout, so it must keep its final
        size; the animation is played on the inner card instead.
    ]]
    local NotifyOuter = Library:Create('Frame', {
        BackgroundTransparency = 1;
        BorderSizePixel = 0;
        Size = UDim2.new(0, Width, 0, Height);
        ClipsDescendants = false;
        ZIndex = 100;
        Parent = Library.NotificationArea;
    });

    local NotifyCard = Library:Create('Frame', {
        BackgroundColor3 = Library.MainColor;
        BackgroundTransparency = 1;
        BorderSizePixel = 0;
        Position = UDim2.new(-1, 0, 0, 0);
        Size = UDim2.new(1, 0, 1, 0);
        ZIndex = 101;
        Parent = NotifyOuter;
    });

    Library:AddCorner(NotifyCard, Library.CornerRadius);
    local CardStroke = Library:AddStroke(NotifyCard, 'OutlineColor', Library.StrokeThickness, 1);

    Library:AddToRegistry(NotifyCard, {
        BackgroundColor3 = 'MainColor';
    }, true);

    -- Accent bar on the left edge.
    local LeftColor = Library:Create('Frame', {
        AnchorPoint = Vector2.new(0, 0.5);
        BackgroundColor3 = Library.AccentColor;
        BackgroundTransparency = 1;
        BorderSizePixel = 0;
        Position = UDim2.new(0, 6, 0.5, 0);
        Size = UDim2.new(0, 3, 1, -12);
        ZIndex = 104;
        Parent = NotifyCard;
    });

    Library:AddCorner(LeftColor, Library.PillCornerRadius);

    Library:AddToRegistry(LeftColor, {
        BackgroundColor3 = 'AccentColor';
    }, true);

    local TitleLabel;

    if Title then
        TitleLabel = Library:CreateLabel({
            Position = UDim2.new(0, 17, 0, 8);
            Size = UDim2.new(1, -25, 0, 16);
            Text = Title;
            Font = Library.FontHeavy;
            TextTransparency = 1;
            TextXAlignment = Enum.TextXAlignment.Left;
            TextSize = Library.TextSize;
            ZIndex = 103;
            Parent = NotifyCard;
        }, true);
    end;

    local NotifyLabel = Library:CreateLabel({
        Position = UDim2.new(0, 17, 0, Title and 24 or 0);
        Size = UDim2.new(1, -25, Title and 0 or 1, Title and Height - 32 or 0);
        Text = Description;
        TextTransparency = 1;
        TextWrapped = true;
        TextXAlignment = Enum.TextXAlignment.Left;
        TextYAlignment = Title and Enum.TextYAlignment.Top or Enum.TextYAlignment.Center;
        TextSize = Library.TextSize;
        ZIndex = 103;
        Parent = NotifyCard;
    }, true);

    -- Slide + fade in.
    Library:Tween(NotifyCard, { Position = UDim2.new(0, 0, 0, 0), BackgroundTransparency = 0 }, Library.Animations.Window);
    Library:Tween(CardStroke, { Transparency = 0 }, Library.Animations.Window);
    Library:Tween(LeftColor, { BackgroundTransparency = 0 }, Library.Animations.Window);
    Library:Tween(NotifyLabel, { TextTransparency = 0 }, Library.Animations.Window);

    if TitleLabel then
        Library:Tween(TitleLabel, { TextTransparency = 0 }, Library.Animations.Window);
    end;

    task.delay(Time or 5, function()
        if (not NotifyOuter.Parent) then return end;

        -- Slide + fade out, then clean up.
        Library:Tween(NotifyCard, { Position = UDim2.new(-1, 0, 0, 0), BackgroundTransparency = 1 }, Library.Animations.Window);
        Library:Tween(CardStroke, { Transparency = 1 }, Library.Animations.Window);
        Library:Tween(LeftColor, { BackgroundTransparency = 1 }, Library.Animations.Window);
        Library:Tween(NotifyLabel, { TextTransparency = 1 }, Library.Animations.Window);

        if TitleLabel then
            Library:Tween(TitleLabel, { TextTransparency = 1 }, Library.Animations.Window);
        end;

        task.wait(Library.Animations.Window + 0.05);

        NotifyOuter:Destroy();
    end);
end;

function Library:CreateWindow(...)
    local Arguments = { ... }
    local Config = { AnchorPoint = Vector2.zero }

    if type(...) == 'table' then
        Config = ...;
    else
        Config.Title = Arguments[1]
        Config.AutoShow = Arguments[2] or false;
    end

    if type(Config.Title) ~= 'string' then Config.Title = 'No title' end
    if type(Config.TabPadding) ~= 'number' then Config.TabPadding = 0 end
    if type(Config.MenuFadeTime) ~= 'number' then Config.MenuFadeTime = 0.2 end

    if typeof(Config.Position) ~= 'UDim2' then Config.Position = UDim2.fromOffset(175, 50) end
    if typeof(Config.Size) ~= 'UDim2' then Config.Size = UDim2.fromOffset(550, 600) end

    if Config.Center then
        Config.AnchorPoint = Vector2.new(0.5, 0.5)
        Config.Position = UDim2.fromScale(0.5, 0.5)
    end

    local Window = {
        Tabs = {};
    };

    --[[
        Modern window shell:
          Outer      -> transparent holder (still Window.Holder, still draggable)
          Elevation  -> soft dark halo behind the window (no risky shadow asset)
          Inner      -> rounded main surface (MainColor)
    ]]
    local Outer = Library:Create('Frame', {
        AnchorPoint = Config.AnchorPoint,
        BackgroundTransparency = 1;
        BorderSizePixel = 0;
        Position = Config.Position,
        Size = Config.Size,
        Visible = false;
        ZIndex = 1;
        Parent = ScreenGui;
    });

    local WindowScale = Library:AddScale(Outer, 1);

    Library:MakeDraggable(Outer, 36);

    local Elevation = Library:Create('Frame', {
        BackgroundColor3 = Color3.fromRGB(0, 0, 0);
        BackgroundTransparency = 0.72;
        BorderSizePixel = 0;
        Position = UDim2.new(0, -5, 0, -4);
        Size = UDim2.new(1, 10, 1, 12);
        ZIndex = 0;
        Parent = Outer;
    });

    Library:AddCorner(Elevation, UDim.new(0, 12));

    local Inner = Library:Create('Frame', {
        BackgroundColor3 = Library.MainColor;
        BorderSizePixel = 0;
        Position = UDim2.new(0, 0, 0, 0);
        Size = UDim2.new(1, 0, 1, 0);
        ZIndex = 1;
        Parent = Outer;
    });

    Library:AddCorner(Inner, UDim.new(0, 10));
    Library:AddStroke(Inner, 'OutlineColor');

    Library:AddToRegistry(Inner, {
        BackgroundColor3 = 'MainColor';
    });

    local TITLE_HEIGHT = 36;

    local WindowLabel = Library:CreateLabel({
        Position = UDim2.new(0, 14, 0, 0);
        Size = UDim2.new(1, -28, 0, TITLE_HEIGHT);
        Text = Config.Title or '';
        Font = Library.FontHeavy;
        TextSize = Library.TitleTextSize;
        TextXAlignment = Enum.TextXAlignment.Left;
        ZIndex = 2;
        Parent = Inner;
    });

    -- Accent dot next to the title.
    local TitleDot = Library:Create('Frame', {
        AnchorPoint = Vector2.new(0, 0.5);
        BackgroundColor3 = Library.AccentColor;
        BorderSizePixel = 0;
        Position = UDim2.new(1, -18, 0, TITLE_HEIGHT / 2);
        Size = UDim2.new(0, 8, 0, 8);
        ZIndex = 2;
        Parent = Inner;
    });

    Library:AddCorner(TitleDot, Library.PillCornerRadius);

    Library:AddToRegistry(TitleDot, {
        BackgroundColor3 = 'AccentColor';
    });

    -- Thin separator under the title bar.
    local TitleSeparator = Library:Create('Frame', {
        BackgroundColor3 = Library.OutlineColor;
        BorderSizePixel = 0;
        Position = UDim2.new(0, 0, 0, TITLE_HEIGHT);
        Size = UDim2.new(1, 0, 0, 1);
        ZIndex = 2;
        Parent = Inner;
    });

    Library:AddToRegistry(TitleSeparator, {
        BackgroundColor3 = 'OutlineColor';
    });

    -- Transparent wrapper kept for structural compatibility.
    local MainSectionOuter = Library:Create('Frame', {
        BackgroundTransparency = 1;
        BorderSizePixel = 0;
        Position = UDim2.new(0, 12, 0, TITLE_HEIGHT + 11);
        Size = UDim2.new(1, -24, 1, -(TITLE_HEIGHT + 23));
        ZIndex = 1;
        Parent = Inner;
    });

    -- Recessed content panel.
    local MainSectionInner = Library:Create('Frame', {
        BackgroundColor3 = Library.BackgroundColor;
        BorderSizePixel = 0;
        Position = UDim2.new(0, 0, 0, 0);
        Size = UDim2.new(1, 0, 1, 0);
        ZIndex = 1;
        Parent = MainSectionOuter;
    });

    Library:AddCorner(MainSectionInner, UDim.new(0, 8));
    Library:AddStroke(MainSectionInner, 'OutlineColor');

    Library:AddToRegistry(MainSectionInner, {
        BackgroundColor3 = 'BackgroundColor';
    });

    local TAB_HEIGHT = 28;

    -- Sliding accent pill behind the active tab button.
    local TabIndicator = Library:Create('Frame', {
        BackgroundColor3 = Library.AccentColor;
        BackgroundTransparency = 0.82;
        BorderSizePixel = 0;
        Position = UDim2.new(0, 10, 0, 10);
        Size = UDim2.new(0, 0, 0, TAB_HEIGHT);
        Visible = false;
        ZIndex = 0;
        Parent = MainSectionInner;
    });

    Library:AddCorner(TabIndicator, Library.CornerRadius);
    Library:AddStroke(TabIndicator, 'AccentColor', Library.StrokeThickness, 0.45);

    Library:AddToRegistry(TabIndicator, {
        BackgroundColor3 = 'AccentColor';
    });

    local TabArea = Library:Create('Frame', {
        BackgroundTransparency = 1;
        Position = UDim2.new(0, 10, 0, 10);
        Size = UDim2.new(1, -20, 0, TAB_HEIGHT);
        ZIndex = 1;
        Parent = MainSectionInner;
    });

    local TabListLayout = Library:Create('UIListLayout', {
        Padding = UDim.new(0, Config.TabPadding > 0 and Config.TabPadding or 6);
        FillDirection = Enum.FillDirection.Horizontal;
        VerticalAlignment = Enum.VerticalAlignment.Center;
        SortOrder = Enum.SortOrder.LayoutOrder;
        Parent = TabArea;
    });

    local ActiveTabButton;

    -- Moves the indicator under/behind the active tab button.
    local function UpdateTabIndicator(Instant)
        if (not ActiveTabButton) or (not ActiveTabButton.Parent) then
            TabIndicator.Visible = false;
            return;
        end;

        local Offset = ActiveTabButton.AbsolutePosition - MainSectionInner.AbsolutePosition;
        local TargetPosition = UDim2.fromOffset(Offset.X, Offset.Y);
        local TargetSize = UDim2.fromOffset(ActiveTabButton.AbsoluteSize.X, ActiveTabButton.AbsoluteSize.Y);

        TabIndicator.Visible = true;

        if Instant or TabIndicator.Size.X.Offset == 0 then
            TabIndicator.Position = TargetPosition;
            TabIndicator.Size = TargetSize;
        else
            Library:Tween(TabIndicator, { Position = TargetPosition, Size = TargetSize }, Library.Animations.Normal);
        end;
    end;

    TabListLayout:GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
        UpdateTabIndicator(true);
    end);

    MainSectionInner:GetPropertyChangedSignal('AbsolutePosition'):Connect(function()
        UpdateTabIndicator(true);
    end);

    local TabContainer = Library:Create('Frame', {
        BackgroundTransparency = 1;
        BorderSizePixel = 0;
        ClipsDescendants = true;
        Position = UDim2.new(0, 6, 0, TAB_HEIGHT + 16);
        Size = UDim2.new(1, -12, 1, -(TAB_HEIGHT + 22));
        ZIndex = 2;
        Parent = MainSectionInner;
    });

    -- CanvasGroup lets a whole tab fade with a single property (when available).
    local TabFrameClass = 'Frame';

    if pcall(function() return Instance.new('CanvasGroup'):Destroy() end) then
        TabFrameClass = 'CanvasGroup';
    end;

    function Window:SetWindowTitle(Title)
        WindowLabel.Text = Title;
    end;

    function Window:AddTab(Name)
        local Tab = {
            Groupboxes = {};
            Tabboxes = {};
        };

        local TabButtonWidth = Library:GetTextBounds(Name, Library.FontHeavy, Library.TextSize);

        -- Pill-shaped tab button; the accent background is the shared indicator.
        local TabButton = Library:Create('Frame', {
            BackgroundColor3 = Library.MainColor;
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            Size = UDim2.new(0, TabButtonWidth + 24, 1, 0);
            ZIndex = 1;
            Parent = TabArea;
        });

        Library:AddCorner(TabButton, Library.CornerRadius);

        Library:AddToRegistry(TabButton, {
            BackgroundColor3 = 'MainColor';
        });

        local TabButtonLabel = Library:CreateLabel({
            Position = UDim2.new(0, 0, 0, 0);
            Size = UDim2.new(1, 0, 1, 0);
            Text = Name;
            Font = Library.Font;
            TextTransparency = 0.35;
            ZIndex = 2;
            Parent = TabButton;
        });

        -- Hover feedback on inactive tabs.
        TabButton.MouseEnter:Connect(function()
            if ActiveTabButton == TabButton then return end;
            Library:Tween(TabButton, { BackgroundTransparency = 0.85 }, Library.Animations.Fast);
            Library:Tween(TabButtonLabel, { TextTransparency = 0.1 }, Library.Animations.Fast);
        end);

        TabButton.MouseLeave:Connect(function()
            if ActiveTabButton == TabButton then return end;
            Library:Tween(TabButton, { BackgroundTransparency = 1 }, Library.Animations.Normal);
            Library:Tween(TabButtonLabel, { TextTransparency = 0.35 }, Library.Animations.Normal);
        end);

        local TabFrameProperties = {
            Name = 'TabFrame',
            BackgroundTransparency = 1;
            Position = UDim2.new(0, 0, 0, 0);
            Size = UDim2.new(1, 0, 1, 0);
            Visible = false;
            ZIndex = 2;
            Parent = TabContainer;
        };

        if TabFrameClass == 'CanvasGroup' then
            TabFrameProperties.GroupTransparency = 0;
        end;

        local TabFrame = Library:Create(TabFrameClass, TabFrameProperties);

        local TabScale = Library:AddScale(TabFrame, 1);

        local LeftSide = Library:Create('ScrollingFrame', {
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            Position = UDim2.new(0, 4, 0, 4);
            Size = UDim2.new(0.5, -8, 1, -8);
            CanvasSize = UDim2.new(0, 0, 0, 0);
            BottomImage = '';
            TopImage = '';
            ScrollBarThickness = 0;
            ZIndex = 2;
            Parent = TabFrame;
        });

        local RightSide = Library:Create('ScrollingFrame', {
            BackgroundTransparency = 1;
            BorderSizePixel = 0;
            Position = UDim2.new(0.5, 4, 0, 4);
            Size = UDim2.new(0.5, -8, 1, -8);
            CanvasSize = UDim2.new(0, 0, 0, 0);
            BottomImage = '';
            TopImage = '';
            ScrollBarThickness = 0;
            ZIndex = 2;
            Parent = TabFrame;
        });

        Library:Create('UIListLayout', {
            Padding = UDim.new(0, 10);
            FillDirection = Enum.FillDirection.Vertical;
            SortOrder = Enum.SortOrder.LayoutOrder;
            HorizontalAlignment = Enum.HorizontalAlignment.Center;
            Parent = LeftSide;
        });

        Library:Create('UIListLayout', {
            Padding = UDim.new(0, 10);
            FillDirection = Enum.FillDirection.Vertical;
            SortOrder = Enum.SortOrder.LayoutOrder;
            HorizontalAlignment = Enum.HorizontalAlignment.Center;
            Parent = RightSide;
        });

        for _, Side in next, { LeftSide, RightSide } do
            Side:WaitForChild('UIListLayout'):GetPropertyChangedSignal('AbsoluteContentSize'):Connect(function()
                Side.CanvasSize = UDim2.fromOffset(0, Side.UIListLayout.AbsoluteContentSize.Y);
            end);
        end;

        --[[
            Tab transition: fade (CanvasGroup when available) combined with a
            short slide and a barely-visible scale pop. Fast and responsive.
        ]]
        function Tab:ShowTab()
            for _, OtherTab in next, Window.Tabs do
                OtherTab:HideTab();
            end;

            ActiveTabButton = TabButton;

            TabButton.BackgroundTransparency = 1;
            Library:Tween(TabButtonLabel, { TextTransparency = 0 }, Library.Animations.Fast);
            TabButtonLabel.Font = Library.FontHeavy;

            UpdateTabIndicator(false);

            local Duration = Library.Animations.TabDuration or Library.Animations.Normal;

            TabFrame.Visible = true;
            TabFrame.Position = UDim2.new(0, Library.Animations.TabSlide or 0, 0, 0);
            TabScale.Scale = Library.Animations.TabScale or 1;

            if TabFrameClass == 'CanvasGroup' and Library.Animations.TabFade then
                TabFrame.GroupTransparency = 1;
                Library:Tween(TabFrame, { GroupTransparency = 0 }, Duration);
            end;

            Library:Tween(TabFrame, { Position = UDim2.new(0, 0, 0, 0) }, Duration);
            Library:Tween(TabScale, { Scale = 1 }, Duration);
        end;

        function Tab:HideTab()
            Library:Tween(TabButton, { BackgroundTransparency = 1 }, Library.Animations.Fast);
            Library:Tween(TabButtonLabel, { TextTransparency = 0.35 }, Library.Animations.Fast);
            TabButtonLabel.Font = Library.Font;

            TabFrame.Visible = false;

            if TabFrameClass == 'CanvasGroup' then
                TabFrame.GroupTransparency = 0;
            end;
        end;

        function Tab:SetLayoutOrder(Position)
            TabButton.LayoutOrder = Position;
            TabListLayout:ApplyLayout();
        end;

        function Tab:AddGroupbox(Info)
            local Groupbox = {};

            local GROUPBOX_HEADER = 34;

            -- Transparent wrapper (kept so Resize() keeps driving the layout height).
            local BoxOuter = Library:Create('Frame', {
                BackgroundTransparency = 1;
                BorderSizePixel = 0;
                Size = UDim2.new(1, 0, 0, GROUPBOX_HEADER);
                ZIndex = 2;
                Parent = Info.Side == 1 and LeftSide or RightSide;
            });

            -- Raised card.
            local BoxInner = Library:Create('Frame', {
                BackgroundColor3 = Library.MainColor;
                BorderSizePixel = 0;
                Size = UDim2.new(1, 0, 1, 0);
                Position = UDim2.new(0, 0, 0, 0);
                ZIndex = 4;
                Parent = BoxOuter;
            });

            Library:AddCorner(BoxInner, Library.CornerRadius);
            Library:AddStroke(BoxInner, 'OutlineColor');

            Library:AddToRegistry(BoxInner, {
                BackgroundColor3 = 'MainColor';
            });

            -- Small accent bar in front of the groupbox title.
            local Highlight = Library:Create('Frame', {
                AnchorPoint = Vector2.new(0, 0.5);
                BackgroundColor3 = Library.AccentColor;
                BorderSizePixel = 0;
                Position = UDim2.new(0, 12, 0, GROUPBOX_HEADER / 2);
                Size = UDim2.new(0, 3, 0, 14);
                ZIndex = 5;
                Parent = BoxInner;
            });

            Library:AddCorner(Highlight, Library.PillCornerRadius);

            Library:AddToRegistry(Highlight, {
                BackgroundColor3 = 'AccentColor';
            });

            local GroupboxLabel = Library:CreateLabel({
                Size = UDim2.new(1, -34, 0, GROUPBOX_HEADER);
                Position = UDim2.new(0, 22, 0, 0);
                Font = Library.FontHeavy;
                TextSize = Library.TextSize;
                Text = Info.Name;
                TextTruncate = Enum.TextTruncate.AtEnd;
                TextXAlignment = Enum.TextXAlignment.Left;
                ZIndex = 5;
                Parent = BoxInner;
            });

            local Container = Library:Create('Frame', {
                BackgroundTransparency = 1;
                Position = UDim2.new(0, 12, 0, GROUPBOX_HEADER);
                Size = UDim2.new(1, -24, 1, -GROUPBOX_HEADER);
                ZIndex = 1;
                Parent = BoxInner;
            });

            Library:Create('UIListLayout', {
                FillDirection = Enum.FillDirection.Vertical;
                SortOrder = Enum.SortOrder.LayoutOrder;
                Parent = Container;
            });

            function Groupbox:Resize()
                local Size = 0;

                for _, Element in next, Groupbox.Container:GetChildren() do
                    if (not Element:IsA('UIListLayout')) and Element.Visible then
                        Size = Size + Element.Size.Y.Offset;
                    end;
                end;

                BoxOuter.Size = UDim2.new(1, 0, 0, GROUPBOX_HEADER + Size + 12);
            end;

            Groupbox.Container = Container;
            setmetatable(Groupbox, BaseGroupbox);

            Groupbox:AddBlank(3);
            Groupbox:Resize();

            Tab.Groupboxes[Info.Name] = Groupbox;

            return Groupbox;
        end;

        function Tab:AddLeftGroupbox(Name)
            return Tab:AddGroupbox({ Side = 1; Name = Name; });
        end;

        function Tab:AddRightGroupbox(Name)
            return Tab:AddGroupbox({ Side = 2; Name = Name; });
        end;

        function Tab:AddTabbox(Info)
            local Tabbox = {
                Tabs = {};
            };

            local TABBOX_HEADER = 42;

            local BoxOuter = Library:Create('Frame', {
                BackgroundTransparency = 1;
                BorderSizePixel = 0;
                Size = UDim2.new(1, 0, 0, TABBOX_HEADER);
                ZIndex = 2;
                Parent = Info.Side == 1 and LeftSide or RightSide;
            });

            local BoxInner = Library:Create('Frame', {
                BackgroundColor3 = Library.MainColor;
                BorderSizePixel = 0;
                Size = UDim2.new(1, 0, 1, 0);
                Position = UDim2.new(0, 0, 0, 0);
                ZIndex = 4;
                Parent = BoxOuter;
            });

            Library:AddCorner(BoxInner, Library.CornerRadius);
            Library:AddStroke(BoxInner, 'OutlineColor');

            Library:AddToRegistry(BoxInner, {
                BackgroundColor3 = 'MainColor';
            });

            -- Segmented control shell.
            local TabboxButtons = Library:Create('Frame', {
                BackgroundColor3 = Library.BackgroundColor;
                BorderSizePixel = 0;
                Position = UDim2.new(0, 8, 0, 8);
                Size = UDim2.new(1, -16, 0, 26);
                ZIndex = 5;
                Parent = BoxInner;
            });

            Library:AddCorner(TabboxButtons, Library.CornerRadius);
            Library:AddPadding(TabboxButtons, 3);

            Library:AddToRegistry(TabboxButtons, {
                BackgroundColor3 = 'BackgroundColor';
            });

            -- Thin accent line kept from the original design (rounded + inset).
            local Highlight = Library:Create('Frame', {
                BackgroundColor3 = Library.AccentColor;
                BackgroundTransparency = 0.55;
                BorderSizePixel = 0;
                Position = UDim2.new(0, 12, 0, TABBOX_HEADER - 3);
                Size = UDim2.new(1, -24, 0, 1);
                ZIndex = 10;
                Parent = BoxInner;
            });

            Library:AddToRegistry(Highlight, {
                BackgroundColor3 = 'AccentColor';
            });

            Library:Create('UIListLayout', {
                FillDirection = Enum.FillDirection.Horizontal;
                HorizontalAlignment = Enum.HorizontalAlignment.Left;
                SortOrder = Enum.SortOrder.LayoutOrder;
                Parent = TabboxButtons;
            });

            function Tabbox:AddTab(Name)
                local Tab = {};

                local Button = Library:Create('Frame', {
                    BackgroundColor3 = Library.MainColor;
                    BackgroundTransparency = 1;
                    BorderSizePixel = 0;
                    Size = UDim2.new(0.5, 0, 1, 0);
                    ZIndex = 6;
                    Parent = TabboxButtons;
                });

                Library:AddCorner(Button, Library.SmallCornerRadius);

                Library:AddToRegistry(Button, {
                    BackgroundColor3 = 'MainColor';
                });

                local ButtonLabel = Library:CreateLabel({
                    Size = UDim2.new(1, 0, 1, 0);
                    Font = Library.Font;
                    TextSize = Library.TextSize;
                    Text = Name;
                    TextTransparency = 0.4;
                    TextXAlignment = Enum.TextXAlignment.Center;
                    ZIndex = 7;
                    Parent = Button;
                });

                -- Legacy seam blocker; invisible with the rounded design but kept
                -- so the original show/hide behaviour stays intact.
                local Block = Library:Create('Frame', {
                    BackgroundColor3 = Library.BackgroundColor;
                    BackgroundTransparency = 1;
                    BorderSizePixel = 0;
                    Position = UDim2.new(0, 0, 1, 0);
                    Size = UDim2.new(1, 0, 0, 1);
                    Visible = false;
                    ZIndex = 9;
                    Parent = Button;
                });

                Library:AddToRegistry(Block, {
                    BackgroundColor3 = 'BackgroundColor';
                });

                local Container = Library:Create('Frame', {
                    BackgroundTransparency = 1;
                    Position = UDim2.new(0, 12, 0, TABBOX_HEADER);
                    Size = UDim2.new(1, -24, 1, -TABBOX_HEADER);
                    ZIndex = 1;
                    Visible = false;
                    Parent = BoxInner;
                });

                local ContainerScale = Library:AddScale(Container, 1);

                Library:Create('UIListLayout', {
                    FillDirection = Enum.FillDirection.Vertical;
                    SortOrder = Enum.SortOrder.LayoutOrder;
                    Parent = Container;
                });

                Button.MouseEnter:Connect(function()
                    if Container.Visible then return end;
                    Library:Tween(ButtonLabel, { TextTransparency = 0.12 }, Library.Animations.Fast);
                end);

                Button.MouseLeave:Connect(function()
                    if Container.Visible then return end;
                    Library:Tween(ButtonLabel, { TextTransparency = 0.4 }, Library.Animations.Normal);
                end);

                function Tab:Show()
                    for _, OtherTab in next, Tabbox.Tabs do
                        OtherTab:Hide();
                    end;

                    Container.Visible = true;
                    Block.Visible = true;

                    -- Animated active segment.
                    Library:Tween(Button, { BackgroundTransparency = 0 }, Library.Animations.Normal);
                    Library:Tween(ButtonLabel, { TextTransparency = 0 }, Library.Animations.Normal);
                    ButtonLabel.Font = Library.FontHeavy;

                    Button.BackgroundColor3 = Library.MainColor;
                    Library.RegistryMap[Button].Properties.BackgroundColor3 = 'MainColor';

                    -- Content fade-in.
                    ContainerScale.Scale = 0.99;
                    Library:Tween(ContainerScale, { Scale = 1 }, Library.Animations.TabDuration or Library.Animations.Normal);

                    Tab:Resize();
                end;

                function Tab:Hide()
                    Container.Visible = false;
                    Block.Visible = false;

                    Library:Tween(Button, { BackgroundTransparency = 1 }, Library.Animations.Fast);
                    Library:Tween(ButtonLabel, { TextTransparency = 0.4 }, Library.Animations.Fast);
                    ButtonLabel.Font = Library.Font;

                    Button.BackgroundColor3 = Library.MainColor;
                    Library.RegistryMap[Button].Properties.BackgroundColor3 = 'MainColor';
                end;

                function Tab:Resize()
                    local TabCount = 0;

                    for _, Tab in next, Tabbox.Tabs do
                        TabCount = TabCount + 1;
                    end;

                    for _, Button in next, TabboxButtons:GetChildren() do
                        if not Button:IsA('UIListLayout') then
                            Button.Size = UDim2.new(1 / TabCount, 0, 1, 0);
                        end;
                    end;

                    if (not Container.Visible) then
                        return;
                    end;

                    local Size = 0;

                    for _, Element in next, Tab.Container:GetChildren() do
                        if (not Element:IsA('UIListLayout')) and Element.Visible then
                            Size = Size + Element.Size.Y.Offset;
                        end;
                    end;

                    BoxOuter.Size = UDim2.new(1, 0, 0, TABBOX_HEADER + Size + 12);
                end;

                Button.InputBegan:Connect(function(Input)
                    if Input.UserInputType == Enum.UserInputType.MouseButton1 and not Library:MouseIsOverOpenedFrame() then
                        Tab:Show();
                        Tab:Resize();
                    end;
                end);

                Tab.Container = Container;
                Tabbox.Tabs[Name] = Tab;

                setmetatable(Tab, BaseGroupbox);

                Tab:AddBlank(3);
                Tab:Resize();

                -- Show first tab (number is 2 cus of the UIListLayout that also sits in that instance)
                if #TabboxButtons:GetChildren() == 2 then
                    Tab:Show();
                end;

                return Tab;
            end;

            Tab.Tabboxes[Info.Name or ''] = Tabbox;

            return Tabbox;
        end;

        function Tab:AddLeftTabbox(Name)
            return Tab:AddTabbox({ Name = Name, Side = 1; });
        end;

        function Tab:AddRightTabbox(Name)
            return Tab:AddTabbox({ Name = Name, Side = 2; });
        end;

        TabButton.InputBegan:Connect(function(Input)
            if Input.UserInputType == Enum.UserInputType.MouseButton1 then
                Tab:ShowTab();
            end;
        end);

        -- This was the first tab added, so we show it by default.
        if #TabContainer:GetChildren() == 1 then
            Tab:ShowTab();
        end;

        Window.Tabs[Name] = Tab;
        return Tab;
    end;

    local ModalElement = Library:Create('TextButton', {
        BackgroundTransparency = 1;
        Size = UDim2.new(0, 0, 0, 0);
        Visible = true;
        Text = '';
        Modal = false;
        Parent = ScreenGui;
    });

    local TransparencyCache = {};
    local Toggled = false;
    local Fading = false;

    function Library:Toggle()
        if Fading then
            return;
        end;

        local FadeTime = Config.MenuFadeTime;
        Fading = true;
        Toggled = (not Toggled);
        ModalElement.Modal = Toggled;

        --[[
            Window open / close motion: a short scale + vertical offset combined
            with the (original) transparency fade.
        ]]
        local BasePosition = Config.Position;

        if Toggled then
            -- A bit scuffed, but if we're going from not toggled -> toggled we want to show the frame immediately so that the fade is visible.
            Outer.Visible = true;

            BasePosition = UDim2.new(
                Outer.Position.X.Scale, Outer.Position.X.Offset,
                Outer.Position.Y.Scale, Outer.Position.Y.Offset
            );

            WindowScale.Scale = 0.96;
            Outer.Position = BasePosition + UDim2.fromOffset(0, 10);

            Library:Tween(WindowScale, { Scale = 1 }, Library.Animations.Window);
            Library:Tween(Outer, { Position = BasePosition }, Library.Animations.Window);

            -- Optional custom cursor (opt-out via Library.ShowCustomCursor = false).
            if Library.ShowCustomCursor and Drawing then
                task.spawn(function()
                    pcall(function()
                        local State = InputService.MouseIconEnabled;

                        local Cursor = Drawing.new('Triangle');
                        Cursor.Thickness = 1;
                        Cursor.Filled = true;
                        Cursor.Visible = true;

                        local CursorOutline = Drawing.new('Triangle');
                        CursorOutline.Thickness = 1;
                        CursorOutline.Filled = false;
                        CursorOutline.Color = Color3.new(0, 0, 0);
                        CursorOutline.Visible = true;

                        while Toggled and ScreenGui.Parent and Library.ShowCustomCursor do
                            InputService.MouseIconEnabled = false;

                            local mPos = InputService:GetMouseLocation();

                            Cursor.Color = Library.AccentColor;

                            Cursor.PointA = Vector2.new(mPos.X, mPos.Y);
                            Cursor.PointB = Vector2.new(mPos.X + 15, mPos.Y + 6);
                            Cursor.PointC = Vector2.new(mPos.X + 6, mPos.Y + 15);

                            CursorOutline.PointA = Cursor.PointA;
                            CursorOutline.PointB = Cursor.PointB;
                            CursorOutline.PointC = Cursor.PointC;

                            RenderStepped:Wait();
                        end;

                        InputService.MouseIconEnabled = State;

                        Cursor:Remove();
                        CursorOutline:Remove();
                    end);
                end);
            end;
        else
            Library:Tween(WindowScale, { Scale = 0.97 }, FadeTime);
        end;

        for _, Desc in next, Outer:GetDescendants() do
            local Properties = {};

            if Desc:IsA('ImageLabel') then
                table.insert(Properties, 'ImageTransparency');
                table.insert(Properties, 'BackgroundTransparency');
            elseif Desc:IsA('TextLabel') or Desc:IsA('TextBox') then
                table.insert(Properties, 'TextTransparency');
            elseif Desc:IsA('Frame') or Desc:IsA('ScrollingFrame') then
                table.insert(Properties, 'BackgroundTransparency');
            elseif Desc:IsA('UIStroke') then
                table.insert(Properties, 'Transparency');
            end;

            local Cache = TransparencyCache[Desc];

            if (not Cache) then
                Cache = {};
                TransparencyCache[Desc] = Cache;
            end;

            for _, Prop in next, Properties do
                if not Cache[Prop] then
                    Cache[Prop] = Desc[Prop];
                end;

                if Cache[Prop] == 1 then
                    continue;
                end;

                TweenService:Create(Desc, TweenInfo.new(FadeTime, Enum.EasingStyle.Linear), { [Prop] = Toggled and Cache[Prop] or 1 }):Play();
            end;
        end;

        task.wait(FadeTime);

        Outer.Visible = Toggled;

        if not Toggled then
            WindowScale.Scale = 1;
        end;

        Fading = false;
    end

    Library:GiveSignal(InputService.InputBegan:Connect(function(Input, Processed)
        if type(Library.ToggleKeybind) == 'table' and Library.ToggleKeybind.Type == 'KeyPicker' then
            if Input.UserInputType == Enum.UserInputType.Keyboard and Input.KeyCode.Name == Library.ToggleKeybind.Value then
                task.spawn(Library.Toggle)
            end
        elseif Input.KeyCode == Enum.KeyCode.RightControl or (Input.KeyCode == Enum.KeyCode.RightShift and (not Processed)) then
            task.spawn(Library.Toggle)
        end
    end))

    if Config.AutoShow then task.spawn(Library.Toggle) end

    Window.Holder = Outer;

    return Window;
end;

local function OnPlayerChange()
    local PlayerList = GetPlayersString();

    for _, Value in next, Options do
        if Value.Type == 'Dropdown' and Value.SpecialType == 'Player' then
            Value:SetValues(PlayerList);
        end;
    end;
end;

Players.PlayerAdded:Connect(OnPlayerChange);
Players.PlayerRemoving:Connect(OnPlayerChange);

getgenv().Library = Library
return Library