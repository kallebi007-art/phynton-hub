--[[ ============================================================
     PHYNTON HUB v3.1 - FINAL
     - IA Player (anda/dash/pula) x Scripter (voa/atravessa)
     - Farm de Maestria
     - Auto Mirage (aproxima reto + oscila 4-5)
     - Otimização Visual (Fog, Fullbright, Shadows, Particles...)
     - Overlay FPS + Ícone
     ============================================================ ]]

-- Re-execução segura
local G = (getgenv and getgenv()) or _G
if G.PhyntonHub then
    pcall(function() G.PhyntonHub:StopAll() end)
    pcall(function() if G.PhyntonFluent then G.PhyntonFluent:Destroy() end end)
end
pcall(function() if G.PhyntonFpsConn then G.PhyntonFpsConn:Disconnect() end end)
pcall(function() if G.PhyntonGui then G.PhyntonGui:Destroy() end end)

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local VIM        = game:GetService("VirtualInputManager")
local Lighting   = game:GetService("Lighting")
local LP         = Players.LocalPlayer

local Hub = { Mode = "Player", Features = {} }

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
        task.spawn(self.Start, self, self.Jan)
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

function Hub:Register(name, start, stop)
    local f = setmetatable({ Name = name, On = false, Start = start, Stop = stop }, Feature)
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
    -- reinicia IAs ativas para pegar o novo comportamento
    for _, n in ipairs({ "CombatAI", "MasteryFarm", "MirageHunt" }) do
        local f = self.Features[n]
        if f and f.On then
            task.spawn(function()
                f:Set(false); task.wait(0.12)
                if self.Mode == mode then f:Set(true) end
            end)
        end
    end
end

LP.CharacterAdded:Connect(function()
    task.wait(1)
    if Hub.Mode == "Player" then clearFlight() end
end)

--------------------------------------------------------------------
-- 3) CONFIG
--------------------------------------------------------------------
Hub.Config = {
    MasteryTypes = { Sword = true, Gun = true, ["Blox Fruit"] = true, Melee = false },
    SwitchEvery  = 25,
    SkillKeys    = { "Z", "X", "C", "V", "F" },
    HoverHeight  = 12,
    AttackRange  = 28,
    DashRange    = 45,
    DashCooldown = 1.8,
    SkillCooldown= 2.0,
    MaxFlyStep   = 10,
    Mirage = {
        ApproachTime        = 20,
        OscillationInterval = 3,
        SearchName          = "Mirage",
    },
}

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
    local folder = workspace:FindFirstChild("Enemies")
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

local function pressKey(k)
    local code = Enum.KeyCode[k]
    if not code then return end
    VIM:SendKeyEvent(true, code, false, game); task.wait(0.05)
    VIM:SendKeyEvent(false, code, false, game)
