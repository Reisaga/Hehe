local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local VirtualInputManager = game:GetService("VirtualInputManager")

local Player = Players.LocalPlayer
local RegisterAttack = ReplicatedStorage.Modules.Net:WaitForChild("RE/RegisterAttack")
local RegisterHit = ReplicatedStorage.Modules.Net:WaitForChild("RE/RegisterHit")
local ShootGunEvent = ReplicatedStorage.Modules.Net:WaitForChild("RE/ShootGunEvent")
local GunValidator = ReplicatedStorage.Remotes:WaitForChild("Validator2")

local Config = {
	AttackDistance = 65,
	AttackCooldown = 0.18,
	ComboResetTime = 1.5,
	MaxCombo = 3,
	HitboxLimbs = {"RightLowerArm","RightUpperArm","LeftLowerArm","LeftUpperArm","RightHand","LeftHand"},
	AutoClickEnabled = true,
	StunForce = 160,
	StunDuration = 0.4
}

local FastAttack = {}
FastAttack.__index = FastAttack

function FastAttack.new()
	local self = setmetatable({}, FastAttack)
	self.Debounce = 0
	self.ComboDebounce = 0
	self.M1Combo = 0
	self.EnemyRootPart = nil
	self._remoteCache = {}
	return self
end

function FastAttack:IsEntityAlive(entity)
	local hum = entity and entity:FindFirstChildOfClass("Humanoid")
	return hum and hum.Health > 0
end

function FastAttack:CheckStun(Character, Humanoid, ToolTip)
	local Stun = Character:FindFirstChild("Stun")
	local Busy = Character:FindFirstChild("Busy")
	if Humanoid and Humanoid.Sit and (ToolTip == "Sword" or ToolTip == "Melee" or ToolTip == "Blox Fruit") then
		return false
	end
	if Stun and Stun.Value > 0 then
		return false
	end
	if Busy and Busy.Value then
		return false
	end
	return true
end

function FastAttack:StunFly(targetPart, force, duration)
	if not (targetPart and targetPart:IsA("BasePart")) then return end
	local dur, fv = duration or Config.StunDuration, force or Config.StunForce
	local bodyVelocity = Instance.new("BodyVelocity")
	bodyVelocity.MaxForce, bodyVelocity.Velocity, bodyVelocity.P, bodyVelocity.Parent = Vector3.new(1e5,1e5,1e5), Vector3.new(0,fv,0), 1e4, targetPart
	local safeDestroy = function(inst) if inst and inst.Parent then (function() local s,e=pcall(function()inst:Destroy()end)if not s then inst.Parent=nil end end)() end end
	local blockPart
	;(function()
		local s,e=pcall(function()
			blockPart=Instance.new("Part")
			blockPart.Name="ZBlock"
			blockPart.Size=targetPart.Size
			blockPart.CFrame=targetPart.CFrame
			blockPart.Anchored=false
			blockPart.CanCollide=true
			blockPart.Transparency=1
			blockPart.Massless=true
			blockPart.CanTouch=true
			blockPart.Parent=workspace
			local weld=Instance.new("WeldConstraint")
			weld.Part0=blockPart
			weld.Part1=targetPart
			weld.Parent=blockPart
			targetPart:SetAttribute("Blocked",true)
		end)
		if not s then blockPart=nil end
	end)()
	task.spawn(function()
		local s=pcall(function()
			local rem=game:GetService("ReplicatedStorage"):FindFirstChild("Remotes")
			if rem and rem:FindFirstChild("BlockPart") and rem.BlockPart.FireServer then
				local ok=pcall(function()rem.BlockPart:FireServer(targetPart)end)
				if not ok then pcall(function()rem.BlockPart:FireServer(targetPart.Position)end)end
			end
		end)
		if not s then task.wait() end
	end)
	task.spawn(function()
		local s=pcall(function()
			local rs=game:GetService("ReplicatedStorage")
			local mod=rs:FindFirstChild("Modules")
			if mod then
				local ok,cu=pcall(function()return require(mod:FindFirstChild("CombatUtil"))end)
				if ok and cu and cu.Particle and cu.Particle.BlockHit then
					pcall(function()cu.Particle.BlockHit(targetPart.Position or targetPart.CFrame.p)end)
				end
			end
		end)
		if not s then task.wait() end
	end)
	task.spawn(function()
		local s=pcall(function()
			local rs=game:GetService("ReplicatedStorage")
			local assets=rs:FindFirstChild("Assets")
			if assets and assets:FindFirstChild("BlockHit") then
				local clone=assets.BlockHit:Clone()
				clone.Parent=targetPart
				task.delay(.05,function()
					pcall(function()
						if clone:IsA("ParticleEmitter") then clone:Emit(1)
						elseif clone:IsA("Model")or clone:IsA("Folder")then
							if clone.PrimaryPart then clone:SetPrimaryPartCFrame(targetPart.CFrame)end
						end
					end)
				end)
				task.delay(dur+.05,function()safeDestroy(clone)end)
			end
		end)
		if not s then task.wait() end
	end)
	task.delay(dur,function()
		pcall(function()if bodyVelocity and bodyVelocity.Parent then bodyVelocity:Destroy()end end)
		pcall(function()if blockPart and blockPart.Parent then blockPart:Destroy()end end)
		pcall(function()targetPart:SetAttribute("Blocked",nil)end)
	end)
