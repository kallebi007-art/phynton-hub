--[[
    PHYNTON HALLOWEEN - Versão estável
]]

local G = (getgenv and getgenv()) or _G
if G.PhyntonHalloween then return end
G.PhyntonHalloween = true

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VIM = game:GetService("VirtualInputManager")
local VirtualUser = game:GetService("VirtualUser")

local lp = Players.LocalPlayer
local cam = Workspace.CurrentCamera

local Flags, Vals, Tokens = {}, {}, {}
local SelfMoving = false

local function val(id, d)
    if Vals[id] == nil then return d end
    return Vals[id]
end
local function flag(id)
    return Flags[id] == true
end

local function comm(...)
    local rem = ReplicatedStorage:FindFirstChild("Remotes")
    local c = rem and rem:FindFirstChild("CommF_")
    if c then
        pcall(function()
            c:InvokeServer(...)
        end)
    end
end

-- Carrega Fluent
local Fluent
local ok, err = pcall(function()
    Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
end)
if not ok or not Fluent then
    G.PhyntonHalloween = nil
    warn("[Halloween] Erro ao carregar Fluent:", err)
    return
end

local Window = Fluent:CreateWindow({
    Title = "Phynton Halloween",
    SubTitle = "event",
    TabWidth = 120,
    Size = UDim2.fromOffset(420, 280),
    Acrylic = false,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl,
})

local Tabs = {
    Farm = Window:AddTab({ Title = "Farm", Icon = "skull" }),
    Items = Window:AddTab({ Title = "Items", Icon = "box" }),
    Config = Window:AddTab({ Title = "Config", Icon = "settings" }),
}

local function notify(msg)
    pcall(function()
        Fluent:Notify({ Title = "Halloween", Content = tostring(msg), Duration = 3 })
    end)
end

local function startLoop(id, fn, waitTime)
    Tokens[id] = (Tokens[id] or 0) + 1
    local my = Tokens[id]
    task.spawn(function()
        while G.PhyntonHalloween and Flags[id] and Tokens[id] == my do
            pcall(fn)
            task.wait(waitTime or 0.2)
        end
    end)
end

local function addToggle(tab, id, title, default, cb)
    Flags[id] = default or false
    local el = tab:AddToggle(id, {
        Title = title,
        Default = default or false
    })
    el:OnChanged(function(v)
        Flags[id] = v
        if cb then
            task.spawn(function()
                pcall(cb, v)
            end)
        end
    end)
end

local function addSlider(tab, id, title, min, max, default)
    Vals[id] = default
    local el = tab:AddSlider(id, {
        Title = title,
        Default = default,
        Min = min,
        Max = max,
        Rounding = 0
    })
    el:OnChanged(function(v)
        Vals[id] = v
    end)
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
        VirtualUser:Button1Down(Vector2.new(0, 0), cam.CFrame)
        task.wait(0.03)
        VirtualUser:Button1Up(Vector2.new(0, 0), cam.CFrame)
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
    local time = math.max(dist / speed, 0.08)
    local tw = TweenService:Create(r, TweenInfo.new(time, Enum.EasingStyle.Linear), {
        CFrame = CFrame.new(pos)
    })
    tw:Play()
    pcall(function()
        tw.Completed:Wait()
    end)
    pcall(function()
        r.AssemblyLinearVelocity = Vector3.zero
    end)
    task.delay(0.15, function()
        SelfMoving = false
    end)
end

local HalloweenNames = {
    "Ghost", "Skeleton", "Zombie", "Pumpkin", "Spirit", "Reaper",
    "Hollow", "Demon", "Soul", "Scarecrow", "Witch", "Vampire",
    "Bone", "Phantom", "Wraith", "Skull"
}

local function isEventMob(name)
    for i = 1, #HalloweenNames do
        if string.find(name, HalloweenNames[i], 1, true) then
            return true
        end
    end
    return false
end

local function nearestEvent(maxDist)
    local r = getRoot()
    if not r then return nil end
    local folder = Workspace:FindFirstChild("Enemies") or Workspace
    local best, bestDist = nil, maxDist or 2500
    for _, m in ipairs(folder:GetChildren()) do
        if m:IsA("Model") and m ~= lp.Character then
            local h = m:FindFirstChildOfClass("Humanoid")
            local hrp = m:FindFirstChild("HumanoidRootPart")
            if h and h.Health > 0 and hrp then
                if not Players:GetPlayerFromCharacter(m) and isEventMob(m.Name) then
                    local d = (hrp.Position - r.Position).Magnitude
                    if d < bestDist then
                        best = m
                        bestDist = d
                    end
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
    local best, bestDist = nil, maxDist or 2500
    for _, m in ipairs(folder:GetChildren()) do
        if m:IsA("Model") and m ~= lp.Character then
            local h = m:FindFirstChildOfClass("Humanoid")
            local hrp = m:FindFirstChild("HumanoidRootPart")
            if h and h.Health > 0 and hrp and not Players:GetPlayerFromCharacter(m) then
                if not filter or string.find(m.Name, filter, 1, true) then
                    local d = (hrp.Position - r.Position).Magnitude
                    if d < bestDist then
                        best = m
                        bestDist = d
                    end
                end
            end
        end
    end
    return best
end

