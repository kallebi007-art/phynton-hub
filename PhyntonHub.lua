--[[ ============================================================
     PHYNTON HUB v6
     - Sem IA, sem modo Player, sem aba de Config
     - v6: NPC/portais, eventos + hop de servidor, quests dinâmicas, Elite/Bone, FPS/Ping
     - Módulos: BASE > DADOS > MOVIMENTO > COMBATE > FARM > EXTRAS > UI
     - Pensado para celular: botão flutuante "pyh" arrastável abre/fecha
     ============================================================ ]]

local G = (getgenv and getgenv()) or _G

-- eventos pedidos por um hop anterior (lido ANTES da limpeza para não ser apagado)
local AUTO_EVENT = G.PhyntonAutoEvent
G.PhyntonAutoEvent = nil

-- Re-execução segura: roda a limpeza deixada pela instância anterior
if G.PhyntonCleanup then
    for _, fn in ipairs(G.PhyntonCleanup) do pcall(fn) end
end
G.PhyntonCleanup = {}
local function onCleanup(fn) table.insert(G.PhyntonCleanup, fn) end
if G.PhyntonHub then pcall(function() G.PhyntonHub:StopAll() end) end
pcall(function() if G.PhyntonFluent then G.PhyntonFluent:Destroy() end end)

if not game:IsLoaded() then game.Loaded:Wait() end

--------------------------------------------------------------------
-- [ MÓDULO: BASE ]
--------------------------------------------------------------------
local Players         = game:GetService("Players")
local RunService      = game:GetService("RunService")
local VIM             = game:GetService("VirtualInputManager")
local Lighting        = game:GetService("Lighting")
local TweenService    = game:GetService("TweenService")
local VirtualUser     = game:GetService("VirtualUser")
local TeleportService = game:GetService("TeleportService")
local HttpService     = game:GetService("HttpService")
local UIS             = game:GetService("UserInputService")
local RS              = game:GetService("ReplicatedStorage")
local Workspace       = game:GetService("Workspace")
local LP              = Players.LocalPlayer

-- Mundo (Sea 1/2/3) pelo PlaceId
local PID = game.PlaceId
local World
if PID == 2753915549 or PID == 85211729168715 then World = "Sea1"
elseif PID == 4442272183 or PID == 79091703265657 then World = "Sea2"
elseif PID == 7449423635 or PID == 100117331123089 then World = "Sea3" end

local Remotes = RS:FindFirstChild("Remotes") or RS:WaitForChild("Remotes", 10)
local CommF = Remotes and Remotes:FindFirstChild("CommF_")

-- InvokeServer protegido: se o remote falhar, o loop não quebra
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

local Hub = { Features = {}, World = World, Version = "6.2", Notify = function() end }

-- Janitor: guarda tudo que uma função cria e limpa de uma vez ao desligar
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

-- Feature: uma função ligável. Set(true/false) nunca duplica loops.
local Feature = {}
Feature.__index = Feature
function Feature:Set(on)
    on = on and true or false
    if on == self.On then return end
    self.On = on
    if on then
        self.Jan = Janitor.new()
        task.spawn(function()
            local ok, err = pcall(self.Start, self, self.Jan)
            if not ok then warn("[Phynton:" .. self.Name .. "] " .. tostring(err)) end
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
            if not ok then warn("[Phynton:" .. f.Name .. "] " .. tostring(err)) end
            task.wait(delay)
        end
    end)
    self.Jan:Add(th)
end
function Hub:Register(name, start, stop)
    local f = setmetatable({ Name = name, On = false, Start = start, Stop = stop }, Feature)
    self.Features[name] = f
    return f
end
function Hub:StopAll()
    for _, f in pairs(self.Features) do f:Set(false) end
end

-- Utilidades de personagem
local function char() return LP.Character end
local function hrp() local c = char(); return c and c:FindFirstChild("HumanoidRootPart") end
local function hum() local c = char(); return c and c:FindFirstChildOfClass("Humanoid") end
local function level()
    local ok, v = pcall(function() return LP.Data.Level.Value end)
    return ok and v or 1
end
local function enemiesFolder() return Workspace:FindFirstChild("Enemies") end
local function always() return true end

local FLY_TAG = "PhyntonFly"
local function clearFlight()
    local r = hrp()
    if r then
        local f = r:FindFirstChild(FLY_TAG)
        if f then f:Destroy() end
        r.AssemblyLinearVelocity = Vector3.zero
    end
    local h = hum()
    if h then pcall(function() h.PlatformStand = false end) end
end

-- Configuração interna (sem aba de Config por enquanto)
Hub.Config = {
    Delay         = 0.2,
    Weapon        = "Melee",        -- ToolTip: Melee | Sword | Gun | Blox Fruit
    FarmDistance  = 35,             -- altura sobre o mob
    TweenSpeed    = 300,
    BringMob      = true,
    BringDistance = 500,
    HitDistance   = 120,
    MasteryTypes  = { Sword = true, Gun = true, ["Blox Fruit"] = true, Melee = false },
    MasteryMethod = "Level",        -- Level | Nearest
    MasteryHealth = 25,             -- % de vida do mob para usar skills
    SwitchEvery   = 25,
    SkillKeys     = { "Z", "X", "C", "V", "F" },
    GunSkills     = { "Z", "X" },
    Boss          = nil,
    BossAll       = false,
    SeaNames      = { "Shark", "Terrorshark", "Piranha", "Fish Crew Member" },
    PointStats    = 1,
    Stats         = { Melee = false, Defense = false, Sword = false, Gun = false, ["Demon Fruit"] = false },
    WalkSpeed     = 100,
    JumpPower     = 200,
    MirageTime    = 20,
    MirageSwitch  = 3,
    DynamicQuests = false,          -- lê quests novas direto do jogo (experimental)
    ShowFps       = true,
    ShowPing      = true,
    Team          = "Pirates",
    AntiBan       = true,
    AntiTp        = true,
    AntiDist      = 55,
    HopEvents     = { "Mirage Island", "rip_indra True Form" },
    HopWait       = 8,              -- segundos esperando o servidor carregar antes de checar
}

--------------------------------------------------------------------
-- [ MÓDULO: DADOS ] (extraído do Relz Hub)
--------------------------------------------------------------------
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
    Sea3 = { "Mansion", "Port Town", "Great Tree", "Castle On The Sea", "MiniSky", "Hydra Island", "Floating Turtle", "Haunted Castle", "Ice Cream Island", "Peanut Island", "Cake Island", "Cocoa Island", "Candy Island", "Tiki Outpost", "Dragon Dojo", "Submerged Island" },
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
    ["Submerged Island"] = { pos = Vector3.new(10782.1, -2087.7, 9268.5) },
}
Hub.Codes = { "KITTGAMING", "ENYU_IS_PRO", "FUDD10", "BIGNEWS", "THEGREATACE", "SUB2GAMERROBOT_EXP1", "STRAWHATMAIME", "SUB2OFFICIALNOOBIE", "SUB2NOOBMASTER123", "SUB2DAIGROCK", "AXIORE", "TANTAIGAMIMG", "STRAWHATMAINE", "JCWK", "FUDD10_V2", "SUB2FER999", "MAGICBIS", "TY_FOR_WATCHING", "STARCODEHEO" }
Hub.NpcData = {
    Sea1 = {
        ["Random Devil Fruit"] = Vector3.new(-1436.2, 61.9, 4.8),
        ["Blox Fruits Dealer"] = Vector3.new(-923.3, 7.7, 1608.6),
        ["Remove Devil Fruit"] = Vector3.new(5664.8, 64.7, 867.9),
        ["Ability Teacher"] = Vector3.new(-1057.7, 9.7, 1799.5),
        ["Dark Step"] = Vector3.new(-987.9, 13.8, 3989.5),
        ["Electro"] = Vector3.new(-5389.5, 13.3, -2149.8),
        ["Fishman Karate"] = Vector3.new(61581.8, 18.9, 987.8),
    },
    Sea2 = {
        ["Dargon Berath"] = Vector3.new(703.4, 187.0, 654.5),
        ["Mtsterious Man"] = Vector3.new(-2574.4, 1627.9, -3739.4),
        ["Mysterious Scientist"] = Vector3.new(-6437.9, 250.6, -4498.9),
        ["Awakening Expert"] = Vector3.new(-408.1, 16.0, 247.4),
        ["Nerd"] = Vector3.new(-401.8, 73.1, 262.3),
        ["Bar Manager"] = Vector3.new(-385.8, 73.0, 316.1),
        ["Blox Fruits Dealer"] = Vector3.new(-450.7, 73.0, 355.6),
        ["Trevor"] = Vector3.new(-341.5, 331.9, 643.0),
        ["Enhancement Editor"] = Vector3.new(-346.8, 73.0, 1194.4),
        ["Pirate Recruiter"] = Vector3.new(-428.1, 72.9, 1445.3),
        ["Marines Recruiter"] = Vector3.new(-1349.8, 73.0, -1045.1),
        ["Chemist"] = Vector3.new(-2777.5, 73.0, -3572.3),
        ["Cyborg"] = Vector3.new(629.1, 312.3, -531.6),
        ["Ghoul Mark"] = Vector3.new(635.2, 126.0, 33219.8),
        ["Guashiem"] = Vector3.new(938.0, 181.1, 33277.9),
        ["El Admin"] = Vector3.new(1322.8, 126.3, 33135.9),
        ["El Rodolfo"] = Vector3.new(941.2, 40.5, 32779.0),
        ["Arowe"] = Vector3.new(-1994.5, 125.5, -72.3),
    },
    Sea3 = {
        ["Blox Fruits Dealer"] = Vector3.new(-12511.0, 337.0, -7448.0),
        ["Remove Devil Fruit"] = Vector3.new(-5571.0, 1089.0, -2661.0),
        ["Horned Man"] = Vector3.new(-11890.0, 931.0, -8760.0),
        ["Hungey Man"] = Vector3.new(-10919.0, 624.0, -10268.0),
        ["Previous Hero"] = Vector3.new(-10368.0, 332.0, -10128.0),
        ["Butler"] = Vector3.new(-5125.0, 316.0, -3130.0),
        ["Lunoven"] = Vector3.new(-5117.0, 316.0, -3093.0),
        ["Elite Hunter"] = Vector3.new(-5420.0, 314.0, -2828.0),
        ["Player Hunter"] = Vector3.new(-5559.0, 314.0, -2840.0),
        ["Uzoth"] = Vector3.new(-9785.0, 852.0, 6667.0),
    },
}

