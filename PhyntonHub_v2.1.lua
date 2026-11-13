--[[
    PHYNTON HUB v2.1  |  Luau (Roblox)  |  Fluent UI  |  Mobile friendly
    Correções: abas vazias, PvP Combo, Movement melhorado, estabilidade
]]

local G = (getgenv and getgenv()) or _G
if G.PhyntonHubLoaded then return end
G.PhyntonHubLoaded = true

---------------------------------------------------------------------
-- SERVICES
---------------------------------------------------------------------
local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local Workspace         = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local UIS               = game:GetService("UserInputService")
local VIM               = game:GetService("VirtualInputManager")
local VirtualUser       = game:GetService("VirtualUser")

local lp  = Players.LocalPlayer
local cam = Workspace.CurrentCamera

---------------------------------------------------------------------
-- CORE
---------------------------------------------------------------------
local Phynton = {
    Flags = {}, Vals = {}, Tokens = {}, Registry = {}, Conns = {},
    Lang = "pt", Paused = false, SelfMoving = false,
}
local Config = {
    IconText = "PHY",
    EnemiesFolder = "Enemies",
}

local Sea = (game.PlaceId == 2753915549 and 1)
    or (game.PlaceId == 4442272183 and 2)
    or (game.PlaceId == 7449423635 and 3) or 3

local function S(pt, en) return { pt = pt, en = en } end
local function TX(s) return s[Phynton.Lang] or s.en end
local function reg(el, s) table.insert(Phynton.Registry, { el = el, s = s }) end
local function val(id, d) local v = Phynton.Vals[id]; if v == nil then return d end; return v end
local function flag(id) return Phynton.Flags[id] == true end

local function comm(...)
    local rem = ReplicatedStorage:FindFirstChild("Remotes")
    local c = rem and rem:FindFirstChild("CommF_")
    if not c then return nil end
    local args = table.pack(...)
    local ok, res = pcall(function() return c:InvokeServer(table.unpack(args, 1, args.n)) end)
    if ok then return res end
    return nil
end

---------------------------------------------------------------------
-- FLUENT UI
---------------------------------------------------------------------
local okLib, Fluent = pcall(function()
    return loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
end)
if not okLib or not Fluent then
    G.PhyntonHubLoaded = nil
    warn("[Phynton Hub] Falha ao carregar Fluent UI.")
    return
end

local Window = Fluent:CreateWindow({
    Title = "Phynton Hub",
    SubTitle = "v2.1 • mobile",
    TabWidth = 125,
    Size = UDim2.fromOffset(520, 350),
    Acrylic = false,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl,
})

local Tabs = {
    Settings = Window:AddTab({ Title = "Settings", Icon = "settings" }),
    FarmCfg  = Window:AddTab({ Title = "Farm Config", Icon = "sliders-horizontal" }),
    Farm     = Window:AddTab({ Title = "Farm", Icon = "trophy" }),
    Quests   = Window:AddTab({ Title = "Swords/Quests", Icon = "sword" }),
    Sea      = Window:AddTab({ Title = "Sea Events", Icon = "waves" }),
    Raid     = Window:AddTab({ Title = "Raid/Race V4", Icon = "zap" }),
    Shop     = Window:AddTab({ Title = "Shop", Icon = "shopping-cart" }),
    Movement = Window:AddTab({ Title = "Movement", Icon = "move" }),
    Combat   = Window:AddTab({ Title = "Combat", Icon = "swords" }),
}

---------------------------------------------------------------------
-- HELPERS DE UI
---------------------------------------------------------------------
local function notify(msg, dur)
    pcall(function() Fluent:Notify({ Title = "Phynton Hub", Content = msg, Duration = dur or 3 }) end)
end

local function startLoop(id, fn, waitFn)
    Phynton.Tokens[id] = (Phynton.Tokens[id] or 0) + 1
    local my = Phynton.Tokens[id]
    task.spawn(function()
        while G.PhyntonHubLoaded and Phynton.Flags[id] and Phynton.Tokens[id] == my do
            if not Phynton.Paused then pcall(fn) end
            local w = 0.1
            if waitFn then
                local ok, v = pcall(waitFn)
                if ok and v then w = v end
            end
            task.wait(w)
        end
    end)
end

local function addToggle(tab, id, s, default, cb)
    Phynton.Flags[id] = default or false
    local el = tab:AddToggle(id, { Title = TX(s), Default = default or false })
    reg(el, s)
    el:OnChanged(function(v)
        Phynton.Flags[id] = v
        if cb then task.spawn(function() pcall(cb, v) end) end
    end)
    return el
end

local function addLoopToggle(tab, id, s, fn, waitFn)
    return addToggle(tab, id, s, false, function(on)
        if on then startLoop(id, fn, waitFn) end
    end)
end

