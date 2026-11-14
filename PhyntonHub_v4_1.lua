--[[ ============================================================
     PHYNTON HUB v4
     Base: arquitetura do Phynton (Janitor/Feature, modo Player x Scripter,
     IA de movimento, Mirage, visual) + mecânicas aprendidas no Relz Hub
     (quests por nível, tween com teleporters, bring mob, hit por Net,
     haki, maestria por HP, ESP, teleporte, loja, stats, servidor).
     Obs.: nem tudo foi testado no jogo. Ligue uma função por vez.
     ============================================================ ]]

local G = (getgenv and getgenv()) or _G

-- Re-execução segura: roda a limpeza deixada pela instância anterior
if G.PhyntonCleanup then
    for _, fn in ipairs(G.PhyntonCleanup) do pcall(fn) end
end
G.PhyntonCleanup = {}
local function onCleanup(fn) table.insert(G.PhyntonCleanup, fn) end
if G.PhyntonHub then pcall(function() G.PhyntonHub:StopAll() end) end
pcall(function() if G.PhyntonFluent then G.PhyntonFluent:Destroy() end end)

if not game:IsLoaded() then game.Loaded:Wait() end

local Players         = game:GetService("Players")
local RunService      = game:GetService("RunService")
local VIM             = game:GetService("VirtualInputManager")
local Lighting        = game:GetService("Lighting")
local TweenService    = game:GetService("TweenService")
local VirtualUser     = game:GetService("VirtualUser")
local TeleportService = game:GetService("TeleportService")
local HttpService     = game:GetService("HttpService")
local RS              = game:GetService("ReplicatedStorage")
local Workspace       = game:GetService("Workspace")
local LP              = Players.LocalPlayer

--------------------------------------------------------------------
-- MUNDO (Sea 1/2/3) e REMOTES
--------------------------------------------------------------------
local PID = game.PlaceId
local World
if PID == 2753915549 or PID == 85211729168715 then World = "Sea1"
elseif PID == 4442272183 or PID == 79091703265657 then World = "Sea2"
elseif PID == 7449423635 or PID == 100117331123089 then World = "Sea3" end

local Remotes = RS:FindFirstChild("Remotes") or RS:WaitForChild("Remotes", 10)
local CommF = Remotes and Remotes:FindFirstChild("CommF_")

-- InvokeServer protegido: nunca quebra o loop se o remote falhar
local function Invoke(...)
    if not CommF then return nil end
    local ok, res = pcall(CommF.InvokeServer, CommF, ...)
    if ok then return res end
    return nil
end

local RegisterAttack, RegisterHit
pcall(function()
    local Net = require(RS:WaitForChild("Modules"):WaitForChild("Net"))
    RegisterAttack = Net:RemoteEvent("RegisterAttack", true)
    RegisterHit = Net:RemoteEvent("RegisterHit", true)
end)

-- Anti-AFK
do
    local c = LP.Idled:Connect(function()
        VirtualUser:Button2Down(Vector2.new(0, 0), Workspace.CurrentCamera.CFrame)
        task.wait(1)
        VirtualUser:Button2Up(Vector2.new(0, 0), Workspace.CurrentCamera.CFrame)
    end)
    onCleanup(function() c:Disconnect() end)
end

local Hub = { Mode = "Player", Features = {}, World = World, Version = "4.1" }

--------------------------------------------------------------------
-- 1) JANITOR + FEATURE
--------------------------------------------------------------------
local Janitor = {}
Janitor.__index = Janitor
function Janitor.new() return setmetatable({ items = {} }, Janitor) end
function Janitor:Add(x) table.insert(self.items, x); return x end
function Janitor:Clean()
    for _, x in ipairs(self.items) do
        local t = typeof(x)
        if t == "RBXScriptConnection" then x:Disconnect()
        elseif t == "Instance" then pcall(function() x:Destroy() end)
        elseif t == "function" then pcall(x)
        elseif t == "thread" then pcall(task.cancel, x) end
    end
    table.clear(self.items)
end

local Feature = {}
Feature.__index = Feature
function Feature:Set(on)
    if on == self.On then return end
    self.On = on
    if on then
        self.Jan = Janitor.new()
        task.spawn(function()
            local ok, err = pcall(self.Start, self, self.Jan)
            if not ok then warn("[Phynton:" .. self.Name .. "] Start:", err) end
        end)
    else
        if self.Jan then self.Jan:Clean(); self.Jan = nil end
        if self.Stop then pcall(self.Stop, self) end
    end
end
function Feature:Loop(delay, fn)
    local f = self
    local th = task.spawn(function()
        while f.On do
            local ok, err = pcall(fn)
            if not ok then warn("[Phynton:" .. f.Name .. "]", err) end
            task.wait(delay)
        end
    end)
    self.Jan:Add(th)
end

-- modeAware = true: a função é reiniciada quando troca Player <-> Scripter
function Hub:Register(name, start, stop, modeAware)
    local f = setmetatable({ Name = name, On = false, Start = start, Stop = stop, ModeAware = modeAware }, Feature)
    self.Features[name] = f
    return f
end
function Hub:StopAll()
    for _, f in pairs(self.Features) do f:Set(false) end
end

--------------------------------------------------------------------
-- 2) UTILS DE PERSONAGEM
--------------------------------------------------------------------
local function char() return LP.Character end
local function hrp() local c = char(); return c and c:FindFirstChild("HumanoidRootPart") end
local function hum() local c = char(); return c and c:FindFirstChildOfClass("Humanoid") end
local function level()
    local ok, v = pcall(function() return LP.Data.Level.Value end)
    return ok and v or 1
end
local function enemiesFolder() return Workspace:FindFirstChild("Enemies") end

local FLY_TAG = "PhyntonFly"
local function clearFlight()
    local r = hrp()
    if r then
        for _, o in ipairs(r:GetChildren()) do
            if o.Name == FLY_TAG or o:IsA("BodyVelocity") or o:IsA("BodyPosition")
                or o:IsA("BodyGyro") or o:IsA("LinearVelocity") or o:IsA("AlignPosition") then
                pcall(function() o:Destroy() end)
            end
        end
        r.AssemblyLinearVelocity = Vector3.zero
    end
    local h = hum()
    if h then
        pcall(function() h.PlatformStand = false end)
        pcall(function() h:ChangeState(Enum.HumanoidStateType.GettingUp) end)
    end
end

function Hub:SetMode(mode)
    if mode == self.Mode then return end
    self.Mode = mode
    if mode == "Player" then clearFlight() end
    -- reinicia funções ativas para pegar o novo comportamento
    for _, f in pairs(self.Features) do
        if f.On and f.ModeAware then
            task.spawn(function()
                f:Set(false); task.wait(0.12)
                if self.Mode == mode then f:Set(true) end
            end)
        end
    end
end

do
    local c = LP.CharacterAdded:Connect(function()
        task.wait(1)
        if Hub.Mode == "Player" then clearFlight() end
    end)
    onCleanup(function() c:Disconnect() end)
end

--------------------------------------------------------------------
-- 3) CONFIG
--------------------------------------------------------------------
Hub.Config = {
    -- geral
    Delay        = 0.2,
    Weapon       = "Melee",          -- ToolTip: Melee | Sword | Gun | Blox Fruit
    AutoHaki     = true,
    FarmDistance = 35,               -- altura sobre o mob (Scripter)
    SpinPosition = false,
    TweenSpeed   = 300,
    BringMob     = true,
    BringDistance= 500,
    AttackAuraDist = 120,
    -- maestria
    MasteryTypes = { Sword = true, Gun = true, ["Blox Fruit"] = true, Melee = false },
    MasteryMethod= "Level",          -- Level | Nearest
    MasteryHealth= 25,               -- % de vida do mob para trocar p/ skills
    SwitchEvery  = 25,
    SkillKeys    = { "Z", "X", "C", "V", "F" },
    GunSkills    = { "Z", "X" },
    -- IA de combate (v3.1)
    HoverHeight  = 12,
    AttackRange  = 28,
    DashRange    = 45,
    DashCooldown = 1.8,
    SkillCooldown= 2.0,
    MaxFlyStep   = 10,
    -- boss / sea
    Boss         = nil,
    BossAll      = false,
    SeaNames     = { "Shark", "Terrorshark", "Piranha", "Fish Crew Member" },
    -- stats / player
    PointStats   = 1,
    Stats        = { Melee = false, Defense = false, Sword = false, Gun = false, ["Demon Fruit"] = false },
    WalkSpeed    = 100,
    JumpPower    = 200,
    Mirage = {
        ApproachTime        = 20,
        OscillationInterval = 3,
        SearchName          = "Mirage",
    },
}