function Hub:GetQuest(lv)
    local list = self.Quests[World]
    if not list then return nil end
    for _, q in ipairs(list) do
        if lv >= q[1] and lv <= q[2] then return q end
    end
    return list[#list]
end

--------------------------------------------------------------------
-- [ MÓDULO: MOVIMENTO ]
--------------------------------------------------------------------
-- Entradas do jogo (requestEntrance) por mar
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
    local list, r = Teleporters[World], hrp()
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

-- Chamado no Start das funções de farm: noclip enquanto a função estiver ligada
function Hub.StartBody(jan)
    jan:Add(RunService.Stepped:Connect(noclipStep))
    jan:Add(function() clearFlight() end)
end

-- Vai até um CFrame. Perto (<=80): instantâneo. Longe: tween (com teleporter do jogo).
-- keep(): devolve false para abortar (ex.: função desligada)
function Hub.GoTo(cf, keep)
    keep = keep or always
    Hub.MoveUntil = os.clock() + 2
    local r, h = hrp(), hum()
    if not (r and h and h.Health > 0) then return end
    local pos = cf.Position
    local dist = (pos - r.Position).Magnitude
    if dist > 500 then
        local tp = nearestTeleporter(pos)
        if tp then
            Invoke("requestEntrance", tp)
            task.wait(0.3)
            r = hrp(); if not r then return end
            r.CFrame = r.CFrame + Vector3.new(0, 50, 0)
            task.wait(0.5)
            r = hrp(); if not r then return end
            dist = (pos - r.Position).Magnitude
        end
    end
    Hub.MoveUntil = os.clock() + math.max(2, dist / math.max(Hub.Config.TweenSpeed, 30) + 1)
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
end

--------------------------------------------------------------------
-- [ MÓDULO: COMBATE ]
--------------------------------------------------------------------
local function findTool(tip)
    local function scan(c)
        if not c then return end
        for _, t in ipairs(c:GetChildren()) do
            if t:IsA("Tool") and t.ToolTip == tip then return t end
        end
    end
    return scan(char()) or scan(LP.Backpack)
end

local function mobAlive(mob)
    local h = mob and mob:FindFirstChildOfClass("Humanoid")
    return h and h.Health > 0 and mob:FindFirstChild("HumanoidRootPart") and mob.Parent
end

-- inimigo vivo mais próximo; name (opcional) filtra por nome (plain = contém)
local function findMob(name, plain, maxDist)
    local folder, r = enemiesFolder(), hrp()
    if not (folder and r) then return nil end
    local best, bd = nil, maxDist or math.huge
    for _, e in ipairs(folder:GetChildren()) do
        if mobAlive(e) then
            local ok = true
            if name then
                ok = e.Name == name or (plain and e.Name:lower():find(name:lower(), 1, true) ~= nil)
            end
            if ok then
                local d = (e.HumanoidRootPart.Position - r.Position).Magnitude
                if d < bd then best, bd = e, d end
            end
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

local function hitTargets(distance)
    local folder, r = enemiesFolder(), hrp()
    if not (folder and r) then return nil end
    local target, others = nil, {}
    for _, e in ipairs(folder:GetChildren()) do
        if mobAlive(e) and (e.HumanoidRootPart.Position - r.Position).Magnitude < distance then
            if not target then target = e.HumanoidRootPart
            else table.insert(others, { e, e.HumanoidRootPart }) end
        end
    end
    return target, others
end

-- Um golpe: ativa a ferramenta e registra o hit
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
    if RegisterAttack and RegisterHit then
        pcall(function()
            local target, others = hitTargets(Hub.Config.HitDistance)
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

-- posição acima do mob, olhando para ele
local function standCF(r)
    local p = r.Position
    return CFrame.new(p + Vector3.new(0, Hub.Config.FarmDistance, 0), p)
end

-- farma um mob até morrer (ou keep() virar false)
function Hub.FarmMob(mob, keep, tip)
    while keep() and mobAlive(mob) do
        local r = mob.HumanoidRootPart
        Hub.Haki()
        Hub.EquipTip(tip or Hub.Config.Weapon)
        Hub.MonFarm, Hub.PosMon = mob.Name, r.CFrame
        Hub.GoTo(standCF(r), keep)
        Hub.Hit()
        task.wait()
    end
end

-- maestria: bate normal; quando o mob chega em MasteryHealth%, usa o item da vez + skills
function Hub.MasteryFight(mob, keep, state)
    while keep() and mobAlive(mob) do
        local r, h = mob.HumanoidRootPart, mob:FindFirstChildOfClass("Humanoid")
        if os.clock() - state.t0 > Hub.Config.SwitchEvery then
            state.idx = state.idx % #state.order + 1
            state.t0 = os.clock()
        end
        Hub.Haki()
        Hub.MonFarm, Hub.PosMon = mob.Name, r.CFrame
        Hub.GoTo(standCF(r), keep)
        local pct = h.Health / math.max(h.MaxHealth, 1) * 100
        if pct <= Hub.Config.MasteryHealth then
            local tip = state.order[state.idx]
            Hub.EquipTip(tip)
            Hub.UseSkills(tip)
        else
            Hub.EquipTip(Hub.Config.Weapon)
        end
        Hub.Hit()
        task.wait()
    end
end

--------------------------------------------------------------------
-- [ MÓDULO: FARM ]
--------------------------------------------------------------------
-- Um passo do farm por nível: pega a quest, vai ao mob e chama fight(mob)
function Hub.LevelStep(keep, fight)
    local q = (Hub.Config.DynamicQuests and Hub.DynamicQuest(level())) or Hub:GetQuest(level())
    if not q then return end
    local mon, qname, qlvl, qpos, mpos = q[3], q[4], q[5], q[6], q[7]
    local qf
    pcall(function() qf = LP.PlayerGui.Main.Quest end)
    if qf and qf.Visible then
        local ok, title = pcall(function() return qf.Container.QuestTitle.Title.Text end)
        if ok and not string.find(title, mon, 1, true) then
            Invoke("AbandonQuest")
            return
        end
    else
        if qpos then Hub.GoTo(CFrame.new(qpos), keep) end
        if keep() then Invoke("StartQuest", qname, qlvl) end
        return
    end
    local mob = findMob(mon)
    if mob then
        fight(mob)
    else
        Hub.GoTo(CFrame.new(mpos + Vector3.new(0, Hub.Config.FarmDistance, 0)), keep)
    end
end

-- se o mapa não for reconhecido, desliga a função com aviso
local function needWorld(self)
    if World then return false end
    Hub.Notify("Mapa não reconhecido (Sea 1/2/3). Função desligada.")
    task.defer(function() self:Set(false) end)
    return true
end

Hub:Register("AutoFarmLevel", function(self, jan)
    if needWorld(self) then return end
    Hub.StartBody(jan)
    local function keep() return self.On end
    self:Loop(Hub.Config.Delay, function()
        Hub.LevelStep(keep, function(mob) Hub.FarmMob(mob, keep) end)
    end)
end)

Hub:Register("FarmNearest", function(self, jan)
    Hub.StartBody(jan)
    local function keep() return self.On end
    self:Loop(Hub.Config.Delay, function()
        local mob = findMob(nil, false, 5000)
        if mob then Hub.FarmMob(mob, keep) end
    end)
end)

Hub:Register("MasteryFarm", function(self, jan)
    local order = {}
    for tip, on in pairs(Hub.Config.MasteryTypes) do if on then table.insert(order, tip) end end
    table.sort(order)
    if #order == 0 then
        Hub.Notify("Escolha ao menos um tipo de maestria.")
        task.defer(function() self:Set(false) end)
        return
    end
    if Hub.Config.MasteryMethod == "Level" and needWorld(self) then return end
    Hub.StartBody(jan)
    local state = { order = order, idx = 1, t0 = os.clock() }
    local function keep() return self.On end
    self:Loop(Hub.Config.Delay, function()
        if Hub.Config.MasteryMethod == "Nearest" then
            local mob = findMob(nil, false, 5000)
            if mob then Hub.MasteryFight(mob, keep, state) end
        else
            Hub.LevelStep(keep, function(mob) Hub.MasteryFight(mob, keep, state) end)
        end
    end)
end)

Hub:Register("BossFarm", function(self, jan)
    if needWorld(self) then return end
    Hub.StartBody(jan)
    local function keep() return self.On end
    self:Loop(0.4, function()
        local names = Hub.Config.BossAll and Hub.Bosses[World] or { Hub.Config.Boss }
        for _, name in ipairs(names) do
            if name then
                local b = findMob(name)
                if b then Hub.FarmMob(b, keep); return end
            end
        end
    end)
end)

Hub:Register("AttackAura", function(self, jan)
    self:Loop(0.1, function() Hub.Hit() end)
end)

-- Traz os mobs do tipo farmado até você (age só quando há farm ligado)
local FARM_FEATURES = { "AutoFarmLevel", "FarmNearest", "MasteryFarm", "BossFarm", "SeaFarm", "EliteHunter", "BoneFarm" }
Hub:Register("BringMob", function(self, jan)
    jan:Add(RunService.Heartbeat:Connect(function()
        if not Hub.Config.BringMob or not (Hub.MonFarm and Hub.PosMon) then return end
        local anyFarm = false
        for _, n in ipairs(FARM_FEATURES) do
            local f = Hub.Features[n]
            if f and f.On then anyFarm = true; break end
        end
        if not anyFarm then return end
        local r, folder = hrp(), enemiesFolder()
        if not (r and folder) then return end
        for _, v in ipairs(folder:GetChildren()) do
            if v.Name == Hub.MonFarm and mobAlive(v)
                and (v.HumanoidRootPart.Position - r.Position).Magnitude <= Hub.Config.BringDistance then
                v.HumanoidRootPart.CFrame = Hub.PosMon
                v.HumanoidRootPart.CanCollide = false
                local vh = v:FindFirstChildOfClass("Humanoid")
                if vh then vh.WalkSpeed = 0 end
                if sethiddenproperty then pcall(sethiddenproperty, LP, "SimulationRadius", math.huge) end
            end
        end
    end))
end)

-- Eventos do mar: ataca inimigos cujo nome contém as palavras escolhidas
Hub:Register("SeaFarm", function(self, jan)
    Hub.StartBody(jan)
    local function keep() return self.On end
    self:Loop(0.3, function()
        for _, kw in ipairs(Hub.Config.SeaNames) do
            local mob = findMob(kw, true)
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
end)

-- Baús (o mais próximo)
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
end)

-- Frutas soltas no mapa
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
end)

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
-- [ MÓDULO: EXTRAS ]
--------------------------------------------------------------------

-- Mirage: aproxima reto e depois alterna a direção. Para ao encontrar a ilha.
Hub:Register("MirageHunt", function(self, jan)
    Hub.StartBody(jan)
    local t0, lastSwitch, dir = os.clock(), 0, 1
    jan:Add(function()
        local h = hum()
        local seat = h and h.SeatPart
        if seat and seat:IsA("VehicleSeat") then
            pcall(function() seat.Throttle = 0; seat.Steer = 0 end)
        end
    end)
    self:Loop(0.1, function()
        for _, obj in ipairs(Workspace:GetChildren()) do
            if obj.Name:lower():find("mirage", 1, true) then
                Hub.Notify("Mirage encontrada! (" .. obj.Name .. ")")
                task.defer(function() self:Set(false) end)
                return
            end
        end
        local h, r = hum(), hrp()
        if not (h and r) then return end
        local approaching = os.clock() - t0 < Hub.Config.MirageTime
        if not approaching and os.clock() - lastSwitch > Hub.Config.MirageSwitch then
            dir = -dir
            lastSwitch = os.clock()
        end
        local seat = h.SeatPart
        if seat and seat:IsA("VehicleSeat") then
            seat.Throttle = 1
            seat.Steer = approaching and 0 or dir
        else
            local cam = Workspace.CurrentCamera
            local look, right = cam.CFrame.LookVector, cam.CFrame.RightVector
            local move = approaching and look or (look + right * dir).Unit
            ensureFloat()
            r.CFrame = r.CFrame + move * 8
            r.AssemblyLinearVelocity = Vector3.zero
        end
    end)
end)

-- Jogador
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

-- ESP (1 varredura por segundo; tudo some ao desligar)
local function makeEsp(name, collect)
    Hub:Register(name, function(self, jan)
        local made = {}
        jan:Add(function()
            for _, g in pairs(made) do pcall(function() g:Destroy() end) end
        end)
        self:Loop(1, function()
            local seen, r = {}, hrp()
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
        local pr = p ~= LP and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
        if pr then table.insert(out, { part = pr, text = p.Name, color = Color3.fromRGB(255, 90, 90) }) end
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
        local er = e:FindFirstChild("HumanoidRootPart")
        if er and table.find(names, e.Name) then
            table.insert(out, { part = er, text = e.Name, color = Color3.fromRGB(255, 120, 255) })
        end
    end
    return out
end)

-- Evento: abóboras e doces (procura por nome; palavras editáveis na aba)
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

local function scanEvent(pats)
    local r = hrp(); if not r then return end
    local best, bd, names = nil, math.huge, {}
    for _, inst in ipairs(Workspace:GetDescendants()) do
        if (inst:IsA("BasePart") or inst:IsA("Model")) and nameMatches(inst.Name, pats)
            and not isOwnOrEnemy(inst) then
            local part = inst:IsA("BasePart") and inst or inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart")
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
    end)
end
registerEventFarm("PumpkinFarm", "Pumpkin")
registerEventFarm("CandyFarm", "Candy")

-- Teleporte
function Hub.TeleportIsland(name)
    local isl = Hub.Islands[name]
    if not isl then return false end
    if isl.entrance then
        task.spawn(Invoke, "requestEntrance", isl.entrance)
    elseif isl.pos then
        task.spawn(function()
            Hub.GoTo(CFrame.new(isl.pos))
            clearFlight()
        end)
    end
    return true
end

function Hub.TeleportPlayer(name)
    local p = Players:FindFirstChild(name)
    local r = p and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
    if not r then return false end
    task.spawn(function()
        Hub.GoTo(r.CFrame)
        clearFlight()
    end)
    return true
end

-- Loja
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

-- Servidor
function Hub.Redeem()
    local rem = Remotes and Remotes:FindFirstChild("Redeem")
    if not rem then return 0 end
    local n = 0
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

-- Visual
local Orig = {
    FogStart = Lighting.FogStart, FogEnd = Lighting.FogEnd,
    Brightness = Lighting.Brightness, Ambient = Lighting.Ambient,
    GlobalShadows = Lighting.GlobalShadows,
}

Hub:Register("RemoveFog", function(self, jan)
    jan:Add(function() Lighting.FogStart = Orig.FogStart; Lighting.FogEnd = Orig.FogEnd end)
    Lighting.FogStart = 0
    Lighting.FogEnd = 100000
end)

Hub:Register("Fullbright", function(self, jan)
    jan:Add(function() Lighting.Brightness = Orig.Brightness; Lighting.Ambient = Orig.Ambient end)
    Lighting.Brightness = 2
    Lighting.Ambient = Color3.fromRGB(255, 255, 255)
end)

Hub:Register("NoShadows", function(self, jan)
    jan:Add(function() Lighting.GlobalShadows = Orig.GlobalShadows end)
    Lighting.GlobalShadows = false
end)

Hub:Register("NoParticles", function(self, jan)
    local touched = {}
    jan:Add(function()
        for _, v in ipairs(touched) do pcall(function() v.Enabled = true end) end
    end)
    self:Loop(2, function()
        for _, v in ipairs(Workspace:GetDescendants()) do
            if (v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Smoke")
                or v:IsA("Fire") or v:IsA("Sparkles")) and v.Enabled then
                v.Enabled = false
                table.insert(touched, v)
            end
        end
    end)
end)

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

--------------------------------------------------------------------
-- [ MÓDULO: MISSÕES, NPC E EVENTOS ]
--------------------------------------------------------------------
local function worldOrigin(name)
    local wo = Workspace:FindFirstChild("_WorldOrigin")
    return wo and wo:FindFirstChild(name)
end
local function stripLv(n) return (n:gsub(" %pLv. %d+%p", "")) end

local function spawnPos(mobName)
    local sp = worldOrigin("EnemySpawns")
    if not sp then return nil end
    for _, v in ipairs(sp:GetChildren()) do
        if v:IsA("BasePart") and (v.Name == mobName or stripLv(v.Name) == mobName) then return v.Position end
    end
end

-- Quests "novas": lê as quests direto do jogo (ReplicatedStorage.Quests) e acha o
-- mob no EnemySpawns. EXPERIMENTAL: depende de como o jogo guarda os dados.
function Hub.DynamicQuest(lv)
    local ok, Q = pcall(function() return require(RS:WaitForChild("Quests", 3)) end)
    if not ok or type(Q) ~= "table" then return nil end
    local best
    for qname, tiers in pairs(Q) do
        if type(tiers) == "table" then
            for idx, t in pairs(tiers) do
                if type(idx) == "number" and type(t) == "table" and type(t.LevelReq) == "number"
                    and t.LevelReq <= lv and type(t.Task) == "table" then
                    local mob
                    for m in pairs(t.Task) do mob = m end
                    if mob and (not best or t.LevelReq > best.req) then
                        local sp = spawnPos(mob)
                        if sp then best = { req = t.LevelReq, qname = qname, qlvl = idx, mob = mob, sp = sp } end
                    end
                end
            end
        end
    end
    if not best then return nil end
    return { best.req, 99999, best.mob, best.qname, best.qlvl, nil, best.sp }
end

-- vai até o NPC da quest (se conhecido) ou até a área do mob
function Hub.GoQuest(toMob)
    local q = (Hub.Config.DynamicQuests and Hub.DynamicQuest(level())) or Hub:GetQuest(level())
    if not q then return false end
    local pos = (toMob or not q[6]) and q[7] or q[6]
    task.spawn(function()
        Hub.GoTo(CFrame.new(pos + Vector3.new(0, 3, 0)))
        clearFlight()
    end)
    return true, q[3]
end

-- NPCs: busca ao vivo (Workspace.NPCs / ReplicatedStorage.NPCs) com fallback nas coordenadas do Relz
local function npcRoots()
    return { Workspace:FindFirstChild("NPCs"), RS:FindFirstChild("NPCs") }
end

function Hub.ListNpcs()
    local seen, out = {}, {}
    for _, root in ipairs(npcRoots()) do
        if root then
            for _, m in ipairs(root:GetChildren()) do
                if not seen[m.Name] then seen[m.Name] = true; table.insert(out, m.Name) end
            end
        end
    end
    table.sort(out)
    return out
end

function Hub.FindNpc(query)
    query = (query or ""):lower()
    if query == "" then return nil end
    for _, root in ipairs(npcRoots()) do
        if root then
            for _, m in ipairs(root:GetChildren()) do
                if m.Name:lower():find(query, 1, true) then
                    local part = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")
                    if part then return m.Name, part.Position, "ao vivo" end
                end
            end
        end
    end
    local data = World and Hub.NpcData[World]
    if data then
        for name, pos in pairs(data) do
            if name:lower():find(query, 1, true) then return name, pos, "tabela" end
        end
    end
end

-- acha o NPC, vai até ele (usando portais quando compensa) e executa after()
function Hub.NpcAndDo(query, after)
    local name, pos, how = Hub.FindNpc(query)
    if not name then return false end
    task.spawn(function()
        Hub.GoTo(CFrame.new(pos + Vector3.new(0, 3, 4)))
        clearFlight()
        if after then after(name) end
    end)
    return true, name, how
end

function Hub.LegendaryDealer()
    local found, name = Hub.NpcAndDo("legendary", function(n)
        for _, id in ipairs({ "1", "2", "3" }) do Invoke("LegendarySwordDealer", id) end
        Hub.Notify("Pedido enviado ao " .. n .. " (espadas 1, 2 e 3).")
    end)
    if not found then
        -- o Relz compra sem se mover; tenta mesmo assim
        for _, id in ipairs({ "1", "2", "3" }) do task.spawn(Invoke, "LegendarySwordDealer", id) end
    end
    return found, name
end

-- Locais de evento (ilhas que aparecem em _WorldOrigin.Locations)
local function locationObj(name)
    local loc = worldOrigin("Locations")
    return loc and loc:FindFirstChild(name)
end
function Hub.GoLocation(name)
    local o = locationObj(name)
    if not o then return false end
    local pos
    if o:IsA("BasePart") then pos = o.Position else pcall(function() pos = o:GetPivot().Position end) end
    if not pos then return false end
    task.spawn(function()
        Hub.GoTo(CFrame.new(pos + Vector3.new(0, 60, 0)))
        clearFlight()
    end)
    return true
end

-- Mirage: ponto mais alto da ilha e Blue Gear (peça neon)
local function mysticIsland()
    local m = Workspace:FindFirstChild("Map")
    return m and m:FindFirstChild("MysticIsland")
end
function Hub.GoMirageTop()
    local mi = mysticIsland(); if not mi then return false end
    local top
    for _, p in ipairs(mi:GetDescendants()) do
        if p:IsA("BasePart") and (not top or p.Position.Y > top.Position.Y) then top = p end
    end
    if not top then return false end
    task.spawn(function()
        Hub.GoTo(CFrame.new(top.Position + Vector3.new(0, 8, 0)))
        clearFlight()
    end)
    return true
end
function Hub.GoBlueGear()
    local mi = mysticIsland(); if not mi then return false end
    for _, p in ipairs(mi:GetChildren()) do
        if p:IsA("MeshPart") and p.Material == Enum.Material.Neon then
            task.spawn(function()
                Hub.GoTo(p.CFrame)
                clearFlight()
            end)
            return true
        end
    end
    return false
end

Hub:Register("LookMoon", function(self, jan)
    jan:Add(RunService.RenderStepped:Connect(function()
        local cam = Workspace.CurrentCamera
        if cam then
            local p = cam.CFrame.Position
            cam.CFrame = CFrame.lookAt(p, p + Lighting:GetMoonDirection() * 100)
        end
    end))
end)

-- Detecção de eventos no servidor atual
local function bossPresent(sub)
    sub = sub:lower()
    local e = enemiesFolder()
    if e then
        for _, m in ipairs(e:GetChildren()) do
            if m.Name:lower():find(sub, 1, true) and mobAlive(m) then return true end
        end
    end
    for _, m in ipairs(RS:GetChildren()) do
        if m:IsA("Model") and m.Name:lower():find(sub, 1, true) and m:FindFirstChildOfClass("Humanoid") then return true end
    end
    return false
end
local function fullMoon()
    local ok, id = pcall(function() return Lighting.Sky.MoonTextureId end)
    return ok and id == "http://www.roblox.com/asset/?id=9709149431"
        and (Lighting.ClockTime > 16 or Lighting.ClockTime < 5)
end

Hub.ServerEvents = {
    "Mirage Island", "Kitsune Island", "Frozen Dimension", "Prehistoric Island",
    "Lua Cheia", "rip_indra True Form", "Elite Hunter (Diablo/Deandre/Urban)",
}
function Hub.EventList()
    local l = {}
    for _, e in ipairs(Hub.ServerEvents) do table.insert(l, e) end
    for _, b in ipairs((World and Hub.Bosses[World]) or {}) do
        if not b:lower():find("rip_indra", 1, true) then table.insert(l, "Boss: " .. b) end
    end
    return l
end

function Hub.CheckEvents(selected)
    local found = {}
    for _, ev in ipairs(selected) do
        local hit = false
        if ev == "Mirage Island" or ev == "Kitsune Island" or ev == "Frozen Dimension" or ev == "Prehistoric Island" then
            hit = locationObj(ev) ~= nil
        elseif ev == "Lua Cheia" then
            hit = fullMoon()
        elseif ev:find("Elite Hunter", 1, true) then
            hit = bossPresent("diablo") or bossPresent("deandre") or bossPresent("urban")
        elseif ev:sub(1, 6) == "Boss: " then
            hit = bossPresent(ev:sub(7))
        else
            hit = bossPresent(ev)
        end
        if hit then table.insert(found, ev) end
    end
    return found
end

-- Hop para outro servidor (aleatório, sem repetir os já visitados)
G.PhyntonVisited = G.PhyntonVisited or {}
Hub.ScriptUrl = nil
pcall(function()
    if isfile and isfile("PhyntonHub_url.txt") then Hub.ScriptUrl = readfile("PhyntonHub_url.txt") end
end)
function Hub.SetScriptUrl(u)
    u = (u or ""):gsub("%s+", "")
    Hub.ScriptUrl = (u ~= "") and u or nil
    pcall(function() if writefile then writefile("PhyntonHub_url.txt", u) end end)
end

-- agenda o script para rodar de novo no próximo servidor (precisa da URL raw + queue_on_teleport)
function Hub.QueueRelaunch()
    local f = Hub.Features.EventHop
    if not (f and f.On and Hub.ScriptUrl and queue_on_teleport) then return false end
    local evs = HttpService:JSONEncode(Hub.Config.HopEvents)
    local code = ("getgenv().PhyntonAutoEvent = game:GetService('HttpService'):JSONDecode(%q); loadstring(game:HttpGet(%q))()")
        :format(evs, Hub.ScriptUrl)
    return pcall(queue_on_teleport, code)
end

function Hub.HopRandom()
    local cursor = ""
    for _ = 1, 3 do
        local url = ("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100%s")
            :format(game.PlaceId, cursor ~= "" and ("&cursor=" .. cursor) or "")
        local ok, data = pcall(function() return HttpService:JSONDecode(game:HttpGet(url)) end)
        if not (ok and data and data.data) then return false end
        local pool = {}
        for _, s in ipairs(data.data) do
            if s.id ~= game.JobId and not G.PhyntonVisited[s.id] and s.playing < s.maxPlayers - 1 then
                table.insert(pool, s)
            end
        end
        if #pool > 0 then
            local s = pool[math.random(#pool)]
            G.PhyntonVisited[s.id] = true
            Hub.QueueRelaunch()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id, LP)
            return true
        end
        cursor = data.nextPageCursor or ""
        if cursor == "" then break end
    end
    return false
end

-- Procura evento: se não houver no servidor atual, troca de servidor e repete
Hub:Register("EventHop", function(self, jan)
    local t0, hopping = os.clock(), false
    self:Loop(1, function()
        if os.clock() - t0 < Hub.Config.HopWait or not hrp() then return end
        local found = Hub.CheckEvents(Hub.Config.HopEvents)
        if #found > 0 then
            Hub.Notify("Evento encontrado: " .. table.concat(found, ", "))
            task.defer(function() self:Set(false) end)
            return
        end
        if hopping then return end
        hopping = true
        Hub.Notify("Nenhum evento aqui. Trocando de servidor...")
        task.spawn(function()
            if not Hub.HopRandom() then
                Hub.Notify("Não achei servidor agora. Tentando de novo...")
                task.wait(5)
            else
                task.wait(15) -- se o teleporte falhar, libera para tentar outro
            end
            hopping = false
        end)
    end)
end)

-- Elite Hunter (Sea 3): pega a quest, mata Diablo/Deandre/Urban
Hub:Register("EliteHunter", function(self, jan)
    if World ~= "Sea3" then
        Hub.Notify("Elite Hunter só existe no Sea 3.")
        task.defer(function() self:Set(false) end)
        return
    end
    Hub.StartBody(jan)
    local function keep() return self.On end
    local npcPos = Vector3.new(-5418.9, 313.7, -2826.2)
    self:Loop(0.3, function()
        local elite = findMob("Diablo") or findMob("Deandre") or findMob("Urban")
        local qf
        pcall(function() qf = LP.PlayerGui.Main.Quest end)
        if not (qf and qf.Visible) then
            Hub.GoTo(CFrame.new(npcPos), keep)
            if keep() then Invoke("EliteHunter") end
            return
        end
        if elite then
            Hub.FarmMob(elite, keep)
            return
        end
        -- elite ainda carregando: vai até o modelo guardado no ReplicatedStorage
        for _, n in ipairs({ "Diablo", "Deandre", "Urban" }) do
            local m = RS:FindFirstChild(n)
            local r = m and m:FindFirstChild("HumanoidRootPart")
            if r then Hub.GoTo(r.CFrame * CFrame.new(0, Hub.Config.FarmDistance, 0), keep); return end
        end
    end)
end)

-- Farm de Bone (Sea 3 - Haunted Castle)
local BONE_MOBS = { "Reborn Skeleton", "Living Zombie", "Demonic Soul", "Posessed Mummy" }
Hub:Register("BoneFarm", function(self, jan)
    if World ~= "Sea3" then
        Hub.Notify("Farm de Bone só existe no Sea 3.")
        task.defer(function() self:Set(false) end)
        return
    end
    Hub.StartBody(jan)
    local function keep() return self.On end
    local questPos = Vector3.new(-9517.0, 172.0, 6078.5)
    local areaPos = Vector3.new(-9506.2, 172.1, 6117.1)
    self:Loop(Hub.Config.Delay, function()
        local qf
        pcall(function() qf = LP.PlayerGui.Main.Quest end)
        if qf and qf.Visible then
            local ok, title = pcall(function() return qf.Container.QuestTitle.Title.Text end)
            if ok and not string.find(title, "Demonic Soul", 1, true) then
                Invoke("AbandonQuest")
                return
            end
        else
            Hub.GoTo(CFrame.new(questPos), keep)
            if keep() then Invoke("StartQuest", "HauntedQuest2", 1) end
            return
        end
        local best, bd
        local r = hrp()
        for _, n in ipairs(BONE_MOBS) do
            local m = findMob(n)
            if m and r then
                local d = (m.HumanoidRootPart.Position - r.Position).Magnitude
                if not bd or d < bd then best, bd = m, d end
            end
        end
        if best then
            Hub.FarmMob(best, keep)
        else
            Hub.GoTo(CFrame.new(areaPos + Vector3.new(0, Hub.Config.FarmDistance, 0)), keep)
        end
    end)
end)

-- BringMob fica ligado (só age quando há farm ativo)
task.defer(function() Hub.Features.BringMob:Set(true) end)



--------------------------------------------------------------------
-- TIME AUTOMATICO + SAIR SE ALGUEM TELEPORTAR PERTO
--------------------------------------------------------------------
function Hub.PickTeam(team)
    team = (team == "Marines") and "Marines" or "Pirates"
    Hub.Config.Team = team
    local pg = LP:FindFirstChild("PlayerGui")
    local main = pg and pg:FindFirstChild("Main")
    local choose = main and main:FindFirstChild("ChooseTeam")
    if not (choose and choose.Visible) then
        return LP.Team ~= nil
    end
    local container = choose:FindFirstChild("Container")
    local side = container and container:FindFirstChild(team)
    local frame = side and side:FindFirstChild("Frame")
    local vp = frame and (frame:FindFirstChild("ViewportFrame") or frame)
    local btn = vp and (vp:FindFirstChild("TextButton") or vp:FindFirstChildWhichIsA("TextButton", true))
    if not btn then return false end
    local fired = false
    pcall(function()
        if getconnections then
            for _, c in ipairs(getconnections(btn.MouseButton1Click)) do
                if c.Function then c.Function() fired = true end
            end
        end
    end)
    if not fired then
        pcall(function()
            firesignal(btn.MouseButton1Click)
            fired = true
        end)
    end
    return fired
end

task.spawn(function()
    for _ = 1, 40 do
        if not LP.Parent then return end
        if LP.Team then return end
        Hub.PickTeam(Hub.Config.Team)
        task.wait(0.4)
    end
end)

local LeavingServer = false
local ClosingGame = false
function Hub.LeaveServer(reason)
    if LeavingServer or ClosingGame then return end
    LeavingServer = true
    Hub.Notify(reason or "Saindo do servidor...")
    task.wait(0.35)
    local ok = false
    pcall(function() ok = Hub.Hop() end)
    if not ok then
        pcall(function() TeleportService:Teleport(game.PlaceId, LP) end)
    end
end

function Hub.CloseGame(reason)
    if ClosingGame then return end
    ClosingGame = true
    LeavingServer = true
    Hub.Notify(reason or "Anti-Ban: fechando o Roblox...")
    task.wait(0.25)
    local env = {}
    pcall(function() env = (getgenv and getgenv()) or {} end)
    for _, name in ipairs({ "closegame", "closeGame", "closeroblox", "closeRoblox", "CloseRoblox", "CloseGame" }) do
        pcall(function()
            local fn = env[name] or _G[name]
            if type(fn) == "function" then fn() end
        end)
    end
    pcall(function()
        if krnl and type(krnl.closeRoblox) == "function" then krnl.closeRoblox() end
    end)
    pcall(function()
        if syn and type(syn.close_roblox) == "function" then syn.close_roblox() end
    end)
    pcall(function()
        if fluxus and type(fluxus.close) == "function" then fluxus.close() end
    end)
    task.spawn(function()
        local junk = {}
        while true do
            junk[#junk + 1] = string.rep("x", 1048576)
        end
    end)
end

function Hub.OnThreat(msg)
    if Hub.Config.AntiBan then
        Hub.CloseGame(msg .. " Fechando o Roblox.")
    elseif Hub.Config.AntiTp then
        Hub.LeaveServer(msg .. " Saindo do servidor.")
    end
end

task.spawn(function()
    local arm = os.clock() + 8
    local last = {}
    LP.CharacterAdded:Connect(function()
        arm = os.clock() + 5
        last[LP] = nil
    end)
    while LP.Parent do
        task.wait(0.25)
        if ClosingGame or LeavingServer or not (Hub.Config.AntiBan or Hub.Config.AntiTp) then
            local r = hrp()
            if r then last[LP] = r.Position end
        else
            pcall(function()
                local r = hrp()
                if not r then return end
                local my = r.Position
                local near = Hub.Config.AntiDist or 55
                local moving = os.clock() < (Hub.MoveUntil or 0)
                for _, p in ipairs(Players:GetPlayers()) do
                    if p ~= LP and p.Character then
                        local h = p.Character:FindFirstChild("HumanoidRootPart")
                        if h then
                            local pos = h.Position
                            local prev = last[p]
                            if prev and os.clock() >= arm then
                                local jumped = (pos - prev).Magnitude
                                if jumped >= 90 and (pos - my).Magnitude <= near then
                                    Hub.OnThreat(p.Name .. " teleportou perto.")
                                    return
                                end
                            end
                            last[p] = pos
                        end
                    end
                end
                local prevMe = last[LP]
                if prevMe and os.clock() >= arm and not moving then
                    if (my - prevMe).Magnitude >= 200 then
                        for _, p in ipairs(Players:GetPlayers()) do
                            if p ~= LP and p.Character then
                                local h = p.Character:FindFirstChild("HumanoidRootPart")
                                if h and (h.Position - my).Magnitude <= near then
                                    Hub.OnThreat("Voce foi puxado perto de " .. p.Name .. ".")
                                    return
                                end
                            end
                        end
                    end
                end
                last[LP] = my
            end)
        end
    end
end)

--------------------------------------------------------------------
-- [ MÓDULO: UI ]  (Fluent)
--------------------------------------------------------------------
local okF, Fluent = pcall(function()
    return loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
end)
if not okF or not Fluent then
    warn("[Phynton] não foi possível carregar a interface Fluent: " .. tostring(Fluent))
    G.PhyntonHub = Hub
    return Hub
end

local Window = Fluent:CreateWindow({
    Title = "Phynton Hub",
    SubTitle = "v6 | " .. (World or "mapa desconhecido"),
    TabWidth = 120,
    Size = UDim2.fromOffset(500, 370),
    Acrylic = false,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl, -- no PC; no celular use o botão "pyh"
})
G.PhyntonFluent = Fluent

Hub.Notify = function(msg)
    pcall(function() Fluent:Notify({ Title = "Phynton Hub", Content = msg, Duration = 4 }) end)
end

local Tabs = {
    Farm     = Window:AddTab({ Title = "Farm",       Icon = "" }),
    Combat   = Window:AddTab({ Title = "Combate",    Icon = "" }),
    Sea      = Window:AddTab({ Title = "Sea",        Icon = "" }),
    Event    = Window:AddTab({ Title = "Eventos",    Icon = "" }),
    Teleport = Window:AddTab({ Title = "Teleporte",  Icon = "" }),
    NPC      = Window:AddTab({ Title = "NPC",        Icon = "" }),
    Shop     = Window:AddTab({ Title = "Loja/Stats", Icon = "" }),
    Player   = Window:AddTab({ Title = "Player",     Icon = "" }),
    Visual   = Window:AddTab({ Title = "Visual",     Icon = "" }),
    Server   = Window:AddTab({ Title = "Servidor",   Icon = "" }),
}

-- helpers de UI
local function toggle(tab, id, title, feat, desc)
    tab:AddToggle(id, { Title = title, Default = false, Description = desc })
        :OnChanged(function(v) Hub.Features[feat]:Set(v) end)
end
local function slider(tab, id, title, min, max, default, rounding, cb)
    tab:AddSlider(id, { Title = title, Default = default, Min = min, Max = max, Rounding = rounding or 0, Callback = cb })
end
local function selectedList(sel)
    local out = {}
    for k, v in pairs(sel) do if v then table.insert(out, k) end end
    table.sort(out)
    return out
end

-- Farm
Tabs.Farm:AddDropdown("Weapon", {
    Title = "Arma do farm", Values = { "Melee", "Sword", "Gun", "Blox Fruit" }, Default = 1,
}):OnChanged(function(v) Hub.Config.Weapon = v end)
toggle(Tabs.Farm, "FarmLevel", "Auto Farm Level", "AutoFarmLevel", "Pega a quest do seu nível e farma")
toggle(Tabs.Farm, "FarmNearest", "Auto Farm Mais Próximo", "FarmNearest")
local bossValues = (World and Hub.Bosses[World]) or {}
Tabs.Farm:AddDropdown("Boss", { Title = "Boss", Values = bossValues })
    :OnChanged(function(v) Hub.Config.Boss = v end)
Tabs.Farm:AddToggle("BossAll", { Title = "Farmar todos os bosses", Default = false })
    :OnChanged(function(v) Hub.Config.BossAll = v end)
toggle(Tabs.Farm, "Boss", "Auto Boss", "BossFarm", "Só ataca se o boss já estiver spawnado")
toggle(Tabs.Farm, "Chest", "Auto Baús", "ChestFarm")
toggle(Tabs.Farm, "Fruit", "Auto Coletar Frutas", "FruitCollect")
toggle(Tabs.Farm, "RandFruit", "Auto Random Fruit", "RandomFruit")
toggle(Tabs.Farm, "Aura", "Attack Aura", "AttackAura")

Tabs.Farm:AddToggle("DynQuests", { Title = "Quests novas (lê do jogo) - experimental", Default = false,
    Description = "Usa ReplicatedStorage.Quests + EnemySpawns em vez da tabela fixa" })
    :OnChanged(function(v) Hub.Config.DynamicQuests = v end)
Tabs.Farm:AddButton({ Title = "Ir até a quest do meu nível", Callback = function()
    local ok, mon = Hub.GoQuest(false)
    Hub.Notify(ok and ("Indo para a quest: " .. tostring(mon)) or "Quest não encontrada para o seu nível.")
end })
Tabs.Farm:AddButton({ Title = "Ir até a área do mob da quest", Callback = function()
    local ok, mon = Hub.GoQuest(true)
    Hub.Notify(ok and ("Indo para: " .. tostring(mon)) or "Quest não encontrada para o seu nível.")
end })
toggle(Tabs.Farm, "Elite", "Auto Elite Hunter (Sea 3)", "EliteHunter", "Diablo / Deandre / Urban")
toggle(Tabs.Farm, "Bone", "Auto Farm Bone (Sea 3)", "BoneFarm", "Quest do Haunted Castle")
Tabs.Farm:AddButton({ Title = "Parar Tudo", Callback = function() Hub:StopAll() end })

-- Combate (maestria)
Tabs.Combat:AddDropdown("MasteryMethod", {
    Title = "Método da maestria", Values = { "Level", "Nearest" }, Default = 1,
}):OnChanged(function(v) Hub.Config.MasteryMethod = v end)
Tabs.Combat:AddDropdown("MasteryTypes", {
    Title = "Treinar maestria de", Values = { "Sword", "Gun", "Blox Fruit", "Melee" },
    Multi = true, Default = { "Sword", "Gun", "Blox Fruit" },
}):OnChanged(function(sel)
    for tip in pairs(Hub.Config.MasteryTypes) do Hub.Config.MasteryTypes[tip] = sel[tip] == true end
    local f = Hub.Features.MasteryFarm
    if f.On then f:Set(false); task.wait(0.1); f:Set(true) end
end)
slider(Tabs.Combat, "MasteryHP", "Usar skills com o mob em (% vida)", 5, 90, Hub.Config.MasteryHealth, 0,
    function(v) Hub.Config.MasteryHealth = v end)
slider(Tabs.Combat, "SwitchEvery", "Trocar de item a cada (s)", 10, 120, Hub.Config.SwitchEvery, 0,
    function(v) Hub.Config.SwitchEvery = v end)
toggle(Tabs.Combat, "Mastery", "Farm de Maestria", "MasteryFarm", "Bate normal e usa skills com o item da vez")

-- Sea
Tabs.Sea:AddDropdown("SeaNames", {
    Title = "Inimigos do mar", Values = { "Shark", "Terrorshark", "Piranha", "Fish Crew Member", "Sea Beast" },
    Multi = true, Default = { "Shark", "Terrorshark", "Piranha", "Fish Crew Member" },
}):OnChanged(function(sel) Hub.Config.SeaNames = selectedList(sel) end)
toggle(Tabs.Sea, "SeaFarm", "Auto Farm Inimigos do Mar", "SeaFarm")
toggle(Tabs.Sea, "Mirage", "Auto Mirage Hunt", "MirageHunt", "Vai reto 20s e depois alterna a direção. Para ao achar.")

-- Eventos
-- Eventos do servidor + hop automático
local eventValues = Hub.EventList()
Tabs.Event:AddDropdown("HopEvents", {
    Title = "Eventos que quero achar", Values = eventValues, Multi = true, Default = { "Mirage Island", "rip_indra True Form" },
}):OnChanged(function(sel)
    Hub.Config.HopEvents = selectedList(sel)
end)
Tabs.Event:AddToggle("EventHop", { Title = "Procurar evento (trocar de servidor até achar)", Default = false,
    Description = "Entra em servidor, confere se o evento existe e, se não, troca de novo" })
    :OnChanged(function(v)
        if v and #Hub.Config.HopEvents == 0 then
            Hub.Notify("Escolha ao menos um evento.")
        end
        Hub.Features.EventHop:Set(v)
    end)
Tabs.Event:AddInput("ScriptUrl", { Title = "URL raw do PhyntonHub.lua (para continuar após trocar de servidor)",
    Default = Hub.ScriptUrl or "", Placeholder = "https://raw.githubusercontent.com/...", Finished = true,
    Callback = function(v) Hub.SetScriptUrl(v); Hub.Notify("URL salva.") end })
Tabs.Event:AddButton({ Title = "Verificar eventos neste servidor", Callback = function()
    local found = Hub.CheckEvents(Hub.EventList())
    Hub.Notify(#found > 0 and ("Aqui tem: " .. table.concat(found, ", ")) or "Nenhum evento da lista neste servidor.")
end })
Tabs.Event:AddParagraph({
    Title = "Como funciona",
    Content = "O Roblox não mostra eventos de outros servidores, então o script entra, confere e troca. Sem a URL raw, ele só faz um salto e você precisa rodar o script de novo. Com a URL (e executor com queue_on_teleport), ele continua sozinho.",
})
toggle(Tabs.Event, "Pumpkin", "Farm de Abóboras", "PumpkinFarm")
toggle(Tabs.Event, "Candy", "Farm de Doces", "CandyFarm")
local function addKeyword(key)
    return function(txt)
        txt = (txt or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
        if txt ~= "" then table.insert(Hub.EventCfg[key], txt) end
    end
end
Tabs.Event:AddInput("PumpkinKw", { Title = "Palavra-chave extra (abóbora)", Default = "", Placeholder = "nome do item", Finished = true, Callback = addKeyword("Pumpkin") })
Tabs.Event:AddInput("CandyKw", { Title = "Palavra-chave extra (doce)", Default = "", Placeholder = "nome do item", Finished = true, Callback = addKeyword("Candy") })
Tabs.Event:AddButton({ Title = "Escanear itens do evento", Callback = function()
    local lines, total = {}, 0
    for key, pats in pairs(Hub.EventCfg) do
        local _, names = Hub.ScanEvent(pats)
        for n, c in pairs(names or {}) do total += c; table.insert(lines, key .. ": " .. n .. " x" .. c) end
    end
    print("[Phynton] itens encontrados:\n" .. table.concat(lines, "\n"))
    Hub.Notify(total .. " itens (lista no console F9)")
end })

-- Teleporte
local islandValues = {}
for _, n in ipairs((World and Hub.IslandList[World]) or {}) do
    if Hub.Islands[n] then table.insert(islandValues, n) end
end
local pickedIsland
Tabs.Teleport:AddDropdown("Island", { Title = "Ilha", Values = islandValues })
    :OnChanged(function(v) pickedIsland = v end)
Tabs.Teleport:AddButton({ Title = "Teleportar para a ilha", Callback = function()
    if not pickedIsland then Hub.Notify("Escolha uma ilha."); return end
    Hub.TeleportIsland(pickedIsland)
end })
local pickedPlayer = ""
Tabs.Teleport:AddInput("PlayerName", { Title = "Nome do jogador", Default = "", Placeholder = "username", Finished = true,
    Callback = function(v) pickedPlayer = v or "" end })
Tabs.Teleport:AddButton({ Title = "Ir até o jogador", Callback = function()
    if not Hub.TeleportPlayer(pickedPlayer) then Hub.Notify("Jogador não encontrado.") end
end })
Tabs.Teleport:AddButton({ Title = "Ir até a Mirage Island (ponto mais alto)", Callback = function()
    if not Hub.GoMirageTop() then Hub.Notify("Mirage Island não está neste servidor.") end
end })
Tabs.Teleport:AddButton({ Title = "Ir até o Blue Gear (Mirage)", Callback = function()
    if not Hub.GoBlueGear() then Hub.Notify("Blue Gear não encontrado.") end
end })
for _, loc in ipairs({ "Kitsune Island", "Frozen Dimension", "Prehistoric Island" }) do
    Tabs.Teleport:AddButton({ Title = "Ir até " .. loc, Callback = function()
        if not Hub.GoLocation(loc) then Hub.Notify(loc .. " não está neste servidor.") end
    end })
end
toggle(Tabs.Teleport, "LookMoon", "Olhar para a lua (câmera)", "LookMoon")
Tabs.Teleport:AddParagraph({
    Title = "Portais",
    Content = "Nas viagens longas o script usa o portal do jogo (requestEntrance) quando ele deixa o destino mais perto, e depois segue voando até o ponto final.",
})

-- NPC
local npcNames = {}
for name in pairs((World and Hub.NpcData[World]) or {}) do table.insert(npcNames, name) end
table.sort(npcNames)
local pickedNpc
local npcDropdown = Tabs.NPC:AddDropdown("NpcList", { Title = "NPC conhecido", Values = npcNames })
npcDropdown:OnChanged(function(v) pickedNpc = v end)
local function goNpc(q)
    local ok, name, how = Hub.NpcAndDo(q)
    Hub.Notify(ok and ("Indo até " .. name .. " (" .. how .. ")") or "NPC não encontrado.")
end
Tabs.NPC:AddButton({ Title = "Ir até o NPC selecionado", Callback = function()
    if pickedNpc then goNpc(pickedNpc) else Hub.Notify("Escolha um NPC.") end
end })
local npcQuery = ""
Tabs.NPC:AddInput("NpcSearch", { Title = "Buscar NPC pelo nome", Default = "", Placeholder = "ex.: legendary, dealer, elite",
    Finished = true, Callback = function(v) npcQuery = v or "" end })
Tabs.NPC:AddButton({ Title = "Ir até o NPC buscado", Callback = function() goNpc(npcQuery) end })
Tabs.NPC:AddButton({ Title = "Listar NPCs carregados no mapa", Callback = function()
    local list = Hub.ListNpcs()
    print("[Phynton] NPCs carregados:\n" .. table.concat(list, "\n"))
    if #list > 0 then pcall(function() npcDropdown:SetValues(list) end) end
    Hub.Notify(#list .. " NPCs (lista no console F9 e no menu acima)")
end })
Tabs.NPC:AddButton({ Title = "Vendedor de Espadas Lendárias: ir e comprar", Callback = function()
    local found, name = Hub.LegendaryDealer()
    Hub.Notify(found and ("Indo até " .. name) or "Vendedor não carregado aqui; tentei comprar mesmo assim.")
end })
Tabs.NPC:AddParagraph({
    Title = "Dica",
    Content = "NPCs só aparecem 'ao vivo' quando estão carregados perto de você. Se não achar, o script usa a tabela de coordenadas (só alguns NPCs).",
})

-- Loja / Stats
for _, item in ipairs(Hub.Shop) do
    Tabs.Shop:AddButton({ Title = "Comprar: " .. item[1], Callback = function()
        task.spawn(function()
            Invoke(table.unpack(item[2]))
            Hub.Notify("Pedido enviado: " .. item[1])
        end)
    end })
end
Tabs.Shop:AddButton({ Title = "Time: Pirates", Callback = function() task.spawn(Invoke, "SetTeam", "Pirates") end })
Tabs.Shop:AddButton({ Title = "Time: Marines", Callback = function() task.spawn(Invoke, "SetTeam", "Marines") end })
Tabs.Shop:AddDropdown("StatSel", {
    Title = "Distribuir pontos em", Values = { "Melee", "Defense", "Sword", "Gun", "Demon Fruit" }, Multi = true,
}):OnChanged(function(sel)
    for k in pairs(Hub.Config.Stats) do Hub.Config.Stats[k] = sel[k] == true end
end)
slider(Tabs.Shop, "PointStats", "Pontos por vez", 1, 100, Hub.Config.PointStats, 0,
    function(v) Hub.Config.PointStats = v end)
toggle(Tabs.Shop, "AutoStats", "Auto Stats", "AutoStats")

-- Player
slider(Tabs.Player, "WalkSpeed", "Velocidade", 16, 500, Hub.Config.WalkSpeed, 0, function(v) Hub.Config.WalkSpeed = v end)
toggle(Tabs.Player, "WalkSpeedOn", "Ativar velocidade", "WalkSpeed")
slider(Tabs.Player, "JumpPower", "Pulo", 50, 500, Hub.Config.JumpPower, 0, function(v) Hub.Config.JumpPower = v end)
toggle(Tabs.Player, "JumpOn", "Ativar pulo", "JumpPower")
toggle(Tabs.Player, "NoClip", "No Clip", "NoClip")
toggle(Tabs.Player, "Water", "Andar na água", "WalkOnWater")
toggle(Tabs.Player, "RaceV3", "Ativar Raça V3", "RaceV3")
toggle(Tabs.Player, "RaceV4", "Ativar Raça V4", "RaceV4")

-- Visual
Tabs.Visual:AddToggle("ShowFps", { Title = "Mostrar FPS", Default = true })
    :OnChanged(function(v) Hub.Config.ShowFps = v; if Hub.RefreshOverlay then Hub.RefreshOverlay() end end)
Tabs.Visual:AddToggle("ShowPing", { Title = "Mostrar Ping", Default = true })
    :OnChanged(function(v) Hub.Config.ShowPing = v; if Hub.RefreshOverlay then Hub.RefreshOverlay() end end)
toggle(Tabs.Visual, "RemoveFog", "Remover Fog", "RemoveFog")
toggle(Tabs.Visual, "Fullbright", "Fullbright", "Fullbright")
toggle(Tabs.Visual, "NoShadows", "Remover Sombras (FPS)", "NoShadows")
toggle(Tabs.Visual, "NoParticles", "Remover Partículas (FPS)", "NoParticles")
Tabs.Visual:AddButton({ Title = "FPS Boost", Callback = function()
    Hub.BoostFps(); Hub.Notify("FPS Boost aplicado (reentrar no jogo desfaz).")
end })
toggle(Tabs.Visual, "EspPlayer", "ESP Jogadores", "EspPlayer")
toggle(Tabs.Visual, "EspFruit", "ESP Frutas", "EspFruit")
toggle(Tabs.Visual, "EspChest", "ESP Baús", "EspChest")
toggle(Tabs.Visual, "EspBoss", "ESP Bosses", "EspBoss")

-- Servidor
Tabs.Server:AddDropdown("TeamPick", {
    Title = "Time ao entrar", Values = { "Pirates", "Marines" }, Default = Hub.Config.Team == "Marines" and 2 or 1,
}):OnChanged(function(v)
    Hub.Config.Team = v
    task.spawn(function() Hub.PickTeam(v) end)
end)
Tabs.Server:AddButton({ Title = "Entrar nesse time agora", Callback = function()
    if Hub.PickTeam(Hub.Config.Team) then Hub.Notify("Pedido de time: " .. Hub.Config.Team)
    else Hub.Notify("Tela de time nao esta aberta (voce ja tem time).") end
end })
Tabs.Server:AddToggle("AntiBan", { Title = "Anti-Ban (fecha o Roblox)", Default = true,
    Description = "Admin ou player teleporta do seu lado: fecha o jogo no celular" })
    :OnChanged(function(v) Hub.Config.AntiBan = v end)
Tabs.Server:AddToggle("AntiTp", { Title = "So trocar de servidor", Default = true,
    Description = "Usado apenas se o Anti-Ban estiver desligado" })
    :OnChanged(function(v) Hub.Config.AntiTp = v end)
slider(Tabs.Server, "AntiDist", "Distancia do teleporte (studs)", 25, 120, Hub.Config.AntiDist, 0,
    function(v) Hub.Config.AntiDist = v end)
Tabs.Server:AddButton({ Title = "Rejoin", Callback = function() Hub.Rejoin() end })
Tabs.Server:AddButton({ Title = "Trocar de servidor (Hop)", Callback = function()
    task.spawn(function() if not Hub.Hop() then Hub.Notify("Nenhum servidor livre encontrado.") end end)
end })
Tabs.Server:AddButton({ Title = "Copiar JobId", Callback = function()
    if setclipboard then setclipboard(game.JobId); Hub.Notify("JobId copiado.")
    else Hub.Notify("Seu executor não tem setclipboard.") end
end })
local jobInput = ""
Tabs.Server:AddInput("JobId", { Title = "Entrar por JobId", Default = "", Placeholder = "cole o JobId", Finished = true,
    Callback = function(v) jobInput = v or "" end })
Tabs.Server:AddButton({ Title = "Entrar no JobId", Callback = function()
    if jobInput ~= "" then TeleportService:TeleportToPlaceInstance(game.PlaceId, jobInput, LP) end
end })
Tabs.Server:AddButton({ Title = "Resgatar todos os códigos", Callback = function()
    task.spawn(function() Hub.Notify("Códigos enviados: " .. Hub.Redeem()) end)
end })

Window:SelectTab(1)
Hub.Notify("Carregado! Toque no botão \"pyh\" para abrir/fechar o menu.")

--------------------------------------------------------------------
-- BOTÃO FLUTUANTE (celular) + CONTADOR DE FPS LEVE
--------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "PhyntonOverlay"
gui.ResetOnSpawn = false
gui.DisplayOrder = 999
gui.IgnoreGuiInset = true
local okParent = pcall(function() gui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
if not okParent or not gui.Parent then gui.Parent = LP:WaitForChild("PlayerGui") end
onCleanup(function() gui:Destroy() end)

-- abre/fecha o menu (Minimize do Fluent; se falhar, liga/desliga a GUI inteira)
local function toggleMenu()
    local ok = pcall(function() Window:Minimize() end)
    if not ok and Fluent.GUI then Fluent.GUI.Enabled = not Fluent.GUI.Enabled end
end

local btn = Instance.new("TextButton")
btn.Name = "PhyntonToggle"
btn.Size = UDim2.fromOffset(52, 52)
btn.Position = UDim2.new(0, 12, 0.35, 0)
btn.Text = "pyh"
btn.Font = Enum.Font.GothamBold
btn.TextSize = 16
btn.TextColor3 = Color3.fromRGB(255, 255, 255)
btn.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
btn.AutoButtonColor = true
btn.Active = true
btn.ZIndex = 10
btn.Parent = gui
Instance.new("UICorner", btn).CornerRadius = UDim.new(1, 0)
local stroke = Instance.new("UIStroke", btn)
stroke.Color = Color3.fromRGB(120, 120, 255); stroke.Thickness = 2

-- toque curto = abre/fecha; arrastar = move o botão
local dragging, moved, dragStart, startPos = false, false, nil, nil
local function isPointer(i)
    return i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseButton1
end
btn.InputBegan:Connect(function(i)
    if isPointer(i) then
        dragging, moved = true, false
        dragStart, startPos = i.Position, btn.Position
    end
end)
local cMove = UIS.InputChanged:Connect(function(i)
    if dragging and (i.UserInputType == Enum.UserInputType.Touch or i.UserInputType == Enum.UserInputType.MouseMovement) then
        local d = i.Position - dragStart
        if d.Magnitude > 8 then moved = true end
        if moved then
            btn.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
        end
    end
end)
local cEnd = UIS.InputEnded:Connect(function(i)
    if dragging and isPointer(i) then
        dragging = false
        if not moved then toggleMenu() end
    end
end)
onCleanup(function() cMove:Disconnect(); cEnd:Disconnect() end)

-- FPS e Ping: 1 conexão, texto atualizado 1x por segundo
local function makeLabel(y, text)
    local l = Instance.new("TextLabel")
    l.Size = UDim2.fromOffset(120, 18)
    l.Position = UDim2.new(0.5, -60, 0, y)
    l.BackgroundTransparency = 1
    l.TextColor3 = Color3.fromRGB(255, 255, 255)
    l.TextStrokeTransparency = 0.6
    l.Font = Enum.Font.GothamBold
    l.TextSize = 14
    l.Text = text
    l.Active = false
    l.Parent = gui
    return l
end
local fpsLabel = makeLabel(6, "FPS: --")
local pingLabel = makeLabel(24, "Ping: --")
function Hub.RefreshOverlay()
    fpsLabel.Visible = Hub.Config.ShowFps
    pingLabel.Visible = Hub.Config.ShowPing
end
Hub.RefreshOverlay()

local function getPing()
    local ok, v = pcall(function() return game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue() end)
    return ok and math.floor(v) or 0
end

local frames, acc = 0, 0
local fpsConn = RunService.Heartbeat:Connect(function(dt)
    frames += 1
    acc += dt
    if acc >= 1 then
        if Hub.Config.ShowFps then fpsLabel.Text = "FPS: " .. math.floor(frames / acc + 0.5) end
        if Hub.Config.ShowPing then pingLabel.Text = "Ping: " .. getPing() .. " ms" end
        frames, acc = 0, 0
    end
end)
onCleanup(function() fpsConn:Disconnect() end)

-- continua a procura de evento depois de um hop (agendado por queue_on_teleport)
if type(AUTO_EVENT) == "table" and #AUTO_EVENT > 0 then
    Hub.Config.HopEvents = AUTO_EVENT
    task.delay(4, function() Hub.Features.EventHop:Set(true) end)
    Hub.Notify("Retomando a procura de evento...")
end

G.PhyntonHub = Hub
return Hub