local function addSlider(tab, id, s, min, max, default, rounding, cb)
    Phynton.Vals[id] = default
    local el = tab:AddSlider(id, {
        Title = TX(s),
        Default = default,
        Min = min,
        Max = max,
        Rounding = rounding or 0
    })
    reg(el, s)
    el:OnChanged(function(v)
        Phynton.Vals[id] = v
        if cb then task.spawn(function() pcall(cb, v) end) end
    end)
    return el
end

local function addDropdown(tab, id, s, values, default, multi, cb)
    local el = tab:AddDropdown(id, {
        Title = TX(s),
        Values = values,
        Multi = multi or false,
        Default = (not multi) and default or nil
    })
    reg(el, s)
    Phynton.Vals[id] = default or {}
    if multi then pcall(function() el:SetValue(default or {}) end) end
    el:OnChanged(function(v)
        Phynton.Vals[id] = v
        if cb then task.spawn(function() pcall(cb, v) end) end
    end)
    return el
end

local function addInput(tab, id, s, default, placeholder)
    Phynton.Vals[id] = default or ""
    local el = tab:AddInput(id, {
        Title = TX(s),
        Default = default or "",
        Placeholder = placeholder or "",
        Numeric = false,
        Finished = false
    })
    reg(el, s)
    el:OnChanged(function(v) Phynton.Vals[id] = v end)
    return el
end

local function addButton(tab, s, cb)
    local el = tab:AddButton({
        Title = TX(s),
        Callback = function() task.spawn(function() pcall(cb) end) end
    })
    reg(el, s)
    return el
end

---------------------------------------------------------------------
-- HELPERS GERAIS
---------------------------------------------------------------------
local function getChar() return lp.Character end
local function getRoot() local c = getChar(); return c and c:FindFirstChild("HumanoidRootPart") end
local function getHum() local c = getChar(); return c and c:FindFirstChildOfClass("Humanoid") end
local function alive(h) return h ~= nil and h.Health > 0 end
local function partOf(m) return m and (m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")) end

local function humanWait()
    if Phynton.Flags.AntiBan then
        task.wait(math.random(1, 3))
    else
        task.wait(0.2)
    end
end

local function pressKey(key)
    pcall(function()
        VIM:SendKeyEvent(true, key, false, game)
        task.wait(0.05)
        VIM:SendKeyEvent(false, key, false, game)
    end)
end

local function click()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:Button1Down(Vector2.new(0, 0), cam.CFrame)
        task.wait(0.02)
        VirtualUser:Button1Up(Vector2.new(0, 0), cam.CFrame)
    end)
end

local function tweenTo(cf, speed)
    local r = getRoot()
    if not r then return end
    speed = speed or val("TweenSpeed", 250)
    local dist = (r.Position - cf.Position).Magnitude
    Phynton.SelfMoving = true
    local tw = TweenService:Create(r, TweenInfo.new(math.max(dist / speed, 0.05), Enum.EasingStyle.Linear), { CFrame = cf })
    tw:Play()
    pcall(function() tw.Completed:Wait() end)
    pcall(function() r.AssemblyLinearVelocity = Vector3.zero end)
    task.delay(0.3, function() Phynton.SelfMoving = false end)
end

local function matchName(n, f)
    if not f then return true end
    if type(f) == "table" then
        for _, p in ipairs(f) do
            if n:find(p, 1, true) then return true end
        end
        return false
    end
    return n:find(f, 1, true) ~= nil
end

local function enemyFolder()
    return Workspace:FindFirstChild(Config.EnemiesFolder) or Workspace
end

local function validEnemy(m)
    if not m or not m:IsA("Model") or m == getChar() then return false end
    if Players:GetPlayerFromCharacter(m) then return false end
    return alive(m:FindFirstChildOfClass("Humanoid")) and m:FindFirstChild("HumanoidRootPart") ~= nil
end

local function nearestEnemy(maxDist, nameFilter)
    local r = getRoot()
    if not r then return nil end
    local best, bd = nil, maxDist or math.huge
    for _, m in ipairs(enemyFolder():GetChildren()) do
        if validEnemy(m) and matchName(m.Name, nameFilter) then
            local d = (m.HumanoidRootPart.Position - r.Position).Magnitude
            if d < bd then
                best, bd = m, d
            end
        end
    end
    return best
end

local function goToSpawn(name)
    local wo = Workspace:FindFirstChild("_WorldOrigin")
    local es = wo and wo:FindFirstChild("EnemySpawns")
    if es then
        for _, s in ipairs(es:GetChildren()) do
            if matchName(s.Name, name) then
                tweenTo(s.CFrame * CFrame.new(0, 15, 0))
                return true
            end
        end
    end
    return false
end

local function lookAtTarget(pos)
    pcall(function()
        cam.CFrame = CFrame.lookAt(cam.CFrame.Position, pos)
    end)
end

---------------------------------------------------------------------
-- ARMAS / SKILLS
---------------------------------------------------------------------
local TIPS = { "Melee", "Sword", "Blox Fruit", "Gun" }
local rotIdx, rotAt = 0, 0

