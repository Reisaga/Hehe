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
RunService.Stepped:Connect(function()
	handler:Attack()
end)

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

Funcs:Attack()

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

local function FastAttack()
    local char = character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    local parts = {}
    for _, v in ipairs(workspace.Enemies:GetChildren()) do
        local hrp = v:FindFirstChild("HumanoidRootPart")
        local hum = v:FindFirstChild("Humanoid")
        if v ~= char and hrp and hum and hum.Health > 0 and plr:DistanceFromCharacter(hrp.Position) <= 35 then
            for _, _v in ipairs(v:GetChildren()) do
                if _v:IsA("BasePart") and plr:DistanceFromCharacter(hrp.Position) <= 35 then
                    parts[#parts + 1] = {v, _v}
                end
            end
        end
    end
    if #parts == 0 then return end
    local tool = char:FindFirstChildOfClass("Tool")
    if #parts > 0 and tool and (tool.ToolTip == "Melee" or tool.ToolTip == "Sword") then
        require(game.ReplicatedStorage.Modules.Net):RemoteEvent("RegisterHit", true)
        require(game.ReplicatedStorage.Modules.Net):RemoteEvent("ReceivedHit")
        game.ReplicatedStorage.Modules.Net["RE/RegisterAttack"]:FireServer()
        local head = parts[1][1]:FindFirstChild("Head")
        game.ReplicatedStorage.Modules.Net["RE/RegisterHit"]:FireServer(head, parts, {}, tostring(game.Players.LocalPlayer.UserId):sub(2, 4) .. tostring(coroutine.running()):sub(11, 15))
        local encryptedEventName = string.gsub("RE/RegisterHit", ".", function(c)
            return string.char(bit32.bxor(string.byte(c), math.floor(workspace:GetServerTimeNow() / 10 % 10) + 1))
        end)
        cloneref(remote):FireServer(
            encryptedEventName,
            bit32.bxor(idremote + 909090, game.ReplicatedStorage.Modules.Net.seed:InvokeServer() * 2), 
            head, 
            parts
        )
    end
end

local lastCallFA = tick()
local FastAttack = function(x)
    if not HumanoidRootPart or not Character:FindFirstChildWhichIsA("Humanoid") or Character.Humanoid.Health <= 0 or not Character:FindFirstChildWhichIsA("Tool") then 
        return 
    end
    local FAD = 1e9 -- Fast Attack Delay (in seconds)
    if FAD ~= 0 and tick() - lastCallFA <= FAD then 
        return 
    end
    local targets = {}
    for _, enemy in next, workspace.Enemies:GetChildren() do
        local humanoid = enemy:FindFirstChild("Humanoid")
        local enemyRoot = enemy:FindFirstChild("HumanoidRootPart")
        if enemy ~= Character and (x and enemy.Name == x or not x) and humanoid and enemyRoot and humanoid.Health > 0 then
            local distance = (enemyRoot.Position - HumanoidRootPart.Position).Magnitude
            if distance <= 500 then
                targets[#targets + 1] = enemy
            end
        end
    end
    if #targets == 0 then return end
    local network = ReplicatedStorage.Modules.Net
    local hitData = {[2] = {}}
    for i = 1, #targets do 
        local enemy = targets[i]
        local hitPart = enemy:FindFirstChild("Head") or enemy:FindFirstChild("HumanoidRootPart")
        
        if not hitData[1] then 
            hitData[1] = hitPart 
        end
        
        hitData[2][#hitData[2] + 1] = {enemy, hitPart}
    end
    network:FindFirstChild("RE/RegisterAttack"):FireServer()
    network:FindFirstChild("RE/RegisterHit"):FireServer(unpack(hitData))
    local encryptedEvent = string.gsub("RE/RegisterHit", ".", function(c)
        return string.char(bit32.bxor(string.byte(c), math.floor(workspace:GetServerTimeNow() / 10 % 10) + 1))
    end)
    cloneref(remoteAttack):FireServer(
        encryptedEvent,
        bit32.bxor(idremote + 909090, seed * 2),
        unpack(hitData)
    )
    lastCallFA = tick()
end

FastAttack(true)

do
	ply = game["Players"]
	plr = ply["LocalPlayer"]
	Root = plr["Character"]["HumanoidRootPart"]
	replicated = game:GetService("ReplicatedStorage")
	Lv = game["Players"]["LocalPlayer"]["Data"]["Level"]["Value"]
	TeleportService = game:GetService("TeleportService")
	TW = game:GetService("TweenService")
	Lighting = game:GetService("Lighting")
	Enemies = workspace["Enemies"]
	vim1 = game:GetService("VirtualInputManager")
	vim2 = game:GetService("VirtualUser")
	TeamSelf = plr["Team"]
	RunSer = game:GetService("RunService")
	Stats = game:GetService("Stats")
	Energy = plr["Character"]["Energy"]["Value"]
	Boss = {}
	BringConnections = {}
	MaterialList = {}
	NPCList = {}
	shouldTween = false
	SoulGuitar = false
	KenTest = true
	debug = false
	Brazier1 = false
	Brazier2 = false
	Brazier3 = false
	Sec = .1
	ClickState = 0
	Num_self = 25
end
local Ec = game["Players"]["LocalPlayer"]
local CombatUtil = require(game.ReplicatedStorage.Modules.CombatUtil)
hookfunction(CombatUtil.GetComboPaddingTime, function(...)
	return 0 
end)
hookfunction(CombatUtil.GetAttackCancelMultiplier, function(...)
	return 0 
end)
hookfunction(CombatUtil.CanAttack, function(...)
	return true 
end)
local function Bc(x)
	if not x then
		return false
	end
	local L = x:FindFirstChild("Humanoid")
	return L and L["Health"] > 0
end
local function Pc(x, L)
	local a = (game:GetService("Workspace"))["Enemies"]:GetChildren()
	local V = (game:GetService("Players")):GetPlayers()
	local H = {}
	local r = (x:GetPivot())["Position"]
	for x, a in ipairs(a) do
		local V = a:FindFirstChild("HumanoidRootPart")
		if V and Bc(a) then
			local x = (V["Position"] - r)["Magnitude"]
			if x <= L then
				table["insert"](H, a)
			end
		end
	end
	for x, a in ipairs(V) do
		if a ~= Ec and a["Character"] then
			local x = a["Character"]:FindFirstChild("HumanoidRootPart")
			if x and Bc(a["Character"]) then
				local V = (x["Position"] - r)["Magnitude"]
				if V <= L then
					table["insert"](H, a["Character"])
				end
			end
		end
	end
	return H
end
function AttackNoCoolDown()
	local x = (game:GetService("Players"))["LocalPlayer"]
	local L = x["Character"]
	if not L then
		return
	end
	local a = nil
	for x, L in ipairs(L:GetChildren()) do
		if L:IsA("Tool") then
			a = L
			break
		end
	end
	if not a then
		return
	end
	local V = Pc(L, 100)
	if #V == 0 then
		return
	end
	local H = game:GetService("ReplicatedStorage")
	local r = H:FindFirstChild("Modules")
	if not r then
		return
	end
	local R = ((H:WaitForChild("Modules")):WaitForChild("Net")):WaitForChild("RE/RegisterAttack")
	local y = ((H:WaitForChild("Modules")):WaitForChild("Net")):WaitForChild("RE/RegisterHit")
	if not R or not y then
		return
	end
	local l, M = {}, nil
	for x, L in ipairs(V) do
		if not L:GetAttribute("IsBoat") then
			local x = {
				"RightLowerArm",
				"RightUpperArm",
				"LeftLowerArm";
				"LeftUpperArm",
				"RightHand",
				"LeftHand"
			}
			local a = L:FindFirstChild(x[math["random"](#x)]) or L["PrimaryPart"]
			if a then
				table["insert"](l, {
					L,
					a
				})
				M = a
			end
		end
	end
	if not M then
		return
	end
	R:FireServer(0)
	local n = x:FindFirstChild("PlayerScripts")
	if not n then
		return
	end
	local b = n:FindFirstChildOfClass("LocalScript")
	while not b do
		n["ChildAdded"]:Wait()
		b = n:FindFirstChildOfClass("LocalScript")
	end
	local Z
	if getsenv then
		local x, L = pcall(getsenv, b)
		if x and L then
			Z = L["_G"]["SendHitsToServer"]
		end
	end
	local q, I = pcall(function()
		return (require(r["Flags"]))["COMBAT_REMOTE_THREAD"] or false
	end)
	if q and (I and Z) then
		Z(M, l)
	elseif q and not I then
		y:FireServer(M, l)
	end
end
CameraShakerR = require(game["ReplicatedStorage"]["Util"]["CameraShaker"])
CameraShakerR:Stop()
get_Monster = function()
	for x, L in pairs(workspace["Enemies"]:GetChildren()) do
		local a = L:FindFirstChild("UpperTorso") or L:FindFirstChild("Head")
		if L:FindFirstChild("HumanoidRootPart", true) and a then
			if (L["Head"]["Position"] - plr["Character"]["HumanoidRootPart"]["Position"])["Magnitude"] <= 50 then
				return true, a["Position"]
			end
		end
	end
	for x, L in pairs(workspace["SeaBeasts"]:GetChildren()) do
		if L:FindFirstChild("HumanoidRootPart") and (L:FindFirstChild("Health") and L["Health"]["Value"] > 0) then
			return true, L["HumanoidRootPart"]["Position"]
		end
	end
	for x, L in pairs(workspace["Enemies"]:GetChildren()) do
		if L:FindFirstChild("Health") and (L["Health"]["Value"] > 0 and L:FindFirstChild("VehicleSeat")) then
			return true, L["Engine"]["Position"]
		end
	end
end
Actived = function()
	local x = game["Players"]["LocalPlayer"]["Character"]:FindFirstChildOfClass("Tool")
	for x, L in next, getconnections(x["Activated"]) do
		if typeof(L["Function"]) == "function" then
			getupvalues(L["Function"])
		end
	end
end
task["spawn"](function()
	RunSer["Heartbeat"]:Connect(function()
		pcall(function()
			if not _G["Seriality"] then
				return
			end
			AttackNoCoolDown()
			local x = game["Players"]["LocalPlayer"]["Character"]:FindFirstChildOfClass("Tool")
			local L = x["ToolTip"]
			local a, V = get_Monster()
			if L == "Blox Fruit" then
				if a then
					local L = x:FindFirstChild("LeftClickRemote")
					if L then
						Actived()
						L:FireServer(Vector3["new"](.01, -500, .01), 1, true)
						L:FireServer(false)
					end
				end
			end
		end)
	end)
end)

_G["Seriality"] = true
local FastAttack = {}
local folders = {
    workspace.Enemies,
    workspace.Characters
}
local Modules = game.ReplicatedStorage:WaitForChild("Modules")
local RE_Attack = Modules.Net:WaitForChild("RE/RegisterAttack")
local RunHitDetection
local HIT_FUNCTION
task.defer(function()
    local success, Env = pcall(getsenv, game:GetService("ReplicatedStorage").Modules.CombatUtil)
    if success and Env then
        print("OK")
        HIT_FUNCTION = Env._G.SendHitsToServer
    end
    local success2, module = pcall(require, Modules:WaitForChild("CombatUtil"))
    if success2 and module then
        RunHitDetection = module.RunHitDetection
    end
end)
function FastAttack:IsAlive(v)
    return v and not v:FindFirstChild("VehicleSeat") and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 and v:FindFirstChild("HumanoidRootPart")
end
function FastAttack:GetDistance(x,xx)
    return ((typeof(x) == "Vector3" and CFrame.new(x) or x).Position - (xx == nil and game.Players.LocalPlayer.Character.PrimaryPart or (typeof(xx) == "Vector3" and Vector3.new(xx) or xx)).Position).Magnitude
end
function FastAttack:GetHits()
    local Hits = {}
    for i,v in next, workspace.Enemies:GetChildren() do
        if self:IsAlive(v) and self:GetDistance(v.HumanoidRootPart.Position) <= 60 then
            table.insert(Hits, v)
        end
    end
    return Hits
end
function FastAttack:GetRandomHitbox(v)
    local HitBox =  {
        "RightLowerArm", 
        "RightUpperArm", 
        "LeftLowerArm", 
        "LeftUpperArm", 
        "RightHand", 
        "LeftHand",
        "HumanoidRootPart",
        "Head"
    }
    return v:FindFirstChild(HitBox[math.random(1, #HitBox)]) or v.HumanoidRootPart
end
function FastAttack:SuperFastAttack()
    local BladeHits = self:GetHits()
    local realenemy
    if #BladeHits == 0 then return end
    local Args = {[1] = nil, [2] = {}}
    for _,v in next, BladeHits do
        if not Args[1] then
            Args[1] = self:GetRandomHitbox(v)
        end
        Args[2][#Args[2] + 1] = {
            [1] = v,
            [2] = self:GetRandomHitbox(v)
        }
        realenemy = v
    end
    if not Args[2] then Args[2] = {realenemy} end
    Args[2][#Args[2] + 1] = realenemy
    RE_Attack:FireServer(0)
    if HIT_FUNCTION then
        HIT_FUNCTION(unpack(Args))
    end
end
function FastAttack:RunHitboxFastAttack()
    local Tool = game.Players.LocalPlayer.Character:FindFirstChildOfClass("Tool")
    if not Tool then return end
    local success, hitResult, overlapParams, group1, group2 = pcall(function()
        return RunHitDetection(game.Players.LocalPlayer.Character, Tool)
    end)
    
    if not success or not hitResult or type(hitResult) ~= "table" then return end
    if #hitResult == 0 then return end

    local Args = {[1] = nil, [2] = {}}
    for _, target in ipairs(hitResult) do
        if self:IsAlive(target) then
            local hitPart = self:GetRandomHitbox(target)
            if not Args[1] then Args[1] = hitPart end
            table.insert(Args[2], {target, hitPart})
        end
    end

    if #Args[2] > 0 then
        RE_Attack:FireServer(0)
        if HIT_FUNCTION then
            HIT_FUNCTION(unpack(Args))
        end
    end
end

while task.wait(0.005) do
    pcall(function()
        FastAttack:SuperFastAttack()
		FastAttack:RunHitboxFastAttack()
    end)
end
