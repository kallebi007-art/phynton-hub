--[[
    PHYNTON HUB LITE  |  Performance Edition
    Leve + Pegar Itens/Espadas + Missões (quando possível)
]]

local G = (getgenv and getgenv()) or _G
if G.PhyntonHubLoaded then return end
G.PhyntonHubLoaded = true

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local Workspace         = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VIM               = game:GetService("VirtualInputManager")
local VirtualUser       = game:GetService("VirtualUser")
local TeleportService   = game:GetService("TeleportService")

local lp  = Players.LocalPlayer
local cam = Workspace.CurrentCamera

local Phynton = {
    Flags = {}, Vals = {}, Tokens = {},
    Paused = false, SelfMoving = false,
}

local function val(id, d)
    local v = Phynton.Vals[id]
    return v == nil and d or v
end
local function flag(id) return Phynton.Flags[id] == true end

local function comm(...)
    local rem = ReplicatedStorage:FindFirstChild("Remotes")
    local c = rem and rem:FindFirstChild("CommF_")
    if not c then return end
    pcall(function() c:InvokeServer(...) end)
end

local ok, Fluent = pcall(function()
    return loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
end)
if not ok or not Fluent then
    G.PhyntonHubLoaded = nil
    return warn("[Phynton Lite] Fluent falhou")
end

local Window = Fluent:CreateWindow({
    Title = "Phynton Lite",
    SubTitle = "performance",
    TabWidth = 110,
    Size = UDim2.fromOffset(460, 310),
    Acrylic = false,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl,
})

local Tabs = {
    Main     = Window:AddTab({ Title = "Main", Icon = "home" }),
    Farm     = Window:AddTab({ Title = "Farm", Icon = "trophy" }),
    Items    = Window:AddTab({ Title = "Items", Icon = "box" }),
    Combat   = Window:AddTab({ Title = "Combat", Icon = "swords" }),
    Movement = Window:AddTab({ Title = "Move", Icon = "move" }),
    Extra    = Window:AddTab({ Title = "Extra", Icon = "settings" }),
}

local function notify(msg)
    pcall(function() Fluent:Notify({ Title = "Phynton", Content = msg, Duration = 2.5 }) end)
end

local function startLoop(id, fn, waitTime)
    Phynton.Tokens[id] = (Phynton.Tokens[id] or 0) + 1
    local my = Phynton.Tokens[id]
    task.spawn(function()
        while G.PhyntonHubLoaded and Phynton.Flags[id] and Phynton.Tokens[id] == my do
            if not Phynton.Paused then pcall(fn) end
            task.wait(waitTime or 0.15)
        end
    end)
end

local function addToggle(tab, id, title, default, cb)
    Phynton.Flags[id] = default or false
    local el = tab:AddToggle(id, { Title = title, Default = default or false })
    el:OnChanged(function(v)
        Phynton.Flags[id] = v
        if cb then task.spawn(function() pcall(cb, v) end) end
    end)
end

local function addSlider(tab, id, title, min, max, default)
    Phynton.Vals[id] = default
    local el = tab:AddSlider(id, { Title = title, Default = default, Min = min, Max = max, Rounding = 1 })
    el:OnChanged(function(v) Phynton.Vals[id] = v end)
end

local function addButton(tab, title, cb)
    tab:AddButton({ Title = title, Callback = function() task.spawn(function() pcall(cb) end) end })
end

local function getRoot()
    local c = lp.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function getHum()
    local c = lp.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

local function click()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:Button1Down(Vector2.new(), cam.CFrame)
        task.wait(0.03)
        VirtualUser:Button1Up(Vector2.new(), cam.CFrame)
    end)
end

local function pressKey(key)
    pcall(function()
        VIM:SendKeyEvent(true, key, false, game)
        task.wait(0.04)
        VIM:SendKeyEvent(false, key, false, game)
    end)
end

