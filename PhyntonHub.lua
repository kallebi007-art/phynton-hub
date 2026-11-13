--[[
    Phynton Hub  |  Luau (Roblox)  |  Fluent UI  |  Mobile friendly
    Modular: Core -> Helpers -> Modules -> UI
    Todos os loops usam task.spawn + pcall.
    NOTA: remotes/quests/raids variam por versao do jogo. Os trechos marcados
    com [CONFIG] devem ser ajustados para o jogo que voce usa.
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
local VIM               = game:GetService("VirtualInputManager")
local VirtualUser       = game:GetService("VirtualUser")

local lp  = Players.LocalPlayer
local cam = Workspace.CurrentCamera

---------------------------------------------------------------------
-- CORE STATE
---------------------------------------------------------------------
local Phynton = {
    Flags = {},          -- estado dos toggles
    Tokens = {},         -- controle de loops (evita loops duplicados)
    Registry = {},       -- elementos da UI p/ traducao
    Lang = "pt",
    Paused = false,      -- Anti-Ban
    SelfMoving = false,  -- true enquanto o proprio script move o personagem
    Conns = {},
}

local Config = { -- [CONFIG]
    CommF = function()
        local r = ReplicatedStorage:FindFirstChild("Remotes")
        return r and r:FindFirstChild("CommF_")
    end,
    RaidChip = "Flame",
    EnemiesFolder = "Enemies",
}

---------------------------------------------------------------------
-- TRADUCAO
---------------------------------------------------------------------
local L = {
    pt = {
        settings = "Configurações", movement = "Movimentação", combat = "Combate", farm = "Farm & Endgame",
        ui_scale = "Escala da GUI", language = "Idioma da interface",
        orbit = "Órbita no alvo", orbit_dist = "Distância da órbita", orbit_speed = "Velocidade da órbita",
        fly = "Voar (Fly)", fly_speed = "Velocidade do voo", fly_up = "Subir", fly_down = "Descer",
        mobility = "Auto Mobility (X/Z)", mobility_cd = "Intervalo mínimo (s)",
        fast = "Fast Attack", fast_delay = "Delay do ataque (s)",
        aimbot = "Aimbot", predict = "Predição", smooth = "Suavidade", teamcheck = "Team Check", fov = "Raio do FOV",
        aim_mode = "Alvos do Aimbot",
        dodge = "Dodge System (esquiva)", dodge_range = "Alcance de detecção",
        skills = "Auto Skills", skills_keys = "Teclas", skills_gap = "Intervalo entre skills (s)",
        weapon = "Tipo de arma", farmlvl = "Auto Farm Level", chest = "Auto Chest", items = "Auto Items (frutas)",
        mirage = "Mirage Island ESP", mirage_go = "Ir ao topo da Mirage", mirage_auto = "Auto coletar na Mirage",
        raid = "Auto Raid", v4 = "Auto Race V4 Trials", antiban = "Anti-Ban", tweenspeed = "Velocidade do tween",
        loaded = "Phynton Hub carregado!", paused = "Teleporte detectado: pausando...",
        no_target = "Sem alvo por perto",
    },
    en = {
        settings = "Settings", movement = "Movement", combat = "Combat", farm = "Farm & Endgame",
        ui_scale = "GUI Scale", language = "Interface language",
        orbit = "Orbit target", orbit_dist = "Orbit distance", orbit_speed = "Orbit speed",
        fly = "Fly", fly_speed = "Fly speed", fly_up = "Up", fly_down = "Down",
        mobility = "Auto Mobility (X/Z)", mobility_cd = "Minimum gap (s)",
        fast = "Fast Attack", fast_delay = "Attack delay (s)",
        aimbot = "Aimbot", predict = "Prediction", smooth = "Smoothness", teamcheck = "Team Check", fov = "FOV radius",
        aim_mode = "Aimbot targets",
        dodge = "Dodge System", dodge_range = "Detection range",
        skills = "Auto Skills", skills_keys = "Keys", skills_gap = "Gap between skills (s)",
        weapon = "Weapon type", farmlvl = "Auto Farm Level", chest = "Auto Chest", items = "Auto Items (fruits)",
        mirage = "Mirage Island ESP", mirage_go = "Go to Mirage top", mirage_auto = "Auto collect on Mirage",
        raid = "Auto Raid", v4 = "Auto Race V4 Trials", antiban = "Anti-Ban", tweenspeed = "Tween speed",
        loaded = "Phynton Hub loaded!", paused = "Teleport detected: pausing...",
        no_target = "No target nearby",
    },
}
local function T(k) return (L[Phynton.Lang] and L[Phynton.Lang][k]) or k end

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
    SubTitle = "mobile",
    TabWidth = 120,
    Size = UDim2.fromOffset(500, 340),
    Acrylic = false, -- melhor desempenho no celular
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.RightControl,
})
local Tabs = {
    Settings = Window:AddTab({ Title = T("settings"), Icon = "settings" }),
    Movement = Window:AddTab({ Title = T("movement"), Icon = "move" }),
    Combat   = Window:AddTab({ Title = T("combat"),   Icon = "swords" }),
    Farm     = Window:AddTab({ Title = T("farm"),     Icon = "trophy" }),
}
local Options = Fluent.Options

