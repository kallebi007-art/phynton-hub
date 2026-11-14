--[[
    PHYNTON HUB LITE v2  |  Luau (Roblox)  |  Fluent UI  |  Mobile
    Base: versao do Grok, corrigida e melhorada.
    - Cada aba e montada em build(): se um bloco falhar, os outros continuam
      e o erro aparece no fim da aba Extra.
    - Trechos [CONFIG] dependem de nomes/remotes do jogo (mudam em updates).
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
local TeleportService   = game:GetService("TeleportService")
local HttpService       = game:GetService("HttpService")

local lp  = Players.LocalPlayer
local cam = Workspace.CurrentCamera

---------------------------------------------------------------------
-- ESTADO / CORE
---------------------------------------------------------------------
local Phynton = {
    Flags = {}, Vals = {}, Tokens = {}, Conns = {},
    Paused = false, SelfMoving = false, PvPActive = false,
}

local Sea = (game.PlaceId == 2753915549 and 1)
    or (game.PlaceId == 4442272183 and 2)
    or (game.PlaceId == 7449423635 and 3) or 3

local function val(id, d) local v = Phynton.Vals[id]; if v == nil then return d end; return v end
local function flag(id) return Phynton.Flags[id] == true end

-- remote que DEVOLVE o resultado [CONFIG]
local function comm(...)
    local rem = ReplicatedStorage:FindFirstChild("Remotes")
    local c = rem and rem:FindFirstChild("CommF_")
    if not c then return nil end
    local args = table.pack(...)
    local ok, res = pcall(function() return c:InvokeServer(table.unpack(args, 1, args.n)) end)
    if ok then return res end
    return nil
end

local ErrorLog = {}
local function logErr(msg) table.insert(ErrorLog, msg); warn("[Phynton Lite] " .. msg) end
local function build(name, fn)
    local ok, err = xpcall(fn, function(e) return tostring(e) end)
    if not ok then logErr(name .. ": " .. err) end
end

---------------------------------------------------------------------
-- FLUENT
---------------------------------------------------------------------
local okLib, Fluent = pcall(function()
    return loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
end)
if not okLib or not Fluent then
    G.PhyntonHubLoaded = nil
    return warn("[Phynton Lite] Falha ao carregar Fluent UI")
end

local Window = Fluent:CreateWindow({
    Title = "Phynton Lite", SubTitle = "v2 • mobile",
    TabWidth = 110, Size = UDim2.fromOffset(480, 320),
    Acrylic = false, Theme = "Dark", MinimizeKey = Enum.KeyCode.RightControl,
})
local Tabs = {
    Main     = Window:AddTab({ Title = "Main", Icon = "home" }),
    Farm     = Window:AddTab({ Title = "Farm", Icon = "trophy" }),
    Items    = Window:AddTab({ Title = "Items", Icon = "box" }),
    Sea      = Window:AddTab({ Title = "Sea", Icon = "waves" }),
    Craft    = Window:AddTab({ Title = "Craft", Icon = "hammer" }),
    Combat   = Window:AddTab({ Title = "Combat", Icon = "swords" }),
    Movement = Window:AddTab({ Title = "Move", Icon = "move" }),
    Extra    = Window:AddTab({ Title = "Extra", Icon = "settings" }),
}

---------------------------------------------------------------------
-- HELPERS DE UI (cada elemento e criado de forma segura)
---------------------------------------------------------------------
local function notify(msg, dur)
    pcall(function() Fluent:Notify({ Title = "Phynton", Content = msg, Duration = dur or 3 }) end)
end

local UI = {}
local function setUI(id, v)
    local el = UI[id]
    if el then pcall(function() el:SetValue(v) end) end
end

-- Modo geral: Player (parece jogador normal) x Scripter (voa, puxa NPCs, ataca rapido)
local function applyMode(m)
    if m == "Scripter" then
        setUI("MoveMode", "Script"); setUI("BringMob", true); setUI("Noclip", true)
        setUI("AtkDelay", 0.07); setUI("AntiBan", true)
        notify("Modo Scripter: voa sobre o alvo, puxa NPCs e ataca rápido")
    else
        setUI("MoveMode", "Player"); setUI("BringMob", false); setUI("Noclip", false)
        setUI("AtkDelay", 0.18); setUI("AntiBan", true)
        setUI("Fly", false); setUI("Orbit", false)
        notify("Modo Player: anda e luta como um jogador normal")
    end
end

local PvPSafe = { Dodge = true, AutoHaki = true }

local function startLoop(id, fn, waitFn)
    Phynton.Tokens[id] = (Phynton.Tokens[id] or 0) + 1
    local my = Phynton.Tokens[id]
    task.spawn(function()
        while G.PhyntonHubLoaded and Phynton.Flags[id] and Phynton.Tokens[id] == my do
            if not Phynton.Paused and (not Phynton.PvPActive or PvPSafe[id]) then
                local ok, e = pcall(fn)
                if not ok then warn("[Phynton:" .. id .. "] " .. tostring(e)) end
            end
            local w = 0.15
            if waitFn then
                if type(waitFn) == "function" then
                    local ok, v = pcall(waitFn); if ok and v then w = v end
                else w = waitFn end
            end
            task.wait(w)
        end
    end)
end

local function dummy() return { OnChanged = function() end, SetValue = function() end } end
local function mk(fn)
    local ok, el = pcall(fn)
    if ok and el then return el end
    logErr(tostring(el))
    return dummy()
end
local function sec(tab, name) pcall(function() tab:AddSection(name) end) end
local function par(tab, cfg) pcall(function() tab:AddParagraph(cfg) end) end

local function addToggle(tab, id, title, default, cb)
    Phynton.Flags[id] = default or false
    local el = mk(function() return tab:AddToggle(id, { Title = title, Default = default or false }) end)
    pcall(function()
        el:OnChanged(function(v)
            Phynton.Flags[id] = v
            if cb then task.spawn(function() pcall(cb, v) end) end
        end)
    end)
    UI[id] = el
    return el
end

local function addLoopToggle(tab, id, title, fn, waitFn)
    return addToggle(tab, id, title, false, function(on)
        if on then startLoop(id, fn, waitFn) end
    end)
end

local function addSlider(tab, id, title, min, max, default, rounding)
    Phynton.Vals[id] = default
    local el = mk(function()
        return tab:AddSlider(id, { Title = title, Default = default, Min = min, Max = max, Rounding = rounding or 0 })
    end)
    pcall(function() el:OnChanged(function(v) Phynton.Vals[id] = v end) end)
    UI[id] = el
    return el
end

local function addDropdown(tab, id, title, values, default, multi, cb)
    local idx = (not multi) and table.find(values, default) or nil
    local el = mk(function()
        return tab:AddDropdown(id, { Title = title, Values = values, Multi = multi or false, Default = idx })
    end)
    Phynton.Vals[id] = default
    if multi then pcall(function() el:SetValue(default or {}) end) end
    pcall(function()
        el:OnChanged(function(v)
            if v ~= nil then Phynton.Vals[id] = v end
            if cb then task.spawn(function() pcall(cb, v) end) end
        end)
    end)
    UI[id] = el
    return el
end

local function addInput(tab, id, title, default, placeholder)
    Phynton.Vals[id] = default or ""
    local el = mk(function()
        return tab:AddInput(id, { Title = title, Default = default or "", Placeholder = placeholder or "", Numeric = false, Finished = false })
    end)
    pcall(function() el:OnChanged(function(v) Phynton.Vals[id] = v end) end)
    UI[id] = el
    return el
end

local function addButton(tab, title, cb)
    pcall(function()
        tab:AddButton({ Title = title, Callback = function() task.spawn(function() pcall(cb) end) end })
    end)
end

---------------------------------------------------------------------
-- HELPERS GERAIS
---------------------------------------------------------------------
local function getChar() return lp.Character end
local function getRoot() local c = getChar(); return c and c:FindFirstChild("HumanoidRootPart") end
local function getHum() local c = getChar(); return c and c:FindFirstChildOfClass("Humanoid") end
local function alive(h) return h ~= nil and h.Health > 0 end
local function partOf(m) return m and (m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart or m:FindFirstChildWhichIsA("BasePart")) end
local function flatDist(a, b) return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude end

local function humanWait()
    if flag("AntiBan") then task.wait(math.random(1, 3)) else task.wait(0.2) end
end

local function click()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:Button1Down(Vector2.new(0, 0), cam.CFrame)
        task.wait(0.02)
        VirtualUser:Button1Up(Vector2.new(0, 0), cam.CFrame)
    end)
end

local function pressKey(key)
    pcall(function()
        VIM:SendKeyEvent(true, key, false, game)
        task.wait(0.05)
        VIM:SendKeyEvent(false, key, false, game)
    end)
end

local function lookAtTarget(pos)
    pcall(function() cam.CFrame = CFrame.lookAt(cam.CFrame.Position, pos) end)
end

-- Movimento: "Script" (tween/CFrame) ou "Player" (Humanoid:MoveTo)
local function tweenCore(cf, speed)
    local r = getRoot(); if not r then return end
    speed = speed or val("TweenSpeed", 250)
    local dist = (r.Position - cf.Position).Magnitude
    Phynton.SelfMoving = true
    local tw = TweenService:Create(r, TweenInfo.new(math.max(dist / speed, 0.05), Enum.EasingStyle.Linear), { CFrame = cf })
    tw:Play()
    pcall(function() tw.Completed:Wait() end)
    pcall(function() r.AssemblyLinearVelocity = Vector3.zero end)
    task.delay(0.3, function() Phynton.SelfMoving = false end)
end

local function tweenTo(cf, speed)
    if val("MoveMode", "Script") ~= "Player" then return tweenCore(cf, speed) end
    local r, h = getRoot(), getHum()
    if not (r and h) then return end
    if (r.Position - cf.Position).Magnitude > 220 then return tweenCore(cf, speed) end -- travessias longas
    local done = false
    local conn = h.MoveToFinished:Connect(function() done = true end)
    h:MoveTo(cf.Position)
    local t0 = os.clock()
    local limit = flatDist(r.Position, cf.Position) / math.max(h.WalkSpeed, 8) + 3
    while not done and G.PhyntonHubLoaded and os.clock() - t0 < limit do
        local rr = getRoot()
        if rr and flatDist(rr.Position, cf.Position) < 6 then break end
        task.wait(0.1)
    end
    conn:Disconnect()
end

local function matchName(n, f)
    if not f then return true end
    if type(f) == "table" then
        for _, p in ipairs(f) do if n:find(p, 1, true) then return true end end
        return false
    end
    return n:find(f, 1, true) ~= nil
end

local function enemyFolder() return Workspace:FindFirstChild("Enemies") or Workspace end

local function validEnemy(m)
    if not m or not m:IsA("Model") or m == getChar() then return false end
    if Players:GetPlayerFromCharacter(m) then return false end
    return alive(m:FindFirstChildOfClass("Humanoid")) and m:FindFirstChild("HumanoidRootPart") ~= nil
end

local function nearestEnemy(maxDist, nameFilter)
    local r = getRoot(); if not r then return nil end
    local best, bd = nil, maxDist or 3000
    for _, m in ipairs(enemyFolder():GetChildren()) do
        if validEnemy(m) and matchName(m.Name, nameFilter) then
            local d = (m.HumanoidRootPart.Position - r.Position).Magnitude
            if d < bd then best, bd = m, d end
        end
    end
    return best
end

-- vai ao spawn quando o inimigo ainda nao carregou (streaming)
local function goToSpawn(name)
    local wo = Workspace:FindFirstChild("_WorldOrigin")
    local es = wo and wo:FindFirstChild("EnemySpawns")
    if es then
        for _, s in ipairs(es:GetChildren()) do
            if matchName(s.Name, name) then tweenTo(s.CFrame * CFrame.new(0, 15, 0)); return true end
        end
    end
    return false
end

---------------------------------------------------------------------
-- ARMAS / SKILLS / COMBATE DE FARM
---------------------------------------------------------------------
local TIPS = { "Melee", "Sword", "Blox Fruit", "Gun" }
local rotIdx, rotAt = 0, 0

local function currentTip()
    local m = Phynton.WeaponOverride or val("FarmWeapon", "Melee")
    if m ~= "Rotate" then return m end
    if os.clock() - rotAt > val("RotateTime", 4) then
        rotAt = os.clock(); rotIdx = rotIdx % #TIPS + 1
    end
    return TIPS[math.max(rotIdx, 1)]
end

local function equipTip(tip)
    local char, bp = getChar(), lp:FindFirstChildOfClass("Backpack")
    if not (char and bp) then return nil end
    for _, t in ipairs(char:GetChildren()) do
        if t:IsA("Tool") and t.ToolTip == tip then return t end
    end
    for _, t in ipairs(bp:GetChildren()) do
        if t:IsA("Tool") and t.ToolTip == tip then
            local h = getHum(); if h then h:EquipTool(t) end
            return t
        end
    end
end

local function heldTool() local c = getChar(); return c and c:FindFirstChildOfClass("Tool") end

-- cooldown dinamico lendo a UI de skills [CONFIG]
local function skillReady(toolName, keyName)
    local ok, res = pcall(function()
        local f = lp.PlayerGui.Main.Skills[toolName][keyName]
        local cd = f:FindFirstChild("Cooldown")
        return (not cd) or cd.Size.X.Scale <= 0.01
    end)
    if ok then return res end
    return true
end

local function keysFor(tip)
    return val("Keys_" .. (tip:gsub(" ", "")), {})
end

local function attack(target)
    local tip = currentTip()
    local tool = equipTip(tip)
    if tool then pcall(function() tool:Activate() end) end
    click()
    if flag("FarmSkills") and tool then
        local keys = keysFor(tip)
        local p = partOf(target)
        if p then lookAtTarget(p.Position) end
        for _, k in ipairs({ "Z", "X", "C", "V", "F" }) do
            if keys[k] and skillReady(tool.Name, k) then
                pressKey(Enum.KeyCode[k]); task.wait(0.12)
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

local function lowHP()
    local h = getHum()
    return flag("LowHPFlee") and h ~= nil and h.MaxHealth > 0 and h.Health > 0
        and h.Health / h.MaxHealth < val("FleeHP", 30) / 100
end

-- sobe, ancora o personagem e espera a vida voltar (corrige o "fugir" que voltava na hora)
local function recover()
    local h = getHum(); if not h then return end
    notify("Vida baixa: recuperando...")
    tweenCore(CFrame.new(getRoot().Position + Vector3.new(0, 150, 0)), 400)
    local r = getRoot(); if not r then return end
    Phynton.SelfMoving = true
    pcall(function() r.Anchored = true end)
    local t0 = os.clock()
    while G.PhyntonHubLoaded and h.Parent and h.Health > 0 and h.Health / h.MaxHealth < 0.75 and os.clock() - t0 < 30 do
        task.wait(0.5)
    end
    pcall(function() r.Anchored = false end)
    Phynton.SelfMoving = false
end

local function engage(t, flagId, maxTicks)
    local n = 0
    while G.PhyntonHubLoaded and Phynton.Flags[flagId] and validEnemy(t) and n < (maxTicks or 300) do
        if Phynton.PvPActive then
            task.wait(0.3)
        elseif lowHP() then
            pcall(recover); break
        elseif not Phynton.Paused then
            local r, hum = getRoot(), getHum()
            if r and hum then
                local hrp = t.HumanoidRootPart
                if val("MoveMode", "Script") == "Player" then
                    if flatDist(hrp.Position, r.Position) > 7 then
                        hum:MoveTo(hrp.Position)
                    else
                        r.CFrame = CFrame.lookAt(r.Position, Vector3.new(hrp.Position.X, r.Position.Y, hrp.Position.Z))
                    end
                else
                    Phynton.SelfMoving = true
                    r.CFrame = hrp.CFrame * CFrame.new(0, val("Height", 10), 0) * CFrame.Angles(math.rad(-90), 0, 0)
                    r.AssemblyLinearVelocity = Vector3.zero
                end
                if flag("BringMob") then bringMobs(t) end
                attack(t)
            end
        end
        n = n + 1
        local jitter = (val("MoveMode", "Script") == "Player") and math.random() * 0.06 or 0
        task.wait(val("AtkDelay", 0.1) + jitter)
    end
    Phynton.SelfMoving = false
end

local function killNearest(flagId, nameFilter, maxDist)
    local t = nearestEnemy(maxDist or 3000, nameFilter)
    if not t then return false end
    tweenTo(t.HumanoidRootPart.CFrame * CFrame.new(0, val("Height", 10), 0))
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
            if r and flag("AntiBan") then
                if last and not Phynton.SelfMoving and not Phynton.Paused and (r.Position - last).Magnitude > 120 then
                    Phynton.Paused = true
                    notify("Teleporte detectado: pausando...")
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
        VirtualUser:CaptureController(); VirtualUser:ClickButton2(Vector2.new())
    end)