local function equipTool()
    local char = lp.Character
    local bp = lp:FindFirstChildOfClass("Backpack")
    if not char or not bp then return end
    for _, t in ipairs(char:GetChildren()) do
        if t:IsA("Tool") then return t end
    end
    for _, t in ipairs(bp:GetChildren()) do
        if t:IsA("Tool") then
            local h = getHum()
            if h then
                h:EquipTool(t)
            end
            return t
        end
    end
end

local function doAttack()
    equipTool()
    click()
    if flag("Skills") then
        pressKey(Enum.KeyCode.Z)
        task.wait(0.08)
        pressKey(Enum.KeyCode.X)
    end
end

local function fight(target, flagId)
    local count = 0
    while G.PhyntonHalloween and flag(flagId) and target and target.Parent and count < 180 do
        local h = target:FindFirstChildOfClass("Humanoid")
        local hrp = target:FindFirstChild("HumanoidRootPart")
        if not h or h.Health <= 0 or not hrp then break end

        local myH = getHum()
        if flag("Flee") and myH and myH.MaxHealth > 0 then
            if myH.Health / myH.MaxHealth < 0.22 then
                local r = getRoot()
                if r then
                    r.CFrame = r.CFrame + Vector3.new(0, 55, 0)
                end
                break
            end
        end

        local r = getRoot()
        if r then
            SelfMoving = true
            r.CFrame = hrp.CFrame * CFrame.new(0, val("Height", 8), 0) * CFrame.Angles(math.rad(-90), 0, 0)
            r.AssemblyLinearVelocity = Vector3.zero
            doAttack()
        end
        count = count + 1
        task.wait(val("Delay", 0.1))
    end
    SelfMoving = false
end

-- Noclip
RunService.Stepped:Connect(function()
    if SelfMoving or flag("Noclip") then
        local c = lp.Character
        if c then
            for _, p in ipairs(c:GetChildren()) do
                if p:IsA("BasePart") then
                    p.CanCollide = false
                end
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
-- FARM TAB
---------------------------------------------------------------------
addToggle(Tabs.Farm, "Skills", "Usar Skills (Z/X)", true)
addToggle(Tabs.Farm, "Flee", "Fugir com pouca vida", true)
addToggle(Tabs.Farm, "Noclip", "Noclip", false)

addToggle(Tabs.Farm, "FarmEvent", "Farm Mobs Halloween", false, function(on)
    if not on then return end
    startLoop("FarmEvent", function()
        local t = nearestEvent(3000)
        if not t then
            t = nearestAny(1200)
        end
        if t then
            local hrp = t:FindFirstChild("HumanoidRootPart")
            if hrp then
                tweenTo(hrp.Position + Vector3.new(0, val("Height", 8), 0))
                fight(t, "FarmEvent")
            end
        else
            task.wait(0.4)
        end
    end, 0.2)
end)

addToggle(Tabs.Farm, "FarmBoss", "Farm Boss Evento", false, function(on)
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
                fight(t, "FarmBoss")
            end
        else
            task.wait(0.5)
        end
    end, 0.25)
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
                fight(t, "FarmBone")
            end
        else
            task.wait(0.5)
        end
    end, 0.25)
end)

---------------------------------------------------------------------
-- ITEMS TAB
---------------------------------------------------------------------
addToggle(Tabs.Items, "Candy", "Pegar Doces / Candy", false, function(on)
    if not on then return end
    startLoop("Candy", function()
        local r = getRoot()
        if not r then return end
        for _, d in ipairs(Workspace:GetDescendants()) do
            if d:IsA("BasePart") then
                local n = string.lower(d.Name)
                if string.find(n, "candy") or string.find(n, "treat") or string.find(n, "pumpkin") or string.find(n, "doce") then
                    if (d.Position - r.Position).Magnitude < 700 then
                        tweenTo(d.Position + Vector3.new(0, 2, 0))
                        task.wait(0.2)
                        return
                    end
                end
            end
        end
        for _, d in ipairs(Workspace:GetChildren()) do
            if d:IsA("Tool") then
                local h = d:FindFirstChild("Handle")
                if h and (h.Position - r.Position).Magnitude < 500 then
                    tweenTo(h.Position)
                    task.wait(0.2)
                    return
                end
            end
        end
    end, 1)
end)

addToggle(Tabs.Items, "Chest", "Auto Chest", false, function(on)
    if not on then return end
    startLoop("Chest", function()
        local r = getRoot()
        if not r then return end
        local best, bestDist = nil, 900
        for _, d in ipairs(Workspace:GetDescendants()) do
            if d:IsA("BasePart") and string.find(string.lower(d.Name), "chest") then
                local dist = (d.Position - r.Position).Magnitude
                if dist < bestDist then
                    best = d
                    bestDist = dist
                end
            end
        end
        if best then
            tweenTo(best.Position + Vector3.new(0, 3, 0))
        end
    end, 0.7)
end)

---------------------------------------------------------------------
-- CONFIG TAB
---------------------------------------------------------------------
addSlider(Tabs.Config, "Speed", "Velocidade", 150, 400, 280)
addSlider(Tabs.Config, "Height", "Altura no mob", 5, 18, 8)
addSlider(Tabs.Config, "Delay", "Delay ataque", 0.05, 0.25, 0.1)

Tabs.Config:AddParagraph({
    Title = "Halloween Event",
    Content = "Farm de Ghost, Skeleton, Pumpkin, Soul, Reaper etc."
})

---------------------------------------------------------------------
Window:SelectTab(1)
notify("Halloween carregado com sucesso!")
print("[Phynton Halloween] Carregado")