local function tweenTo(pos)
    local r = getRoot()
    if not r then return end
    Phynton.SelfMoving = true
    local speed = val("TweenSpeed", 280)
    local dist = (r.Position - pos).Magnitude
    local tw = TweenService:Create(r, TweenInfo.new(math.max(dist / speed, 0.08), Enum.EasingStyle.Linear), {
        CFrame = CFrame.new(pos)
    })
    tw:Play()
    pcall(function() tw.Completed:Wait() end)
    pcall(function() r.AssemblyLinearVelocity = Vector3.zero end)
    task.delay(0.2, function() Phynton.SelfMoving = false end)
end

local function nearestEnemy(maxDist, nameFilter)
    local r = getRoot()
    if not r then return nil end
    local folder = Workspace:FindFirstChild("Enemies") or Workspace
    local best, bd = nil, maxDist or 2000
    for _, m in ipairs(folder:GetChildren()) do
        if m:IsA("Model") and m ~= lp.Character then
            local h = m:FindFirstChildOfClass("Humanoid")
            local hrp = m:FindFirstChild("HumanoidRootPart")
            if h and h.Health > 0 and hrp and not Players:GetPlayerFromCharacter(m) then
                if not nameFilter or m.Name:find(nameFilter, 1, true) then
                    local d = (hrp.Position - r.Position).Magnitude
                    if d < bd then best, bd = m, d end
                end
            end
        end
    end
    return best
end

local function equipAny()
    local char = lp.Character
    local bp = lp:FindFirstChildOfClass("Backpack")
    if not (char and bp) then return end
    for _, t in ipairs(char:GetChildren()) do
        if t:IsA("Tool") then return t end
    end
    for _, t in ipairs(bp:GetChildren()) do
        if t:IsA("Tool") then
            local h = getHum()
            if h then h:EquipTool(t) end
            return t
        end
    end
end

local function simpleAttack()
    equipAny()
    click()
    if flag("UseSkills") then
        pressKey(Enum.KeyCode.Z)
        task.wait(0.1)
        pressKey(Enum.KeyCode.X)
    end
end

local function engage(target, flagId)
    local ticks = 0
    while G.PhyntonHubLoaded and flag(flagId) and target and target.Parent and ticks < 250 do
        local h = target:FindFirstChildOfClass("Humanoid")
        local hrp = target:FindFirstChild("HumanoidRootPart")
        if not (h and h.Health > 0 and hrp) then break end

        local myH = getHum()
        if flag("LowHPFlee") and myH and myH.Health / myH.MaxHealth < (val("FleeHP", 30) / 100) then
            local r = getRoot()
            if r then r.CFrame = r.CFrame + Vector3.new(0, 60, 0) end
            break
        end

        local r = getRoot()
        if r then
            Phynton.SelfMoving = true
            r.CFrame = hrp.CFrame * CFrame.new(0, val("Height", 9), 0) * CFrame.Angles(math.rad(-90), 0, 0)
            r.AssemblyLinearVelocity = Vector3.zero
            simpleAttack()
        end
        ticks = ticks + 1
        task.wait(val("AtkDelay", 0.1))
    end
    Phynton.SelfMoving = false
end

-- Anti AFK
pcall(function()
    lp.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end)

-- Noclip
RunService.Stepped:Connect(function()
    if flag("Noclip") or Phynton.SelfMoving then
        local c = lp.Character
        if c then
            for _, p in ipairs(c:GetChildren()) do
                if p:IsA("BasePart") then p.CanCollide = false end
            end
        end
    end
end)

---------------------------------------------------------------------
-- MAIN
---------------------------------------------------------------------
do
    addToggle(Tabs.Main, "AntiBan", "Anti-Ban", true)
    addToggle(Tabs.Main, "Noclip", "Noclip", false)
    addToggle(Tabs.Main, "LowHPFlee", "Fugir com pouca vida", true)
    addSlider(Tabs.Main, "FleeHP", "% vida para fugir", 15, 50, 30)
    addSlider(Tabs.Main, "TweenSpeed", "Velocidade Tween", 150, 400, 280)
    addSlider(Tabs.Main, "Height", "Altura no inimigo", 5, 20, 9)
    addSlider(Tabs.Main, "AtkDelay", "Delay ataque", 0.05, 0.3, 0.1)