end)

Phynton.Conns.Noclip = RunService.Stepped:Connect(function()
    pcall(function()
        if flag("Noclip") or Phynton.SelfMoving then
            local c = getChar()
            if c then for _, p in ipairs(c:GetChildren()) do if p:IsA("BasePart") then p.CanCollide = false end end end
        end
    end)
end)

---------------------------------------------------------------------
-- QUESTS [CONFIG]: {nivelMin, quest, indice, inimigo}
---------------------------------------------------------------------
local Quests = {
    [1] = {
        { 1, "BanditQuest1", 1, "Bandit" }, { 10, "JungleQuest", 1, "Monkey" }, { 15, "JungleQuest", 2, "Gorilla" },
        { 30, "BuggyQuest1", 1, "Pirate" }, { 40, "BuggyQuest1", 2, "Brute" }, { 60, "DesertQuest", 1, "Desert Bandit" },
        { 75, "DesertQuest", 2, "Desert Officer" }, { 90, "SnowQuest", 1, "Snow Bandit" }, { 100, "SnowQuest", 2, "Snowman" },
        { 120, "MarineQuest2", 1, "Chief Petty Officer" }, { 150, "SkyQuest", 1, "Sky Bandit" }, { 175, "SkyQuest", 2, "Dark Master" },
        { 190, "PrisonerQuest", 1, "Prisoner" }, { 210, "PrisonerQuest", 2, "Dangerous Prisoner" },
        { 250, "ColosseumQuest", 1, "Toga Warrior" }, { 275, "ColosseumQuest", 2, "Gladiator" },
        { 300, "MagmaQuest", 1, "Military Soldier" }, { 325, "MagmaQuest", 2, "Military Spy" },
        { 375, "FishmanQuest", 1, "Fishman Warrior" }, { 400, "FishmanQuest", 2, "Fishman Commando" },
        { 450, "SkyExp1Quest", 1, "God's Guard" }, { 475, "SkyExp1Quest", 2, "Shanda" },
        { 525, "SkyExp2Quest", 1, "Royal Squad" }, { 550, "SkyExp2Quest", 2, "Royal Soldier" },
        { 625, "FountainQuest", 1, "Galley Pirate" }, { 650, "FountainQuest", 2, "Galley Captain" },
    },
    [2] = {
        { 700, "Area1Quest", 1, "Raider" }, { 725, "Area1Quest", 2, "Mercenary" }, { 775, "Area2Quest", 1, "Swan Pirate" },
        { 800, "Area2Quest", 2, "Factory Staff" }, { 875, "MarineQuest3", 1, "Marine Lieutenant" }, { 900, "MarineQuest3", 2, "Marine Captain" },
        { 950, "ZombieQuest", 1, "Zombie" }, { 975, "ZombieQuest", 2, "Vampire" }, { 1000, "SnowMountainQuest", 1, "Snow Trooper" },
        { 1050, "SnowMountainQuest", 2, "Winter Warrior" }, { 1100, "IceSideQuest", 1, "Lab Subordinate" }, { 1125, "IceSideQuest", 2, "Horned Warrior" },
        { 1175, "FireSideQuest", 1, "Magma Ninja" }, { 1200, "FireSideQuest", 2, "Lava Pirate" }, { 1250, "ShipQuest1", 1, "Ship Deckhand" },
        { 1275, "ShipQuest1", 2, "Ship Engineer" }, { 1300, "ShipQuest2", 1, "Ship Steward" }, { 1325, "ShipQuest2", 2, "Ship Officer" },
        { 1350, "FrostQuest", 1, "Arctic Warrior" }, { 1375, "FrostQuest", 2, "Snow Lurker" }, { 1425, "ForgottenQuest", 1, "Sea Soldier" },
        { 1450, "ForgottenQuest", 2, "Water Fighter" },
    },
    [3] = {
        { 1500, "PiratePortQuest", 1, "Pirate Millionaire" }, { 1525, "PiratePortQuest", 2, "Pistol Billionaire" },
        { 1575, "AmazonQuest", 1, "Dragon Crew Warrior" }, { 1600, "AmazonQuest", 2, "Dragon Crew Archer" },
        { 1625, "AmazonQuest2", 1, "Female Islander" }, { 1650, "AmazonQuest2", 2, "Giant Islander" },
        { 1700, "MarineTreeIsland", 1, "Marine Commodore" }, { 1725, "MarineTreeIsland", 2, "Marine Rear Admiral" },
        { 1775, "DeepForestIsland3", 1, "Fishman Raider" }, { 1800, "DeepForestIsland3", 2, "Fishman Captain" },
        { 1825, "DeepForestIsland", 1, "Forest Pirate" }, { 1850, "DeepForestIsland", 2, "Mythological Pirate" },
        { 1900, "DeepForestIsland2", 1, "Jungle Pirate" }, { 1925, "DeepForestIsland2", 2, "Musketeer Pirate" },
        { 1975, "HauntedQuest1", 1, "Reborn Skeleton" }, { 2000, "HauntedQuest1", 2, "Living Zombie" },
        { 2025, "HauntedQuest2", 1, "Demonic Soul" }, { 2050, "HauntedQuest2", 2, "Posessed Mummy" },
        { 2075, "NutsIslandQuest", 1, "Peanut Scout" }, { 2100, "NutsIslandQuest", 2, "Peanut President" },
        { 2125, "IceCreamIslandQuest", 1, "Ice Cream Chef" }, { 2150, "IceCreamIslandQuest", 2, "Ice Cream Commander" },
        { 2200, "CakeQuest1", 1, "Cookie Crafter" }, { 2225, "CakeQuest1", 2, "Cake Guard" },
        { 2250, "CakeQuest2", 1, "Baking Staff" }, { 2275, "CakeQuest2", 2, "Head Baker" },
        { 2300, "ChocQuest1", 1, "Cocoa Warrior" }, { 2325, "ChocQuest1", 2, "Chocolate Bar Battler" },
        { 2350, "ChocQuest2", 1, "Sweet Thief" }, { 2375, "ChocQuest2", 2, "Candy Rebel" },
        { 2400, "CandyQuest1", 1, "Candy Pirate" }, { 2425, "CandyQuest1", 2, "Snow Demon" },
        { 2450, "TikiQuest1", 1, "Isle Outlaw" }, { 2475, "TikiQuest1", 2, "Island Boy" },
        { 2500, "TikiQuest2", 1, "Sun-kissed Warrior" }, { 2525, "TikiQuest2", 2, "Isle Champion" },
        { 2550, "TikiQuest3", 1, "Serpent Hunter" }, { 2575, "TikiQuest3", 2, "Skull Slayer" },
    },
}
local BoneQuests = {
    { "HauntedQuest1", 1, "Reborn Skeleton" }, { "HauntedQuest1", 2, "Living Zombie" },
    { "HauntedQuest2", 1, "Demonic Soul" }, { "HauntedQuest2", 2, "Posessed Mummy" },
}