-- Dados extraídos do Relz Hub
Hub.Quests = {
    Sea1 = {
        { 1, 9, "Bandit", "BanditQuest1", 1, Vector3.new(1059.4, 15.4, 1550.4), Vector3.new(1046.0, 27.0, 1560.8) },
        { 10, 14, "Monkey", "JungleQuest", 1, Vector3.new(-1598.1, 35.6, 153.4), Vector3.new(-1448.5, 67.9, 11.5) },
        { 15, 29, "Gorilla", "JungleQuest", 2, Vector3.new(-1598.1, 35.6, 153.4), Vector3.new(-1129.9, 40.5, -525.4) },
        { 30, 39, "Pirate", "BuggyQuest1", 1, Vector3.new(-1141.1, 4.1, 3831.5), Vector3.new(-1103.5, 13.8, 3896.1) },
        { 40, 59, "Brute", "BuggyQuest1", 2, Vector3.new(-1141.1, 4.1, 3831.5), Vector3.new(-1140.1, 14.8, 4322.9) },
        { 60, 74, "Desert Bandit", "DesertQuest", 1, Vector3.new(894.5, 5.1, 4392.4), Vector3.new(924.8, 6.4, 4481.6) },
        { 75, 89, "Desert Officer", "DesertQuest", 2, Vector3.new(894.5, 5.1, 4392.4), Vector3.new(1608.3, 8.6, 4371.0) },
        { 90, 99, "Snow Bandit", "SnowQuest", 1, Vector3.new(1389.7, 88.2, -1298.9), Vector3.new(1354.3, 87.3, -1393.9) },
        { 100, 119, "Snowman", "SnowQuest", 2, Vector3.new(1389.7, 88.2, -1298.9), Vector3.new(1201.6, 144.6, -1550.1) },
        { 120, 149, "Chief Petty Officer", "MarineQuest2", 1, Vector3.new(-5039.6, 27.4, 4324.7), Vector3.new(-4881.2, 22.7, 4273.8) },
        { 150, 174, "Sky Bandit", "SkyQuest", 1, Vector3.new(-4839.5, 716.4, -2619.4), Vector3.new(-4953.2, 295.7, -2899.2) },
        { 175, 189, "Dark Master", "SkyQuest", 2, Vector3.new(-4839.5, 716.4, -2619.4), Vector3.new(-5259.8, 391.4, -2229.0) },
        { 190, 209, "Prisoner", "PrisonerQuest", 1, Vector3.new(5308.9, 1.7, 475.1), Vector3.new(5099.0, -0.3, 474.2) },
        { 210, 249, "Dangerous Prisoner", "PrisonerQuest", 2, Vector3.new(5308.9, 1.7, 475.1), Vector3.new(5654.6, 15.6, 866.3) },
        { 250, 274, "Toga Warrior", "ColosseumQuest", 1, Vector3.new(-1580.0, 6.4, -2986.5), Vector3.new(-1820.2, 51.7, -2740.7) },
        { 275, 299, "Gladiator", "ColosseumQuest", 2, Vector3.new(-1580.0, 6.4, -2986.5), Vector3.new(-1292.8, 56.4, -3339.0) },
        { 300, 324, "Military Soldier", "MagmaQuest", 1, Vector3.new(-5313.4, 11.0, 8515.3), Vector3.new(-5411.2, 11.1, 8454.3) },
        { 325, 374, "Military Spy", "MagmaQuest", 2, Vector3.new(-5313.4, 11.0, 8515.3), Vector3.new(-5802.9, 86.3, 8828.9) },
        { 375, 399, "Fishman Warrior", "FishmanQuest", 1, Vector3.new(61122.7, 18.5, 1569.4), Vector3.new(60878.3, 18.5, 1543.8) },
        { 400, 449, "Fishman Commando", "FishmanQuest", 2, Vector3.new(61122.7, 18.5, 1569.4), Vector3.new(61922.6, 18.5, 1493.9) },
        { 450, 474, "God's Guard", "SkyExp1Quest", 1, Vector3.new(-4721.9, 843.9, -1950.0), Vector3.new(-4710.0, 845.3, -1927.3) },
        { 475, 524, "Shanda", "SkyExp1Quest", 2, Vector3.new(-7859.1, 5544.2, -381.5), Vector3.new(-7678.5, 5566.4, -497.2) },
        { 525, 549, "Royal Squad", "SkyExp2Quest", 1, Vector3.new(-7906.8, 5634.7, -1412.0), Vector3.new(-7624.3, 5658.1, -1467.4) },
        { 550, 624, "Royal Soldier", "SkyExp2Quest", 2, Vector3.new(-7906.8, 5634.7, -1412.0), Vector3.new(-7836.8, 5645.7, -1790.6) },
        { 625, 649, "Galley Pirate", "FountainQuest", 1, Vector3.new(5259.8, 37.4, 4050.0), Vector3.new(5551.0, 78.9, 3930.4) },
        { 650, 99999, "Galley Captain", "FountainQuest", 2, Vector3.new(5259.8, 37.4, 4050.0), Vector3.new(5442.0, 42.5, 4950.1) },
    },
    Sea2 = {
        { 700, 724, "Raider", "Area1Quest", 1, Vector3.new(-429.5, 71.8, 1836.2), Vector3.new(-728.3, 52.8, 2345.8) },
        { 725, 774, "Mercenary", "Area1Quest", 2, Vector3.new(-429.5, 71.8, 1836.2), Vector3.new(-1004.3, 80.2, 1424.6) },
        { 775, 799, "Swan Pirate", "Area2Quest", 1, Vector3.new(638.4, 71.8, 918.3), Vector3.new(1068.7, 137.6, 1322.1) },
        { 800, 874, "Factory Staff", "Area2Quest", 2, Vector3.new(632.7, 73.1, 918.7), Vector3.new(73.1, 81.9, -27.5) },
        { 875, 899, "Marine Lieutenant", "MarineQuest3", 1, Vector3.new(-2440.8, 71.7, -3216.1), Vector3.new(-2821.4, 75.9, -3070.1) },
        { 900, 949, "Marine Captain", "MarineQuest3", 2, Vector3.new(-2440.8, 71.7, -3216.1), Vector3.new(-1861.2, 80.2, -3254.7) },
        { 950, 974, "Zombie", "ZombieQuest", 1, Vector3.new(-5497.1, 47.6, -795.2), Vector3.new(-5657.8, 79.0, -928.7) },
        { 975, 999, "Vampire", "ZombieQuest", 2, Vector3.new(-5497.1, 47.6, -795.2), Vector3.new(-6037.7, 32.2, -1340.7) },
        { 1000, 1049, "Snow Trooper", "SnowMountainQuest", 1, Vector3.new(609.9, 400.1, -5372.3), Vector3.new(549.1, 427.4, -5563.7) },
        { 1050, 1099, "Winter Warrior", "SnowMountainQuest", 2, Vector3.new(609.9, 400.1, -5372.3), Vector3.new(1142.7, 475.6, -5199.4) },
        { 1100, 1124, "Lab Subordinate", "IceSideQuest", 1, Vector3.new(-6064.1, 15.2, -4903.0), Vector3.new(-5707.5, 16.0, -4513.4) },
        { 1125, 1174, "Horned Warrior", "IceSideQuest", 2, Vector3.new(-6064.1, 15.2, -4903.0), Vector3.new(-6341.4, 16.0, -5723.2) },
        { 1175, 1199, "Magma Ninja", "FireSideQuest", 1, Vector3.new(-5428.0, 15.1, -5299.4), Vector3.new(-5449.7, 76.7, -5808.2) },
        { 1200, 1249, "Lava Pirate", "FireSideQuest", 2, Vector3.new(-5428.0, 15.1, -5299.4), Vector3.new(-5213.3, 49.7, -4701.5) },
        { 1250, 1274, "Ship Deckhand", "ShipQuest1", 1, Vector3.new(1037.8, 125.1, 32911.6), Vector3.new(1212.0, 150.8, 33059.2) },
        { 1275, 1299, "Ship Engineer", "ShipQuest1", 2, Vector3.new(1037.8, 125.1, 32911.6), Vector3.new(919.5, 43.5, 32780.0) },
        { 1300, 1324, "Ship Steward", "ShipQuest2", 1, Vector3.new(968.8, 125.1, 33244.1), Vector3.new(919.4, 129.6, 33436.0) },
        { 1325, 1349, "Ship Officer", "ShipQuest2", 2, Vector3.new(968.8, 125.1, 33244.1), Vector3.new(1036.0, 181.4, 33315.7) },
        { 1350, 1374, "Arctic Warrior", "FrostQuest", 1, Vector3.new(5667.7, 26.8, -6486.1), Vector3.new(5966.2, 63.0, -6179.4) },
        { 1375, 1424, "Snow Lurker", "FrostQuest", 2, Vector3.new(5667.7, 26.8, -6486.1), Vector3.new(5407.1, 69.2, -6880.9) },
        { 1425, 1449, "Sea Soldier", "ForgottenQuest", 1, Vector3.new(-3054.4, 235.5, -10142.8), Vector3.new(-3028.2, 64.7, -9775.4) },
        { 1450, 99999, "Water Fighter", "ForgottenQuest", 2, Vector3.new(-3054.4, 235.5, -10142.8), Vector3.new(-3352.9, 285.0, -10534.8) },
    },
    Sea3 = {
        { 1500, 1524, "Pirate Millionaire", "PiratePortQuest", 1, Vector3.new(-290.1, 42.9, 5581.6), Vector3.new(-246.0, 47.3, 5584.1) },
        { 1525, 1574, "Pistol Billionaire", "PiratePortQuest", 2, Vector3.new(-290.1, 42.9, 5581.6), Vector3.new(-187.3, 86.2, 6013.5) },
        { 1575, 1599, "Dragon Crew Warrior", "AmazonQuest", 1, Vector3.new(5832.8, 51.7, -1101.5), Vector3.new(6141.1, 51.4, -1340.7) },
        { 1600, 1624, "Dragon Crew Archer", "AmazonQuest", 2, Vector3.new(5833.1, 51.6, -1103.1), Vector3.new(6616.4, 441.8, 446.0) },
        { 1625, 1649, "Female Islander", "AmazonQuest2", 1, Vector3.new(5446.9, 601.6, 749.5), Vector3.new(4685.3, 735.8, 815.3) },
        { 1650, 1699, "Giant Islander", "AmazonQuest2", 2, Vector3.new(5446.9, 601.6, 749.5), Vector3.new(4729.1, 590.4, -37.0) },
        { 1700, 1724, "Marine Commodore", "MarineTreeIsland", 1, Vector3.new(2180.5, 27.8, -6741.5), Vector3.new(2286.0, 73.1, -7159.8) },
        { 1725, 1774, "Marine Rear Admiral", "MarineTreeIsland", 2, Vector3.new(2180.0, 28.7, -6740.1), Vector3.new(3656.8, 160.5, -7001.6) },
        { 1775, 1799, "Fishman Raider", "DeepForestIsland3", 1, Vector3.new(-10581.7, 330.9, -8761.2), Vector3.new(-10407.5, 331.8, -8368.5) },
        { 1800, 1824, "Fishman Captain", "DeepForestIsland3", 2, Vector3.new(-10581.7, 330.9, -8761.2), Vector3.new(-10994.7, 352.4, -9002.1) },
        { 1825, 1849, "Forest Pirate", "DeepForestIsland", 1, Vector3.new(-13234.0, 331.5, -7625.4), Vector3.new(-13274.5, 332.4, -7769.6) },
        { 1850, 1899, "Mythological Pirate", "DeepForestIsland", 2, Vector3.new(-13234.0, 331.5, -7625.4), Vector3.new(-13680.6, 501.1, -6991.2) },
        { 1900, 1924, "Jungle Pirate", "DeepForestIsland2", 1, Vector3.new(-12680.4, 390.0, -9902.0), Vector3.new(-12256.2, 331.7, -10485.8) },
        { 1925, 1974, "Musketeer Pirate", "DeepForestIsland2", 2, Vector3.new(-12680.4, 390.0, -9902.0), Vector3.new(-13457.9, 391.5, -9859.2) },
        { 1975, 1999, "Reborn Skeleton", "HauntedQuest1", 1, Vector3.new(-9479.2, 141.2, 5566.1), Vector3.new(-8763.7, 165.7, 6159.9) },
        { 2000, 2024, "Living Zombie", "HauntedQuest1", 2, Vector3.new(-9479.2, 141.2, 5566.1), Vector3.new(-10144.1, 138.6, 5838.1) },
        { 2025, 2049, "Demonic Soul", "HauntedQuest2", 1, Vector3.new(-9517.0, 172.0, 6078.5), Vector3.new(-9505.9, 172.1, 6159.0) },
        { 2050, 2074, "Posessed Mummy", "HauntedQuest2", 2, Vector3.new(-9517.0, 172.0, 6078.5), Vector3.new(-9582.0, 6.3, 6205.5) },
        { 2075, 2099, "Peanut Scout", "NutsIslandQuest", 1, Vector3.new(-2104.4, 38.1, -10194.2), Vector3.new(-2143.2, 47.7, -10030.0) },
        { 2100, 2124, "Peanut President", "NutsIslandQuest", 2, Vector3.new(-2104.4, 38.1, -10194.2), Vector3.new(-1859.4, 38.1, -10422.4) },
        { 2125, 2149, "Ice Cream Chef", "IceCreamIslandQuest", 1, Vector3.new(-820.6, 65.8, -10965.8), Vector3.new(-872.2, 65.8, -10920.0) },
        { 2150, 2199, "Ice Cream Commander", "IceCreamIslandQuest", 2, Vector3.new(-820.6, 65.8, -10965.8), Vector3.new(-558.1, 112.0, -11290.8) },
        { 2200, 2224, "Cookie Crafter", "CakeQuest1", 1, Vector3.new(-2021.3, 37.8, -12028.7), Vector3.new(-2374.1, 37.8, -12125.3) },
        { 2225, 2249, "Cake Guard", "CakeQuest1", 2, Vector3.new(-2021.3, 37.8, -12028.7), Vector3.new(-1598.3, 43.8, -12244.6) },
        { 2250, 2274, "Baking Staff", "CakeQuest2", 1, Vector3.new(-1927.9, 37.8, -12842.5), Vector3.new(-1887.8, 77.6, -12998.4) },
        { 2275, 2299, "Head Baker", "CakeQuest2", 2, Vector3.new(-1927.9, 37.8, -12842.5), Vector3.new(-2216.2, 82.9, -12869.3) },
        { 2300, 2324, "Cocoa Warrior", "ChocQuest1", 1, Vector3.new(233.2, 29.9, -12201.2), Vector3.new(-21.6, 80.6, -12352.4) },
        { 2325, 2349, "Chocolate Bar Battler", "ChocQuest1", 2, Vector3.new(233.2, 29.9, -12201.2), Vector3.new(582.6, 77.2, -12463.2) },
        { 2350, 2374, "Sweet Thief", "ChocQuest2", 1, Vector3.new(150.5, 30.7, -12774.5), Vector3.new(165.2, 76.1, -12600.8) },
        { 2375, 2399, "Candy Rebel", "ChocQuest2", 2, Vector3.new(150.5, 30.7, -12774.5), Vector3.new(134.9, 77.2, -12876.5) },
        { 2400, 2424, "Candy Pirate", "CandyQuest1", 1, Vector3.new(-1150.0, 20.4, -14446.3), Vector3.new(-1310.5, 26.0, -14562.4) },
        { 2425, 2449, "Snow Demon", "CandyQuest1", 2, Vector3.new(-1150.0, 20.4, -14446.3), Vector3.new(-880.2, 71.2, -14538.6) },
        { 2450, 2474, "Isle Outlaw", "TikiQuest1", 1, Vector3.new(-16547.7, 61.1, -173.4), Vector3.new(-16442.8, 116.1, -264.5) },
        { 2475, 2524, "Island Boy", "TikiQuest1", 2, Vector3.new(-16547.7, 61.1, -173.4), Vector3.new(-16901.3, 84.1, -192.9) },
        { 2525, 2549, "Isle Champion", "TikiQuest2", 2, Vector3.new(-16539.1, 55.7, 1051.6), Vector3.new(-16641.7, 235.8, 1031.3) },
        { 2550, 2574, "Serpent Hunter", "TikiQuest3", 1, Vector3.new(-16661.9, 105.3, 1576.7), Vector3.new(-16587.9, 154.2, 1533.4) },
        { 2575, 2599, "Skull Slayer", "TikiQuest3", 2, Vector3.new(-16661.9, 105.3, 1576.7), Vector3.new(-16885.2, 114.1, 1627.9) },
        { 2600, 2624, "Reef Bandit", "SubmergedQuest1", 1, Vector3.new(10782.1, -2087.7, 9268.5), Vector3.new(10918.1, -2115.6, 9056.0) },
        { 2625, 2649, "Coral Pirate", "SubmergedQuest1", 2, Vector3.new(10782.1, -2087.7, 9268.5), Vector3.new(10656.1, -2018.7, 9258.4) },
        { 2650, 2674, "Sea Chanter", "SubmergedQuest2", 1, Vector3.new(10879.6, -2086.2, 10027.5), Vector3.new(10691.5, -2023.2, 10026.3) },
        { 2675, 2699, "Ocean Prophet", "SubmergedQuest2", 2, Vector3.new(10879.6, -2086.2, 10027.5), Vector3.new(10900.4, -1973.1, 10233.2) },
        { 2700, 99999, "Grand Devotee", "SubmergedQuest3", 2, Vector3.new(9634.7, -1992.4, 9608.3), Vector3.new(9653.1, -1928.3, 9915.9) },
    },
}
Hub.Bosses = {
    Sea1 = { "The Gorilla King", "Bobby", "Yeti", "Mob Leader", "Vice Admiral", "Warden", "Chief Warden", "Swan", "Magma Admiral", "Fishman Lord", "Wysper", "Thunder God", "Cyborg", "Saber Expert" },
    Sea2 = { "Diamond", "Jeremy", "Fajita", "Don Swan", "Smoke Admiral", "Cursed Captain", "Darkbeard", "Order", "Awakened Ice Admiral", "Tide Keeper" },
    Sea3 = { "Stone", "Island Empress", "Kilo Admiral", "Captain Elephant", "Beautiful Pirate", "rip_indra True Form", "Longma", "Soul Reaper", "Cake Queen", "Tyrant Of The Skies" },
}
Hub.IslandList = {
    Sea1 = { "WindMill", "Marine", "Middle Town", "Jungle", "Pirate Village", "Desert", "Snow Island", "MarineFord", "Colosseum", "Sky Island 1", "Sky Island 2", "Sky Island 3", "Prison", "Magma Village", "Under Water Island", "Fountain City", "Shank Room", "Mob Island" },
    Sea2 = { "The Cafe", "Frist Spot", "Dark Area", "Flamingo Mansion", "Flamingo Room", "Green Zone", "Factory", "Colossuim", "Zombie Island", "Two Snow Mountain", "Punk Hazard", "Cursed Ship", "Ice Castle", "Forgotten Island", "Ussop Island", "Mini Sky Island" },
    Sea3 = { "Mansion", "Port Town", "Great Tree", "Castle On The Sea", "MiniSky", "Hydra Island", "Floating Turtle", "Haunted Castle", "Ice Cream Island", "Peanut Island", "Cake Island", "Cocoa Island", "Candy Island", "Tiki Outpost", "Dragon Dojo" },
}
Hub.Islands = {
    ["WindMill"] = { pos = Vector3.new(979.8, 16.5, 1429.0) },
    ["Marine"] = { pos = Vector3.new(-2566.4, 6.9, 2045.3) },
    ["Middle Town"] = { pos = Vector3.new(-690.3, 15.1, 1582.2) },
    ["Jungle"] = { pos = Vector3.new(-1612.8, 36.9, 149.1) },
    ["Pirate Village"] = { pos = Vector3.new(-1181.3, 4.8, 3803.5) },
    ["Desert"] = { pos = Vector3.new(944.2, 20.9, 4373.3) },
    ["Snow Island"] = { pos = Vector3.new(1347.8, 104.7, -1319.7) },
    ["MarineFord"] = { pos = Vector3.new(-4914.8, 51.0, 4281.0) },
    ["Colosseum"] = { pos = Vector3.new(-1427.6, 7.3, -2792.8) },
    ["Sky Island 1"] = { pos = Vector3.new(-4869.1, 733.5, -2667.0) },
    ["Sky Island 2"] = { entrance = Vector3.new(-4607.8, 872.5, -1667.6) },
    ["Sky Island 3"] = { entrance = Vector3.new(-7894.6, 5547.1, -380.3) },
    ["Prison"] = { pos = Vector3.new(4875.3, 5.7, 734.9) },
    ["Magma Village"] = { pos = Vector3.new(-5247.7, 12.9, 8505.0) },
    ["Under Water Island"] = { entrance = Vector3.new(61163.9, 11.7, 1819.8) },
    ["Fountain City"] = { pos = Vector3.new(5127.1, 59.5, 4105.4) },
    ["Shank Room"] = { pos = Vector3.new(-1442.2, 29.9, -28.4) },
    ["Mob Island"] = { pos = Vector3.new(-2850.2, 7.4, 5355.0) },
    ["The Cafe"] = { pos = Vector3.new(-380.5, 77.2, 255.8) },
    ["Frist Spot"] = { pos = Vector3.new(-11.3, 29.3, 2771.5) },
    ["Dark Area"] = { pos = Vector3.new(3780.0, 22.7, -3498.6) },
    ["Flamingo Mansion"] = { pos = Vector3.new(-483.7, 332.0, 595.3) },
    ["Flamingo Room"] = { pos = Vector3.new(2284.4, 15.2, 875.7) },
    ["Green Zone"] = { pos = Vector3.new(-2448.5, 73.0, -3210.6) },
    ["Factory"] = { pos = Vector3.new(424.1, 211.2, -427.5) },
    ["Colossuim"] = { pos = Vector3.new(-1503.6, 219.8, 1369.3) },
    ["Zombie Island"] = { pos = Vector3.new(-5622.0, 492.2, -781.8) },
    ["Two Snow Mountain"] = { pos = Vector3.new(753.1, 408.2, -5274.6) },
    ["Punk Hazard"] = { pos = Vector3.new(-6127.7, 16.0, -5040.3) },
    ["Cursed Ship"] = { pos = Vector3.new(923.4, 125.1, 32885.9) },
    ["Ice Castle"] = { pos = Vector3.new(6148.4, 294.4, -6741.1) },
    ["Forgotten Island"] = { pos = Vector3.new(-3032.8, 317.9, -10075.4) },
    ["Ussop Island"] = { pos = Vector3.new(4816.9, 8.5, 2863.8) },
    ["Mini Sky Island"] = { pos = Vector3.new(-288.7, 49326.3, -35248.6) },
    ["Great Tree"] = { pos = Vector3.new(2681.3, 1682.8, -7191.0) },
    ["Castle On The Sea"] = { entrance = Vector3.new(-5083.3, 314.6, -3175.7) },
    ["MiniSky"] = { pos = Vector3.new(-260.7, 49325.8, -35253.6) },
    ["Port Town"] = { pos = Vector3.new(-290.7, 6.7, 5343.6) },
    ["Hydra Island"] = { pos = Vector3.new(5291.2, 1005.4, 393.8) },
    ["Floating Turtle"] = { pos = Vector3.new(-13274.5, 531.8, -7579.2) },
    ["Mansion"] = { entrance = Vector3.new(-12471.2, 374.9, -7551.7) },
    ["Haunted Castle"] = { pos = Vector3.new(-9515.4, 164.0, 5786.1) },
    ["Ice Cream Island"] = { pos = Vector3.new(-902.6, 79.9, -10988.8) },
    ["Peanut Island"] = { pos = Vector3.new(-2062.7, 50.5, -10232.6) },
    ["Cake Island"] = { pos = Vector3.new(-1884.8, 19.3, -11666.9) },
    ["Cocoa Island"] = { pos = Vector3.new(87.9, 73.6, -12319.5) },
    ["Candy Island"] = { pos = Vector3.new(-1014.4, 149.1, -14556.0) },
    ["Tiki Outpost"] = { pos = Vector3.new(-16218.7, 9.1, 445.6) },
    ["Dragon Dojo"] = { pos = Vector3.new(5743.3, 1206.9, 936.0) },
}
Hub.Codes = { "KITTGAMING", "ENYU_IS_PRO", "FUDD10", "BIGNEWS", "THEGREATACE", "SUB2GAMERROBOT_EXP1", "STRAWHATMAIME", "SUB2OFFICIALNOOBIE", "SUB2NOOBMASTER123", "SUB2DAIGROCK", "AXIORE", "TANTAIGAMIMG", "STRAWHATMAINE", "JCWK", "FUDD10_V2", "SUB2FER999", "MAGICBIS", "TY_FOR_WATCHING", "STARCODEHEO" }

