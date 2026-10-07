a
    losParams.FilterDescendantsInstances = losFilter
    return Workspace:Raycast(from, point - from, losParams) == nil
end

xDTaraZ.Target.Profiles = { Silent = {}, Rage = {}, Aim = {} }

---@param kind string  "Silent", "Rage" or "Aim"; each aim system keeps its own settings
---@return table        { Fov, Bone, Priority, Range }, Fov 0 = no FOV limit
function xDTaraZ.Target.Profile(kind)
    local opts, profile = xDTaraZ.Options, xDTaraZ.Target.Profiles[kind]
    if kind == "Silent" then
        profile.Fov, profile.Bone, profile.Priority, profile.Range = opts.SilentFov, "Head", opts.SilentPriority, opts.SilentMaxDistance
    elseif kind == "Rage" then
        profile.Fov, profile.Bone, profile.Priority, profile.Range = 0, "Head", "Distance", opts.RageMaxDistance
    else
        profile.Fov, profile.Bone, profile.Priority, profile.Range = opts.AimFov, opts.AimBone, opts.AimPriority, opts.AimMaxDistance
    end
    return profile
end

---@return BasePart?, number?, boolean?  aim part, screen distance, on screen; nil when out of range, FOV or sight
function xDTaraZ.Target.Check(model, profile, cam, origin, center)
    if not xDTaraZ.Target.IsEnemy(model) then return nil end
    local part = xDTaraZ.Target.Part(model, profile.Bone)
    if not part or (part.Position - origin).Magnitude > profile.Range then return nil end
    local screen, onScreen = cam:WorldToViewportPoint(part.Position)
    local screenDist = (Vector2.new(screen.X, screen.Y) - center).Magnitude
    if profile.Fov > 0 and (not onScreen or screenDist > profile.Fov) then return nil end
    if not xDTaraZ.Target.Visible(origin, model, part.Position) then return nil end
    return part, screenDist, onScreen
end

---@return Model?, BasePart?
function xDTaraZ.Target.Pick(profile)
    local cam = Workspace.CurrentCamera
    local origin = cam.CFrame.Position
    local center = cam.ViewportSize / 2
    local best, bestPart, bestScore

    for _, model in ipairs(xDTaraZ.Target.Candidates()) do
        local part, screenDist, onScreen = xDTaraZ.Target.Check(model, profile, cam, origin, center)
        if not part then continue end
        local score = (part.Position - origin).Magnitude
        if profile.Priority == "Crosshair" then
            score = onScreen and screenDist or 1e6 + score
        elseif profile.Priority == "Health" then
            local hum = model:FindFirstChildOfClass("Humanoid")
            score = hum and hum.Health or score
        end
        if not bestScore or score < bestScore then
            best, bestPart, bestScore = model, part, score
        end
    end
    return best, bestPart
end

---@param keep Model?  previous lock, kept while still valid when Sticky is on
---@return BasePart?
function xDTaraZ.Target.Lock(keep)
    local profile = xDTaraZ.Target.Profile("Aim")
    if keep and xDTaraZ.Options.AimSticky then
        local cam = Workspace.CurrentCamera
        local part = xDTaraZ.Target.Check(keep, profile, cam, cam.CFrame.Position, cam.ViewportSize / 2)
        if part then return part end
    end
    local _, part = xDTaraZ.Target.Pick(profile)
    return part
end

function xDTaraZ.Target.Label(model)
    local player = Players:GetPlayerFromCharacter(model)
    return player and player.DisplayName or ("[Bot] " .. model.Name)
end

xDTaraZ.Combat = { Unhook = nil, PressedAt = 0, Want = false, Refire = false, Pumping = false, Circles = {}, Parts = {}, ReloadedAt = 0, SwitchedAt = 0, TriggerSeen = nil, TriggerSince = 0, TriggerRoll = false }

---@param shot table  27001 payload, edited in place; must not namecall
function xDTaraZ.Combat.Rewrite(shot)
    local state, opts = xDTaraZ.State, xDTaraZ.Options
    local entityId = state.AimEntity
    if not entityId or math.random(100) > opts.SilentHitChance then return end
    local part = (math.random(100) <= opts.SilentHeadChance and state.AimHead) or state.AimBody or state.AimHead
    if not (part and part.Parent) then return end
    local dirs = shot.rayDirections
    if type(dirs) ~= "table" or #dirs == 0 then return end

    local origin = typeof(shot.origin) == "CFrame" and shot.origin.Position or Workspace.CurrentCamera.CFrame.Position
    local offset = part.Position - origin
    local dist = offset.Magnitude
    local range = typeof(dirs[1]) == "Vector3" and dirs[1].Magnitude or xDTaraZ.Config.DefaultRange
    if dist > range or dist < 1e-3 then return end

    local unit = offset.Unit
    local results = table.create(#dirs)
    for index, dir in ipairs(dirs) do
        dirs[index] = unit * (typeof(dir) == "Vector3" and dir.Magnitude or range)
        results[index] = { instance = part, normal = -unit, distance = dist, taggedEntityId = entityId, isTeammate = false }
    end
    shot.rayResults = results
end

function xDTaraZ.Combat.Aiming()
    local opts = xDTaraZ.Options
    return opts.SilentAim or opts.Ragebot
end

function xDTaraZ.Combat.InstallHook()
    local combat = xDTaraZ.Combat
    if combat.Unhook or not GameLib.Main or not xDTaraZ.Caps.Namecall then return end
    local main, getMethod = GameLib.Main, Util.GetNamecall
    local old
    local ok, original, unhook = pcall(xDTaraZ.Library.Compat.HookMeta, game, "__namecall", function(self, ...)
        if self == main and xDTaraZ.State.Alive and xDTaraZ.Combat.Aiming() and getMethod() == "FireServer" then
            local packet = ...
            if type(packet) == "table" and packet[1] == xDTaraZ.Proto.Blaster_ShootReq and type(packet[2]) == "table" then
                xDTaraZ.State.LastShot = osClock()
                local rewritten, err = pcall(xDTaraZ.Combat.Rewrite, packet[2])
                if not rewritten then warn("[AirDropArena] rewrite:", err) end
            end
        end
        return old(self, ...)
    end)
    if not (ok and type(original) == "function") then
        warn("[AirDropArena] shot hook:", ok and "executor refused the hook" or original)
        return
    end
    old, combat.Unhook = original, unhook
end

function xDTaraZ.Combat.RemoveHook()
    local unhook = xDTaraZ.Combat.Unhook
    if not unhook then return end
    xDTaraZ.Combat.Unhook = nil
    Util.Try("shot unhook", unhook)
end

function xDTaraZ.Combat.SyncHook()
    if xDTaraZ.Combat.Aiming() then
        xDTaraZ.Combat.InstallHook()
    else
        xDTaraZ.Combat.RemoveHook()
    end
end

---@return table?  the game's input behaviour for your character (BeginFire/EndFire)
function xDTaraZ.Combat.Behavior()
    local combat = xDTaraZ.Combat
    if combat.Input and rawget(combat.Input, "owner") then return combat.Input end
    combat.Input = nil
    if not xDTaraZ.Caps.Gc or osClock() - (combat.LastScan or 0) < xDTaraZ.Config.StatScanGap then return nil end
    combat.LastScan = osClock()
    for _, entry in ipairs(Util.GetGc(true)) do
        if type(entry) == "table" and rawget(entry, "owner") and type(entry.BeginFire) == "function" and type(entry.FastKnife) == "function" then
            combat.Input = entry
            return entry
        end
    end
    return nil
end

---@return boolean  true once the press reached the game; a timed-out deferred call still lands later
function xDTaraZ.Combat.Press(down)
    local input = xDTaraZ.Combat.Behavior()
    local sent, err = false, nil
    if input then
        sent, err = pcall(xDTaraZ.Library.Compat.Call, down and input.BeginFire or input.EndFire, input)
        sent = sent or tostring(err):find("timed out", 1, true) ~= nil
    end
    if not sent then
        local center = Workspace.CurrentCamera.ViewportSize / 2
        sent = pcall(VirtualInputManager.SendMouseButtonEvent, VirtualInputManager, center.X, center.Y, 0, down, game, 0)
    end
    if not sent then return false end

    xDTaraZ.State.Firing = down
    if down then xDTaraZ.Combat.PressedAt = osClock() end
    return true
end

function xDTaraZ.Combat.Pending()
    local combat, firing = xDTaraZ.Combat, xDTaraZ.State.Firing
    return combat.Want ~= firing or (combat.Refire and firing)
end

function xDTaraZ.Combat.PressNext()
    local combat, firing = xDTaraZ.Combat, xDTaraZ.State.Firing
    local refire = combat.Refire and firing
    combat.Refire = false
    local sent = false
    if refire or combat.Want ~= firing then sent = xDTaraZ.Combat.Press(not refire and combat.Want) end
    combat.Pumping = false

    if sent and not refire and xDTaraZ.Combat.Pending() then xDTaraZ.Combat.Pump() end
end

function xDTaraZ.Combat.Pump()
    local combat = xDTaraZ.Combat
    if combat.Pumping then return end
    combat.Pumping = true
    task.defer(xDTaraZ.Combat.PressNext)
end

---@param want boolean  keeps auto guns held and re-clicks semi-auto ones
function xDTaraZ.Combat.Fire(want)
    local combat, state = xDTaraZ.Combat, xDTaraZ.State
    combat.Want = want
    if want and state.Firing and not combat.Pumping then
        local now, gap = osClock(), xDTaraZ.Config.RefireGap
        combat.Refire = now - combat.PressedAt > gap and now - state.LastShot > gap
    end
    if xDTaraZ.Combat.Pending() then xDTaraZ.Combat.Pump() end
end

---@return table  { Drawing = circle } or a Gui ring when the executor has no Drawing
function xDTaraZ.Combat.NewCircle(color)
    if xDTaraZ.Caps.Drawing then
        local circle = Drawing.new("Circle")
        circle.Thickness, circle.NumSides, circle.Filled, circle.Color = 1.5, 64, false, color
        return { Drawing = circle }
    end

    local ring = Instance.new("Frame")
    ring.AnchorPoint, ring.BackgroundTransparency = Vector2.new(0.5, 0.5), 1
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(1, 0)
    corner.Parent = ring
    local stroke = Instance.new("UIStroke")
    stroke.Thickness, stroke.Color = 1.5, color
    stroke.Parent = ring
    ring.Parent = Util.Screen()
    return { Ring = ring }
end

function xDTaraZ.Combat.UpdateCircles()
    local opts, config = xDTaraZ.Options, xDTaraZ.Config
    xDTaraZ.Combat.UpdateCircle("Aim", opts.ShowFov, opts.AimFov, config.FovColor)
    xDTaraZ.Combat.UpdateCircle("Silent", opts.ShowSilentFov, opts.SilentFov, config.SilentFovColor)
end

function xDTaraZ.Combat.UpdateCircle(key, show, radius, color)
    local circles = xDTaraZ.Combat.Circles
    local circle = circles[key]
    if not circle then
        if not show then return end
        circle = xDTaraZ.Combat.NewCircle(color)
        circles[key] = circle
    end

    local center = Workspace.CurrentCamera.ViewportSize / 2
    if circle.Drawing then
        circle.Drawing.Visible, circle.Drawing.Position, circle.Drawing.Radius = show, center, radius
        return
    end
    circle.Ring.Visible = show
    circle.Ring.Position = UDim2.fromOffset(center.X, center.Y)
    circle.Ring.Size = UDim2.fromOffset(radius * 2, radius * 2)
end

local triggerParams = RaycastParams.new()
triggerParams.FilterType = Enum.RaycastFilterType.Exclude

---@return boolean  true while the crosshair sits on an enemy long enough to shoot
function xDTaraZ.Combat.TriggerWant()
    local combat, opts = xDTaraZ.Combat, xDTaraZ.Options
    local cam = Workspace.CurrentCamera
    triggerParams.FilterDescendantsInstances = { LocalPlayer.Character, cam }
    local hit = Workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * xDTaraZ.Config.TriggerRange, triggerParams)
    local model = hit and hit.Instance:FindFirstAncestorOfClass("Model")
    while model and not model:GetAttribute("EntityId") do
        model = model.Parent and model.Parent:FindFirstAncestorOfClass("Model")
    end
    if not (model and xDTaraZ.Target.IsEnemy(model)) then
        combat.TriggerSeen = nil
        return false
    end
    if combat.TriggerSeen ~= model then
        combat.TriggerSeen, combat.TriggerSince = model, osClock()
        combat.TriggerRoll = math.random(100) <= opts.TriggerChance
    end
    return combat.TriggerRoll and osClock() - combat.TriggerSince >= opts.TriggerDelay / 1000
end

---@return table  equip part -> live gun object; stale copies lose their blaster field
function xDTaraZ.Combat.ScanGuns()
    local combat = xDTaraZ.Combat
    for part, gun in pairs(combat.Parts) do
        if rawget(gun, "blaster") == nil then combat.Parts[part] = nil end
    end
    local char = LocalPlayer.Character
    local using = char and char:GetAttribute("UseEPos")
    if not using or combat.Parts[using] or not xDTaraZ.Caps.Gc then return combat.Parts end
    for _, entry in ipairs(Util.GetGc(true)) do
        local part = type(entry) == "table" and rawget(entry, "islocalplayer") == true and rawget(entry, "blaster") ~= nil and rawget(entry, "blasterPart")
        if part then combat.Parts[part] = entry end
    end
    return combat.Parts
end

---@return table?  the gun in your hands right now
function xDTaraZ.Combat.HeldGun()
    local char = LocalPlayer.Character
    local using = char and char:GetAttribute("UseEPos")
    local gun = using and xDTaraZ.Combat.Parts[using]
    return gun and rawget(gun, "blaster") ~= nil and gun or nil
end

function xDTaraZ.Combat.GunStep()
    local opts = xDTaraZ.Options
    if not (xDTaraZ.Combat.Aiming() or opts.Triggerbot or opts.SmartReload) then return end
    if not xDTaraZ.Player.InBattle() then return end
    xDTaraZ.Combat.ScanGuns()
    if xDTaraZ.Combat.Aiming() then xDTaraZ.Combat.DrawGun() end
    if opts.SmartReload then xDTaraZ.Combat.Reload() end
end

---@return boolean  switched from the knife back to a gun so aim features can hit at range
function xDTaraZ.Combat.DrawGun()
    local combat = xDTaraZ.Combat
    local char = LocalPlayer.Character
    if not char or char:GetAttribute("UseEPos") ~= xDTaraZ.Config.MeleePart then return false end
    if osClock() - combat.SwitchedAt < xDTaraZ.Config.SwitchGap then return false end
    local input = xDTaraZ.Combat.Behavior()
    if not (input and type(input.SwitchBlaster) == "function") then return false end
    for _, part in ipairs(xDTaraZ.Config.GunSlots) do
        local worn = char:GetAttribute("EPos_" .. part)
        if type(worn) ~= "string" or worn:match("^I_(%d+)") == "0" then continue end
        combat.SwitchedAt = osClock()
        local ok, err = pcall(xDTaraZ.Library.Compat.Call, input.SwitchBlaster, input, part)
        if not ok and not tostring(err):find("timed out", 1, true) then warn("[AirDropArena] switch:", err) end
        return true
    end
    return false
end

---@return boolean  a reload was started; only between fights and below the set magazine level
function xDTaraZ.Combat.Reload()
    local combat, opts = xDTaraZ.Combat, xDTaraZ.Options
    local gun = xDTaraZ.Combat.HeldGun()
    local map = gun and rawget(gun, "propMap")
    local ammo, size = gun and rawget(gun, "ammo"), map and tonumber(map[71])
    if not (type(ammo) == "number" and size and size > 1) then return false end
    if ammo >= size or ammo / size * 100 > opts.ReloadAt and ammo > 0 then return false end
    if xDTaraZ.State.Target and ammo > 0 then return false end
    if osClock() - combat.ReloadedAt < (tonumber(map[78]) or 2) + xDTaraZ.Config.ReloadSlack then return false end
    local input = xDTaraZ.Combat.Behavior()
    if not (input and type(input.BeginReload) == "function") then return false end
    combat.ReloadedAt = osClock()
    local ok, err = pcall(xDTaraZ.Library.Compat.Call, input.BeginReload, input)
    if not ok and not tostring(err):find("timed out", 1, true) then warn("[AirDropArena] reload:", err) end
    return true
end

function xDTaraZ.Combat.Clear()
    local state = xDTaraZ.State
    state.Target, state.AimHead, state.AimBody, state.AimEntity, state.LockPart = nil, nil, nil, nil, nil
end

function xDTaraZ.Combat.Step()
    local opts, state = xDTaraZ.Options, xDTaraZ.State
    xDTaraZ.Combat.UpdateCircles()

    local active = xDTaraZ.Combat.Aiming() or opts.Aimbot or opts.Triggerbot
    if not (active and xDTaraZ.Player.InBattle()) then
        xDTaraZ.Combat.Clear()
        xDTaraZ.Combat.Fire(false)
        return
    end

    local target
    if opts.Ragebot then
        target = xDTaraZ.Target.Pick(xDTaraZ.Target.Profile("Rage"))
    elseif opts.SilentAim then
        target = xDTaraZ.Target.Pick(xDTaraZ.Target.Profile("Silent"))
    end
    state.AimHead = target and xDTaraZ.Target.Part(target, "Head")
    state.AimBody = target and xDTaraZ.Target.Part(target, "Torso")
    state.AimEntity = target and target:GetAttribute("EntityId")

    local locked = state.LockPart and state.LockPart.Parent
    state.LockPart = opts.Aimbot and xDTaraZ.Target.Lock(locked) or nil
    state.Target = target or (state.LockPart and state.LockPart.Parent)

    local trigger = opts.Triggerbot and xDTaraZ.Combat.TriggerWant()
    local held = xDTaraZ.Combat.HeldGun()
    local empty = held ~= nil and rawget(held, "ammo") == 0
    xDTaraZ.Combat.Fire(not empty and ((target ~= nil and opts.Ragebot) or trigger == true))
end

function xDTaraZ.Combat.OnServer(packet)
    if type(packet) ~= "table" or type(packet[2]) ~= "table" then return end
    local id, body = packet[1], packet[2]
    if id == xDTaraZ.Proto.Blaster_BulletHitNotify then
        if body.killerEntityId ~= xDTaraZ.Player.EntityId() then return end
        xDTaraZ.State.Hits += 1
        xDTaraZ.Damage.OnHit(body.targetEntityId)
    elseif id == xDTaraZ.Proto.Battlefield_EntityDeathNotify then
        local mine = body.killerEntityId == xDTaraZ.Player.EntityId()
        if mine then xDTaraZ.State.Kills += 1 end
        xDTaraZ.Damage.OnDeath(body.entityId, mine)
    elseif id == xDTaraZ.Config.NoticeProto then
        xDTaraZ.Hunt.OnNotice(body.context)
    elseif id == xDTaraZ.Proto.Battlefield_S2CCustomSyncNotify then
        xDTaraZ.Loot.OnSync(body)
    end
end

function xDTaraZ.Combat.LockCamera()
    local part = xDTaraZ.State.LockPart
    if not (xDTaraZ.Options.Aimbot and part and part.Parent) then return end
    local cam = Workspace.CurrentCamera
    local origin = cam.CFrame.Position
    local want = (part.Position - origin).Unit
    local smooth = math.max(xDTaraZ.Options.AimSmooth, 1)
    local look = smooth <= 1 and want or cam.CFrame.LookVector:Lerp(want, 1 / smooth).Unit
    cam.CFrame = cframeLookAt(origin, origin + look)
end

function xDTaraZ.Combat.Rest()
    xDTaraZ.Combat.Clear()
    xDTaraZ.Combat.Fire(false)
    xDTaraZ.Combat.UpdateCircles()
end

function xDTaraZ.Combat.Start()
    RunService:BindToRenderStep("xDTaraZAim", xDTaraZ.Config.AimRenderPriority, xDTaraZ.Combat.LockCamera)
    xDTaraZ:Connect(RunService.Heartbeat, function()
        local ok, err = pcall(xDTaraZ.Combat.Step)
        if ok then
            xDTaraZ.Faults.Clear("Combat")
        else
            xDTaraZ.Faults.Report("Combat", err, xDTaraZ.Config.CombatToggles, xDTaraZ.Combat.Rest)
        end
    end)
    if GameLib.Main then xDTaraZ:Connect(GameLib.Main.OnClientEvent, xDTaraZ.Combat.OnServer) end
end

function xDTaraZ.Combat.Unload()
    xDTaraZ.Combat.Fire(false)
    xDTaraZ.Combat.RemoveHook()
    pcall(RunService.UnbindFromRenderStep, RunService, "xDTaraZAim")
    for key, circle in pairs(xDTaraZ.Combat.Circles) do
        xDTaraZ.Combat.Circles[key] = nil
        if circle.Drawing then
            pcall(function() circle.Drawing:Remove() end)
        else
            circle.Ring:Destroy()
        end
    end
end

function xDTaraZ.Combat.GetStatus()
    local state = xDTaraZ.State
    local target = state.Target and xDTaraZ.Target.Label(state.Target) or "none"
    return string.format("Target: %s | Hits %d | Kills %d | Guns %d",
        target, state.Hits, state.Kills, xDTaraZ.Guns.Count)
end

xDTaraZ.Guns = {
    Known = setmetatable({}, { __mode = "k" }),
    Saved = setmetatable({}, { __mode = "k" }),
    Count = 0,
    LastScan = 0,
    Signature = "",
}

function xDTaraZ.Guns.Wanted()
    local opts = xDTaraZ.Options
    return opts.NoSpread or opts.NoRecoil or opts.InstantAds
end

function xDTaraZ.Guns.Scan()
    if not xDTaraZ.Caps.Gc then return end
    local known, count = xDTaraZ.Guns.Known, 0
    for _, entry in ipairs(Util.GetGc(true)) do
        if type(entry) == "table" and rawget(entry, "islocalplayer") == true and type(rawget(entry, "propMap")) == "table" then
            known[entry] = true
            count += 1
        end
    end
    xDTaraZ.Guns.Count = count
    xDTaraZ.Guns.LastScan = osClock()
end