local function playerLevel()
    local lvl = 1
    pcall(function() lvl = lp.Data.Level.Value end)
    return lvl
end
local function currentQuest()
    local lvl, pick = playerLevel(), nil
    for _, q in ipairs(Quests[Sea] or {}) do if lvl >= q[1] then pick = q end end
    return pick
end
local function questActive()
    local ok, v = pcall(function() return lp.PlayerGui.Main.Quest.Visible end)
    return ok and v
end
local function questMatches(enemy)
    local ok, v = pcall(function()
        return lp.PlayerGui.Main.Quest.Container.QuestTitle.Title.Text:find(enemy, 1, true) ~= nil
    end)
    return ok and v
end
local function questFarmStep(flagId, q)
    if questActive() and not questMatches(q[4]) then comm("AbandonQuest"); humanWait() end
    if not questActive() then comm("StartQuest", q[2], q[3]); humanWait() end
    if not killNearest(flagId, q[4]) then goToSpawn(q[4]) end
end

---------------------------------------------------------------------
-- MAIN (configuracao geral e de arma)
---------------------------------------------------------------------
build("Main", function()
    addDropdown(Tabs.Main, "Mode", "MODO GERAL (Player / Scripter)", { "Player", "Scripter" }, "Player", false, function(v)
        if Phynton.Ready then applyMode(v) end
    end)
    par(Tabs.Main, { Title = "Player x Scripter", Content = "Player: anda com o Humanoid, não puxa NPCs, ataque mais lento (parece jogador). Scripter: voa/tween sobre o alvo, junta os NPCs, noclip e ataque rápido." })
    addToggle(Tabs.Main, "AntiBan", "Anti-Ban (esperas + pausa em teleporte)", true)
    addToggle(Tabs.Main, "Noclip", "Noclip", false)
    addDropdown(Tabs.Main, "MoveMode", "Modo de movimento (Script / Player)", { "Script", "Player" }, "Script", false)
    par(Tabs.Main, { Title = "Script x Player", Content = "Script: tween/CFrame (rápido). Player: anda com o Humanoid, como jogador normal (acima de 220 studs usa tween)." })
    addSlider(Tabs.Main, "TweenSpeed", "Velocidade do tween", 100, 400, 250, 0)

    sec(Tabs.Main, "Arma do farm")
    addDropdown(Tabs.Main, "FarmWeapon", "Usar no farm", { "Melee", "Sword", "Blox Fruit", "Gun", "Rotate" }, "Melee", false)
    addSlider(Tabs.Main, "RotateTime", "Trocar de arma a cada (s) [Rotate]", 2, 15, 4, 0)
    addToggle(Tabs.Main, "FarmSkills", "Usar skills no farm", true)
    local K = { "Z", "X", "C", "V", "F" }
    addDropdown(Tabs.Main, "Keys_Melee", "Teclas: Melee", K, { Z = true, X = true }, true)
    addDropdown(Tabs.Main, "Keys_Sword", "Teclas: Espada", K, { Z = true, X = true }, true)
    addDropdown(Tabs.Main, "Keys_BloxFruit", "Teclas: Fruta", K, { Z = true, X = true, C = true }, true)
    addDropdown(Tabs.Main, "Keys_Gun", "Teclas: Arma de fogo", K, { Z = true }, true)

    sec(Tabs.Main, "Farm")
    addSlider(Tabs.Main, "Height", "Altura sobre o inimigo", 5, 30, 10, 0)
    addSlider(Tabs.Main, "AtkDelay", "Delay do ataque (s)", 0.03, 0.4, 0.1, 2)
    addToggle(Tabs.Main, "BringMob", "Bring Mob (puxar inimigos)", false)
    addToggle(Tabs.Main, "LowHPFlee", "Recuperar com pouca vida", true)
    addSlider(Tabs.Main, "FleeHP", "% de vida para recuperar", 15, 50, 30, 0)
end)