function Hub:GetQuest(lv)
    local list = self.Quests[World]; if not list then return nil end
    for _, q in ipairs(list) do
        if lv >= q[1] and lv <= q[2] then return q end
    end
    return list[#list]
end

local function findTool(tip)
    local function scan(c)
        if not c then return end
        for _, t in ipairs(c:GetChildren()) do
            if t:IsA("Tool") and t.ToolTip == tip then return t end
        end
    end
    return scan(char()) or scan(LP.Backpack)
end

local function nearestEnemy(maxDist)
    local r = hrp(); if not r then return end
    local best, bd = nil, maxDist or 1500
    local folder = enemiesFolder()
    if not folder then return end
    for _, e in ipairs(folder:GetChildren()) do
        local h, p = e:FindFirstChildOfClass("Humanoid"), e:FindFirstChild("HumanoidRootPart")
        if h and p and h.Health > 0 then
            local d = (p.Position - r.Position).Magnitude
            if d < bd then best, bd = e, d end
        end
    end
    return best
end

local function findMobByName(name, plain)
    local folder = enemiesFolder(); local r = hrp()
    if not (folder and r) then return nil end
    local best, bd = nil, math.huge
    for _, e in ipairs(folder:GetChildren()) do
        local h, p = e:FindFirstChildOfClass("Humanoid"), e:FindFirstChild("HumanoidRootPart")
        if h and p and h.Health > 0 and (e.Name == name or (plain and e.Name:lower():find(name:lower(), 1, true))) then
            local d = (p.Position - r.Position).Magnitude
            if d < bd then best, bd = e, d end
        end
    end
    return best
end

local function pressKey(k)
    local code = typeof(k) == "EnumItem" and k or Enum.KeyCode[k]
    if not code then return end
    VIM:SendKeyEvent(true, code, false, game); task.wait(0.05)
    VIM:SendKeyEvent(false, code, false, game)
end

--------------------------------------------------------------------
-- 4) MOVIMENTO: GoTo (tween no Scripter / andar no Player)
--------------------------------------------------------------------
-- Entradas/teleporters do jogo (do Relz Hub): usa o remote requestEntrance
local Teleporters = {
    Sea1 = {
        Sky3 = Vector3.new(-7894, 5547, -380), Sky3Exit = Vector3.new(-4607, 874, -1667),
        UnderWater = Vector3.new(61163, 11, 1819), UnderwaterExit = Vector3.new(4050, -1, -1814),
        PirateVillage = Vector3.new(-1242.5, 4.8, 3901.3),
    },
    Sea2 = {
        SwanMansion = Vector3.new(-390, 332, 673), SwanRoom = Vector3.new(2285, 15, 905),
        CursedShip = Vector3.new(923, 126, 32852), ZombieIsland = Vector3.new(-6509, 83, -133),
    },
    Sea3 = {
        FloatingTurtle = Vector3.new(-12462, 375, -7552), HydraIsland = Vector3.new(5657.9, 1013.1, -335.5),
        Castle = Vector3.new(-5036, 315, -3179), DimensionalShift = Vector3.new(-2097.3, 4776.2, -15013.5),
        BeautifulPirate = Vector3.new(5319, 23, -93), TempleOfTime = Vector3.new(28286, 14897, 103),
    },
}
local function nearestTeleporter(targetPos)
    if targetPos.Y < -60 then return nil end
    local list = Teleporters[World]; local r = hrp()
    if not (list and r) then return nil end
    local minD, best = math.huge, nil
    for _, v in pairs(list) do
        local d = (v - targetPos).Magnitude
        if d < minD then minD, best = d, v end
    end
    if best and minD <= (targetPos - r.Position).Magnitude then return best end
end

local function ensureFloat()
    local r = hrp(); if not r then return end
    if not r:FindFirstChild(FLY_TAG) then
        local bv = Instance.new("BodyVelocity")
        bv.Name = FLY_TAG; bv.MaxForce = Vector3.new(1e5, 1e5, 1e5); bv.Velocity = Vector3.zero
        bv.Parent = r
    end
end

local function noclipStep()
    local c = char(); if not c then return end
    for _, p in ipairs(c:GetDescendants()) do
        if p:IsA("BasePart") and p.CanCollide then p.CanCollide = false end
    end
end

-- Chamado no Start das funções de farm: noclip + limpeza (só no Scripter)
function Hub.StartBody(jan)
    if Hub.Mode ~= "Scripter" then return end
    jan:Add(RunService.Stepped:Connect(noclipStep))
    jan:Add(function() clearFlight() end)
end

-- keep(): devolve false para abortar (ex.: função desligada)
-- force: usa tween mesmo no modo Player (teleportes do menu)
function Hub.GoTo(cf, keep, force)
    keep = keep or function() return true end
    local r, h = hrp(), hum()
    if not (r and h and h.Health > 0) then return end
    local pos = cf.Position

    if Hub.Mode == "Scripter" or force then
        local dist = (pos - r.Position).Magnitude
        if dist > 500 then
            local tp = nearestTeleporter(pos)
            if tp then
                Invoke("requestEntrance", tp)
                r = hrp(); if not r then return end
                r.CFrame = r.CFrame + Vector3.new(0, 50, 0)
                task.wait(0.5)
                r = hrp(); if not r then return end
                dist = (pos - r.Position).Magnitude
            end
        end
        ensureFloat()
        if dist <= 80 then
            r.CFrame = cf
            r.AssemblyLinearVelocity = Vector3.zero
            return
        end
        local nc = RunService.Stepped:Connect(noclipStep)
        local tween = TweenService:Create(r, TweenInfo.new(dist / math.max(Hub.Config.TweenSpeed, 30), Enum.EasingStyle.Linear), { CFrame = cf })
        local done = false
        local cc = tween.Completed:Connect(function() done = true end)
        tween:Play()
        while not done and keep() do task.wait() end
        if not done then tween:Cancel() end
        cc:Disconnect(); nc:Disconnect()
        local r2 = hrp(); if r2 then r2.AssemblyLinearVelocity = Vector3.zero end
    else
        -- Player: anda de verdade (física normal)
        local t0 = os.clock()
        while keep() and os.clock() - t0 < 25 do
            local r2 = hrp(); if not r2 then return end
            local flat = Vector3.new(pos.X - r2.Position.X, 0, pos.Z - r2.Position.Z)
            if flat.Magnitude < 6 then break end
            h:MoveTo(pos)
            local wall = Workspace:FindPartOnRay(Ray.new(r2.Position, flat.Unit * 4 + Vector3.new(0, 1, 0)), char())
            if wall and wall.CanCollide then h.Jump = true end
            task.wait(0.1)
        end
        h:Move(Vector3.zero)
    end
end

--------------------------------------------------------------------
-- 5) COMBATE: haki, equipar, bater, skills, farmar um mob
--------------------------------------------------------------------
local lastHaki = 0
function Hub.Haki()
    local c = char()
    if c and not c:FindFirstChild("HasBuso") and os.clock() - lastHaki > 3 then
        lastHaki = os.clock()
        task.spawn(Invoke, "Buso")
    end
end

function Hub.EquipTip(tip)
    local c, h = char(), hum()
    if not (c and h) then return end
    local cur = c:FindFirstChildOfClass("Tool")
    if cur and cur.ToolTip == tip then return end
    local tool = findTool(tip)
    if tool then pcall(function() h:EquipTool(tool) end) end
end

local function closestEnemies(distance)
    local folder, r = enemiesFolder(), hrp()
    if not (folder and r) then return nil end
    local target, others = nil, {}
    for _, e in ipairs(folder:GetChildren()) do
        local er, eh = e:FindFirstChild("HumanoidRootPart"), e:FindFirstChildOfClass("Humanoid")
        if er and eh and eh.Health > 0 and (er.Position - r.Position).Magnitude < distance then
            if not target then target = er else table.insert(others, { e, er }) end
        end
    end
    return target, others
end