end

---------------------------------------------------------------------
-- FARM
---------------------------------------------------------------------
do
    addToggle(Tabs.Farm, "UseSkills", "Usar skills no farm", true)

    addToggle(Tabs.Farm, "FarmLevel", "Auto Farm Level", false, function(on)
        if not on then return end
        startLoop("FarmLevel", function()
            local t = nearestEnemy(2500)
            if t then
                local hrp = t:FindFirstChild("HumanoidRootPart")
                if hrp then
                    tweenTo(hrp.Position + Vector3.new(0, val("Height", 9), 0))
                    engage(t, "FarmLevel")
                end
            else
                task.wait(0.4)
            end
        end, 0.25)
    end)

    addToggle(Tabs.Farm, "FarmBoss", "Auto Farm Boss", false, function(on)
        if not on then return end
        startLoop("FarmBoss", function()
            local name = val("BossName", "")
            if name == "" then return end
            local t = nearestEnemy(3000, name)
            if t then
                local hrp = t:FindFirstChild("HumanoidRootPart")
                if hrp then
                    tweenTo(hrp.Position + Vector3.new(0, val("Height", 9), 0))
                    engage(t, "FarmBoss")
                end
            else
                task.wait(0.5)
            end
        end, 0.3)
    end)

    Tabs.Farm:AddInput("BossName", {
        Title = "Nome do Boss",
        Default = "",
        Placeholder = "Greybeard / Darkbeard..."
    })
    task.spawn(function()
        while G.PhyntonHubLoaded do
            pcall(function()
                local opt = Fluent.Options and Fluent.Options.BossName
                if opt and opt.Value then Phynton.Vals.BossName = opt.Value end
            end)
            task.wait(1)
        end
    end)

    addToggle(Tabs.Farm, "FarmBone", "Farm Bone", false, function(on)
        if not on then return end
        startLoop("FarmBone", function()
            local t = nearestEnemy(2500, "Skeleton") or nearestEnemy(2500, "Zombie") or nearestEnemy(2500, "Soul")
            if t then
                local hrp = t:FindFirstChild("HumanoidRootPart")
                if hrp then
                    tweenTo(hrp.Position + Vector3.new(0, val("Height", 9), 0))
                    engage(t, "FarmBone")
                end
            else
                task.wait(0.5)
            end
        end, 0.3)
    end)

    addToggle(Tabs.Farm, "AutoChest", "Auto Chest", false, function(on)
        if not on then return end
        startLoop("AutoChest", function()
            local r = getRoot()
            if not r then return end
            local best, bd = nil, 9999
            for _, d in ipairs(Workspace:GetDescendants()) do
                if d:IsA("BasePart") and d.Name:lower():find("chest") then
                    local dist = (d.Position - r.Position).Magnitude
                    if dist < bd and dist < 800 then
                        best, bd = d, dist
                    end
                end
            end
            if best then
                tweenTo(best.Position + Vector3.new(0, 3, 0))
            end
        end, 0.6)
    end)
end