---------------------------------------------------------------------
-- FARM
---------------------------------------------------------------------
build("Farm", function()
    addLoopToggle(Tabs.Farm, "FarmLevel", "Auto Farm Level (com quest)", function()
        local q = currentQuest(); if not q then return end
        questFarmStep("FarmLevel", q)
    end, 0.3)

    addLoopToggle(Tabs.Farm, "FarmBone", "Auto Farm Bone (Sea 3)", function()
        if Sea ~= 3 then return end
        local pick
        for _, q in ipairs(BoneQuests) do
            if nearestEnemy(3000, q[3]) then pick = q; break end
        end
        questFarmStep("FarmBone", pick or BoneQuests[1])
    end, 0.3)

    addInput(Tabs.Farm, "BossName", "Nome do Boss", "", "ex: Greybeard")
    addLoopToggle(Tabs.Farm, "FarmBoss", "Auto Farm Boss (pelo nome)", function()
        local name = val("BossName", "")
        if name == "" then return end
        if not killNearest("FarmBoss", name) then goToSpawn(name); humanWait() end
    end, 0.3)

    -- baus: usa a tag do jogo e guarda em cache (nada de GetDescendants em loop)
    local cache, cacheAt = {}, 0
    local function chests()
        if os.clock() - cacheAt > 5 then
            cacheAt = os.clock()
            cache = CollectionService:GetTagged("_ChestTagged")
        end
        return cache
    end
    addSlider(Tabs.Farm, "ChestRange", "Alcance dos baús (studs)", 200, 5000, 1500, 0)
    addLoopToggle(Tabs.Farm, "AutoChest", "Auto Chest", function()
        local r = getRoot(); if not r then return end
        local best, bd = nil, val("ChestRange", 1500)
        for _, c in ipairs(chests()) do
            if c.Parent then
                local p = c:IsA("Model") and c:GetPivot().Position or c.Position
                local d = (p - r.Position).Magnitude
                if d < bd then best, bd = c, d end
            end
        end
        if best then
            tweenTo(best:IsA("Model") and best:GetPivot() or best.CFrame)
        end
        humanWait()
    end, 0.3)
end)

---------------------------------------------------------------------
-- ITEMS
---------------------------------------------------------------------
build("Items", function()
    -- somente Tools soltas no Workspace (frutas, espadas dropadas); sem varrer o mapa inteiro
    addSlider(Tabs.Items, "ItemRange", "Alcance dos itens (studs)", 100, 3000, 600, 0)
    addLoopToggle(Tabs.Items, "PickItems", "Pegar Itens / Frutas / Espadas", function()
        local r = getRoot(); if not r then return end
        for _, d in ipairs(Workspace:GetChildren()) do
            if d:IsA("Tool") or (d:IsA("Model") and d.Name:find("Fruit", 1, true)) then
                local h = d:FindFirstChild("Handle") or partOf(d)
                if h and (h.Position - r.Position).Magnitude < val("ItemRange", 600) then
                    tweenTo(h.CFrame); humanWait(); return
                end
            end
        end
    end, 1.5)

    addLoopToggle(Tabs.Items, "StoreFruit", "Guardar frutas (Auto Store)", function()
        local bp = lp:FindFirstChildOfClass("Backpack"); if not bp then return end
        for _, t in ipairs(bp:GetChildren()) do
            if t:IsA("Tool") and t.Name:find("Fruit", 1, true) then
                comm("StoreFruit", t:GetAttribute("OriginalName") or t.Name, t)
            end
        end
    end, 5)

    addLoopToggle(Tabs.Items, "RandomFruit", "Auto Random Fruit", function()
        comm("Cousin", "Buy"); humanWait()
    end, 2)

    addLoopToggle(Tabs.Items, "RandomBone", "Auto Random Bone", function()
        comm("Bones", "Buy", 1, 1); humanWait()
    end, 1)

    addButton(Tabs.Items, "Pegar item mais próximo agora", function()
        local r = getRoot(); if not r then return notify("Sem personagem") end
        for _, d in ipairs(Workspace:GetChildren()) do
            if d:IsA("Tool") then
                local h = d:FindFirstChild("Handle")
                if h and (h.Position - r.Position).Magnitude < 800 then
                    notify("Indo pegar: " .. d.Name); tweenTo(h.CFrame); return
                end
            end
        end
        notify("Nenhum item perto")
    end)
end)