-- Um "golpe": ativa a ferramenta; no Scripter também registra o hit via Net
function Hub.Hit()
    local c = char(); if not c then return end
    local tool = c:FindFirstChildOfClass("Tool")
    if tool then
        pcall(function() tool:Activate() end)
        if tool.ToolTip == "Blox Fruit" then
            local lc = tool:FindFirstChild("LeftClickRemote")
            if lc then
                pcall(function()
                    lc:FireServer(Vector3.new(0.01, -500, 0.01), 1, true)
                    lc:FireServer(false)
                end)
            end
        end
    end
    if Hub.Mode == "Scripter" and RegisterAttack and RegisterHit then
        pcall(function()
            local target, others = closestEnemies(Hub.Config.AttackAuraDist)
            if target then
                RegisterAttack:FireServer(0)
                RegisterHit:FireServer(target, others)
            end
        end)
    else
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:Button1Down(Vector2.new(1280, 672))
        end)
    end
end

function Hub.UseSkills(tip)
    local keys = (tip == "Gun") and Hub.Config.GunSkills or Hub.Config.SkillKeys
    for _, k in ipairs(keys) do pressKey(k) end
end

-- posição "em pé" em relação ao mob (acima dele no Scripter; em cima no Player)
function Hub.StandCF(r)
    if Hub.Mode ~= "Scripter" then return r.CFrame end
    local d = Hub.Config.FarmDistance
    if Hub.Config.SpinPosition then
        local a = math.rad((os.clock() * 360) % 360)
        return r.CFrame * CFrame.new(math.cos(a) * 20, d, math.sin(a) * 20)
    end
    return r.CFrame * CFrame.new(0, d, 0)
end

local function mobAlive(mob)
    local h = mob and mob:FindFirstChildOfClass("Humanoid")
    return h and h.Health > 0 and mob:FindFirstChild("HumanoidRootPart") and mob.Parent
end

-- farma um mob até morrer (ou keep() virar false)
function Hub.FarmMob(mob, keep, tip)
    while keep() and mobAlive(mob) do
        local r = mob.HumanoidRootPart
        if Hub.Config.AutoHaki then Hub.Haki() end
        Hub.EquipTip(tip or Hub.Config.Weapon)
        Hub.MonFarm, Hub.PosMon = mob.Name, r.CFrame
        Hub.GoTo(Hub.StandCF(r), keep)
        Hub.Hit()
        task.wait()
    end
end

-- farma um mob com troca por HP (maestria): bate normal e, quando o mob
-- chega em MasteryHealth%, usa o item da vez (espada/arma/fruta) + skills
function Hub.MasteryFight(mob, keep, state)
    while keep() and mobAlive(mob) do
        local r, h = mob.HumanoidRootPart, mob:FindFirstChildOfClass("Humanoid")
        if os.clock() - state.t0 > Hub.Config.SwitchEvery then
            state.idx = state.idx % #state.order + 1; state.t0 = os.clock()
        end
        if Hub.Config.AutoHaki then Hub.Haki() end
        Hub.MonFarm, Hub.PosMon = mob.Name, r.CFrame
        Hub.GoTo(Hub.StandCF(r), keep)
        local pct = h.Health / math.max(h.MaxHealth, 1) * 100
        if pct <= Hub.Config.MasteryHealth then
            local tip = state.order[state.idx]
            Hub.EquipTip(tip)
            Hub.UseSkills(tip)
            Hub.Hit()
        else
            Hub.EquipTip(Hub.Config.Weapon)
            Hub.Hit()
        end
        task.wait()
    end
end

-- Passo do "Auto Farm Level": pega quest, vai ao mob e chama fight(mob)
function Hub.LevelStep(keep, fight)
    local q = Hub:GetQuest(level())
    if not q then return false end
    local mon, qname, qlvl, qpos, mpos = q[3], q[4], q[5], q[6], q[7]
    local qf
    pcall(function() qf = LP.PlayerGui.Main.Quest end)
    local visible = qf and qf.Visible
    if visible then
        local ok, title = pcall(function() return qf.Container.QuestTitle.Title.Text end)
        if ok and not string.find(title, mon, 1, true) then
            Invoke("AbandonQuest")
            return true
        end
    else
        Hub.GoTo(CFrame.new(qpos), keep)
        if keep() then Invoke("StartQuest", qname, qlvl) end
        return true
    end
    local mob = findMobByName(mon)
    if mob then
        fight(mob)
    else
        local up = (Hub.Mode == "Scripter") and Hub.Config.FarmDistance or 0
        Hub.GoTo(CFrame.new(mpos + Vector3.new(0, up, 0)), keep)
    end
    return true
end

local function needWorld(self)
    if World then return false end
    warn("[Phynton] mapa não reconhecido (Sea1/2/3). Função desligada.")
    task.defer(function() self:Set(false) end)
    return true
end

--------------------------------------------------------------------
-- FUNÇÕES DE FARM
--------------------------------------------------------------------
Hub:Register("AutoFarmLevel", function(self, jan)
    if needWorld(self) then return end
    Hub.StartBody(jan)
    local function keep() return self.On end
    self:Loop(Hub.Config.Delay, function()
        Hub.LevelStep(keep, function(mob) Hub.FarmMob(mob, keep) end)
    end)
end, nil, true)

Hub:Register("FarmNearest", function(self, jan)
    Hub.StartBody(jan)
    local function keep() return self.On end
    self:Loop(Hub.Config.Delay, function()
        local mob = nearestEnemy(5000)
        if mob then Hub.FarmMob(mob, keep) end
    end)
end, nil, true)

Hub:Register("MasteryFarm", function(self, jan)
    Hub.StartBody(jan)
    local order = {}
    for tip, on in pairs(Hub.Config.MasteryTypes) do if on then table.insert(order, tip) end end
    table.sort(order)
    if #order == 0 then
        warn("[Phynton] escolha ao menos um tipo de maestria")
        task.defer(function() self:Set(false) end)
        return
    end
    if Hub.Config.MasteryMethod == "Level" and needWorld(self) then return end
    local state = { order = order, idx = 1, t0 = os.clock() }
    local function keep() return self.On end
    self:Loop(Hub.Config.Delay, function()
        if Hub.Config.MasteryMethod == "Nearest" then
            local mob = nearestEnemy(5000)
            if mob then Hub.MasteryFight(mob, keep, state) end
        else
            Hub.LevelStep(keep, function(mob) Hub.MasteryFight(mob, keep, state) end)
        end
    end)
end, nil, true)

Hub:Register("BossFarm", function(self, jan)
    if needWorld(self) then return end
    Hub.StartBody(jan)
    local function keep() return self.On end
    self:Loop(0.4, function()
        local names = Hub.Config.BossAll and Hub.Bosses[World] or { Hub.Config.Boss }
        for _, name in ipairs(names) do
            if name then
                local b = findMobByName(name)
                if b then Hub.FarmMob(b, keep); return end
            end
        end
    end)
end, nil, true)

Hub:Register("AttackAura", function(self, jan)
    self:Loop(0.1, function() Hub.Hit() end)
end, nil, true)

-- Traz os mobs do tipo que está sendo farmado até você (só no Scripter)
Hub:Register("BringMob", function(self, jan)
    jan:Add(RunService.Heartbeat:Connect(function()
        if Hub.Mode ~= "Scripter" or not Hub.Config.BringMob or not (Hub.MonFarm and Hub.PosMon) then return end
        local anyFarm = false
        for _, n in ipairs({ "AutoFarmLevel", "FarmNearest", "MasteryFarm", "BossFarm", "SeaFarm" }) do
            if Hub.Features[n] and Hub.Features[n].On then anyFarm = true; break end
        end
        if not anyFarm then return end
        local r, folder = hrp(), enemiesFolder()
        if not (r and folder) then return end
        for _, v in ipairs(folder:GetChildren()) do
            local vr, vh = v:FindFirstChild("HumanoidRootPart"), v:FindFirstChildOfClass("Humanoid")
            if vr and vh and v.Name == Hub.MonFarm and vh.Health > 0
                and (vr.Position - r.Position).Magnitude <= Hub.Config.BringDistance then
                vr.CFrame = Hub.PosMon
                vr.CanCollide = false
                vh.WalkSpeed = 0
                if sethiddenproperty then
                    pcall(sethiddenproperty, LP, "SimulationRadius", math.huge)
                end
            end
        end
    end))
end, nil, false)

-- Eventos do mar: ataca inimigos cujo nome contém as palavras escolhidas
Hub:Register("SeaFarm", function(self, jan)
    Hub.StartBody(jan)
    local function keep() return self.On end
    self:Loop(0.3, function()
        for _, kw in ipairs(Hub.Config.SeaNames) do
            local mob = findMobByName(kw, true)
            if not mob then
                local sb = Workspace:FindFirstChild("SeaBeasts")
                if sb then
                    for _, b in ipairs(sb:GetChildren()) do
                        if mobAlive(b) and b.Name:lower():find(kw:lower(), 1, true) then mob = b; break end
                    end
                end
            end
            if mob then Hub.FarmMob(mob, keep); return end
        end
    end)
end, nil, true)

-- Coletar baús (o mais próximo)
local function nearestChest()
    local r = hrp(); if not r then return nil end
    local best, bd = nil, math.huge
    for _, v in ipairs(Workspace:GetChildren()) do
        if v:IsA("BasePart") and v.Name:find("Chest") then
            local d = (v.Position - r.Position).Magnitude
            if d < bd then best, bd = v, d end
        end
    end
    return best
end
Hub:Register("ChestFarm", function(self, jan)
    Hub.StartBody(jan)
    local function keep() return self.On end
    self:Loop(0.3, function()
        local c = nearestChest()
        if c then Hub.GoTo(c.CFrame, keep) end
    end)
end, nil, true)

-- Coletar frutas soltas no mapa
Hub:Register("FruitCollect", function(self, jan)
    Hub.StartBody(jan)
    local function keep() return self.On end
    self:Loop(0.5, function()
        for _, v in ipairs(Workspace:GetChildren()) do
            if v:IsA("Tool") and v.Name:find("Fruit") and v:FindFirstChild("Handle") then
                Hub.GoTo(v.Handle.CFrame, keep)
                return
            end
        end
    end)
end, nil, true)

Hub:Register("RandomFruit", function(self, jan)
    self:Loop(1, function() Invoke("Cousin", "Buy") end)
end)

Hub:Register("AutoStats", function(self, jan)
    self:Loop(0.5, function()
        local pts = 0
        pcall(function() pts = LP.Data.Points.Value end)
        if pts <= 0 then return end
        for stat, on in pairs(Hub.Config.Stats) do
            if on then Invoke("AddPoint", stat, Hub.Config.PointStats) end
        end
    end)
end)


--------------------------------------------------------------------
-- 4) COMBAT AI (PLAYER x SCRIPTER)
--------------------------------------------------------------------
Hub:Register("CombatAI", function(self, jan)
    jan:Add(function()
        local h = hum(); if h then h:Move(Vector3.zero) end
        clearFlight()
    end)

    self:Loop(0.06, function()
        if not self.On then return end
        local h, r = hum(), hrp()
        if not h or not r then return end

        local enemy = nearestEnemy(2000)
        if not enemy then h:Move(Vector3.zero); return end
        local eRoot = enemy:FindFirstChild("HumanoidRootPart")
        if not eRoot then return end

        local myPos = r.Position
        local ePos  = eRoot.Position
        local flat  = Vector3.new(ePos.X - myPos.X, 0, ePos.Z - myPos.Z)
        local dist  = flat.Magnitude

        if Hub.Mode == "Player" then
            if r:FindFirstChild(FLY_TAG) then clearFlight() end

            if dist > 8 and flat.Magnitude > 0.1 then
                h:Move(flat.Unit, false)

                local now = tick()
                if dist > Hub.Config.DashRange and (now - (self.LastDash or 0) > Hub.Config.DashCooldown) then
                    pressKey("Q"); self.LastDash = now
                end

                local aheadRay = Ray.new(myPos, flat.Unit * 6 + Vector3.new(0, -3, 0))
                local aheadHit = workspace:FindPartOnRay(aheadRay, char())
                if aheadHit and aheadHit.CanCollide and aheadHit.Parent ~= char() then
                    h.Jump = true
                end
                local wallRay = Ray.new(myPos, flat.Unit * 4 + Vector3.new(0, 2, 0))
                local wallHit = workspace:FindPartOnRay(wallRay, char())
                if wallHit and wallHit.CanCollide then h.Jump = true end
            else
                h:Move(Vector3.zero)
            end
        else
            local targetPos = ePos + Vector3.new(0, Hub.Config.HoverHeight, 0)
            local delta = targetPos - myPos
            local step = delta.Magnitude > Hub.Config.MaxFlyStep and delta.Unit * Hub.Config.MaxFlyStep or delta
            r.CFrame = CFrame.new(myPos + step, ePos)
            r.AssemblyLinearVelocity = Vector3.zero
        end

        if dist < Hub.Config.AttackRange then
            local t = char() and char():FindFirstChildOfClass("Tool")
            if t then pcall(function() t:Activate() end) end
            local now = tick()
            if now - (self.LastSkill or 0) > Hub.Config.SkillCooldown then
                for _, k in ipairs(Hub.Config.SkillKeys) do
                    if not self.On then return end
                    pressKey(k)
                end
                self.LastSkill = now
            end
        end
    end)
end)


--------------------------------------------------------------------
-- 6) MIRAGE HUNT
--------------------------------------------------------------------
local function getVehicleSeat()
    local h = hum()
    if h and h.SeatPart and h.SeatPart:IsA("VehicleSeat") then
        return h.SeatPart
    end
    return nil
end

local function findMirage()
    local key = Hub.Config.Mirage.SearchName:lower()
    for _, obj in ipairs(workspace:GetChildren()) do
        if obj.Name:lower():find(key) then return obj end
    end
    return nil
end