---------------------------------------------------------------------
-- HELPERS GERAIS
---------------------------------------------------------------------
local function getChar() return lp.Character end
local function getRoot() local c = getChar(); return c and c:FindFirstChild("HumanoidRootPart") end
local function getHum()  local c = getChar(); return c and c:FindFirstChildOfClass("Humanoid") end
local function alive(h) return h and h.Health > 0 end

local function opt(id, default)
    local o = Options[id]
    if o == nil or o.Value == nil then return default end
    return o.Value
end

local function notify(msg, dur)
    pcall(function() Fluent:Notify({ Title = "Phynton Hub", Content = msg, Duration = dur or 3 }) end)
end

-- Inicia um loop controlado por token (nunca duplica)
local function startLoop(id, fn, waitFn)
    Phynton.Tokens[id] = (Phynton.Tokens[id] or 0) + 1
    local my = Phynton.Tokens[id]
    task.spawn(function()
        while G.PhyntonHubLoaded and Phynton.Flags[id] and Phynton.Tokens[id] == my do
            if not Phynton.Paused then pcall(fn) end
            local w = 0.1
            if waitFn then local ok, v = pcall(waitFn); if ok and v then w = v end end
            task.wait(w)
        end
    end)
end

-- Espera "humana" (Anti-Ban) usada entre acoes de farm
local function humanWait()
    if Phynton.Flags.AntiBan then task.wait(math.random(1, 3)) else task.wait(0.2) end
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
    local r = getRoot(); if not r then return end
    speed = speed or opt("TweenSpeed", 250)
    local dist = (r.Position - cf.Position).Magnitude
    Phynton.SelfMoving = true
    local tw = TweenService:Create(r, TweenInfo.new(math.max(dist / speed, 0.05), Enum.EasingStyle.Linear), { CFrame = cf })
    tw:Play()
    pcall(function() tw.Completed:Wait() end)
    pcall(function() r.AssemblyLinearVelocity = Vector3.zero end)
    task.delay(0.3, function() Phynton.SelfMoving = false end)
end

---------------------------------------------------------------------
-- ALVOS (NPC / Boss / Jogadores)
---------------------------------------------------------------------
local function enemyFolder()
    return Workspace:FindFirstChild(Config.EnemiesFolder) or Workspace
end

local function validEnemy(m)
    if not m or not m:IsA("Model") or m == getChar() then return false end
    if Players:GetPlayerFromCharacter(m) then return false end
    local h = m:FindFirstChildOfClass("Humanoid")
    return alive(h) and m:FindFirstChild("HumanoidRootPart") ~= nil
end