local function currentTip()
    local m = val("FarmWeapon", "Melee")
    if m ~= "Rotate" then return m end
    if os.clock() - rotAt > val("RotateTime", 4) then
        rotAt = os.clock()
        rotIdx = rotIdx % #TIPS + 1
    end
    return TIPS[math.max(rotIdx, 1)]
end

local function equipTip(tip)
    local char = getChar()
    local bp = lp:FindFirstChildOfClass("Backpack")
    if not (char and bp) then return nil end
    for _, t in ipairs(char:GetChildren()) do
        if t:IsA("Tool") and t.ToolTip == tip then return t end
    end
    for _, t in ipairs(bp:GetChildren()) do
        if t:IsA("Tool") and t.ToolTip == tip then
            local h = getHum()
            if h then h:EquipTool(t) end
            return t
        end
    end
end

local function heldTool()
    local c = getChar()
    return c and c:FindFirstChildOfClass("Tool")
end

local function skillReady(toolName, keyName)
    local ok, res = pcall(function()
        local f = lp.PlayerGui.Main.Skills[toolName][keyName]
        local cd = f:FindFirstChild("Cooldown")
        return (not cd) or cd.Size.X.Scale <= 0.01
    end)
    if ok then return res end
    return true
end

local function attack(target)
    local tip = currentTip()
    local tool = equipTip(tip)
    if tool then pcall(function() tool:Activate() end) end
    click()
    if flag("FarmSkills") and tool then
        local keys = val("Keys_" .. tip:gsub(" ", ""), {})
        local p = partOf(target)
        if p then lookAtTarget(p.Position) end
        for _, k in ipairs({ "Z", "X", "C", "V", "F" }) do
            if keys[k] and skillReady(tool.Name, k) then
                pressKey(Enum.KeyCode[k])
                task.wait(0.12)
            end
        end
    end
end

local function bringMobs(t)
    pcall(function() sethiddenproperty(lp, "SimulationRadius", math.huge) end)
    local tp = t.HumanoidRootPart.Position
    for _, m in ipairs(enemyFolder():GetChildren()) do
        if m ~= t and m.Name == t.Name and validEnemy(m) then
            local hrp = m.HumanoidRootPart
            if (hrp.Position - tp).Magnitude < 350 then
                pcall(function()
                    hrp.CFrame = t.HumanoidRootPart.CFrame
                    hrp.CanCollide = false
                    m.Humanoid.WalkSpeed = 0
                end)
            end
        end
    end
end

local function engage(t, flagId, maxTicks)
    local n = 0
    while G.PhyntonHubLoaded and Phynton.Flags[flagId] and validEnemy(t) and n < (maxTicks or 300) do
        if not Phynton.Paused then
            local r = getRoot()
            if r then
                Phynton.SelfMoving = true
                local h = val("FarmHeight", 10)
                r.CFrame = t.HumanoidRootPart.CFrame * CFrame.new(0, h, 0) * CFrame.Angles(math.rad(-90), 0, 0)
                r.AssemblyLinearVelocity = Vector3.zero
                if flag("BringMob") then bringMobs(t) end
                attack(t)
            end
        end
        n = n + 1
        task.wait(val("FastDelay", 0.08))
    end
    Phynton.SelfMoving = false
end

local function killNearest(flagId, nameFilter, maxDist)
    local t = nearestEnemy(maxDist or 3000, nameFilter)
    if not t then return false end
    tweenTo(t.HumanoidRootPart.CFrame * CFrame.new(0, val("FarmHeight", 10), 0))
    engage(t, flagId)
    return true
end

---------------------------------------------------------------------
-- ANTI-BAN / ANTI-AFK / NOCLIP
---------------------------------------------------------------------
task.spawn(function()
    local last
    while G.PhyntonHubLoaded do
        pcall(function()
            local r = getRoot()
            if r and Phynton.Flags.AntiBan then
                if last and not Phynton.SelfMoving and not Phynton.Paused and (r.Position - last).Magnitude > 120 then
                    Phynton.Paused = true
                    notify(TX(S("Teleporte detectado: pausando...", "Teleport detected: pausing...")))
                    task.delay(math.random(4, 8), function() Phynton.Paused = false end)
                end
                last = r.Position
            else
                last = nil
            end
        end)
        task.wait(0.25)
    end
end)

pcall(function()
    Phynton.Conns.AFK = lp.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end)

Phynton.Conns.Noclip = RunService.Stepped:Connect(function()
    pcall(function()
        if flag("Noclip") or Phynton.SelfMoving then
            local c = getChar()
            if c then
                for _, p in ipairs(c:GetChildren()) do
                    if p:IsA("BasePart") then p.CanCollide = false end
                end
            end
        end
    end)
end)