Hub:Register("MirageHunt", function(self, jan)
    local startTime       = tick()
    local lastOscillation = 0
    local direction       = 1
    local mirageFound     = false

    jan:Add(function()
        local seat = getVehicleSeat()
        if seat then pcall(function() seat.Throttle = 0; seat.Steer = 0 end) end
        local h = hum(); if h then h:Move(Vector3.zero) end
        clearFlight()
    end)

    self:Loop(0.1, function()
        if not self.On then return end

        if not mirageFound then
            local mirage = findMirage()
            if mirage then
                mirageFound = true
                self:Set(false)
                if G.PhyntonFluent then
                    G.PhyntonFluent:Notify({
                        Title = "Phynton Hub",
                        Content = "Mirage encontrada! (" .. mirage.Name .. ")",
                        Duration = 6
                    })
                end
                return
            end
        end

        local seat = getVehicleSeat()
        local h, r = hum(), hrp()
        if not (h and r) then return end

        local elapsed      = tick() - startTime
        local isApproaching = elapsed < Hub.Config.Mirage.ApproachTime

        if Hub.Mode == "Player" then
            if seat then
                seat.Throttle = 1
                if isApproaching then
                    seat.Steer = 0
                else
                    if tick() - lastOscillation > Hub.Config.Mirage.OscillationInterval then
                        direction = -direction
                        lastOscillation = tick()
                    end
                    seat.Steer = direction
                end
            else
                if isApproaching then
                    h:Move(Vector3.new(0, 0, -1), false)
                else
                    if tick() - lastOscillation > Hub.Config.Mirage.OscillationInterval then
                        direction = -direction
                        lastOscillation = tick()
                    end
                    h:Move(Vector3.new(direction * 0.7, 0, -0.7), false)
                end
            end
        else
            local cam     = workspace.CurrentCamera
            local forward = cam.CFrame.LookVector
            local right   = cam.CFrame.RightVector
            local moveDir
            if isApproaching then
                moveDir = forward
            else
                if tick() - lastOscillation > Hub.Config.Mirage.OscillationInterval then
                    direction = -direction
                    lastOscillation = tick()
                end
                moveDir = (forward + right * direction).Unit
            end
            r.CFrame = CFrame.new(r.Position + moveDir * 8)
            r.AssemblyLinearVelocity = Vector3.zero
        end
    end)
end)


--------------------------------------------------------------------
-- 7) RECORD/REPLAY (mimic de movimento)
--------------------------------------------------------------------
local Rec = { segments = {}, MAX = 400 }
local function anyFeatureOn()
    for n, f in pairs(Hub.Features) do
        if f.On and n ~= "MoveRecorder" and n ~= "MoveAI" and n ~= "CombatAI" and n ~= "MirageHunt" then
            return true
        end
    end
    return false
end

Hub:Register("MoveRecorder", function(self, jan)
    local cam = workspace.CurrentCamera
    local seg
    jan:Add(RunService.Heartbeat:Connect(function(dt)
        if anyFeatureOn() or Hub.Features.MoveAI.On or Hub.Features.CombatAI.On then seg = nil; return end
        local h = hum(); if not h then return end
        local d = h.MoveDirection
        local rel = d.Magnitude > 0.1 and cam.CFrame:VectorToObjectSpace(d) or Vector3.zero
        local key = string.format("%.1f_%.1f_%s", rel.X, rel.Z, tostring(h.Jump))
        if seg and seg.key == key then
            seg.t += dt
        else
            if seg and seg.t > 0.05 then
                table.insert(Rec.segments, seg)
                if #Rec.segments > Rec.MAX then table.remove(Rec.segments, 1) end
            end
            seg = { key = key, dir = rel, jump = h.Jump, t = 0 }
        end
    end))
end)

Hub.Profiles = {
    Sharkizim = {
        { 0, 1, false, 0.35 }, { 1, 1, true, 0.25 }, { -1, 1, false, 0.3 },
        { 0, -1, false, 0.2 }, { 1, 0, true, 0.3 },
    },
}
Hub.ActiveProfile = "Sharkizim"

Hub:Register("MoveAI", function(self, jan)
    local cam = workspace.CurrentCamera
    jan:Add(function() local h = hum(); if h then h:Move(Vector3.zero) end end)
    self:Loop(0, function()
        if Hub.Features.CombatAI.On then return end
        local h = hum(); if not h then task.wait(0.2) return end
        local x, z, jump, dur
        if Hub.ActiveProfile == "Gravado" and #Rec.segments > 0 then
            local s = Rec.segments[math.random(#Rec.segments)]
            x, z, jump, dur = s.dir.X, s.dir.Z, s.jump, s.t
        else
            local p = Hub.Profiles[Hub.ActiveProfile] or Hub.Profiles.Sharkizim
            local s = p[math.random(#p)]
            x, z, jump, dur = s[1], s[2], s[3], s[4]
        end
        dur = math.clamp(dur * (0.85 + math.random() * 0.3), 0.1, 1.5)
        local t0 = os.clock()
        while self.On and os.clock() - t0 < dur do
            local dir = cam.CFrame:VectorToWorldSpace(Vector3.new(x, 0, z))
            h:Move(Vector3.new(dir.X, 0, dir.Z), false)
            if jump then h.Jump = true end
            RunService.Heartbeat:Wait()
        end
    end)
end)

task.defer(function() Hub.Features.MoveRecorder:Set(true) end)


--------------------------------------------------------------------
-- 8) OTIMIZAÇÃO VISUAL
--------------------------------------------------------------------
local Orig = {
    FogStart      = Lighting.FogStart,
    FogEnd        = Lighting.FogEnd,
    Brightness    = Lighting.Brightness,
    Ambient       = Lighting.Ambient,
    GlobalShadows = Lighting.GlobalShadows,
}

Hub:Register("RemoveFog", function(self, jan)
    jan:Add(function()
        Lighting.FogStart = Orig.FogStart
        Lighting.FogEnd   = Orig.FogEnd
    end)
    Lighting.FogStart = 0
    Lighting.FogEnd   = 100000
end)

Hub:Register("Fullbright", function(self, jan)
    jan:Add(function()
        Lighting.Brightness = Orig.Brightness
        Lighting.Ambient    = Orig.Ambient
    end)
    Lighting.Brightness = 2
    Lighting.Ambient    = Color3.fromRGB(255, 255, 255)
end)

Hub:Register("NoShadows", function(self, jan)
    jan:Add(function() Lighting.GlobalShadows = Orig.GlobalShadows end)
    Lighting.GlobalShadows = false
end)

Hub:Register("NoParticles", function(self, jan)
    local touched = {}
    local function scan()
        for _, v in ipairs(workspace:GetDescendants()) do
            if v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Smoke")
                or v:IsA("Fire") or v:IsA("Sparkles") then
                if v.Enabled then
                    v.Enabled = false
                    table.insert(touched, v)
                end
            end
        end
    end
    scan()
    self:Loop(2, scan) -- leve: varre a cada 2s, não a cada frame
    jan:Add(function()
        for _, v in ipairs(touched) do pcall(function() v.Enabled = true end) end
    end)
end)

Hub:Register("NoCameraEffects", function(self, jan)
    local touched = {}
    local function scan()
        for _, v in ipairs(Lighting:GetChildren()) do
            if v:IsA("PostEffect") and v.Enabled then
                v.Enabled = false
                table.insert(touched, v)
            end
        end
    end
    scan()
    self:Loop(2, scan) -- leve: varre a cada 2s, não a cada frame
    jan:Add(function()
        for _, v in ipairs(touched) do pcall(function() v.Enabled = true end) end
    end)
end)

Hub:Register("FastMode", function(self, jan)
    local sg = Instance.new("ScreenGui")
    sg.Name = "PhyntonFastMode"
    sg.ResetOnSpawn = false
    sg.Parent = (gethui and gethui()) or game:GetService("CoreGui") or LP:WaitForChild("PlayerGui")
    local fr = Instance.new("Frame")
    fr.Size = UDim2.new(1, 0, 1, 0)
    fr.BackgroundColor3 = Color3.new(0, 0, 0)
    fr.BackgroundTransparency = 1
    fr.Parent = sg
    jan:Add(sg)
end)



Hub.Features.CombatAI.ModeAware = true
Hub.Features.MirageHunt.ModeAware = true

--------------------------------------------------------------------
-- 6) JOGADOR (velocidade, pulo, noclip, água, raça)
--------------------------------------------------------------------
Hub:Register("WalkSpeed", function(self, jan)
    jan:Add(RunService.Heartbeat:Connect(function()
        local h = hum(); if h then h.WalkSpeed = Hub.Config.WalkSpeed end
    end))
end, function() local h = hum(); if h then h.WalkSpeed = 16 end end)

Hub:Register("JumpPower", function(self, jan)
    jan:Add(RunService.Heartbeat:Connect(function()
        local h = hum()
        if h then h.UseJumpPower = true; h.JumpPower = Hub.Config.JumpPower end
    end))
end, function() local h = hum(); if h then h.JumpPower = 50 end end)

Hub:Register("NoClip", function(self, jan)
    jan:Add(RunService.Stepped:Connect(noclipStep))
end)

Hub:Register("WalkOnWater", function(self, jan)
    local function setSize(y)
        pcall(function() Workspace.Map["WaterBase-Plane"].Size = Vector3.new(1000, y, 1000) end)
    end
    jan:Add(function() setSize(80) end)
    setSize(112)
end)

Hub:Register("RaceV3", function(self, jan)
    self:Loop(Hub.Config.Delay, function()
        local ce = Remotes and Remotes:FindFirstChild("CommE")
        if ce then ce:FireServer("ActivateAbility") end
    end)
end)

Hub:Register("RaceV4", function(self, jan)
    self:Loop(Hub.Config.Delay, function()
        local c = char(); if not c then return end
        local energy = c:FindFirstChild("RaceEnergy")
        if energy and tonumber(energy.Value) == 1 and c.RaceTransformed.Default == false then
            pressKey("Y")
        end
    end)
end)

--------------------------------------------------------------------
-- 7) ESP (leve: 1 varredura por segundo, tudo removido ao desligar)
--------------------------------------------------------------------
local function makeEsp(name, collect)
    Hub:Register(name, function(self, jan)
        local made = {}
        jan:Add(function()
            for _, g in pairs(made) do pcall(function() g:Destroy() end) end
        end)
        self:Loop(1, function()
            local seen = {}
            local r = hrp()
            for _, it in ipairs(collect()) do
                local part = it.part
                if part and part.Parent then
                    local g = made[part]
                    if not g or not g.Parent then
                        g = Instance.new("BillboardGui")
                        g.Name = "PhyntonEsp"; g.Size = UDim2.fromOffset(180, 26)
                        g.AlwaysOnTop = true; g.Adornee = part; g.ExtentsOffset = Vector3.new(0, 2, 0)
                        local t = Instance.new("TextLabel")
                        t.Name = "T"; t.Size = UDim2.fromScale(1, 1); t.BackgroundTransparency = 1
                        t.TextColor3 = it.color or Color3.new(1, 1, 1); t.TextStrokeTransparency = 0.5
                        t.Font = Enum.Font.GothamBold; t.TextSize = 13; t.Parent = g
                        g.Parent = part
                        made[part] = g
                    end
                    local d = r and math.floor((part.Position - r.Position).Magnitude / 3) or 0
                    g.T.Text = it.text .. " [" .. d .. "m]"
                    seen[part] = true
                end
            end
            for part, g in pairs(made) do
                if not seen[part] then pcall(function() g:Destroy() end); made[part] = nil end
            end
        end)
    end)
end

makeEsp("EspPlayer", function()
    local out = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LP and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
            table.insert(out, { part = p.Character.HumanoidRootPart, text = p.Name, color = Color3.fromRGB(255, 90, 90) })
        end
    end
    return out
end)
makeEsp("EspFruit", function()
    local out = {}
    for _, v in ipairs(Workspace:GetChildren()) do
        if v:IsA("Tool") and v.Name:find("Fruit") and v:FindFirstChild("Handle") then
            table.insert(out, { part = v.Handle, text = v.Name, color = Color3.fromRGB(255, 200, 60) })
        end
    end
    return out
end)
makeEsp("EspChest", function()
    local out = {}
    for _, v in ipairs(Workspace:GetChildren()) do
        if v:IsA("BasePart") and v.Name:find("Chest") then
            table.insert(out, { part = v, text = v.Name, color = Color3.fromRGB(120, 220, 255) })
        end
    end
    return out
end)
makeEsp("EspBoss", function()
    local out, names = {}, (World and Hub.Bosses[World]) or {}
    local folder = enemiesFolder()
    if not folder then return out end
    for _, e in ipairs(folder:GetChildren()) do
        if table.find(names, e.Name) and e:FindFirstChild("HumanoidRootPart") then
            table.insert(out, { part = e.HumanoidRootPart, text = e.Name, color = Color3.fromRGB(255, 120, 255) })
        end
    end
    return out
end)

--------------------------------------------------------------------
-- 8) EVENTO: abóboras e doces (procura por nome; palavras editáveis)
--------------------------------------------------------------------
Hub.EventCfg = {
    Pumpkin = { "pumpkin", "abobora", "abóbora" },
    Candy = { "candy", "candies", "doce", "sweet", "lollipop" },
}

local function nameMatches(name, pats)
    name = name:lower()
    for _, p in ipairs(pats) do
        if name:find(p:lower(), 1, true) then return true end
    end
    return false
end

local function isOwnOrEnemy(inst)
    local c = char()
    if c and inst:IsDescendantOf(c) then return true end
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl.Character and inst:IsDescendantOf(pl.Character) then return true end
    end
    local en = enemiesFolder()
    return en ~= nil and inst:IsDescendantOf(en)
end

local function eventPart(inst)
    if inst:IsA("BasePart") then return inst end
    if inst:IsA("Model") then return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart") end
end

local function scanEvent(pats)
    local r = hrp(); if not r then return end
    local best, bd, names = nil, math.huge, {}
    for _, inst in ipairs(Workspace:GetDescendants()) do
        if (inst:IsA("BasePart") or inst:IsA("Model")) and nameMatches(inst.Name, pats)
            and not isOwnOrEnemy(inst) then
            local part = eventPart(inst)
            if part and part.Parent then
                names[inst.Name] = (names[inst.Name] or 0) + 1
                local d = (part.Position - r.Position).Magnitude
                if d < bd then best, bd = part, d end
            end
        end
    end
    return best, names