---@return string  changes whenever the held loadout changes
function xDTaraZ.Guns.LoadoutSignature()
    local char = LocalPlayer.Character
    local folder = char and char:FindFirstChild("Blaster")
    if not folder then return "" end
    local names = {}
    for _, child in ipairs(folder:GetChildren()) do names[#names + 1] = child.Name end
    return table.concat(names, "|")
end

---@return number?  nil keeps the original value
function xDTaraZ.Guns.Desired(id, base)
    local opts = xDTaraZ.Options
    if (id == 72 or id == 73) and opts.NoSpread then return 0 end
    if id == 82 and opts.InstantAds then return xDTaraZ.Config.AdsSpeed end
    return nil
end

local function NoRecoilRate() return 0 end
local function NoRecoil() end

function xDTaraZ.Guns.ApplyRecoil(blaster, saved)
    if xDTaraZ.Options.NoRecoil then
        if saved.Recoil then return end
        saved.Recoil = { rawget(blaster, "GetRecoilRate") or false, rawget(blaster, "Recoil") or false }
        rawset(blaster, "GetRecoilRate", NoRecoilRate)
        rawset(blaster, "Recoil", NoRecoil)
    elseif saved.Recoil then
        rawset(blaster, "GetRecoilRate", saved.Recoil[1] or nil)
        rawset(blaster, "Recoil", saved.Recoil[2] or nil)
        saved.Recoil = nil
    end
end

function xDTaraZ.Guns.Apply()
    local savedAll = xDTaraZ.Guns.Saved
    for blaster in pairs(xDTaraZ.Guns.Known) do
        local map = rawget(blaster, "propMap")
        if type(map) ~= "table" then continue end
        local saved = savedAll[blaster] or {}
        savedAll[blaster] = saved

        for _, id in ipairs(xDTaraZ.Config.ModProps) do
            local base = saved[id] or map[id]
            if type(base) ~= "number" then continue end
            local want = xDTaraZ.Guns.Desired(id, base)
            if want then
                saved[id], map[id] = base, want
            elseif saved[id] then
                map[id], saved[id] = saved[id], nil
            end
        end
        xDTaraZ.Guns.ApplyRecoil(blaster, saved)
    end
end

function xDTaraZ.Guns.Step()
    if not xDTaraZ.Guns.Wanted() and next(xDTaraZ.Guns.Saved) == nil then return end
    local signature = xDTaraZ.Guns.LoadoutSignature()
    if xDTaraZ.Guns.Wanted() and (signature ~= xDTaraZ.Guns.Signature or osClock() - xDTaraZ.Guns.LastScan > xDTaraZ.Config.GunScanInterval) then
        xDTaraZ.Guns.Signature = signature
        xDTaraZ.Guns.Scan()
    end
    xDTaraZ.Guns.Apply()
end

function xDTaraZ.Guns.Restore()
    for _, key in ipairs(xDTaraZ.Config.GunToggles) do
        xDTaraZ.Options[key] = false
    end
    xDTaraZ.Guns.Apply()
    table.clear(xDTaraZ.Guns.Saved)
end

xDTaraZ.Loot = { Marks = {} }

function xDTaraZ.Loot.Folder()
    return Workspace:FindFirstChild("DropItemFloder")
end

---@return string?  "AirDrop", "Crate" or "Item"
function xDTaraZ.Loot.Kind(model)
    if model.Name == "AirDrop" or model:GetAttribute("AirDropClientModel") then return "AirDrop" end
    local bagType = model:GetAttribute("BagType")
    if bagType == 20000 then return "Crate" end
    if bagType == 10000 or model:GetAttribute("ItemId") then return "Item" end
    return nil
end

function xDTaraZ.Loot.Label(model, kind)
    if kind == "Item" then
        local id = model:GetAttribute("ItemId")
        return id and xDTaraZ.ItemNames[id] or "Item"
    end
    return kind == "AirDrop" and "Air Drop" or "Crate"
end

---@return table?  the game's drop manager, holds every bag the client knows about
function xDTaraZ.Loot.Manager()
    local cached = xDTaraZ.Loot.DropManager
    if cached or not xDTaraZ.Caps.Gc then return cached end
    for _, entry in ipairs(Util.GetGc(true)) do
        if type(entry) == "table" and rawget(entry, "dropItems") and type(rawget(entry, "BagController")) == "table" then
            xDTaraZ.Loot.DropManager = entry
            return entry
        end
    end
    return nil
end

function xDTaraZ.Loot.ItemConfig(configId)
    local items = GameLib.Configs.ItemConfig
    if not items then return nil end
    local ok, cfg = pcall(items.GetItemConfigById, items, configId)
    return ok and type(cfg) == "table" and cfg or nil
end

---@return table  item type -> { label, { equip slots } }, read from the game so new gear slots show up by themselves
function xDTaraZ.Loot.Slots()
    if xDTaraZ.Loot.SlotMap then return xDTaraZ.Loot.SlotMap end
    local enum = GameLib.BagEnum
    local names, types = enum and enum.EquipMentPosMap, enum and enum.EquipMentPosToItemTypeMap
    if type(names) ~= "table" or type(types) ~= "table" then
        xDTaraZ.Loot.SlotMap = xDTaraZ.Config.GearSlots
        return xDTaraZ.Loot.SlotMap
    end
    local map = {}
    for name, pos in pairs(names) do
        local itemType = type(pos) == "number" and types[pos]
        if not itemType or name == "Min" or name == "Max" then continue end
        local entry = map[itemType] or { xDTaraZ.Config.SlotLabels[name] or name, {} }
        table.insert(entry[2], pos)
        map[itemType] = entry
    end
    xDTaraZ.Loot.SlotMap = map
    return map
end

---@return string[]  gear labels for the loot filter
function xDTaraZ.Loot.SlotLabels()
    local labels, seen = {}, {}
    for _, entry in pairs(xDTaraZ.Loot.Slots()) do
        if not seen[entry[1]] then
            seen[entry[1]] = true
            labels[#labels + 1] = entry[1]
        end
    end
    table.sort(labels)
    return labels
end

xDTaraZ.Loot.GunStats = {}

---@return table  { damage, rpm, rays, ammo item ids } from the game's weapon table, nil for non-guns
function xDTaraZ.Loot.Gun(itemId)
    local cache = xDTaraZ.Loot.GunStats
    if cache[itemId] ~= nil then return cache[itemId] or nil end
    local blasters = GameLib.Configs.BlasterConfig
    local ok, cfg = pcall(function() return blasters:GetBlasterConfigById(itemId) end)
    local att = ok and type(cfg) == "table" and cfg.attMap
    local ammo = ok and type(cfg) == "table" and type(cfg.bulletIds) == "table" and cfg.bulletIds or {}
    local stats = type(att) == "table" and tonumber(att[77]) and { tonumber(att[77]), tonumber(att[70]) or 60, tonumber(att[74]) or 1, ammo } or false
    cache[itemId] = stats
    return stats or nil
end

---@return number  higher = better within one item type
function xDTaraZ.Loot.Score(cfg)
    local mode = xDTaraZ.Options.GearScore
    local gun = mode ~= "Rarity" and xDTaraZ.Config.GunTypes[cfg.type] and xDTaraZ.Loot.Gun(cfg.id)
    if gun then
        local perShot = gun[1] * gun[3]
        return mode == "Damage per shot" and perShot or perShot * gun[2] / 60
    end
    return (cfg.quality or 0) * 1e7 + (cfg.value or 0)
end

---@return string?  buff family ("Atk", "FireRate" ...) of a buff item name
function xDTaraZ.Loot.BuffKind(name)
    return type(name) == "string" and name:match("^([%a]+)%+") or nil
end

---@return string[], string[]  currency names, buff families; read from the game's item table
function xDTaraZ.Loot.Kinds()
    if xDTaraZ.Loot.KindLists then return table.unpack(xDTaraZ.Loot.KindLists) end
    local currencies, buffs, seen = {}, {}, {}
    for id = 1, xDTaraZ.Config.ItemScan do
        local cfg = xDTaraZ.Loot.ItemConfig(id)
        local name = cfg and cfg.name
        if type(name) ~= "string" or seen[name] or name:find("[\128-\255]") then continue end
        if cfg.type == xDTaraZ.Config.CurrencyType then
            seen[name] = true
            currencies[#currencies + 1] = name
        elseif cfg.type == xDTaraZ.Config.BuffType then
            local kind = xDTaraZ.Loot.BuffKind(name)
            if kind and not seen[kind] then
                seen[kind] = true
                buffs[#buffs + 1] = kind
            end
        end
    end
    xDTaraZ.Loot.KindLists = { currencies, buffs }
    return currencies, buffs
end

---@param slots number[]  equip slots that take this item type
---@return number           score of the weakest item worn in them, 0 when one is empty, huge when you have none of these slots
function xDTaraZ.Loot.WornScore(slots)
    local char = LocalPlayer.Character
    local weakest = math.huge
    for _, slot in ipairs(slots) do
        local worn = char and char:GetAttribute("EPos_" .. slot)
        if worn == nil then continue end
        local id = type(worn) == "string" and tonumber(worn:match("^I_(%d+)"))
        local cfg = id and id > 0 and xDTaraZ.Loot.ItemConfig(id)
        weakest = math.min(weakest, cfg and xDTaraZ.Loot.Score(cfg) or 0)
    end
    return weakest
end

---@return table  item ids lying in any bag on the map
function xDTaraZ.Loot.OnMap(bags)
    local present = {}
    for _, bag in pairs(bags) do
        for _, item in pairs(type(bag.itemMap) == "table" and bag.itemMap or {}) do present[item.configId] = true end
    end
    return present
end

---@return boolean  false for a gun whose ammo is nowhere on the map, so you never swap to a gun you can't feed
function xDTaraZ.Loot.Feedable(cfg, present)
    local gun = xDTaraZ.Config.GunTypes[cfg.type] and xDTaraZ.Loot.Gun(cfg.id)
    if not gun or #gun[4] == 0 then return true end
    for _, ammo in ipairs(gun[4]) do
        if present[ammo] then return true end
    end
    return false
end

---@return table[]  { bagUid, itemUid, name } for every slot that has a better item lying around
function xDTaraZ.Loot.Upgrades()
    local manager = xDTaraZ.Loot.Manager()
    local bags = manager and manager.BagController.bagMap
    if type(bags) ~= "table" then return {} end
    local wanted, slots = xDTaraZ.Options.LootGear, xDTaraZ.Loot.Slots()
    local present = xDTaraZ.Loot.OnMap(bags)
    local best = {}
    for bagUid, bag in pairs(bags) do
        for itemUid, item in pairs(type(bag.itemMap) == "table" and bag.itemMap or {}) do
            local cfg = xDTaraZ.Loot.ItemConfig(item.configId)
            local gear = cfg and slots[cfg.type]
            if not (gear and wanted[gear[1]] and xDTaraZ.Loot.Feedable(cfg, present)) then continue end
            local tried = xDTaraZ.State.Tried[itemUid]
            if tried and osClock() - tried < xDTaraZ.Config.LootRetry then continue end
            local score = xDTaraZ.Loot.Score(cfg)
            local top = best[cfg.type]
            if not top or score > top[4] then best[cfg.type] = { bagUid, itemUid, cfg.name, score } end
        end
    end

    local list = {}
    for itemType, pick in pairs(best) do
        if pick[4] > xDTaraZ.Loot.WornScore(slots[itemType][2]) then list[#list + 1] = pick end
    end
    return list
end

---@return number  items requested
function xDTaraZ.Loot.TakeUpgrades()
    if not xDTaraZ.Player.InBattle() then return 0 end
    local got = 0
    for _, pick in ipairs(xDTaraZ.Loot.Upgrades()) do
        if xDTaraZ.Loot.Pick(pick[1], pick[2], pick[3]) then got += 1 end
    end
    xDTaraZ.State.Looted += got
    return got
end

---@param types table  { Currency = bool, Buff = bool }
---@return number      items requested from every bag on the map
function xDTaraZ.Loot.TakeValuables(types)
    local manager = xDTaraZ.Loot.Manager()
    local bags = manager and manager.BagController.bagMap
    if not (type(bags) == "table" and xDTaraZ.Player.InBattle()) then return 0 end
    local got = 0
    for bagUid, bag in pairs(bags) do
        for itemUid, item in pairs(type(bag.itemMap) == "table" and bag.itemMap or {}) do
            local cfg = xDTaraZ.Loot.ItemConfig(item.configId)
            if not cfg then continue end
            local opts = xDTaraZ.Options
            local wanted = (types.Currency and cfg.type == xDTaraZ.Config.CurrencyType and opts.LootCurrency[cfg.name])
                or (types.Buff and cfg.type == xDTaraZ.Config.BuffType and opts.LootBuffs[xDTaraZ.Loot.BuffKind(cfg.name) or ""])
            if not wanted then continue end
            if xDTaraZ.Loot.Pick(bagUid, itemUid, cfg.name) then got += 1 end
        end
    end
    xDTaraZ.State.Valuables += got
    return got
end

---@return table  ammo item ids for every gun you carry
function xDTaraZ.Loot.AmmoWanted()
    local set, char = {}, LocalPlayer.Character
    for _, slot in ipairs(xDTaraZ.Config.GunSlots) do
        local worn = char and char:GetAttribute("EPos_" .. slot)
        local id = type(worn) == "string" and tonumber(worn:match("^I_(%d+)"))
        local gun = id and id > 0 and xDTaraZ.Loot.Gun(id)
        for _, ammo in ipairs(gun and gun[4] or {}) do set[ammo] = true end
    end
    return set
end

---@return number  ammo stacks requested for the guns you carry, from anywhere on the map
function xDTaraZ.Loot.TakeAmmo()
    local manager = xDTaraZ.Loot.Manager()
    local bags = manager and manager.BagController.bagMap
    if not (type(bags) == "table" and xDTaraZ.Player.InBattle()) then return 0 end
    local wanted, got = xDTaraZ.Loot.AmmoWanted(), 0
    for bagUid, bag in pairs(bags) do
        for itemUid, item in pairs(type(bag.itemMap) == "table" and bag.itemMap or {}) do
            if not wanted[item.configId] then continue end
            if xDTaraZ.Loot.Pick(bagUid, itemUid, xDTaraZ.ItemNames[item.configId]) then got += 1 end
            if got >= xDTaraZ.Config.AmmoBatch then return got end
        end
    end
    return got
end

function xDTaraZ.Loot.AmmoStep()
    if xDTaraZ.Options.AutoAmmo then xDTaraZ.Loot.TakeAmmo() end
end

function xDTaraZ.Loot.ValuablesStep()
    local opts = xDTaraZ.Options
    if not (opts.AutoValuables or opts.AutoBuffs) then return end
    xDTaraZ.Loot.TakeValuables({ Currency = opts.AutoValuables, Buff = opts.AutoBuffs })
end

function xDTaraZ.Loot.GearStep()
    if not xDTaraZ.Options.AutoGear then return end
    xDTaraZ.Loot.TakeUpgrades()
end

---@return boolean  false when skipped or not sent
function xDTaraZ.Loot.Pick(bagUid, itemUid, name)
    local tried = xDTaraZ.State.Tried
    if tried[itemUid] and osClock() - tried[itemUid] < xDTaraZ.Config.LootRetry then return false end
    tried[itemUid] = osClock()
    if not xDTaraZ.Net.Send("DropItem_PickWorldItemReq", { bagUid = bagUid, itemUid = itemUid }) then return false end
    xDTaraZ.State.LastLoot = name or xDTaraZ.State.LastLoot
    return true
end

---@return number  items requested from every air drop on the map; gear only when it beats what you wear
function xDTaraZ.Loot.EmptyAirDrops()
    local manager, folder = xDTaraZ.Loot.Manager(), xDTaraZ.Loot.Folder()
    local bags = manager and manager.BagController.bagMap
    if not (type(bags) == "table" and folder and GameLib.Configs.ItemConfig and xDTaraZ.Player.InBattle()) then return 0 end
    local got, taken = 0, {}
    for _, model in ipairs(folder:GetChildren()) do
        local bagUid = model:GetAttribute("BagUid")
        local bag = xDTaraZ.Loot.Kind(model) == "AirDrop" and bagUid and bags[bagUid]
        if not bag then continue end
        for itemUid, item in pairs(bag.itemMap) do
            local cfg = xDTaraZ.Loot.ItemConfig(item.configId)
            local gear = cfg and xDTaraZ.Loot.Slots()[cfg.type]
            if gear and (taken[cfg.type] or xDTaraZ.Loot.Score(cfg) <= xDTaraZ.Loot.WornScore(gear[2])) then continue end
            if xDTaraZ.Loot.Pick(bagUid, itemUid, cfg and cfg.name) then
                got += 1
                if gear then taken[cfg.type] = true end
            end
        end
    end
    xDTaraZ.State.AirDrops += got
    return got
end

function xDTaraZ.Loot.AirDropStep()
    if xDTaraZ.Options.AutoAirDrop then xDTaraZ.Loot.EmptyAirDrops() end
end

function xDTaraZ.Loot.OnSync(body)
    local timer = body.airdptime
    if type(timer) == "table" and type(timer.endstamp) == "number" then xDTaraZ.State.AirDropAt = timer.endstamp end
end

function xDTaraZ.Loot.Mark(model, kind)
    local gui = Instance.new("BillboardGui")
    gui.Name, gui.AlwaysOnTop, gui.Size, gui.StudsOffset = "xDTaraZLoot", true, UDim2.fromOffset(180, 20), vector3New(0, 2, 0)
    local label = Instance.new("TextLabel")
    label.BackgroundTransparency, label.Size, label.Font, label.TextSize = 1, UDim2.fromScale(1, 1), Enum.Font.GothamBold, 12
    label.TextColor3, label.TextStrokeTransparency = xDTaraZ.Config.LootColors[kind], 0.3
    label.Parent = gui
    gui.Adornee = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
    Util.Mount(gui)
    return { Gui = gui, Label = label }
end

function xDTaraZ.Loot.ClearMarks()
    for _, mark in pairs(xDTaraZ.Loot.Marks) do mark.Gui:Destroy() end
    table.clear(xDTaraZ.Loot.Marks)
end

function xDTaraZ.Loot.EspStep()
    local opts = xDTaraZ.Options
    local marks = xDTaraZ.Loot.Marks
    local show = { AirDrop = opts.LootEspAirDrop, Crate = opts.LootEspCrate, Item = opts.LootEspItem }
    if not (show.AirDrop or show.Crate or show.Item) then
        if next(marks) ~= nil then xDTaraZ.Loot.ClearMarks() end
        return
    end

    local folder, hrp = xDTaraZ.Loot.Folder(), xDTaraZ.Player.Root()
    local seen = {}
    if folder and hrp then
        for _, model in ipairs(folder:GetChildren()) do
            local kind = xDTaraZ.Loot.Kind(model)
            if not (kind and show[kind]) then continue end
            local dist = (model:GetPivot().Position - hrp.Position).Magnitude
            if dist > opts.LootEspRange and kind ~= "AirDrop" then continue end
            seen[model] = true
            marks[model] = marks[model] or xDTaraZ.Loot.Mark(model, kind)
            local opened = kind == "AirDrop" and model:GetAttribute("AirDropOpened") and " (opened)" or ""
            marks[model].Label.Text = string.format("%s%s [%dm]", xDTaraZ.Loot.Label(model, kind), opened, math.floor(dist))
        end
    end

    for model, mark in pairs(marks) do
        if not seen[model] then
            mark.Gui:Destroy()
            marks[model] = nil
        end
    end
end

xDTaraZ.Slide = { Skill = nil, LastScan = 0, Dir = nil }

---@return table?  the game's slide skill object for you
function xDTaraZ.Slide.Find()
    local slide = xDTaraZ.Slide
    if slide.Skill then return slide.Skill end
    if not xDTaraZ.Caps.Gc or osClock() - slide.LastScan < xDTaraZ.Config.StatScanGap then return nil end
    slide.LastScan = osClock()
    for _, entry in ipairs(Util.GetGc(true)) do
        if type(entry) == "table" and rawget(entry, "slideRequestId") ~= nil and rawget(entry, "owner") and getmetatable(entry) then
            slide.Skill = entry
            return entry
        end
    end
    return nil
end

function xDTaraZ.Slide.OnHeartbeat()
    local slide = xDTaraZ.Slide
    local skill = xDTaraZ.Options.SuperSlide and xDTaraZ.Slide.Find()
    local hrp, hum = xDTaraZ.Player.Root(), xDTaraZ.Player.Humanoid()
    if not (skill and hrp and hum and rawget(skill, "slideActive")) then
        slide.Dir = nil
        return
    end
    if not slide.Dir then
        local move = hum.MoveDirection * vector3New(1, 0, 1)
        local look = Workspace.CurrentCamera.CFrame.LookVector * vector3New(1, 0, 1)
        slide.Dir = move.Magnitude > 0.1 and move.Unit or look.Unit
    end
    local vel, speed = hrp.AssemblyLinearVelocity, xDTaraZ.Options.SlideSpeed
    hrp.AssemblyLinearVelocity = vector3New(slide.Dir.X * speed, vel.Y, slide.Dir.Z * speed)
end

xDTaraZ.Movement = { Collided = {} }

function xDTaraZ.Movement.OnHeartbeat(dt)
    local opts = xDTaraZ.Options
    if not (opts.Speed or opts.Fly) then return end
    local hrp, hum = xDTaraZ.Player.Root(), xDTaraZ.Player.Humanoid()
    if not (hrp and hum) or hum.Health <= 0 then return end

    if opts.Fly then
        local vertical = 0
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then vertical += 1 end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then vertical -= 1 end
        local dir = hum.MoveDirection + vector3New(0, vertical, 0)
        hrp.AssemblyLinearVelocity = dir.Magnitude > 0 and dir.Unit * opts.FlySpeed or Vector3.zero
        return
    end

    local extra = opts.SpeedValue - hum.WalkSpeed
    if extra > 0 and hum.MoveDirection.Magnitude > 0 then
        hrp.CFrame += hum.MoveDirection * extra * dt
    end
end

function xDTaraZ.Movement.OnStepped()
    local saved = xDTaraZ.Movement.Collided
    local char = LocalPlayer.Character
    if not xDTaraZ.Options.Noclip then
        if next(saved) == nil then return end
        for part in pairs(saved) do
            if part.Parent then part.CanCollide = true end
        end
        table.clear(saved)
        return
    end
    if not char then return end
    for _, part in ipairs(char:GetChildren()) do
        if part:IsA("BasePart") and part.CanCollide then
            saved[part] = true
            part.CanCollide = false
        end
    end
end

function xDTaraZ.Movement.OnJumpRequest()
    if not xDTaraZ.Options.InfiniteJump then return end
    local hum = xDTaraZ.Player.Humanoid()
    if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
end

function xDTaraZ.Movement.Start()
    xDTaraZ:Connect(RunService.Heartbeat, xDTaraZ.Movement.OnHeartbeat)
    xDTaraZ:Connect(RunService.Heartbeat, xDTaraZ.Slide.OnHeartbeat)
    xDTaraZ:Connect(RunService.Stepped, xDTaraZ.Movement.OnStepped)
    xDTaraZ:Connect(UserInputService.JumpRequest, xDTaraZ.Movement.OnJumpRequest)
end

function xDTaraZ.Movement.StopFly()
    local hrp = xDTaraZ.Player.Root()
    if hrp then hrp.AssemblyLinearVelocity = Vector3.zero end
end

xDTaraZ.World = { Saved = nil, FovSaved = nil }

function xDTaraZ.World.Step()
    local saved = xDTaraZ.World.Saved
    if xDTaraZ.Options.Fullbright then
        if not saved then
            xDTaraZ.World.Saved = { Lighting.Brightness, Lighting.ClockTime, Lighting.FogEnd, Lighting.GlobalShadows, Lighting.Ambient }
        end
        Lighting.Brightness, Lighting.ClockTime, Lighting.FogEnd = 2, 14, 1e6
        Lighting.GlobalShadows, Lighting.Ambient = false, Color3.fromRGB(178, 178, 178)
    elseif saved then
        Lighting.Brightness, Lighting.ClockTime, Lighting.FogEnd, Lighting.GlobalShadows, Lighting.Ambient = table.unpack(saved)
        xDTaraZ.World.Saved = nil
    end
end

function xDTaraZ.World.OnRender()
    local cam = Workspace.CurrentCamera
    if xDTaraZ.Options.CameraFov then
        xDTaraZ.World.FovSaved = xDTaraZ.World.FovSaved or cam.FieldOfView
        cam.FieldOfView = xDTaraZ.Options.CameraFovValue
    elseif xDTaraZ.World.FovSaved then
        cam.FieldOfView = xDTaraZ.World.FovSaved
        xDTaraZ.World.FovSaved = nil
    end
end

function xDTaraZ.World.OnIdled()
    if not xDTaraZ.Options.AntiAfk then return end
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.zero)
end

function xDTaraZ.World.Rejoin()
    TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
end

function xDTaraZ.World.Hop()
    local body = Util.HttpGet(("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Desc&limit=100"):format(game.PlaceId))
    local ok, list = pcall(HttpService.JSONDecode, HttpService, body)
    for _, server in ipairs(ok and list.data or {}) do
        if server.id ~= game.JobId and server.playing < server.maxPlayers then
            TeleportService:TeleportToPlaceInstance(game.PlaceId, server.id, LocalPlayer)
            return true
        end
    end
    return false
end

xDTaraZ.Respawn = {}

function xDTaraZ.Respawn.Now()
    local state = xDTaraZ.State
    if osClock() - state.LastRespawn < xDTaraZ.Config.RespawnGap then return false end
    state.LastRespawn = osClock()
    return xDTaraZ.Net.Send("Battlefield_DeployReq")
end

function xDTaraZ.Respawn.Step()
    local state = xDTaraZ.State
    if not xDTaraZ.Player.IsSoul() then
        state.SoulSince = nil
        return
    end
    state.SoulSince = state.SoulSince or osClock()
    if not xDTaraZ.Options.InstantRespawn or osClock() - state.SoulSince < xDTaraZ.Options.RespawnDelay then return end
    xDTaraZ.Respawn.Now()
end

function xDTaraZ.Respawn.Rejoin()
    local char = LocalPlayer.Character
    if not xDTaraZ.Options.AutoRejoin or not (char and char:GetAttribute("EntityState") == 0) then
        xDTaraZ.Farm.LobbySince = nil
        return
    end
    xDTaraZ.Farm.LobbySince = xDTaraZ.Farm.LobbySince or osClock()
    if osClock() - xDTaraZ.Farm.LobbySince > xDTaraZ.Config.LobbyRejoin then xDTaraZ.Respawn.Now() end
end

function xDTaraZ.Respawn.Watch(char)
    if xDTaraZ.Respawn.Conn then xDTaraZ.Respawn.Conn:Disconnect() end
    xDTaraZ.Respawn.Conn = char:GetAttributeChangedSignal("EntityState"):Connect(function()
        xDTaraZ.Heal.Stats, xDTaraZ.Slide.Skill, xDTaraZ.Combat.Input = nil, nil, nil
        xDTaraZ.Respawn.Step()
    end)
end

xDTaraZ.Heal = { Stats = nil, LastScan = 0, LastHeal = 0, Healed = 0 }

---@return table?  the game's live stat table for you (curHp, maxHp)
function xDTaraZ.Heal.Player()
    local heal = xDTaraZ.Heal
    if heal.Stats and type(rawget(heal.Stats, "curHp")) == "number" then return heal.Stats end
    if not xDTaraZ.Caps.Gc or osClock() - heal.LastScan < xDTaraZ.Config.StatScanGap then return nil end
    heal.LastScan = osClock()
    for _, entry in ipairs(Util.GetGc(true)) do
        if type(entry) == "table" and type(rawget(entry, "curHp")) == "number" and rawget(entry, "maxSp") ~= nil then
            heal.Stats = entry
            return entry
        end
    end
    return nil
end

---@return number?, number?
function xDTaraZ.Heal.Health()
    local stats = xDTaraZ.Heal.Player()
    if not stats then return nil end
    return stats.curHp, stats.maxHp
end

---@return table  configId -> hp restored
function xDTaraZ.Heal.Values()
    local cached = xDTaraZ.Heal.Cache
    if cached then return cached end
    local medicine = GameLib.Configs.MedicineConfig
    local values = {}
    for id, entry in pairs(type(medicine) == "table" and type(medicine.datamap) == "table" and medicine.datamap or {}) do
        if type(entry) == "table" and type(entry.value) == "number" then values[id] = entry.value end
    end
    xDTaraZ.Heal.Cache = values
    return values
end

---@return string[]  names of every med the game has
function xDTaraZ.Heal.Names()
    local names = {}
    for id in pairs(xDTaraZ.Heal.Values()) do
        if xDTaraZ.Loot.ItemConfig(id) then names[#names + 1] = xDTaraZ.ItemNames[id] end
    end
    table.sort(names)
    return names
end

---@param missing number  hp to fill
---@param urgent boolean  take the biggest one
---@return table?  { bagUid, itemUid, name }
function xDTaraZ.Heal.PickMed(missing, urgent)
    local manager = xDTaraZ.Loot.Manager()
    local bags = manager and manager.BagController.bagMap
    if type(bags) ~= "table" then return nil end
    local values, tried, allowed = xDTaraZ.Heal.Values(), xDTaraZ.State.Tried, xDTaraZ.Options.HealMeds
    local best, bestScore
    for bagUid, bag in pairs(bags) do
        for itemUid, item in pairs(type(bag.itemMap) == "table" and bag.itemMap or {}) do
            local heal = values[item.configId]
            if not heal or not allowed[xDTaraZ.ItemNames[item.configId]] or (tried[itemUid] and osClock() - tried[itemUid] < xDTaraZ.Config.LootRetry) then continue end
            local score = urgent and -heal or math.abs(missing - heal)
            if not bestScore or score < bestScore then best, bestScore = { bagUid, itemUid, item.configId }, score end
        end
    end
    if best then best[3] = xDTaraZ.ItemNames[best[3]] end
    return best
end

---@return boolean  a med was taken
function xDTaraZ.Heal.Now()
    local hp, maxHp = xDTaraZ.Heal.Health()
    if not (hp and maxHp and hp < maxHp and xDTaraZ.Player.InBattle()) then return false end
    local urgent = hp / maxHp * 100 <= xDTaraZ.Config.HealUrgent
    local med = xDTaraZ.Heal.PickMed(maxHp - hp, urgent)
    if not (med and xDTaraZ.Loot.Pick(med[1], med[2], med[3])) then return false end
    xDTaraZ.Heal.LastHeal = osClock()
    xDTaraZ.Heal.Healed += 1
    return true
end

function xDTaraZ.Heal.Step()
    if not xDTaraZ.Options.AutoHeal then return end
    if osClock() - xDTaraZ.Heal.LastHeal < xDTaraZ.Config.HealGap then return end
    local hp, maxHp = xDTaraZ.Heal.Health()
    if not (hp and maxHp) or hp / maxHp * 100 > xDTaraZ.Options.HealAt then return end
    xDTaraZ.Heal.Now()
end

function xDTaraZ.Heal.GetStatus()
    local hp, maxHp = xDTaraZ.Heal.Health()
    if not hp then return "HP unknown" end
    return string.format("HP %d/%d | Meds used %d", math.floor(hp), math.floor(maxHp), xDTaraZ.Heal.Healed)
end

xDTaraZ.Hunt = { LastSeen = 0, Jumps = 0, PausedUntil = 0, Desyncs = 0 }

---@return Model?  closest living enemy anywhere on the map
function xDTaraZ.Hunt.Nearest()
    local hrp = xDTaraZ.Player.Root()
    if not hrp then return nil end
    local best, bestDist
    for _, model in ipairs(xDTaraZ.Target.Candidates()) do
        local root = xDTaraZ.Target.IsEnemy(model) and model:FindFirstChild("HumanoidRootPart")
        if not root then continue end
        local dist = (root.Position - hrp.Position).Magnitude
        if not bestDist or dist < bestDist then best, bestDist = model, dist end
    end
    return best
end

function xDTaraZ.Hunt.Step()
    if not (xDTaraZ.Options.Hunt and xDTaraZ.Player.InBattle()) then return end
    if xDTaraZ.State.Target then
        xDTaraZ.Hunt.LastSeen = osClock()
        return
    end
    local opts, hunt = xDTaraZ.Options, xDTaraZ.Hunt
    if osClock() - hunt.LastSeen < opts.HuntIdle or osClock() < hunt.PausedUntil then return end
    local enemy, hrp = xDTaraZ.Hunt.Nearest(), xDTaraZ.Player.Root()
    if not (enemy and hrp) then return end
    local root = enemy.HumanoidRootPart
    local facing = root.CFrame.LookVector * vector3New(1, 0, 1)
    facing = facing.Magnitude > 0.1 and facing.Unit or vector3New(1, 0, 0)
    local offset = (opts.HuntMode == "Front" and facing or opts.HuntMode == "Above" and Vector3.zero or -facing) * opts.HuntDistance
    local goal = root.Position + offset + vector3New(0, opts.HuntHeight, 0)
    local delta = goal - hrp.Position
    local partial = opts.HuntMaxWarp > 0 and delta.Magnitude > opts.HuntMaxWarp
    if partial then goal = hrp.Position + delta.Unit * opts.HuntMaxWarp end
    hrp.AssemblyLinearVelocity = Vector3.zero
    hrp.CFrame = CFrame.lookAt(goal, root.Position)
    if not partial then hunt.LastSeen = osClock() end
    hunt.Jumps += 1
end

---@param text string  server notice; a movement desync means it pulled us back, so stop warping for a moment
function xDTaraZ.Hunt.OnNotice(text)
    if type(text) ~= "string" or not text:find("out of sync", 1, true) then return end
    xDTaraZ.Hunt.PausedUntil = osClock() + xDTaraZ.Config.HuntSyncPause
    xDTaraZ.Hunt.Desyncs += 1
end

xDTaraZ.Farm = { Bag = nil, Start = nil, Totals = {}, LobbySince = nil }

---@return table?  your persistent currency bag (gold, ore, crystals)
function xDTaraZ.Farm.CurrencyBag()
    local farm = xDTaraZ.Farm
    if farm.Bag and type(rawget(farm.Bag, "itemMap")) == "table" then return farm.Bag end
    if not xDTaraZ.Caps.Gc then return nil end
    for _, entry in ipairs(Util.GetGc(true)) do
        if type(entry) == "table" and rawget(entry, "bagType") == xDTaraZ.Config.CurrencyType and type(rawget(entry, "itemMap")) == "table" and rawget(entry, "controller") then
            farm.Bag = entry
            return entry
        end
    end
    return nil
end

function xDTaraZ.Farm.Sample()
    local bag = xDTaraZ.Farm.CurrencyBag()
    if not bag then return end
    local totals = {}
    for _, item in pairs(bag.itemMap) do totals[xDTaraZ.ItemNames[item.configId]] = item.num end
    xDTaraZ.Farm.Totals = totals
    if not xDTaraZ.Farm.Start then xDTaraZ.Farm.Start = { osClock(), table.clone(totals), xDTaraZ.State.Kills } end
end

---@return string  gains per hour since the script started
function xDTaraZ.Farm.GetStatus()
    local start = xDTaraZ.Farm.Start
    if not start then return "-" end
    local hours = math.max(osClock() - start[1], 60) / 3600
    local seen, names, parts = {}, {}, {}
    for _, totals in ipairs({ xDTaraZ.Farm.Totals, start[2] }) do
        for name in pairs(totals) do
            if not seen[name] then seen[name] = true table.insert(names, name) end
        end
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local gained = (xDTaraZ.Farm.Totals[name] or 0) - (start[2][name] or 0)
        parts[#parts + 1] = string.format("%s +%d (%d/h)", name, gained, math.floor(gained / hours))
    end
    local kills = xDTaraZ.State.Kills - start[3]
    parts[#parts + 1] = string.format("Kills %d (%d/h)", kills, math.floor(kills / hours))
    return table.concat(parts, " | ")
end

xDTaraZ.Rewards = { Owner = nil, Services = {}, Pending = {}, Claimed = 0, Last = "-" }

---@return table?  the game's player object (Task, Season, Online, SignIn, Bag ...)
function xDTaraZ.Rewards.Data()
    local rewards = xDTaraZ.Rewards
    local cached = rewards.Owner
    if cached and type(rawget(cached, "Task")) == "table" then return cached end
    if not xDTaraZ.Caps.Gc then return nil end
    for _, entry in ipairs(Util.GetGc(true)) do
        local tasks = type(entry) == "table" and rawget(entry, "Task")
        if type(tasks) == "table" and rawget(tasks, "player") == entry and type(rawget(entry, "Season")) == "table" then
            rewards.Owner = entry
            return entry
        end
    end
    return nil
end

---@return table?  the game service table that owns this method
function xDTaraZ.Rewards.Service(method)
    local services = xDTaraZ.Rewards.Services
    if services[method] then return services[method] end
    if not xDTaraZ.Caps.Gc then return nil end
    for _, entry in ipairs(Util.GetGc(true)) do
        if type(entry) == "table" and type(rawget(entry, method)) == "function" then
            services[method] = entry
            return entry
        end
    end
    return nil
end

---@return number  how many of this item you own
function xDTaraZ.Rewards.Count(itemId)
    local data = xDTaraZ.Rewards.Data()
    local ok, count = pcall(function() return data:GetItemNum(itemId) end)
    return ok and tonumber(count) or 0
end

---@return number  claims sent
function xDTaraZ.Rewards.Tasks(data)
    local tasks, sent = data.Task, 0
    local done = GameLib.TaskState.done
    local ok, newbie = pcall(tasks.GetCanRewardTaskId, tasks)
    if ok and type(newbie) == "table" and #newbie > 0 and xDTaraZ.Net.Send("Task_ReceiveNewbieTaskReq", newbie) then sent += 1 end

    for _, kind in pairs(type(tasks.taskList) == "table" and tasks.taskList or {}) do
        for taskId, info in pairs(kind) do
            if type(info) ~= "table" or info.state ~= done then continue end
            if xDTaraZ.Net.Send("Task_ReceiveTaskAwardReq", { taskId = taskId }) then sent += 1 end
        end
    end
    pcall(tasks.ReceiveWeekReward, tasks)
    return sent
end

function xDTaraZ.Rewards.Season(data)
    local season, sent = data.Season, 0
    local done = GameLib.TaskState.done
    local list = type(season.seasonTask) == "table" and season.seasonTask.taskList
    for _, kind in pairs(type(list) == "table" and list or {}) do
        for taskId, info in pairs(kind) do
            if type(info) == "table" and info.state == done and xDTaraZ.Net.Send("Season_ReceiveTask", taskId) then sent += 1 end
        end
    end

    local ok, can = pcall(season.GetCanReceivePassAward, season)
    if ok and can and xDTaraZ.Net.Send("Season_RequireReceiveAllAward", {}) then sent += 1 end

    local rank = xDTaraZ.Rewards.Service("ReceiveRankAward")
    local okLv, rankLv = pcall(season.GetRankLv, season)
    for lv = 1, okLv and tonumber(rankLv) or 0 do
        local open, state = pcall(season.CanReceiveRankLv, season, lv)
        if not (open and state and rank) then continue end
        if pcall(rank.ReceiveRankAward, rank, lv) then sent += 1 end
    end
    return sent
end

function xDTaraZ.Rewards.Daily(data, kinds)
    local sent, now = 0, Workspace:GetServerTimeNow()
    local online = data.Online
    local gifts = kinds["Online gifts"] and type(online.receiveStateList) == "table" and online.receiveStateList or {}
    for index, gift in ipairs(gifts) do
        if gift.receiveState or (gift.timeStamp or math.huge) > now then continue end
        if xDTaraZ.Net.Send("Online_ReceiveGiftReq", { receiveIdx = index }) then sent += 1 end
    end

    local sign = data.SignIn
    local okDay, day = pcall(sign.GetSignDay, sign)
    local info = type(sign.sign_day_info) == "table" and sign.sign_day_info
    if kinds["Sign-in"] and okDay and tonumber(day) and info and not info[day] and xDTaraZ.Net.Send("Sign_RequireSigned", { signDay = day }) then sent += 1 end

    local update = data.GameUpdate
    local okAward, award = pcall(update.GetUpdateVerAward, update)
    if kinds["Update gift"] and okAward and award and pcall(update.ReqReceiveCurVerAward, update) then sent += 1 end
    return sent
end

---@return number  claims sent in this pass
function xDTaraZ.Rewards.ClaimAll()
    local data = xDTaraZ.Rewards.Data()
    if not data then return 0 end
    local sent, kinds = 0, xDTaraZ.Options.ClaimKinds
    local steps = {
        { kinds.Tasks, xDTaraZ.Rewards.Tasks },
        { kinds.Season, xDTaraZ.Rewards.Season },
        { kinds["Online gifts"] or kinds["Sign-in"] or kinds["Update gift"], xDTaraZ.Rewards.Daily },
    }
    for _, entry in ipairs(steps) do
        if not entry[1] then continue end
        local ok, got = pcall(entry[2], data, kinds)
        if ok then sent += got else warn("[AirDropArena] claim:", got) end
    end
    xDTaraZ.Rewards.Claimed += sent
    if sent > 0 then xDTaraZ.Rewards.Last = os.date("%H:%M") .. " +" .. sent end
    return sent
end

---@return number, number  codes that paid out, gold gained
function xDTaraZ.Rewards.RedeemCodes()
    local codes = GameLib.Configs.CodeConfig
    local ok, keys = pcall(function() return codes:GetListKey() end)
    if not (ok and type(keys) == "table") then return 0, 0 end
    local paid, gold = 0, 0
    for _, code in ipairs(keys) do
        local before = xDTaraZ.Rewards.Count(xDTaraZ.Config.GoldId)
        if not xDTaraZ.Net.Send("PlayerChat_C2SCode", code) then break end
        task.wait(xDTaraZ.Config.CodeGap)
        local gained = xDTaraZ.Rewards.Count(xDTaraZ.Config.GoldId) - before
        if gained > 0 then paid, gold = paid + 1, gold + gained end
    end
    return paid, gold
end

---@return table[]  { id, name, price } for every box the shop sells for gold
function xDTaraZ.Rewards.Boxes()
    if xDTaraZ.Rewards.BoxList then return xDTaraZ.Rewards.BoxList end
    local shop, list = GameLib.Configs.ShopConfig, {}
    for id = xDTaraZ.Config.BoxIds[1], xDTaraZ.Config.BoxIds[2] do
        local ok, cfg = pcall(function() return shop:GetSkinLotteryConfigById(id) end)
        if ok and type(cfg) == "table" then list[#list + 1] = { id, xDTaraZ.ItemNames[id], tonumber(cfg.coinVal) or 0 } end
    end
    xDTaraZ.Rewards.BoxList = list
    return list
end

---@return number  boxes opened
function xDTaraZ.Rewards.OpenBoxes()
    local opened = 0
    local allowed = xDTaraZ.Options.OpenBoxList
    for _, box in ipairs(xDTaraZ.Rewards.Boxes()) do
        if not allowed[box[2]] then continue end
        local owned = xDTaraZ.Rewards.Count(box[1])
        for _ = 1, math.min(owned, xDTaraZ.Config.OpenBatch) do
            if not xDTaraZ.Net.Send("Bag_C2SOpenSkinBoxReq", { id = box[1], num = 1 }) then return opened end
            opened += 1
            task.wait(xDTaraZ.Config.OpenGap)
        end
    end
    return opened
end

---@return number  boxes bought, stops at the gold you keep
function xDTaraZ.Rewards.BuyBoxes()
    local opts, bought = xDTaraZ.Options, 0
    local box
    for _, entry in ipairs(xDTaraZ.Rewards.Boxes()) do
        if entry[2] == opts.BuyBox and entry[3] > 0 then box = entry end
    end
    if not box then return 0 end
    local spare = xDTaraZ.Rewards.Count(xDTaraZ.Config.GoldId) - opts.KeepGold
    local amount = math.min(opts.BuyAmount, math.floor(spare / box[3]))
    for _ = 1, amount do
        if not xDTaraZ.Net.Send("Bag_C2SBuySkinBoxReq", { id = box[1], num = 1 }) then break end
        bought += 1
        task.wait(xDTaraZ.Config.OpenGap)
    end
    return bought
end

---@param action string  "Claim", "Codes", "Open", "Buy"
function xDTaraZ.Rewards.Request(action)
    xDTaraZ.Rewards.Pending[action] = true
end

function xDTaraZ.Rewards.Step()
    local rewards, opts = xDTaraZ.Rewards, xDTaraZ.Options
    local pending = rewards.Pending
    local now = osClock()
    if pending.Claim or (opts.AutoClaim and now - (rewards.LastClaim or 0) > xDTaraZ.Config.ClaimGap) then
        pending.Claim, rewards.LastClaim = nil, now
        xDTaraZ.UI.Queue("Rewards", ("Claimed %d rewards"):format(rewards.ClaimAll()))
    end
    if pending.Codes then
        pending.Codes = nil
        local paid, gold = rewards.RedeemCodes()
        xDTaraZ.UI.Queue("Codes", paid > 0 and ("%d codes worked, +%d gold"):format(paid, gold) or "No code paid out (all used or expired)")
    end
    if pending.Open or opts.AutoOpenBoxes then
        local manual = pending.Open
        pending.Open = nil
        local opened = rewards.OpenBoxes()
        if manual or opened > 0 then xDTaraZ.UI.Queue("Boxes", ("Opened %d boxes"):format(opened)) end
    end
    if pending.Buy then
        pending.Buy = nil
        xDTaraZ.UI.Queue("Boxes", ("Bought %d boxes"):format(rewards.BuyBoxes()))
    end
end

function xDTaraZ.Rewards.GetStatus()
    return ("Sent %d | Last %s"):format(xDTaraZ.Rewards.Claimed, xDTaraZ.Rewards.Last)
end

xDTaraZ.Admin = { Seen = {} }

---@return string?  name of a staff member in this server
function xDTaraZ.Admin.Find()
    local list = GameLib.AdminIds
    if type(list) ~= "table" then return nil end
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and list[player.UserId] then return player.Name end
    end
    return nil
end

function xDTaraZ.Admin.Step()
    local opts = xDTaraZ.Options
    if not (opts.AdminAlert or opts.AdminHop) then return end
    local name = xDTaraZ.Admin.Find()
    if not name then return end
    if not xDTaraZ.Admin.Seen[name] then
        xDTaraZ.Admin.Seen[name] = true
        xDTaraZ.UI.Queue("Nova Hub", "Staff in server: " .. name)
    end
    if opts.AdminHop then xDTaraZ.World.Hop() end
end

xDTaraZ.Damage = { Hits = {}, Last = {}, Samples = {} }

---@return number  confirmed hits it takes to kill, learned from your own kills
function xDTaraZ.Damage.HitsToKill()
    local samples = xDTaraZ.Damage.Samples
    if #samples == 0 then
        local char = LocalPlayer.Character
        local worn = char and char:GetAttribute("EPos_1")
        local id = type(worn) == "string" and tonumber(worn:match("^I_(%d+)"))
        local gun = id and xDTaraZ.Loot.Gun(id)
        return gun and math.max(1, math.ceil(xDTaraZ.Config.BaseHp / gun[1])) or 5
    end
    local total = 0
    for _, n in ipairs(samples) do total += n end
    return total / #samples
end

function xDTaraZ.Damage.OnHit(entityId)
    local damage = xDTaraZ.Damage
    damage.Hits[entityId] = (damage.Hits[entityId] or 0) + 1
    damage.Last[entityId] = osClock()
end

function xDTaraZ.Damage.OnDeath(entityId, mine)
    local damage = xDTaraZ.Damage
    local hits = damage.Hits[entityId]
    damage.Hits[entityId], damage.Last[entityId] = nil, nil
    if not (mine and hits and hits > 0) then return end
    table.insert(damage.Samples, hits)
    if #damage.Samples > xDTaraZ.Config.KillSamples then table.remove(damage.Samples, 1) end
end

---@return number  0..1 health left, estimated from your confirmed hits (the server never sends enemy health)
function xDTaraZ.Damage.Fraction(entityId)
    local damage = xDTaraZ.Damage
    local hits = entityId and damage.Hits[entityId]
    if not hits then return 1 end
    if osClock() - damage.Last[entityId] > xDTaraZ.Config.HitForget then
        damage.Hits[entityId], damage.Last[entityId] = nil, nil
        return 1
    end
    return math.clamp(1 - hits / xDTaraZ.Damage.HitsToKill(), 0.05, 1)
end

xDTaraZ.Esp = { Count = 0 }

---@return table[]  targets in the shape Library.Visuals expects
function xDTaraZ.Esp.Targets()
    local list = {}
    for _, model in ipairs(xDTaraZ.Target.Candidates(true)) do
        local hum = model:FindFirstChildOfClass("Humanoid")
        if not hum or hum.Health <= 0 then continue end
        list[#list + 1] = {
            Model = model,
            Name = xDTaraZ.Target.Label(model),
            Health = math.floor(xDTaraZ.Damage.Fraction(model:GetAttribute("EntityId")) * xDTaraZ.Config.BaseHp),
            MaxHealth = xDTaraZ.Config.BaseHp,
            Friendly = xDTaraZ.Target.SameTeam(model),
            Root = model:FindFirstChild("HumanoidRootPart"),
        }
    end
    xDTaraZ.Esp.Count = #list
    return list
end

function xDTaraZ.Esp.GetStatus()
    local visuals = xDTaraZ.Library and xDTaraZ.Library.Visuals
    if not (visuals and visuals:Get("Enabled")) then return "Off" end
    return xDTaraZ.Esp.Count .. " targets"
end

xDTaraZ.Faults = { Streaks = {} }

function xDTaraZ.Faults.Clear(name)
    xDTaraZ.Faults.Streaks[name] = nil
end

function xDTaraZ.Faults.Wanted(toggles)
    for _, key in ipairs(toggles) do
        if xDTaraZ.Options[key] then return true end
    end
    return false
end

---@param restore function?  the feature's own off path, run once
function xDTaraZ.Faults.Stop(name, err, toggles, restore)
    warn("[AirDropArena] " .. name .. " stopped:", err)
    for _, key in ipairs(toggles) do xDTaraZ.Options[key] = false end
    if restore then Util.Try(name .. " restore", restore) end
    table.insert(xDTaraZ.State.Halted, { name, tostring(err):match("^[^\n]*"), toggles })
end

---@param toggles string[]   switched off once the feature keeps failing; empty = never stops, warns once per streak
---@param restore function?  run once when the feature stops
---@return boolean           true while the feature is stopped
function xDTaraZ.Faults.Report(name, err, toggles, restore)
    local now = osClock()
    local streak = xDTaraZ.Faults.Streaks[name]
    if not streak or (streak.Halted and xDTaraZ.Faults.Wanted(toggles)) then
        streak = { Count = 0, First = now, Warned = false, Halted = false }
        xDTaraZ.Faults.Streaks[name] = streak
    end
    streak.Count += 1
    if streak.Warned then return streak.Halted end
    if streak.Count < xDTaraZ.Config.MaxFails or now - streak.First < xDTaraZ.Config.FailWindow then return false end

    streak.Warned = true
    if #toggles == 0 then
        warn("[AirDropArena] " .. name .. " keeps failing:", err)
        return false
    end
    streak.Halted = true
    xDTaraZ.Faults.Stop(name, err, toggles, restore)
    return true
end

xDTaraZ.Scheduler = { Jobs = {}, Booted = false }

---@param toggles string[]?  options that keep the job alive; turned off if it keeps failing
---@param restore function?  the job's off path, run once if it gets stopped
function xDTaraZ.Scheduler.Every(name, interval, fn, toggles, restore)
    xDTaraZ.Scheduler.Jobs[name] = { Interval = interval, Fn = fn, Last = 0, Running = false, Toggles = toggles or {}, Restore = restore }
end

function xDTaraZ.Scheduler.Settle(name, job)
    local err = job.Error
    job.Error = nil
    if err == false then
        xDTaraZ.Faults.Clear(name)
        return
    end
    job.Halted = xDTaraZ.Faults.Report(name, err, job.Toggles, job.Restore)
end

function xDTaraZ.Scheduler.Step()
    local now = osClock()
    for name, job in pairs(xDTaraZ.Scheduler.Jobs) do
        if job.Running then continue end
        if job.Error ~= nil then xDTaraZ.Scheduler.Settle(name, job) end
        if job.Halted then
            if not xDTaraZ.Faults.Wanted(job.Toggles) then continue end
            job.Halted = false
            xDTaraZ.Faults.Clear(name)
        end
        if now - job.Last < job.Interval then continue end

        job.Last, job.Running = now, true
        task.spawn(function()
            local ok, err = pcall(job.Fn)
            job.Error = not ok and tostring(err) or false
            job.Running = false
        end)
    end
end

function xDTaraZ.Scheduler.Boot()
    if xDTaraZ.Scheduler.Booted then return end
    xDTaraZ.Scheduler.Booted = true
    xDTaraZ:Connect(RunService.Heartbeat, xDTaraZ.Scheduler.Step)
end

xDTaraZ.UI = { Labels = {} }
local Library, T

function xDTaraZ.UI.Detach(fn)
    return function(...)
        local packed = table.pack(...)
        task.defer(function()
            local ok, err = pcall(fn, table.unpack(packed, 1, packed.n))
            if not ok then warn("[AirDropArena] ui:", err) end
        end)
    end
end

function xDTaraZ.UI.Bind(widget, key)
    local function Apply(value) xDTaraZ.Options[key] = value end
    Apply(widget.Value)
    widget:OnChanged(Apply)
end

---@param got number   items taken
---@param none string  shown when nothing was taken
function xDTaraZ.UI.Report(title, got, done, none)
    if got > 0 then
        Library:Notify(title, done:format(got), 4, "Success")
    else
        Library:Notify(title, none, 4, "Info")
    end
end

function xDTaraZ.UI.BuildMain(window)
    window:AddTabSection(T("Main", "หลัก"))
    local tab = window:AddTab(T("Main", "หลัก"), "mushroom", T("Status and links", "สถานะและลิงก์"))

    local status = tab:AddLeftGroupbox(T("Status", "สถานะ"), "star")
    xDTaraZ.UI.Labels.Farm = status:AddParagraph({ Title = T("Farm", "ฟาร์ม"), Content = "-" })
    xDTaraZ.UI.Labels.Heal = status:AddParagraph({ Title = T("Health", "เลือด"), Content = "-" })
    xDTaraZ.UI.Labels.Combat = status:AddParagraph({ Title = T("Combat", "การต่อสู้"), Content = "-" })
    xDTaraZ.UI.Labels.Rewards = status:AddParagraph({ Title = T("Rewards", "รางวัล"), Content = "-" })

    local discord = tab:AddRightGroupbox(T("Discord", "ดิสคอร์ด"), "link")
    discord:AddLabel(xDTaraZ.Config.Discord)
    discord:AddButton({ Text = T("Copy Discord Link", "คัดลอกลิงก์ดิสคอร์ด"), Func = xDTaraZ.UI.Detach(function()
        if Util.Copy(xDTaraZ.Config.Discord) then
            Library:Notify(T("Discord", "ดิสคอร์ด"), T("Link copied", "คัดลอกลิงก์แล้ว"), 3, "Success")
        else
            Library:Notify(T("Discord", "ดิสคอร์ด"), xDTaraZ.Config.Discord, 6, "Info")
        end
    end) })

    local logBox = tab:AddRightGroupbox(T("Update Log", "อัปเดตล่าสุด"), "bell")
    for i = 1, math.min(2, #xDTaraZ.Config.UpdateLog) do
        local entry = xDTaraZ.Config.UpdateLog[i]
        logBox:AddParagraph({ Title = entry[1], Content = entry[2] })
    end

    local live = tab:AddRightGroupbox(T("Loot and ESP", "ของดรอปและ ESP"), "coin")
    xDTaraZ.UI.Labels.Loot = live:AddParagraph({ Title = T("Loot", "ของดรอป"), Content = "-" })
    xDTaraZ.UI.Labels.Esp = live:AddParagraph({ Title = T("ESP", "ESP"), Content = "-" })
end

function xDTaraZ.UI.BuildCombat(window)
    window:AddTabSection(T("Combat", "การต่อสู้"))
    local tab = window:AddTab(T("Aim", "เล็ง"), "target", T("Silent aim, ragebot, aimbot, triggerbot", "ไซเลนต์เอม เรจบอท เล็งอัตโนมัติ ยิงอัตโนมัติ"))
    local priorities = { "Crosshair", "Distance", "Health" }

    local silent = tab:AddLeftGroupbox(T("Silent Aim", "ไซเลนต์เอม"), "bomb", "OP")
    silent:AddToggle("SilentAim", { Text = T("Silent aim", "ไซเลนต์เอม"), Description = T("Your shots hit the target in the FOV", "กระสุนวิ่งเข้าเป้าในวง FOV"), Risky = true })
        :AddKeyPicker("SilentAimKey", { Default = "None", Mode = "Toggle" })
    silent:AddSlider("SilentHitChance", { Text = T("Hit chance", "โอกาสโดน"), Min = 1, Max = 100, Default = 100, Rounding = 0, Suffix = "%" })
    silent:AddSlider("SilentHeadChance", { Text = T("Headshot chance", "โอกาสโดนหัว"), Min = 0, Max = 100, Default = 100, Rounding = 0, Suffix = "%" })
    silent:AddDropdown("SilentPriority", { Text = T("Target priority", "เลือกเป้าตาม"), Values = priorities, Default = "Crosshair" })
    silent:AddSlider("SilentFov", { Text = T("FOV", "ระยะมอง"), Min = 20, Max = 1000, Default = 250, Suffix = "px" })
    silent:AddToggle("ShowSilentFov", { Text = T("Show FOV circle", "แสดงวงระยะมอง") })
    silent:AddSlider("SilentMaxDistance", { Text = T("Max distance", "ระยะสูงสุด"), Min = 50, Max = 2000, Default = 1000, Suffix = "m" })
    Library.Compat.NeedCap("SilentAim", "Namecall")

    local rage = tab:AddLeftGroupbox(T("Ragebot", "เรจบอท"), "bomb")
    rage:AddToggle("Ragebot", { Text = T("Ragebot", "เรจบอท"), Description = T("Shoots every enemy in sight on its own", "ยิงศัตรูทุกตัวที่มองเห็นเอง"), Risky = true })
        :AddKeyPicker("RagebotKey", { Default = "None", Mode = "Toggle" })
    rage:AddSlider("RageMaxDistance", { Text = T("Max distance", "ระยะสูงสุด"), Min = 50, Max = 2000, Default = 1000, Suffix = "m" })
    Library.Compat.NeedCap("Ragebot", "Namecall")

    local aim = tab:AddRightGroupbox(T("Aimbot", "เล็งอัตโนมัติ"), "target")
    aim:AddToggle("Aimbot", { Text = T("Aimbot", "เล็งอัตโนมัติ"), Description = T("Locks your view onto the enemy in the FOV", "ล็อคกล้องไปที่ศัตรูในวง FOV"), Tooltip = T("Right-click or long-press the key to change Hold / Toggle / Always", "คลิกขวาหรือกดค้างที่ปุ่มคีย์เพื่อเปลี่ยน Hold / Toggle / Always") })
        :AddKeyPicker("AimbotKey", { Default = "X", Mode = "Hold" })
    aim:AddSlider("AimSmooth", { Text = T("Smoothness", "ความนุ่ม"), Min = 1, Max = 20, Default = 1, Rounding = 0 })
    aim:AddCheckbox("AimSticky", { Text = T("Sticky target", "ล็อคเป้าเดิม") })
    aim:AddDropdown("AimBone", { Text = T("Aim part", "จุดที่เล็ง"), Values = { "Head", "Torso" }, Default = "Head" })
    aim:AddDropdown("AimPriority", { Text = T("Target priority", "เลือกเป้าตาม"), Values = priorities, Default = "Crosshair" })
    aim:AddSlider("AimFov", { Text = T("FOV", "ระยะมอง"), Min = 20, Max = 800, Default = 200, Suffix = "px" })
    aim:AddToggle("ShowFov", { Text = T("Show FOV circle", "แสดงวงระยะมอง") })
    aim:AddSlider("AimMaxDistance", { Text = T("Max distance", "ระยะสูงสุด"), Min = 50, Max = 2000, Default = 1000, Suffix = "m" })

    local trigger = tab:AddRightGroupbox(T("Triggerbot", "ยิงอัตโนมัติ"), "crosshair")
    trigger:AddToggle("Triggerbot", { Text = T("Triggerbot", "ยิงอัตโนมัติ"), Description = T("Fires when your crosshair is on an enemy", "ยิงเองเมื่อเป้าเล็งอยู่บนศัตรู") })
        :AddKeyPicker("TriggerbotKey", { Default = "None", Mode = "Toggle" })
    trigger:AddSlider("TriggerDelay", { Text = T("Reaction delay", "หน่วงก่อนยิง"), Min = 0, Max = 500, Default = 0, Rounding = 0, Suffix = "ms" })
    trigger:AddSlider("TriggerChance", { Text = T("Fire chance", "โอกาสยิง"), Min = 1, Max = 100, Default = 100, Rounding = 0, Suffix = "%" })
    trigger:AddCheckbox("TargetBots", { Text = T("Include bots", "รวมบอท"), Default = true })

    xDTaraZ.UI.BuildSurvival(window)
end

function xDTaraZ.UI.BuildSurvival(window)
    local tab = window:AddTab(T("Survival", "เอาตัวรอด"), "heart", T("Hunt, healing, respawn and gun mods", "ล่าศัตรู ฮีล เกิดใหม่ และม็อดปืน"))

    local hunt = tab:AddLeftGroupbox(T("Hunt", "ล่าศัตรู"), "zap")
    hunt:AddToggle("Hunt", { Text = T("Hunt", "ล่าศัตรู"), Description = T("Warps to the closest enemy whenever nobody is in sight", "วาร์ปไปหาศัตรูที่ใกล้สุดเมื่อไม่เห็นใคร"), Risky = true })
    hunt:AddDropdown("HuntMode", { Text = T("Position", "ตำแหน่ง"), Values = { "Behind", "Above", "Front" }, Default = "Behind" })
    hunt:AddSlider("HuntDistance", { Text = T("Distance", "ระยะห่าง"), Min = 0, Max = 60, Default = 15, Rounding = 0, Suffix = "m" })
    hunt:AddSlider("HuntHeight", { Text = T("Height", "ความสูง"), Min = 0, Max = 40, Default = 10, Rounding = 0, Suffix = "m" })
    hunt:AddSlider("HuntMaxWarp", { Text = T("Max warp per jump", "วาร์ปไกลสุดต่อครั้ง"), Min = 0, Max = 400, Default = 0, Rounding = 0, Suffix = "m", Tooltip = T("0 = no limit", "0 = ไม่จำกัด") })
    hunt:AddSlider("HuntIdle", { Text = T("Wait before warp", "รอก่อนวาร์ป"), Min = 0, Max = 5, Default = 0.6, Rounding = 1, Suffix = "s" })

    local life = tab:AddLeftGroupbox(T("Respawn", "เกิดใหม่"), "heart")
    life:AddToggle("InstantRespawn", { Text = T("Auto respawn", "เกิดใหม่อัตโนมัติ"), Description = T("Respawns as soon as the game allows", "เกิดใหม่เองทันทีที่เกมอนุญาต") })
    life:AddSlider("RespawnDelay", { Text = T("Respawn delay", "หน่วงก่อนเกิด"), Min = 0, Max = 10, Default = 0, Rounding = 1, Suffix = "s" })
    life:AddToggle("AutoRejoin", { Text = T("Auto rejoin match", "เข้าแมตช์ใหม่อัตโนมัติ"), Description = T("Jumps back into a match when you sit in the lobby", "กลับเข้าแมตช์เองเมื่อค้างอยู่ในล็อบบี้") })
    life:AddButton({ Text = T("Respawn Now", "เกิดใหม่ตอนนี้"), Func = xDTaraZ.UI.Detach(function()
        xDTaraZ.State.LastRespawn = 0
        xDTaraZ.Respawn.Now()
    end) })

    local heal = tab:AddRightGroupbox(T("Auto Heal", "ฮีลอัตโนมัติ"), "heart")
    heal:AddToggle("AutoHeal", { Text = T("Auto heal", "ฮีลอัตโนมัติ"), Description = T("Grabs a med from anywhere on the map when you get hurt", "ดึงยาจากทุกที่ในแมพมาใช้เมื่อเลือดลด"), Risky = true })
    heal:AddSlider("HealAt", { Text = T("Heal below", "ฮีลเมื่อเลือดต่ำกว่า"), Min = 10, Max = 99, Default = 70, Rounding = 0, Suffix = "%" })
    local meds = xDTaraZ.Heal.Names()
    heal:AddDropdown("HealMeds", { Text = T("Meds to use", "ยาที่ใช้"), Values = meds, Default = meds, Multi = true, AllowNull = true })
    heal:AddButton({ Text = T("Heal Now", "ฮีลตอนนี้"), Style = "Success", Func = xDTaraZ.UI.Detach(function()
        if not xDTaraZ.Heal.Now() then Library:Notify("Heal", "No med on the map or HP is full", 3, "Info") end
    end) })

    local gun = tab:AddRightGroupbox(T("Gun Mods", "ม็อดปืน"), "swords")
    gun:AddToggle("SmartReload", { Text = T("Auto reload", "รีโหลดอัตโนมัติ"), Description = T("Tops up your magazine while nobody is in sight", "เติมแม็กตอนไม่มีศัตรูในสายตา") })
    gun:AddSlider("ReloadAt", { Text = T("Reload below", "รีโหลดเมื่อกระสุนต่ำกว่า"), Min = 10, Max = 95, Default = 50, Rounding = 0, Suffix = "%" })
    gun:AddToggle("NoSpread", { Text = T("No spread", "ยิงไม่กระจาย") })
    gun:AddToggle("NoRecoil", { Text = T("No recoil", "ไม่มีแรงถีบ") })
    gun:AddToggle("InstantAds", { Text = T("Instant aim down sights", "เล็งศูนย์ทันที") })
    for _, idx in ipairs(xDTaraZ.Config.GunToggles) do
        Library.Compat.NeedCap(idx, "Gc")
    end
end

function xDTaraZ.UI.BuildLoot(window)
    window:AddTabSection(T("Farming", "ฟาร์ม"))
    local tab = window:AddTab(T("Loot", "ของดรอป"), "coin", T("Gear, valuables and air drops from anywhere", "ของ ของมีค่า และแอร์ดรอปจากทุกที่"))

    local gear = tab:AddLeftGroupbox(T("Best Gear", "ของดีที่สุด"), "star")
    gear:AddToggle("AutoGear", { Text = T("Auto loot best gear", "เก็บของดีสุดอัตโนมัติ"), Description = T("Grabs better guns and armor from any crate on the map", "ดึงปืนและเกราะที่ดีกว่าจากกล่องทุกใบในแมพ"), Risky = true })
    local gearLabels = xDTaraZ.Loot.SlotLabels()
    gear:AddDropdown("LootGear", { Text = T("Gear types", "ประเภทของ"), Values = gearLabels, Default = gearLabels, Multi = true, AllowNull = true })
    gear:AddToggle("AutoAmmo", { Text = T("Auto ammo", "กระสุนอัตโนมัติ"), Description = T("Takes ammo for your guns from anywhere on the map", "ดึงกระสุนที่ตรงกับปืนจากทุกที่ในแมพ"), Risky = true })
    gear:AddDropdown("GearScore", { Text = T("Rank guns by", "จัดอันดับปืนตาม"), Values = { "Damage per second", "Damage per shot", "Rarity" }, Default = "Damage per second" })
    gear:AddButton({ Text = T("Loot Best Now", "เก็บของดีสุดตอนนี้"), Style = "Primary", Func = xDTaraZ.UI.Detach(function()
        xDTaraZ.UI.Report("Loot", xDTaraZ.Loot.TakeUpgrades(), "Took %d upgrades", "Nothing better on the map")
    end) })

    local money = tab:AddRightGroupbox(T("Valuables", "ของมีค่า"), "coin")
    money:AddToggle("AutoValuables", { Text = T("Auto loot valuables", "เก็บของมีค่าอัตโนมัติ"), Description = T("Takes ore, crystals and gold from every crate on the map", "เก็บแร่ คริสตัล และทองจากกล่องทุกใบในแมพ"), Risky = true })
    local currencies, buffs = xDTaraZ.Loot.Kinds()
    money:AddDropdown("LootCurrency", { Text = T("Valuables to take", "ของมีค่าที่เก็บ"), Values = currencies, Default = currencies, Multi = true, AllowNull = true, Searchable = true })
    money:AddToggle("AutoBuffs", { Text = T("Auto loot buffs", "เก็บบัฟอัตโนมัติ"), Description = T("Takes damage, fire rate, ammo and health buffs from every crate", "เก็บบัฟดาเมจ ยิงเร็ว กระสุน และเลือดจากกล่องทุกใบ"), Risky = true })
    money:AddDropdown("LootBuffs", { Text = T("Buffs to take", "บัฟที่เก็บ"), Values = buffs, Default = buffs, Multi = true, AllowNull = true })
    money:AddButton({ Text = T("Loot Valuables Now", "เก็บของมีค่าตอนนี้"), Style = "Primary", Func = xDTaraZ.UI.Detach(function()
        xDTaraZ.UI.Report("Loot", xDTaraZ.Loot.TakeValuables({ Currency = true, Buff = true }), "Took %d items", "No valuables on the map")
    end) })

    local drop = tab:AddRightGroupbox(T("Air Drop", "แอร์ดรอป"), "flag")
    drop:AddToggle("AutoAirDrop", { Text = T("Auto air drop", "แอร์ดรอปอัตโนมัติ"), Description = T("Takes air drop loot from anywhere on the map", "เก็บของในแอร์ดรอปได้จากทุกที่ในแมพ"), Risky = true })
    drop:AddButton({ Text = T("Loot Air Drops Now", "เก็บแอร์ดรอปตอนนี้"), Style = "Primary", Func = xDTaraZ.UI.Detach(function()
        xDTaraZ.UI.Report("Air Drop", xDTaraZ.Loot.EmptyAirDrops(), "Took %d items", "Nothing to take")
    end) })
end

function xDTaraZ.UI.BuildRewards(window)
    local tab = window:AddTab(T("Rewards", "รางวัล"), "qblock", T("Tasks, season pass, gifts, codes and boxes", "ภารกิจ ซีซั่นพาส ของขวัญ โค้ด และกล่อง"))

    local claim = tab:AddLeftGroupbox(T("Claim", "รับรางวัล"), "star")
    claim:AddToggle("AutoClaim", { Text = T("Auto claim", "รับรางวัลอัตโนมัติ"), Description = T("Tasks, season pass, rank rewards, online gifts, sign-in and update gifts", "ภารกิจ ซีซั่นพาส รางวัลแรงก์ ของขวัญออนไลน์ เช็คอิน และของขวัญอัปเดต") })
    local kinds = xDTaraZ.Config.ClaimKinds
    claim:AddDropdown("ClaimKinds", { Text = T("Rewards to claim", "รางวัลที่รับ"), Values = kinds, Default = kinds, Multi = true, AllowNull = true })
    claim:AddButton({ Text = T("Claim All Now", "รับทั้งหมดตอนนี้"), Style = "Success", Func = function() xDTaraZ.Rewards.Request("Claim") end })

    local codes = tab:AddLeftGroupbox(T("Codes", "โค้ด"), "key")
    codes:AddButton({ Text = T("Redeem All Codes", "ใช้โค้ดทั้งหมด"), Style = "Primary", Func = function() xDTaraZ.Rewards.Request("Codes") end })

    local boxes = tab:AddRightGroupbox(T("Boxes", "กล่อง"), "qblock")
    boxes:AddToggle("AutoOpenBoxes", { Text = T("Auto open boxes", "เปิดกล่องอัตโนมัติ"), Description = T("Opens every skin and weapon box you own", "เปิดกล่องสกินและกล่องปืนทุกใบที่มี") })
    local owned = {}
    for _, box in ipairs(xDTaraZ.Rewards.Boxes()) do
        if not table.find(owned, box[2]) then owned[#owned + 1] = box[2] end
    end
    boxes:AddDropdown("OpenBoxList", { Text = T("Boxes to open", "กล่องที่เปิด"), Values = owned, Default = owned, Multi = true, AllowNull = true, Searchable = true })
    boxes:AddButton({ Text = T("Open Boxes Now", "เปิดกล่องตอนนี้"), Func = function() xDTaraZ.Rewards.Request("Open") end })

    local shop = tab:AddRightGroupbox(T("Buy Boxes", "ซื้อกล่อง"), "coin")
    local names = {}
    for _, box in ipairs(xDTaraZ.Rewards.Boxes()) do
        if box[3] > 0 then names[#names + 1] = box[2] end
    end
    shop:AddDropdown("BuyBox", { Text = T("Box", "กล่อง"), Values = names, Default = names[1] })
    shop:AddSlider("BuyAmount", { Text = T("Amount", "จำนวน"), Min = 1, Max = xDTaraZ.Config.BuyAmountMax, Default = 1, Rounding = 0 })
    shop:AddSlider("KeepGold", { Text = T("Keep gold", "เก็บทองไว้"), Min = 0, Max = 1000000, Default = 50000, Rounding = 0 })
    shop:AddButton({ Text = T("Buy Now", "ซื้อตอนนี้"), Func = function() xDTaraZ.Rewards.Request("Buy") end })
end

function xDTaraZ.UI.BuildVisuals(window)
    window:AddTabSection(T("Visuals", "การมองเห็น"))
    window:AddVisualsTab({ Provider = xDTaraZ.Esp.Targets, Preview = true })

    local tab = window:AddTab(T("Loot ESP", "มองเห็นของ"), "eye", T("Air drops, crates and items", "แอร์ดรอป กล่อง และไอเทม"))
    local esp = tab:AddLeftGroupbox(T("Loot ESP", "มองเห็นของ"), "eye")
    esp:AddToggle("LootEspAirDrop", { Text = T("Air drops", "แอร์ดรอป") })
    esp:AddToggle("LootEspCrate", { Text = T("Crates", "กล่อง") })
    esp:AddToggle("LootEspItem", { Text = T("Items", "ไอเทม") })

    local range = tab:AddRightGroupbox(T("Range", "ระยะ"), "eye")
    range:AddSlider("LootEspRange", { Text = T("Range", "ระยะ"), Min = 50, Max = 2000, Default = 400, Suffix = "m" })
end

function xDTaraZ.UI.BuildMisc(window)
    window:AddTabSection(T("Misc", "อื่นๆ"))
    local tab = window:AddTab(T("Player", "ผู้เล่น"), "oneup", T("Movement, world, server", "การเคลื่อนที่ โลก เซิร์ฟเวอร์"))

    local move = tab:AddLeftGroupbox(T("Movement", "การเคลื่อนที่"), "zap")
    move:AddToggle("Speed", { Text = T("Speed", "วิ่งเร็ว") }):AddKeyPicker("SpeedKey", { Default = "None", Mode = "Toggle" })
    move:AddSlider("SpeedValue", { Text = T("Speed", "ความเร็ว"), Min = 16, Max = 120, Default = 40, Rounding = 0 })
    move:AddToggle("InfiniteJump", { Text = T("Infinite jump", "กระโดดไม่จำกัด") })
    move:AddToggle("Noclip", { Text = T("Noclip", "ทะลุกำแพง") }):AddKeyPicker("NoclipKey", { Default = "None", Mode = "Toggle" })

    local fly = tab:AddLeftGroupbox(T("Fly", "บิน"), "star")
    fly:AddToggle("Fly", { Text = T("Fly", "บิน"), Description = T("Space up, Ctrl down", "Space ขึ้น Ctrl ลง"), Callback = function(on)
        if not on then xDTaraZ.Movement.StopFly() end
    end }):AddKeyPicker("FlyKey", { Default = "None", Mode = "Toggle" })
    fly:AddSlider("FlySpeed", { Text = T("Fly speed", "ความเร็วบิน"), Min = 20, Max = 200, Default = 60, Rounding = 0 })

    local slide = tab:AddRightGroupbox(T("Slide", "สไลด์"), "zap")
    slide:AddToggle("SuperSlide", { Text = T("Slide boost", "สไลด์ไกล"), Description = T("Faster and longer slides", "สไลด์เร็วและไกลขึ้น") })
    slide:AddSlider("SlideSpeed", { Text = T("Slide speed", "ความเร็วสไลด์"), Min = 60, Max = 300, Default = 120, Rounding = 0 })
    Library.Compat.NeedCap("SuperSlide", "Gc")

    local world = tab:AddRightGroupbox(T("World", "โลก"), "globe")
    world:AddToggle("Fullbright", { Text = T("Fullbright", "สว่างทั้งแมพ") })
    world:AddToggle("CameraFov", { Text = T("Camera FOV", "มุมกล้อง") })
    world:AddSlider("CameraFovValue", { Text = T("FOV", "มุมกล้อง"), Min = 50, Max = 120, Default = 90, Rounding = 0 })

    local server = tab:AddRightGroupbox(T("Server", "เซิร์ฟเวอร์"), "castle")
    server:AddToggle("AntiAfk", { Text = T("Anti AFK", "กันหลุด AFK") })
    server:AddToggle("AdminAlert", { Text = T("Staff alert", "เตือนเมื่อมีทีมงาน"), Description = T("Tells you when a game staff member is in your server", "แจ้งเมื่อทีมงานเกมอยู่ในเซิร์ฟ") })
    server:AddToggle("AdminHop", { Text = T("Leave when staff joins", "ย้ายเซิร์ฟเมื่อทีมงานเข้า") })
    server:AddButton({ Text = T("Rejoin", "เข้าใหม่"), Func = xDTaraZ.UI.Detach(xDTaraZ.World.Rejoin) })
        :AddButton({ Text = T("Server hop", "ย้ายเซิร์ฟ"), Func = xDTaraZ.UI.Detach(function()
            if not xDTaraZ.World.Hop() then Library:Notify(T("Server", "เซิร์ฟเวอร์"), T("No other server found", "ไม่เจอเซิร์ฟอื่น"), 4, "Warning") end
        end) })
end

function xDTaraZ.UI.RefreshStatus()
    local labels, state = xDTaraZ.UI.Labels, xDTaraZ.State
    if labels.Combat then labels.Combat:SetContent(xDTaraZ.Combat.GetStatus()) end
    if labels.Loot then
        local wait = math.max(0, math.floor(state.AirDropAt - Workspace:GetServerTimeNow()))
        local eta = wait > 0 and ("next in %ds"):format(wait) or "-"
        labels.Loot:SetContent(string.format("Gear %d | Valuables %d | Air drop items %d (%s) | Last: %s", state.Looted, state.Valuables, state.AirDrops, eta, state.LastLoot))
    end
    if labels.Esp then labels.Esp:SetContent(xDTaraZ.Esp.GetStatus()) end
    if labels.Heal then labels.Heal:SetContent(xDTaraZ.Heal.GetStatus()) end
    if labels.Farm then labels.Farm:SetContent(xDTaraZ.Farm.GetStatus()) end
    if labels.Rewards then labels.Rewards:SetContent(xDTaraZ.Rewards.GetStatus()) end
end

---@param text string  shown by the UI pump; worker threads that touched game code can't drive the UI
function xDTaraZ.UI.Queue(title, text)
    table.insert(xDTaraZ.State.Notices, { title, text })
end

function xDTaraZ.UI.ShowNotices()
    local notices = xDTaraZ.State.Notices
    if #notices == 0 then return end
    local pending = table.clone(notices)
    table.clear(notices)
    for _, notice in ipairs(pending) do Library:Notify(notice[1], notice[2], 5, "Info") end
end

function xDTaraZ.UI.ShowHalted()
    local queue = xDTaraZ.State.Halted
    if #queue == 0 then return end
    local stopped = table.clone(queue)
    table.clear(queue)

    for _, halt in ipairs(stopped) do
        local name, reason, toggles = halt[1], halt[2], halt[3]
        for _, key in ipairs(toggles) do
            local toggle = Library.Options[key]
            if toggle and toggle.Value == true then Util.Try("halt " .. key, toggle.SetValue, toggle, false) end
        end
        Library:Notify("Nova Hub", name .. " stopped: " .. reason, 6, "Error")
    end
end

function xDTaraZ.UI.HookOnDemand()
    for _, idx in ipairs({ "SilentAim", "Ragebot" }) do
        local toggle = Library.Options[idx]
        if toggle then toggle:OnChanged(function() task.defer(xDTaraZ.Combat.SyncHook) end) end
    end
end

function xDTaraZ.UI.GuardConfigFeatures()
    local unsupported = T("Not available on this executor", "ใช้กับ executor นี้ไม่ได้")
    local outdated = T("Changed by a game update, wait for a script update", "เกมอัปเดตแล้ว รอสคริปต์อัปเดต")
    local missing = GameLib.Missing.ConfigManager
    for _, idx in ipairs(xDTaraZ.Config.ConfigFeatures) do
        if missing then
            Library.Compat.Block(idx, missing == "Absent" and outdated or unsupported)
        else
            Library.Compat.NeedCap(idx, "Gc")
        end
    end

    for _, idx in ipairs(xDTaraZ.Config.GcFeatures) do
        Library.Compat.NeedCap(idx, "Gc")
    end

    if GameLib.Main then return end
    for _, idx in ipairs(xDTaraZ.Config.RemoteFeatures) do
        local option = Library.Options[idx]
        if option and not option.Blocked then Library.Compat.Block(option, outdated) end
    end
end

function xDTaraZ.UI.Build()
    local window = Library.Window
    local sections = {
        { "main tab", xDTaraZ.UI.BuildMain },
        { "combat tab", xDTaraZ.UI.BuildCombat },
        { "loot tab", xDTaraZ.UI.BuildLoot },
        { "rewards tab", xDTaraZ.UI.BuildRewards },
        { "visuals tab", xDTaraZ.UI.BuildVisuals },
        { "misc tab", xDTaraZ.UI.BuildMisc },
    }
    for _, section in ipairs(sections) do
        Util.Try(section[1], section[2], window)
    end
    Util.Try("settings tab", window.AddSettingsTab, window)

    for key in pairs(xDTaraZ.Options) do
        local widget = Library.Options[key]
        if widget then Util.Try("bind " .. key, xDTaraZ.UI.Bind, widget, key) end
    end
    Util.Try("hooks", xDTaraZ.UI.HookOnDemand)
    Util.Try("feature guards", xDTaraZ.UI.GuardConfigFeatures)

    Library:Every(xDTaraZ.Config.StatusInterval, xDTaraZ.UI.RefreshStatus)
    Library:Every(xDTaraZ.Config.StatusInterval, xDTaraZ.UI.ShowHalted)
    Library:Every(xDTaraZ.Config.StatusInterval, xDTaraZ.UI.ShowNotices)
end

---@return boolean  false when the menu could not be shown
local function BuildInterface()
    Library = Util.LoadLibrary(xDTaraZ.Config.UiSource)
    if not Library then return false end
    pcall(NovaBanner.Step, "UI library")
    xDTaraZ.Library = Library
    T = function(en, th) return Library:T(en, th) end

    local opened, err = pcall(Library.CreateWindow, Library, {
        Title = "Nova Hub",
        SubTitle = "FPS AirDrop Arena by xDTaraZ",
        MenuKey = Enum.KeyCode.LeftControl,
        ConfigFolder = xDTaraZ.Config.SaveFolder,
        Language = "Auto",
        Theme = "Nova",
        Intro = xDTaraZ.Config.Intro,
        OnUnlocked = function()
            xDTaraZ.UI.Build()
            task.defer(Util.Try, "boot", xDTaraZ.Boot)
            task.defer(Util.Try, "autoload config", Library.LoadAutoloadConfig, Library)
        end,
    })
    if not opened then
        Util.Alert("The menu failed to load on this executor: " .. tostring(err):match("^[^\n]*"), err)
        return false
    end
    Library:OnUnload(function()
        xDTaraZ:Unload()
    end)
    return true
end

function xDTaraZ.Boot()
    Util.Try("combat", xDTaraZ.Combat.Start)
    Util.Try("movement", xDTaraZ.Movement.Start)
    xDTaraZ:Connect(LocalPlayer.Idled, xDTaraZ.World.OnIdled)
    xDTaraZ:Connect(RunService.RenderStepped, xDTaraZ.World.OnRender)
    if LocalPlayer.Character then xDTaraZ.Respawn.Watch(LocalPlayer.Character) end
    xDTaraZ:Connect(LocalPlayer.CharacterAdded, xDTaraZ.Respawn.Watch)

    local config = xDTaraZ.Config
    xDTaraZ.Scheduler.Every("Gun Mods", 0.5, xDTaraZ.Guns.Step, config.GunToggles, xDTaraZ.Guns.Restore)
    xDTaraZ.Scheduler.Every("Auto Air Drop", 1, xDTaraZ.Loot.AirDropStep, { "AutoAirDrop" })
    xDTaraZ.Scheduler.Every("Loot ESP", 0.5, xDTaraZ.Loot.EspStep, config.LootEspToggles, xDTaraZ.Loot.ClearMarks)
    xDTaraZ.Scheduler.Every("Fullbright", 0.5, xDTaraZ.World.Step, { "Fullbright" }, xDTaraZ.World.Step)
    xDTaraZ.Scheduler.Every("Auto Respawn", 0.5, xDTaraZ.Respawn.Step, { "InstantRespawn" })
    xDTaraZ.Scheduler.Every("Best Gear", 0.5, xDTaraZ.Loot.GearStep, { "AutoGear" })
    xDTaraZ.Scheduler.Every("Auto Ammo", 1, xDTaraZ.Loot.AmmoStep, { "AutoAmmo" })
    xDTaraZ.Scheduler.Every("Guns in hand", 0.2, xDTaraZ.Combat.GunStep)
    xDTaraZ.Scheduler.Every("Valuables", 1, xDTaraZ.Loot.ValuablesStep, { "AutoValuables" })
    xDTaraZ.Scheduler.Every("Auto Heal", 0.1, xDTaraZ.Heal.Step, { "AutoHeal" })
    xDTaraZ.Scheduler.Every("Farm stats", 2, xDTaraZ.Farm.Sample)
    xDTaraZ.Scheduler.Every("Auto Rejoin", 2, xDTaraZ.Respawn.Rejoin, { "AutoRejoin" })
    xDTaraZ.Scheduler.Every("Hunt", 0.5, xDTaraZ.Hunt.Step, { "Hunt" })
    xDTaraZ.Scheduler.Every("Rewards", 1, xDTaraZ.Rewards.Step)
    xDTaraZ.Scheduler.Every("Staff", 3, xDTaraZ.Admin.Step)
    Util.Try("scheduler", xDTaraZ.Scheduler.Boot)
end

local function UnloadHub()
    if xDTaraZ.Library and not xDTaraZ.Library.Unloaded then
        xDTaraZ.Library:Unload()
    else
        xDTaraZ:Unload()
    end
end

function xDTaraZ:Unload()
    self.State.Alive = false
    if environment.AirDropArenaUnload == UnloadHub then environment.AirDropArenaUnload = nil end
    xDTaraZ.Combat.Unload()
    xDTaraZ.Guns.Restore()
    for _, key in ipairs({ "Fullbright", "CameraFov", "Noclip", "Fly", "Speed" }) do
        xDTaraZ.Options[key] = false
    end
    pcall(xDTaraZ.Loot.ClearMarks)
    pcall(xDTaraZ.World.Step)
    pcall(xDTaraZ.World.OnRender)
    pcall(xDTaraZ.Movement.OnStepped)
    for _, conn in ipairs(self.State.Connections) do
        pcall(function() conn:Disconnect() end)
    end
    table.clear(self.State.Connections)
    if xDTaraZ.Respawn.Conn then
        xDTaraZ.Respawn.Conn:Disconnect()
        xDTaraZ.Respawn.Conn = nil
    end
    if Util.Overlay then
        Util.Overlay:Destroy()
        Util.Overlay = nil
    end
end

environment.AirDropArenaUnload = UnloadHub

pcall(NovaBanner.Step, "Systems")
if not BuildInterface() then return end
pcall(NovaBanner.Step, "Interface")
pcall(NovaBanner.Ready)]==]

NOVA_HUB_MODULES[7633926880] = [==[if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")
local TeleportService = game:GetService("TeleportService")
local StarterGui = game:GetService("StarterGui")
local VirtualInputManager = game:GetService("VirtualInputManager")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer

if game.GameId ~= 7633926880 then
    LocalPlayer:Kick("Nova Hub: this script is for BloxStrike only")
    return
end

---@return function  the game's own print when the executor exposes it
local function RuntimePrint()
    local ok, renv = pcall(getrenv)
    return ok and type(renv) == "table" and type(renv.print) == "function" and renv.print or print
end

local NovaBanner = {
    Print = RuntimePrint(),
    Started = os.clock(),
    Last = os.clock(),
    Done = 0,
    Total = 4,
}

function NovaBanner.Show()
    local ok, executor = pcall(identifyexecutor)
    if not ok or type(executor) ~= "string" then executor = "Unknown" end
    local rule = string.rep("=", 54)
    NovaBanner.Print(table.concat({
        "",
        [[
                                                                     @%@
                                                                    @*-#@
                                          @@@@@@@@@@@@@          @@#+.:-*%@@      @@
                                   @@@@@%##***********##%@@@@@   @*--:-==+*@@@@#*+==+*%@@
                              @@@@#+=+==---==++++++++++++**+++#@@@@@%==+@@@@#:.......:::=%@@
                          @@%#+---::-=++++++++++************+***++#%@%+@@@#:..-+*****+-:::+%@
                      @@@#=-::.:-==++++++++++*************************#@@+::=*-:.:+-::-+:.:=#@
                    @@%-:...:-===+++++**#################****************%%*+::::+*++::-+..:=#@
                 @@%*-:...:--==++*########**+==--===+**#######************+#%+::-*==-:::=-::=+@@
               @@%+=-::---===+*###%#+-:...................:=+#####***********#@+++==----==:-+*@@
             @@%++=-======+*###%+:............................::+####**********#@*+=----=---**@@
            @%=++=++++++*####=:...................................:+###**********%@==--==--+**@@
          @@*+++++++++*###*:........................................:-*##**********%*==+--=**@@@
         @%+++++++++*##%+:............................................::*##*********%%+--=##%@+%@
       @@#+++++++++###*:.....-+==+*#-......................:**+**#+:....:=###********%%+*##%@*:+@@
      @@*++++++++*###:......-+:.:-=*#*-..................:+*--+**#%*:.....:+##********#@#%%+:.:--+#@
     @@+++++++++*##+:......-*::-=++++*##:...............=#=-++****#%*:.....:-##********#@@@%+=-++#@@
    @@+=-=+++++*##+.......:*-:==++++++*##+............-*+-=+*******#%+:.....:-##********#@  @#=#@@
    @*=:.=++++*##-.......:*=:=++++++++*+*##=........:**==+**********##=:.....::*#********%@  @#@
   @#+-.-++*+*##=........*+-++++++*********##-....:+*==+*************#%-:.....:-**********%@
  @@++-=++***##+........*+-++++++***********#%*::=#+-+****************#%-:.....:=**********@@
 @@*++=++***###........+*-+++++***************###+-=+*****************###-:.....:+*********%@
 @%++=+*****#%:.......=*-++++*******************==+********************#%*-:....:-#********#@@
@@**+++****##+.......=*=+++*********************************************#%+::....:+*********@@
@%**++*****##-......=#=++**********#%#********************%%*************#%+:....:-#********%@
@%**++*****#*:.....-*=++**********#%%%#*****************#%%%**************#%=:....-********##@@
@#**++*****#*:....:*++************%%%%%%#*************#%%%%%#**************##-:...-+*******#*@@
@#**+******#+:...:#++************#%%%@@%%##*********#%%%%%@%#**************#%#-:..:+*+*****#*@@
@#**+******#+:..:#+=************#%%%%%*%%%##*******%%%%%%#%%##**************#%#::.-+*+*****#*@@
@#*********#+:.:+*=*************%%%%%+==*%%###***#%%%%%#++*%##***************#%*::-+*+*****#*@@
@%*#*******#*:.+*=*************%%%%%*=----*%###%%%%%%#+====*###**************##%+--*++****###@@
@%*#********#-:####***********#%%%%#=-::.::=###%%%%#+==--:::####************#%%%#==*+*****###@@
@@##********#+:#%%%%#********#%%%%%=--:....::=%%%%+==--::..:-%###********#%%%%%%#=#++*****##%@
@@###********#-=#%%%%%%##****%%%%%*=-:.......::-==---::.....:+###*****##%%%%%%%#++#++****###@@
 @%###*******##::=+%%%%%%%##%%%%%#=-:...........:::::........:####*#%%%%%%%%%*+=+*+=*****##%@
 @@###********#+:.:-=*%%%%%%%%%%%+--:.........................=###%%%%%%%%*+====*=.=****###@@
  @@###********#+:..::-=*%%%%%%%*=-:..:::-------------::::...::*#%%%%%%*+==---=*+-=+***###%@
   @%###*******#%#*+-..::-=#%@@%#**++==----------------===+++**#%@@@#+===---+*#*++****####@@
    @%###**#%#=::-=+##*##+-:...:::-=+**---*###*=--++++=--=++++=--:::-=+#%**#-:..:=#%##%##@@
    @@%#%#+:...:-=++=:..::=*####+#=:..=@#%:....%@*....*%%#...:--=*##+------=+=:::::-=#%%@@
     @@%*=--::::-*::::::-%=...:%@#:...:@@#.....%@+....=@@=.........:*#=-----=+=:::-==++%@@
  @@%+--+==--:::-#=-::::-%+....+%%-....%@#....:@@+....+@@:...:%%....-@*---==+*+:::-=+++*=+#@@
 @%-:-==*+==-:::-+*--:::-*#:...........*@#....:@@+....+@%..........-%%+---==+*=::-=+++#*=-:-*@@
 @@#+===+*+==-::-=*=--::-=%-......:....+@%:....:-....:#@*....=+:...-%#=--==+**-:--=++#*+=-=*%@
   @@#*=++#+=-:::-+*------#+....+@%....-@@#:.......::*@@+....+#=.:::=%+-===+#+-:-=++***++*%@@
     @@#+++*==-::-=*=-----+%:...-@@-::-=@%%@#+=--==*%@%%=:::::::::::#%+===+**----=++#**#%@@
     @@*-=+*+=-::-=*+=----=%#+*#%@%@@@@@#+-=*%%@@@%#*==*@@%%%##*+*#@@*====+#+-:-=++***++%@
    @@*--=+++===++*#*=------#%%#+=-----===============----==+*#%%%#+=-===+*#*+++=++**+==*@@
    @%=:-==+***%%@@@#=-=====++*##%%%@@@@@@@@@@%%@@@@@@@@@%%%##**++=======+*@@@@%#*+#+=--=#@
    @*:---==+*###%@@@#*#%%@%%%%%%######*****++++++++***######%%%%%%%%%%#*#%@@@####**+=---+@@
   @@+--=**#%@@@@@  @@@%%%%%%%#*******************************####%%%%%%@@@  @@@@@%#**=--+%@
    @@%%@@@@@          @@@@%%%%%%###**********************####%%%%%%%@@@          @@@@@%%%@@
      @@                  @@@@@%%%%%%%%%###############%%%%%%%%%@@@@@                  @@@
                               @@@@@@%%%%%%%%%%%%%%%%%%%%%%@@@@@
                                    @@@@@@@@@@@@@@@@@@@@@@@
]],
        [[
  __  __    _    ____  ___ ___    _   _ _   _ ____
 |  \/  |  / \  |  _ \|_ _/ _ \  | | | | | | | __ )
 | |\/| | / _ \ | |_) || | | | | | |_| | | | |  _ \
 | |  | |/ ___ \|  _ < | | |_| | |  _  | |_| | |_) |
 |_|  |_/_/   \_\_| \_\___\___/  |_| |_|\___/|____/
]],
        rule,
        "   BLOXSTRIKE  //  by xDTaraZ  //  discord.gg/FHVfmeSceA",
        "   executor: " .. executor .. "   //   player: " .. game:GetService("Players").LocalPlayer.Name,
        rule,
    }, "\n"))
end

---@param label string  what just finished loading
function NovaBanner.Step(label)
    local now = os.clock()
    NovaBanner.Done = math.min(NovaBanner.Done + 1, NovaBanner.Total)
    local filled = math.floor(NovaBanner.Done / NovaBanner.Total * 20 + 0.5)
    NovaBanner.Print(string.format("[Nova Hub] [%s] %3d%%  %-24s +%dms",
        string.rep("#", filled) .. string.rep(".", 20 - filled),
        math.floor(NovaBanner.Done / NovaBanner.Total * 100), label, math.floor((now - NovaBanner.Last) * 1000)))
    NovaBanner.Last = now
end

function NovaBanner.Ready()
    local rule = string.rep("=", 54)
    NovaBanner.Print(table.concat({
        rule,
        string.format("   >> READY in %dms", math.floor((os.clock() - NovaBanner.Started) * 1000)),
        rule,
    }, "\n"))
end

pcall(NovaBanner.Show)
pcall(NovaBanner.Step, "Core")

local environment = getgenv and getgenv() or _G
if environment.BloxStrikeUnload then pcall(environment.BloxStrikeUnload) end

if not LPH_OBFUSCATED then
    local function Passthrough(fn) return fn end
    LPH_JIT, LPH_JIT_MAX, LPH_NO_VIRTUALIZE = Passthrough, Passthrough, Passthrough
end

local vector2New = Vector2.new
local cframeLookAt = CFrame.lookAt
local osClock = os.clock

local Library, T

local xDTaraZ = setmetatable({}, {
    __newindex = function(self, key, value)
        rawset(self, key, type(value) == "function" and LPH_JIT(value) or value)
    end,
})

xDTaraZ.Config = {
    UiSource = "NovaHub://embedded-ui",
    Discord = "https://discord.gg/FHVfmeSceA",
    UpdateLog = {
        { "2026-10-03", "Classic Nova Hub UI is back\nBetter executor support\nImproved Combat & Movement" },
    },
    SaveFolder = "BloxStrike",
    StatusInterval = 1,
    AimRenderPriority = Enum.RenderPriority.Camera.Value + 1,
    RefireGap = 0.12,
    TriggerRay = 2000,
    MinShotDistance = 0.05,
    RedeemGap = 1.1,
    RebuyGap = 0.25,
    AlertTries = 20,
    AlertGap = 0.5,
    RequireTimeout = 5,
    MaxFails = 5,
    FailWindow = 10,
    CombatToggles = { "Aimbot", "Triggerbot", "Ragebot", "AimbotShowFov", "SilentShowFov" },
    ModuleFeatures = {
        Net = { "SilentAim", "Ragebot", "AutoRebuy" },
        Character = { "BunnyHop" },
        Weapons = { "FullAuto", "RapidFire", "WeaponSpeed" },
        Skins = { "SkinChanger" },
    },
    Codes = {
        "1MGROUPMEMBERS", "MYFAULTYALL", "RIANOMINATED2026", "LORE", "DUST_II", "MICHAELSRETURN",
        "FREEDOM", "HAPPYBDAYYUUTO", "GAMEBROKE318", "OHNEPIXEL", "NEBULA", "REACTORDELAY", "BUTTERFLYCASE", "TRADEUPS",
    },
    BoneParts = {
        Head = { "Head" },
        Torso = { "UpperTorso", "Torso", "HumanoidRootPart" },
    },
    BuyStates = { ["Buy Period"] = true, ["Warmup"] = true },
    StickySlack = 1.5,
    HopGap = 0.05,
    HookSettle = 1,
    SkinFile = "BloxStrike/skins.json",
    SkinWears = { "Factory New", "Minimal Wear", "Field-Tested", "Well-Worn", "Battle-Scarred" },
    SkinKinds = { Melee = "Knives", Glove = "Gloves", Grenade = "Grenades", C4 = "Gear", ["Zeus x27"] = "Gear" },
    SkinOrder = { "Pistol", "SMG", "Rifle", "Sniper", "Heavy", "Shotgun", "Machine Gun", "Knives", "Gloves", "Grenades", "Gear" },
    SkinRanks = { Forbidden = 9, Special = 8, Red = 7, Pink = 6, Purple = 5, Blue = 4, LightBlue = 3, Gray = 2, White = 1 },
    SkinMainRows = 5,
    SkinArms = { ["Left Arm"] = true, ["Right Arm"] = true },
    GloveKey = "@Glove",
    FovColors = {
        Aimbot = Color3.fromRGB(232, 160, 76),
        Silent = Color3.fromRGB(110, 170, 255),
    },
    EspFocusColor = Color3.fromRGB(255, 214, 64),
    FovLayer = 50,
}

xDTaraZ.State = {
    Alive = true,
    Connections = {},
    Halted = {},
    Notices = {},
    AimTarget = nil,
    AimPart = nil,
    RageTarget = nil,
    RagePart = nil,
    SilentTarget = nil,
    Firing = false,
    PressedAt = 0,
    LastShot = 0,
    Shots = 0,
    Redirected = 0,
    Bought = {},
    LastRebuyRound = nil,
    LightSaved = nil,
    WeaponSaved = {},
    Hooks = {},
    RecoilWarned = false,
    TriggerWarned = false,
    HopAt = 0,
    HopCrouched = false,
    SpaceHeld = false,
    FovBound = false,
    FovBase = 0,
}

xDTaraZ.Options = {
    Aimbot = false,
    AimbotSmooth = 1,
    AimbotBone = "Head",
    AimbotPriority = "Crosshair",
    AimbotFov = 150,
    AimbotShowFov = false,
    AimbotVisible = true,
    AimbotSticky = true,
    AimbotMaxDistance = 1500,
    SilentAim = false,
    SilentHitChance = 100,
    SilentHeadChance = 100,
    SilentPriority = "Crosshair",
    SilentFov = 220,
    SilentShowFov = false,
    SilentVisible = true,
    SilentMaxDistance = 2000,
    Triggerbot = false,
    TriggerDelay = 0,
    TriggerHitChance = 100,
    Ragebot = false,
    RageVisible = true,
    RageMaxDistance = 2000,
    NoRecoil = false,
    RecoilKeep = 0,
    NoSpread = false,
    FullAuto = false,
    RapidFire = false,
    FireRateMult = 1.5,
    WeaponSpeed = false,
    WeaponSpeedMult = 1.3,
    Fullbright = false,
    NoFlash = false,
    NoSmoke = false,
    CameraFov = false,
    CameraFovValue = 100,
    InfiniteJump = false,
    BunnyHop = false,
    BunnyCrouch = true,
    SkinChanger = false,
    AutoRebuy = false,
    AntiAfk = false,
}

xDTaraZ.Caps = setmetatable({}, {
    __index = function(_, name)
        return Library ~= nil and Library.Compat.Caps[name] == true
    end,
})

xDTaraZ.Util = {}

function xDTaraZ.Util.HttpGet(url)
    if url == "NovaHub://embedded-ui" then return NOVA_HUB_UI_SOURCE end
    local ok, body = pcall(game.HttpGet, game, url)
    if ok and type(body) == "string" then return body end
    local req = request or http_request or (syn and syn.request)
    if not req then error("no http") end

    local sent, response = pcall(req, { Url = url, Method = "GET" })
    if not sent then error(response) end
    local status = type(response) == "table" and tonumber(response.StatusCode)
    if status ~= 200 or type(response.Body) ~= "string" then error("http status " .. tostring(status)) end
    return response.Body
end

---@param detail any  extra context for the warn; the player only sees `text`
function xDTaraZ.Util.Alert(text, detail)
    warn("[BloxStrike] menu:", detail or text)
    task.spawn(function()
        for _ = 1, xDTaraZ.Config.AlertTries do
            if pcall(StarterGui.SetCore, StarterGui, "SendNotification", { Title = "Nova Hub", Text = text, Duration = 10 }) then return end
            task.wait(xDTaraZ.Config.AlertGap)
        end
    end)
end

---@return table?  nil after the player was told on screen
function xDTaraZ.Util.LoadLibrary(url)
    local got, source = pcall(xDTaraZ.Util.HttpGet, url)
    local whole = got and type(source) == "string" and source:sub(-64):find("return Library%s*$") ~= nil
    if not whole then
        xDTaraZ.Util.Alert("Could not download the menu. Check your connection and run it again.", got and "truncated or not the menu" or source)
        return nil
    end
    local chunk, err = loadstring(source)
    if type(chunk) ~= "function" then
        xDTaraZ.Util.Alert("The menu failed to load on this executor: " .. tostring(err))
        return nil
    end
    local ran, loaded = pcall(chunk)
    if ran and type(loaded) == "table" then return loaded end
    xDTaraZ.Util.Alert("The menu failed to load on this executor: " .. tostring(loaded))
    return nil
end

function xDTaraZ.Util.Try(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then warn("[BloxStrike] " .. label .. ":", err) end
    return ok
end

function xDTaraZ.Util.Copy(text)
    local fn = setclipboard or toclipboard
    if not fn then return false end
    return pcall(fn, text)
end

---@return function?  original, nil when already hooked or the executor can't hook it
function xDTaraZ.Util.Hook(key, fn, replacement)
    if type(fn) ~= "function" or xDTaraZ.State.Hooks[key] or not xDTaraZ.Caps.HookFunction then return nil end
    local ok, original = pcall(hookfunction, fn, replacement)
    if not ok or type(original) ~= "function" then
        warn("[BloxStrike] hook " .. key .. ":", ok and "executor returned no original" or original)
        return nil
    end
    xDTaraZ.State.Hooks[key] = { Fn = fn, Original = original }
    return original
end

function xDTaraZ.Util.UnhookAll()
    for key, hook in pairs(xDTaraZ.State.Hooks) do
        local ok, err = pcall(Library.Compat.Unhook, hook.Fn, function() hookfunction(hook.Fn, hook.Original) end)
        if not ok then warn("[BloxStrike] unhook " .. key .. ":", err) end
    end
    table.clear(xDTaraZ.State.Hooks)
end

function xDTaraZ.Util.Decode(raw)
    if type(raw) ~= "string" then return nil end
    local ok, decoded = pcall(HttpService.JSONDecode, HttpService, raw)
    return ok and decoded or nil
end

function xDTaraZ:Connect(signal, handler)
    local conn = signal:Connect(handler)
    table.insert(self.State.Connections, conn)
    return conn
end

xDTaraZ.GameLib = { Missing = {} }

---@param parent Instance?     where it lives today
---@param home string          parent name a moved copy must still have
---@return Instance?           nil after a warning that names it
function xDTaraZ.GameLib.Find(parent, name, class, home)
    local found = parent and parent:FindFirstChild(name)
    if found and found:IsA(class) then return found end
    for _, desc in ipairs(ReplicatedStorage:GetDescendants()) do
        if desc.Name == name and desc:IsA(class) and desc.Parent and desc.Parent.Name == home then return desc end
    end
    xDTaraZ.GameLib.Missing[name] = "Absent"
    warn("[BloxStrike] " .. home .. "." .. name .. " not found, features that need it are blocked")
    return nil
end

---@return any  module, or nil when this executor can't require it (never throws)
function xDTaraZ.GameLib.Require(inst)
    if not (inst and inst:IsA("ModuleScript")) then return nil end
    local ok, mod = pcall(require, inst)
    if ok then return mod end

    local done, okAgain, again = false, false, nil
    task.spawn(function()
        pcall(setthreadidentity, 2)
        local read, identity = pcall(getthreadidentity)
        if read and identity == 2 then okAgain, again = pcall(require, inst) end
        done = true
    end)
    local deadline = osClock() + xDTaraZ.Config.RequireTimeout
    while not done and osClock() < deadline do task.wait() end
    if okAgain then return again end
    warn("[BloxStrike] require " .. inst.Name .. ":", mod)
    return nil
end

do
    local database = ReplicatedStorage:FindFirstChild("Database")
    local security = database and database:FindFirstChild("Security")
    local custom = database and database:FindFirstChild("Custom")
    local controllers = ReplicatedStorage:FindFirstChild("Controllers")
    local find = xDTaraZ.GameLib.Find
    xDTaraZ.GameLib.Net = xDTaraZ.GameLib.Require(find(security, "Remotes", "ModuleScript", "Security"))
    xDTaraZ.GameLib.Character = xDTaraZ.GameLib.Require(find(controllers, "CharacterController", "ModuleScript", "Controllers"))
    xDTaraZ.GameLib.Camera = xDTaraZ.GameLib.Require(find(controllers, "CameraController", "ModuleScript", "Controllers"))
    xDTaraZ.GameLib.WeaponFolder = find(custom, "Weapons", "Folder", "Custom")
end

xDTaraZ.Weapons = {}
do
    local folder = xDTaraZ.GameLib.WeaponFolder
    for _, module in ipairs(folder and folder:GetChildren() or {}) do
        local data = module:IsA("ModuleScript") and xDTaraZ.GameLib.Require(module)
        if type(data) == "table" and data.FireRate then xDTaraZ.Weapons[module.Name] = data end
    end
end

xDTaraZ.Player = {}

function xDTaraZ.Player.Character()
    local chars = Workspace:FindFirstChild("Characters")
    return (chars and chars:FindFirstChild(LocalPlayer.Name)) or LocalPlayer.Character
end

function xDTaraZ.Player.Alive()
    local char = xDTaraZ.Player.Character()
    return char ~= nil and char.Parent ~= nil and tostring(LocalPlayer:GetAttribute("Dead")) ~= "true"
end

function xDTaraZ.Player.Humanoid()
    local char = xDTaraZ.Player.Character()
    return char and char:FindFirstChildOfClass("Humanoid")
end

---@return table?  the game's own local character state; nil outside a round
function xDTaraZ.Player.Body()
    local controller = xDTaraZ.GameLib.Character
    if not controller then return nil end
    local ok, body = pcall(controller.getCurrentCharacter)
    return ok and body or nil
end

function xDTaraZ.Player.Equipped()
    return xDTaraZ.Util.Decode(LocalPlayer:GetAttribute("CurrentEquipped"))
end

xDTaraZ.Target = {}

local losParams = RaycastParams.new()
losParams.FilterType = Enum.RaycastFilterType.Exclude
local losFilter = table.create(3)

function xDTaraZ.Target.Candidates()
    local list = {}
    local chars = Workspace:FindFirstChild("Characters")
    if not chars then return list end
    for _, model in ipairs(chars:GetChildren()) do
        if model.Name ~= LocalPlayer.Name and model:IsA("Model") then list[#list + 1] = model end
    end
    return list
end

function xDTaraZ.Target.Owner(model)
    return Players:FindFirstChild(model.Name)
end

function xDTaraZ.Target.IsEnemy(model)
    if tostring(model:GetAttribute("Dead")) == "true" then return false end
    local owner = xDTaraZ.Target.Owner(model)
    if not owner then return false end
    local mine = LocalPlayer:GetAttribute("Team")
    return mine == nil or owner:GetAttribute("Team") ~= mine
end

function xDTaraZ.Target.Part(model, bone)
    for _, name in ipairs(xDTaraZ.Config.BoneParts[bone] or xDTaraZ.Config.BoneParts.Head) do
        local part = model:FindFirstChild(name)
        if part and part:IsA("BasePart") then return part end
    end
    return model:FindFirstChild("HumanoidRootPart")
end

function xDTaraZ.Target.Visible(from, model, point)
    losFilter[1], losFilter[2], losFilter[3] = xDTaraZ.Player.Character(), model, Workspace.CurrentCamera
    losParams.FilterDescendantsInstances = losFilter
    return Workspace:Raycast(from, point - from, losParams) == nil
end

---@param cfg table  { Bone, Fov?, Visible, MaxDistance, Priority }  Fov nil = whole map
---@return Model?, BasePart?
function xDTaraZ.Target.Pick(cfg)
    local cam = Workspace.CurrentCamera
    local origin = cam.CFrame.Position
    local center = cam.ViewportSize / 2
    local best, bestPart, bestScore

    for _, model in ipairs(xDTaraZ.Target.Candidates()) do
        if not xDTaraZ.Target.IsEnemy(model) then continue end
        local part = xDTaraZ.Target.Part(model, cfg.Bone)
        if not part then continue end
        local dist = (part.Position - origin).Magnitude
        if dist > cfg.MaxDistance then continue end

        local screen, onScreen = cam:WorldToViewportPoint(part.Position)
        local screenDist = (vector2New(screen.X, screen.Y) - center).Magnitude
        if cfg.Fov and (not onScreen or screenDist > cfg.Fov) then continue end
        if cfg.Visible and not xDTaraZ.Target.Visible(origin, model, part.Position) then continue end

        local score = dist
        if cfg.Priority == "Crosshair" then
            score = onScreen and screenDist or 1e6 + dist
        elseif cfg.Priority == "Health" then
            score = (tonumber(model:GetAttribute("Health")) or 100) * 1e4 + dist
        end
        if not bestScore or score < bestScore then best, bestPart, bestScore = model, part, score end
    end
    return best, bestPart
end

---@return boolean  still a valid lock, with a looser fov
function xDTaraZ.Target.StillValid(model, part, cfg)
    if not (model and part and part.Parent and xDTaraZ.Target.IsEnemy(model)) then return false end
    local cam = Workspace.CurrentCamera
    local origin = cam.CFrame.Position
    if (part.Position - origin).Magnitude > cfg.MaxDistance then return false end
    if cfg.Visible and not xDTaraZ.Target.Visible(origin, model, part.Position) then return false end
    if not cfg.Fov then return true end
    local screen, onScreen = cam:WorldToViewportPoint(part.Position)
    local center = cam.ViewportSize / 2
    return onScreen and (vector2New(screen.X, screen.Y) - center).Magnitude <= cfg.Fov * xDTaraZ.Config.StickySlack
end

---@return Model?  enemy under the crosshair right now
function xDTaraZ.Target.UnderCrosshair()
    local cam = Workspace.CurrentCamera
    losFilter[1], losFilter[2], losFilter[3] = xDTaraZ.Player.Character(), cam, nil
    losParams.FilterDescendantsInstances = losFilter
    local hit = Workspace:Raycast(cam.CFrame.Position, cam.CFrame.LookVector * xDTaraZ.Config.TriggerRay, losParams)
    if not hit then return nil end
    local chars = Workspace:FindFirstChild("Characters")
    local model = hit.Instance
    while model and model.Parent ~= chars do model = model.Parent end
    if model and model:IsA("Model") and xDTaraZ.Target.IsEnemy(model) then return model end
    return nil
end

local function roll(percent)
    return percent >= 100 or math.random() * 100 < percent
end

xDTaraZ.Aimbot = {}

function xDTaraZ.Aimbot.Config()
    local o = xDTaraZ.Options
    return { Bone = o.AimbotBone, Fov = o.AimbotFov, Visible = o.AimbotVisible, MaxDistance = o.AimbotMaxDistance, Priority = o.AimbotPriority }
end

function xDTaraZ.Aimbot.Step()
    local state, o = xDTaraZ.State, xDTaraZ.Options
    if not o.Aimbot then state.AimTarget, state.AimPart = nil, nil return end
    local cfg = xDTaraZ.Aimbot.Config()
    if o.AimbotSticky and xDTaraZ.Target.StillValid(state.AimTarget, state.AimPart, cfg) then return end
    state.AimTarget, state.AimPart = xDTaraZ.Target.Pick(cfg)
end

function xDTaraZ.Aimbot.Lock()
    local o, state = xDTaraZ.Options, xDTaraZ.State
    local part, smooth = nil, 1
    if o.Ragebot and state.RagePart and state.RagePart.Parent then
        part = state.RagePart
    elseif o.Aimbot and state.AimPart and state.AimPart.Parent then
        part, smooth = state.AimPart, math.max(o.AimbotSmooth, 1)
    end
    if not part then return end
    local cam = Workspace.CurrentCamera
    local origin = cam.CFrame.Position
    local want = (part.Position - origin).Unit
    local look = smooth <= 1 and want or cam.CFrame.LookVector:Lerp(want, 1 / smooth).Unit
    cam.CFrame = cframeLookAt(origin, origin + look)
end

xDTaraZ.Silent = {}

---@param forced boolean  ragebot shot: always hits, no fov
function xDTaraZ.Silent.Config(bone, forced)
    local o = xDTaraZ.Options
    if forced then return { Bone = bone, Visible = o.RageVisible, MaxDistance = o.RageMaxDistance, Priority = "Distance" } end
    return { Bone = bone, Fov = o.SilentFov, Visible = o.SilentVisible, MaxDistance = o.SilentMaxDistance, Priority = o.SilentPriority }
end

---@param payload table  ShootWeapon packet, edited in place
function xDTaraZ.Silent.Rewrite(payload)
    local o = xDTaraZ.Options
    local forced = o.Ragebot
    if not forced and not roll(o.SilentHitChance) then return end
    local bone = (forced or roll(o.SilentHeadChance)) and "Head" or "Torso"
    local target, part = xDTaraZ.Target.Pick(xDTaraZ.Silent.Config(bone, forced))
    xDTaraZ.State.SilentTarget = target
    if not part then return end
    local material = part.Material.Name
    for _, bullet in ipairs(payload.Bullets) do
        local origin = typeof(bullet.Origin) == "Vector3" and bullet.Origin or Workspace.CurrentCamera.CFrame.Position
        local offset = part.Position - origin
        local dist = offset.Magnitude
        if dist < xDTaraZ.Config.MinShotDistance then continue end
        local unit = offset / dist
        bullet.Direction = unit
        bullet.Hits = { { Instance = part, Position = part.Position, Normal = -unit, Material = material, Distance = dist, Exit = false } }
    end
    xDTaraZ.State.Redirected += 1
end

function xDTaraZ.Silent.InstallHook()
    local net = xDTaraZ.GameLib.Net
    local packet = net and net.Inventory and net.Inventory.ShootWeapon
    if not packet then return end
    local original
    original = xDTaraZ.Util.Hook("Shoot", packet.Send, function(payload, ...)
        if type(payload) == "table" and type(payload.Bullets) == "table" then
            xDTaraZ.State.LastShot = osClock()
            xDTaraZ.State.Shots += 1
            if xDTaraZ.Options.SilentAim or xDTaraZ.Options.Ragebot then
                local ok, err = pcall(xDTaraZ.Silent.Rewrite, payload)
                if not ok then warn("[BloxStrike] silent:", err) end
            end
        end
        return original(payload, ...)
    end)
end

xDTaraZ.Trigger = {}

function xDTaraZ.Trigger.Press(down)
    xDTaraZ.State.Firing = down
    if down then xDTaraZ.State.PressedAt = osClock() end
    local center = Workspace.CurrentCamera.ViewportSize / 2
    pcall(VirtualInputManager.SendMouseButtonEvent, VirtualInputManager, center.X, center.Y, 0, down, game, 0)
end

---@param want boolean  holds auto guns and re-clicks semi-auto ones
function xDTaraZ.Trigger.Fire(want)
    local state, now = xDTaraZ.State, osClock()
    if not want then
        if state.Firing then xDTaraZ.Trigger.Press(false) end
        return
    end
    if not state.Firing then
        xDTaraZ.Trigger.Press(true)
        return
    end
    local gap = xDTaraZ.Config.RefireGap
    if now - state.PressedAt > gap and now - state.LastShot > gap then xDTaraZ.Trigger.Press(false) end
end

function xDTaraZ.Trigger.Wanted()
    local o, state = xDTaraZ.Options, xDTaraZ.State
    if not o.Triggerbot then return false end
    local model = xDTaraZ.Target.UnderCrosshair()
    if model ~= state.TriggerModel then
        state.TriggerModel = model
        state.TriggerSeen = model and osClock() or nil
        state.TriggerRoll = model ~= nil and roll(o.TriggerHitChance)
    end
    if not model or not state.TriggerRoll then return false end
    return osClock() - state.TriggerSeen >= o.TriggerDelay / 1000
end

xDTaraZ.Rage = {}

function xDTaraZ.Rage.Step()
    local state = xDTaraZ.State
    if not xDTaraZ.Options.Ragebot then state.RageTarget, state.RagePart = nil, nil return false end
    state.RageTarget, state.RagePart = xDTaraZ.Target.Pick(xDTaraZ.Silent.Config("Head", true))
    return state.RageTarget ~= nil
end

xDTaraZ.Combat = { Circles = {} }

---@return ScreenGui  made once; hidden gui first, then CoreGui, then PlayerGui
function xDTaraZ.Combat.Screen()
    local screen = xDTaraZ.Combat.Gui
    if screen and screen.Parent then return screen end

    screen = Instance.new("ScreenGui")
    screen.Name = "NovaHubFov"
    screen.IgnoreGuiInset = true
    screen.ResetOnSpawn = false
    screen.DisplayOrder = xDTaraZ.Config.FovLayer

    local function Mount(parent) screen.Parent = parent end
    local okHui, hui = pcall(gethui)
    local mounted = okHui and hui ~= nil and pcall(Mount, hui)
    if not mounted then mounted = pcall(Mount, game:GetService("CoreGui")) end
    if not mounted then Mount(LocalPlayer:FindFirstChildOfClass("PlayerGui")) end

    xDTaraZ.Combat.Gui = screen
    return screen
end

---@return table  { Drawing = circle }, or { Frame = ring } drawn with Gui when Drawing is missing
function xDTaraZ.Combat.NewCircle(color)
    if xDTaraZ.Caps.Drawing then
        local circle = Drawing.new("Circle")
        circle.Thickness, circle.NumSides, circle.Filled, circle.Color = 1.5, 64, false, color
        return { Drawing = circle }
    end
    local frame = Instance.new("Frame")
    frame.AnchorPoint = vector2New(0.5, 0.5)
    frame.BackgroundTransparency = 1
    local round = Instance.new("UICorner")
    round.CornerRadius = UDim.new(1, 0)
    round.Parent = frame
    local edge = Instance.new("UIStroke")
    edge.Thickness, edge.Color = 1.5, color
    edge.Parent = frame
    frame.Parent = xDTaraZ.Combat.Screen()
    return { Frame = frame }
end

function xDTaraZ.Combat.Circle(key, show, radius)
    local circle = xDTaraZ.Combat.Circles[key]
    if not circle then
        if not show then return end
        circle = xDTaraZ.Combat.NewCircle(xDTaraZ.Config.FovColors[key])
        xDTaraZ.Combat.Circles[key] = circle
    end
    local center = Workspace.CurrentCamera.ViewportSize / 2
    local drawing, frame = circle.Drawing, circle.Frame
    if drawing then
        drawing.Visible, drawing.Position, drawing.Radius = show, center, radius
        return
    end
    frame.Visible = show
    frame.Position = UDim2.fromOffset(center.X, center.Y)
    frame.Size = UDim2.fromOffset(radius * 2, radius * 2)
end

function xDTaraZ.Combat.Step()
    local o, state = xDTaraZ.Options, xDTaraZ.State
    xDTaraZ.Combat.Circle("Aimbot", o.AimbotShowFov, o.AimbotFov)
    xDTaraZ.Combat.Circle("Silent", o.SilentShowFov, o.SilentFov)
    if not xDTaraZ.Player.Alive() then
        state.AimTarget, state.AimPart, state.RageTarget, state.RagePart = nil, nil, nil, nil
        xDTaraZ.Trigger.Fire(false)
        return
    end
    xDTaraZ.Aimbot.Step()
    local rage = xDTaraZ.Rage.Step()
    xDTaraZ.Trigger.Fire(rage or xDTaraZ.Trigger.Wanted())
end

function xDTaraZ.Combat.Rest()
    local state = xDTaraZ.State
    state.AimTarget, state.AimPart, state.RageTarget, state.RagePart = nil, nil, nil, nil
    xDTaraZ.Trigger.Fire(false)
    for key in pairs(xDTaraZ.Combat.Circles) do
        xDTaraZ.Combat.Circle(key, false, 0)
    end
end

function xDTaraZ.Combat.Start()
    RunService:BindToRenderStep("xDTaraZAim", xDTaraZ.Config.AimRenderPriority, xDTaraZ.Aimbot.Lock)
    xDTaraZ:Connect(RunService.Heartbeat, function()
        local ok, err = pcall(xDTaraZ.Combat.Step)
        if ok then
            xDTaraZ.Faults.Clear("Combat")
        else
            xDTaraZ.Faults.Report("Combat", err, xDTaraZ.Config.CombatToggles, xDTaraZ.Combat.Rest)
        end
    end)
end

function xDTaraZ.Combat.Unload()
    xDTaraZ.Trigger.Fire(false)
    pcall(RunService.UnbindFromRenderStep, RunService, "xDTaraZAim")
    for key, circle in pairs(xDTaraZ.Combat.Circles) do
        xDTaraZ.Combat.Circles[key] = nil
        if circle.Frame then
            circle.Frame:Destroy()
        else
            pcall(function() circle.Drawing:Remove() end)
        end
    end
    if xDTaraZ.Combat.Gui then
        xDTaraZ.Combat.Gui:Destroy()
        xDTaraZ.Combat.Gui = nil
    end
end

xDTaraZ.Guns = { Signature = nil, Warned = false }

function xDTaraZ.Guns.Save(name, data)
    local saved = xDTaraZ.State.WeaponSaved
    if saved[name] then return saved[name] end
    local spread = type(data.Spread) == "table" and table.clone(data.Spread) or nil
    local recoil = type(data.Recoil) == "table" and table.clone(data.Recoil) or nil
    saved[name] = { FireRate = data.FireRate, Automatic = data.Automatic, WalkSpeed = data.WalkSpeed, Spread = spread, Recoil = recoil }
    return saved[name]
end

---@return boolean  false when a frozen weapon table stays read-only on this executor
function xDTaraZ.Guns.Unfreeze(data)
    for _, section in pairs({ data = data, spread = data.Spread, recoil = data.Recoil }) do
        if type(section) ~= "table" or not table.isfrozen(section) then continue end
        if setreadonly then pcall(setreadonly, section, false) end
        if table.isfrozen(section) then return false end
    end
    return true
end

function xDTaraZ.Guns.Locked()
    if xDTaraZ.Guns.Warned then return end
    xDTaraZ.Guns.Warned = true
    warn("[BloxStrike] gun mods: weapon tables are read-only on this executor")
    table.insert(xDTaraZ.State.Notices, { "Gun Mods", "Some gun mods are not supported on this executor" })
end

function xDTaraZ.Guns.AnyActive()
    local opts = xDTaraZ.Options
    return opts.NoSpread or opts.NoRecoil or opts.FullAuto or opts.RapidFire or opts.WeaponSpeed
end

function xDTaraZ.Guns.ApplyOne(name, data)
    local opts = xDTaraZ.Options
    if not xDTaraZ.Guns.Unfreeze(data) then
        xDTaraZ.Guns.Locked()
        return
    end
    local base = xDTaraZ.Guns.Save(name, data)
    if base.Spread then
        for key, value in pairs(base.Spread) do
            data.Spread[key] = (opts.NoSpread and type(value) == "number") and 0 or value
        end
    end
    if base.Recoil then
        for key, value in pairs(base.Recoil) do
            local scaled = opts.NoRecoil and type(value) == "number" and key ~= "RecoverySpeed" and key ~= "Damper"
            data.Recoil[key] = scaled and value * opts.RecoilKeep / 100 or value
        end
    end
    data.Automatic = opts.FullAuto or base.Automatic
    data.FireRate = opts.RapidFire and base.FireRate / math.max(opts.FireRateMult, 1) or base.FireRate
    if base.WalkSpeed then data.WalkSpeed = opts.WeaponSpeed and base.WalkSpeed * opts.WeaponSpeedMult or base.WalkSpeed end
end

function xDTaraZ.Guns.Key()
    local o = xDTaraZ.Options
    return table.concat({ tostring(o.NoSpread), tostring(o.NoRecoil), o.RecoilKeep, tostring(o.FullAuto), tostring(o.RapidFire), o.FireRateMult, tostring(o.WeaponSpeed), o.WeaponSpeedMult }, "|")
end

function xDTaraZ.Guns.Step()
    local signature = xDTaraZ.Guns.Key()
    if signature == xDTaraZ.Guns.Signature then return end
    xDTaraZ.Guns.Signature = signature
    if not xDTaraZ.Guns.AnyActive() and not next(xDTaraZ.State.WeaponSaved) then return end
    for name, data in pairs(xDTaraZ.Weapons) do
        local ok, err = pcall(xDTaraZ.Guns.ApplyOne, name, data)
        if not ok then warn("[BloxStrike] gun:", name, err) end
    end
end

function xDTaraZ.Guns.HookKick()
    local cam = xDTaraZ.GameLib.Camera
    if not cam then return end
    local kick
    kick = xDTaraZ.Util.Hook("Kick", cam.weaponKick, function(...)
        local o = xDTaraZ.Options
        if o.NoRecoil and o.RecoilKeep <= 0 then return end
        return kick(...)
    end)
end

---@return boolean  true while any scope or zoom is up
function xDTaraZ.Guns.Scoped()
    if LocalPlayer:GetAttribute("IsSniperScoped") == true then return true end
    local cam = xDTaraZ.GameLib.Camera
    local getter = cam and cam.getTargetFOV
    if type(getter) ~= "function" then return false end
    local ok, target = pcall(getter)
    if not ok or type(target) ~= "number" then return false end

    local state = xDTaraZ.State
    if target > state.FovBase then state.FovBase = target end
    return target < state.FovBase
end

function xDTaraZ.Guns.StepFov()
    if not xDTaraZ.Options.CameraFov or xDTaraZ.Guns.Scoped() then return end
    local camera = Workspace.CurrentCamera
    if camera then camera.FieldOfView = xDTaraZ.Options.CameraFovValue end
end

function xDTaraZ.Guns.BindFov()
    local state = xDTaraZ.State
    if state.FovBound then return end
    state.FovBound = true
    RunService:BindToRenderStep("xDTaraZFov", Enum.RenderPriority.Camera.Value + 3, xDTaraZ.Guns.StepFov)
end

function xDTaraZ.Guns.UnbindFov()
    xDTaraZ.State.FovBound = false
    pcall(RunService.UnbindFromRenderStep, RunService, "xDTaraZFov")
end

function xDTaraZ.Guns.FindClass()
    if not xDTaraZ.Caps.Gc or not xDTaraZ.Caps.HookFunction then return nil end
    for _, entry in ipairs(getgc(true)) do
        if type(entry) == "table" and rawget(entry, "getSpread") and rawget(entry, "shoot") and rawget(entry, "setupRecoil") then return entry end
    end
    return nil
end

function xDTaraZ.Guns.HookSpread()
    local class = xDTaraZ.Guns.FindClass()
    if not class then return end
    local spread
    spread = xDTaraZ.Util.Hook("Spread", class.getSpread, function(self, ...)
        if xDTaraZ.Options.NoSpread then return 0 end
        return spread(self, ...)
    end)
end

function xDTaraZ.Guns.Restore()
    for name, base in pairs(xDTaraZ.State.WeaponSaved) do
        local data = xDTaraZ.Weapons[name]
        if data and xDTaraZ.Guns.Unfreeze(data) then
            if base.Spread then for k, v in pairs(base.Spread) do data.Spread[k] = v end end
            if base.Recoil then for k, v in pairs(base.Recoil) do data.Recoil[k] = v end end
            data.FireRate, data.Automatic = base.FireRate, base.Automatic
            if base.WalkSpeed then data.WalkSpeed = base.WalkSpeed end
        end
    end
end

function xDTaraZ.Guns.Rest()
    xDTaraZ.Guns.Signature = nil
    xDTaraZ.Guns.Restore()
end

xDTaraZ.Esp = { Count = 0, Decoded = {} }

---@return table?  JSON attribute decoded once per distinct raw string
function xDTaraZ.Esp.Attr(owner, key)
    local raw = owner:GetAttribute(key)
    if type(raw) ~= "string" then return nil end
    local cache = xDTaraZ.Esp.Decoded
    if cache[raw] == nil then cache[raw] = xDTaraZ.Util.Decode(raw) or false end
    return cache[raw] or nil
end

---@return string  " C4 Kit Helmet Scoped" style tags, "" when none
function xDTaraZ.Esp.Flags(owner)
    if not owner then return "" end
    local flags = {}
    local armor = xDTaraZ.Esp.Attr(owner, "Armor")
    local bomb = xDTaraZ.Esp.Attr(owner, "Slot5")
    if bomb and bomb.Weapon == "C4" then flags[#flags + 1] = "C4" end
    if owner:GetAttribute("HasDefuseKit") == true then table.insert(flags, "Kit") end
    if armor and type(armor.Type) == "string" and armor.Type:find("Helmet") then flags[#flags + 1] = "Helmet" end
    if owner:GetAttribute("IsSniperScoped") == true then flags[#flags + 1] = "Scoped" end
    return #flags > 0 and " " .. table.concat(flags, " ") or ""
end

---@return Model?  whatever aimbot, silent aim or ragebot is locked on
function xDTaraZ.Esp.Focus()
    local state = xDTaraZ.State
    return state.AimTarget or state.SilentTarget or state.RageTarget
end

---@return table[]  targets in the shape Library.Visuals expects; bots count as enemies
function xDTaraZ.Esp.Targets()
    local list = {}
    local mine = LocalPlayer:GetAttribute("Team")
    local focus = xDTaraZ.Esp.Focus()
    for _, model in ipairs(xDTaraZ.Target.Candidates()) do
        if tostring(model:GetAttribute("Dead")) == "true" then continue end
        local owner = xDTaraZ.Target.Owner(model)
        local equipped = owner and xDTaraZ.Util.Decode(owner:GetAttribute("CurrentEquipped"))
        local label = owner and owner.DisplayName or model.Name
        if equipped and equipped.Name then label = label .. " [" .. equipped.Name .. "]" end

        list[#list + 1] = {
            Model = model,
            Name = label .. xDTaraZ.Esp.Flags(owner),
            Health = tonumber(model:GetAttribute("Health")) or 100,
            MaxHealth = tonumber(model:GetAttribute("MaxHealth")) or 100,
            Friendly = mine ~= nil and owner ~= nil and owner:GetAttribute("Team") == mine,
            Root = model:FindFirstChild("HumanoidRootPart"),
            Color = model == focus and xDTaraZ.Config.EspFocusColor or nil,
        }
    end
    xDTaraZ.Esp.Count = #list
    return list
end

xDTaraZ.World = {}

function xDTaraZ.World.Step()
    local opts, state = xDTaraZ.Options, xDTaraZ.State
    if opts.Fullbright then
        state.LightSaved = state.LightSaved or { Lighting.Brightness, Lighting.ClockTime, Lighting.FogEnd, Lighting.GlobalShadows, Lighting.Ambient }
        Lighting.Brightness, Lighting.ClockTime, Lighting.FogEnd, Lighting.GlobalShadows = 2, 14, 1e6, false
        Lighting.Ambient = Color3.fromRGB(178, 178, 178)
    elseif state.LightSaved then
        Lighting.Brightness, Lighting.ClockTime, Lighting.FogEnd, Lighting.GlobalShadows, Lighting.Ambient = table.unpack(state.LightSaved)
        state.LightSaved = nil
    end
    if opts.NoFlash then xDTaraZ.World.ClearFlash() end
end

function xDTaraZ.World.ClearFlash()
    for _, effect in ipairs(Lighting:GetChildren()) do
        if effect.Name:lower():find("flash") and effect:IsA("PostEffect") then effect.Enabled = false end
    end
    local gui = LocalPlayer:FindFirstChild("PlayerGui")
    if not gui then return end
    for _, screen in ipairs(gui:GetChildren()) do
        if screen:IsA("ScreenGui") and screen.Name:lower():find("flash") then screen.Enabled = false end
    end
end

function xDTaraZ.World.OnDescendant(inst)
    if not xDTaraZ.Options.NoSmoke then return end
    if not (inst:IsA("ParticleEmitter") or inst:IsA("Smoke")) then return end
    local owner = inst:FindFirstAncestorOfClass("Model") or inst.Parent
    local name = (owner and owner.Name or ""):lower() .. inst.Name:lower()
    if name:find("smoke") then inst.Enabled = false end
end

function xDTaraZ.World.OnIdled()
    if not xDTaraZ.Options.AntiAfk then return end
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(vector2New())
    end)
end

function xDTaraZ.World.OnJump()
    if not xDTaraZ.Options.InfiniteJump or xDTaraZ.Player.Body() then return end
    local hum = xDTaraZ.Player.Humanoid()
    if hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
end

function xDTaraZ.World.SetCrouch(down)
    local state = xDTaraZ.State
    if state.HopCrouched == down then return end
    state.HopCrouched = down
    local controller = xDTaraZ.GameLib.Character
    if not controller then return end
    if not down and UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then return end
    controller.crouch(down)
end

function xDTaraZ.World.OnSpace(input, down, processed)
    if input.KeyCode ~= Enum.KeyCode.Space then return end
    if down and (processed or UserInputService:GetFocusedTextBox()) then return end
    xDTaraZ.State.SpaceHeld = down
end

function xDTaraZ.World.Hop()
    local opts, state = xDTaraZ.Options, xDTaraZ.State
    local body = opts.BunnyHop and state.SpaceHeld and xDTaraZ.Player.Alive() and xDTaraZ.Player.Body()
    if not body or UserInputService:GetFocusedTextBox() then
        xDTaraZ.World.SetCrouch(false)
        return
    end
    local controller = xDTaraZ.GameLib.Character
    local grounded = body.OnGround == true
    xDTaraZ.World.SetCrouch(opts.BunnyCrouch and not grounded)
    controller.jump(false)
    if not grounded or osClock() - state.HopAt < xDTaraZ.Config.HopGap then return end
    state.HopAt = osClock()
    controller.jump()
end

function xDTaraZ.World.HopStep()
    local ok, err = pcall(xDTaraZ.World.Hop)
    if ok then
        xDTaraZ.Faults.Clear("Bunny Hop")
    else
        xDTaraZ.Faults.Report("Bunny Hop", err, { "BunnyHop" }, xDTaraZ.World.Hop)
    end
end

function xDTaraZ.World.Rejoin()
    pcall(TeleportService.TeleportToPlaceInstance, TeleportService, game.PlaceId, game.JobId, LocalPlayer)
end

function xDTaraZ.World.ServerHop()
    pcall(TeleportService.Teleport, TeleportService, game.PlaceId, LocalPlayer)
end

xDTaraZ.Skins = { Map = {}, Applied = setmetatable({}, { __mode = "k" }), Catalog = nil, Rarity = {} }

function xDTaraZ.Skins.Folder()
    local assets = ReplicatedStorage:FindFirstChild("Assets")
    return assets and assets:FindFirstChild("Skins")
end

---@return string?  category name, nil = not a weapon look
function xDTaraZ.Skins.CategoryOf(name, kind)
    local mapped = xDTaraZ.Config.SkinKinds[kind]
    if mapped then return mapped end
    if kind ~= "Weapon" then return nil end
    local gun = xDTaraZ.Weapons[name]
    return gun and gun.Type or "Other"
end

function xDTaraZ.Skins.Build()
    local skins = xDTaraZ.Skins
    local folder = skins.Folder()
    local listing = xDTaraZ.Util.Decode(ReplicatedStorage:GetAttribute("AvaiableSkins")) or {}
    local ranks = xDTaraZ.Config.SkinRanks
    local catalog = {}
    for name, entries in pairs(listing) do
        if type(entries) ~= "table" or not (folder and folder:FindFirstChild(name)) then continue end
        local _, first = next(entries)
        local category = skins.CategoryOf(name, type(first) == "table" and first.type)
        if not category then continue end
        catalog[category] = catalog[category] or {}
        table.insert(catalog[category], name)
        skins.Rarity[name] = {}
        for skin, entry in pairs(entries) do
            skins.Rarity[name][skin] = type(entry) == "table" and ranks[entry.rarity] or 0
        end
    end
    for _, names in pairs(catalog) do table.sort(names) end
    skins.Catalog = catalog
end

---@return string[]  categories in display order
function xDTaraZ.Skins.Categories()
    if not xDTaraZ.Skins.Catalog then xDTaraZ.Skins.Build() end
    local list, seen = {}, {}
    for _, category in ipairs(xDTaraZ.Config.SkinOrder) do
        if xDTaraZ.Skins.Catalog[category] then list[#list + 1] = category seen[category] = true end
    end
    for category in pairs(xDTaraZ.Skins.Catalog) do
        if not seen[category] then list[#list + 1] = category end
    end
    if #list == 0 then list[1] = "-" end
    return list
end

function xDTaraZ.Skins.Items(category)
    if not xDTaraZ.Skins.Catalog then xDTaraZ.Skins.Build() end
    local names = xDTaraZ.Skins.Catalog[category or ""]
    return (names and #names > 0) and names or { "-" }
end

---@return string[]  rarest first
function xDTaraZ.Skins.List(weapon)
    local folder = xDTaraZ.Skins.Folder()
    local holder = folder and folder:FindFirstChild(weapon or "")
    if not holder then return { "-" } end
    local ranks = xDTaraZ.Skins.Rarity[weapon] or {}
    local names = {}
    for _, child in ipairs(holder:GetChildren()) do names[#names + 1] = child.Name end
    table.sort(names, function(a, b)
        local ra, rb = ranks[a] or 0, ranks[b] or 0
        if ra ~= rb then return ra > rb end
        return a < b
    end)
    return #names > 0 and names or { "-" }
end

---@param view string  "Camera" or "Character"
---@return Folder?     best wear available
function xDTaraZ.Skins.Source(weapon, skin, view)
    local folder = xDTaraZ.Skins.Folder()
    local paint = folder and folder:FindFirstChild(weapon) and folder[weapon]:FindFirstChild(skin)
    local side = paint and paint:FindFirstChild(view)
    if not side then return nil end
    for _, wear in ipairs(xDTaraZ.Config.SkinWears) do
        if side:FindFirstChild(wear) then return side[wear] end
    end
    return side:FindFirstChildOfClass("Folder")
end

function xDTaraZ.Skins.Paint(model, weapon, skin, view)
    local source = xDTaraZ.Skins.Source(weapon, skin, view)
    if not source then return false end
    local whole = source:FindFirstChild("SurfaceAppearance")
    local arms = xDTaraZ.Config.SkinArms
    for _, part in ipairs(model:GetDescendants()) do
        if not part:IsA("BasePart") then continue end
        local old = part:FindFirstChildOfClass("SurfaceAppearance")
        local look = source:FindFirstChild(part.Name)
        if not look and whole and old and not arms[part.Name] then look = whole end
        if not look then continue end
        if old then old:Destroy() end
        look:Clone().Parent = part
    end
    return true
end

function xDTaraZ.Skins.WeaponOf(model)
    local folder = xDTaraZ.Skins.Folder()
    if folder and folder:FindFirstChild(model.Name) then return model.Name end
    local equipped = xDTaraZ.Player.Equipped()
    return equipped and (equipped.Weapon or equipped.Name)
end

function xDTaraZ.Skins.Models()
    local list = {}
    for _, child in ipairs(Workspace.CurrentCamera:GetChildren()) do
        if child:IsA("Model") then list[#list + 1] = { child, "Camera" } end
    end
    local char = xDTaraZ.Player.Character()
    local folder = xDTaraZ.Skins.Folder()
    if char and folder then
        for _, child in ipairs(char:GetChildren()) do
            if child:IsA("Model") and folder:FindFirstChild(child.Name) then list[#list + 1] = { child, "Character" } end
        end
    end
    return list
end

function xDTaraZ.Skins.Step()
    local skins = xDTaraZ.Skins
    local on = xDTaraZ.Options.SkinChanger
    local glove = on and skins.Map[xDTaraZ.Config.GloveKey]
    local gloveSkin = glove and skins.Map[glove]
    for _, entry in ipairs(skins.Models()) do
        local model, view = entry[1], entry[2]
        local weapon = skins.WeaponOf(model)
        local skin = weapon and (on and skins.Map[weapon] or (skins.Applied[model] and "Stock"))
        local key = tostring(weapon) .. "|" .. tostring(skin) .. "|" .. tostring(gloveSkin)
        if skins.Applied[model] == key or not (skin or gloveSkin) then continue end
        if skin then skins.Paint(model, weapon, skin, view) end
        if gloveSkin and view == "Camera" then skins.Paint(model, glove, gloveSkin, view) end
        skins.Applied[model] = on and key or nil
    end
end

function xDTaraZ.Skins.Set(weapon, skin, quiet)
    if not weapon or weapon == "-" or not skin or skin == "-" then return false end
    local map, gloveKey = xDTaraZ.Skins.Map, xDTaraZ.Config.GloveKey
    local isGlove = xDTaraZ.Skins.Catalog and table.find(xDTaraZ.Skins.Catalog.Gloves or {}, weapon)
    if skin == "Default" then
        if map[weapon] == nil then return false end
        map[weapon] = nil
        if map[gloveKey] == weapon then map[gloveKey] = nil end
    else
        if map[weapon] == skin then return false end
        map[weapon] = skin
        if isGlove then map[gloveKey] = weapon end
    end
    if not quiet then xDTaraZ.Skins.Save() end
    return true
end

---@param pick fun(list: string[]): string  chooses one skin per item
---@return number  items changed
function xDTaraZ.Skins.SetAll(pick)
    local count = 0
    for _, category in ipairs(xDTaraZ.Skins.Categories()) do
        if category == "Gloves" then continue end
        for _, weapon in ipairs(xDTaraZ.Skins.Items(category)) do
            xDTaraZ.Skins.Set(weapon, pick(xDTaraZ.Skins.List(weapon)), true)
            count += 1
        end
    end
    xDTaraZ.Skins.Save()
    return count
end

function xDTaraZ.Skins.Save()
    if type(writefile) ~= "function" then return end
    local ok, err = pcall(function()
        if type(isfolder) == "function" and not isfolder(xDTaraZ.Config.SaveFolder) then makefolder(xDTaraZ.Config.SaveFolder) end
        writefile(xDTaraZ.Config.SkinFile, HttpService:JSONEncode(xDTaraZ.Skins.Map))
    end)
    if not ok then warn("[BloxStrike] skins save:", err) end
end

function xDTaraZ.Skins.Load()
    if type(readfile) ~= "function" or type(isfile) ~= "function" then return end
    local ok, raw = pcall(function() return isfile(xDTaraZ.Config.SkinFile) and readfile(xDTaraZ.Config.SkinFile) end)
    local map = ok and xDTaraZ.Util.Decode(raw)
    if type(map) == "table" then xDTaraZ.Skins.Map = map end
end

xDTaraZ.Economy = {}

function xDTaraZ.Economy.RedeemAll()
    local net = xDTaraZ.GameLib.Net
    local packet = net and net.Dashboard and net.Dashboard.RedeemCode
    if not packet then return 0 end
    local sent = 0
    for _, code in ipairs(xDTaraZ.Config.Codes) do
        if pcall(packet.Send, code) then sent += 1 end
        task.wait(xDTaraZ.Config.RedeemGap)
    end
    return sent
end

function xDTaraZ.Economy.HookBuys()
    local net = xDTaraZ.GameLib.Net
    local packet = net and net.Inventory and net.Inventory.BuyMenuPurchase
    if not packet then return end
    local original
    original = xDTaraZ.Util.Hook("Buy", packet.Send, function(payload, ...)
        if type(payload) == "table" and payload.Name and not xDTaraZ.State.Replaying then
            local list = xDTaraZ.State.Bought
            for index, entry in ipairs(list) do
                if entry.Name == payload.Name then table.remove(list, index) break end
            end
            list[#list + 1] = { Equipment = payload.Equipment, Path = payload.Path, Name = payload.Name }
        end
        return original(payload, ...)
    end)
end

function xDTaraZ.Economy.Rebuy()
    local net = xDTaraZ.GameLib.Net
    local packet = net and net.Inventory and net.Inventory.BuyMenuPurchase
    if not packet or #xDTaraZ.State.Bought == 0 then return 0 end
    xDTaraZ.State.Replaying = true
    local sent = 0
    for _, entry in ipairs(xDTaraZ.State.Bought) do
        if pcall(packet.Send, { Equipment = entry.Equipment, Path = entry.Path, Name = entry.Name }) then sent += 1 end
        task.wait(xDTaraZ.Config.RebuyGap)
    end
    xDTaraZ.State.Replaying = false
    return sent
end

function xDTaraZ.Economy.Step()
    if not xDTaraZ.Options.AutoRebuy or not xDTaraZ.Player.Alive() then return end
    if not xDTaraZ.Config.BuyStates[Workspace:GetAttribute("GameState")] then return end
    local round = tostring(Workspace:GetAttribute("MatchSessionId")) .. ":" .. tostring((Workspace:GetAttribute("TScore") or 0) + (Workspace:GetAttribute("CTScore") or 0))
    if xDTaraZ.State.LastRebuyRound == round then return end
    xDTaraZ.State.LastRebuyRound = round
    task.spawn(xDTaraZ.Economy.Rebuy)
end

function xDTaraZ.Economy.BoughtText()
    local names = {}
    for _, entry in ipairs(xDTaraZ.State.Bought) do names[#names + 1] = entry.Name end
    return #names > 0 and table.concat(names, ", ") or "-"
end

xDTaraZ.Spectators = {}

function xDTaraZ.Spectators.Text()
    local count = tonumber(LocalPlayer:GetAttribute("Spectators")) or 0
    if count == 0 then return "None" end
    local names = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer and tostring(player:GetAttribute("IsSpectating")) == "true" and tostring(player:GetAttribute("Dead")) == "true" then
            names[#names + 1] = player.DisplayName
        end
    end
    return count .. " watching" .. (#names > 0 and (" (dead: " .. table.concat(names, ", ") .. ")") or "")
end

xDTaraZ.Faults = { Streaks = {} }

function xDTaraZ.Faults.Clear(name)
    xDTaraZ.Faults.Streaks[name] = nil
end

function xDTaraZ.Faults.AnyOn(toggles)
    for _, key in ipairs(toggles) do
        if xDTaraZ.Options[key] then return true end
    end
    return false
end

---@param restore function?  the feature's own off path
function xDTaraZ.Faults.Halt(name, err, toggles, restore)
    warn("[BloxStrike] " .. name .. " stopped:", err)
    for _, key in ipairs(toggles) do
        xDTaraZ.Options[key] = false
    end
    if restore then xDTaraZ.Util.Try(name .. " restore", restore) end
    local halted = xDTaraZ.State.Halted
    halted[#halted + 1] = { name, tostring(err):match("^[^\n]*"), toggles }
end

---@param toggles string[]   turned off once the feature keeps failing; empty = keeps running, warns once per streak
---@param restore function?  run once when the feature is stopped
---@return boolean           true while the feature is stopped
function xDTaraZ.Faults.Report(name, err, toggles, restore)
    local now, streaks = osClock(), xDTaraZ.Faults.Streaks
    local streak = streaks[name]
    if not streak or (streak.Halted and xDTaraZ.Faults.AnyOn(toggles)) then
        streak = { Count = 0, First = now, Warned = false, Halted = false }
        streaks[name] = streak
    end
    streak.Count += 1
    if streak.Warned then return streak.Halted end
    if streak.Count < xDTaraZ.Config.MaxFails or now - streak.First < xDTaraZ.Config.FailWindow then return false end

    streak.Warned = true
    if #toggles == 0 then
        warn("[BloxStrike] " .. name .. " keeps failing:", err)
        return false
    end
    streak.Halted = true
    xDTaraZ.Faults.Halt(name, err, toggles, restore)
    return true
end

xDTaraZ.Scheduler = { Jobs = {} }

---@param toggles string[]   options the job serves; switched off if it keeps failing
---@param restore function?  the job's off path, run once if it gets stopped
function xDTaraZ.Scheduler.Every(name, interval, fn, toggles, restore)
    xDTaraZ.Scheduler.Jobs[name] = { Interval = interval, Fn = fn, Next = 0, Toggles = toggles, Restore = restore }
end

---@return boolean  a halted job runs again once one of its toggles is back on
function xDTaraZ.Scheduler.Resume(name, job)
    if not xDTaraZ.Faults.AnyOn(job.Toggles) then return false end
    job.Halted = false
    xDTaraZ.Faults.Clear(name)
    return true
end

function xDTaraZ.Scheduler.Boot()
    xDTaraZ:Connect(RunService.Heartbeat, function()
        local now = osClock()
        for name, job in pairs(xDTaraZ.Scheduler.Jobs) do
            if now < job.Next then continue end
            job.Next = now + job.Interval
            if job.Halted and not xDTaraZ.Scheduler.Resume(name, job) then continue end

            local ok, err = pcall(job.Fn)
            if ok then
                xDTaraZ.Faults.Clear(name)
            else
                job.Halted = xDTaraZ.Faults.Report(name, err, job.Toggles, job.Restore)
            end
        end
    end)
end

xDTaraZ.UI = { Labels = {} }

function xDTaraZ.UI.Detach(fn)
    return function(...)
        local packed = table.pack(...)
        task.defer(function()
            local ok, err = pcall(fn, table.unpack(packed, 1, packed.n))
            if not ok then warn("[BloxStrike] ui:", err) end
        end)
    end
end

function xDTaraZ.UI.Bind(widget, key)
    local function Apply(value) xDTaraZ.Options[key] = value end
    Apply(widget.Value)
    widget:OnChanged(Apply)
end

function xDTaraZ.UI.AddKeyMode(group, toggleIdx, keyIdx, default)
    group:AddDropdown(toggleIdx .. "Mode", { Text = T("Key mode", "โหมดปุ่ม"), Values = { "Hold", "Toggle", "Always" }, Default = default, Callback = function(mode)
        local picker = Library.Options[keyIdx]
        if picker then picker:SetValue({ picker.Value, mode }) end
    end })
end

---Toggle that keeps its info, so the library's "not supported" / "not available" notices name the feature instead of the idx.
function xDTaraZ.UI.NamedToggle(group, idx, info)
    local toggle = group:AddToggle(idx, info)
    toggle.Info = toggle.Info or info
    return toggle
end

function xDTaraZ.UI.BuildMain(window)
    window:AddTabSection(T("Main", "หลัก"))
    local tab = window:AddTab(T("Main", "หลัก"), "mushroom", T("Status and links", "สถานะและลิงก์"))

    local status = tab:AddLeftGroupbox(T("Status", "สถานะ"), "star")
    xDTaraZ.UI.Labels.Match = status:AddParagraph({ Title = T("Match", "แมตช์"), Content = "-" })
    xDTaraZ.UI.Labels.Combat = status:AddParagraph({ Title = T("Combat", "การต่อสู้"), Content = "-" })
    xDTaraZ.UI.Labels.Spectators = status:AddParagraph({ Title = T("Spectators", "คนดูเรา"), Content = "-" })
    xDTaraZ.UI.Labels.Esp = status:AddParagraph({ Title = T("ESP", "ESP"), Content = "-" })

    local quick = tab:AddRightGroupbox(T("Quick", "ด่วน"), "bomb")
    quick:AddButton({ Text = T("Panic - all off", "ฉุกเฉิน ปิดทั้งหมด"), Style = "Danger", Func = xDTaraZ.UI.Detach(function()
        for _, toggle in pairs(Library.Toggles) do
            if toggle.Value == true then toggle:SetValue(false) end
        end
    end) })

    local discord = tab:AddRightGroupbox(T("Discord", "ดิสคอร์ด"), "link")
    discord:AddLabel(xDTaraZ.Config.Discord)
    discord:AddButton({ Text = T("Copy Discord Link", "คัดลอกลิงก์ดิสคอร์ด"), Func = xDTaraZ.UI.Detach(function()
        if xDTaraZ.Util.Copy(xDTaraZ.Config.Discord) then
            Library:Notify(T("Discord", "ดิสคอร์ด"), T("Link copied", "คัดลอกลิงก์แล้ว"), 3, "Success")
        else
            Library:Notify(T("Discord", "ดิสคอร์ด"), xDTaraZ.Config.Discord, 6, "Info")
        end
    end) })

    local logBox = tab:AddRightGroupbox(T("Update Log", "อัปเดตล่าสุด"), "bell")
    for i = 1, math.min(2, #xDTaraZ.Config.UpdateLog) do
        local entry = xDTaraZ.Config.UpdateLog[i]
        logBox:AddParagraph({ Title = entry[1], Content = entry[2] })
    end
end

local priorities = { "Crosshair", "Distance", "Health" }

function xDTaraZ.UI.BuildAimbot(window)
    window:AddTabSection(T("Combat", "การต่อสู้"))
    local tab = window:AddTab(T("Aimbot", "เล็งอัตโนมัติ"), "crosshair", T("Locks your camera onto enemies", "ล็อคกล้องไปที่ศัตรู"))

    local main = tab:AddLeftGroupbox(T("Aimbot", "เล็งอัตโนมัติ"), "crosshair")
    main:AddToggle("Aimbot", { Text = T("Aimbot", "เล็งอัตโนมัติ"), Description = T("Locks your view onto the enemy in the FOV", "ล็อคกล้องไปที่ศัตรูในวง FOV") })
        :AddKeyPicker("AimbotKey", { Default = "E", Mode = "Hold" })
    xDTaraZ.UI.AddKeyMode(main, "Aimbot", "AimbotKey", "Hold")
    main:AddSlider("AimbotSmooth", { Text = T("Smoothness", "ความนุ่ม"), Description = T("1 = instant snap", "1 = หันทันที"), Min = 1, Max = 20, Default = 1, Rounding = 0 })
    main:AddCheckbox("AimbotSticky", { Text = T("Sticky target", "ล็อคเป้าเดิม"), Description = T("Keeps the same enemy until it is lost", "ไม่สลับเป้าจนกว่าเป้าเดิมจะหลุด"), Default = true })

    local target = tab:AddRightGroupbox(T("Aimbot Targeting", "การเลือกเป้า (เล็ง)"), "target")
    target:AddDropdown("AimbotBone", { Text = T("Aim part", "จุดที่เล็ง"), Values = { "Head", "Torso" }, Default = "Head" })
    target:AddDropdown("AimbotPriority", { Text = T("Priority", "เลือกเป้าตาม"), Values = priorities, Default = "Crosshair" })
    target:AddCheckbox("AimbotVisible", { Text = T("Visible only", "เฉพาะที่มองเห็น"), Default = true })
    target:AddSlider("AimbotFov", { Text = T("FOV", "ขนาดวง"), Min = 20, Max = 800, Default = 150, Suffix = "px" })
    target:AddToggle("AimbotShowFov", { Text = T("Show FOV circle", "แสดงวง FOV") })
    target:AddSlider("AimbotMaxDistance", { Text = T("Max distance", "ระยะสูงสุด"), Min = 50, Max = 3000, Default = 1500, Suffix = "m" })
end

function xDTaraZ.UI.BuildSilent(window)
    local tab = window:AddTab(T("Silent Aim", "ไซเลนต์เอม"), "bomb", T("Your shots find the enemy for you", "กระสุนวิ่งหาศัตรูเอง"))

    local main = tab:AddLeftGroupbox(T("Silent Aim", "ไซเลนต์เอม"), "bomb")
    xDTaraZ.UI.NamedToggle(main, "SilentAim", { Text = T("Silent aim", "ไซเลนต์เอม"), Description = T("Shots you fire go to the enemy in the FOV", "นัดที่ยิงพุ่งไปหาศัตรูในวง FOV"), Risky = true })
        :AddKeyPicker("SilentKey", { Default = "None", Mode = "Toggle" })
    main:AddSlider("SilentHitChance", { Text = T("Hit chance", "โอกาสโดน"), Description = T("Lower looks more legit", "ยิ่งต่ำยิ่งดูเนียน"), Min = 1, Max = 100, Default = 100, Rounding = 0, Suffix = "%" })
    main:AddSlider("SilentHeadChance", { Text = T("Headshot chance", "โอกาสเข้าหัว"), Description = T("The rest go to the body", "ที่เหลือเข้าลำตัว"), Min = 0, Max = 100, Default = 100, Rounding = 0, Suffix = "%" })
    Library.Compat.NeedCap("SilentAim", "HookFunction")

    local target = tab:AddRightGroupbox(T("Silent Targeting", "การเลือกเป้า (ไซเลนต์)"), "target")
    target:AddDropdown("SilentPriority", { Text = T("Priority", "เลือกเป้าตาม"), Values = priorities, Default = "Crosshair" })
    target:AddCheckbox("SilentVisible", { Text = T("Visible only", "เฉพาะที่มองเห็น"), Description = T("Off = also through walls", "ปิด = ยิงทะลุกำแพงด้วย"), Default = true })
    target:AddSlider("SilentFov", { Text = T("FOV", "ขนาดวง"), Min = 20, Max = 1000, Default = 220, Suffix = "px" })
    target:AddToggle("SilentShowFov", { Text = T("Show FOV circle", "แสดงวง FOV") })
    target:AddSlider("SilentMaxDistance", { Text = T("Max distance", "ระยะสูงสุด"), Min = 50, Max = 3000, Default = 2000, Suffix = "m" })
end

function xDTaraZ.UI.BuildTrigger(window)
    local tab = window:AddTab(T("Trigger & Rage", "ยิงออโต้ & เรจ"), "zap", T("Shoots for you", "ยิงให้อัตโนมัติ"))

    local trigger = tab:AddLeftGroupbox(T("Triggerbot", "ยิงอัตโนมัติ"), "zap")
    trigger:AddToggle("Triggerbot", { Text = T("Triggerbot", "ยิงอัตโนมัติ"), Description = T("Fires the moment an enemy is under your crosshair", "ยิงทันทีที่ศัตรูอยู่ใต้เป้า") })
        :AddKeyPicker("TriggerKey", { Default = "T", Mode = "Toggle" })
    xDTaraZ.UI.AddKeyMode(trigger, "Triggerbot", "TriggerKey", "Toggle")
    trigger:AddSlider("TriggerDelay", { Text = T("Reaction delay", "ดีเลย์ก่อนยิง"), Min = 0, Max = 400, Default = 0, Rounding = 0, Suffix = "ms" })
    trigger:AddSlider("TriggerHitChance", { Text = T("Fire chance", "โอกาสยิง"), Min = 1, Max = 100, Default = 100, Rounding = 0, Suffix = "%" })

    local rage = tab:AddRightGroupbox(T("Ragebot", "เรจบอท"), "bomb")
    xDTaraZ.UI.NamedToggle(rage, "Ragebot", { Text = T("Ragebot", "เรจบอท"), Description = T("Snaps to and kills any enemy it can reach on its own", "หันไปยิงศัตรูที่ยิงถึงเองทันที"), Risky = true })
        :AddKeyPicker("RageKey", { Default = "None", Mode = "Toggle" })
    rage:AddCheckbox("RageVisible", { Text = T("Visible only", "เฉพาะที่มองเห็น"), Description = T("Off = also through walls", "ปิด = ยิงทะลุกำแพงด้วย"), Default = true })
    rage:AddSlider("RageMaxDistance", { Text = T("Max distance", "ระยะสูงสุด"), Min = 50, Max = 3000, Default = 2000, Suffix = "m" })
    Library.Compat.NeedCap("Ragebot", "HookFunction")
end

function xDTaraZ.UI.BuildGuns(window)
    local tab = window:AddTab(T("Gun Mods", "ม็อดปืน"), "swords", T("Recoil, spread and fire rate", "แรงถีบ การกระจาย และอัตรายิง"))

    local mods = tab:AddLeftGroupbox(T("Gun Mods", "ม็อดปืน"), "swords")
    xDTaraZ.UI.NamedToggle(mods, "NoRecoil", { Text = T("No recoil", "ไม่มีแรงถีบ"), Description = T("Your view and bullets stay still while spraying", "จอและกระสุนนิ่งตอนกดยิงค้าง") })
    mods:AddSlider("RecoilKeep", { Text = T("Recoil left", "แรงถีบที่เหลือ"), Description = T("0 = none, 100 = normal", "0 = ไม่มีเลย, 100 = ปกติ"), Min = 0, Max = 100, Default = 0, Rounding = 0, Suffix = "%" })
    xDTaraZ.UI.NamedToggle(mods, "NoSpread", { Text = T("No spread", "ไม่มีการกระจาย"), Description = T("Every bullet lands on the crosshair", "ทุกนัดลงกลางเป้า") })
    xDTaraZ.UI.NamedToggle(mods, "FullAuto", { Text = T("Full auto", "ยิงรัวทุกปืน"), Description = T("Hold to spray with any gun", "กดค้างยิงรัวได้ทุกปืน") })
    Library.Compat.NeedCap("NoSpread", { "HookFunction", "Gc" })

    local rate = tab:AddRightGroupbox(T("Fire Rate", "อัตรายิง"), "zap")
    xDTaraZ.UI.NamedToggle(rate, "RapidFire", { Text = T("Rapid fire", "ยิงเร็ว"), Description = T("Shoots faster than normal", "ยิงเร็วกว่าปกติ"), Risky = true })
    rate:AddSlider("FireRateMult", { Text = T("Speed", "ความเร็ว"), Min = 1, Max = 4, Default = 1.5, Rounding = 1, Suffix = "x" })
    xDTaraZ.UI.NamedToggle(rate, "WeaponSpeed", { Text = T("Move speed", "เดินเร็ว"), Description = T("Run faster with any weapon", "วิ่งเร็วขึ้นทุกอาวุธ"), Risky = true })
    rate:AddSlider("WeaponSpeedMult", { Text = T("Move speed", "ความเร็วเดิน"), Min = 1, Max = 2, Default = 1.3, Rounding = 1, Suffix = "x" })
end

function xDTaraZ.UI.BuildVisuals(window)
    window:AddTabSection(T("Visuals", "การมองเห็น"))
    xDTaraZ.Util.Try("visuals tab", function()
        window:AddVisualsTab({ Provider = xDTaraZ.Esp.Targets, Preview = true })
    end)

    local tab = window:AddTab(T("World", "โลก"), "globe", T("Lighting, flash and smoke", "แสง แฟลช และควัน"))
    local world = tab:AddLeftGroupbox(T("World", "โลก"), "flower")
    world:AddToggle("Fullbright", { Text = T("Fullbright", "สว่างทั้งแมพ") })
    world:AddToggle("NoFlash", { Text = T("No flash", "กันแฟลช"), Description = T("Flashbangs do not blind you", "แฟลชไม่ทำให้ตาบอด") })
    world:AddToggle("NoSmoke", { Text = T("No smoke", "ไม่มีควัน"), Description = T("See through smoke grenades", "มองทะลุควัน") })

    local cam = tab:AddRightGroupbox(T("Camera", "กล้อง"), "eye")
    xDTaraZ.UI.NamedToggle(cam, "CameraFov", { Text = T("Custom FOV", "ปรับมุมมอง") })
    cam:AddSlider("CameraFovValue", { Text = T("FOV", "มุมมอง"), Min = 70, Max = 120, Default = 100, Rounding = 0 })
end

local skinTitles = {
    Pistol = { "Pistols", "ปืนพก", "coin" },
    SMG = { "SMGs", "ปืนกลมือ", "zap" },
    Rifle = { "Rifles", "ปืนไรเฟิล", "crosshair" },
    Sniper = { "Snipers", "สไนเปอร์", "target" },
    Heavy = { "Heavy", "ปืนหนัก", "bomb" },
    Shotgun = { "Shotguns", "ลูกซอง", "bomb" },
    ["Machine Gun"] = { "Machine Guns", "ปืนกล", "zap" },
    Knives = { "Knives", "มีด", "swords" },
    Gloves = { "Gloves", "ถุงมือ", "shield" },
    Grenades = { "Grenades", "ระเบิด", "bomb" },
    Gear = { "Gear", "อุปกรณ์", "gear" },
}

function xDTaraZ.UI.SkinGroup(tab, category, side)
    local title = skinTitles[category] or { category, category, "star" }
    local group = side == "Left" and tab:AddLeftGroupbox(T(title[1], title[2]), title[3]) or tab:AddRightGroupbox(T(title[1], title[2]), title[3])
    for _, weapon in ipairs(xDTaraZ.Skins.Items(category)) do
        if weapon == "-" then continue end
        local values = { "Default" }
        for _, skin in ipairs(xDTaraZ.Skins.List(weapon)) do values[#values + 1] = skin end
        group:AddDropdown("Skin_" .. weapon, { Text = weapon, Values = values, Default = xDTaraZ.Skins.Map[weapon] or "Default", Searchable = true, Callback = function(skin)
            xDTaraZ.Skins.Set(weapon, skin)
        end })
    end
end

---@param heights table  rows used per side so far, updated in place
function xDTaraZ.UI.PlaceSkinGroup(tab, category, heights)
    local side = heights.Left <= heights.Right and "Left" or "Right"
    local rows = 1
    for _, weapon in ipairs(xDTaraZ.Skins.Items(category)) do
        if weapon ~= "-" then rows += 1 end
    end
    if rows == 1 then return end
    heights[side] += rows
    xDTaraZ.Util.Try("skins " .. category, xDTaraZ.UI.SkinGroup, tab, category, side)
end

function xDTaraZ.UI.SyncSkins()
    for _, category in ipairs(xDTaraZ.Skins.Categories()) do
        for _, weapon in ipairs(xDTaraZ.Skins.Items(category)) do
            local picker = Library.Options["Skin_" .. weapon]
            if picker then picker:SetValue(xDTaraZ.Skins.Map[weapon] or "Default") end
        end
    end
end

function xDTaraZ.UI.BuildSkins(window)
    local tab = window:AddTab(T("Skins", "สกิน"), "star", T("Any skin, only on your screen", "ใส่สกินไหนก็ได้ เห็นแค่บนจอคุณ"))

    local main = tab:AddLeftGroupbox(T("Skin Changer", "เปลี่ยนสกิน"), "star")
    main:AddToggle("SkinChanger", { Text = T("Skin changer", "เปลี่ยนสกิน"), Description = T("Pick a skin below and it shows right away", "เลือกสกินด้านล่างแล้วขึ้นทันที") })
    main:AddButton({ Text = T("Rarest On Everything", "หายากสุดทุกอัน"), Style = "Primary", Func = xDTaraZ.UI.Detach(function()
        local count = xDTaraZ.Skins.SetAll(function(list) return list[1] end)
        xDTaraZ.UI.SyncSkins()
        Library:Notify("Skins", "Set " .. count .. " items", 3, "Success")
    end) })
    main:AddButton({ Text = T("Random", "สุ่ม"), Func = xDTaraZ.UI.Detach(function()
        xDTaraZ.Skins.SetAll(function(list) return list[math.random(#list)] end)
        xDTaraZ.UI.SyncSkins()
    end) }):AddButton({ Text = T("Reset All", "ล้างทั้งหมด"), Style = "Danger", Func = xDTaraZ.UI.Detach(function()
        table.clear(xDTaraZ.Skins.Map)
        xDTaraZ.Skins.Save()
        xDTaraZ.UI.SyncSkins()
    end) })

    local gear = { Knives = true, Gloves = true, Grenades = true, Gear = true }
    local heights = { Left = xDTaraZ.Config.SkinMainRows, Right = 0 }
    for _, category in ipairs({ "Knives", "Gloves", "Grenades", "Gear" }) do
        xDTaraZ.UI.PlaceSkinGroup(tab, category, heights)
    end

    local guns = window:AddTab(T("Gun Skins", "สกินปืน"), "crosshair", T("Skins for every gun", "สกินปืนทุกกระบอก"))
    heights = { Left = 0, Right = 0 }
    local ok, categories = pcall(xDTaraZ.Skins.Categories)
    for _, category in ipairs(ok and categories or {}) do
        if gear[category] then continue end
        xDTaraZ.UI.PlaceSkinGroup(guns, category, heights)
    end
end

function xDTaraZ.UI.BuildMisc(window)
    window:AddTabSection(T("Misc", "อื่นๆ"))
    local tab = window:AddTab(T("Misc", "อื่นๆ"), "gear", T("Buying, codes and utility", "ซื้อของ โค้ด และอื่นๆ"))

    local buy = tab:AddLeftGroupbox(T("Auto Buy", "ซื้ออัตโนมัติ"), "shop")
    xDTaraZ.UI.NamedToggle(buy, "AutoRebuy", { Text = T("Auto rebuy", "ซื้อซ้ำอัตโนมัติ"), Description = T("Buys your last loadout every round", "ซื้อชุดล่าสุดของคุณให้ทุกรอบ") })
    Library.Compat.NeedCap("AutoRebuy", "HookFunction")
    xDTaraZ.UI.Labels.Bought = buy:AddParagraph({ Title = T("Saved loadout", "ชุดที่จำไว้"), Content = "-" })
    buy:AddButton({ Text = T("Rebuy Now", "ซื้อซ้ำตอนนี้"), Style = "Primary", Func = xDTaraZ.UI.Detach(function()
        local sent = xDTaraZ.Economy.Rebuy()
        Library:Notify("Auto Buy", sent > 0 and ("Bought " .. sent .. " items") or "Buy something once first", 3, sent > 0 and "Success" or "Info")
    end) }):AddButton({ Text = T("Clear", "ล้าง"), Func = xDTaraZ.UI.Detach(function()
        table.clear(xDTaraZ.State.Bought)
    end) })

    local codes = tab:AddLeftGroupbox(T("Codes", "โค้ด"), "key")
    codes:AddButton({ Text = T("Redeem All Codes", "แลกโค้ดทั้งหมด"), Style = "Primary", Func = xDTaraZ.UI.Detach(function()
        local sent = xDTaraZ.Economy.RedeemAll()
        Library:Notify("Codes", "Sent " .. sent .. " codes (level 5+ needed)", 4, "Coin")
    end) })

    local util = tab:AddRightGroupbox(T("Utility", "อรรถประโยชน์"), "flower")
    util:AddToggle("InfiniteJump", { Text = T("Infinite jump", "กระโดดไม่จำกัด"), Description = T("Lobby only, use Bunny hop in rounds", "ใช้ได้เฉพาะล็อบบี้ ในรอบใช้บันนี่ฮอป"), Risky = true })
    util:AddToggle("BunnyHop", { Text = T("Bunny hop", "บันนี่ฮอป"), Description = T("Hold Space to keep hopping and carry your speed", "กด Space ค้างเพื่อกระโดดต่อเนื่องและรักษาความเร็ว"), Risky = true })
    util:AddCheckbox("BunnyCrouch", { Text = T("Crouch jump", "ย่อตอนลอย"), Description = T("Crouches in the air like a CS crouch jump", "ย่อตัวกลางอากาศแบบ crouch jump ใน CS"), Default = true })
    util:AddToggle("AntiAfk", { Text = T("Anti AFK", "กันหลุด AFK") })
    util:AddButton({ Text = T("Rejoin", "เข้าใหม่"), Func = xDTaraZ.UI.Detach(xDTaraZ.World.Rejoin) })
        :AddButton({ Text = T("Server Hop", "ย้ายเซิร์ฟ"), Func = xDTaraZ.UI.Detach(xDTaraZ.World.ServerHop) })
end

function xDTaraZ.UI.RefreshStatus()
    local labels, state = xDTaraZ.UI.Labels, xDTaraZ.State
    if labels.Match then
        labels.Match:SetText(("%s | %s | $%s"):format(tostring(Workspace:GetAttribute("Map") or "-"), tostring(Workspace:GetAttribute("GameState") or "-"), tostring(LocalPlayer:GetAttribute("Money") or 0)))
    end
    if labels.Combat then
        local target = state.RageTarget or state.AimTarget or state.SilentTarget
        target = target and target.Name or "none"
        labels.Combat:SetText(("Target: %s | Kills %s | Shots %d | Aimed %d"):format(target, tostring(LocalPlayer:GetAttribute("Kills") or 0), state.Shots, state.Redirected))
    end
    if labels.Spectators then labels.Spectators:SetText(xDTaraZ.Spectators.Text()) end
    if labels.Esp then
        local visuals = Library.Visuals
        labels.Esp:SetText((visuals and visuals:Get("Enabled")) and (xDTaraZ.Esp.Count .. " players") or "Off")
    end
    if labels.Bought then labels.Bought:SetText(xDTaraZ.Economy.BoughtText()) end
end

---Turns off what the scheduler halted and shows queued notices; runs on the UI pump, never on a game thread.
function xDTaraZ.UI.Drain()
    local state = xDTaraZ.State
    if not (state.Halted[1] or state.Notices[1]) then return end
    local stopped, notices = table.clone(state.Halted), table.clone(state.Notices)
    table.clear(state.Halted)
    table.clear(state.Notices)

    for _, halt in ipairs(stopped) do
        for _, key in ipairs(halt[3]) do
            local toggle = Library.Options[key]
            if toggle and toggle.Value == true then xDTaraZ.Util.Try("halt " .. key, toggle.SetValue, toggle, false) end
        end
        Library:Notify("Nova Hub", halt[1] .. " stopped: " .. halt[2], 6, "Error")
    end
    for _, notice in ipairs(notices) do
        Library:Notify(notice[1], notice[2], 5, "Warning")
    end
end

---Hooks go in the first time a feature that needs them is switched on, never at load.
function xDTaraZ.UI.HookOnDemand()
    local installers = {
        SilentAim = xDTaraZ.Silent.InstallHook,
        Ragebot = xDTaraZ.Silent.InstallHook,
        Triggerbot = xDTaraZ.Silent.InstallHook,
        NoRecoil = xDTaraZ.Guns.HookKick,
        CameraFov = xDTaraZ.Guns.BindFov,
        NoSpread = xDTaraZ.Guns.HookSpread,
        AutoRebuy = xDTaraZ.Economy.HookBuys,
    }
    for idx, install in pairs(installers) do
        local toggle = Library.Options[idx]
        if not toggle then continue end
        toggle:OnChanged(function(on)
            if on then task.defer(xDTaraZ.Util.Try, "hook " .. idx, install) end
        end)
    end

    local trigger = Library.Options.Triggerbot
    if trigger then
        trigger:OnChanged(function(on)
            if on then task.delay(xDTaraZ.Config.HookSettle, xDTaraZ.UI.WarnReducedTrigger) end
        end)
    end

    local recoil = Library.Options.NoRecoil
    if recoil then
        recoil:OnChanged(function(on)
            if on then task.defer(xDTaraZ.UI.WarnPartialRecoil) end
        end)
    end
end

---Triggerbot fires without the shoot hook; only shot pacing is less exact, so say so once.
function xDTaraZ.UI.WarnReducedTrigger()
    local state = xDTaraZ.State
    if state.Hooks.Shoot or state.TriggerWarned then return end
    state.TriggerWarned = true
    table.insert(state.Notices, { T("Triggerbot", "ยิงอัตโนมัติ"), T("Running in reduced mode on this executor; shot pacing is less exact", "ทำงานแบบจำกัดบน executor นี้ จังหวะยิงอาจไม่แม่นเท่าที่ควร") })
end

---No recoil still clears the gun's own recoil without hooks; the camera kick needs one, so say so once.
function xDTaraZ.UI.WarnPartialRecoil()
    local state = xDTaraZ.State
    if state.Hooks.Kick or state.RecoilWarned then return end
    state.RecoilWarned = true
    table.insert(state.Notices, { T("No recoil", "ไม่มีแรงถีบ"), T("Your view still kicks on this executor; bullet recoil is removed", "จอยังเด้งบน executor นี้ แต่แรงถีบกระสุนหายแล้ว") })
end

function xDTaraZ.UI.BlockMissing()
    local absent = xDTaraZ.GameLib.Missing
    local missing = {
        Net = xDTaraZ.GameLib.Net == nil and (absent.Remotes or true),
        Character = xDTaraZ.GameLib.Character == nil and (absent.CharacterController or true),
        Weapons = next(xDTaraZ.Weapons) == nil and (absent.Weapons or true),
        Skins = xDTaraZ.Skins.Folder() == nil and "Absent",
    }
    if missing.Skins then warn("[BloxStrike] Assets.Skins not found, the skin changer is blocked") end

    local unsupported = T("Not available on this executor", "ใช้กับ executor นี้ไม่ได้")
    local outdated = T("Changed by a game update, wait for a script update", "เกมอัปเดตแล้ว รอสคริปต์อัปเดต")
    for source, features in pairs(xDTaraZ.Config.ModuleFeatures) do
        local why = missing[source]
        if not why then continue end
        for _, idx in ipairs(features) do
            Library.Compat.Block(idx, why == "Absent" and outdated or unsupported)
        end
    end
end

function xDTaraZ.UI.Build()
    local window = Library.Window
    for _, build in ipairs({ xDTaraZ.UI.BuildMain, xDTaraZ.UI.BuildAimbot, xDTaraZ.UI.BuildSilent, xDTaraZ.UI.BuildTrigger, xDTaraZ.UI.BuildGuns, xDTaraZ.UI.BuildVisuals, xDTaraZ.UI.BuildSkins, xDTaraZ.UI.BuildMisc }) do
        xDTaraZ.Util.Try("build", build, window)
    end
    xDTaraZ.Util.Try("settings tab", function() window:AddSettingsTab() end)

    for key in pairs(xDTaraZ.Options) do
        local widget = Library.Options[key]
        if widget then xDTaraZ.Util.Try("bind " .. key, xDTaraZ.UI.Bind, widget, key) end
    end
    xDTaraZ.Util.Try("hooks", xDTaraZ.UI.HookOnDemand)
    xDTaraZ.Util.Try("missing modules", xDTaraZ.UI.BlockMissing)

    Library:Every(xDTaraZ.Config.StatusInterval, xDTaraZ.UI.RefreshStatus)
    Library:Every(xDTaraZ.Config.StatusInterval, xDTaraZ.UI.Drain)
end

function xDTaraZ.Boot()
    xDTaraZ.Util.Try("skins load", xDTaraZ.Skins.Load)
    xDTaraZ.Util.Try("combat", xDTaraZ.Combat.Start)
    xDTaraZ:Connect(LocalPlayer.Idled, xDTaraZ.World.OnIdled)
    xDTaraZ:Connect(UserInputService.JumpRequest, xDTaraZ.World.OnJump)
    xDTaraZ:Connect(RunService.Heartbeat, xDTaraZ.World.HopStep)
    xDTaraZ:Connect(UserInputService.InputBegan, function(input, processed) xDTaraZ.World.OnSpace(input, true, processed) end)
    xDTaraZ:Connect(UserInputService.InputEnded, function(input) xDTaraZ.World.OnSpace(input, false) end)
    xDTaraZ:Connect(Workspace.DescendantAdded, xDTaraZ.World.OnDescendant)

    xDTaraZ.Scheduler.Every("Gun Mods", 0.25, xDTaraZ.Guns.Step, { "NoSpread", "NoRecoil", "FullAuto", "RapidFire", "WeaponSpeed" }, xDTaraZ.Guns.Rest)
    xDTaraZ.Scheduler.Every("World", 0.2, xDTaraZ.World.Step, { "Fullbright", "NoFlash" }, xDTaraZ.World.Step)
    xDTaraZ.Scheduler.Every("Auto Rebuy", 0.5, xDTaraZ.Economy.Step, { "AutoRebuy" })
    xDTaraZ.Scheduler.Every("Skin Changer", 0.15, xDTaraZ.Skins.Step, { "SkinChanger" }, xDTaraZ.Skins.Step)
    xDTaraZ.Util.Try("scheduler", xDTaraZ.Scheduler.Boot)
end

function xDTaraZ:Unload()
    self.State.Alive = false
    xDTaraZ.Combat.Unload()
    for _, key in ipairs({ "NoRecoil", "NoSpread", "FullAuto", "RapidFire", "WeaponSpeed", "Fullbright", "CameraFov", "BunnyHop", "SkinChanger" }) do
        xDTaraZ.Options[key] = false
    end
    pcall(xDTaraZ.Guns.Restore)
    pcall(xDTaraZ.World.Step)
    pcall(xDTaraZ.World.SetCrouch, false)
    xDTaraZ.Guns.UnbindFov()
    pcall(xDTaraZ.Skins.Step)
    for _, conn in ipairs(self.State.Connections) do pcall(function() conn:Disconnect() end) end
    table.clear(self.State.Connections)
    if Library then xDTaraZ.Util.UnhookAll() end
    environment.BloxStrikeUnload = nil
end

---@return boolean  false when the menu could not be opened
local function BuildInterface()
    Library = xDTaraZ.Util.LoadLibrary(xDTaraZ.Config.UiSource)
    if not Library then return false end
    pcall(NovaBanner.Step, "UI library")
    xDTaraZ.Library = Library
    T = function(en, th) return Library:T(en, th) end
    local opened, err = pcall(Library.CreateWindow, Library, {
        Title = "Nova Hub",
        SubTitle = "BloxStrike by xDTaraZ",
        MenuKey = Enum.KeyCode.RightControl,
        ConfigFolder = xDTaraZ.Config.SaveFolder,
        Language = "Auto",
        Theme = "Nova",
        Intro = true,
        OnUnlocked = function()
            xDTaraZ.UI.Build()
            task.defer(xDTaraZ.Util.Try, "boot", xDTaraZ.Boot)
            task.defer(xDTaraZ.Util.Try, "autoload config", function() Library:LoadAutoloadConfig() end)
        end,
    })
    if not opened then
        xDTaraZ.Util.Alert("The menu failed to load on this executor: " .. tostring(err):match("^[^\n]*"), err)
        return false
    end
    Library:OnUnload(function() xDTaraZ:Unload() end)
    return true
end

environment.BloxStrikeUnload = function()
    if xDTaraZ.Library and not xDTaraZ.Library.Unloaded then
        xDTaraZ.Library:Unload()
    else
        xDTaraZ:Unload()
    end
end

pcall(NovaBanner.Step, "Systems")
if not BuildInterface() then return end
pcall(NovaBanner.Step, "Interface")
pcall(NovaBanner.Ready)]==]

NOVA_HUB_MODULES[10765298801] = [==[if not game:IsLoaded() then
    game.Loaded:Wait()
end

if game.GameId ~= 10765298801 then
    game:GetService("Players").LocalPlayer:Kick("Nova Hub: this script is for Stone Skipping only")
    return
end

local NovaBanner = {
    Print = print,
    Started = os.clock(),
    Last = os.clock(),
    Done = 0,
    Total = 4,
}

do
    local ok, renv = pcall(getrenv)
    if ok and type(renv) == "table" and type(renv.print) == "function" then
        NovaBanner.Print = renv.print
    end
end

function NovaBanner.Show()
    local ok, executor = pcall(identifyexecutor)
    if not ok or type(executor) ~= "string" then executor = "Unknown" end
    local rule = string.rep("=", 54)
    NovaBanner.Print(table.concat({
        "",
        [[
                                                                     @%@
                                                                    @*-#@
                                          @@@@@@@@@@@@@          @@#+.:-*%@@      @@
                                   @@@@@%##***********##%@@@@@   @*--:-==+*@@@@#*+==+*%@@
                              @@@@#+=+==---==++++++++++++**+++#@@@@@%==+@@@@#:.......:::=%@@
                          @@%#+---::-=++++++++++************+***++#%@%+@@@#:..-+*****+-:::+%@
                      @@@#=-::.:-==++++++++++*************************#@@+::=*-:.:+-::-+:.:=#@
                    @@%-:...:-===+++++**#################****************%%*+::::+*++::-+..:=#@
                 @@%*-:...:--==++*########**+==--===+**#######************+#%+::-*==-:::=-::=+@@
               @@%+=-::---===+*###%#+-:...................:=+#####***********#@+++==----==:-+*@@
             @@%++=-======+*###%+:............................::+####**********#@*+=----=---**@@
            @%=++=++++++*####=:...................................:+###**********%@==--==--+**@@
          @@*+++++++++*###*:........................................:-*##**********%*==+--=**@@@
         @%+++++++++*##%+:............................................::*##*********%%+--=##%@+%@
       @@#+++++++++###*:.....-+==+*#-......................:**+**#+:....:=###********%%+*##%@*:+@@
      @@*++++++++*###:......-+:.:-=*#*-..................:+*--+**#%*:.....:+##********#@#%%+:.:--+#@
     @@+++++++++*##+:......-*::-=++++*##:...............=#=-++****#%*:.....:-##********#@@@%+=-++#@@
    @@+=-=+++++*##+.......:*-:==++++++*##+............-*+-=+*******#%+:.....:-##********#@  @#=#@@
    @*=:.=++++*##-.......:*=:=++++++++*+*##=........:**==+**********##=:.....::*#********%@  @#@
   @#+-.-++*+*##=........*+-++++++*********##-....:+*==+*************#%-:.....:-**********%@
  @@++-=++***##+........*+-++++++***********#%*::=#+-+****************#%-:.....:=**********@@
 @@*++=++***###........+*-+++++***************###+-=+*****************###-:.....:+*********%@
 @%++=+*****#%:.......=*-++++*******************==+********************#%*-:....:-#********#@@
@@**+++****##+.......=*=+++*********************************************#%+::....:+*********@@
@%**++*****##-......=#=++**********#%#********************%%*************#%+:....:-#********%@
@%**++*****#*:.....-*=++**********#%%%#*****************#%%%**************#%=:....-********##@@
@#**++*****#*:....:*++************%%%%%%#*************#%%%%%#**************##-:...-+*******#*@@
@#**+******#+:...:#++************#%%%@@%%##*********#%%%%%@%#**************#%#-:..:+*+*****#*@@
@#**+******#+:..:#+=************#%%%%%*%%%##*******%%%%%%#%%##**************#%#::.-+*+*****#*@@
@#*********#+:.:+*=*************%%%%%+==*%%###***#%%%%%#++*%##***************#%*::-+*+*****#*@@
@%*#*******#*:.+*=*************%%%%%*=----*%###%%%%%%#+====*###**************##%+--*++****###@@
@%*#********#-:####***********#%%%%#=-::.::=###%%%%#+==--:::####************#%%%#==*+*****###@@
@@##********#+:#%%%%#********#%%%%%=--:....::=%%%%+==--::..:-%###********#%%%%%%#=#++*****##%@
@@###********#-=#%%%%%%##****%%%%%*=-:.......::-==---::.....:+###*****##%%%%%%%#++#++****###@@
 @%###*******##::=+%%%%%%%##%%%%%#=-:...........:::::........:####*#%%%%%%%%%*+=+*+=*****##%@
 @@###********#+:.:-=*%%%%%%%%%%%+--:.........................=###%%%%%%%%*+====*=.=****###@@
  @@###********#+:..::-=*%%%%%%%*=-:..:::-------------::::...::*#%%%%%%*+==---=*+-=+***###%@
   @%###*******#%#*+-..::-=#%@@%#**++==----------------===+++**#%@@@#+===---+*#*++****####@@
    @%###**#%#=::-=+##*##+-:...:::-=+**---*###*=--++++=--=++++=--:::-=+#%**#-:..:=#%##%##@@
    @@%#%#+:...:-=++=:..::=*####+#=:..=@#%:....%@*....*%%#...:--=*##+------=+=:::::-=#%%@@
     @@%*=--::::-*::::::-%=...:%@#:...:@@#.....%@+....=@@=.........:*#=-----=+=:::-==++%@@
  @@%+--+==--:::-#=-::::-%+....+%%-....%@#....:@@+....+@@:...:%%....-@*---==+*+:::-=+++*=+#@@
 @%-:-==*+==-:::-+*--:::-*#:...........*@#....:@@+....+@%..........-%%+---==+*=::-=+++#*=-:-*@@
 @@#+===+*+==-::-=*=--::-=%-......:....+@%:....:-....:#@*....=+:...-%#=--==+**-:--=++#*+=-=*%@
   @@#*=++#+=-:::-+*------#+....+@%....-@@#:.......::*@@+....+#=.:::=%+-===+#+-:-=++***++*%@@
     @@#+++*==-::-=*=-----+%:...-@@-::-=@%%@#+=--==*%@%%=:::::::::::#%+===+**----=++#**#%@@
     @@*-=+*+=-::-=*+=----=%#+*#%@%@@@@@#+-=*%%@@@%#*==*@@%%%##*+*#@@*====+#+-:-=++***++%@
    @@*--=+++===++*#*=------#%%#+=-----===============----==+*#%%%#+=-===+*#*+++=++**+==*@@
    @%=:-==+***%%@@@#=-=====++*##%%%@@@@@@@@@@%%@@@@@@@@@%%%##**++=======+*@@@@%#*+#+=--=#@
    @*:---==+*###%@@@#*#%%@%%%%%%######*****++++++++***######%%%%%%%%%%#*#%@@@####**+=---+@@
   @@+--=**#%@@@@@  @@@%%%%%%%#*******************************####%%%%%%@@@  @@@@@%#**=--+%@
    @@%%@@@@@          @@@@%%%%%%###**********************####%%%%%%%@@@          @@@@@%%%@@
      @@                  @@@@@%%%%%%%%%###############%%%%%%%%%@@@@@                  @@@
                               @@@@@@%%%%%%%%%%%%%%%%%%%%%%@@@@@
                                    @@@@@@@@@@@@@@@@@@@@@@@
]],
        [[
  __  __    _    ____  ___ ___    _   _ _   _ ____
 |  \/  |  / \  |  _ \|_ _/ _ \  | | | | | | | __ )
 | |\/| | / _ \ | |_) || | | | | | |_| | | | |  _ \
 | |  | |/ ___ \|  _ < | | |_| | |  _  | |_| | |_) |
 |_|  |_/_/   \_\_| \_\___\___/  |_| |_|\___/|____/
]],
        rule,
        "   STONE SKIPPING  //  by xDTaraZ  //  discord.gg/FHVfmeSceA",
        "   executor: " .. executor .. "   //   player: " .. game:GetService("Players").LocalPlayer.Name,
        rule,
    }, "\n"))
end

---@param label string  what just finished loading
function NovaBanner.Step(label)
    local now = os.clock()
    NovaBanner.Done = math.min(NovaBanner.Done + 1, NovaBanner.Total)
    local filled = math.floor(NovaBanner.Done / NovaBanner.Total * 20 + 0.5)
    NovaBanner.Print(string.format("[Nova Hub] [%s] %3d%%  %-24s +%dms",
        string.rep("#", filled) .. string.rep(".", 20 - filled),
        math.floor(NovaBanner.Done / NovaBanner.Total * 100), label, math.floor((now - NovaBanner.Last) * 1000)))
    NovaBanner.Last = now
end

function NovaBanner.Ready()
    local rule = string.rep("=", 54)
    NovaBanner.Print(table.concat({
        rule,
        string.format("   >> READY in %dms", math.floor((os.clock() - NovaBanner.Started) * 1000)),
        rule,
    }, "\n"))
end

pcall(NovaBanner.Show)
pcall(NovaBanner.Step, "Core")

if not LPH_OBFUSCATED then
    local function Passthrough(fn) return fn end
    LPH_JIT, LPH_JIT_MAX, LPH_NO_VIRTUALIZE = Passthrough, Passthrough, Passthrough
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local VirtualUser = game:GetService("VirtualUser")
local MarketplaceService = game:GetService("MarketplaceService")
local TeleportService = game:GetService("TeleportService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")
local StarterGui = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer
local osClock, osTime = os.clock, os.time
local vector3New = Vector3.new

local xDTaraZ = setmetatable({}, {
    __newindex = function(self, key, value)
        rawset(self, key, type(value) == "function" and LPH_JIT(value) or value)
    end,
})

xDTaraZ.Config = {
    Discord = "https://discord.gg/FHVfmeSceA",
    UpdateLog = {
        { "2026-10-04", "Auto Pet Index\nAuto Fuse (Golden & Diamond)\nRemoved keybinds from auto features" },
        { "2026-10-03", "Classic Nova Hub UI is back\nBetter executor support\nBug fixes & better UI" },
    },
    UiSource = "NovaHub://embedded-ui",
    SaveFolder = "Stone Skipping",
    LoadTimeout = 30,
    RequireTimeout = 3,
    MaxFailures = 5,
    FailWindow = 10,
    AlertTries = 20,
    AlertDelay = 0.5,
    TickDelay = 0.2,
    GcRescan = 5,
    WalkTimeout = 15,
    ArriveRadius = 4,
    StallTime = 1.5,
    StallDistance = 1,
    HopStep = 6,
    HopDelay = 0.1,
    HopRange = 24,
    StandHeight = 3,
    PracticeStart = 4,
    ZoneBench = 120,
    CapNames = { Gc = "getgc", Upvalues = "getupvalue" },
    GatedFeatures = { "AutoFarm", "AutoBuyStone", "AutoRebirth", "AutoTravel", "AutoHatch", "AutoInventoryHatch", "AutoPotions", "AutoClaim", "AutoPetIndex", "AutoFuse" },
    StandLane = 10,
    ThrowTimeout = 30,
    ThrowStart = 3,
    PageTimeout = 10,
    OfflinePage = "OfflineEarningsOverlay",
    HatchTimeout = 15,
    HatchCooldown = 0.8,
    HatchBurst = 25,
    RevealClickGap = 0.35,
    ClaimInterval = 20,
    IndexInterval = 15,
    FuseInterval = 5,
    FuseGap = 1,
    FuseNext = { Normal = "Golden", Golden = "Diamond" },
    BuyInterval = 3,
    PotionInterval = 10,
    RebirthInterval = 15,
    RateWindow = 120,
    RejoinDelay = 5,
    Codes = { "10KCCU", "SECRET", "WORLD4", "WORLD3", "5KCCU", "WELCOME" },
    PotionKinds = { "Skill", "Win", "Luck" },
    Needs = {
        AutoFarm = { "Worlds.Definitions", "Balance.TrainingPasses" },
        AutoBuyStone = { "Balance.Stones", "Worlds.Definitions" },
        AutoTravel = { "Worlds.Definitions" },
        AutoClaim = { "Balance.GiftRewards", "Balance.DailyRewards.Rewards" },
        AutoPetIndex = { "Balance.PetIndex.MilestoneStep" },
        AutoFuse = { "Balance.PetFusion.EnabledVariants" },
    },
}

xDTaraZ.State = {
    Alive = true,
    Connections = {},
    Requests = {},
    Messages = {},
    Failures = {},
    Halted = {},
    Status = "Idle",
    Throws = 0,
    WinsEarned = 0,
    SkillEarned = 0,
    EarnLog = {},
    Last = {},
    Benched = {},
    ZonesByWorld = {},
    LastHatch = 0,
    OwnedPasses = {},
    Opt = {
        AutoFarm = false,
        FarmMode = "Smart",
        TrainZone = "Best",
        AutoBuyStone = false,
        StoneReserve = 0,
        AutoRebirth = false,
        AutoHatch = false,
        HatchEgg = "Best",
        HatchReserve = 0,
        AutoInventoryHatch = false,
        AutoPotions = false,
        Potions = {},
        AutoClaim = false,
        AutoPetIndex = false,
        AutoFuse = false,
        FuseVariants = { Golden = true, Diamond = true },
        FuseMode = "Upgrades only",
        AutoTravel = false,
        SpeedOn = false,
        WalkSpeed = 32,
        InfJump = false,
        AntiAfk = false,
        AutoRejoin = false,
    },
}

local Config, State = xDTaraZ.Config, xDTaraZ.State

xDTaraZ.GameLib = {}

---@return Instance?  the network folder; a renamed one is found by its Request + Event remotes
function xDTaraZ.GameLib.FindNetwork()
    local named = ReplicatedStorage:FindFirstChild("SkippingNetwork")
    if named then return named end
    for _, remote in ipairs(ReplicatedStorage:GetDescendants()) do
        if remote.Name == "Request" and remote:IsA("RemoteEvent") and remote.Parent:FindFirstChild("Event") then return remote.Parent end
    end
    return ReplicatedStorage:WaitForChild("SkippingNetwork", Config.LoadTimeout)
end

local Network = xDTaraZ.GameLib.FindNetwork()
local Shared = ReplicatedStorage:WaitForChild("Shared", Config.LoadTimeout)
local SharedConfig = Shared and Shared:WaitForChild("Config", Config.LoadTimeout)

xDTaraZ.GameLib.Request = Network and Network:WaitForChild("Request", Config.LoadTimeout)
xDTaraZ.GameLib.Event = Network and Network:WaitForChild("Event", Config.LoadTimeout)

---@return ModuleScript?  Shared.Config.<name>, or the first module with that name anywhere under Shared
function xDTaraZ.GameLib.Module(name)
    local direct = SharedConfig and SharedConfig:FindFirstChild(name)
    if direct then return direct end
    local found = Shared and Shared:FindFirstChild(name, true)
    return found and found:IsA("ModuleScript") and found or nil
end

---@return boolean, any  ok + module, retried from an identity-2 thread when the executor can really switch
function xDTaraZ.GameLib.RequireAsGame(module)
    local done, ok, loaded = false, false, nil
    task.spawn(function()
        pcall(setthreadidentity, 2)
        local read, identity = pcall(getthreadidentity)
        if read and identity == 2 then
            ok, loaded = pcall(require, module)
        end
        done = true
    end)
    local deadline = osClock() + Config.RequireTimeout
    while not done and osClock() < deadline do
        task.wait()
    end
    return ok, loaded
end

---@return table?  nil when it is missing or this executor can't require it
function xDTaraZ.GameLib.Require(module)
    if not module then return nil end
    local ok, loaded = pcall(require, module)
    if ok then return loaded end
    local okAgain, again = xDTaraZ.GameLib.RequireAsGame(module)
    if okAgain then return again end
    warn("[StoneSkipping] require", module:GetFullName(), loaded)
    return nil
end

local GameLib = xDTaraZ.GameLib
GameLib.Balance = GameLib.Require(GameLib.Module("GameBalance"))
GameLib.Worlds = GameLib.Require(GameLib.Module("Worlds"))
GameLib.Ready = GameLib.Balance ~= nil and GameLib.Worlds ~= nil and GameLib.Request ~= nil

---@return table  option idx -> GameLib paths that are gone
function xDTaraZ.GameLib.Missing()
    local missing = {}
    for idx, paths in pairs(Config.Needs) do
        for _, path in ipairs(paths) do
            local node = GameLib
            for part in path:gmatch("[^.]+") do
                node = type(node) == "table" and node[part] or nil
            end
            if node == nil then
                missing[idx] = missing[idx] or {}
                table.insert(missing[idx], path)
            end
        end
    end
    return missing
end

xDTaraZ.StoneById = {}
do
    for _, stone in ipairs(GameLib.Balance and GameLib.Balance.Stones or {}) do
        xDTaraZ.StoneById[stone.Id] = stone
    end
end

xDTaraZ.WorldById = {}
do
    for _, world in ipairs(GameLib.Worlds and GameLib.Worlds.Definitions or {}) do
        xDTaraZ.WorldById[world.Id] = world
    end
end

function xDTaraZ.Format(n)
    n = tonumber(n) or 0
    local units = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc" }
    local i = 1
    while math.abs(n) >= 1000 and i < #units do
        n /= 1000
        i += 1
    end
    return (i == 1 and "%d%s" or "%.2f%s"):format(n, units[i])
end

function xDTaraZ:Notify(msg)
    table.insert(State.Messages, msg)
end

function xDTaraZ.Try(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then warn("[StoneSkipping]", err) end
    return ok, err
end

xDTaraZ.Util = {}

---@return string?, string?  body, or nil + why every transport failed
function xDTaraZ.Util.HttpGet(url)
    if url == "NovaHub://embedded-ui" then return NOVA_HUB_UI_SOURCE end
    local ok, body = pcall(function() return game:HttpGet(url) end)
    if ok and type(body) == "string" then return body end

    local send = request or http_request or (syn and syn.request) or (http and http.request)
    if not send then return nil, tostring(body) end
    local sent, response = pcall(send, { Url = url, Method = "GET" })
    if not sent then return nil, tostring(response) end
    if type(response) ~= "table" or response.StatusCode ~= 200 or type(response.Body) ~= "string" then
        return nil, "HTTP " .. tostring(type(response) == "table" and response.StatusCode)
    end
    return response.Body
end

---Shows a Roblox notification even when the menu never loaded; SetCore fails for a while after joining.
function xDTaraZ.Util.Alert(text, detail)
    warn("[StoneSkipping] menu:", text, detail or "")
    task.spawn(function()
        for _ = 1, Config.AlertTries do
            if pcall(StarterGui.SetCore, StarterGui, "SendNotification", { Title = "Nova Hub", Text = text, Duration = 10 }) then return end
            task.wait(Config.AlertDelay)
        end
    end)
end

---@return table?  the UI library, nil after telling the player why
function xDTaraZ.Util.LoadLibrary()
    local body, err = xDTaraZ.Util.HttpGet(Config.UiSource)
    if not body or not body:sub(-64):find("return Library%s*$") then
        xDTaraZ.Util.Alert("Could not download the menu. Check your connection and run it again.", err or "truncated body")
        return nil
    end
    local chunk, compileErr = loadstring(body)
    if not chunk then
        xDTaraZ.Util.Alert("The menu failed to load on this executor: " .. tostring(compileErr))
        return nil
    end
    local ok, library = pcall(chunk)
    if ok and type(library) == "table" then return library end
    xDTaraZ.Util.Alert("The menu failed to load on this executor: " .. tostring(library))
    return nil
end

---@param caps string|string[]  Library.Compat cap names
---@return boolean              false until the menu library is loaded
function xDTaraZ:Can(caps)
    return self.Compat ~= nil and self.Compat.Has(caps) == true
end

---@return string?  the game piece that failed to load, nil when all of them did
function xDTaraZ.GameLib.MissingPart()
    if not GameLib.Request then return "the game's request remote" end
    if not GameLib.Balance then return "the GameBalance module" end
    if not GameLib.Worlds then return "the Worlds module" end
    return nil
end

---@return string?, string?  English and Thai reason the farm features can't run here; nil when they can
function xDTaraZ:Unsupported()
    local part = GameLib.MissingPart()
    if part then
        return ("Can't load %s on this executor"):format(part), ("โหลด %s บน executor นี้ไม่ได้"):format(part)
    end
    if not self.Compat then return nil end
    local supported, cap = self.Compat.Has({ "Gc", "Upvalues" })
    if supported then return nil end
    local name = Config.CapNames[cap] or cap
    return ("Needs %s"):format(name), ("ต้องใช้ %s"):format(name)
end

function xDTaraZ:Character()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildOfClass("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not (hum and hrp and hum.Health > 0) then return nil end
    return char, hum, hrp
end

function xDTaraZ:Send(action, ...)
    GameLib.Request:FireServer(action, ...)
end

xDTaraZ.Game = {}

xDTaraZ.Game.GetUpvalue = getupvalue or debug.getupvalue

function xDTaraZ.Game.Controller()
    local cached = xDTaraZ.Game.Cached
    if cached and type(rawget(cached, "BeginThrow")) == "function" then return cached end
    if not xDTaraZ:Can({ "Gc", "Upvalues" }) or osClock() - (State.Last.GcScan or -math.huge) < Config.GcRescan then return nil end
    State.Last.GcScan = osClock()
    for _, t in ipairs(getgc(true)) do
        if type(t) == "table" and type(rawget(t, "RedeemCode")) == "function" and type(rawget(t, "BeginThrow")) == "function" then
            local canThrow = xDTaraZ.Game.GetUpvalue(t.BeginThrow, 1)
            if type(canThrow) ~= "function" then return nil end
            xDTaraZ.Game.Cached = t
            xDTaraZ.Game.CanThrow = canThrow
            return t
        end
    end
    return nil
end

---@return table?  live player profile kept by the game client
function xDTaraZ.Game.Profile()
    if not xDTaraZ.Game.Controller() then return nil end
    local profile = xDTaraZ.Game.GetUpvalue(xDTaraZ.Game.CanThrow, 3)
    return type(profile) == "table" and profile or nil
end

function xDTaraZ.Game.World()
    local world = Workspace:FindFirstChild("SkippingWorlds")
    local id = LocalPlayer:GetAttribute("SkippingWorld") or "World1"
    return world and world:FindFirstChild(id), id
end

function xDTaraZ.Game.Activity()
    return LocalPlayer:GetAttribute("SkippingActivity") or "Idle"
end

function xDTaraZ.Game.Wins()
    local data = xDTaraZ.Game.Profile()
    return data and tonumber(data.Wins) or 0
end

function xDTaraZ.Game.RebirthLevel(data)
    local listed = tonumber(data.NextRebirthLevel)
    if listed then return listed end
    local rebirths = tonumber(data.Rebirths) or 0
    local hud = LocalPlayer.PlayerGui:FindFirstChild("SkippingHUD")
    local overlay = hud and hud:FindFirstChild("RebirthOverlay", true)
    local label = overlay and overlay:FindFirstChild("Requirement", true)
    local shown = label and label:IsA("TextLabel") and tonumber((label.Text:gsub(",", "")):match("/%s*Level%s*(%d+)"))
    if shown then return shown end
    local reb = GameLib.Balance.Rebirth
    local need = reb.RequiredLevels[rebirths + 1]
    if need then return need end
    local count = #reb.RequiredLevels
    return math.min(reb.RequiredLevels[count] + (rebirths + 1 - count) * 20, reb.MaxRequiredLevel)
end

function xDTaraZ.Game.HatchActive()
    local hud = LocalPlayer.PlayerGui:FindFirstChild("SkippingHUD")
    return hud ~= nil and hud:GetAttribute("HatchActive") == true
end

---@return boolean  false while the offline earnings page still blocks a throw
function xDTaraZ.Game.ClosePages()
    local hud = LocalPlayer.PlayerGui:FindFirstChild("SkippingHUD")
    if not hud then return true end
    local frames = hud:FindFirstChild("Frames")
    if frames and xDTaraZ:Can("Connections") then
        for _, overlay in ipairs(frames:GetChildren()) do
            if not (overlay:IsA("GuiObject") and overlay.Visible) then continue end
            local close = overlay:FindFirstChild("Close", true)
            if close and close:IsA("GuiButton") then
                for _, conn in ipairs(xDTaraZ.Compat.Api.GetConnections(close.Activated)) do conn:Fire() end
            end
        end
    end
    return xDTaraZ.Game.ClearOffline(hud:FindFirstChild(Config.OfflinePage, true))
end

---The offline page has no close button, only the free claim and a paid x10, so the free claim is what hides it.
function xDTaraZ.Game.ClearOffline(page)
    if not (page and page:IsA("GuiObject") and page.Visible) then return true end
    State.Status = "Claiming offline earnings"
    xDTaraZ:Send("ClaimOffline")

    local deadline = osClock() + Config.PageTimeout
    while page.Visible and osClock() < deadline do
        if not xDTaraZ.Scheduler.Live() then return false end
        task.wait(0.25)
    end
    if page.Visible then State.Status = "Offline earnings page is stuck open" end
    return not page.Visible
end

---@return boolean  false once this client refuses virtual clicks; it is not tried again
function xDTaraZ.Game.ClickReveal()
    if State.RevealBroken then return false end
    local cam = Workspace.CurrentCamera
    local size = cam and cam.ViewportSize or Vector2.new(800, 600)
    local ok, err = pcall(function()
        VirtualInputManager:SendMouseButtonEvent(size.X / 2, size.Y / 2, 0, true, game, 0)
        task.wait(0.05)
        VirtualInputManager:SendMouseButtonEvent(size.X / 2, size.Y / 2, 0, false, game, 0)
    end)
    if ok then return true end
    State.RevealBroken = true
    warn("[StoneSkipping] reveal click:", err)
    return false
end

---Clicks through the hatch reveal, or just waits it out when clicks don't work here.
function xDTaraZ.Game.SkipReveal()
    local deadline = osClock() + Config.HatchTimeout
    while xDTaraZ.Game.HatchActive() and osClock() < deadline and xDTaraZ.Scheduler.Live() do
        xDTaraZ.Game.ClickReveal()
        task.wait(Config.RevealClickGap)
    end
end

xDTaraZ.Move = {}

function xDTaraZ.Move.FlatGap(from, pos)
    return (from - vector3New(pos.X, from.Y, pos.Z)).Magnitude
end

---@return boolean  false on timeout or as soon as the character stops making progress
function xDTaraZ.Move.WalkTo(pos)
    local _, hum, hrp = xDTaraZ:Character()
    if not hum then return false end
    local deadline = osClock() + Config.WalkTimeout
    local mark, markedAt = hrp.Position, osClock()
    repeat
        hum:MoveTo(pos)
        task.wait(0.25)
        if xDTaraZ.Move.FlatGap(hrp.Position, pos) <= Config.ArriveRadius then return true end
        if (hrp.Position - mark).Magnitude > Config.StallDistance then
            mark, markedAt = hrp.Position, osClock()
        elseif osClock() - markedAt > Config.StallTime then
            return false
        end
    until osClock() > deadline or not xDTaraZ.Scheduler.Live() or hum.Health <= 0
    return false
end

---Covers the last few studs a walk can't (raised stands, fences) in short CFrame steps.
function xDTaraZ.Move.HopTo(pos)
    local _, _, hrp = xDTaraZ:Character()
    if not hrp or (hrp.Position - pos).Magnitude > Config.HopRange then return false end
    for _ = 1, math.ceil(Config.HopRange / Config.HopStep) + 1 do
        local offset = pos - hrp.Position
        if offset.Magnitude <= Config.ArriveRadius or not xDTaraZ.Scheduler.Live() then break end
        hrp.CFrame += offset.Magnitude > Config.HopStep and offset.Unit * Config.HopStep or offset
        hrp.AssemblyLinearVelocity = Vector3.zero
        task.wait(Config.HopDelay)
    end
    return xDTaraZ.Move.FlatGap(hrp.Position, pos) <= Config.ArriveRadius
end

---@return number?  x of the open lane in front of the training stands
function xDTaraZ.Move.LaneX()
    local spot = xDTaraZ.Move.ZoneSpot("TrainingZone")
    return spot and spot.X + Config.StandLane
end

function xDTaraZ.Move.Travel(pos)
    if xDTaraZ.Game.Activity() == "Practice" then
        xDTaraZ:Send("StopPractice")
        task.wait(0.3)
    end
    local _, _, hrp = xDTaraZ:Character()
    local laneX = xDTaraZ.Move.LaneX()
    if hrp and laneX and math.abs(hrp.Position.Z - pos.Z) > Config.ArriveRadius then
        xDTaraZ.Move.WalkTo(vector3New(laneX, pos.Y, hrp.Position.Z))
        xDTaraZ.Move.WalkTo(vector3New(laneX, pos.Y, pos.Z))
    end
    if xDTaraZ.Move.WalkTo(pos) then return true end
    return xDTaraZ.Move.HopTo(pos)
end

function xDTaraZ.Move.LaunchSpot()
    local world = xDTaraZ.Game.World()
    local zone = world and world:FindFirstChild("LaunchZone")
    if not zone then return nil end
    return zone.Position + vector3New(0, 2, 0)
end

function xDTaraZ.Move.ZoneSpot(name)
    local world = xDTaraZ.Game.World()
    local folder = world and world:FindFirstChild("TrainingZones")
    local zone = folder and folder:FindFirstChild(name)
    local stand = zone and zone:FindFirstChild("TrainingStand")
    if not stand then return nil end
    return stand.Position + vector3New(0, stand.Size.Y / 2 + Config.StandHeight, 0)
end

function xDTaraZ.Move.EggSpot(eggId)
    local world = xDTaraZ.Game.World()
    local displays = world and world:FindFirstChild("EggShop") and world.EggShop:FindFirstChild("Displays")
    local egg = displays and displays:FindFirstChild(eggId)
    local anchor = egg and egg:FindFirstChild("PromptAnchor", true)
    if not anchor then return nil end
    return anchor.WorldPosition, egg
end

function xDTaraZ.Move.ApplySpeed()
    local _, hum = xDTaraZ:Character()
    if not hum then return end
    if State.Opt.SpeedOn then
        State.BaseSpeed = State.BaseSpeed or hum.WalkSpeed
        hum.WalkSpeed = State.Opt.WalkSpeed
    elseif State.BaseSpeed then
        hum.WalkSpeed = State.BaseSpeed
        State.BaseSpeed = nil
    end
end

xDTaraZ.Train = {}

function xDTaraZ.Train.OwnsPass(passId)
    if not passId then return true end
    local known = State.OwnedPasses[passId]
    if known ~= nil then return known end
    local ok, owns = pcall(MarketplaceService.UserOwnsGamePassAsync, MarketplaceService, LocalPlayer.UserId, passId)
    State.OwnedPasses[passId] = ok and owns or false
    return State.OwnedPasses[passId]
end

function xDTaraZ.Train.CheckPasses()
    local passes = GameLib.Balance and GameLib.Balance.TrainingPasses
    for _, passId in pairs(passes or {}) do
        xDTaraZ.Train.OwnsPass(passId)
    end
end

---Each world carries its own bonuses and rebirth gates (World2 needs 30 rebirths for the zone World1 opens at 6).
---@return table[]  zones of the current world, best bonus first; empty until the world data is readable
function xDTaraZ.Train.Zones()
    local _, worldId = xDTaraZ.Game.World()
    local cached = State.ZonesByWorld[worldId]
    if cached then return cached end
    local world = xDTaraZ.WorldById[worldId]
    local practice = world and world.Practice
    local zones = {}
    if not practice then return zones end
    for name, bonus in pairs(practice.ZoneBonuses) do
        table.insert(zones, {
            Name = name,
            Bonus = bonus,
            Rebirths = practice.ZoneRequiredRebirths[name] or 0,
            Pass = GameLib.Balance.TrainingPasses[name],
        })
    end
    table.sort(zones, function(a, b) return a.Bonus > b.Bonus end)
    State.ZonesByWorld[worldId] = zones
    return zones
end

---@return string  the picked zone, or the best one this world has that needs no pass you lack, no more rebirths and did not just refuse training
function xDTaraZ.Train.BestZone()
    local data = xDTaraZ.Game.Profile()
    local rebirths = data and tonumber(data.Rebirths) or 0
    local best
    for _, zone in ipairs(xDTaraZ.Train.Zones()) do
        if rebirths < zone.Rebirths or not xDTaraZ.Move.ZoneSpot(zone.Name) then continue end
        if (State.Benched[zone.Name] or 0) > osClock() or not xDTaraZ.Train.OwnsPass(zone.Pass) then continue end
        if zone.Name == State.Opt.TrainZone then return zone.Name end
        best = best or zone.Name
    end
    return best or "TrainingZone"
end

---Waits for the game to start practice after reaching a stand; a stand that never starts it is benched and the character steps off so the next visit touches it fresh.
---@return boolean  true once the activity is Practice
function xDTaraZ.Train.AwaitPractice(name, spot)
    local deadline = osClock() + Config.PracticeStart
    while xDTaraZ.Game.Activity() ~= "Practice" do
        if not xDTaraZ.Scheduler.Live() then return false end
        if osClock() > deadline then
            State.Benched[name] = osClock() + Config.ZoneBench
            State.Status = "Stand did not start training, resetting"
            local laneX = xDTaraZ.Move.LaneX()
            local lane = laneX and vector3New(laneX, spot.Y, spot.Z)
            if lane and not xDTaraZ.Move.WalkTo(lane) then xDTaraZ.Move.HopTo(lane) end
            return false
        end
        task.wait(0.2)
    end
    return true
end

function xDTaraZ.Train.Step()
    local name = xDTaraZ.Train.BestZone()
    local spot = xDTaraZ.Move.ZoneSpot(name)
    if not spot then return end
    State.Status = "Training at " .. name:gsub("TrainingZone_?", ""):gsub("^$", "Basic")
    if xDTaraZ.Game.Activity() == "Practice" then return end
    if not xDTaraZ.Move.Travel(spot) then return end
    xDTaraZ.Train.AwaitPractice(name, spot)
end

xDTaraZ.Throw = {}

---@return boolean  true once the player stands idle on the launch zone with no game page in the way
function xDTaraZ.Throw.Ready()
    local spot = xDTaraZ.Move.LaunchSpot()
    if not spot then return false end
    State.Status = "Walking to throw zone"
    if not xDTaraZ.Move.Travel(spot) then return false end

    local deadline = osClock() + Config.ThrowTimeout
    while not xDTaraZ.Game.CanThrow() do
        if osClock() > deadline or not xDTaraZ.Scheduler.Live() then return false end
        task.wait(0.2)
    end
    xDTaraZ.Shop.IdleTasks()
    return xDTaraZ.Game.ClosePages()
end

function xDTaraZ.Throw.Once()
    local ctrl = xDTaraZ.Game.Controller()
    if not (ctrl and xDTaraZ.Throw.Ready()) then return false end

    local before = xDTaraZ.Game.Wins()
    State.Status = "Throwing"
    task.spawn(ctrl.BeginThrow)
    local started = osClock() + Config.ThrowStart
    while xDTaraZ.Game.Activity() ~= "Throw" do
        if osClock() > started or not xDTaraZ.Scheduler.Live() then return false end
        task.wait(0.1)
    end

    local deadline = osClock() + Config.ThrowTimeout
    while xDTaraZ.Game.Activity() == "Throw" and osClock() < deadline do
        if not xDTaraZ.Scheduler.Live() then return false end
        task.wait(0.25)
    end

    local got = xDTaraZ.Game.Wins() - before
    State.Throws += 1
    if got > 0 then
        State.WinsEarned += got
        table.insert(State.EarnLog, { osClock(), got })
    end
    return true
end

---@return boolean  next world still locked and a throw can now reach its portal
function xDTaraZ.Throw.PortalReachable()
    local data = xD