---------------------------------------------------------------------
-- ÍCONE FLUTUANTE
---------------------------------------------------------------------
local IconGui
do
    local ok = pcall(function()
        local parent = (gethui and gethui()) or game:GetService("CoreGui")
        IconGui = Instance.new("ScreenGui")
        IconGui.Name = "PhyntonIcon"
        IconGui.ResetOnSpawn = false
        IconGui.DisplayOrder = 999
        IconGui.IgnoreGuiInset = true
        IconGui.Parent = parent
    end)
    if not ok then
        IconGui = Instance.new("ScreenGui")
        IconGui.Name = "PhyntonIcon"
        IconGui.ResetOnSpawn = false
        IconGui.Parent = lp:WaitForChild("PlayerGui")
    end

    local btn = Instance.new("TextButton")
    btn.Name = "PHYButton"
    btn.Size = UDim2.fromOffset(54, 54)
    btn.Position = UDim2.new(0, 16, 0.35, 0)
    btn.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
    btn.AutoButtonColor = false
    btn.Text = Config.IconText
    btn.TextColor3 = Color3.fromRGB(170, 120, 255)
    btn.Font = Enum.Font.GothamBold
    btn.TextScaled = true
    btn.Parent = IconGui
    Instance.new("UICorner", btn).CornerRadius = UDim.new(1, 0)
    local stroke = Instance.new("UIStroke", btn)
    stroke.Color = Color3.fromRGB(150, 90, 255)
    stroke.Thickness = 2

    local dragging, moved, activeInput, dragStart, startPos = false, false, nil, nil, nil
    btn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            moved = false
            activeInput = input
            dragStart = input.Position
            startPos = btn.Position
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if not dragging then return end
        local isTouch = activeInput and activeInput.UserInputType == Enum.UserInputType.Touch
        if (isTouch and input == activeInput) or (not isTouch and input.UserInputType == Enum.UserInputType.MouseMovement) then
            local d = input.Position - dragStart
            if d.Magnitude > 8 then moved = true end
            if moved then
                btn.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end
        end
    end)
    UIS.InputEnded:Connect(function(input)
        if dragging and input == activeInput then
            dragging = false
            if not moved then
                pcall(function() Window:Minimize() end)
            end
        end
    end)
end

---------------------------------------------------------------------
-- TAB: SETTINGS
---------------------------------------------------------------------
do
    local scaleObj
    local function applyScale(v)
        if not scaleObj or not scaleObj.Parent then
            local target
            pcall(function() target = Fluent.Window and Fluent.Window.Root end)
            if not target then pcall(function() target = Fluent.GUI end) end
            if not target then return end
            scaleObj = target:FindFirstChild("PhyntonScale") or Instance.new("UIScale")
            scaleObj.Name = "PhyntonScale"
            scaleObj.Parent = target
        end
        scaleObj.Scale = v
    end
    addSlider(Tabs.Settings, "UIScale", S("Escala da GUI", "GUI Scale"), 0.5, 1.5, 1, 2, applyScale)

    local dd = Tabs.Settings:AddDropdown("Lang", {
        Title = "Idioma / Language",
        Values = { "Português", "English" },
        Multi = false,
        Default = 1
    })
    dd:OnChanged(function(v)
        Phynton.Lang = (v == "English") and "en" or "pt"
        for _, item in ipairs(Phynton.Registry) do
            pcall(function() item.el:SetTitle(TX(item.s)) end)
        end
    end)

    addToggle(Tabs.Settings, "ShowIcon", S("Ícone flutuante PHY", "Floating PHY icon"), true, function(on)
        if IconGui then IconGui.Enabled = on end
    end)
    addToggle(Tabs.Settings, "AntiBan", S("Anti-Ban", "Anti-Ban"), true)
    addSlider(Tabs.Settings, "TweenSpeed", S("Velocidade do tween", "Tween speed"), 100, 400, 250, 0)
    addToggle(Tabs.Settings, "Noclip", S("Noclip", "Noclip"), false)
end

