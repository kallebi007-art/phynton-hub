--[[ Phynton Hub - NÚCLEO CORRIGIDO
 Corrige: 1) voo no modo Player  2) funções que continuam rodando ao desligar
          3) falta de maestria (Espada / Arma / Fruta / Melee)  4) IA de movimento
 Cole no seu PhyntonHub.lua e ligue cada Toggle do Fluent em Hub.Features.X:Set(valor)
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VIM = game:GetService("VirtualInputManager")
local LP = Players.LocalPlayer

local Hub = { Mode = "Player", Features = {} }

--------------------------------------------------------------------
-- 1) GERENCIADOR DE FUNÇÕES (resolve "desativo e continua rodando")
-- Tudo que uma função cria (conexões, loops, objetos) vai no Janitor.
-- Ao desligar, o Janitor limpa TUDO de uma vez.
--------------------------------------------------------------------
local Janitor = {}
Janitor.__index = Janitor
function Janitor.new() return setmetatable({ items = {} }, Janitor) end
function Janitor:Add(x) table.insert(self.items, x); return x end
function Janitor:Clean()
	for _, x in ipairs(self.items) do
		local t = typeof(x)
		if t == "RBXScriptConnection" then x:Disconnect()
		elseif t == "Instance" then x:Destroy()
		elseif t == "function" then pcall(x)
		elseif t == "thread" then pcall(task.cancel, x) end
	end
	table.clear(self.items)
end

local Feature = {}
Feature.__index = Feature
function Feature:Set(on)
	if on == self.On then return end -- evita ligar duas vezes (loops duplicados)
	self.On = on
	if on then
		self.Jan = Janitor.new()
		task.spawn(self.Start, self, self.Jan)
	else
		if self.Jan then self.Jan:Clean(); self.Jan = nil end
		if self.Stop then pcall(self.Stop, self) end
	end
end
-- loop seguro: para sozinho quando a função é desligada
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
-- 2) MODO PLAYER x SCRIPTER (resolve o personagem voando no Player)
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
				o:Destroy()
			end
		end
		r.AssemblyLinearVelocity = Vector3.zero
	end
	local h = hum()
	if h then h.PlatformStand = false; h:ChangeState(Enum.HumanoidStateType.GettingUp) end
end

function Hub:SetMode(mode)
	self.Mode = mode
	if mode == "Player" then
		-- desliga tudo que voa/teleporta e devolve o controle ao jogador
		for _, n in ipairs({ "FlyToTarget", "AutoFarm", "MasteryFarm" }) do
			if self.Features[n] then self.Features[n]:Set(false) end
		end
		clearFlight()
	end
end
-- só deixa voar se estiver em modo Scripter
local function canFly() return Hub.Mode == "Scripter" end

-- voo controlado (Scripter): fica sobre o alvo, e SEMPRE se limpa ao desligar
local function hoverAbove(target, height)
	if not canFly() then return end
	local r = hrp(); if not (r and target) then return end
	local bv = r:FindFirstChild(FLY_TAG)
	if not bv then
		bv = Instance.new("BodyVelocity"); bv.Name = FLY_TAG
		bv.MaxForce = Vector3.new(1e5, 1e5, 1e5); bv.Velocity = Vector3.zero; bv.Parent = r
	end
	r.CFrame = CFrame.new(target.Position + Vector3.new(0, height or 12, 0), target.Position)
end

LP.CharacterAdded:Connect(function() task.wait(1); if Hub.Mode == "Player" then clearFlight() end end)

