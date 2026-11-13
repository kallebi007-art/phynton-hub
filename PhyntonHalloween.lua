--[[
    PHYNTON HUB - HALLOWEEN EVENT
    Versão leve só para farmar o evento de Halloween (Hollowin)
]]

local G = (getgenv and getgenv()) or _G
if G.PhyntonHalloween then return end
G.PhyntonHalloween = true

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local Workspace         = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VIM               = game:GetService("VirtualInputManager")
local VirtualUser       = game:GetService("VirtualUser")

local lp  = Players.LocalPlayer
local cam = Workspace.CurrentCamera

local Flags, Vals, Tokens = {}, {}, {}
local Paused, SelfMoving = false, false

local function val(id, d) return Vals[id] == nil and d or Vals[id] end
local function flag(id) return Flags[id] == true end

local function comm(...)
    local rem = ReplicatedStorage:FindFirstChild("Remotes")
    local c = rem and rem:FindFirstChild("CommF_")
    if c then pcall(function() c:InvokeServer(...) end) end
end

local ok, Fluent = pcall(function()
    return loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
end)
if not ok or not Fluent then
    G.PhyntonHalloween = nil
    return warn("[Halloween] Fluent falhou")
end

local Window = Fluent:CreateWindow({
    Title = "Phynton Halloween",
    SubTitle = "event farm",
    TabWidth = 120,
    Size = UDim2.fromOffset(440, 290),
    Acrylic = false,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl,
})

local Tabs = {
    Farm   = Window:AddTab({ Title = "Farm", Icon = "skull" }),
    Items  = Window:AddTab({ Title = "Items", Icon = "candy" }),
    Config = Window:AddTab({ Title = "Config", Icon = "settings" }),
}

local function notify(msg)
    pcall(function() Fluent:Notify({ Title = "Halloween", Content = msg, Duration = 2.5 }) end)
end

local function startLoop(id, fn, waitTime)
    Tokens[id] = (Tokens[id] or 0) + 1
    local my = Tokens[id]
    task.spawn(function()
        while G.PhyntonHalloween and Flags[id] and Tokens[id] == my do
            if not Paused then pcall(fn) end
            task.wait(waitTime or 0.2)
        end
    end)
end

local function addToggle(tab, id, title, default, cb)
    Flags[id] = default or false
    local el = tab:AddToggle(id, { Title = title, Default = default or false })
    el:OnChanged(function(v)
        Flags[id] = v
        if cb then task.spawn(function() pcall(cb, v) end) end
    end)
end

local function addSlider(tab, id, title, min, max, default)
    Vals[id] = default
    local el = tab:AddSlider(id, { Title = title, Default = default, Min = min, Max = max, Rounding = 0 })
    el:OnChanged(function(v) Vals[id] = v end)
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
    SelfMoving = true
    local speed = val("Speed", 280)
    local dist = (r.Position - pos).Magnitude
    local tw = TweenService:Create(r, TweenInfo.new(math.max(dist / speed, 0.08), Enum.EasingStyle.Linear), {
        CFrame = CFrame.new(pos)
    })
    tw:Play()
    pcall(function() tw.Completed:Wait() end)
    pcall(function() r.AssemblyLinearVelocity = Vector3.zero end)
    task.delay(0.2, function() SelfMoving = false end)
end

-- Nomes comuns de mobs de Halloween / evento
local HalloweenMobs = {
    "Ghost", "Skeleton", "Zombie", "Pumpkin", "Spirit", "Reaper",
    "Hollow", "Demon", "Soul", "Scarecrow", "Witch", "Vampire",
    "Bone", "Phantom", "Wraith"
}

local function isHalloweenMob(name)
    for _, n in ipairs(HalloweenMobs) do
        if name:find(n, 1, true) then return true end
    end
    return false
end