end

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
-- 5) MAESTRIA
--------------------------------------------------------------------
Hub:Register("MasteryFarm", function(self, jan)
    local order, idx, t0 = {}, 1, 0
    for tip, on in pairs(Hub.Config.MasteryTypes) do if on then table.insert(order, tip) end end
    if #order == 0 then self.On = false; return end
    jan:Add(function() clearFlight() end)

    self:Loop(0.15, function()
        if not self.On then return end
        if os.clock() - t0 > Hub.Config.SwitchEvery then
            idx = idx % #order + 1; t0 = os.clock()
        end
        local tip = order[idx]
        local tool, h = findTool(tip), hum()
        if tool and h and tool.Parent ~= char() then h:EquipTool(tool) end
        local enemy = nearestEnemy()
        if not enemy then return end

        local r = hrp(); local eRoot = enemy:FindFirstChild("HumanoidRootPart")
        if r and eRoot then
            if Hub.Mode == "Player" then
                local flat = Vector3.new(eRoot.Position.X - r.Position.X, 0, eRoot.Position.Z - r.Position.Z)
                if flat.Magnitude > 8 then h:Move(flat.Unit, false) else h:Move(Vector3.zero) end
            else
                r.CFrame = CFrame.new(eRoot.Position + Vector3.new(0, Hub.Config.HoverHeight, 0), eRoot.Position)
                r.AssemblyLinearVelocity = Vector3.zero
            end
        end

        for _, k in ipairs(Hub.Config.SkillKeys) do
            if not self.On then return end
            pressKey(k)
        end
        local t = char() and char():FindFirstChildOfClass("Tool")
        if t then t:Activate() end
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
    jan:Add(RunService.Heartbeat:Connect(scan))
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
    jan:Add(RunService.Heartbeat:Connect(scan))
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

--------------------------------------------------------------------
-- 9) UI FLUENT
--------------------------------------------------------------------
local Fluent = loadstring(game:HttpGet("https://github.com/dawid-scripts/Fluent/releases/latest/download/main.lua"))()
local Window = Fluent:CreateWindow({
    Title = "Phynton Hub",
    SubTitle = "v3.1 | IA Player/Scripter",
    TabWidth = 120,
    Size = UDim2.fromOffset(490, 360),
    Acrylic = false,
    Theme = "Dark",
    MinimizeKey = Enum.KeyCode.LeftControl,
})
G.PhyntonFluent = Fluent

local Tabs = {
    Settings = Window:AddTab({ Title = "Config",    Icon = "" }),
    Combat   = Window:AddTab({ Title = "Combate",   Icon = "" }),
    Movement = Window:AddTab({ Title = "Movimento", Icon = "" }),
    Sea      = Window:AddTab({ Title = "Sea",       Icon = "" }),
    Visual   = Window:AddTab({ Title = "Visual",    Icon = "" }),
}

-- Config
Tabs.Settings:AddDropdown("Mode", {
    Title = "Modo de Jogo",
    Values = { "Player", "Scripter" },
    Default = 1,
}):OnChanged(function(v) Hub:SetMode(v) end)

Tabs.Settings:AddButton({
    Title = "Parar Tudo",
    Callback = function() Hub:StopAll() end
})

Tabs.Settings:AddParagraph({
    Title = "Modos",
    Content = "Player = física real (anda/corre/pula/dash). Scripter = voa e atravessa paredes.",
})

-- Combate
Tabs.Combat:AddToggle("CombatAI", {
    Title = "IA de Combate",
    Default = false,
    Description = "Player = anda/dash/pula. Scripter = voa/atravessa.",
}):OnChanged(function(v) Hub.Features.CombatAI:Set(v) end)

Tabs.Combat:AddDropdown("MasteryTypes", {
    Title = "Treinar Maestria de",
    Values = { "Sword", "Gun", "Blox Fruit", "Melee" },
    Multi = true,
    Default = { "Sword", "Gun", "Blox Fruit" },
}):OnChanged(function(sel)
    for tip in pairs(Hub.Config.MasteryTypes) do
        Hub.Config.MasteryTypes[tip] = sel[tip] == true
    end
    if Hub.Features.MasteryFarm.On then
        Hub.Features.MasteryFarm:Set(false)
        Hub.Features.MasteryFarm:Set(true)
    end
end)

Tabs.Combat:AddToggle("Mastery", {
    Title = "Farm de Maestria",
    Default = false,
}):OnChanged(function(v) Hub.Features.MasteryFarm:Set(v) end)

-- Movimento
Tabs.Movement:AddDropdown("Profile", {
    Title = "Perfil (Record/Replay)",
    Values = { "Sharkizim", "Gravado" },
    Default = 1,
}):OnChanged(function(v) Hub.ActiveProfile = v end)

Tabs.Movement:AddToggle("MoveAI", {
    Title = "IA de Movimento (Mimic)",
    Default = false,
    Description = "Só imita padrões de andar. Não luta.",
}):OnChanged(function(v) Hub.Features.MoveAI:Set(v) end)

-- Sea (Mirage)
Tabs.Sea:AddToggle("MirageHunt", {
    Title = "Auto Mirage Hunt",
    Default = false,
    Description = "Aproxima reto e depois oscila entre perigo 4-5. Para ao encontrar.",
}):OnChanged(function(v) Hub.Features.MirageHunt:Set(v) end)

Tabs.Sea:AddParagraph({
    Title = "Como funciona",
    Content = "Fase 1: vai reto por 20s. Fase 2: ziguezagueia via Steer alternado. Use um barco para o spawn.",
})

-- Visual
Tabs.Visual:AddToggle("RemoveFog",       { Title = "Remover Fog",                  Default = false }):OnChanged(function(v) Hub.Features.RemoveFog:Set(v) end)
Tabs.Visual:AddToggle("Fullbright",      { Title = "Fullbright",                   Default = false }):OnChanged(function(v) Hub.Features.Fullbright:Set(v) end)
Tabs.Visual:AddToggle("NoShadows",       { Title = "Remover Sombras (FPS)",        Default = false }):OnChanged(function(v) Hub.Features.NoShadows:Set(v) end)
Tabs.Visual:AddToggle("NoParticles",     { Title = "Remover Partículas (FPS)",     Default = false }):OnChanged(function(v) Hub.Features.NoParticles:Set(v) end)
Tabs.Visual:AddToggle("NoCameraEffects", { Title = "Remover Efeitos de Câmera",     Default = false }):OnChanged(function(v) Hub.Features.NoCameraEffects:Set(v) end)
Tabs.Visual:AddToggle("FastMode",        { Title = "Fast Mode (Overlay)",          Default = false }):OnChanged(function(v) Hub.Features.FastMode:Set(v) end)

Tabs.Visual:AddParagraph({
    Title = "Dica",
    Content = "Sombras + Partículas = maior ganho de FPS. Fog = visão limpa.",
})

Window:SelectTab(1)
Fluent:Notify({ Title = "Phynton Hub", Content = "Carregado!", Duration = 3 })

--------------------------------------------------------------------
-- 10) OVERLAY (FPS + ÍCONE)
--------------------------------------------------------------------
local gui = Instance.new("ScreenGui")
gui.Name = "PhyntonOverlay"
gui.ResetOnSpawn = false
pcall(function() gui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
if not gui.Parent then gui.Parent = LP:WaitForChild("PlayerGui") end

G.PhyntonGui = gui

-- Contador de FPS leve: 1 conexão, texto atualizado só 1x por segundo
local fpsLabel = Instance.new("TextLabel")
fpsLabel.Size = UDim2.fromOffset(80, 20)
fpsLabel.Position = UDim2.new(0.5, -40, 0, 6)
fpsLabel.BackgroundTransparency = 1
fpsLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
fpsLabel.TextStrokeTransparency = 0.6
fpsLabel.Font = Enum.Font.GothamBold
fpsLabel.TextSize = 14
fpsLabel.Text = "FPS: --"
fpsLabel.Active = false
fpsLabel.Parent = gui

local frames, acc = 0, 0
G.PhyntonFpsConn = RunService.Heartbeat:Connect(function(dt)
    frames += 1
    acc += dt
    if acc >= 1 then
        fpsLabel.Text = "FPS: " .. math.floor(frames / acc + 0.5)
        frames, acc = 0, 0
    end
end)

local btn = Instance.new("TextButton")
btn.Size = UDim2.fromOffset(46, 46)
btn.Position = UDim2.new(0, 10, 0.4, 0)
btn.Text = "pyh"
btn.TextColor3 = Color3.fromRGB(255, 255, 255)
btn.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
btn.Parent = gui
Instance.new("UICorner", btn).CornerRadius = UDim.new(1, 0)
btn.Activated:Connect(function()
    if Window.Visible then Window:Minimize() else Window:Show() end
end)

G.PhyntonHub = Hub
return Hub