local function nearestEnemy(maxDist, nameFilter)
    local r = getRoot(); if not r then return nil end
    local best, bd = nil, maxDist or math.huge
    for _, m in ipairs(enemyFolder():GetChildren()) do
        if validEnemy(m) and (not nameFilter or m.Name:find(nameFilter)) then
            local d = (m.HumanoidRootPart.Position - r.Position).Magnitude
            if d < bd then best, bd = m, d end
        end
    end
    return best
end

---------------------------------------------------------------------
-- ARMAS
---------------------------------------------------------------------
local function equipType(tip)
    local char, bp = getChar(), lp:FindFirstChildOfClass("Backpack")
    if not (char and bp) then return nil end
    for _, t in ipairs(char:GetChildren()) do
        if t:IsA("Tool") and (tip == "Any" or t.ToolTip == tip) then return t end
    end
    for _, t in ipairs(bp:GetChildren()) do
        if t:IsA("Tool") and (tip == "Any" or t.ToolTip == tip) then
            local h = getHum(); if h then h:EquipTool(t) end
            return t
        end
    end
end

local function heldTool()
    local c = getChar()
    return c and c:FindFirstChildOfClass("Tool")
end

-- Cooldown dinamico: le a UI de skills do jogo (se existir) [CONFIG]
local function skillReady(toolName, keyName)
    local ok, res = pcall(function()
        local f = lp.PlayerGui.Main.Skills[toolName][keyName]
        local cd = f:FindFirstChild("Cooldown")
        return (not cd) or cd.Size.X.Scale <= 0.01
    end)
    if ok then return res end
    return true
end