local function nearestHalloween(maxDist)
    local r = getRoot()
    if not r then return nil end
    local folder = Workspace:FindFirstChild("Enemies") or Workspace
    local best, bd = nil, maxDist or 2500
    for _, m in ipairs(folder:GetChildren()) do
        if m:IsA("Model") and m ~= lp.Character then
            local h = m:FindFirstChildOfClass("Humanoid")
            local hrp = m:FindFirstChild("HumanoidRootPart")
            if h and h.Health > 0 and hrp and not Players:GetPlayerFromCharacter(m) then
                if isHalloweenMob(m.Name) then
                    local d = (hrp.Position - r.Position).Magnitude
                    if d < bd then best, bd = m, d end
                end
            end
        end
    end
    return best
end

local function nearestAny(maxDist, filter)
    local r = getRoot()
    if not r then return nil end
    local folder = Workspace:FindFirstChild("Enemies") or Workspace
    local best, bd = nil, maxDist or 2500
    for _, m in ipairs(folder:GetChildren()) do
        if m:IsA("Model") and m ~= lp.Character then
            local h = m:FindFirstChildOfClass("Humanoid")
            local hrp = m:FindFirstChild("HumanoidRootPart")
            if h and h.Health > 0 and hrp and not Players:GetPlayerFromCharacter(m) then
                if not filter or m.Name:find(filter, 1, true) then
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

local function attack()
    equipAny()
    click()
    if flag("Skills") then
        pressKey(Enum.KeyCode.Z)
        task.wait(0.1)
        pressKey(Enum.KeyCode.X)
    end
end

local function engage(target, flagId)
    local ticks = 0
    while G.PhyntonHalloween and flag(flagId) and target and target.Parent and ticks < 200 do
        local h = target:FindFirstChildOfClass("Humanoid")
        local hrp = target:FindFirstChild("HumanoidRootPart")
        if not (h and h.Health > 0 and hrp) then break end

        local myH = getHum()
        if flag("Flee") and myH and myH.Health / myH.MaxHealth < 0.25 then
            local r = getRoot()
            if r then r.CFrame = r.CFrame + Vector3.new(0, 50, 0) end
            break
        end

        local r = getRoot()
        if r then
            SelfMoving = true
            r.CFrame = hrp.CFrame * CFrame.new(0, val("Height", 8), 0) * CFrame.Angles(math.rad(-90), 0, 0)
            r.AssemblyLinearVelocity = Vector3.zero
            attack()
        end
        ticks = ticks + 1
        task.wait(val("Delay", 0.1))
    end
    SelfMoving = false
end

-- Noclip leve
RunService.Stepped:Connect(function()
    if SelfMoving or flag("Noclip") then
        local c = lp.Character
        if c then
            for _, p in ipairs(c:GetChildren()) do
                if p:IsA("BasePart") then p.CanCollide = false end
            end
        end
    end
end)