--------------------------------------------------------------------
-- 3) MAESTRIA (Espada / Arma / Fruta / Melee)
-- No Blox Fruits o Tool tem .ToolTip = "Melee" | "Sword" | "Gun" | "Blox Fruit"
--------------------------------------------------------------------
Hub.Config = {
	MasteryTypes = { Sword = true, Gun = true, ["Blox Fruit"] = true, Melee = false },
	SwitchEvery = 25,        -- segundos em cada tipo antes de trocar
	SkillKeys = { "Z", "X", "C", "V", "F" },
	HoverHeight = 14,
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
	VIM:SendKeyEvent(true, code, false, game); task.wait(0.05)
	VIM:SendKeyEvent(false, code, false, game)
end

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
		if tool and h and tool.Parent ~= char() then h:EquipTool(tool) end -- equipa o tipo da vez
		local enemy = nearestEnemy()
		if not enemy then return end
		hoverAbove(enemy.HumanoidRootPart, Hub.Config.HoverHeight)
		-- ataca com o tipo equipado (skills dão mais maestria)
		for _, k in ipairs(Hub.Config.SkillKeys) do
			if not self.On then return end
			pressKey(k)
		end
		local t = char() and char():FindFirstChildOfClass("Tool")
		if t then t:Activate() end
	end)
end)

--------------------------------------------------------------------
-- 4) IA DE MOVIMENTO (grava quando nada está ligado, replica quando liga)
-- Grava "segmentos": direção relativa à câmera + pulo + duração.
-- Replay usa Humanoid:Move -> parece jogador normal (sem voar/teleportar).
--------------------------------------------------------------------
local Rec = { segments = {}, last = nil, MAX = 400 }

local function anyFeatureOn()
	for n, f in pairs(Hub.Features) do
		if f.On and n ~= "MoveAI" and n ~= "MoveRecorder" then return true end
	end
	return false
end

Hub:Register("MoveRecorder", function(self, jan)
	local cam = workspace.CurrentCamera
	local seg
	jan:Add(RunService.Heartbeat:Connect(function(dt)
		if anyFeatureOn() or Hub.Features.MoveAI.On then seg = nil; return end -- só grava "livre"
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

-- Perfil do "Sharkizim": cole aqui os padrões que você observar dele
-- (ex.: pula + anda de lado durante skills). Cada passo = {x, z, pulo, segundos}
Hub.Profiles = {
	Sharkizim = {
		{ 0, 1, false, 0.35 }, { 1, 1, true, 0.25 }, { -1, 1, false, 0.3 },
		{ 0, -1, false, 0.2 }, { 1, 0, true, 0.3 },
	},
}
Hub.ActiveProfile = "Sharkizim" -- ou "Gravado" para usar o que a IA aprendeu

Hub:Register("MoveAI", function(self, jan)
	local cam = workspace.CurrentCamera
	jan:Add(function() local h = hum(); if h then h:Move(Vector3.zero) end end)
	self:Loop(0, function()
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
		dur = math.clamp(dur * (0.85 + math.random() * 0.3), 0.1, 1.5) -- variação humana
		local t0 = os.clock()
		while self.On and os.clock() - t0 < dur do
			local dir = cam.CFrame:VectorToWorldSpace(Vector3.new(x, 0, z))
			h:Move(Vector3.new(dir.X, 0, dir.Z), false)
			if jump then h.Jump = true end
			RunService.Heartbeat:Wait()
		end
	end)
end)

-- liga a gravação por padrão (ela mesma pausa quando algo está ativo)
task.defer(function() Hub.Features.MoveRecorder:Set(true) end)

--------------------------------------------------------------------
-- EXEMPLO de ligação com o Fluent (um Toggle por função, sempre :Set)
--------------------------------------------------------------------
-- Tabs.Settings:AddDropdown("Mode", { Title="Modo", Values={"Player","Scripter"}, Default="Player",
--     Callback=function(v) Hub:SetMode(v) end })
-- Tabs.Combat:AddToggle("Mastery", { Title="Farm de Maestria", Default=false,
--     Callback=function(v) Hub.Features.MasteryFarm:Set(v) end })
-- Tabs.Movement:AddToggle("MoveAI", { Title="IA de Movimento", Default=false,
--     Callback=function(v) Hub.Features.MoveAI:Set(v) end })
-- Tabs.Settings:AddButton({ Title="Parar tudo", Callback=function() Hub:StopAll() end })

return Hub