---------------------------------------------------------------------
-- ANTI-BAN: detecta teleporte externo e pausa
---------------------------------------------------------------------
task.spawn(function()
    local last
    while G.PhyntonHubLoaded do
        pcall(function()
            local r = getRoot()
            if r and Phynton.Flags.AntiBan then
                if last and not Phynton.SelfMoving and not Phynton.Paused
                    and (r.Position - last).Magnitude > 120 then
                    Phynton.Paused = true
                    notify(T("paused"))
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

---------------------------------------------------------------------
-- UI HELPERS (registram elementos para traducao)
---------------------------------------------------------------------
local function reg(el, key) table.insert(Phynton.Registry, { el = el, key = key }) end

local function addToggle(tab, id, key, default, cb)
    Phynton.Flags[id] = default or false
    local el = tab:AddToggle(id, { Title = T(key), Default = default or false })
    reg(el, key)
    el:OnChanged(function(v)
        Phynton.Flags[id] = v
        task.spawn(function() pcall(cb, v) end)
    end)
    return el
end

local function addSlider(tab, id, key, min, max, default, rounding, cb)
    local el = tab:AddSlider(id, { Title = T(key), Default = default, Min = min, Max = max, Rounding = rounding or 0,
        Callback = function(v) if cb then task.spawn(function() pcall(cb, v) end) end end })
    reg(el, key)
    return el
end

---------------------------------------------------------------------
-- ABA SETTINGS
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

    addSlider(Tabs.Settings, "UIScale", "ui_scale", 0.5, 1.5, 1, 2, applyScale)

    local dd = Tabs.Settings:AddDropdown("Lang", {
        Title = T("language"), Values = { "Português", "English" }, Multi = false, Default = 1,
    })
    reg(dd, "language")
    dd:OnChanged(function(v)
        Phynton.Lang = (v == "English") and "en" or "pt"
        for _, item in ipairs(Phynton.Registry) do
            pcall(function() item.el:SetTitle(T(item.key)) end)
        end
    end)

    addToggle(Tabs.Settings, "AntiBan", "antiban", true, function() end)
    addSlider(Tabs.Settings, "TweenSpeed", "tweenspeed", 100, 400, 250, 0)
end

---------------------------------------------------------------------
-- ABA MOVEMENT
---------------------------------------------------------------------
-- Orbita (seno/cosseno)
do
    local angle = 0
    addSlider(Tabs.Movement, "OrbitDist", "orbit_dist", 5, 40, 15, 0)
    addSlider(Tabs.Movement, "OrbitSpeed", "orbit_speed", 1, 10, 3, 1)
    addToggle(Tabs.Movement, "Orbit", "orbit", false, function(on)
        if Phynton.Conns.Orbit then Phynton.Conns.Orbit:Disconnect(); Phynton.Conns.Orbit = nil end
        if not on then return end
        Phynton.Conns.Orbit = RunService.Heartbeat:Connect(function(dt)
            pcall(function()
                if Phynton.Paused then return end
                local r = getRoot(); if not r then return end
                local t = nearestEnemy(300)
                if not t then return end
                local tp = t.HumanoidRootPart.Position
                angle = angle + opt("OrbitSpeed", 3) * dt
                local d = opt("OrbitDist", 15)
                local pos = tp + Vector3.new(math.cos(angle) * d, 3, math.sin(angle) * d)
                Phynton.SelfMoving = true
                r.CFrame = CFrame.new(pos, tp)
                r.AssemblyLinearVelocity = Vector3.zero
            end)
        end)
    end)
end

-- Fly (BodyVelocity horizontal + AlignPosition altitude)
do
    local bv, ap, att, targetY
    local function cleanup()
        if Phynton.Conns.Fly then Phynton.Conns.Fly:Disconnect(); Phynton.Conns.Fly = nil end
        for _, o in ipairs({ bv, ap, att }) do if o then pcall(function() o:Destroy() end) end end
        bv, ap, att = nil, nil, nil
        local h = getHum(); if h then pcall(function() h.PlatformStand = false end) end
    end

    addSlider(Tabs.Movement, "FlySpeed", "fly_speed", 20, 200, 80, 0)
    Tabs.Movement:AddButton({ Title = T("fly_up"),   Callback = function() if targetY then targetY = targetY + 10 end end })
    Tabs.Movement:AddButton({ Title = T("fly_down"), Callback = function() if targetY then targetY = targetY - 10 end end })

    addToggle(Tabs.Movement, "Fly", "fly", false, function(on)
        cleanup()
        if not on then return end
        local r, h = getRoot(), getHum()
        if not (r and h) then return end
        targetY = r.Position.Y

        att = Instance.new("Attachment"); att.Parent = r
        bv = Instance.new("BodyVelocity")
        bv.MaxForce = Vector3.new(1e6, 0, 1e6); bv.Velocity = Vector3.zero; bv.Parent = r
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
                local spd = opt("FlySpeed", 80)
                bv.Velocity = Vector3.new(hh.MoveDirection.X * spd, 0, hh.MoveDirection.Z * spd)
                ap.Position = Vector3.new(rr.Position.X, targetY, rr.Position.Z)
            end)
        end)
    end)
end

-- Auto Mobility (X / Z) com cooldown dinamico
do
    addSlider(Tabs.Movement, "MobGap", "mobility_cd", 0.2, 3, 0.8, 1)
    addToggle(Tabs.Movement, "Mobility", "mobility", false, function(on)
        if not on then return end
        local lastPress = { X = 0, Z = 0 }
        startLoop("Mobility", function()
            local tool = heldTool(); if not tool then return end
            for name, code in pairs({ X = Enum.KeyCode.X, Z = Enum.KeyCode.Z }) do
                local gap = opt("MobGap", 0.8)
                if os.clock() - lastPress[name] >= gap and skillReady(tool.Name, name) then
                    pressKey(code)
                    lastPress[name] = os.clock()
                    task.wait(0.15) -- nao atropela a animacao
                end
            end
        end, function() return 0.1 end)
    end)
end