-- Anti AFK
pcall(function()
    lp.Idled:Connect(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end)

---------------------------------------------------------------------
-- FARM
---------------------------------------------------------------------
do
    addToggle(Tabs.Farm, "Skills", "Usar Skills", true)
    addToggle(Tabs.Farm, "Flee", "Fugir com pouca vida", true)
    addToggle(Tabs.Farm, "Noclip", "Noclip", false)

    addToggle(Tabs.Farm, "FarmEvent", "Farm Mobs Halloween", false, function(on)
        if not on then return end
        startLoop("FarmEvent", function()
            local t = nearestHalloween(3000)
            if t then
                local hrp = t:FindFirstChild("HumanoidRootPart")
                if hrp then
                    tweenTo(hrp.Position + Vector3.new(0, val("Height", 8), 0))
                    engage(t, "FarmEvent")
                end
            else
                -- se não achar mob de evento, farm normal perto
                local t2 = nearestAny(1500)
                if t2 then
                    local hrp = t2:FindFirstChild("HumanoidRootPart")
                    if hrp then
                        tweenTo(hrp.Position + Vector3.new(0, val("Height", 8), 0))
                        engage(t2, "FarmEvent")
                    end
                else
                    task.wait(0.5)
                end
            end
        end, 0.25)
    end)

    addToggle(Tabs.Farm, "FarmBoss", "Farm Boss do Evento", false, function(on)
        if not on then return end
        startLoop("FarmBoss", function()
            local t = nearestAny(4000, "Reaper")
                or nearestAny(4000, "Hollow")
                or nearestAny(4000, "Demon")
                or nearestAny(4000, "Boss")
            if t then
                local hrp = t:FindFirstChild("HumanoidRootPart")
                if hrp then
                    tweenTo(hrp.Position + Vector3.new(0, val("Height", 8), 0))
                    engage(t, "FarmBoss")
                end
            else
                task.wait(0.6)
            end
        end, 0.3)
    end)

    addToggle(Tabs.Farm, "FarmBone", "Farm Bone / Soul", false, function(on)
        if not on then return end
        startLoop("FarmBone", function()
            local t = nearestAny(2500, "Skeleton")
                or nearestAny(2500, "Soul")
                or nearestAny(2500, "Zombie")
                or nearestAny(2500, "Bone")
            if t then
                local hrp = t:FindFirstChild("HumanoidRootPart")
                if hrp then
                    tweenTo(hrp.Position + Vector3.new(0, val("Height", 8), 0))
                    engage(t, "FarmBone")
                end
            else
                task.wait(0.5)
            end
        end, 0.3)
    end)
end

---------------------------------------------------------------------
-- ITEMS
---------------------------------------------------------------------
do
    addToggle(Tabs.Items, "Candy", "Pegar Doces / Candies", false, function(on)
        if not on then return end
        startLoop("Candy", function()
            local r = getRoot()
            if not r then return end
            for _, d in ipairs(Workspace:GetDescendants()) do
                if d:IsA("BasePart") or d:IsA("MeshPart") then
                    local n = d.Name:lower()
                    if n:find("candy") or n:find("doce") or n:find("treat") or n:find("pumpkin") then
                        if (d.Position - r.Position).Magnitude < 600 then
                            tweenTo(d.Position + Vector3.new(0, 2, 0))
                            task.wait(0.25)
                            return
                        end
                    end
                end
            end
            -- tools no chão
            for _, d in ipairs(Workspace:GetChildren()) do
                if d:IsA("Tool") then
                    local h = d:FindFirstChild("Handle")
                    if h and (h.Position - r.Position).Magnitude < 500 then
                        tweenTo(h.Position)
                        task.wait(0.25)
                        return
                    end
                end
            end
        end, 1)
    end)

    addToggle(Tabs.Items, "Chest", "Auto Chest Evento", false, function(on)
        if not on then return end
        startLoop("Chest", function()
            local r = getRoot()
            if not r then return end
            local best, bd = nil, 900
            for _, d in ipairs(Workspace:GetDescendants()) do
                if d:IsA("BasePart") and d.Name:lower():find("chest") then
                    local dist = (d.Position - r.Position).Magnitude
                    if dist < bd then best, bd = d, dist end
                end
            end
            if best then
                tweenTo(best.Position + Vector3.new(0, 3, 0))
            end
        end, 0.7)
    end)

    addToggle(Tabs.Items, "Store", "Guardar Frutas / Itens", false, function(on)
        if not on then return end
        startLoop("Store", function()
            local bp = lp:FindFirstChildOfClass("Backpack")
            if not bp then return end
            for _, t in ipairs(bp:GetChildren()) do
                if t:IsA("Tool") and (t.Name:find("Fruit") or t.Name:find("Candy")) then
                    pcall(function()
                        comm("StoreFruit", t:GetAttribute("OriginalName") or t.Name, t)
                    end)
                end
            end
        end, 5)
    end)
end

---------------------------------------------------------------------
-- CONFIG
---------------------------------------------------------------------
do
    addSlider(Tabs.Config, "Speed", "Velocidade Tween", 150, 400, 280)
    addSlider(Tabs.Config, "Height", "Altura no mob", 5, 18, 8)
    addSlider(Tabs.Config, "Delay", "Delay ataque", 0.05, 0.25, 0.1)

    Tabs.Config:AddParagraph({
        Title = "Sobre",
        Content = "Versão só para evento de Halloween.\nFarm de Ghost, Skeleton, Pumpkin, Soul, etc."
    })
end

---------------------------------------------------------------------
Window:SelectTab(1)
notify("Halloween Event carregado")