---------------------------------------------------------------------
-- COMBAT (Aimbot, Dodge, Auto Skills, PvP)
---------------------------------------------------------------------
build("Combat", function()
    -- Aimbot (RenderStepped = sem tremedeira)
    local function candidates()
        local list, mode = {}, val("AimMode", "Players")
        if mode == "Players" or mode == "Both" then
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= lp and p.Character then
                    local same = flag("AimTeam") and p.Team ~= nil and lp.Team ~= nil and p.Team == lp.Team
                    local h, hrp = p.Character:FindFirstChildOfClass("Humanoid"), p.Character:FindFirstChild("HumanoidRootPart")
                    if not same and alive(h) and hrp then table.insert(list, hrp) end
                end
            end
        end
        if mode == "NPCs" or mode == "Both" then
            for _, m in ipairs(enemyFolder():GetChildren()) do
                if validEnemy(m) then table.insert(list, m.HumanoidRootPart) end
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
                if d < bd then best, bd = hrp, d end
            end
        end
        return best
    end
    addDropdown(Tabs.Combat, "AimMode", "Alvos do Aimbot", { "Players", "NPCs", "Both" }, "Players", false)
    addToggle(Tabs.Combat, "AimTeam", "Team Check (ignorar aliados)", true)
    addSlider(Tabs.Combat, "AimPredict", "Predição", 0, 0.5, 0.12, 2)
    addSlider(Tabs.Combat, "AimSmooth", "Suavidade (Lerp)", 0.05, 1, 0.3, 2)
    addSlider(Tabs.Combat, "AimFov", "Raio do FOV", 50, 600, 250, 0)
    addToggle(Tabs.Combat, "Aimbot", "Aimbot", false, function(on)
        if Phynton.Conns.Aim then Phynton.Conns.Aim:Disconnect(); Phynton.Conns.Aim = nil end
        if not on then return end
        Phynton.Conns.Aim = RunService.RenderStepped:Connect(function()
            pcall(function()
                if Phynton.Paused then return end
                local t = pick(); if not t then return end
                local aimPos = t.Position + t.AssemblyLinearVelocity * val("AimPredict", 0.12)
                cam.CFrame = cam.CFrame:Lerp(CFrame.new(cam.CFrame.Position, aimPos), val("AimSmooth", 0.3))
            end)
        end)
    end)

    -- Dodge
    local lastDodge = 0
    addSlider(Tabs.Combat, "DodgeRange", "Alcance do Dodge", 20, 120, 60, 0)
    addLoopToggle(Tabs.Combat, "Dodge", "Dodge System (esquiva)", function()
        local r = getRoot(); if not r or os.clock() - lastDodge < 0.6 then return end
        local params = OverlapParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { getChar() }
        for _, p in ipairs(Workspace:GetPartBoundsInRadius(r.Position, val("DodgeRange", 60), params)) do
            local m = p:FindFirstAncestorOfClass("Model")
            if not p.Anchored and not (m and m:FindFirstChildOfClass("Humanoid")) then
                local vel = p.AssemblyLinearVelocity
                if vel.Magnitude > 30 then
                    local toMe = r.Position - p.Position
                    if vel.Unit:Dot(toMe.Unit) > 0.9 and (toMe.Magnitude / vel.Magnitude) < 1 then
                        local side = (math.random() > 0.5) and 1 or -1
                        Phynton.SelfMoving = true
                        r.CFrame = r.CFrame + vel.Unit:Cross(Vector3.yAxis).Unit * side * 12
                        task.delay(0.3, function() Phynton.SelfMoving = false end)
                        lastDodge = os.clock()
                        return
                    end
                end
            end
        end
    end, 0.08)

    -- Auto Skills (usa as teclas da arma equipada e respeita cooldown)
    addSlider(Tabs.Combat, "SkillGap", "Intervalo entre skills (s)", 0.2, 3, 0.6, 1)
    addLoopToggle(Tabs.Combat, "AutoSkills", "Auto Skills no alvo", function()
        local t = nearestEnemy(120); if not t then return end
        local tool = heldTool(); if not tool then return end
        local p = partOf(t); if p then lookAtTarget(p.Position) end
        local keys = keysFor(tool.ToolTip ~= "" and tool.ToolTip or currentTip())
        for _, k in ipairs({ "Z", "X", "C", "V", "F" }) do
            if keys[k] and skillReady(tool.Name, k) then
                pressKey(Enum.KeyCode[k]); task.wait(val("SkillGap", 0.6))
            end
        end
    end, 0.1)

    ---------------------------------------------------------------
    -- PvP: ao ser atacado por outro jogador, trava nele e faz combo
    ---------------------------------------------------------------
    sec(Tabs.Combat, "PvP")
    local ComboNames = { "HUD: Melee > Espada > Fruta", "Melee pesado", "Fruit burst", "Espada rápida", "Custom" }
    local ComboPresets = {
        ["HUD: Melee > Espada > Fruta"] = "@Melee,HUD,@Sword,HUD,@Fruit,HUD,M1,M1",
        ["Melee pesado"] = "@Melee,M1,M1,Z,X,C,M1,M1,V",
        ["Fruit burst"] = "@Fruit,Z,X,C,V,F,M1",
        ["Espada rápida"] = "@Sword,M1,M1,Z,X,M1,M1,Z,X",
    }
    local TIPNAME = { Melee = "Melee", Sword = "Sword", Fruit = "Blox Fruit", Gun = "Gun" }
    local PvP = { Target = nil, Until = 0 }

    local function sameTeam(p) return flag("PvPTeam") and p.Team ~= nil and lp.Team ~= nil and p.Team == lp.Team end

    local function nearestPlayer(range)
        local r = getRoot(); if not r then return nil end
        local best, bd = nil, range
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= lp and p.Character and not sameTeam(p) then
                local h, hrp = p.Character:FindFirstChildOfClass("Humanoid"), p.Character:FindFirstChild("HumanoidRootPart")
                if alive(h) and hrp and (not flag("PvPNeedTool") or p.Character:FindFirstChildOfClass("Tool")) then
                    local d = (hrp.Position - r.Position).Magnitude
                    if d < bd then best, bd = p, d end
                end
            end
        end
        return best
    end

    local function targetRoot()
        local c = PvP.Target and PvP.Target.Character
        return c and c:FindFirstChild("HumanoidRootPart")
    end

    local function stick()
        local tr, r, hum = targetRoot(), getRoot(), getHum()
        if not (tr and r and hum) then return end
        local d = val("PvPDist", 5)
        if val("MoveMode", "Script") == "Player" then
            if (tr.Position - r.Position).Magnitude > d + 3 then hum:MoveTo(tr.Position) end
        else
            Phynton.SelfMoving = true
            r.CFrame = CFrame.lookAt((tr.CFrame * CFrame.new(0, 0, d)).Position, tr.Position)
            r.AssemblyLinearVelocity = Vector3.zero
        end
        lookAtTarget(tr.Position)
    end

    local function pressSkill(k)
        local code; pcall(function() code = Enum.KeyCode[k] end)
        if not code then return end
        local tool = heldTool()
        local t0 = os.clock()
        while tool and not skillReady(tool.Name, k) and os.clock() - t0 < 0.5 do task.wait(0.05) end
        if tool and not skillReady(tool.Name, k) then return end
        stick()
        pressKey(code); task.wait(0.15)
    end

    local function runCombo(str)
        for tok in string.gmatch(str, "[^,%s]+") do
            if not (G.PhyntonHubLoaded and Phynton.PvPActive) then return end
            local up = tok:upper()
            if up == "M1" then
                stick(); click(); task.wait(0.12)
            elseif tok:sub(1, 1) == "@" then
                equipTip(TIPNAME[tok:sub(2)] or tok:sub(2)); task.wait(0.15)
            elseif tok:match("^[Ww][%d%.]+$") then
                task.wait(tonumber(tok:sub(2)) or 0.2)
            elseif up == "HUD" then
                local tool = heldTool()
                local tip = (tool and tool.ToolTip ~= "") and tool.ToolTip or "Melee"
                local keys = keysFor(tip)
                for _, k in ipairs({ "Z", "X", "C", "V", "F" }) do if keys[k] then pressSkill(k) end end
            elseif #up == 1 then
                pressSkill(up)
            end
        end
    end

    local function comboString()
        local pr = val("ComboPreset", ComboNames[1])
        if pr == "Custom" then return val("ComboCustom", "") end
        return ComboPresets[pr] or ComboPresets[ComboNames[1]]
    end

    local function startPvP(plr)
        PvP.Until = os.clock() + val("PvPDuration", 12)
        PvP.Target = plr
        if Phynton.PvPActive then return end
        Phynton.PvPActive = true
        notify("PvP: " .. plr.DisplayName)
        task.spawn(function()
            while G.PhyntonHubLoaded and flag("PvPMode") and os.clock() < PvP.Until do
                pcall(function()
                    local c = PvP.Target and PvP.Target.Character
                    local th, tr, r = c and c:FindFirstChildOfClass("Humanoid"), targetRoot(), getRoot()
                    if not (alive(th) and tr and r) then PvP.Until = 0; return end
                    if (tr.Position - r.Position).Magnitude > val("PvPRange", 45) * 2 then PvP.Until = 0; return end
                    stick()
                    runCombo(comboString())
                end)
                task.wait(0.05)
            end
            Phynton.PvPActive = false
            Phynton.SelfMoving = false
            PvP.Target = nil
        end)
    end

    local function hook(char)
        local h = char:WaitForChild("Humanoid", 10); if not h then return end
        local last = h.Health
        h.HealthChanged:Connect(function(hp)
            if flag("PvPMode") and hp < last and hp > 0 then
                local p = nearestPlayer(val("PvPRange", 45))
                if p then startPvP(p) end
            end
            last = hp
        end)
    end
    if lp.Character then task.spawn(hook, lp.Character) end
    lp.CharacterAdded:Connect(function(c) task.spawn(hook, c) end)

    addToggle(Tabs.Combat, "PvPMode", "Modo PvP (contra-atacar ao ser atacado)", false)
    addSlider(Tabs.Combat, "PvPRange", "Alcance para detectar o atacante", 15, 100, 45, 0)
    addSlider(Tabs.Combat, "PvPDuration", "Duração do contra-ataque (s)", 5, 30, 12, 0)
    addSlider(Tabs.Combat, "PvPDist", "Distância ao alvo", 3, 12, 5, 0)
    addToggle(Tabs.Combat, "PvPTeam", "Ignorar aliados (team check)", true)
    addToggle(Tabs.Combat, "PvPNeedTool", "Só reagir a quem está com arma na mão", true)
    addDropdown(Tabs.Combat, "ComboPreset", "Combo", ComboNames, ComboNames[1], false)
    addInput(Tabs.Combat, "ComboCustom", "Combo Custom", "@Melee,HUD,@Sword,HUD,M1", "@Melee,Z,X,M1,W0.3")
    par(Tabs.Combat, { Title = "Combo: como escrever", Content = "Separe por vírgula. Z X C V F = skill; M1 = ataque básico; @Melee/@Sword/@Fruit/@Gun = trocar de arma; W0.3 = esperar 0.3s; HUD = usa as teclas configuradas na aba Main para a arma atual." })
end)