end
Hub.ScanEvent = scanEvent

local function collectEvent(part, keep)
    local r = hrp(); if not (r and part and part.Parent) then return end
    local done = false
    if firetouchinterest and part:FindFirstChildWhichIsA("TouchInterest", true) then
        pcall(function() firetouchinterest(r, part, 0); firetouchinterest(r, part, 1) end)
        done = true
    end
    local pp = part:FindFirstChildWhichIsA("ProximityPrompt", true)
        or (part.Parent and part.Parent:FindFirstChildWhichIsA("ProximityPrompt", true))
    if pp and fireproximityprompt then
        pcall(fireproximityprompt, pp); done = true
    end
    if not done then Hub.GoTo(part.CFrame + Vector3.new(0, 3, 0), keep) end
end

local function registerEventFarm(name, key)
    Hub:Register(name, function(self, jan)
        Hub.StartBody(jan)
        local function keep() return self.On end
        self:Loop(0.5, function()
            local part = scanEvent(Hub.EventCfg[key])
            if part then collectEvent(part, keep) end
        end)
    end, nil, true)
end
registerEventFarm("PumpkinFarm", "Pumpkin")
registerEventFarm("CandyFarm", "Candy")

--------------------------------------------------------------------
-- 9) TELEPORTE, LOJA, SERVIDOR, FPS
--------------------------------------------------------------------
function Hub.TeleportIsland(name)
    local isl = Hub.Islands[name]
    if not isl then return false end
    if isl.entrance then
        Invoke("requestEntrance", isl.entrance)
    elseif isl.pos then
        task.spawn(function()
            Hub.GoTo(CFrame.new(isl.pos), nil, true)
            if Hub.Mode == "Player" then clearFlight() end
        end)
    end
    return true
end

function Hub.TeleportPlayer(name)
    local p = Players:FindFirstChild(name)
    local r = p and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
    if not r then return false end
    task.spawn(function()
        Hub.GoTo(r.CFrame, nil, true)
        if Hub.Mode == "Player" then clearFlight() end
    end)
    return true
end

Hub.Shop = {
    { "Black Leg",       { "BuyBlackLeg" } },
    { "Electro",         { "BuyElectro" } },
    { "Fishman Karate",  { "BuyFishmanKarate" } },
    { "Dragon Claw",     { "BlackbeardReward", "DragonClaw", "2" } },
    { "Superhuman",      { "BuySuperhuman" } },
    { "Death Step",      { "BuyDeathStep" } },
    { "Sharkman Karate", { "BuySharkmanKarate" } },
    { "Electric Claw",   { "BuyElectricClaw" } },
    { "Dragon Talon",    { "BuyDragonTalon" } },
    { "God Human",       { "BuyGodhuman" } },
    { "Sanguine Art",    { "BuySanguineArt" } },
    { "Haki Color",      { "ColorsDealer", "2" } },
}

function Hub.Redeem()
    local n = 0
    local rem = Remotes and Remotes:FindFirstChild("Redeem")
    if not rem then return 0 end
    for _, code in ipairs(Hub.Codes) do
        pcall(function() rem:InvokeServer(code) end)
        n += 1
    end
    return n
end

function Hub.Rejoin()
    TeleportService:Teleport(game.PlaceId, LP)
end

function Hub.Hop()
    local ok, data = pcall(function()
        return HttpService:JSONDecode(game:HttpGet(
            ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100"):format(game.PlaceId)))
    end)
    if not (ok and data and data.data) then return false end
    for _, s in ipairs(data.data) do
        if s.id ~= game.JobId and s.playing < s.maxPlayers then
            TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id, LP)
            return true
        end
    end
    return false
end

function Hub.BoostFps()
    pcall(function() settings().Rendering.QualityLevel = "Level01" end)
    for _, v in ipairs(game:GetDescendants()) do
        if v:IsA("BasePart") then
            v.Material = Enum.Material.Plastic; v.Reflectance = 0
        elseif v:IsA("Decal") or v:IsA("Texture") then
            v.Transparency = 1
        elseif v:IsA("ParticleEmitter") or v:IsA("Trail") then
            v.Lifetime = NumberRange.new(0)
        elseif v:IsA("Fire") or v:IsA("SpotLight") or v:IsA("Smoke") then
            v.Enabled = false
        end
    end
end

-- liga a BringMob por padrão (ela só age quando uma função de farm está ativa)
task.defer(function() Hub.Features.BringMob:Set(true) end)


--------------------------------------------------------------------
-- 10) NOVA GUI PHYNTON HUB v4 (integrada à arquitetura original)
--------------------------------------------------------------------
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Camera = Workspace.CurrentCamera
local Sidebar, ContentArea

local Theme = {
    bg = Color3.fromRGB(14, 16, 20),
    panel = Color3.fromRGB(20, 23, 29),
    card = Color3.fromRGB(27, 31, 39),
    cardHover = Color3.fromRGB(35, 41, 51),
    accent = Color3.fromRGB(40, 205, 220),
    accentDark = Color3.fromRGB(22, 105, 119),
    text = Color3.fromRGB(238, 242, 247),
    muted = Color3.fromRGB(155, 166, 180),
    off = Color3.fromRGB(63, 71, 83),
}

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "PhyntonHubGUI"
ScreenGui.ResetOnSpawn = false
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() ScreenGui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
if not ScreenGui.Parent then ScreenGui.Parent = LP:WaitForChild("PlayerGui") end
onCleanup(function() pcall(function() ScreenGui:Destroy() end) end)

local function corner(obj, radius)
    local c = Instance.new("UICorner")
    c.CornerRadius = UDim.new(0, radius or 8)
    c.Parent = obj
    return c
end
local function stroke(obj, color, transparency, thickness)
    local s = Instance.new("UIStroke")
    s.Color = color or Theme.accent
    s.Transparency = transparency or 0.75
    s.Thickness = thickness or 1
    s.Parent = obj
    return s
end
local function make(class, props, parent)
    local obj = Instance.new(class)
    for k, v in pairs(props or {}) do obj[k] = v end
    obj.Parent = parent
    return obj
end
local function label(parent, text, size, color, bold)
    return make("TextLabel", {
        BackgroundTransparency = 1, Text = text or "", TextColor3 = color or Theme.text,
        Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham,
        TextSize = size or 12, TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
    }, parent)
end

local MainFrame = make("Frame", {
    Name = "MainFrame", AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(650, 430),
    BackgroundColor3 = Theme.bg, BorderSizePixel = 0, Active = true,
    ClipsDescendants = true,
}, ScreenGui)
corner(MainFrame, 11)
stroke(MainFrame, Theme.accent, 0.72, 1)

-- Escala global: 30% mantém o tamanho-base; o controle vai de 0% a 100%.
local UiScale = Instance.new("UIScale")
UiScale.Name = "PhyntonUIScale"
UiScale.Scale = 1
UiScale.Parent = MainFrame
local uiScalePercent = 30
local function applyUiScale(value)
    uiScalePercent = math.clamp(math.floor(value + 0.5), 0, 100)
    UiScale.Scale = 0.7 + (uiScalePercent / 100)
end

local function updateResponsive()
    local viewport = (Camera and Camera.ViewportSize) or Vector2.new(800, 600)
    local inset = GuiService:GetGuiInset()
    local maxW = math.max(280, viewport.X - 20)
    local maxH = math.max(260, viewport.Y - inset.Y - 20)
    local scale = math.max(UiScale.Scale, 0.1)
    local width = math.min(650, maxW / scale)
    local height = math.min(430, maxH / scale)
    MainFrame.Size = UDim2.fromOffset(width, height)
    MainFrame.Position = UDim2.new(0.5, 0, 0.5, inset.Y / 2)
    local compact = (width * scale) < 440
    Sidebar.Size = UDim2.new(0, compact and 112 or 158, 1, -48)
    ContentArea.Position = UDim2.new(0, compact and 112 or 158, 0, 44)
    ContentArea.Size = UDim2.new(1, -(compact and 112 or 158), 1, -48)
end

local TopBar = make("Frame", {
    Name = "TopBar", Size = UDim2.new(1, 0, 0, 42),
    BackgroundColor3 = Theme.panel, BorderSizePixel = 0,
}, MainFrame)
local TitleLabel = label(TopBar, "PHYNTON HUB  |  v" .. tostring(Hub.Version) .. "  •  " .. tostring(World or "MAPA DESCONHECIDO"), 13, Theme.accent, true)
TitleLabel.Position = UDim2.fromOffset(14, 0)
TitleLabel.Size = UDim2.new(1, -205, 1, 0)

local CloseBtn = make("TextButton", {
    Size = UDim2.fromOffset(34, 32), Position = UDim2.new(1, -40, 0, 5),
    BackgroundColor3 = Theme.card, BorderSizePixel = 0, Text = "×",
    TextColor3 = Theme.text, Font = Enum.Font.GothamBold, TextSize = 20,
}, TopBar)
corner(CloseBtn, 7)
CloseBtn.Activated:Connect(function() ScreenGui.Enabled = false end)

-- Editor de tamanho da interface, no topo do Hub.
local ScaleLabel = label(TopBar, "UI 30%", 10, Theme.muted, true)
ScaleLabel.AnchorPoint = Vector2.new(1, 0)
ScaleLabel.Position = UDim2.new(1, -82, 0, 3)
ScaleLabel.Size = UDim2.fromOffset(48, 14)
ScaleLabel.TextXAlignment = Enum.TextXAlignment.Right
local ScaleTrack = make("TextButton", {
    Name = "UIScaleTrack", AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -82, 0, 27), Size = UDim2.fromOffset(68, 6),
    BackgroundColor3 = Theme.off, BorderSizePixel = 0, Text = "", AutoButtonColor = false,
}, TopBar)
corner(ScaleTrack, 4)
local ScaleFill = make("Frame", {
    Name = "Fill", Size = UDim2.new(0.3, 0, 1, 0),
    BackgroundColor3 = Theme.accent, BorderSizePixel = 0,
}, ScaleTrack)
corner(ScaleFill, 4)
local ScaleKnob = make("Frame", {
    Name = "Knob", AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.new(0.3, 0, 0.5, 0), Size = UDim2.fromOffset(10, 10),
    BackgroundColor3 = Theme.text, BorderSizePixel = 0,
}, ScaleTrack)
corner(ScaleKnob, 5)
local function updateScaleControl()
    local fraction = uiScalePercent / 100
    ScaleLabel.Text = "UI " .. tostring(uiScalePercent) .. "%"
    ScaleFill.Size = UDim2.new(fraction, 0, 1, 0)
    ScaleKnob.Position = UDim2.new(fraction, 0, 0.5, 0)
end
local function setScaleFromX(x)
    local width = math.max(ScaleTrack.AbsoluteSize.X, 1)
    local fraction = math.clamp((x - ScaleTrack.AbsolutePosition.X) / width, 0, 1)
    applyUiScale(fraction * 100)
    updateScaleControl()
    updateResponsive()
end
local scaling = false
local scaleBeginConn = ScaleTrack.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        scaling = true
        setScaleFromX(input.Position.X)
    end
end)
local scaleMoveConn = UserInputService.InputChanged:Connect(function(input)
    if scaling and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        setScaleFromX(input.Position.X)
    end
end)
local scaleEndConn = UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        scaling = false
    end
end)
onCleanup(function()
    scaleBeginConn:Disconnect(); scaleMoveConn:Disconnect(); scaleEndConn:Disconnect()
end)
applyUiScale(30)
updateScaleControl()

-- Arraste: uma única conexão global, removida no cleanup.
do
    local dragging, dragInput, dragStart, startPos = false, nil, nil, nil
    local beginConn = TopBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging, dragStart, startPos = true, input.Position, MainFrame.Position
            local ended
            ended = input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if ended then ended:Disconnect() end
                end
            end)
        end
    end)
    local changedConn = TopBar.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)
    local globalConn = UserInputService.InputChanged:Connect(function(input)
        if dragging and input == dragInput and dragStart and startPos then
            local delta = input.Position - dragStart
            MainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X,
                startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
    onCleanup(function() beginConn:Disconnect(); changedConn:Disconnect(); globalConn:Disconnect() end)
end

Sidebar = make("ScrollingFrame", {
    Name = "Sidebar", Position = UDim2.fromOffset(0, 44), Size = UDim2.new(0, 158, 1, -48),
    BackgroundColor3 = Theme.panel, BorderSizePixel = 0, ScrollBarThickness = 3,
    ScrollBarImageColor3 = Theme.accent, CanvasSize = UDim2.new(),
}, MainFrame)
local sidePad = Instance.new("UIPadding")
sidePad.PaddingTop = UDim.new(0, 8); sidePad.PaddingBottom = UDim.new(0, 8)
sidePad.PaddingLeft = UDim.new(0, 7); sidePad.PaddingRight = UDim.new(0, 7)
sidePad.Parent = Sidebar
local sideLayout = Instance.new("UIListLayout")
sideLayout.Padding = UDim.new(0, 5); sideLayout.SortOrder = Enum.SortOrder.LayoutOrder
sideLayout.Parent = Sidebar
local sideSizeConn = sideLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    Sidebar.CanvasSize = UDim2.fromOffset(0, sideLayout.AbsoluteContentSize.Y + 18)
end)
onCleanup(function() sideSizeConn:Disconnect() end)