-- Fast Attack
do
    addSlider(Tabs.Movement, "FastDelay", "fast_delay", 0.02, 0.5, 0.08, 2)
    local dd = Tabs.Movement:AddDropdown("WeaponType", {
        Title = T("weapon"), Values = { "Melee", "Sword", "Blox Fruit", "Any" }, Multi = false, Default = 1 })
    reg(dd, "weapon")

    addToggle(Tabs.Movement, "FastAttack", "fast", false, function(on)
        if not on then return end
        startLoop("FastAttack", function()
            local tool = equipType(opt("WeaponType", "Melee")); if not tool then return end
            -- reduz valores de delay/cooldown expostos na ferramenta [CONFIG]
            for _, v in ipairs(tool:GetDescendants()) do
                if (v:IsA("NumberValue") or v:IsA("IntValue")) and v.Name:lower():find("attackspeed") then
                    pcall(function() v.Value = math.min(v.Value, opt("FastDelay", 0.08)) end)
                end
            end
            pcall(function() tool:Activate() end)
            click()
        end, function() return opt("FastDelay", 0.08) end)
    end)
end

---------------------------------------------------------------------
-- ABA COMBAT
---------------------------------------------------------------------
-- Aimbot
do
    local function teamOK(plr)
        if not opt("AimTeam", true) then return true end
        return not (plr.Team and lp.Team and plr.Team == lp.Team)
    end

    local function candidates()
        local list, mode = {}, opt("AimMode", "Players")
        if mode == "Players" or mode == "Both" then
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= lp and p.Character and teamOK(p) then
                    local h = p.Character:FindFirstChildOfClass("Humanoid")
                    local hrp = p.Character:FindFirstChild("HumanoidRootPart")
                    if alive(h) and hrp then table.insert(list, hrp) end
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
        local best, bd = nil, opt("AimFov", 250)
        local vp = cam.ViewportSize / 2
        for _, hrp in ipairs(candidates()) do
            local sp, onScreen = cam:WorldToViewportPoint(hrp.Position)
            if onScreen then
                local d = (Vector2.new(sp.X, sp.Y) - vp).Magnitude
                if d < bd then best, bd = hrp, d end
            end
        end
        return best
    end

    local dd = Tabs.Combat:AddDropdown("AimMode", {
        Title = T("aim_mode"), Values = { "Players", "NPCs", "Both" }, Multi = false, Default = 3 })
    reg(dd, "aim_mode")
    addToggle(Tabs.Combat, "AimTeam", "teamcheck", true, function() end)
    addSlider(Tabs.Combat, "AimPredict", "predict", 0, 0.5, 0.12, 2)
    addSlider(Tabs.Combat, "AimSmooth", "smooth", 0.05, 1, 0.3, 2)
    addSlider(Tabs.Combat, "AimFov", "fov", 50, 600, 250, 0)

    addToggle(Tabs.Combat, "Aimbot", "aimbot", false, function(on)
        if Phynton.Conns.Aim then Phynton.Conns.Aim:Disconnect(); Phynton.Conns.Aim = nil end
        if not on then return end
        Phynton.Conns.Aim = RunService.RenderStepped:Connect(function()
            pcall(function()
                if Phynton.Paused then return end
                local t = pick(); if not t then return end
                local aimPos = t.Position + t.AssemblyLinearVelocity * opt("AimPredict", 0.12)
                local goal = CFrame.new(cam.CFrame.Position, aimPos)
                cam.CFrame = cam.CFrame:Lerp(goal, opt("AimSmooth", 0.3))
            end)
        end)
    end)
end