---------------------------------------------------------------------
-- TAB: FARM CONFIG
---------------------------------------------------------------------
do
    addDropdown(Tabs.FarmCfg, "FarmWeapon", S("Usar no farm", "Use for farming"),
        { "Melee", "Sword", "Blox Fruit", "Gun", "Rotate" }, "Melee", false)
    addSlider(Tabs.FarmCfg, "RotateTime", S("Trocar arma a cada (s)", "Switch weapon every (s)"), 2, 15, 4, 0)
    addSlider(Tabs.FarmCfg, "FarmHeight", S("Altura sobre o inimigo", "Height above enemy"), 5, 30, 10, 0)
    addSlider(Tabs.FarmCfg, "FastDelay", S("Delay do ataque (s)", "Attack delay (s)"), 0.02, 0.5, 0.08, 2)
    addToggle(Tabs.FarmCfg, "BringMob", S("Bring Mob", "Bring Mob"), false)
    addToggle(Tabs.FarmCfg, "FarmSkills", S("Usar skills no farm", "Use skills while farming"), true)

    Tabs.FarmCfg:AddParagraph({
        Title = "Skills por tipo",
        Content = "Escolha as teclas de cada arma"
    })
    addDropdown(Tabs.FarmCfg, "Keys_Melee", S("Teclas Melee", "Melee Keys"), { "Z", "X", "C", "V", "F" }, { Z = true, X = true }, true)
    addDropdown(Tabs.FarmCfg, "Keys_Sword", S("Teclas Espada", "Sword Keys"), { "Z", "X", "C", "V", "F" }, { Z = true, X = true }, true)
    addDropdown(Tabs.FarmCfg, "Keys_BloxFruit", S("Teclas Fruta", "Fruit Keys"), { "Z", "X", "C", "V", "F" }, { Z = true, X = true, C = true }, true)
    addDropdown(Tabs.FarmCfg, "Keys_Gun", S("Teclas Gun", "Gun Keys"), { "Z", "X", "C", "V", "F" }, { Z = true }, true)

    addLoopToggle(Tabs.FarmCfg, "AutoHaki", S("Auto Haki (Buso)", "Auto Haki"), function()
        local c = getChar()
        if c and not c:FindFirstChild("HasBuso") then
            comm("Buso")
        end
    end, function() return 3 end)

    addDropdown(Tabs.FarmCfg, "StatList", S("Auto Stats", "Auto Stats"),
        { "Melee", "Defense", "Sword", "Gun", "Demon Fruit" }, { Melee = true, Defense = true }, true)
    addLoopToggle(Tabs.FarmCfg, "AutoStats", S("Auto Stats", "Auto Stats"), function()
        for stat, on in pairs(val("StatList", {})) do
            if on then comm("AddPoint", stat, 3) end
        end
    end, function() return 5 end)
end

---------------------------------------------------------------------
-- TAB: FARM
---------------------------------------------------------------------
do
    Tabs.Farm:AddSection("Farm Principal")
    addLoopToggle(Tabs.Farm, "FarmLevel", S("Auto Farm Level", "Auto Farm Level"), function()
        local t = nearestEnemy(3000)
        if t then
            tweenTo(t.HumanoidRootPart.CFrame * CFrame.new(0, val("FarmHeight", 10), 0))
            engage(t, "FarmLevel")
        else
            humanWait()
        end
    end, function() return 0.3 end)

    addInput(Tabs.Farm, "BossName", S("Nome do Boss", "Boss name"), "", "ex: Greybeard")
    addLoopToggle(Tabs.Farm, "FarmBoss", S("Auto Farm Boss", "Auto Farm Boss"), function()
        local name = val("BossName", "")
        if name == "" then return end
        if not killNearest("FarmBoss", name) then
            goToSpawn(name)
            humanWait()
        end
    end, function() return 0.3 end)

    Tabs.Farm:AddSection("Itens")
    addLoopToggle(Tabs.Farm, "AutoChest", S("Auto Chest", "Auto Chest"), function()
        local r = getRoot()
        if not r then return end
        local list = CollectionService:GetTagged("_ChestTagged")
        local best, bd = nil, math.huge
        for _, c in ipairs(list) do
            local p = c:IsA("Model") and c:GetPivot().Position or c.Position
            local d = (p - r.Position).Magnitude
            if d < bd then
                best, bd = c, d
            end
        end
        if best then
            tweenTo(best:IsA("Model") and best:GetPivot() or best.CFrame)
        end
        humanWait()
    end, function() return 0.4 end)

    addLoopToggle(Tabs.Farm, "CollectFruit", S("Auto Collect Fruit", "Auto Collect Fruit"), function()
        for _, d in ipairs(Workspace:GetChildren()) do
            if (d:IsA("Tool") or d:IsA("Model")) and d.Name:find("Fruit", 1, true) then
                local h = d:FindFirstChild("Handle") or partOf(d)
                if h then
                    tweenTo(h.CFrame)
                    humanWait()
                end
            end
        end
    end, function() return 1.5 end)
end

---------------------------------------------------------------------
-- TAB: SWORDS / QUESTS
---------------------------------------------------------------------
do
    Tabs.Quests:AddSection("Elite / Yama")
    addLoopToggle(Tabs.Quests, "EliteHunter", S("Auto Elite Hunter", "Auto Elite Hunter"), function()
        if not killNearest("EliteHunter", {"Diablo", "Deandre", "Urban"}) then
            for _, n in ipairs({"Diablo", "Deandre", "Urban"}) do
                if goToSpawn(n) then break end
            end
        end
    end, function() return 0.5 end)

    Tabs.Quests:AddSection("Outros")
    addLoopToggle(Tabs.Quests, "AutoDojo", S("Auto Dojo (beta)", "Auto Dojo (beta)"), function()
        local npcs = Workspace:FindFirstChild("NPCs")
        local trainer = npcs and (npcs:FindFirstChild("Dojo Trainer") or npcs:FindFirstChild("Dojo"))
        if trainer then
            local p = partOf(trainer)
            if p then tweenTo(p.CFrame * CFrame.new(0, 0, 4)) end
            for _, d in ipairs(trainer:GetDescendants()) do
                if d:IsA("ProximityPrompt") then
                    pcall(fireproximityprompt, d)
                elseif d:IsA("ClickDetector") then
                    pcall(fireclickdetector, d)
                end
            end
        end
        humanWait()
        killNearest("AutoDojo", nil, 400)
    end, function() return 1 end)