end

function FastAttack:GetBladeHits(Character)
	local hits, position = {}, Character:GetPivot().Position
	local function process(folder)
		for _, Enemy in ipairs(folder:GetChildren()) do
			if Enemy ~= Character and self:IsEntityAlive(Enemy) then
				local part = Enemy:FindFirstChild(Config.HitboxLimbs[math.random(#Config.HitboxLimbs)]) or Enemy:FindFirstChild("HumanoidRootPart")
				if part and (position - part.Position).Magnitude <= Config.AttackDistance then
					table.insert(hits, {Enemy, part})
				end
			end
		end
	end
	if Workspace:FindFirstChild("Enemies") then
		process(Workspace.Enemies)
	end
	if Workspace:FindFirstChild("Characters") then
		process(Workspace.Characters)
	end
	return hits
end

function FastAttack:GetClosestEnemy(Character, Distance)
	local root, closest, best = Character:GetPivot().Position, nil, Distance or 120
	for _, hit in ipairs(self:GetBladeHits(Character, Distance)) do
		local dist = (root - hit[2].Position).Magnitude
		if dist < best then
			best, closest = dist, hit[2]
		end
	end
	return closest
end

function FastAttack:GetCombo()
	local now = tick()
	local combo = (now - self.ComboDebounce) <= Config.ComboResetTime and self.M1Combo or 0
	combo = combo >= Config.MaxCombo and 1 or combo + 1
	self.ComboDebounce = now
	self.M1Combo = combo
	return combo
end

function FastAttack:UseNormalClick(Character, Humanoid, Cooldown)
	local hits = self:GetBladeHits(Character)
	if hits[1] then
		self.EnemyRootPart = hits[1][2]
		RegisterAttack:FireServer(Cooldown)
		RegisterHit:FireServer(self.EnemyRootPart, hits)
		self:StunFly(self.EnemyRootPart, Config.StunForce, Config.StunDuration)
	end
end

function FastAttack:UseFruitM1(Character, Equipped, Combo)
	local hits = self:GetBladeHits(Character)
	if hits[1] then
		local direction = (hits[1][2].Position - Character:GetPivot().Position).Unit
		Equipped.LeftClickRemote:FireServer(direction, Combo)
		self:StunFly(hits[1][2], Config.StunForce * 0.6, Config.StunDuration)
	end
end

function FastAttack:ShootInTarget(position)
	local Character = Player.Character
	local Equipped = Character and Character:FindFirstChildOfClass("Tool")
	if Equipped and Equipped.ToolTip == "Gun" then
		ShootGunEvent:FireServer(position)
		GunValidator:FireServer({})
		self:StunFly(self.EnemyRootPart or Equipped.Handle, Config.StunForce * 0.8, Config.StunDuration)
	end
end

function FastAttack:Attack()
	if not Config.AutoClickEnabled then
		return
	end
	if (tick() - self.Debounce) < Config.AttackCooldown then
		return
	end
	local Character = Player.Character
	if not self:IsEntityAlive(Character) then
		return
	end
	local Humanoid = Character:FindFirstChildOfClass("Humanoid")
	local Equipped = Character:FindFirstChildOfClass("Tool")
	if not Equipped then
		return
	end
	local ToolTip = Equipped.ToolTip
	if ToolTip == "Melee" or ToolTip == "Blox Fruit" or ToolTip == "Sword" or ToolTip == "Gun" then
		if self:CheckStun(Character, Humanoid, ToolTip) then
			local Combo = self:GetCombo()
			local Cooldown = Equipped:FindFirstChild("Cooldown") and Equipped.Cooldown.Value or Config.AttackCooldown
			Cooldown = Cooldown + (Combo >= Config.MaxCombo and 0.05 or 0)
			self.Debounce = tick()
			if ToolTip == "Blox Fruit" and Equipped:FindFirstChild("LeftClickRemote") then
				self:UseFruitM1(Character, Equipped, Combo)
			elseif ToolTip == "Gun" then
				local target = self:GetClosestEnemy(Character, 120)
				if target then
					self:ShootInTarget(target.Position)
				end
			else
				self:UseNormalClick(Character, Humanoid, Cooldown)
			end
		end
	end
end

local AttackInstance = FastAttack.new()
RunService.Stepped:Connect(function()
	AttackInstance:Attack()
end)
---Fast 2 ---
local Modules = game.ReplicatedStorage.Modules
local Net = Modules.Net
local Register_Hit, Register_Attack = Net:WaitForChild("RE/RegisterHit"), Net:WaitForChild("RE/RegisterAttack")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local Funcs = {}
local BladeHandler = {}
BladeHandler.__index = BladeHandler

function BladeHandler.new()
	local self = setmetatable({}, BladeHandler)
	self.Range = 65
	self.LiftPower = 80
	self.LiftDuration = 0.5
	return self
end

function BladeHandler:_validTarget(root)
	if not root then return false end
	local h = root:FindFirstChildOfClass("Humanoid")
	local hrp = root:FindFirstChild("HumanoidRootPart")
	if not h or not hrp then return false end
	if h.Health <= 0 then return false end
	local lp = LocalPlayer and LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
	if not lp then return false end
	if (hrp.Position - lp.Position).Magnitude > self.Range then return false end
	return true
end

function BladeHandler:GetAllBladeHits()
	local out = {}
	local enemies = workspace:FindFirstChild("Enemies")
	if not enemies then return out end
	local children = enemies:GetChildren()
	for i = 1, #children do
		local v = children[i]
		if self:_validTarget(v) then
			out[#out + 1] = v
		end
	end
	return out
end

function BladeHandler:Getplayerhit()
	local out = {}
	local chars = workspace:FindFirstChild("Characters")
	if not chars then return out end
	local lpname = LocalPlayer and LocalPlayer.Name
	local children = chars:GetChildren()
	for i = 1, #children do
		local v = children[i]
		if v.Name ~= lpname and self:_validTarget(v) then
			out[#out + 1] = v
		end
	end
	return out
end

local handler = BladeHandler.new()

function Funcs:Attack()
	local bladehits = {}
	local a = handler:GetAllBladeHits()
	for i = 1, #a do bladehits[#bladehits + 1] = a[i] end
	local b = handler:Getplayerhit()
	for i = 1, #b do bladehits[#bladehits + 1] = b[i] end

	repeat
		if #bladehits == 0 then break end

		local args = {
			[1] = nil;
			[2] = {},
			[4] = "078da341"
		}

		for idx = 1, #bladehits do
			local v = bladehits[idx]
			pcall(function()
				Register_Attack:FireServer(0)
			end)
			if not args[1] and v:FindFirstChild("Head") then
				args[1] = v.Head
			end
			local hrp = v:FindFirstChild("HumanoidRootPart")
			args[2][idx] = {
				[1] = v,
				[2] = hrp
			}

			pcall(function()
				if hrp and hrp:IsA("BasePart") then
					local bv = Instance.new("BodyVelocity")
					bv.MaxForce = Vector3.new(1e5, 1e5, 1e5)
					bv.Velocity = Vector3.new(0, handler.LiftPower, 0)
					bv.Parent = hrp
					task.delay(handler.LiftDuration, function()
						pcall(function() bv:Destroy() end)
					end)
				end
				local hum = v:FindFirstChildOfClass("Humanoid")
				if hum then
					pcall(function() hum.PlatformStand = true end)
					task.delay(handler.LiftDuration, function()
						pcall(function() if hum and hum.Parent then hum.PlatformStand = false end end)
					end)
				end
			end)
		end

		pcall(function() Register_Hit:FireServer(unpack(args)) end)
	until true
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = workspace

local Player = Players.LocalPlayer
local FAST_ATTACK_RANGE = 100
local MONSTER_CHECK_RANGE = 50

local NetFolder = ReplicatedStorage.Modules.Net
local AttackEvent = NetFolder:WaitForChild("RE/RegisterAttack")
local HitEvent = NetFolder:WaitForChild("RE/RegisterHit")

local function IsAlive(c)
    local h = c:FindFirstChild("Humanoid")
    return h and h.Health > 0
end

local function GetRoot(c)
    return c and c:FindFirstChild("HumanoidRootPart")
end

local function GetEnemiesInRange(r)
    local p = GetRoot(Player.Character)
    if not p then return {} end
    local t = {}
    for _, e in ipairs(Workspace.Enemies:GetChildren()) do
        if IsAlive(e) then
            local er = GetRoot(e)
            if er and (er.Position - p.Position).Magnitude <= r then
                t[#t+1] = e
            end
        end
    end
    for _, pl in ipairs(Players:GetPlayers()) do
        if pl ~= Player and pl.Character and IsAlive(pl.Character) then
            local pr = GetRoot(pl.Character)
            if pr and (pr.Position - p.Position).Magnitude <= r then
                t[#t+1] = pl.Character
            end
        end
    end
    return t
end

local function FindMonster()
    local pr = GetRoot(Player.Character)
    if not pr then return false,nil end
    for _, e in ipairs(Workspace.Enemies:GetChildren()) do
        local hr = GetRoot(e)
        local limb = e:FindFirstChild("UpperTorso") or e:FindFirstChild("Head")
        if hr and limb and (hr.Position - pr.Position).Magnitude <= MONSTER_CHECK_RANGE then
            return true, limb.Position
        end
    end
    for _, b in ipairs(Workspace.SeaBeasts:GetChildren()) do
        if b:FindFirstChild("Health") and b.Health.Value > 0 then
            local br = GetRoot(b)
            if br then return true, br.Position end
        end
    end
    for _, v in ipairs(Workspace.Enemies:GetChildren()) do
        if v:FindFirstChild("Health") and v.Health.Value > 0 and v:FindFirstChild("Engine") then
            return true, v.Engine.Position
        end
    end
    return false,nil
end

local function StunAndPull(e)
    local r = GetRoot(e)
    local pr = GetRoot(Player.Character)
    if r and pr then
        r.Anchored = false
        r.CFrame = pr.CFrame * CFrame.new(0,0,-4)
        local bv = Instance.new("BodyVelocity")
        bv.MaxForce = Vector3.new(9e9,9e9,9e9)
        bv.Velocity = (pr.Position - r.Position).Unit * 20
        bv.Parent = r
        task.delay(0.15,function()
            if bv then bv:Destroy() end
        end)
    end
end

local function PerformAttack()
    local c = Player.Character
    if not c then return end
    local tool = c:FindFirstChildOfClass("Tool")
    if not tool then return end
    local enemies = GetEnemiesInRange(FAST_ATTACK_RANGE)
    if #enemies == 0 then return end

    local hits = {}
    local main = nil
    local limbs = {"RightLowerArm","RightUpperArm","LeftLowerArm","LeftUpperArm","RightHand","LeftHand"}

    for _, e in ipairs(enemies) do
        if not e:GetAttribute("IsBoat") then
            StunAndPull(e)
            local part = e:FindFirstChild(limbs[math.random(#limbs)]) or GetRoot(e)
            if part then
                hits[#hits+1] = {e,part}
                main = main or part
            end
        end
    end

    if not main then return end

    AttackEvent:FireServer(0)

    local ls = Player.PlayerScripts:FindFirstChildOfClass("LocalScript")
    local hitfunc = nil
    if ls then
        local s, env = pcall(getsenv, ls)
        hitfunc = s and rawget(env,"_G") and env._G.SendHitsToServer
    end

    local ok, flags = pcall(function() return require(ReplicatedStorage.Modules.Flags) end)
    local thread = ok and flags.COMBAT_REMOTE_THREAD

    if hitfunc and thread then
        hitfunc(main, hits)
    else
        HitEvent:FireServer(main, hits)
    end
end

local function HandleFruitSkill()
    local c = Player.Character
    if not c then return end
    local tool = c:FindFirstChildOfClass("Tool")
    if not tool then return end
    local tt = tool:FindFirstChild("ToolTip")
    if not tt or tt.Value ~= "Blox Fruit" then return end
    local ok, pos = FindMonster()
    if not ok then return end
    local r = tool:FindFirstChild("LeftClickRemote")
    if r then
        r:FireServer(Vector3.new(0,-500,0),1,true)
        task.wait(0.03)
        r:FireServer(false)
    end
end

RunService.Heartbeat:Connect(function()
    if _V and _V.FastAttack then
        pcall(PerformAttack)
        pcall(HandleFruitSkill)
    end
end)