ContentArea = make("Frame", {
    Name = "ContentArea", Position = UDim2.new(0, 158, 0, 44),
    Size = UDim2.new(1, -158, 1, -48), BackgroundTransparency = 1,
}, MainFrame)
local SearchBox = make("TextBox", {
    Name = "SearchBox", Position = UDim2.new(0, 9, 0, 7), Size = UDim2.new(1, -18, 0, 30),
    BackgroundColor3 = Theme.panel, BorderSizePixel = 0, ClearTextOnFocus = false,
    PlaceholderText = "  Buscar categoria ou função...", Text = "", TextColor3 = Theme.text,
    PlaceholderColor3 = Theme.muted, Font = Enum.Font.Gotham, TextSize = 12,
    TextXAlignment = Enum.TextXAlignment.Left,
}, ContentArea)
corner(SearchBox, 7)
local PagesFolder = Instance.new("Folder")
PagesFolder.Name = "Pages"; PagesFolder.Parent = ContentArea

local Pages, TabButtons, SearchItems = {}, {}, {}
local activePage
local function addSearchItem(obj, text)
    obj:SetAttribute("PhyntonSearch", string.lower(tostring(text or "")))
    table.insert(SearchItems, obj)
end

local function CreatePage(name)
    local page = make("ScrollingFrame", {
        Name = name .. "Page", Position = UDim2.new(0, 8, 0, 45),
        Size = UDim2.new(1, -16, 1, -52), BackgroundTransparency = 1,
        BorderSizePixel = 0, ScrollBarThickness = 3, ScrollBarImageColor3 = Theme.accent,
        CanvasSize = UDim2.new(), Visible = false,
    }, ContentArea)
    local pad = Instance.new("UIPadding")
    pad.PaddingBottom = UDim.new(0, 12); pad.PaddingRight = UDim.new(0, 5)
    pad.Parent = page
    local layout = Instance.new("UIListLayout")
    layout.Padding = UDim.new(0, 7); layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Parent = page
    local conn = layout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        page.CanvasSize = UDim2.fromOffset(0, layout.AbsoluteContentSize.Y + 18)
    end)
    onCleanup(function() conn:Disconnect() end)
    Pages[name] = page
    return page
end

local function SelectTab(name)
    if not Pages[name] then return end
    activePage = name
    for tabName, page in pairs(Pages) do page.Visible = tabName == name end
    for tabName, btn in pairs(TabButtons) do
        local selected = tabName == name
        btn.BackgroundColor3 = selected and Theme.accentDark or Theme.card
        btn.TextColor3 = selected and Color3.new(1, 1, 1) or Theme.muted
    end
end

local function AddTabButton(title, targetPage, order)
    local btn = make("TextButton", {
        Name = "Tab_" .. targetPage, Size = UDim2.new(1, 0, 0, 32),
        BackgroundColor3 = Theme.card, BorderSizePixel = 0,
        Font = Enum.Font.GothamMedium, TextSize = 11, TextColor3 = Theme.muted,
        TextXAlignment = Enum.TextXAlignment.Left, Text = "   " .. title,
        LayoutOrder = order or 1, AutoButtonColor = true,
    }, Sidebar)
    corner(btn, 7)
    btn.Activated:Connect(function() SelectTab(targetPage) end)
    TabButtons[targetPage] = btn
    addSearchItem(btn, title)
end

local function notify(msg)
    local toast = make("TextLabel", {
        Size = UDim2.new(1, -24, 0, 34), Position = UDim2.new(0, 12, 1, -46),
        BackgroundColor3 = Theme.panel, BorderSizePixel = 0,
        Text = "  PHYNTON  •  " .. tostring(msg), TextColor3 = Theme.accent,
        Font = Enum.Font.GothamMedium, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Left,
        ZIndex = 20,
    }, MainFrame)
    corner(toast, 7); stroke(toast, Theme.accent, 0.65)
    task.delay(2.8, function() if toast and toast.Parent then toast:Destroy() end end)
end

local function CreateSection(page, titleText)
    local lbl = label(page, string.upper(titleText), 11, Theme.accent, true)
    lbl.Size = UDim2.new(1, -5, 0, 24)
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    addSearchItem(lbl, titleText)
    return lbl
end

local function CreateToggle(page, title, default, callback)
    local card = make("Frame", {
        Size = UDim2.new(1, -5, 0, 40), BackgroundColor3 = Theme.card, BorderSizePixel = 0,
    }, page)
    corner(card, 7)
    local lbl = label(card, title, 11, Theme.text, false)
    lbl.Position = UDim2.fromOffset(11, 0); lbl.Size = UDim2.new(1, -66, 1, 0)
    local state = default == true
    local track = make("Frame", {
        Size = UDim2.fromOffset(38, 20), Position = UDim2.new(1, -49, 0.5, -10),
        BackgroundColor3 = state and Theme.accentDark or Theme.off, BorderSizePixel = 0,
    }, card)
    corner(track, 12)
    local knob = make("Frame", {
        Size = UDim2.fromOffset(14, 14), Position = state and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7),
        BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
    }, track)
    corner(knob, 10)
    local hit = make("TextButton", {
        Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Text = "",
    }, card)
    local function setState(v, silent)
        state = v == true
        track.BackgroundColor3 = state and Theme.accentDark or Theme.off
        knob.Position = state and UDim2.new(1, -17, 0.5, -7) or UDim2.new(0, 3, 0.5, -7)
        if not silent and callback then
            local ok, err = pcall(callback, state)
            if not ok then notify("Erro em " .. title .. ": " .. tostring(err)) end
        end
    end
    hit.Activated:Connect(function() setState(not state, false) end)
    addSearchItem(card, title)
    return { Set = setState, Get = function() return state end }
end

local function CreateButton(page, title, callback)
    local btn = make("TextButton", {
        Size = UDim2.new(1, -5, 0, 36), BackgroundColor3 = Theme.card,
        BorderSizePixel = 0, Font = Enum.Font.GothamMedium, TextSize = 11,
        TextColor3 = Theme.text, TextXAlignment = Enum.TextXAlignment.Left,
        Text = "   " .. title, AutoButtonColor = true,
    }, page)
    corner(btn, 7)
    btn.Activated:Connect(function()
        local ok, err = pcall(callback or function() end)
        if not ok then notify("Falha: " .. tostring(err)) end
    end)
    addSearchItem(btn, title)
    return btn
end

local function CreateSlider(page, title, min, max, default, decimals, callback)
    min, max = tonumber(min) or 0, tonumber(max) or 1
    if max <= min then max = min + 1 end
    default = math.clamp(tonumber(default) or min, min, max)
    local card = make("Frame", {
        Size = UDim2.new(1, -5, 0, 54), BackgroundColor3 = Theme.card, BorderSizePixel = 0,
    }, page)
    corner(card, 7)
    local valueLabel = label(card, title .. ": " .. tostring(default), 11, Theme.text, false)
    valueLabel.Position = UDim2.fromOffset(11, 3); valueLabel.Size = UDim2.new(1, -20, 0, 20)
    local bar = make("TextButton", {
        Size = UDim2.new(1, -22, 0, 8), Position = UDim2.fromOffset(11, 34),
        BackgroundColor3 = Theme.off, BorderSizePixel = 0, Text = "", AutoButtonColor = false,
    }, card)
    corner(bar, 8)
    local pct = (default - min) / (max - min)
    local fill = make("Frame", { Size = UDim2.new(pct, 0, 1, 0), BackgroundColor3 = Theme.accent, BorderSizePixel = 0 }, bar)
    corner(fill, 8)
    local sliding = false
    local function update(x)
        local width = math.max(1, bar.AbsoluteSize.X)
        local p = math.clamp((x - bar.AbsolutePosition.X) / width, 0, 1)
        fill.Size = UDim2.new(p, 0, 1, 0)
        local mult = 10 ^ (decimals or 0)
        local val = math.floor((min + (max - min) * p) * mult + 0.5) / mult
        valueLabel.Text = title .. ": " .. tostring(val)
        if callback then
            local ok, err = pcall(callback, val)
            if not ok then notify("Erro no ajuste: " .. tostring(err)) end
        end
    end
    local began = bar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            sliding = true; update(input.Position.X)
        end
    end)
    local changed = UserInputService.InputChanged:Connect(function(input)
        if sliding and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then update(input.Position.X) end
    end)
    local ended = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then sliding = false end
    end)
    onCleanup(function() began:Disconnect(); changed:Disconnect(); ended:Disconnect() end)
    addSearchItem(card, title)
end