---------------------------------------------------------------------
-- ITEMS / MISSÕES (leve)
---------------------------------------------------------------------
do
    -- Pegar itens / espadas no chão
    addToggle(Tabs.Items, "PickItems", "Pegar Itens / Espadas", false, function(on)
        if not on then return end
        startLoop("PickItems", function()
            local r = getRoot()
            if not r then return end
            for _, d in ipairs(Workspace:GetChildren()) do
                if d:IsA("Tool") then
                    local handle = d:FindFirstChild("Handle")
                    if handle then
                        local dist = (handle.Position - r.Position).Magnitude
                        if dist < 400 then
                            tweenTo(handle.Position)
                            task.wait(0.3)
                            return
                        end
                    end
                end
            end
            -- também procura modelos de espada
            for _, d in ipairs(Workspace:GetDescendants()) do
                if d:IsA("BasePart") and (d.Name:find("Sword") or d.Name:find("Blade") or d.Name:find("Katana")) then
                    local dist = (d.Position - r.Position).Magnitude
                    if dist < 300 then
                        tweenTo(d.Position + Vector3.new(0, 2, 0))
                        task.wait(0.3)
                        return
                    end
                end
            end
        end, 1.2)
    end)

    -- Missões (só se o remote existir / for possível)
    addToggle(Tabs.Items, "AutoQuest", "Auto Missão (se possível)", false, function(on)
        if not on then return end
        startLoop("AutoQuest", function()
            -- tenta iniciar quest genérica (best-effort)
            local ok = pcall(function()
                comm("StartQuest")
            end)
            -- se tiver quest ativa, farm normal
            local t = nearestEnemy(2000)
            if t then
                local hrp = t:FindFirstChild("HumanoidRootPart")
                if hrp then
                    tweenTo(hrp.Position + Vector3.new(0, val("Height", 9), 0))
                    engage(t, "AutoQuest")
                end
            else
                task.wait(0.6)
            end
        end, 0.4)
    end)

    addButton(Tabs.Items, "Tentar pegar item perto", function()
        local r = getRoot()
        if not r then return notify("Sem personagem") end
        for _, d in ipairs(Workspace:GetChildren()) do
            if d:IsA("Tool") then
                local handle = d:FindFirstChild("Handle")
                if handle and (handle.Position - r.Position).Magnitude < 500 then
                    tweenTo(handle.Position)
                    notify("Indo pegar: " .. d.Name)
                    return
                end
            end
        end
        notify("Nenhum item perto")
    end)
end

---------------------------------------------------------------------
-- COMBAT
---------------------------------------------------------------------
do
    addToggle(Tabs.Combat, "Aimbot", "Aimbot (Players)", false, function(on)
        if Phynton.Tokens.Aim then Phynton.Tokens.Aim = Phynton.Tokens.Aim + 1 end
        if not on then return end
        local my = (Phynton.Tokens.Aim or 0) + 1
        Phynton.Tokens.Aim = my
        task.spawn(function()
            while G.PhyntonHubLoaded and flag("Aimbot") and Phynton.Tokens.Aim == my do
                pcall(function()
                    local best, bd = nil, val("FOV", 250)
                    local center = cam.ViewportSize / 2
                    for _, p in ipairs(Players:GetPlayers()) do
                        if p ~= lp and p.Character then
                            local hrp = p.Character:FindFirstChild("HumanoidRootPart")
                            local h = p.Character:FindFirstChildOfClass("Humanoid")
                            if hrp and h and h.Health > 0 then
                                local sp, onScreen = cam:WorldToViewportPoint(hrp.Position)
                                if onScreen then
                                    local d = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                                    if d < bd then best, bd = hrp, d end
                                end
                            end
                        end
                    end
                    if best then
                        cam.CFrame = cam.CFrame:Lerp(CFrame.new(cam.CFrame.Position, best.Position), 0.35)
                    end
                end)
                task.wait(0.03)
            end
        end)
    end)
    addSlider(Tabs.Combat, "FOV", "FOV Aimbot", 80, 400, 250)

    local lastHP, lastCombo = 100, 0
    addToggle(Tabs.Combat, "PvPCombo", "PvP Combo (quando atacado)", false, function(on)
        if Phynton.Tokens.PvP then Phynton.Tokens.PvP = Phynton.Tokens.PvP + 1 end
        if not on then return end
        local my = (Phynton.Tokens.PvP or 0) + 1
        Phynton.Tokens.PvP = my
        task.spawn(function()
            while G.PhyntonHubLoaded and flag("PvPCombo") and Phynton.Tokens.PvP == my do
                pcall(function()
                    local h = getHum()
                    if h then
                        if h.Health < lastHP - 5 and os.clock() - lastCombo > 1.4 then
                            lastCombo = os.clock()
                            pressKey(Enum.KeyCode.Z)
                            task.wait(0.12)
                            pressKey(Enum.KeyCode.X)
                            task.wait(0.12)
                            pressKey(Enum.KeyCode.C)
                            click()
                        end
                        lastHP = h.Health
                    end
                end)
                task.wait(0.1)
            end
        end)
    end)

    addToggle(Tabs.Combat, "AutoSkills", "Auto Skills", false, function(on)
        if not on then return end
        startLoop("AutoSkills", function()
            local t = nearestEnemy(100)
            if not t then return end
            pressKey(Enum.KeyCode.Z)
            task.wait(0.15)
            pressKey(Enum.KeyCode.X)
        end, 0.4)
    end)