---------------------------------------------------------------------
-- MOVEMENT
---------------------------------------------------------------------
build("Movement", function()
    -- Fly (BodyVelocity horizontal + AlignPosition na altura)
    local bv, ap, att, targetY
    local function cleanup()
        if Phynton.Conns.Fly then Phynton.Conns.Fly:Disconnect(); Phynton.Conns.Fly = nil end
        for _, o in ipairs({ bv, ap, att }) do if o then pcall(function() o:Destroy() end) end end
        bv, ap, att = nil, nil, nil
    end
    addSlider(Tabs.Movement, "FlySpeed", "Velocidade do voo", 20, 200, 80, 0)
    addButton(Tabs.Movement, "Voo: subir", function() if targetY then targetY = targetY + 10 end end)
    addButton(Tabs.Movement, "Voo: descer", function() if targetY then targetY = targetY - 10 end end)
    addToggle(Tabs.Movement, "Fly", "Voar (Fly)", false, function(on)
        cleanup()
        if not on then return end
        local r = getRoot(); if not (r and getHum()) then return end
        targetY = r.Position.Y
        att = Instance.new("Attachment"); att.Parent = r
        bv = Instance.new("BodyVelocity"); bv.MaxForce = Vector3.new(1e6, 0, 1e6); bv.Velocity = Vector3.zero; bv.Parent = r
        ap = Instance.new("AlignPosition")
        ap.Mode = Enum.PositionAlignmentMode.OneAttachment; ap.Attachment0 = att
        ap.ForceLimitMode = Enum.ForceLimitMode.PerAxis; ap.MaxAxesForce = Vector3.new(0, 1e6, 0)
        ap.Responsiveness = 40; ap.Position = r.Position; ap.Parent = r
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

    -- Orbita (seno/cosseno)
    local angle = 0
    addSlider(Tabs.Movement, "OrbitDist", "Distância da órbita", 5, 40, 15, 0)
    addSlider(Tabs.Movement, "OrbitSpeed", "Velocidade da órbita", 1, 10, 3, 1)
    addToggle(Tabs.Movement, "Orbit", "Órbita no alvo (NPC/Boss)", false, function(on)
        if Phynton.Conns.Orbit then Phynton.Conns.Orbit:Disconnect(); Phynton.Conns.Orbit = nil end
        if not on then return end
        Phynton.Conns.Orbit = RunService.Heartbeat:Connect(function(dt)
            pcall(function()
                if Phynton.Paused or Phynton.PvPActive then return end
                local r = getRoot(); if not r then return end
                local t = nearestEnemy(300); if not t then return end
                local tp = t.HumanoidRootPart.Position
                angle = angle + val("OrbitSpeed", 3) * dt
                local d = val("OrbitDist", 15)
                Phynton.SelfMoving = true
                r.CFrame = CFrame.new(tp + Vector3.new(math.cos(angle) * d, 3, math.sin(angle) * d), tp)
                r.AssemblyLinearVelocity = Vector3.zero
            end)
        end)
    end)

    -- Auto Mobility (X/Z) com cooldown dinamico
    addSlider(Tabs.Movement, "MobGap", "Mobility: intervalo mínimo (s)", 0.2, 3, 0.8, 1)
    local lastPress = { X = 0, Z = 0 }
    addLoopToggle(Tabs.Movement, "Mobility", "Auto Mobility (X/Z)", function()
        local tool = heldTool(); if not tool then return end
        for name, code in pairs({ X = Enum.KeyCode.X, Z = Enum.KeyCode.Z }) do
            if os.clock() - lastPress[name] >= val("MobGap", 0.8) and skillReady(tool.Name, name) then
                pressKey(code); lastPress[name] = os.clock(); task.wait(0.15)
            end
        end
    end, 0.1)

    -- Fast Attack (delay lido a cada ciclo, nao so ao ligar)
    addLoopToggle(Tabs.Movement, "FastAttack", "Fast Attack", function()
        local tool = equipTip(currentTip()); if not tool then return end
        for _, v in ipairs(tool:GetDescendants()) do
            if (v:IsA("NumberValue") or v:IsA("IntValue")) and v.Name:lower():find("attackspeed", 1, true) then
                pcall(function() v.Value = math.min(v.Value, val("AtkDelay", 0.1)) end)
            end
        end
        pcall(function() tool:Activate() end)
        click()
    end, function() return val("AtkDelay", 0.1) end)

    addSlider(Tabs.Movement, "WalkSpeedVal", "WalkSpeed", 16, 200, 16, 0)
    addToggle(Tabs.Movement, "WalkSpeedOn", "Aplicar WalkSpeed", false, function(on)
        if Phynton.Conns.WS then Phynton.Conns.WS:Disconnect(); Phynton.Conns.WS = nil end
        if not on then
            local h = getHum(); if h then h.WalkSpeed = 16 end
            return
        end
        Phynton.Conns.WS = RunService.Heartbeat:Connect(function()
            pcall(function() local h = getHum(); if h then h.WalkSpeed = val("WalkSpeedVal", 16) end end)
        end)
    end)

    addToggle(Tabs.Movement, "InfJump", "Pulo infinito", false, function(on)
        if Phynton.Conns.IJ then Phynton.Conns.IJ:Disconnect(); Phynton.Conns.IJ = nil end
        if not on then return end
        Phynton.Conns.IJ = UIS.JumpRequest:Connect(function()
            pcall(function() local h = getHum(); if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end end)
        end)
    end)
end)

---------------------------------------------------------------------
-- SEA EVENTS
---------------------------------------------------------------------
build("Sea", function()
    local SeaPatterns = {
        ["Terrorshark"] = { "Terrorshark" },
        ["Piranha"] = { "Piranha" },
        ["Fish Crew (barco)"] = { "FishBoat" },
        ["Pirate Brigade"] = { "PirateBrigade", "Pirate Brigade" },
        ["Pirate Grand Brigade"] = { "PirateGrandBrigade" },
        ["Sea Beast"] = { "SeaBeast" },
        ["Leviathan"] = { "Leviathan" },
        ["Ghost Ship"] = { "GhostShip", "Ghost Ship" },
    }
    local SeaNames = { "Terrorshark", "Piranha", "Fish Crew (barco)", "Pirate Brigade", "Pirate Grand Brigade", "Sea Beast", "Leviathan", "Ghost Ship" }

    local function seaTarget()
        local sel, names = val("SeaSel", {}), {}
        for k, on in pairs(sel) do
            if on and SeaPatterns[k] then for _, pat in ipairs(SeaPatterns[k]) do table.insert(names, pat) end end
        end
        if #names == 0 then return nil end
        local r = getRoot(); if not r then return nil end
        local best, bd = nil, math.huge
        for _, folder in ipairs({ Workspace:FindFirstChild("SeaBeasts"), Workspace:FindFirstChild("Boats"), enemyFolder() }) do
            if folder then
                for _, m in ipairs(folder:GetChildren()) do
                    -- ignora barcos de jogadores (tem Owner)
                    if m:IsA("Model") and matchName(m.Name, names) and not m:FindFirstChild("Owner") then
                        local h, p = m:FindFirstChildOfClass("Humanoid"), partOf(m)
                        if p and (not h or h.Health > 0) then
                            local d = (p.Position - r.Position).Magnitude
                            if d < bd then best, bd = m, d end
                        end
                    end
                end
            end
        end
        return best
    end

    local function engageSea(m)
        Phynton.WeaponOverride = val("SeaWeapon", "Blox Fruit")
        local n = 0
        while G.PhyntonHubLoaded and Phynton.Flags.SeaFarm and m.Parent and n < 500 do
            local h = m:FindFirstChildOfClass("Humanoid")
            if h and h.Health <= 0 then break end
            if Phynton.PvPActive then
                task.wait(0.3)
            elseif lowHP() then
                pcall(recover); break
            elseif not Phynton.Paused then
                local p, r = partOf(m), getRoot()
                if not (p and r) then break end
                Phynton.SelfMoving = true
                r.CFrame = p.CFrame * CFrame.new(0, val("SeaHeight", 40), 0) * CFrame.Angles(math.rad(-90), 0, 0)
                r.AssemblyLinearVelocity = Vector3.zero
                attack(m)
            end
            n = n + 1
            task.wait(val("AtkDelay", 0.1))
        end
        Phynton.WeaponOverride = nil
        Phynton.SelfMoving = false
    end

    addDropdown(Tabs.Sea, "SeaSel", "Eventos para fazer", SeaNames, { Terrorshark = true, ["Sea Beast"] = true, ["Pirate Brigade"] = true }, true)
    addDropdown(Tabs.Sea, "SeaWeapon", "Arma nos eventos", { "Blox Fruit", "Sword", "Gun", "Melee" }, "Blox Fruit", false)
    addSlider(Tabs.Sea, "SeaHeight", "Altura sobre o alvo", 15, 80, 40, 0)
    par(Tabs.Sea, { Title = "Eventos do mar", Content = "No mar o script usa voo/CFrame (não dá para andar na água), mesmo no modo Player. Marque os eventos, ligue 'Fazer eventos' e, se quiser, 'Explorar o mar'." })

    addLoopToggle(Tabs.Sea, "SeaFarm", "Fazer eventos selecionados", function()
        local m = seaTarget(); if not m then return end
        engageSea(m)
    end, 0.4)

    -- procura eventos em espiral ao redor do ponto onde voce ligou
    local spiral = { n = 0, center = nil }
    addToggle(Tabs.Sea, "SeaExplore", "Explorar o mar procurando eventos", false, function(on)
        if not on then return end
        spiral.center, spiral.n = nil, 0
        startLoop("SeaExplore", function()
            if seaTarget() then return end
            local r = getRoot(); if not r then return end
            if not spiral.center then spiral.center = r.Position end
            spiral.n = spiral.n + 1
            if spiral.n > 60 then spiral.n = 1 end
            local ang, rad = spiral.n * 0.9, 400 + spiral.n * 120
            local pos = spiral.center + Vector3.new(math.cos(ang) * rad, val("SeaHeight", 40), math.sin(ang) * rad)
            tweenCore(CFrame.new(pos), val("TweenSpeed", 250))
            task.wait(1)
        end, 0.5)
    end)

    addDropdown(Tabs.Sea, "BoatType", "Barco", { "PirateBrigade", "PirateGrandBrigade", "MarineBrigade", "Beast Hunter", "Sloop" }, "PirateBrigade", false)
    addButton(Tabs.Sea, "Comprar barco", function() comm("BuyBoat", val("BoatType", "PirateBrigade")) end)
end)

---------------------------------------------------------------------
-- CRAFT (juntar materiais e craftar) [CONFIG]
---------------------------------------------------------------------
build("Craft", function()
    -- de onde cada material dropa (ajuste se algum nao bater no seu mar)
    local MatSources = {
        ["Magma Ore"] = { "Military Soldier", "Military Spy", "Magma Ninja", "Lava Pirate" },
        ["Angel Wings"] = { "God's Guard", "Shanda", "Royal Squad", "Royal Soldier" },
        ["Mystic Droplet"] = { "Water Fighter", "Sea Soldier" },
        ["Vampire Fang"] = { "Vampire" },
        ["Ectoplasm"] = { "Ship Deckhand", "Ship Engineer", "Ship Steward", "Ship Officer" },
        ["Radioactive Material"] = { "Factory Staff" },
        ["Conjured Cocoa"] = { "Cocoa Warrior", "Chocolate Bar Battler", "Sweet Thief", "Candy Rebel" },
        ["Demonic Wisp"] = { "Demonic Soul" },
        ["Dragon Scale"] = { "Dragon Crew Warrior", "Dragon Crew Archer" },
        ["Gunpowder"] = { "Pistol Billionaire" },
        ["Bones"] = { "Reborn Skeleton", "Living Zombie", "Demonic Soul", "Posessed Mummy" },
    }
    local MatNames = {}
    for k in pairs(MatSources) do table.insert(MatNames, k) end
    table.sort(MatNames)
    table.insert(MatNames, "Custom")

    local invCache, invAt = nil, 0
    local function materialCount(name)
        if os.clock() - invAt > 4 then
            invAt = os.clock()
            local inv = comm("getInventory")
            if type(inv) == "table" then invCache = inv end
        end
        if not invCache then return nil end
        for _, it in pairs(invCache) do
            if type(it) == "table" and it.Name == name then return tonumber(it.Count) or tonumber(it.Amount) or 1 end
        end
        return 0
    end

    local function matEnemies()
        local manual = val("MatEnemy", "")
        if manual ~= "" then return manual end
        return MatSources[val("MatName", MatNames[1])]
    end

    local lastWarn = 0
    local function warnOnce(msg)
        if os.clock() - lastWarn > 10 then lastWarn = os.clock(); notify(msg) end
    end

    local function craftNow()
        local item = val("CraftItem", "")
        if item == "" then warnOnce("Digite o nome do item para craftar"); return end
        comm("CraftItem", "Craft", item)
        invAt = 0
    end

    local function farmStep(flagId)
        local names = matEnemies()
        if not names then warnOnce("Material 'Custom': preencha o inimigo manual"); humanWait(); return end
        if not killNearest(flagId, names) then goToSpawn(names); humanWait() end
    end

    addDropdown(Tabs.Craft, "MatName", "Material", MatNames, MatNames[1], false)
    addInput(Tabs.Craft, "MatEnemy", "Inimigo manual (opcional)", "", "ex: Vampire")
    addSlider(Tabs.Craft, "MatAmount", "Quantidade desejada", 1, 500, 20, 0)
    addInput(Tabs.Craft, "CraftItem", "Item para craftar", "", "nome exato do item")

    addButton(Tabs.Craft, "Ver quantidade do material", function()
        local mat = val("MatName", MatNames[1])
        local c = materialCount(mat)
        notify(c and (mat .. ": " .. c) or "Inventário indisponível")
    end)
    addButton(Tabs.Craft, "Craftar agora", craftNow)

    addLoopToggle(Tabs.Craft, "FarmMaterial", "Só farmar material (até a meta)", function()
        local have = materialCount(val("MatName", MatNames[1]))
        if have and have >= val("MatAmount", 20) then
            notify("Meta de material atingida!")
            Phynton.Flags.FarmMaterial = false
            setUI("FarmMaterial", false)
            return
        end
        farmStep("FarmMaterial")
    end, 0.3)

    addLoopToggle(Tabs.Craft, "CraftCycle", "Ciclo completo: farmar → craftar → repetir", function()
        local have = materialCount(val("MatName", MatNames[1]))
        if have == nil or have < val("MatAmount", 20) then
            farmStep("CraftCycle")
        else
            craftNow(); humanWait()
        end
    end, 0.3)
end)

---------------------------------------------------------------------
-- ICONE FLUTUANTE PHY
---------------------------------------------------------------------
local IconGui
build("Icon", function()
    local ok = pcall(function()
        local parent = (gethui and gethui()) or game:GetService("CoreGui")
        IconGui = Instance.new("ScreenGui")
        IconGui.Name = "PhyntonIcon"; IconGui.ResetOnSpawn = false
        IconGui.DisplayOrder = 999; IconGui.IgnoreGuiInset = true
        IconGui.Parent = parent
    end)
    if not ok then
        IconGui = Instance.new("ScreenGui")
        IconGui.Name = "PhyntonIcon"; IconGui.ResetOnSpawn = false
        IconGui.Parent = lp:WaitForChild("PlayerGui")
    end

    local btn = Instance.new("TextButton")
    btn.Name = "PHYButton"; btn.Size = UDim2.fromOffset(54, 54)
    btn.Position = UDim2.new(0, 16, 0.35, 0)
    btn.BackgroundColor3 = Color3.fromRGB(24, 24, 32)
    btn.AutoButtonColor = false
    btn.Text = "PHY"; btn.TextColor3 = Color3.fromRGB(170, 120, 255)
    btn.Font = Enum.Font.GothamBold; btn.TextScaled = true
    btn.Parent = IconGui
    Instance.new("UICorner", btn).CornerRadius = UDim.new(1, 0)
    local stroke = Instance.new("UIStroke", btn)
    stroke.Color = Color3.fromRGB(150, 90, 255); stroke.Thickness = 2
    local pad = Instance.new("UIPadding", btn)
    pad.PaddingLeft = UDim.new(0, 9); pad.PaddingRight = UDim.new(0, 9)
    pad.PaddingTop = UDim.new(0, 14); pad.PaddingBottom = UDim.new(0, 14)

    local dragging, moved, activeInput, dragStart, startPos = false, false, nil, nil, nil
    btn.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging, moved, activeInput = true, false, input
            dragStart, startPos = input.Position, btn.Position
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
            if not moved then pcall(function() Window:Minimize() end) end
        end
    end)
end)