end

---------------------------------------------------------------------
-- TAB: SEA EVENTS
---------------------------------------------------------------------
do
    addDropdown(Tabs.Sea, "SeaSel", S("Eventos", "Events"),
        { "Terrorshark", "Piranha", "Sea Beast", "Leviathan", "Ghost Ship" },
        { Terrorshark = true, ["Sea Beast"] = true }, true)

    addSlider(Tabs.Sea, "SeaHeight", S("Altura sobre o alvo", "Height above target"), 15, 80, 35, 0)

    addLoopToggle(Tabs.Sea, "SeaFarm", S("Auto Farm Sea Events", "Auto Farm Sea Events"), function()
        local t = nearestEnemy(4000, {"Terrorshark", "SeaBeast", "Leviathan", "GhostShip", "Piranha"})
        if t then
            local r = getRoot()
            if r then
                Phynton.SelfMoving = true
                r.CFrame = t.HumanoidRootPart.CFrame * CFrame.new(0, val("SeaHeight", 35), 0) * CFrame.Angles(math.rad(-90), 0, 0)
                attack(t)
            end
        end
    end, function() return 0.4 end)
end

---------------------------------------------------------------------
-- TAB: RAID / RACE V4
---------------------------------------------------------------------
do
    Tabs.Raid:AddSection("Raid")
    addDropdown(Tabs.Raid, "RaidChip", S("Raid", "Raid"),
        { "Flame", "Ice", "Quake", "Light", "Dark", "Spider", "Rumble", "Magma", "Buddha", "Sand", "Phoenix", "Dough" }, "Flame", false)

    addLoopToggle(Tabs.Raid, "AutoRaid", S("Auto Raid", "Auto Raid"), function()
        local main = lp.PlayerGui:FindFirstChild("Main")
        local timer = main and main:FindFirstChild("Timer")
        if timer and timer.Visible then
            killNearest("AutoRaid", nil, 1500)
        else
            comm("RaidsNpc", "Select", val("RaidChip", "Flame"))
            humanWait()
        end
    end, function() return 0.5 end)

    Tabs.Raid:AddSection("Race V4")
    addLoopToggle(Tabs.Raid, "RaceV4", S("Auto Race V4 Trials", "Auto Race V4 Trials"), function()
        if killNearest("RaceV4", nil, 400) then
            pressKey(Enum.KeyCode.V)
        else
            humanWait()
        end
    end, function() return 0.3 end)
end

---------------------------------------------------------------------
-- TAB: SHOP
---------------------------------------------------------------------
do
    local ShopItems = {
        ["Buso Haki"] = { "BuyHaki", "Buso" },
        ["Geppo"] = { "BuyHaki", "Geppo" },
        ["Soru"] = { "BuyHaki", "Soru" },
        ["Ken"] = { "KenTalk", "Buy" },
        ["Superhuman"] = { "BuySuperhuman" },
        ["Death Step"] = { "BuyDeathStep" },
        ["Godhuman"] = { "BuyGodhuman" },
    }
    local names = {}
    for k in pairs(ShopItems) do table.insert(names, k) end
    table.sort(names)

    addDropdown(Tabs.Shop, "ShopItem", S("Item da loja", "Shop item"), names, names[1], false)
    addButton(Tabs.Shop, S("Comprar item", "Buy item"), function()
        local a = ShopItems[val("ShopItem", names[1])]
        if a then
            comm(table.unpack(a))
            notify("Comprado: " .. val("ShopItem", ""))
        end
    end)
end