-- Dodge System
do
    local lastDodge = 0
    addSlider(Tabs.Combat, "DodgeRange", "dodge_range", 20, 120, 60, 0)
    addToggle(Tabs.Combat, "Dodge", "dodge", false, function(on)
        if not on then return end
        startLoop("Dodge", function()
            local r = getRoot(); if not r then return end
            if os.clock() - lastDodge < 0.6 then return end
            local params = OverlapParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = { getChar() }
            local parts = Workspace:GetPartBoundsInRadius(r.Position, opt("DodgeRange", 60), params)
            for _, p in ipairs(parts) do
                if not p.Anchored and not p:FindFirstAncestorOfClass("Model") or
                   (not p.Anchored and not (p.Parent and p.Parent:FindFirstChildOfClass("Humanoid"))) then
                    local vel = p.AssemblyLinearVelocity
                    if vel.Magnitude > 30 then
                        local toMe = r.Position - p.Position
                        if vel.Unit:Dot(toMe.Unit) > 0.9 and (toMe.Magnitude / vel.Magnitude) < 1 then
                            local side = (math.random() > 0.5) and 1 or -1
                            local perp = vel.Unit:Cross(Vector3.yAxis).Unit * side
                            Phynton.SelfMoving = true
                            r.CFrame = r.CFrame + perp * 12
                            task.delay(0.3, function() Phynton.SelfMoving = false end)
                            lastDodge = os.clock()
                            return
                        end
                    end
                end
            end
        end, function() return 0.08 end)
    end)
end

-- Auto Skills
do
    local dd = Tabs.Combat:AddDropdown("SkillKeys", {
        Title = T("skills_keys"), Values = { "Z", "X", "C", "V" }, Multi = true, Default = { "Z", "X" } })
    reg(dd, "skills_keys")
    addSlider(Tabs.Combat, "SkillGap", "skills_gap", 0.2, 3, 0.6, 1)

    addToggle(Tabs.Combat, "AutoSkills", "skills", false, function(on)
        if not on then return end
        startLoop("AutoSkills", function()
            local r = getRoot(); if not r then return end
            local t = nearestEnemy(120); if not t then return end
            local tp = t.HumanoidRootPart.Position
            r.CFrame = CFrame.lookAt(r.Position, Vector3.new(tp.X, r.Position.Y, tp.Z))
            local tool = heldTool()
            local sel = opt("SkillKeys", {})
            for _, k in ipairs({ "Z", "X", "C", "V" }) do
                if sel[k] and (not tool or skillReady(tool.Name, k)) then
                    pressKey(Enum.KeyCode[k])
                    task.wait(opt("SkillGap", 0.6))
                end
            end
        end, function() return 0.1 end)
    end)
end

---------------------------------------------------------------------
-- ABA FARM & ENDGAME
---------------------------------------------------------------------
-- [CONFIG] tabela de quests: adicione as linhas do seu mar/versao.
-- { MinLevel, QuestName, QuestIndex, EnemyName, QuestNPCPosition (opcional) }
local QuestData = {
    { 1,  "BanditQuest1",  1, "Bandit",  nil },
    { 10, "JungleQuest",   1, "Monkey",  nil },
    { 15, "JungleQuest",   2, "Gorilla", nil },
    { 30, "BuggyQuest1",   1, "Pirate",  nil },
    { 40, "BuggyQuest1",   2, "Brute",   nil },
}

local function currentQuest()
    local lvl = 1
    pcall(function() lvl = lp.Data.Level.Value end)
    local pick
    for _, q in ipairs(QuestData) do if lvl >= q[1] then pick = q end end
    return pick
end

local function questActive()
    local ok, v = pcall(function() return lp.PlayerGui.Main.Quest.Visible end)
    return ok and v
end

-- Auto Farm Level
do
    addToggle(Tabs.Farm, "FarmLevel", "farmlvl", false, function(on)
        if not on then return end
        startLoop("FarmLevel", function()
            local q = currentQuest(); if not q then return end
            local comm = Config.CommF()
            if not questActive() and comm then
                if q[5] then tweenTo(CFrame.new(q[5])); humanWait() end
                pcall(function() comm:InvokeServer("StartQuest", q[2], q[3]) end)
                humanWait()
            end
            -- ataca inimigos da quest
            local t = nearestEnemy(2000, q[4])
            if t then
                tweenTo(t.HumanoidRootPart.CFrame * CFrame.new(0, 8, 0))
                equipType(opt("WeaponType", "Melee"))
                local n = 0
                while G.PhyntonHubLoaded and Phynton.Flags.FarmLevel and validEnemy(t) and n < 200 do
                    if not Phynton.Paused then
                        local r = getRoot()
                        if r then
                            Phynton.SelfMoving = true
                            r.CFrame = t.HumanoidRootPart.CFrame * CFrame.new(0, 8, 0) * CFrame.Angles(math.rad(-90), 0, 0)
                        end
                        click()
                    end
                    n = n + 1
                    task.wait(0.1)
                end
            else
                humanWait()
            end
            -- quest concluida -> o proximo ciclo reabre e coleta recompensa
        end, function() return 0.3 end)
    end)