local function CreateDropdown(page, title, values, defaultIdx, callback)
    values = values or {}
    local idx = math.clamp(tonumber(defaultIdx) or 1, 1, math.max(1, #values))
    local function current() return values[idx] or "Indisponível" end
    local btn = make("TextButton", {
        Size = UDim2.new(1, -5, 0, 37), BackgroundColor3 = Theme.card,
        BorderSizePixel = 0, Font = Enum.Font.Gotham, TextSize = 11,
        TextColor3 = Theme.text, TextXAlignment = Enum.TextXAlignment.Left,
        Text = "   " .. title .. "  ›  " .. tostring(current()),
    }, page)
    corner(btn, 7)
    btn.Activated:Connect(function()
        if #values == 0 then notify("Nenhuma opção disponível."); return end
        idx = (idx % #values) + 1
        btn.Text = "   " .. title .. "  ›  " .. tostring(current())
        if callback then
            local ok, err = pcall(callback, current())
            if not ok then notify("Erro na seleção: " .. tostring(err)) end
        end
    end)
    addSearchItem(btn, title .. " " .. table.concat(values, " "))
end

local function CreateInput(page, title, placeholder, callback)
    local card = make("Frame", { Size = UDim2.new(1, -5, 0, 42), BackgroundColor3 = Theme.card, BorderSizePixel = 0 }, page)
    corner(card, 7)
    local lbl = label(card, title, 10, Theme.muted, false)
    lbl.Position = UDim2.fromOffset(10, 0); lbl.Size = UDim2.new(0.38, 0, 1, 0)
    local box = make("TextBox", {
        Size = UDim2.new(0.58, -7, 0, 28), Position = UDim2.new(0.40, 0, 0.5, -14),
        BackgroundColor3 = Theme.panel, BorderSizePixel = 0, Font = Enum.Font.Gotham,
        TextSize = 10, TextColor3 = Theme.text, PlaceholderColor3 = Theme.muted,
        PlaceholderText = placeholder or "", Text = "", ClearTextOnFocus = false,
    }, card)
    corner(box, 5)
    box.FocusLost:Connect(function(enterPressed)
        if callback then
            local ok, err = pcall(callback, box.Text)
            if not ok then notify("Erro no campo: " .. tostring(err)) end
        end
    end)
    addSearchItem(card, title)
end

local function safeSet(featName, state)
    local feature = Hub.Features and Hub.Features[featName]
    if not feature then notify("Função ainda não implementada: " .. tostring(featName)); return false end
    feature:Set(state == true)
    return true
end

local categories = {
    "Home", "Farm", "Combat", "Fighting Style", "Items", "Sea Events",
    "Mirage & Race", "Drago Dojo", "Prehistoric", "Raid", "Fruits",
    "Teleport", "Player", "Visual", "Shop & Stats", "Server & Misc",
}
for i, name in ipairs(categories) do CreatePage(name); AddTabButton(name, name, i) end

-- Home / configurações gerais
local p = Pages.Home
CreateSection(p, "Painel principal")
CreateDropdown(p, "Modo", { "Player", "Scripter" }, Hub.Mode == "Scripter" and 2 or 1, function(v)
    Hub:SetMode(v); notify("Modo alterado: " .. v)
end)
CreateDropdown(p, "Arma principal", { "Melee", "Sword", "Gun", "Blox Fruit" }, 1, function(v) Hub.Config.Weapon = v end)
CreateToggle(p, "Auto Haki (Buso)", Hub.Config.AutoHaki, function(v) Hub.Config.AutoHaki = v end)
CreateSlider(p, "Altura do farm", 10, 80, Hub.Config.FarmDistance, 0, function(v) Hub.Config.FarmDistance = v end)
CreateToggle(p, "Girar em volta do alvo", Hub.Config.SpinPosition, function(v) Hub.Config.SpinPosition = v end)
CreateSlider(p, "Velocidade do tween", 50, 350, Hub.Config.TweenSpeed, 0, function(v) Hub.Config.TweenSpeed = v end)
CreateToggle(p, "Bring Mob (Scripter)", Hub.Config.BringMob, function(v) Hub.Config.BringMob = v end)
CreateSlider(p, "Distância do Bring", 100, 1000, Hub.Config.BringDistance, 0, function(v) Hub.Config.BringDistance = v end)
CreateSlider(p, "Delay global", 0.05, 1, Hub.Config.Delay, 2, function(v) Hub.Config.Delay = v end)
CreateButton(p, "PARAR TODAS AS FUNÇÕES", function() Hub:StopAll(); notify("Todas as funções foram paradas.") end)

-- Farm
p = Pages.Farm
CreateSection(p, "Farm de nível e inimigos")
CreateToggle(p, "Auto Farm Level", false, function(v) safeSet("AutoFarmLevel", v) end)
CreateToggle(p, "Farm do inimigo mais próximo", false, function(v) safeSet("FarmNearest", v) end)
CreateToggle(p, "Attack Aura", false, function(v) safeSet("AttackAura", v) end)
CreateSection(p, "Bosses e baús")
local bossValues = (World and Hub.Bosses[World]) or {}
if #bossValues > 0 then
    Hub.Config.Boss = Hub.Config.Boss or bossValues[1]
    CreateDropdown(p, "Boss selecionado", bossValues, table.find(bossValues, Hub.Config.Boss) or 1, function(v) Hub.Config.Boss = v end)
else
    CreateSection(p, "Lista de bosses indisponível neste mapa")
end
CreateToggle(p, "Farmar todos os bosses", Hub.Config.BossAll, function(v) Hub.Config.BossAll = v end)
CreateToggle(p, "Auto Boss", false, function(v) safeSet("BossFarm", v) end)
CreateToggle(p, "Auto Baús", false, function(v) safeSet("ChestFarm", v) end)

-- Combat
p = Pages.Combat
CreateSection(p, "Combate e maestria")
CreateToggle(p, "IA de Combate", false, function(v) safeSet("CombatAI", v) end)
CreateDropdown(p, "Método da maestria", { "Level", "Nearest" }, Hub.Config.MasteryMethod == "Nearest" and 2 or 1, function(v) Hub.Config.MasteryMethod = v end)
CreateSlider(p, "Usar skills abaixo de vida (%)", 5, 90, Hub.Config.MasteryHealth, 0, function(v) Hub.Config.MasteryHealth = v end)
CreateSlider(p, "Trocar item a cada (s)", 10, 120, Hub.Config.SwitchEvery, 0, function(v) Hub.Config.SwitchEvery = v end)
CreateSection(p, "Tipos de maestria")
for _, tip in ipairs({ "Sword", "Gun", "Blox Fruit", "Melee" }) do
    CreateToggle(p, "Treinar " .. tip, Hub.Config.MasteryTypes[tip] == true, function(v)
        Hub.Config.MasteryTypes[tip] = v
        local f = Hub.Features.MasteryFarm
        if f and f.On then f:Set(false); f:Set(true) end
    end)
end
CreateToggle(p, "Farm de Maestria", false, function(v) safeSet("MasteryFarm", v) end)

-- Categorias reservadas para módulos que ainda não existem no Phynton.
local function placeholder(pageName, detail)
    local page = Pages[pageName]
    CreateSection(page, pageName .. " • em desenvolvimento")
    local note = make("TextLabel", {
        Size = UDim2.new(1, -5, 0, 68), BackgroundColor3 = Theme.card,
        BorderSizePixel = 0, TextWrapped = true, Text = detail,
        TextColor3 = Theme.muted, Font = Enum.Font.Gotham, TextSize = 11,
    }, page)
    corner(note, 7)
    addSearchItem(note, pageName .. " em desenvolvimento")
end
placeholder("Fighting Style", "Esta página está preparada para receber módulos de estilos de luta. Nenhuma automação foi adicionada porque o Phynton v4 ainda não contém essas rotinas.")
placeholder("Items", "Espadas, materiais e itens especiais: área reservada. Os módulos do VUA não foram copiados sem adaptação e validação.")
placeholder("Drago Dojo", "Área reservada para funções do Drago Dojo. Ainda sem automações conectadas.")
placeholder("Prehistoric", "Área reservada para eventos e conteúdos pré-históricos. Ainda sem automações conectadas.")
placeholder("Raid", "Área reservada para raids. Ainda sem automações conectadas.")

-- Sea Events
p = Pages["Sea Events"]
CreateSection(p, "Eventos marítimos • selecione os alvos")
for _, seaName in ipairs({ "Shark", "Terrorshark", "Piranha", "Fish Crew Member", "SeaBeast" }) do
    local selected = table.find(Hub.Config.SeaNames, seaName) ~= nil
    CreateToggle(p, "Alvo: " .. seaName, selected, function(v)
        local nextList = {}
        for _, current in ipairs(Hub.Config.SeaNames) do
            if current ~= seaName then table.insert(nextList, current) end
        end
        if v then table.insert(nextList, seaName) end
        Hub.Config.SeaNames = nextList
    end)
end
CreateToggle(p, "Auto Farm Sea", false, function(v) safeSet("SeaFarm", v) end)

-- Mirage & Race
p = Pages["Mirage & Race"]
CreateSection(p, "Mirage e evolução de raça")
CreateToggle(p, "Auto Mirage Hunt", false, function(v) safeSet("MirageHunt", v) end)
CreateToggle(p, "Ativar Raça V3", false, function(v) safeSet("RaceV3", v) end)
CreateToggle(p, "Ativar Raça V4", false, function(v) safeSet("RaceV4", v) end)

-- Fruits / eventos
p = Pages.Fruits
CreateSection(p, "Frutas")
CreateToggle(p, "Coletar frutas do mapa", false, function(v) safeSet("FruitCollect", v) end)
CreateToggle(p, "Random Fruit (Gacha)", false, function(v) safeSet("RandomFruit", v) end)
CreateSection(p, "Itens de evento")
CreateToggle(p, "Farm de Abóboras", false, function(v) safeSet("PumpkinFarm", v) end)
CreateToggle(p, "Farm de Doces", false, function(v) safeSet("CandyFarm", v) end)
local function addEventKeyword(key)
    return function(value)
        local keyword = tostring(value or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        if keyword ~= "" then
            table.insert(Hub.EventCfg[key], keyword)
            notify("Palavra-chave adicionada: " .. keyword)
        end
    end
end
CreateInput(p, "Palavra para abóbora", "nome extra do item", addEventKeyword("Pumpkin"))
CreateInput(p, "Palavra para doce", "nome extra do item", addEventKeyword("Candy"))
CreateButton(p, "Escanear itens de evento", function()
    local lines, total = {}, 0
    for key, patterns in pairs(Hub.EventCfg or {}) do
        local _, names = Hub.ScanEvent(patterns)
        for name, count in pairs(names or {}) do
            total += count; table.insert(lines, key .. ": " .. name .. " x" .. count)
        end
    end
    print("[Phynton] itens encontrados:\n" .. table.concat(lines, "\n"))
    notify(tostring(total) .. " itens encontrados (console F9).")
end)

-- Teleport
p = Pages.Teleport
CreateSection(p, "Viagem entre ilhas")
local islandValues = {}
for _, islandName in ipairs((World and Hub.IslandList[World]) or {}) do
    if Hub.Islands[islandName] then table.insert(islandValues, islandName) end
end
local pickedIsland = islandValues[1]
if #islandValues > 0 then CreateDropdown(p, "Selecionar ilha", islandValues, 1, function(v) pickedIsland = v end) end
CreateButton(p, "Teleportar para ilha selecionada", function()
    if not pickedIsland then notify("Nenhuma ilha disponível."); return end
    if Hub.TeleportIsland(pickedIsland) == false then notify("Não foi possível iniciar o teleporte.") end
end)
CreateSection(p, "Teleportar até jogador")
local pickedPlayer = ""
CreateInput(p, "Username", "Digite o nome do jogador", function(v) pickedPlayer = v or "" end)
CreateButton(p, "Ir até o jogador", function()
    if pickedPlayer == "" or not Hub.TeleportPlayer(pickedPlayer) then notify("Jogador não encontrado.") end
end)

-- Player
p = Pages.Player
CreateSection(p, "Movimentação")
CreateSlider(p, "WalkSpeed", 16, 500, Hub.Config.WalkSpeed, 0, function(v) Hub.Config.WalkSpeed = v end)
CreateToggle(p, "Ativar WalkSpeed", false, function(v) safeSet("WalkSpeed", v) end)
CreateSlider(p, "JumpPower", 50, 500, Hub.Config.JumpPower, 0, function(v) Hub.Config.JumpPower = v end)
CreateToggle(p, "Ativar JumpPower", false, function(v) safeSet("JumpPower", v) end)
CreateToggle(p, "No Clip", false, function(v) safeSet("NoClip", v) end)
CreateToggle(p, "Andar na água", false, function(v) safeSet("WalkOnWater", v) end)
CreateDropdown(p, "Perfil IA de movimento", { "Sharkizim", "Gravado" }, 1, function(v) Hub.ActiveProfile = v end)
CreateToggle(p, "IA de Movimento (Mimic)", false, function(v) safeSet("MoveAI", v) end)

-- Visual
p = Pages.Visual
CreateSection(p, "Localizadores ESP")
CreateToggle(p, "ESP Jogadores", false, function(v) safeSet("EspPlayer", v) end)
CreateToggle(p, "ESP Frutas", false, function(v) safeSet("EspFruit", v) end)
CreateToggle(p, "ESP Baús", false, function(v) safeSet("EspChest", v) end)
CreateToggle(p, "ESP Bosses", false, function(v) safeSet("EspBoss", v) end)
CreateSection(p, "Gráficos e FPS")
CreateToggle(p, "Remover Fog", false, function(v) safeSet("RemoveFog", v) end)
CreateToggle(p, "Fullbright", false, function(v) safeSet("Fullbright", v) end)
CreateToggle(p, "Remover sombras", false, function(v) safeSet("NoShadows", v) end)
CreateToggle(p, "Remover partículas", false, function(v) safeSet("NoParticles", v) end)
CreateToggle(p, "Remover efeitos de câmera", false, function(v) safeSet("NoCameraEffects", v) end)
CreateToggle(p, "Fast Mode", false, function(v) safeSet("FastMode", v) end)
CreateButton(p, "Aplicar FPS Boost", function() Hub.BoostFps(); notify("FPS Boost aplicado.") end)

-- Shop & Stats
p = Pages["Shop & Stats"]
CreateSection(p, "Distribuição de pontos")
for _, stat in ipairs({ "Melee", "Defense", "Sword", "Gun", "Demon Fruit" }) do
    CreateToggle(p, "Distribuir em " .. stat, Hub.Config.Stats[stat] == true, function(v) Hub.Config.Stats[stat] = v end)
end
CreateSlider(p, "Pontos por ciclo", 1, 100, Hub.Config.PointStats, 0, function(v) Hub.Config.PointStats = v end)
CreateToggle(p, "Ativar Auto Stats", false, function(v) safeSet("AutoStats", v) end)
CreateSection(p, "Equipe e loja")
CreateButton(p, "Entrar no time Pirates", function() task.spawn(Invoke, "SetTeam", "Pirates") end)
CreateButton(p, "Entrar no time Marines", function() task.spawn(Invoke, "SetTeam", "Marines") end)
for _, item in ipairs(Hub.Shop or {}) do
    local itemName, args = item[1], item[2]
    CreateButton(p, "Comprar: " .. tostring(itemName), function()
        task.spawn(function() Invoke(table.unpack(args)); notify("Solicitação enviada: " .. tostring(itemName)) end)
    end)
end

-- Server & Misc
p = Pages["Server & Misc"]
CreateSection(p, "Utilitários de servidor")
CreateButton(p, "Reentrar no servidor", function() Hub.Rejoin() end)
CreateButton(p, "Trocar de servidor", function()
    task.spawn(function() if not Hub.Hop() then notify("Nenhum servidor livre encontrado.") end end)
end)
CreateButton(p, "Copiar JobId", function()
    if setclipboard then setclipboard(game.JobId); notify("JobId copiado.") else notify("Executor sem suporte a clipboard.") end
end)
local jobInput = ""
CreateInput(p, "JobId", "Cole o JobId de destino", function(v) jobInput = v or "" end)
CreateButton(p, "Entrar no JobId", function()
    if jobInput == "" then notify("Informe um JobId."); return end
    TeleportService:TeleportToPlaceInstance(game.PlaceId, jobInput, LP)
end)
CreateButton(p, "Resgatar códigos", function()
    task.spawn(function() notify("Códigos enviados: " .. tostring(Hub.Redeem())) end)
end)

-- Busca por categoria ou controle: mantém visíveis apenas os resultados.
local searchConn = SearchBox:GetPropertyChangedSignal("Text"):Connect(function()
    local query = string.lower(SearchBox.Text or "")
    local matchedPage
    for _, obj in ipairs(SearchItems) do
        if obj and obj.Parent then
            local text = obj:GetAttribute("PhyntonSearch") or ""
            local matched = query == "" or string.find(text, query, 1, true) ~= nil
            obj.Visible = matched
            if query ~= "" and matched and obj.Parent and obj.Parent:IsA("ScrollingFrame") then
                local candidate = obj.Parent.Name:gsub("Page$", "")
                if Pages[candidate] and not matchedPage then matchedPage = candidate end
            end
        end
    end
    if query ~= "" then
        if matchedPage then SelectTab(matchedPage) else
            for name, btn in pairs(TabButtons) do
                if btn.Visible then SelectTab(name); break end
            end
        end
    elseif activePage then
        SelectTab(activePage)
    end
end)
onCleanup(function() searchConn:Disconnect() end)

SelectTab("Home")
updateResponsive()
local viewportConn
if Camera then
    viewportConn = Camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsive)
    onCleanup(function() viewportConn:Disconnect() end)
end
notify("Interface carregada • Modo " .. tostring(Hub.Mode))

--------------------------------------------------------------------
-- 11) OVERLAY FLUTUANTE E CONTADOR DE FPS
--------------------------------------------------------------------
local overlayGui = Instance.new("ScreenGui")
overlayGui.Name = "PhyntonOverlay"
overlayGui.ResetOnSpawn = false
overlayGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() overlayGui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
if not overlayGui.Parent then overlayGui.Parent = LP:WaitForChild("PlayerGui") end
onCleanup(function() pcall(function() overlayGui:Destroy() end) end)

local FloatBtn = make("TextButton", {
    Size = UDim2.fromOffset(46, 46), Position = UDim2.new(0, 12, 0.42, 0),
    Text = "PH", Font = Enum.Font.GothamBold, TextSize = 13,
    TextColor3 = Theme.text, BackgroundColor3 = Theme.panel, BorderSizePixel = 0,
}, overlayGui)
corner(FloatBtn, 23); stroke(FloatBtn, Theme.accent, 0.35, 1.3)
FloatBtn.Activated:Connect(function() ScreenGui.Enabled = not ScreenGui.Enabled end)

local FpsLabel = make("TextLabel", {
    Size = UDim2.fromOffset(90, 22), Position = UDim2.new(0.5, -45, 0, 6),
    BackgroundTransparency = 1, TextColor3 = Theme.accent,
    TextStrokeTransparency = 0.65, Font = Enum.Font.GothamBold,
    TextSize = 12, Text = "FPS: --", Active = false,
}, overlayGui)
local frames, acc = 0, 0
local fpsConn = RunService.Heartbeat:Connect(function(dt)
    frames += 1; acc += dt
    if acc >= 1 then
        FpsLabel.Text = "FPS: " .. math.floor(frames / math.max(acc, 0.001) + 0.5)
        frames, acc = 0, 0
    end
end)
onCleanup(function() fpsConn:Disconnect() end)

G.PhyntonHub = Hub
return Hub