---------------------------------------------------------------------
-- TAB: MOVEMENT
---------------------------------------------------------------------
do
    local angle = 0
    addSlider(Tabs.Movement, "OrbitDist", S("Distância da órbita", "Orbit distance"), 5, 40, 15, 0)
    addSlider(Tabs.Movement, "OrbitSpeed", S("Velocidade da órbita", "Orbit speed"), 1, 10, 3, 1)
    addToggle(Tabs.Movement, "Orbit", S("Órbita no alvo", "Orbit target"), false, function(on)
        if Phynton.Conns.Orbit then
            Phynton.Conns.Orbit:Disconnect()
            Phynton.Conns.Orbit = nil
        end
        if not on then return end
        Phynton.Conns.Orbit = RunService.Heartbeat:Connect(function(dt)
            pcall(function()
                if Phynton.Paused then return end
                local r = getRoot()
                if not r then return end
                local t = nearestEnemy(300)
                if not t then return end
                local tp = t.HumanoidRootPart.Position
                angle = angle + val("OrbitSpeed", 3) * dt
                local d = val("OrbitDist", 15)
                Phynton.SelfMoving = true
                r.CFrame = CFrame.new(tp + Vector3.new(math.cos(angle) * d, 3, math.sin(angle) * d), tp)
                r.AssemblyLinearVelocity = Vector3.zero
            end)
        end)
    end)

    local bv, ap, att, targetY
    local function cleanupFly()
        if Phynton.Conns.Fly then
            Phynton.Conns.Fly:Disconnect()
            Phynton.Conns.Fly = nil
        end
        for _, o in ipairs({ bv, ap, att }) do
            if o then pcall(function() o:Destroy() end) end
        end
        bv, ap, att = nil, nil, nil
    end
    addSlider(Tabs.Movement, "FlySpeed", S("Velocidade do voo", "Fly speed"), 20, 200, 80, 0)
    addButton(Tabs.Movement, S("Voo: subir", "Fly: up"), function()
        if targetY then targetY = targetY + 12 end
    end)
    addButton(Tabs.Movement, S("Voo: descer", "Fly: down"), function()
        if targetY then targetY = targetY - 12 end
    end)
    addToggle(Tabs.Movement, "Fly", S("Voar (Fly)", "Fly"), false, function(on)
        cleanupFly()
        if not on then return end
        local r = getRoot()
        if not (r and getHum()) then return end
        targetY = r.Position.Y
        att = Instance.new("Attachment")
        att.Parent = r
        bv = Instance.new("BodyVelocity")
        bv.MaxForce = Vector3.new(1e6, 0, 1e6)
        bv.Velocity = Vector3.zero
        bv.Parent = r
        ap = Instance.new("AlignPosition")
        ap.Mode = Enum.PositionAlignmentMode.OneAttachment
        ap.Attachment0 = att
        ap.ForceLimitMode = Enum.ForceLimitMode.PerAxis
        ap.MaxAxesForce = Vector3.new(0, 1e6, 0)
        ap.Responsiveness = 40
        ap.Position = r.Position
        ap.Parent = r
        Phynton.Conns.Fly = RunService.Heartbeat:Connect(function()
            pcall(function()
                local rr, hh = getRoot(), getHum()
                if not (rr and hh and bv and ap) then return end
                local spd = val("FlySpeed", 80)
                bv.Velocity = Vector3.new(hh.MoveDirection.X * spd, 0, hh.MoveDirection.Z * spd)
                ap.Position = Vector3.new(rr.Position.X, targetY, rr.Position.Z)
            end)
        end)
    end)

    addSlider(Tabs.Movement, "MobGap", S("Mobility intervalo (s)", "Mobility gap (s)"), 0.2, 3, 0.8, 1)
    local lastPress = { X = 0, Z = 0 }
    addLoopToggle(Tabs.Movement, "Mobility", S("Auto Mobility (X/Z)", "Auto Mobility (X/Z)"), function()
        local tool = heldTool()
        if not tool then return end
        for name, code in pairs({ X = Enum.KeyCode.X, Z = Enum.KeyCode.Z }) do
            if os.clock() - lastPress[name] >= val("MobGap", 0.8) and skillReady(tool.Name, name) then
                pressKey(code)
                lastPress[name] = os.clock()
                task.wait(0.15)
            end
        end
    end, function() return 0.1 end)

    addLoopToggle(Tabs.Movement, "FastAttack", S("Fast Attack", "Fast Attack"), function()
        local tool = equipTip(currentTip())
        if not tool then return end
        pcall(function() tool:Activate() end)
        click()
    end, function() return val("FastDelay", 0.08) end)
end