end

-- Auto Chest & Items
do
    local function chests()
        local list = CollectionService:GetTagged("_ChestTagged")
        if #list == 0 then
            for _, d in ipairs(Workspace:GetDescendants()) do
                if d:IsA("BasePart") and d.Name:lower():find("chest") then table.insert(list, d) end
            end
        end
        return list
    end

    addToggle(Tabs.Farm, "AutoChest", "chest", false, function(on)
        if not on then return end
        startLoop("AutoChest", function()
            local r = getRoot(); if not r then return end
            local best, bd = nil, math.huge
            for _, c in ipairs(chests()) do
                local p = c:IsA("Model") and c:GetPivot().Position or c.Position
                local d = (p - r.Position).Magnitude
                if d < bd then best, bd = c, d end
            end
            if best then
                local p = best:IsA("Model") and best:GetPivot() or best.CFrame
                tweenTo(p)
                humanWait()
            else
                humanWait()
            end
        end, function() return 0.3 end)
    end)

    addToggle(Tabs.Farm, "AutoItems", "items", false, function(on)
        if not on then return end
        startLoop("AutoItems", function()
            for _, d in ipairs(Workspace:GetChildren()) do
                if d:IsA("Tool") or (d:IsA("Model") and d.Name:find("Fruit")) then
                    local h = d:FindFirstChild("Handle") or d:FindFirstChildWhichIsA("BasePart")
                    if h then tweenTo(h.CFrame); humanWait() end
                end
            end
        end, function() return 1 end)
    end)
end

-- Mirage Island
do
    local function findMirage()
        local map = Workspace:FindFirstChild("Map")
        return map and (map:FindFirstChild("MysticIsland") or map:FindFirstChild("Mirage")) -- [CONFIG]
    end

    local function clearESP()
        local m = findMirage()
        if m then
            for _, n in ipairs({ "PhyntonESP", "PhyntonTag" }) do
                local o = m:FindFirstChild(n); if o then o:Destroy() end
            end
        end
    end

    addToggle(Tabs.Farm, "MirageESP", "mirage", false, function(on)
        if not on then clearESP(); return end
        startLoop("MirageESP", function()
            local m = findMirage(); if not m then return end
            if not m:FindFirstChild("PhyntonESP") then
                local hl = Instance.new("Highlight")
                hl.Name = "PhyntonESP"; hl.FillColor = Color3.fromRGB(90, 200, 255)
                hl.FillTransparency = 0.6; hl.Parent = m
                local bb = Instance.new("BillboardGui")
                bb.Name = "PhyntonTag"; bb.Size = UDim2.fromOffset(160, 30)
                bb.AlwaysOnTop = true; bb.StudsOffset = Vector3.new(0, 80, 0)
                local tl = Instance.new("TextLabel", bb)
                tl.Size = UDim2.fromScale(1, 1); tl.BackgroundTransparency = 1
                tl.TextColor3 = Color3.new(1, 1, 1); tl.TextScaled = true; tl.Text = "Mirage Island"
                bb.Adornee = m:FindFirstChildWhichIsA("BasePart", true)
                bb.Parent = m
            end
            local r = getRoot()
            local tl = m.PhyntonTag and m.PhyntonTag:FindFirstChildOfClass("TextLabel")
            if r and tl then
                tl.Text = ("Mirage Island [%d]"):format((m:GetPivot().Position - r.Position).Magnitude)
            end
        end, function() return 1 end)
    end)

    local function goTop()
        local m = findMirage(); if not m then return notify("Mirage não encontrada") end
        local cf, size = m:GetBoundingBox()
        tweenTo(CFrame.new(cf.Position + Vector3.new(0, size.Y / 2 + 25, 0)))
    end
    Tabs.Farm:AddButton({ Title = T("mirage_go"), Callback = function() task.spawn(function() pcall(goTop) end) end })

    addToggle(Tabs.Farm, "MirageCollect", "mirage_auto", false, function(on)
        if not on then return end
        startLoop("MirageCollect", function()
            local m = findMirage(); if not m then return end
            goTop()
            for _, d in ipairs(m:GetDescendants()) do
                if d:IsA("BasePart") and (d.Name:find("Gear") or d.Name:find("Chest")) then
                    tweenTo(d.CFrame); humanWait()
                end
            end
        end, function() return 2 end)
    end)