end

---------------------------------------------------------------------
-- MOVEMENT
---------------------------------------------------------------------
do
    addToggle(Tabs.Movement, "Fly", "Fly", false, function(on)
        if Phynton.Conns and Phynton.Conns.Fly then
            pcall(function() Phynton.Conns.Fly:Disconnect() end)
            Phynton.Conns.Fly = nil
        end
        if not on then return end
        Phynton.Conns = Phynton.Conns or {}
        local bv = Instance.new("BodyVelocity")
        bv.MaxForce = Vector3.new(1e5, 0, 1e5)
        bv.Velocity = Vector3.zero
        local r = getRoot()
        if r then bv.Parent = r end

        Phynton.Conns.Fly = RunService.Heartbeat:Connect(function()
            pcall(function()
                local rr = getRoot()
                local hh = getHum()
                if not (rr and hh and bv and bv.Parent) then return end
                if bv.Parent ~= rr then bv.Parent = rr end
                local spd = val("FlySpeed", 70)
                bv.Velocity = Vector3.new(hh.MoveDirection.X * spd, 0, hh.MoveDirection.Z * spd)
            end)
        end)
    end)
    addSlider(Tabs.Movement, "FlySpeed", "Velocidade Fly", 30, 150, 70)

    addToggle(Tabs.Movement, "Mobility", "Auto Mobility (X/Z)", false, function(on)
        if not on then return end
        startLoop("Mobility", function()
            pressKey(Enum.KeyCode.X)
            task.wait(0.3)
            pressKey(Enum.KeyCode.Z)
        end, 0.8)
    end)

    addToggle(Tabs.Movement, "FastAttack", "Fast Attack", false, function(on)
        if not on then return end
        startLoop("FastAttack", function()
            equipAny()
            click()
        end, val("AtkDelay", 0.1))
    end)
end

---------------------------------------------------------------------
-- EXTRA
---------------------------------------------------------------------
do
    addButton(Tabs.Extra, "Server Hop", function()
        notify("Trocando de servidor...")
        pcall(function() TeleportService:Teleport(game.PlaceId, lp) end)
    end)

    addButton(Tabs.Extra, "Info do Servidor", function()
        notify(string.format("Players: %d/%d", #Players:GetPlayers(), Players.MaxPlayers))
    end)

    addToggle(Tabs.Extra, "AutoHaki", "Auto Haki", false, function(on)
        if not on then return end
        startLoop("AutoHaki", function()
            local c = lp.Character
            if c and not c:FindFirstChild("HasBuso") then
                comm("Buso")
            end
        end, 4)
    end)

    addToggle(Tabs.Extra, "StoreFruit", "Guardar Frutas", false, function(on)
        if not on then return end
        startLoop("StoreFruit", function()
            local bp = lp:FindFirstChildOfClass("Backpack")
            if not bp then return end
            for _, t in ipairs(bp:GetChildren()) do
                if t:IsA("Tool") and t.Name:find("Fruit") then
                    pcall(function()
                        comm("StoreFruit", t:GetAttribute("OriginalName") or t.Name, t)
                    end)
                end
            end
        end, 5)
    end)
end

---------------------------------------------------------------------
Window:SelectTab(1)
notify("Phynton Lite carregado")