---------------------------------------------------------------------
-- TAB: COMBAT + PvP COMBO
---------------------------------------------------------------------
do
    local function teamOK(plr)
        if not flag("AimTeam") then return true end
        return not (plr.Team and lp.Team and plr.Team == lp.Team)
    end

    local function candidates()
        local list = {}
        local mode = val("AimMode", "Both")
        if mode == "Players" or mode == "Both" then
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= lp and p.Character and teamOK(p) then
                    local h = p.Character:FindFirstChildOfClass("Humanoid")
                    local hrp = p.Character:FindFirstChild("HumanoidRootPart")
                    if alive(h) and hrp then
                        table.insert(list, hrp)
                    end
                end
            end
        end
        if mode == "NPCs" or mode == "Both" then
            for _, m in ipairs(enemyFolder():GetChildren()) do
                if validEnemy(m) then
                    table.insert(list, m.HumanoidRootPart)
                end
            end
        end
        return list
    end

    local function pick()
        local best, bd = nil, val("AimFov", 250)
        local vp = cam.ViewportSize / 2
        for _, hrp in ipairs(candidates()) do
            local sp, on = cam:WorldToViewportPoint(hrp.Position)
            if on then
                local d = (Vector2.new(sp.X, sp.Y) - vp).Magnitude
                if d < bd then
                    best, bd = hrp, d
                end
            end
        end
        return best
    end

    addDropdown(Tabs.Combat, "AimMode", S("Alvos do Aimbot", "Aimbot targets"), { "Players", "NPCs", "Both" }, "Both", false)
    addToggle(Tabs.Combat, "AimTeam", S("Team Check", "Team Check"), true)
    addSlider(Tabs.Combat, "AimPredict", S("Predição", "Prediction"), 0, 0.5, 0.12, 2)
    addSlider(Tabs.Combat, "AimSmooth", S("Suavidade", "Smoothness"), 0.05, 1, 0.3, 2)
    addSlider(Tabs.Combat, "AimFov", S("Raio do FOV", "FOV radius"), 50, 600, 250, 0)

    addToggle(Tabs.Combat, "Aimbot", S("Aimbot", "Aimbot"), false, function(on)
        if Phynton.Conns.Aim then
            Phynton.Conns.Aim:Disconnect()
            Phynton.Conns.Aim = nil
        end
        if not on then return end
        Phynton.Conns.Aim = RunService.RenderStepped:Connect(function()
            pcall(function()
                if Phynton.Paused then return end
                local t = pick()
                if not t then return end
                local aimPos = t.Position + t.AssemblyLinearVelocity * val("AimPredict", 0.12)
                cam.CFrame = cam.CFrame:Lerp(CFrame.new(cam.CFrame.Position, aimPos), val("AimSmooth", 0.3))
            end)
        end)
    end)

    -- PvP Auto Combo
    local lastHealth = 100
    local lastComboTime = 0
    addToggle(Tabs.Combat, "PvPCombo", S("PvP Auto Combo (quando atacado)", "PvP Auto Combo (when attacked)"), false, function(on)
        if Phynton.Conns.PvP then
            Phynton.Conns.PvP:Disconnect()
            Phynton.Conns.PvP = nil
        end
        if not on then return end

        Phynton.Conns.PvP = RunService.Heartbeat:Connect(function()
            pcall(function()
                local h = getHum()
                if not h then return end
                if h.Health < lastHealth - 4 and os.clock() - lastComboTime > 1.2 then
                    lastComboTime = os.clock()
                    for _, k in ipairs({"Z", "X", "C", "V"}) do
                        pressKey(Enum.KeyCode[k])
                        task.wait(0.13)
                    end
                    click()
                    task.wait(0.1)
                    click()
                end
                lastHealth = h.Health
            end)
        end)
    end)

    local lastDodge = 0
    addSlider(Tabs.Combat, "DodgeRange", S("Alcance de detecção", "Detection range"), 20, 120, 60, 0)
    addLoopToggle(Tabs.Combat, "Dodge", S("Dodge System", "Dodge System"), function()
        local r = getRoot()
        if not r or os.clock() - lastDodge < 0.6 then return end
        local params = OverlapParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { getChar() }
        for _, p in ipairs(Workspace:GetPartBoundsInRadius(r.Position, val("DodgeRange", 60), params)) do
            if not p.Anchored and p.AssemblyLinearVelocity.Magnitude > 30 then
                local toMe = r.Position - p.Position
                if p.AssemblyLinearVelocity.Unit:Dot(toMe.Unit) > 0.85 then
                    local side = (math.random() > 0.5) and 1 or -1
                    Phynton.SelfMoving = true
                    r.CFrame = r.CFrame + p.AssemblyLinearVelocity.Unit:Cross(Vector3.yAxis).Unit * side * 12
                    task.delay(0.3, function() Phynton.SelfMoving = false end)
                    lastDodge = os.clock()
                    return
                end
            end
        end
    end, function() return 0.08 end)

    addDropdown(Tabs.Combat, "SkillKeys", S("Auto Skills: teclas", "Auto Skills keys"), { "Z", "X", "C", "V" }, { Z = true, X = true }, true)
    addSlider(Tabs.Combat, "SkillGap", S("Intervalo entre skills", "Skill gap"), 0.2, 3, 0.6, 1)
    addLoopToggle(Tabs.Combat, "AutoSkills", S("Auto Skills", "Auto Skills"), function()
        local r = getRoot()
        if not r then return end
        local t = nearestEnemy(120)
        if not t then return end
        local tp = t.HumanoidRootPart.Position
        r.CFrame = CFrame.lookAt(r.Position, Vector3.new(tp.X, r.Position.Y, tp.Z))
        local tool = heldTool()
        local sel = val("SkillKeys", {})
        for _, k in ipairs({ "Z", "X", "C", "V" }) do
            if sel[k] and (not tool or skillReady(tool.Name, k)) then
                pressKey(Enum.KeyCode[k])
                task.wait(val("SkillGap", 0.6))
            end
        end
    end, function() return 0.1 end)
end

---------------------------------------------------------------------
-- FINALIZAÇÃO
---------------------------------------------------------------------
lp.CharacterAdded:Connect(function()
    Phynton.SelfMoving = false
end)

Window:SelectTab(1)
notify(TX(S("Phynton Hub v2.1 carregado! Toque no ícone PHY para minimizar.", "Phynton Hub v2.1 loaded!")), 5)