end

-- Auto Raid (best-effort) [CONFIG]
do
    addToggle(Tabs.Farm, "AutoRaid", "raid", false, function(on)
        if not on then return end
        startLoop("AutoRaid", function()
            local comm = Config.CommF()
            local main = lp.PlayerGui:FindFirstChild("Main")
            local inRaid = main and main:FindFirstChild("Timer") and main.Timer.Visible
            if inRaid then
                local t = nearestEnemy(1500)
                if t then
                    tweenTo(t.HumanoidRootPart.CFrame * CFrame.new(0, 8, 0))
                    equipType(opt("WeaponType", "Melee"))
                    local n = 0
                    while G.PhyntonHubLoaded and Phynton.Flags.AutoRaid and validEnemy(t) and n < 150 do
                        local r = getRoot()
                        if r then Phynton.SelfMoving = true; r.CFrame = t.HumanoidRootPart.CFrame * CFrame.new(0, 8, 0) end
                        click(); n = n + 1; task.wait(0.1)
                    end
                else
                    -- vai para a proxima ilha da raid
                    local map = Workspace:FindFirstChild("Map")
                    local rm = map and map:FindFirstChild("RaidMap")
                    if rm then
                        for _, isl in ipairs(rm:GetChildren()) do
                            tweenTo(isl:GetPivot() * CFrame.new(0, 60, 0)); humanWait(); break
                        end
                    end
                end
            elseif comm then
                pcall(function() comm:InvokeServer("RaidsNpc", "Select", Config.RaidChip) end)
                humanWait()
                -- inicia a raid tocando o botao do laboratorio [CONFIG]
                for _, d in ipairs(Workspace:GetDescendants()) do
                    if d:IsA("ClickDetector") and d.Parent.Name:lower():find("raid") then
                        pcall(fireclickdetector, d); break
                    end
                end
                humanWait()
            end
        end, function() return 0.5 end)
    end)

    -- Race V4 Trials (best-effort): vai ao gatilho do trial, derrota alvos e usa habilidade V
    addToggle(Tabs.Farm, "RaceV4", "v4", false, function(on)
        if not on then return end
        startLoop("RaceV4", function()
            local map = Workspace:FindFirstChild("Map")
            local trial = map and (map:FindFirstChild("TrialDoor") or map:FindFirstChild("Trial")) -- [CONFIG]
            local t = nearestEnemy(400)
            if t then
                tweenTo(t.HumanoidRootPart.CFrame * CFrame.new(0, 6, 0))
                click(); pressKey(Enum.KeyCode.V)
            elseif trial then
                tweenTo(trial:GetPivot() * CFrame.new(0, 5, 0)); humanWait()
            else
                humanWait()
            end
        end, function() return 0.2 end)
    end)
end

---------------------------------------------------------------------
-- FINALIZACAO
---------------------------------------------------------------------
lp.CharacterAdded:Connect(function()
    -- fly/orbit reconectam sozinhos pois leem getRoot() a cada frame
    Phynton.SelfMoving = false
end)

Window:SelectTab(1)
notify(T("loaded"), 4)