---------------------------------------------------------------------
-- EXTRA
---------------------------------------------------------------------
build("Extra", function()
    addToggle(Tabs.Extra, "ShowIcon", "Ícone flutuante PHY", true, function(on)
        if IconGui then IconGui.Enabled = on end
    end)

    -- Server hop de verdade: escolhe outro servidor publico com vaga
    addButton(Tabs.Extra, "Server Hop", function()
        notify("Procurando outro servidor...")
        local ok, body = pcall(function()
            return game:HttpGet("https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?sortOrder=Asc&limit=100")
        end)
        if ok then
            local ok2, data = pcall(function() return HttpService:JSONDecode(body) end)
            if ok2 and data and data.data then
                local cands = {}
                for _, s in ipairs(data.data) do
                    if s.id ~= game.JobId and s.playing < s.maxPlayers - 1 then table.insert(cands, s.id) end
                end
                if #cands > 0 then
                    TeleportService:TeleportToPlaceInstance(game.PlaceId, cands[math.random(#cands)], lp)
                    return
                end
            end
        end
        TeleportService:Teleport(game.PlaceId, lp)
    end)

    addButton(Tabs.Extra, "Info do Servidor", function()
        notify(string.format("Players: %d/%d | Sea %d | Level %d", #Players:GetPlayers(), Players.MaxPlayers, Sea, playerLevel()))
    end)

    addLoopToggle(Tabs.Extra, "AutoHaki", "Auto Haki (Buso)", function()
        local c = getChar()
        if c and not c:FindFirstChild("HasBuso") then comm("Buso") end
    end, 4)
end)

---------------------------------------------------------------------
-- FINALIZACAO
---------------------------------------------------------------------
lp.CharacterAdded:Connect(function() Phynton.SelfMoving = false end)

if #ErrorLog > 0 then
    par(Tabs.Extra, { Title = "Erros de carregamento", Content = table.concat(ErrorLog, "\n") })
    notify("Alguns módulos falharam: veja a aba Extra", 8)
end

Phynton.Ready = true
applyMode(val("Mode", "Player"))

Window:SelectTab(1)
notify("Phynton Lite v2 carregado! Toque no ícone PHY para minimizar.", 5)
