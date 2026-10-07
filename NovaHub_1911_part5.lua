turn tonumber(xDTaraZ.Data.Read("Money")) or 0
end

function xDTaraZ.Data.Rebirth()
    return tonumber(xDTaraZ.Data.Read("Rebirth")) or 0
end

function xDTaraZ.Data.Rolls()
    return tonumber(xDTaraZ.Data.Read("Rolls")) or 0
end

function xDTaraZ.Data.Token(name)
    local total = 0
    for _, entry in pairs(xDTaraZ.Data.Table("Inventory")) do
        if type(entry) == "table" and entry.name == name then
            total += tonumber(entry.amount) or 0
        end
    end
    return total
end

---@return table<string, boolean>  unit keys placed on the plot or in the tower team
function xDTaraZ.Data.BusyKeys()
    local busy = {}
    for _, slot in pairs(xDTaraZ.Data.Table("Slots")) do
        if type(slot) == "table" and slot.unitId then busy[tostring(slot.unitId)] = true end
    end
    for _, key in pairs(xDTaraZ.Data.Table("TowerTeam")) do
        if type(key) == "string" then busy[key] = true end
    end
    return busy
end

---@return table[]  items of one kind {Key, Name, Amount}
function xDTaraZ.Data.ItemsOfKind(kind)
    local items = {}
    for key, entry in pairs(xDTaraZ.Data.Table("Inventory")) do
        if type(entry) == "table" and entry.name then
            local config = GameLib.EntryOf(entry.name)
            if config and config.kind == kind then
                items[#items + 1] = { Key = tostring(key), Name = entry.name, Amount = tonumber(entry.amount) or 1 }
            end
        end
    end
    return items
end

---@return number  unit entries the server counts against Unit Storage, trade reservations included
function xDTaraZ.Data.UnitCount()
    local count = 0
    for _, entry in pairs(xDTaraZ.Data.Table("Inventory")) do
        local config = type(entry) == "table" and entry.name and GameLib.EntryOf(entry.name)
        if config and config.kind == "Unit" then count += 1 end
    end
    local trade = xDTaraZ.Data.Read("PendingTrade")
    if type(trade) == "table" and not trade.applied then count += tonumber(trade.reservedUnits) or 0 end
    return count
end

xDTaraZ.Data.UnitCache = { At = -1, List = {} }

---@return table[]  owned units, plotted first then by income; shared snapshot
function xDTaraZ.Data.Units()
    local cache = xDTaraZ.Data.UnitCache
    local now = osClock()
    if now - cache.At < xDTaraZ.Config.SnapshotTtl then return cache.List end
    cache.List = xDTaraZ.Data.ScanUnits()
    cache.At = now
    return cache.List
end

function xDTaraZ.Data.Invalidate()
    xDTaraZ.Data.UnitCache.At = -1
end

function xDTaraZ.Data.IncomeAt(config, attrs, level)
    local probe = table.clone(attrs)
    probe.level = level
    local ok, value = pcall(config.income, probe)
    return ok and tonumber(value) or 0
end

function xDTaraZ.Data.LevelPrice(unit, level)
    local probe = table.clone(unit.Attr)
    probe.level = level
    local ok, price = pcall(GameLib.UnitUtil.GetLevelPrice, unit.Name, probe)
    return ok and tonumber(price) or math.huge
end

function xDTaraZ.Data.ScanUnits()
    local busy = xDTaraZ.Data.BusyKeys()
    local units = {}
    for key, entry in pairs(xDTaraZ.Data.Table("Inventory")) do
        if type(entry) == "table" and entry.name then
            local config = GameLib.EntryOf(entry.name)
            if config and config.kind == "Unit" then
                local attrs = type(entry.attributes) == "table" and entry.attributes or {}
                local rarity = config.rarity
                if type(config.getRarity) == "function" then
                    local ok, dynamic = pcall(config.getRarity, attrs)
                    if ok and dynamic then rarity = dynamic end
                end
                local income, potential = 0, 0
                if type(config.income) == "function" then
                    local ok, value = pcall(config.income, attrs)
                    if ok then income = tonumber(value) or 0 end
                    potential = xDTaraZ.Data.IncomeAt(config, attrs, 1)
                end
                local chance
                if type(config.chance) == "function" and not config.limited and (tonumber(entry.amount) or 1) == 1 then
                    local ok, value = pcall(config.chance, attrs)
                    chance = ok and tonumber(value) or nil
                end
                key = tostring(key)
                units[#units + 1] = {
                    Key = key,
                    Name = entry.name,
                    Attr = attrs,
                    Rarity = rarity,
                    Grade = attrs.grade,
                    Trait = attrs.trait,
                    Mutation = attrs.mutation,
                    Level = tonumber(attrs.level) or 1,
                    Locked = attrs.locked == true,
                    Busy = busy[key] == true,
                    Value = income,
                    Potential = potential,
                    Chance = chance,
                }
            end
        end
    end
    table.sort(units, function(a, b)
        if a.Busy ~= b.Busy then return a.Busy end
        return a.Value > b.Value
    end)
    return units
end

xDTaraZ.Player = { Client = LocalPlayer }

function xDTaraZ.Player:Bind(character)
    self.Character = character
    self.Humanoid = character:WaitForChild("Humanoid", xDTaraZ.Config.LoadTimeout)
    self.Root = character:WaitForChild("HumanoidRootPart", xDTaraZ.Config.LoadTimeout)
end

xDTaraZ.Scheduler = { Jobs = {}, Booted = false }

---@param interval number|function  seconds, or a getter read every tick
---@param toggles string[]?          options switched off when the job keeps failing
function xDTaraZ.Scheduler.Every(name, interval, fn, toggles)
    xDTaraZ.Scheduler.Jobs[name] = { Interval = interval, Fn = fn, Last = 0, Running = false, Fails = 0, Toggles = toggles or {} }
end

---@return boolean  one of the job's toggles is on
function xDTaraZ.Scheduler.Wanted(job)
    for _, idx in ipairs(job.Toggles) do
        if xDTaraZ.Options[idx] == true then return true end
    end
    return false
end

function xDTaraZ.Scheduler.Run(name, job)
    local ok, err = pcall(job.Fn)
    job.Running = false
    if ok then
        job.Fails, job.FailSince = 0, nil
        return
    end

    job.Fails += 1
    job.FailSince = job.FailSince or osClock()
    if job.Fails == 1 then warn("[AnimeDice] job " .. name .. " failing:", err) end

    local config = xDTaraZ.Config
    if job.Fails < config.JobFailLimit or osClock() - job.FailSince < config.JobFailWindow then return end
    if not xDTaraZ.Scheduler.Wanted(job) then return end
    job.Halted = true
    table.insert(xDTaraZ.State.Halted, { name, job.Toggles, tostring(err):match("^[^\n]*") })
end

function xDTaraZ.Scheduler.Step()
    local now = osClock()
    for name, job in pairs(xDTaraZ.Scheduler.Jobs) do
        local interval = type(job.Interval) == "function" and job.Interval() or job.Interval
        if not job.Running and not job.Halted and now - job.Last >= interval then
            job.Last = now
            job.Running = true
            task.spawn(xDTaraZ.Scheduler.Run, name, job)
        end
    end
end

function xDTaraZ.Scheduler.Resume(idx)
    for _, job in pairs(xDTaraZ.Scheduler.Jobs) do
        if table.find(job.Toggles, idx) then
            job.Halted, job.Fails, job.FailSince = false, 0, nil
        end
    end
end

function xDTaraZ.Scheduler.Boot()
    if xDTaraZ.Scheduler.Booted then return end
    xDTaraZ.Scheduler.Booted = true
    xDTaraZ:Connect(RunService.Heartbeat, xDTaraZ.Scheduler.Step)
end

xDTaraZ.AntiAfk = { Connection = nil }

function xDTaraZ.AntiAfk.OnIdled()
    if not xDTaraZ.Options.AntiAfk then return end
    VirtualUser:CaptureController()
    VirtualUser:ClickButton2(Vector2.zero)
end

function xDTaraZ.AntiAfk.Start()
    xDTaraZ.Options.AntiAfk = true
    if not xDTaraZ.AntiAfk.Connection then
        xDTaraZ.AntiAfk.Connection = xDTaraZ:Connect(LocalPlayer.Idled, xDTaraZ.AntiAfk.OnIdled)
    end
end

function xDTaraZ.AntiAfk.Stop()
    xDTaraZ.Options.AntiAfk = false
end

xDTaraZ.Cutscene = { Saved = nil }

function xDTaraZ.Cutscene.Skip() end

function xDTaraZ.Cutscene.Apply()
    local controller = GameLib.RollController
    if type(controller) ~= "table" or table.isfrozen(controller) or xDTaraZ.Cutscene.Saved then return end
    local original = rawget(controller, "PlayCutscene")
    if type(original) ~= "function" then return end
    xDTaraZ.Cutscene.Saved = original
    rawset(controller, "PlayCutscene", xDTaraZ.Cutscene.Skip)
end

function xDTaraZ.Cutscene.Restore()
    local controller = GameLib.RollController
    local original = xDTaraZ.Cutscene.Saved
    if not original then return end
    if rawget(controller, "PlayCutscene") == xDTaraZ.Cutscene.Skip then rawset(controller, "PlayCutscene", original) end
    xDTaraZ.Cutscene.Saved = nil
end

function xDTaraZ.Cutscene.Step()
    if xDTaraZ.Options.DisableCutscene then xDTaraZ.Cutscene.Apply() else xDTaraZ.Cutscene.Restore() end
end

xDTaraZ.Move = { NoClipConnection = nil, FlyConnection = nil, FlyForce = nil, JumpConnection = nil }

function xDTaraZ.Move.ApplyWalkSpeed()
    local hum = xDTaraZ.Player.Humanoid
    if hum and xDTaraZ.Options.WalkSpeed then hum.WalkSpeed = xDTaraZ.Options.WalkSpeedValue end
end

function xDTaraZ.Move.SpeedStart()
    xDTaraZ.Options.WalkSpeed = true
    xDTaraZ.Move.ApplyWalkSpeed()
end

function xDTaraZ.Move.SpeedStop()
    xDTaraZ.Options.WalkSpeed = false
    local hum = xDTaraZ.Player.Humanoid
    if hum then hum.WalkSpeed = 16 end
end

function xDTaraZ.Move.JumpStart()
    xDTaraZ.Options.InfiniteJump = true
    if xDTaraZ.Move.JumpConnection then return end
    xDTaraZ.Move.JumpConnection = xDTaraZ:Connect(UserInputService.JumpRequest, function()
        local hum = xDTaraZ.Player.Humanoid
        if xDTaraZ.Options.InfiniteJump and hum then hum:ChangeState(Enum.HumanoidStateType.Jumping) end
    end)
end

function xDTaraZ.Move.JumpStop()
    xDTaraZ.Options.InfiniteJump = false
end

function xDTaraZ.Move.NoClipStart()
    xDTaraZ.Options.NoClip = true
    if xDTaraZ.Move.NoClipConnection then return end
    xDTaraZ.Move.NoClipConnection = xDTaraZ:Connect(RunService.Stepped, function()
        local char = xDTaraZ.Player.Character
        if not (xDTaraZ.Options.NoClip and char) then return end
        for _, part in ipairs(char:GetChildren()) do
            if part:IsA("BasePart") and part.CanCollide then part.CanCollide = false end
        end
    end)
end

function xDTaraZ.Move.NoClipStop()
    xDTaraZ.Options.NoClip = false
    local char = xDTaraZ.Player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hrp then hrp.CanCollide = true end
end

function xDTaraZ.Move.FlyStart()
    if xDTaraZ.Move.FlyForce then return end
    local hrp = xDTaraZ.Player.Root
    if not hrp then return end
    xDTaraZ.Options.Fly = true

    local force = Instance.new("BodyVelocity")
    force.MaxForce = Vector3.one * 9e9
    force.Velocity = Vector3.zero
    force.Parent = hrp
    xDTaraZ.Move.FlyForce = force

    if xDTaraZ.Move.FlyConnection then return end
    xDTaraZ.Move.FlyConnection = xDTaraZ:Connect(RunService.RenderStepped, function()
        local bv = xDTaraZ.Move.FlyForce
        if not (xDTaraZ.Options.Fly and bv) then return end
        local look = Workspace.CurrentCamera.CFrame
        local dir = Vector3.zero
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir += look.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir -= look.LookVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir -= look.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir += look.RightVector end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir += Vector3.yAxis end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then dir -= Vector3.yAxis end
        bv.Velocity = dir.Magnitude > 0 and dir.Unit * xDTaraZ.Options.FlySpeed or Vector3.zero
    end)
end

function xDTaraZ.Move.FlyStop()
    xDTaraZ.Options.Fly = false
    if xDTaraZ.Move.FlyForce then
        xDTaraZ.Move.FlyForce:Destroy()
        xDTaraZ.Move.FlyForce = nil
    end
end

function xDTaraZ.Move.Rebind()
    xDTaraZ.Move.ApplyWalkSpeed()
    if xDTaraZ.Options.Fly then
        xDTaraZ.Move.FlyForce = nil
        xDTaraZ.Move.FlyStart()
    end
end

xDTaraZ.Roll = { Status = "Off", Session = 0, LastRolls = nil, StorageFull = false, NextAt = 0 }

---@return number  seconds the server holds a roll back after an accepted one
function xDTaraZ.Roll.Duration()
    local buffs = GameLib.Buffs
    if not buffs then return 0 end
    local ok, duration = pcall(buffs.GetBuff, "Roll Duration")
    return ok and tonumber(duration) or 0
end

---@return boolean, number, number  room left for a roll, units held, units the server allows
function xDTaraZ.Roll.Room()
    local buffs = GameLib.Buffs
    if not buffs then return true, 0, 0 end
    local okStorage, storage = pcall(buffs.GetBuff, "Unit Storage")
    local okRolls, rolls = pcall(buffs.GetBuff, "Rolls")
    storage, rolls = tonumber(okStorage and storage), tonumber(okRolls and rolls)
    if not storage or not rolls then return true, 0, 0 end
    local limit = storage + rolls - 1
    local held = xDTaraZ.Data.UnitCount()
    return held < limit, held, limit
end

function xDTaraZ.Roll.SetStorageFull(full, held, limit)
    if full == xDTaraZ.Roll.StorageFull then return end
    xDTaraZ.Roll.StorageFull = full
    if not full then return end
    table.insert(xDTaraZ.State.Notices, {
        "Unit storage full",
        string.format("%d/%d units. Rolling paused until you sell or clear some.", held, limit),
    })
end

function xDTaraZ.Roll.Once()
    return xDTaraZ.Net.Invoke("RollService.RF.RollDice")
end

function xDTaraZ.Roll.ResetCounter()
    xDTaraZ.Roll.Session = 0
    xDTaraZ.Roll.LastRolls = xDTaraZ.Data.Rolls()
end

function xDTaraZ.Roll.Track()
    local rolls = xDTaraZ.Data.Rolls()
    if xDTaraZ.Roll.LastRolls and rolls > xDTaraZ.Roll.LastRolls then
        xDTaraZ.Roll.Session += rolls - xDTaraZ.Roll.LastRolls
    end
    xDTaraZ.Roll.LastRolls = rolls
end

function xDTaraZ.Roll.Step()
    xDTaraZ.Roll.Track()
    if not xDTaraZ.Options.AutoRoll then
        xDTaraZ.Roll.Status = "Off"
        xDTaraZ.Roll.StorageFull = false
        return
    end
    local hasRoom, held, limit = xDTaraZ.Roll.Room()
    xDTaraZ.Roll.SetStorageFull(not hasRoom, held, limit)
    if not hasRoom then
        xDTaraZ.Roll.Status = string.format("Storage full %d/%d, paused", held, limit)
        return
    end
    xDTaraZ.Roll.Status = "Rolling"
    if osClock() < xDTaraZ.Roll.NextAt then return end
    local ok, reply = xDTaraZ.Roll.Once()
    if ok and reply ~= nil then
        xDTaraZ.Roll.NextAt = osClock() + math.max(xDTaraZ.Roll.Duration() - xDTaraZ.Config.RollLead, 0)
    end
end

function xDTaraZ.Roll.GetStatus()
    return string.format("%s · session %s · total %s", xDTaraZ.Roll.Status,
        Util.FormatNumber(xDTaraZ.Roll.Session), Util.FormatNumber(xDTaraZ.Data.Rolls()))
end

xDTaraZ.Plot = { Status = "Off" }

function xDTaraZ.Plot.CollectNow()
    for index, slot in pairs(xDTaraZ.Data.Table("Slots")) do
        local balance = type(slot) == "table" and tonumber(slot.balance) or 0
        if balance > 0 then
            xDTaraZ.Net.Fire("PlotService.RE.CollectBalance", tonumber(index))
            xDTaraZ.Economy.Collected += balance
        end
    end
end

---@return number  highest level whose price still pays back within the payback limit
function xDTaraZ.Plot.WorthLevel(unit, mult)
    local config = GameLib.EntryOf(unit.Name)
    if not config then return unit.Level end
    local gain = (xDTaraZ.Data.IncomeAt(config, unit.Attr, 2) - unit.Potential) * mult
    if gain <= 0 then return unit.Level end
    local cap = math.min(xDTaraZ.Options.LevelTarget, 500)
    local level = 1
    while level < cap and xDTaraZ.Data.LevelPrice(unit, level) / gain <= xDTaraZ.Options.LevelPayback do
        level += 1
    end
    return level
end

---@return number  income this unit reaches on the plot once cheap levels are bought
function xDTaraZ.Plot.Score(unit, mult)
    local config = GameLib.EntryOf(unit.Name)
    if not config then return unit.Value end
    local level = math.max(unit.Level, xDTaraZ.Plot.WorthLevel(unit, mult))
    return level == unit.Level and unit.Value or xDTaraZ.Data.IncomeAt(config, unit.Attr, level)
end

---@return table[]  { slot, placeKey } swaps that raise plot income, weakest slot first
function xDTaraZ.Plot.PlanSwaps()
    local slots = xDTaraZ.Data.Table("Slots")
    local byKey = {}
    for _, unit in ipairs(xDTaraZ.Data.Units()) do byKey[unit.Key] = unit end

    local mult = xDTaraZ.Economy.Multiplier()
    local current, placed = {}, {}
    for index, slot in pairs(slots) do
        if type(slot) ~= "table" then continue end
        local unit = slot.unitId and byKey[tostring(slot.unitId)]
        current[#current + 1] = { tonumber(index), unit and xDTaraZ.Plot.Score(unit, mult) or 0 }
        if unit then placed[unit.Key] = true end
    end
    table.sort(current, function(a, b) return a[2] < b[2] end)

    local bench = {}
    for _, unit in ipairs(xDTaraZ.Data.Units()) do
        if not placed[unit.Key] then bench[#bench + 1] = unit end
    end
    table.sort(bench, function(a, b) return a.Potential > b.Potential end)
    for index = #bench, #current * 2 + 1, -1 do bench[index] = nil end
    for _, unit in ipairs(bench) do unit.Score = xDTaraZ.Plot.Score(unit, mult) end
    table.sort(bench, function(a, b) return a.Score > b.Score end)

    local swaps = {}
    for index, slot in ipairs(current) do
        local candidate = bench[index]
        if not candidate or candidate.Score < slot[2] * xDTaraZ.Config.SwapMargin then break end
        swaps[#swaps + 1] = { slot[1], candidate.Key }
    end
    return swaps
end

---@return number  units moved onto the plot
function xDTaraZ.Plot.EquipBest()
    if xDTaraZ.Options.PlacementMode ~= "Potential" then
        xDTaraZ.Net.Fire("PlotService.RE.EquipBest")
        return 0
    end
    local moved = 0
    for _, swap in ipairs(xDTaraZ.Plot.PlanSwaps()) do
        if moved >= xDTaraZ.Config.SwapsPerPass then break end
        xDTaraZ.Net.Fire("PlotService.RE.CollectBalance", swap[1])
        local ok, held = xDTaraZ.Net.Invoke("UnitService.RF.Equip", swap[2])
        if not (ok and held) then break end
        task.wait(xDTaraZ.Config.PlaceDelay)
        xDTaraZ.Net.Fire("PlotService.RE.InteractSlot", swap[1])
        moved += 1
        task.wait(xDTaraZ.Config.PlaceDelay)
    end
    if moved > 0 then xDTaraZ.Data.Invalidate() end
    xDTaraZ.Plot.Status = moved > 0 and (moved .. " better units placed") or "Best units placed"
    return moved
end

function xDTaraZ.Plot.CollectStep()
    if xDTaraZ.Options.AutoCollect then xDTaraZ.Plot.CollectNow() end
end

function xDTaraZ.Plot.EquipStep()
    if xDTaraZ.Options.EquipBestUnitsAuto then xDTaraZ.Plot.EquipBest() end
end

---@return table[]  { slot, price, payback } for plotted units, fastest payback first
function xDTaraZ.Plot.LevelCandidates()
    local byKey = {}
    for _, unit in ipairs(xDTaraZ.Data.Units()) do byKey[unit.Key] = unit end
    local minRarity = GameLib.RarityOrder(xDTaraZ.Options.LevelMinRarity)
    local mult = xDTaraZ.Economy.Multiplier()
    local list = {}

    for index, slot in pairs(xDTaraZ.Data.Table("Slots")) do
        local unit = type(slot) == "table" and slot.unitId and byKey[tostring(slot.unitId)]
        if not unit or unit.Level >= xDTaraZ.Options.LevelTarget or GameLib.RarityOrder(unit.Rarity) < minRarity then continue end
        local config = GameLib.EntryOf(unit.Name)
        local okPrice, price = pcall(GameLib.UnitUtil.GetLevelPrice, unit.Name, unit.Attr)
        local nextAttrs = table.clone(unit.Attr)
        nextAttrs.level = unit.Level + 1
        local okGain, nextIncome = pcall(config.income, nextAttrs)
        local gain = okGain and ((tonumber(nextIncome) or 0) - unit.Value) * mult or 0
        if okPrice and tonumber(price) and gain > 0 then
            list[#list + 1] = { tonumber(index), price, price / gain }
        end
    end
    table.sort(list, function(a, b) return a[3] < b[3] end)
    return list
end

---@param ignoreGoal boolean?  manual pass: skip saving for dice/rebirth
---@return number  levels bought
function xDTaraZ.Plot.LevelPass(ignoreGoal)
    local money = xDTaraZ.Data.Money()
    local goal = not ignoreGoal and xDTaraZ.Economy.Goal()
    local levelled = 0

    for _, pick in ipairs(xDTaraZ.Plot.LevelCandidates()) do
        local slot, price, payback = pick[1], pick[2], pick[3]
        if payback > xDTaraZ.Options.LevelPayback then break end
        if price > money then continue end
        if goal and money - price < goal.Cost and payback >= xDTaraZ.Economy.Eta(goal.Cost, money - price) then continue end
        xDTaraZ.Net.Fire("PlotService.RE.LevelUpSlot", slot)
        money -= price
        levelled += 1
        task.wait(xDTaraZ.Config.LevelDelay)
    end
    xDTaraZ.Plot.Status = levelled > 0 and (levelled .. " levelled") or (goal and ("Saving for " .. goal.Name) or "No level worth it")
    return levelled
end

xDTaraZ.Economy = { Rate = 0, Collected = 0, LastTotal = nil, LastAt = 0, Earned = 0 }

function xDTaraZ.Economy.Sample()
    local total = 0
    for _, slot in pairs(xDTaraZ.Data.Table("Slots")) do
        if type(slot) == "table" then total += tonumber(slot.balance) or 0 end
    end
    local economy, now = xDTaraZ.Economy, osClock()
    if economy.LastTotal and now > economy.LastAt then
        local earned = total + economy.Collected - economy.LastTotal
        local sample = earned / (now - economy.LastAt)
        if sample >= 0 then
            economy.Rate = economy.Rate == 0 and sample or economy.Rate * 0.8 + sample * 0.2
            economy.Earned += earned
        end
    end
    economy.LastTotal, economy.LastAt, economy.Collected = total, now, 0
end

---@return number  real money per second divided by the plotted units' raw income
function xDTaraZ.Economy.Multiplier()
    local plotted = {}
    for _, slot in pairs(xDTaraZ.Data.Table("Slots")) do
        if type(slot) == "table" and slot.unitId then plotted[tostring(slot.unitId)] = true end
    end
    local raw = 0
    for _, unit in ipairs(xDTaraZ.Data.Units()) do
        if plotted[unit.Key] then raw += unit.Value end
    end
    return (raw > 0 and xDTaraZ.Economy.Rate > 0) and xDTaraZ.Economy.Rate / raw or 1
end

---@return table?  cheapest enabled goal {Name, Cost} still out of reach
function xDTaraZ.Economy.Goal()
    local goals = {}
    if xDTaraZ.Options.AutoRebirth then
        local rebirth = xDTaraZ.Rebirth.Next()
        if rebirth then goals[#goals + 1] = { Name = "rebirth", Cost = tonumber(rebirth.cost) or math.huge } end
    end
    if xDTaraZ.Options.AutoBuyDice then
        local name, price = xDTaraZ.Dice.NextTarget()
        if name then goals[#goals + 1] = { Name = name .. " dice", Cost = price } end
    end
    table.sort(goals, function(a, b) return a.Cost < b.Cost end)
    return goals[1]
end

function xDTaraZ.Economy.Eta(cost, money)
    local rate = xDTaraZ.Economy.Rate
    if cost <= money then return 0 end
    return rate > 0 and (cost - money) / rate or math.huge
end

function xDTaraZ.Economy.Step()
    xDTaraZ.Economy.Sample()
    local options = xDTaraZ.Options
    if options.AutoBuyDice or options.AutoEquipBestDice then xDTaraZ.Dice.Step() end
    if options.AutoRebirth then xDTaraZ.Rebirth.RebirthNow() end
    if options.AutoRebirthStats then xDTaraZ.Rebirth.SpendPoints() end
    if options.AutoBuyUpgrades then xDTaraZ.Upgrade.BuyAll() end
    if options.AutoLevelUp then xDTaraZ.Plot.LevelPass() end
end

function xDTaraZ.Economy.GetStatus()
    local goal = xDTaraZ.Economy.Goal()
    local text = "Income " .. Util.FormatNumber(xDTaraZ.Economy.Rate) .. "/s"
    if not goal then return text end
    local eta = xDTaraZ.Economy.Eta(goal.Cost, xDTaraZ.Data.Money())
    local etaText = eta == math.huge and "?" or (eta < 60 and string.format("%ds", eta) or string.format("%dm", math.floor(eta / 60)))
    return string.format("%s · %s in %s", text, goal.Name, etaText)
end

xDTaraZ.Dice = { Status = "Off" }

---@return string, number  free starter dice (cheapest in the shop) and its luck
function xDTaraZ.Dice.Starter()
    local name, price, luck = "Basic", math.huge, 1
    for diceName, info in pairs(GameLib.Dice and GameLib.Dice.GetAll() or {}) do
        local cost = tonumber(info.price) or 0
        if cost < price then name, price, luck = diceName, cost, tonumber(info.luck) or 1 end
    end
    return name, luck
end

function xDTaraZ.Dice.OwnedSet()
    local owned = { [xDTaraZ.Dice.Starter()] = true }
    for key, value in pairs(xDTaraZ.Data.Table("OwnedDice")) do
        if type(key) == "number" then owned[value] = true elseif value then owned[key] = true end
    end
    return owned
end

---@return string, number  best owned dice and its luck
function xDTaraZ.Dice.BestOwned()
    local owned = xDTaraZ.Dice.OwnedSet()
    local bestName, bestLuck = xDTaraZ.Dice.Starter()
    for name, info in pairs(GameLib.Dice and GameLib.Dice.GetAll() or {}) do
        local luck = tonumber(info.luck) or 0
        if owned[name] and luck > bestLuck then bestName, bestLuck = name, luck end
    end
    return bestName, bestLuck
end

---@return string?  highest-luck dice affordable now that beats the best owned
function xDTaraZ.Dice.NextBuy()
    local owned = xDTaraZ.Dice.OwnedSet()
    local money = xDTaraZ.Data.Money()
    local _, pickLuck = xDTaraZ.Dice.BestOwned()
    local pick
    for name, info in pairs(GameLib.Dice and GameLib.Dice.GetAll() or {}) do
        local luck = tonumber(info.luck) or 0
        if not owned[name] and (tonumber(info.price) or math.huge) <= money and luck > pickLuck then
            pick, pickLuck = name, luck
        end
    end
    return pick
end

---@return string?, number  cheapest unowned dice luckier than the best owned
function xDTaraZ.Dice.NextTarget()
    local owned = xDTaraZ.Dice.OwnedSet()
    local _, bestLuck = xDTaraZ.Dice.BestOwned()
    local pick, pickPrice = nil, math.huge
    for name, info in pairs(GameLib.Dice and GameLib.Dice.GetAll() or {}) do
        local price = tonumber(info.price) or math.huge
        if not owned[name] and (tonumber(info.luck) or 0) > bestLuck and price < pickPrice then pick, pickPrice = name, price end
    end
    return pick, pickPrice
end

function xDTaraZ.Dice.EquipBest()
    local best = xDTaraZ.Dice.BestOwned()
    if best ~= xDTaraZ.Data.Read("Dice") then xDTaraZ.Net.Fire("DiceShopService.RE.EquipDice", best) end
end

function xDTaraZ.Dice.Step()
    if xDTaraZ.Options.AutoBuyDice then
        local buy = xDTaraZ.Dice.NextBuy()
        if buy then
            xDTaraZ.Net.Fire("DiceShopService.RE.BuyDice", buy)
            xDTaraZ.Dice.Status = "Bought " .. buy
            task.wait(xDTaraZ.Config.BuyDelay)
        end
    end
    if xDTaraZ.Options.AutoEquipBestDice or xDTaraZ.Options.AutoBuyDice then xDTaraZ.Dice.EquipBest() end
end

xDTaraZ.Upgrade = { Status = "Off" }

function xDTaraZ.Upgrade.Branch(name)
    return (name:gsub("%s+[IVXLC]+$", ""))
end

function xDTaraZ.Upgrade.Branches()
    local seen = {}
    for name in pairs(GameLib.Upgrades or {}) do
        if type(name) == "string" and name ~= "Start" then seen[xDTaraZ.Upgrade.Branch(name)] = true end
    end
    return Util.SortedKeys(seen)
end

---@return table  stat -> { base, percentage } summed over owned upgrades
function xDTaraZ.Upgrade.OwnedBuffs(owned)
    local sums = {}
    for name in pairs(owned) do
        local info = GameLib.Upgrades and GameLib.Upgrades[name]
        for stat, buff in pairs(type(info) == "table" and info.buffs or {}) do
            sums[stat] = sums[stat] or { base = 0, percentage = 0 }
            if sums[stat][buff.bucket] then sums[stat][buff.bucket] += tonumber(buff.amount) or 0 end
        end
    end
    return sums
end

---@return number  relative boost this buff adds to its stat (0.1 = +10%)
function xDTaraZ.Upgrade.Gain(stat, buff, sums)
    local amount = tonumber(buff.amount) or 0
    local sum = sums[stat] or { base = 0, percentage = 0 }
    if stat == "Roll Duration" then
        local ok, duration = pcall(GameLib.Buffs.GetBuff, stat)
        duration = ok and tonumber(duration) or 0
        return duration + amount > 0 and duration / (duration + amount) - 1 or 0
    end
    if buff.bucket == "percentage" then return amount / (1 + sum.percentage) end
    if buff.bucket == "multiplier" then return amount - 1 end
    local ok, config = pcall(GameLib.BuffsConfig.GetBuff, stat)
    local default = ok and type(config) == "table" and tonumber(config.default) or 1
    return amount / math.max(default + sum.base, 1e-3)
end

---@return number?  money spent per +1% luck on the next dice, nil when dice are maxed
function xDTaraZ.Upgrade.DiceDeal()
    local name, price = xDTaraZ.Dice.NextTarget()
    if not name then return nil end
    local _, bestLuck = xDTaraZ.Dice.BestOwned()
    local luck = tonumber(GameLib.Dice.GetAll()[name].luck) or bestLuck
    return price / math.max(luck / bestLuck - 1, 1e-3)
end

---@return boolean  price is a small slice of what the player earns
function xDTaraZ.Upgrade.Cheap(stat, price, money, rate)
    local seconds = xDTaraZ.Config.UtilitySeconds
    if rate > 0 then return price <= rate * (seconds[stat] or seconds.Default) end
    return price <= money * xDTaraZ.Config.UtilityFallbackShare
end

---@return table[]  { name, price, rank } upgrades worth buying now, best first
function xDTaraZ.Upgrade.Worth()
    local owned = xDTaraZ.Data.Table("Upgrades")
    local sums = xDTaraZ.Upgrade.OwnedBuffs(owned)
    local money, rate = xDTaraZ.Data.Money(), xDTaraZ.Economy.Rate
    local goal = xDTaraZ.Economy.Goal()
    local diceDeal = xDTaraZ.Upgrade.DiceDeal()
    local filter = Util.SetFromList(xDTaraZ.Options.UpgradeFilter)
    local anyBranch = next(filter) == nil
    local tree = GameLib.Tree
    local picks = {}

    for name, info in pairs(GameLib.Upgrades or {}) do
        if type(info) ~= "table" or name == "Start" or owned[name] then continue end
        local price = tonumber(info.price) or math.huge
        if price > money or not (anyBranch or filter[xDTaraZ.Upgrade.Branch(name)]) then continue end
        local parent = tree.GetParent(name)
        if parent and parent ~= "Start" and not owned[parent] then continue end

        local rank
        for stat, buff in pairs(info.buffs or {}) do
            local gain = xDTaraZ.Upgrade.Gain(stat, buff, sums)
            if gain <= 0 then continue end
            if stat == "Money Multiplier" and rate > 0 then
                local payback = price / (rate * gain)
                local etaAfter = goal and xDTaraZ.Economy.Eta(goal.Cost, money - price) or math.huge
                if payback <= xDTaraZ.Options.UpgradePayback or payback < etaAfter then rank = payback end
            elseif xDTaraZ.Config.RollStats[stat] and diceDeal then
                if price / (gain * 100) <= diceDeal / 100 then rank = 1e6 + price / money end
            elseif xDTaraZ.Upgrade.Cheap(stat, price, money, rate) then
                rank = 2e6 + price / money
            end
        end
        if rank then picks[#picks + 1] = { name, price, rank } end
    end
    table.sort(picks, function(a, b) return a[3] < b[3] end)
    return picks
end

---@return string  cheapest upgrade still locked behind money
function xDTaraZ.Upgrade.NextHint()
    local owned = xDTaraZ.Data.Table("Upgrades")
    local pick, price = nil, math.huge
    for name, info in pairs(GameLib.Upgrades or {}) do
        if type(info) ~= "table" or name == "Start" or owned[name] then continue end
        local parent = GameLib.Tree.GetParent(name)
        if parent and parent ~= "Start" and not owned[parent] then continue end
        if (tonumber(info.price) or math.huge) < price then pick, price = name, tonumber(info.price) end
    end
    return pick and string.format("Next: %s at %s", pick, Util.FormatNumber(price)) or "All upgrades owned"
end

---@return number  upgrades bought
function xDTaraZ.Upgrade.BuyAll()
    local bought, spent = 0, 0
    for _, pick in ipairs(xDTaraZ.Upgrade.Worth()) do
        if pick[2] + spent > xDTaraZ.Data.Money() then continue end
        xDTaraZ.Net.Fire("RE.BuyUpgrade", pick[1])
        spent += pick[2]
        bought += 1
        task.wait(xDTaraZ.Config.BuyDelay)
    end
    xDTaraZ.Upgrade.Status = bought > 0 and (bought .. " bought") or xDTaraZ.Upgrade.NextHint()
    return bought
end

xDTaraZ.Sell = { Status = "Off" }

---@return string[]  unit keys to sell under the current filters
function xDTaraZ.Sell.Pick()
    local wanted = Util.SetFromList(xDTaraZ.Options.SellRarities)
    if next(wanted) == nil then return {} end
    local keepMutation = Util.SetFromList(xDTaraZ.Options.SellKeepMutations)
    local keep = math.max(xDTaraZ.Options.KeepPerRarity, 0)

    local byRarity = {}
    for _, unit in ipairs(xDTaraZ.Data.Units()) do
        if unit.Busy or unit.Locked or not wanted[unit.Rarity] then continue end
        if unit.Mutation and keepMutation[unit.Mutation] then continue end
        byRarity[unit.Rarity] = byRarity[unit.Rarity] or {}
        table.insert(byRarity[unit.Rarity], unit)
    end

    local keys = {}
    for _, list in pairs(byRarity) do
        for index = keep + 1, #list do keys[#keys + 1] = list[index].Key end
    end
    return keys
end

function xDTaraZ.Sell.SellNow()
    local keys = xDTaraZ.Sell.Pick()
    if #keys == 0 then xDTaraZ.Sell.Status = "Nothing to sell" return xDTaraZ.Sell.Status end
    local before = xDTaraZ.Data.Money()
    xDTaraZ.Net.Invoke("SellService.RF.SellInventory", keys)
    xDTaraZ.Data.Invalidate()
    xDTaraZ.Sell.Status = string.format("%d sold (+%s)", #keys, Util.FormatNumber(xDTaraZ.Data.Money() - before))
    return xDTaraZ.Sell.Status
end

function xDTaraZ.Sell.Step()
    if xDTaraZ.Options.AutoSell then xDTaraZ.Sell.SellNow() end
end

xDTaraZ.Storage = { Status = "-" }

function xDTaraZ.Storage.Cap()
    local buffs = GameLib.Buffs
    local ok, cap = pcall(function() return buffs.GetBuff("Unit Storage") end)
    return ok and tonumber(cap) or math.huge
end

---@return number  units sold to make room for rolling
function xDTaraZ.Storage.Clear()
    local units = xDTaraZ.Data.Units()
    local cap = xDTaraZ.Storage.Cap()
    xDTaraZ.Storage.Status = string.format("%d/%s", #units, cap == math.huge and "?" or tostring(cap))
    if #units < cap - xDTaraZ.Config.StorageHeadroom then return 0 end

    local keepRank = GameLib.RarityOrder(xDTaraZ.Options.ClearKeepRarity)
    local keepMutation = Util.SetFromList(xDTaraZ.Options.SellKeepMutations)
    local spare = {}
    for _, unit in ipairs(units) do
        if unit.Busy or unit.Locked or (unit.Mutation and keepMutation[unit.Mutation]) then continue end
        if keepRank > 0 and GameLib.RarityOrder(unit.Rarity) >= keepRank then continue end
        spare[#spare + 1] = unit
    end
    table.sort(spare, function(a, b) return a.Potential < b.Potential end)

    local excess = #units - math.floor(cap * xDTaraZ.Config.StorageRefill)
    local keys = {}
    for index = 1, math.min(excess, #spare) do keys[index] = spare[index].Key end
    if #keys == 0 then xDTaraZ.Storage.Status ..= " · full, nothing sellable" return 0 end

    xDTaraZ.Net.Invoke("SellService.RF.SellInventory", keys)
    xDTaraZ.Data.Invalidate()
    return #keys
end

function xDTaraZ.Storage.Step()
    if xDTaraZ.Options.AutoClearStorage then xDTaraZ.Storage.Clear() end
end

xDTaraZ.Rebirth = { Status = "Off" }

---@return table?  next tier {cost, moneyMultiplier}, nil at max
function xDTaraZ.Rebirth.Next()
    local rebirths = GameLib.Rebirths
    if not rebirths then return nil end
    local ok, info = pcall(rebirths.GetNext, xDTaraZ.Data.Rebirth())
    return ok and type(info) == "table" and info or nil
end

function xDTaraZ.Rebirth.RebirthNow()
    local info = xDTaraZ.Rebirth.Next()
    if not info then xDTaraZ.Rebirth.Status = "Max rebirth" return false end
    if xDTaraZ.Data.Money() < (tonumber(info.cost) or math.huge) then
        xDTaraZ.Rebirth.Status = "Need " .. Util.FormatNumber(info.cost)
        return false
    end
    xDTaraZ.Net.Fire("RebirthService.RE.Rebirth")
    xDTaraZ.Rebirth.Status = "Rebirthed"
    return true
end

function xDTaraZ.Rebirth.PointsLeft()
    local config = GameLib.RebirthStats
    if not config then return 0 end
    local ok, left = pcall(config.GetRemaining, xDTaraZ.Data.Rebirth(), xDTaraZ.Data.Table("RebirthStats"))
    return ok and tonumber(left) or 0
end

---@return number  points spent
function xDTaraZ.Rebirth.SpendPoints()
    local stat = xDTaraZ.Options.RebirthStat
    local spent = 0
    while xDTaraZ.Rebirth.PointsLeft() > 0 and spent < 200 do
        local before = xDTaraZ.Rebirth.PointsLeft()
        xDTaraZ.Net.Fire("RebirthService.RE.AddStat", stat)
        task.wait(xDTaraZ.Config.StatDelay)
        if xDTaraZ.Rebirth.PointsLeft() >= before then
            task.wait(xDTaraZ.Config.StatDelay * 3)
            if xDTaraZ.Rebirth.PointsLeft() >= before then break end
        end
        spent += 1
    end
    return spent
end

---@return boolean, string?  false and why when the reset can't run
function xDTaraZ.Rebirth.ResetStats()
    local config = GameLib.RebirthStats
    if not config then return false, "Stats not found" end
    if config.GetSpent(xDTaraZ.Data.Table("RebirthStats")) <= 0 then return false, "No points spent" end
    if xDTaraZ.Data.Token("Reset Token") < 1 then return false, "No Reset Token" end
    xDTaraZ.Net.Fire("RebirthService.RE.UseResetToken")
    return true
end

xDTaraZ.Grade = { Status = "Off" }

---@return table?  next unit that should be rerolled toward the target
function xDTaraZ.Grade.Pick()
    local target = GameLib.GradeOrder(xDTaraZ.Options.GradeTarget)
    local protected = xDTaraZ.Data.Table("ProtectedGrades")
    for _, unit in ipairs(xDTaraZ.Data.Units()) do
        if not unit.Busy or unit.Locked or GameLib.GradeOrder(unit.Grade) >= target then continue end
        if unit.Grade and protected[unit.Grade] and not xDTaraZ.Options.GradeOverwrite then continue end
        return unit
    end
    return nil
end

function xDTaraZ.Grade.RollOne()
    if xDTaraZ.Data.Token("Gems") < 1 then xDTaraZ.Grade.Status = "No Gems" return false end
    local unit = xDTaraZ.Grade.Pick()
    if not unit then xDTaraZ.Grade.Status = "All at target" return false end
    xDTaraZ.Net.Fire("GradeService.RE.Roll", unit.Key)
    xDTaraZ.Grade.Status = string.format("%s [%s]", unit.Name, unit.Grade or "-")
    return true
end

function xDTaraZ.Grade.Step()
    if xDTaraZ.Options.AutoGrade then xDTaraZ.Grade.RollOne() end
end

xDTaraZ.Trait = { Status = "Off" }

function xDTaraZ.Trait.Pick()
    local target = GameLib.TraitPower(xDTaraZ.Options.TraitTarget)
    local protected = xDTaraZ.Data.Table("ProtectedTraits")
    for _, unit in ipairs(xDTaraZ.Data.Units()) do
        if not unit.Busy or unit.Locked or GameLib.TraitPower(unit.Trait) >= target then continue end
        if unit.Trait and protected[unit.Trait] and not xDTaraZ.Options.TraitOverwrite then continue end
        return unit
    end
    return nil
end

function xDTaraZ.Trait.RollOne()
    if xDTaraZ.Data.Token("Trait Reroll") < 1 then xDTaraZ.Trait.Status = "No Trait Reroll" return false end
    local unit = xDTaraZ.Trait.Pick()
    if not unit then xDTaraZ.Trait.Status = "All at target" return false end
    xDTaraZ.Net.Fire("TraitService.RE.Roll", unit.Key)
    xDTaraZ.Trait.Status = string.format("%s [%s]", unit.Name, unit.Trait or "-")
    return true
end

function xDTaraZ.Trait.Step()
    if xDTaraZ.Options.AutoTrait then xDTaraZ.Trait.RollOne() end
end

xDTaraZ.Fuse = { Status = "Off" }

---@return table[]  spare units the game allows to fuse, rarest first
function xDTaraZ.Fuse.Pool()
    local wanted = Util.SetFromList(xDTaraZ.Options.FuseRarities)
    local anyRarity = next(wanted) == nil
    local keepRank = GameLib.RarityOrder(xDTaraZ.Options.ClearKeepRarity)
    local keepMutation = Util.SetFromList(xDTaraZ.Options.SellKeepMutations)
    local pool = {}
    for _, unit in ipairs(xDTaraZ.Data.Units()) do
        if unit.Busy or unit.Locked or not unit.Chance then continue end
        if unit.Mutation and keepMutation[unit.Mutation] then continue end
        if anyRarity and keepRank > 0 and GameLib.RarityOrder(unit.Rarity) >= keepRank then continue end
        if anyRarity or wanted[unit.Rarity] then pool[#pool + 1] = unit end
    end
    table.sort(pool, function(a, b) return a.Chance > b.Chance end)
    return pool
end

---@return table?  three keys whose expected result is clearly rarer than the best input and cheap to fuse
function xDTaraZ.Fuse.PickTrio()
    local pool = xDTaraZ.Fuse.Pool()
    local config = GameLib.FusingConfig
    local average = tonumber(config.AverageMultiplier) or 0.667
    local budget = xDTaraZ.Data.Money() * xDTaraZ.Config.FuseMoneyShare
    for index = 1, #pool - 2 do
        local a, b, c = pool[index], pool[index + 1], pool[index + 2]
        local sum = a.Chance + b.Chance + c.Chance
        local ok, cost = pcall(config.GetCost, sum)
        if sum * average >= a.Chance * xDTaraZ.Config.FuseGain and ok and cost <= budget then
            return { a.Key, b.Key, c.Key, a.Name }
        end
    end
    return nil
end

function xDTaraZ.Fuse.FuseNow()
    local trio = xDTaraZ.Fuse.PickTrio()
    if not trio then xDTaraZ.Fuse.Status = "No worthwhile trio" return false end
    xDTaraZ.Net.Fire("FusingService.RE.Fuse", trio[1], trio[2], trio[3])
    xDTaraZ.Data.Invalidate()
    xDTaraZ.Fuse.Status = "Fused " .. trio[4] .. " +2"
    return true
end

function xDTaraZ.Fuse.Step()
    if xDTaraZ.Options.AutoFuse then xDTaraZ.Fuse.FuseNow() end
end

xDTaraZ.Tower = { Status = "Off", State = "Idle", NextAt = 0, Floor = 0, Best = 0, Runs = 0, Misses = 0, Ending = false }

---@return string[]  "Tower (Difficulty)" labels, easiest first
function xDTaraZ.Tower.Labels()
    local towers = GameLib.Towers and GameLib.Towers.GetAll() or {}
    local names = {}
    for name in pairs(towers) do names[#names + 1] = name end
    table.sort(names, function(a, b) return (tonumber(towers[a].order) or 0) < (tonumber(towers[b].order) or 0) end)
    local labels = {}
    for _, name in ipairs(names) do
        local difficulty = type(towers[name].difficulty) == "table" and towers[name].difficulty.name or "?"
        labels[#labels + 1] = string.format("%s (%s)", name, difficulty)
    end
    return labels
end

function xDTaraZ.Tower.NameFromLabel(label)
    return (tostring(label):gsub("%s*%b()$", ""))
end

function xDTaraZ.Tower.EquipTeam()
    xDTaraZ.Net.Fire("Towers.RE.EquipBestTowerTeam")
end

---@return number  seconds the server needs to play the returned actions
function xDTaraZ.Tower.Duration(actions)
    local total = 0
    for _, action in ipairs(actions) do
        total += xDTaraZ.Config.TowerActionTime[action.action] or 0.3
    end
    return total
end

---@return string[]  tower names, easiest first
function xDTaraZ.Tower.Order()
    local towers = GameLib.Towers and GameLib.Towers.GetAll() or {}
    local names = {}
    for name in pairs(towers) do names[#names + 1] = name end
    table.sort(names, function(a, b) return (tonumber(towers[a].order) or 0) < (tonumber(towers[b].order) or 0) end)
    return names
end

---@param floor number?  floor the last run reached, nil when the tower could not be entered
function xDTaraZ.Tower.Adapt(floor)
    if not xDTaraZ.Options.TowerSmart then return end
    local order = xDTaraZ.Tower.Order()
    local index = table.find(order, xDTaraZ.Options.TowerName) or 1
    local info = GameLib.Towers.Get(xDTaraZ.Options.TowerName)
    local top = math.min(tonumber(info and info.maxFloors) or math.huge, xDTaraZ.Options.TowerStopFloor)
    if floor and floor >= top and order[index + 1] then
        index += 1
    elseif (not floor or floor < xDTaraZ.Config.TowerDemoteFloor) and index > 1 then
        index -= 1
    end
    xDTaraZ.Options.TowerName = order[index]
end

function xDTaraZ.Tower.Leave()
    if xDTaraZ.Tower.Ending then return end
    xDTaraZ.Tower.Ending = true
    xDTaraZ.Net.Invoke("Towers.RF.CancelTower")
end

function xDTaraZ.Tower.Start()
    local now = osClock()
    if xDTaraZ.Options.TowerReequip or xDTaraZ.Tower.Runs == 0 then
        xDTaraZ.Tower.EquipTeam()
        task.wait(0.4)
    end
    local _, started = xDTaraZ.Net.Invoke("Towers.RF.PlayTower", xDTaraZ.Options.TowerName)
    xDTaraZ.Tower.State = "Climbing"
    xDTaraZ.Tower.Floor = 0
    xDTaraZ.Tower.Ending = not started
    xDTaraZ.Tower.NextAt = now
    xDTaraZ.Tower.Status = started and ("Entered " .. xDTaraZ.Options.TowerName) or "Finishing previous run"
end

function xDTaraZ.Tower.Climb()
    local ok, actions = xDTaraZ.Net.Invoke("Towers.RF.CompleteTowerFloor")
    local now = osClock()
    if not ok or type(actions) ~= "table" or #actions == 0 then
        xDTaraZ.Tower.Misses += 1
        xDTaraZ.Tower.NextAt = now + xDTaraZ.Config.TowerRetry
        if xDTaraZ.Tower.Misses >= 20 then
            xDTaraZ.Tower.Misses = 0
            xDTaraZ.Tower.Adapt(nil)
            xDTaraZ.Tower.State = "Idle"
            xDTaraZ.Tower.NextAt = now + xDTaraZ.Config.TowerStartCooldown
        end
        return
    end
    xDTaraZ.Tower.Misses = 0

    for _, action in ipairs(actions) do
        if tonumber(action.floor) then xDTaraZ.Tower.Floor = math.max(xDTaraZ.Tower.Floor, action.floor) end
    end
    xDTaraZ.Tower.Best = math.max(xDTaraZ.Tower.Best, xDTaraZ.Tower.Floor)
    xDTaraZ.Tower.NextAt = now + xDTaraZ.Tower.Duration(actions)

    if actions[#actions].action == "ended" then
        xDTaraZ.Tower.Runs += 1
        xDTaraZ.Tower.State = "Idle"
        xDTaraZ.Tower.Ending = false
        xDTaraZ.Tower.NextAt += xDTaraZ.Config.TowerStartCooldown
        xDTaraZ.Tower.Status = string.format("Run %d ended at floor %d", xDTaraZ.Tower.Runs, xDTaraZ.Tower.Floor)
        xDTaraZ.Tower.Adapt(xDTaraZ.Tower.Floor)
        return
    end
    if xDTaraZ.Tower.Floor >= xDTaraZ.Options.TowerStopFloor then xDTaraZ.Tower.Leave() end
    xDTaraZ.Tower.Status = string.format("%s · floor %d", xDTaraZ.Options.TowerName, xDTaraZ.Tower.Floor)
end

function xDTaraZ.Tower.Step()
    local tower = xDTaraZ.Tower
    if osClock() < tower.NextAt then return end
    if not xDTaraZ.Options.AutoTower then
        if tower.State == "Idle" then tower.Status = "Off" return end
        tower.Leave()
        tower.Climb()
        return
    end
    if tower.State == "Idle" then tower.Start() else tower.Climb() end
end

function xDTaraZ.Tower.GetStatus()
    if not xDTaraZ.Options.AutoTower then return "Off" end
    return string.format("%s · best %d · runs %d", xDTaraZ.Tower.Status, xDTaraZ.Tower.Best, xDTaraZ.Tower.Runs)
end

xDTaraZ.Gear = { Status = "Off" }

---@return number  slots changed
function xDTaraZ.Gear.EquipBest()
    local best = {}
    for _, item in ipairs(xDTaraZ.Data.ItemsOfKind("Gear")) do
        local config = GameLib.EntryOf(item.Name)
        local slot = config and config.slot
        if not slot then continue end
        local rank = GameLib.RarityOrder(config.rarity)
        if not best[slot] or rank > best[slot][2] then best[slot] = { item.Name, rank } end
    end

    local equipped = xDTaraZ.Data.Table("EquippedGear")
    local changed = 0
    for slot, pick in pairs(best) do
        if equipped[slot] ~= pick[1] then
            xDTaraZ.Net.Fire("GearService.RE.Equip", slot, pick[1])
            changed += 1
            task.wait(xDTaraZ.Config.GradeDelay)
        end
    end
    xDTaraZ.Gear.Status = changed > 0 and (changed .. " slots upgraded") or "Best gear on"
    return changed
end

function xDTaraZ.Gear.Step()
    if xDTaraZ.Options.AutoGear then xDTaraZ.Gear.EquipBest() end
end

xDTaraZ.Items = { Status = "Off" }

---@return boolean  true while the potion's effect is actually being used
function xDTaraZ.Items.PotionUseful(name)
    local towerWord = name:match("^(%a+)%s+%a+%s+[IVX]+$")
    if towerWord then
        return xDTaraZ.Options.AutoTower and xDTaraZ.Tower.State == "Climbing" and xDTaraZ.Options.TowerName:find(towerWord) ~= nil
    end
    if name:find("Luck") then return xDTaraZ.Options.AutoRoll end
    if name:find("Damage") then return xDTaraZ.Options.AutoTower end
    if name:find("Income") then return xDTaraZ.Economy.Rate > 0 end
    return true
end

---@param force boolean?  manual use: ignore timing
function xDTaraZ.Items.UsePotions(force)
    local filter = Util.SetFromList(xDTaraZ.Options.PotionFilter)
    local anyPotion = next(filter) == nil
    local active = xDTaraZ.Data.Table("ActiveEntries")
    local used = 0
    for _, item in ipairs(xDTaraZ.Data.ItemsOfKind("Boost")) do
        if not (force or xDTaraZ.Items.PotionUseful(item.Name)) then continue end
        if (anyPotion or filter[item.Name]) and not active[item.Name] then
            xDTaraZ.Net.Fire("BoostService.RE.Use", item.Key)
            used += 1
            task.wait(xDTaraZ.Config.ItemDelay)
        end
    end
    return used
end

function xDTaraZ.Items.UseSpins()
    local used = 0
    for _, item in ipairs(xDTaraZ.Data.ItemsOfKind("Spin")) do
        for _ = 1, math.min(item.Amount, 10) do
            xDTaraZ.Net.Fire("SpinService.RE.Use", item.Key)
            used += 1
            task.wait(xDTaraZ.Config.ItemDelay)
        end
    end
    return used
end

---@return number  gamepass items redeemed
function xDTaraZ.Items.UseGamepasses()
    local owned = xDTaraZ.Data.Table("OwnedGamepasses")
    local used = 0
    for _, item in ipairs(xDTaraZ.Data.ItemsOfKind("Gamepass")) do
        local config = GameLib.EntryOf(item.Name)
        if config and config.gamepass and owned[config.gamepass] then continue end
        xDTaraZ.Net.Fire("GamepassService.RE.Use", item.Key)
        used += 1
        task.wait(xDTaraZ.Config.ItemDelay)
    end
    return used
end

---@return number  ticket shop purchases made
function xDTaraZ.Items.BuyTicketShop()
    local wanted = Util.SetFromList(xDTaraZ.Options.TicketShopItems)
    if next(wanted) == nil then return 0 end
    local shop = GameLib.Quests and GameLib.Quests.Shop or {}
    local bought = 0
    for _, item in ipairs(shop) do
        if type(item) ~= "table" or not wanted[item.name] then continue end
        local cost = tonumber(item.tickets) or math.huge
        while xDTaraZ.Data.Token("Tickets") >= cost and bought < 50 do
            local before = xDTaraZ.Data.Token("Tickets")
            xDTaraZ.Net.Fire("QuestService.RE.Buy", item.name)
            bought += 1
            task.wait(xDTaraZ.Config.ItemDelay)
            if xDTaraZ.Data.Token("Tickets") >= before then break end
        end
    end
    return bought
end

function xDTaraZ.Items.Step()
    if xDTaraZ.Options.AutoPotion then xDTaraZ.Items.UsePotions() end
    if xDTaraZ.Options.AutoSpin then xDTaraZ.Items.UseSpins() end
    if xDTaraZ.Options.AutoGamepass then xDTaraZ.Items.UseGamepasses() end
    if xDTaraZ.Options.AutoTicketShop then xDTaraZ.Items.BuyTicketShop() end
end

xDTaraZ.Watch = { Seen = nil, Best = nil, Pulls = 0, StartAt = osClock(), StartGems = nil }

function xDTaraZ.Watch.Describe(unit)
    return string.format("%s [%s]%s", unit.Name, unit.Rarity or "?", unit.Mutation and (" · " .. unit.Mutation) or "")
end

function xDTaraZ.Watch.Alert(unit)
    local text = xDTaraZ.Watch.Describe(unit)
    pcall(function() xDTaraZ.Library:Notify("Rare pull", text, 8, "Success") end)
    local url = xDTaraZ.Options.WebhookUrl
    if type(url) ~= "string" or not url:find("^https://") or not Util.Request then return end
    local body = HttpService:JSONEncode({
        username = "Nova Hub",
        embeds = { { title = "Anime Dice · rare pull", description = text, color = xDTaraZ.Config.WebhookColor } },
    })
    local ok, err = pcall(Util.Request, { Url = url, Method = "POST", Headers = { ["Content-Type"] = "application/json" }, Body = body })
    if not ok then warn("[AnimeDice] webhook:", err) end
end

function xDTaraZ.Watch.OnNew(unit)
    local watch = xDTaraZ.Watch
    watch.Pulls += 1
    if not watch.Best or unit.Potential > watch.Best.Potential then watch.Best = unit end
    if not xDTaraZ.Options.RareNotify then return end
    local rarities = Util.SetFromList(xDTaraZ.Options.NotifyRarities)
    local mutations = Util.SetFromList(xDTaraZ.Options.NotifyMutations)
    if rarities[unit.Rarity] or (unit.Mutation and mutations[unit.Mutation]) then watch.Alert(unit) end
end

function xDTaraZ.Watch.Step()
    local watch = xDTaraZ.Watch
    local units = xDTaraZ.Data.Units()
    if not watch.Seen then
        watch.Seen, watch.StartGems = {}, xDTaraZ.Data.Token("Gems")
        for _, unit in ipairs(units) do watch.Seen[unit.Key] = true end
        return
    end
    for _, unit in ipairs(units) do
        if not watch.Seen[unit.Key] then
            watch.Seen[unit.Key] = true
            watch.OnNew(unit)
        end
    end
end

---@return string[]  lines for the stats panel
function xDTaraZ.Watch.Stats()
    local watch = xDTaraZ.Watch
    local hours = math.max(osClock() - watch.StartAt, 1) / 3600
    return {
        string.format("Money %s/h · Rolls %s/h", Util.FormatNumber(xDTaraZ.Economy.Earned / hours), Util.FormatNumber(xDTaraZ.Roll.Session / hours)),
        string.format("Pulls %d · Gems %+d · Tower runs %d", watch.Pulls, xDTaraZ.Data.Token("Gems") - (watch.StartGems or 0), xDTaraZ.Tower.Runs),
        "Best pull: " .. (watch.Best and xDTaraZ.Watch.Describe(watch.Best) or "-"),
    }
end

xDTaraZ.Lock = { Status = "Off" }

---@return number  units locked this pass
function xDTaraZ.Lock.Step()
    if not xDTaraZ.Options.AutoLock then return 0 end
    local rank = GameLib.RarityOrder(xDTaraZ.Options.LockRarity)
    local mutations = Util.SetFromList(xDTaraZ.Options.LockMutations)
    local keys, count = {}, 0
    for _, unit in ipairs(xDTaraZ.Data.Units()) do
        if unit.Locked then continue end
        if (rank > 0 and GameLib.RarityOrder(unit.Rarity) >= rank) or (unit.Mutation and mutations[unit.Mutation]) then
            keys[unit.Key] = true
            count += 1
        end
    end
    if count > 0 then
        xDTaraZ.Net.Fire("UnitService.RE.SetLocked", keys)
        xDTaraZ.Data.Invalidate()
    end
    xDTaraZ.Lock.Status = count > 0 and (count .. " locked") or "Nothing new to lock"
    return count
end

xDTaraZ.Rejoin = { Hooked = false, Busy = false }

function xDTaraZ.Rejoin.Now()
    if xDTaraZ.Rejoin.Busy then return end
    xDTaraZ.Rejoin.Busy = true
    if Util.QueueTeleport then
        local resume = xDTaraZ.Options.Kaitun and "getgenv().AnimeDiceResume = true " or ""
        pcall(Util.QueueTeleport, resume .. xDTaraZ.Config.ReloadSource)
    end
    local ok, err = pcall(TeleportService.Teleport, TeleportService, game.PlaceId, LocalPlayer)
    if not ok then warn("[AnimeDice] rejoin:", err) end
    task.delay(xDTaraZ.Config.RejoinRetry, function() xDTaraZ.Rejoin.Busy = false end)
end

function xDTaraZ.Rejoin.Start()
    xDTaraZ.Options.AutoRejoin = true
    if xDTaraZ.Rejoin.Hooked then return end
    xDTaraZ.Rejoin.Hooked = true
    xDTaraZ:Connect(GuiService.ErrorMessageChanged, function(message)
        if xDTaraZ.Options.AutoRejoin and message ~= "" then task.delay(xDTaraZ.Config.RejoinDelay, xDTaraZ.Rejoin.Now) end
    end)
end

function xDTaraZ.Rejoin.Stop()
    xDTaraZ.Options.AutoRejoin = false
end

xDTaraZ.Rewards = { Status = "Off", DailyRetryAt = 0, Member = nil }

function xDTaraZ.Rewards.RedeemAll()
    local redeemed = xDTaraZ.Data.Table("RedeemedCodes")
    local sent = 0
    for code in pairs(GameLib.Codes or {}) do
        if type(code) == "string" and not redeemed[code] then
            xDTaraZ.Net.Fire("CodesService.RE.RedeemCode", code)
            sent += 1
            task.wait(xDTaraZ.Config.RedeemDelay)
        end
    end
    return sent > 0 and (sent .. " codes redeemed") or "All codes already redeemed"
end

---@return number  quests claimed
function xDTaraZ.Rewards.ClaimQuests()
    local periods = GameLib.Quests and GameLib.Quests.Periods
    local records = xDTaraZ.Data.Table("Quests")
    if type(periods) ~= "table" then return 0 end
    local claimedCount = 0
    for period, def in pairs(periods) do
        local record = records[period]
        if type(record) ~= "table" or type(def) ~= "table" then continue end
        local progress = type(record.progress) == "table" and record.progress or {}
        local claimed = type(record.claimed) == "table" and record.claimed or {}
        for _, quest in ipairs(def.quests or {}) do
            if not claimed[quest.id] and (tonumber(progress[quest.id]) or 0) >= (tonumber(quest.target) or math.huge) then
                xDTaraZ.Net.Fire("QuestService.RE.Claim", period, quest.id, record.expiresAt)
                claimedCount += 1
                task.wait(xDTaraZ.Config.ClaimDelay)
            end
        end
    end
    return claimedCount
end

function xDTaraZ.Rewards.ClaimOffline()
    if (tonumber(xDTaraZ.Data.Read("PendingOfflineEarnings")) or 0) > 0 then
        xDTaraZ.Net.Fire("OfflineEarningsService.RE.Claim")
    end
end

function xDTaraZ.Rewards.DailyReady()
    local cooldown = GameLib.Daily and tonumber(GameLib.Daily.Cooldown) or 82800
    local last = tonumber(xDTaraZ.Data.Read("LastDailyRewardClaim")) or 0
    return os.time() - last >= cooldown and osClock() >= xDTaraZ.Rewards.DailyRetryAt
end

function xDTaraZ.Rewards.InGroup()
    if xDTaraZ.Rewards.Member == nil then
        local groupId = GameLib.Group and tonumber(GameLib.Group.GroupId) or xDTaraZ.Config.GroupId
        local ok, member = pcall(LocalPlayer.IsInGroup, LocalPlayer, groupId)
        xDTaraZ.Rewards.Member = ok and member == true
    end
    return xDTaraZ.Rewards.Member
end

function xDTaraZ.Rewards.Step()
    if xDTaraZ.Options.AutoDaily and xDTaraZ.Rewards.DailyReady() then
        xDTaraZ.Rewards.DailyRetryAt = osClock() + 60
        xDTaraZ.Net.Fire("DailyRewardService.RE.Claim")
    end
    if xDTaraZ.Options.AutoGroup and not xDTaraZ.Data.Read("ClaimedGroupReward") and xDTaraZ.Rewards.InGroup() then
        xDTaraZ.Net.Fire("GroupRewardService.RE.Claim")
    end
    if xDTaraZ.Options.AutoOffline then xDTaraZ.Rewards.ClaimOffline() end
    if xDTaraZ.Options.AutoQuest then xDTaraZ.Rewards.ClaimQuests() end
end

xDTaraZ.Kaitun = { Status = "Off", Members = {
    "AntiAfk", "AutoRejoin", "RareNotify", "AutoLock", "TowerSmart", "AutoFuse", "DisableCutscene", "AutoRoll", "AutoCollect", "EquipBestUnitsAuto", "AutoLevelUp",
    "AutoBuyDice", "AutoEquipBestDice", "AutoBuyUpgrades", "AutoSell", "AutoRebirth", "AutoRebirthStats", "AutoGrade",
    "AutoTrait", "AutoTower", "AutoPotion", "AutoSpin", "AutoGamepass", "AutoTicketShop", "AutoDaily", "AutoGroup",
    "AutoOffline", "AutoQuest", "AutoGear", "AutoClearStorage",
} }

---@param fromTop boolean  take the rarest end instead of the commonest
---@return string[]        up to count names from a list sorted commonest first
function xDTaraZ.Kaitun.Slice(list, count, fromTop)
    local picked = {}
    local first = fromTop and math.max(#list - count + 1, 1) or 1
    for index = first, math.min(first + count - 1, #list) do
        table.insert(picked, list[index])
    end
    return picked
end

function xDTaraZ.Kaitun.SetMembers(on)
    local toggles = xDTaraZ.Library and xDTaraZ.Library.Toggles or {}
    for _, idx in ipairs(xDTaraZ.Kaitun.Members) do
        if toggles[idx] then toggles[idx]:SetValue(on) else xDTaraZ.Options[idx] = on end
    end
end

function xDTaraZ.Kaitun.Start()
    xDTaraZ.Options.Kaitun = true
    local options = xDTaraZ.Library and xDTaraZ.Library.Options or {}
    local function Default(idx, value)
        if next(Util.SetFromList(xDTaraZ.Options[idx])) ~= nil then return end
        if options[idx] then options[idx]:SetValue(Util.SetFromList(value)) end
        xDTaraZ.Options[idx] = value
    end
    local slice = xDTaraZ.Kaitun.Slice
    local lists = xDTaraZ.UI.Lists
    local rarities, mutations = lists.Rarities, lists.Mutations
    if table.find(GameLib.ShopNames(), "Gems") then Default("TicketShopItems", { "Gems" }) end
    Default("SellRarities", slice(rarities, 2))
    Default("LockMutations", slice(mutations, 3, true))
    Default("NotifyRarities", slice(rarities, 4, true))
    Default("NotifyMutations", slice(mutations, 2, true))
    if options.LevelTarget then options.LevelTarget:SetValue(200) end
    xDTaraZ.Options.LevelTarget = 200
    xDTaraZ.Kaitun.SetMembers(true)
    task.defer(function() xDTaraZ.Rewards.RedeemAll() end)
end

function xDTaraZ.Kaitun.Stop()
    xDTaraZ.Options.Kaitun = false
    xDTaraZ.Kaitun.SetMembers(false)
end

function xDTaraZ.Kaitun.GetStatus()
    return string.format("R%d · %s", xDTaraZ.Data.Rebirth(), xDTaraZ.Economy.GetStatus())
end

xDTaraZ.UI = { Labels = {}, Lists = { Rarities = {}, Mutations = {} } }
local Library, T

function xDTaraZ.UI.Detach(fn)
    return function(...)
        local packed = table.pack(...)
        task.defer(function()
            local ok, err = pcall(fn, table.unpack(packed, 1, packed.n))
            if not ok then warn("[AnimeDice] ui: " .. tostring(err)) end
        end)
    end
end

---@param module table  feature with Start/Stop
function xDTaraZ.UI.StartStop(module)
    return xDTaraZ.UI.Detach(function(on)
        if on then module.Start() else module.Stop() end
    end)
end

function xDTaraZ.UI.Notify(title, text, kind)
    Library:Notify(title, tostring(text), 4, kind or "Info")
end

---@return table  list from a game-data source, empty when it errors
function xDTaraZ.UI.Values(source, ...)
    local ok, list = pcall(source, ...)
    return ok and type(list) == "table" and list or {}
end

---@param fallback number  index used when the game renamed or removed the preferred value
function xDTaraZ.UI.Prefer(values, preferred, fallback)
    if table.find(values, preferred) then return preferred end
    return values[math.clamp(fallback, 1, math.max(#values, 1))]
end

function xDTaraZ.UI.MultiDropdown(group, idx, text, desc, values)
    return group:AddDropdown(idx, {
        Text = text,
        Description = desc,
        Values = values,
        Multi = true,
        Default = {},
        AllowNull = true,
        Searchable = true,
    })
end

xDTaraZ.UI.Needs = {
    Kaitun = { "DataClient", "Entry" },
    AutoCollect = { "DataClient" },
    EquipBestUnitsAuto = { "DataClient", "Entry" },
    AutoLevelUp = { "DataClient", "Entry", "UnitUtil" },
    AutoTower = { "Towers" },
    AutoSell = { "DataClient", "Entry" },
    AutoClearStorage = { "DataClient", "Entry", "Buffs" },
    AutoBuyDice = { "DataClient", "Dice" },
    AutoEquipBestDice = { "DataClient", "Dice" },
    AutoBuyUpgrades = { "DataClient", "Upgrades", "Tree", "Buffs", "BuffsConfig" },
    AutoRebirth = { "DataClient", "Rebirths" },
    AutoRebirthStats = { "DataClient", "RebirthStats" },
    AutoGamepass = { "DataClient", "Entry" },
    AutoGrade = { "DataClient", "Entry", "Grades" },
    AutoTrait = { "DataClient", "Entry", "Traits" },
    AutoFuse = { "DataClient", "Entry", "FusingConfig" },
    AutoGear = { "DataClient", "Entry" },
    AutoLock = { "DataClient", "Entry" },
    AutoPotion = { "DataClient", "Entry" },
    AutoSpin = { "DataClient", "Entry" },
    AutoTicketShop = { "DataClient", "Quests" },
    AutoQuest = { "DataClient", "Quests" },
    AutoDaily = { "DataClient" },
    AutoGroup = { "DataClient" },
    AutoOffline = { "DataClient" },
    RareNotify = { "DataClient", "Entry" },
}

xDTaraZ.UI.Remotes = {
    AutoRoll = { "RollService.RF.RollDice" },
    AutoCollect = { "PlotService.RE.CollectBalance" },
    EquipBestUnitsAuto = { "PlotService.RE.EquipBest", "PlotService.RE.InteractSlot", "UnitService.RF.Equip" },
    AutoLevelUp = { "PlotService.RE.LevelUpSlot" },
    AutoTower = { "Towers.RF.PlayTower", "Towers.RF.CompleteTowerFloor", "Towers.RF.CancelTower" },
    AutoSell = { "SellService.RF.SellInventory" },
    AutoClearStorage = { "SellService.RF.SellInventory" },
    AutoBuyDice = { "DiceShopService.RE.BuyDice" },
    AutoEquipBestDice = { "DiceShopService.RE.EquipDice" },
    AutoBuyUpgrades = { "RE.BuyUpgrade" },
    AutoRebirth = { "RebirthService.RE.Rebirth" },
    AutoRebirthStats = { "RebirthService.RE.AddStat" },
    AutoGamepass = { "GamepassService.RE.Use" },
    AutoGrade = { "GradeService.RE.Roll" },
    AutoTrait = { "TraitService.RE.Roll" },
    AutoFuse = { "FusingService.RE.Fuse" },
    AutoGear = { "GearService.RE.Equip" },
    AutoLock = { "UnitService.RE.SetLocked" },
    AutoPotion = { "BoostService.RE.Use" },
    AutoSpin = { "SpinService.RE.Use" },
    AutoTicketShop = { "QuestService.RE.Buy" },
    AutoQuest = { "QuestService.RE.Claim" },
    AutoDaily = { "DailyRewardService.RE.Claim" },
    AutoGroup = { "GroupRewardService.RE.Claim" },
    AutoOffline = { "OfflineEarningsService.RE.Claim" },
}

---@return string?, boolean  first missing module or remote, true when it is a remote
function xDTaraZ.UI.MissingFor(idx)
    for _, key in ipairs(xDTaraZ.UI.Needs[idx] or {}) do
        if GameLib[key] == nil then return key, false end
    end
    for _, path in ipairs(xDTaraZ.UI.Remotes[idx] or {}) do
        if not xDTaraZ.Net.Get(path) then return path, true end
    end
    return nil, false
end

function xDTaraZ.UI.Gate()
    local blocked = 0
    local seen = {}
    for idx in pairs(xDTaraZ.UI.Needs) do seen[idx] = true end
    for idx in pairs(xDTaraZ.UI.Remotes) do seen[idx] = true end

    for idx in pairs(seen) do
        local missing, isRemote = xDTaraZ.UI.MissingFor(idx)
        if not Library.Options[idx] or not missing then continue end
        blocked += 1
        warn("[AnimeDice] " .. idx .. " blocked, missing " .. (isRemote and "remote " or "module ") .. missing)
        local reason = isRemote and T("The game changed, waiting for a script update", "เกมอัปเดต รอสคริปต์อัปเดต")
            or T("Not available on this executor", "ใช้กับ executor นี้ไม่ได้")
        Library.Compat.Block(idx, reason)
    end
    if blocked == 0 then return end
    Library:Notify("Nova Hub", T(blocked .. " features are turned off for now", "ปิดไว้ก่อน " .. blocked .. " ฟีเจอร์"), 8, "Warning")
end

function xDTaraZ.UI.DrainHalted()
    local halted = xDTaraZ.State.Halted
    while #halted > 0 do
        local entry = table.remove(halted, 1)
        local stopKaitun = false
        for _, idx in ipairs(entry[2]) do
            local toggle = Library.Toggles[idx]
            if toggle and toggle.Value == true then toggle:SetValue(false) end
            stopKaitun = stopKaitun or table.find(xDTaraZ.Kaitun.Members, idx) ~= nil
        end

        local kaitun = Library.Toggles.Kaitun
        if stopKaitun and kaitun and kaitun.Value == true then kaitun:SetValue(false) end
        Library:Notify("Nova Hub", entry[1] .. " stopped: " .. tostring(entry[3]), 8, "Error")
    end
end

function xDTaraZ.UI.DrainNotices()
    local notices = xDTaraZ.State.Notices
    while #notices > 0 do
        local notice = table.remove(notices, 1)
        Library:Notify(notice[1], notice[2], 8, "Warning")
    end
end

function xDTaraZ.UI.BuildMain(window)
    local tab = window:AddTab(T("Home", "หน้าแรก"), "mushroom", T("Status and full auto", "สถานะและโหมดอัตโนมัติ"))

    local status = tab:AddLeftGroupbox(T("Status", "สถานะ"), "star")
    xDTaraZ.UI.Labels.Economy = status:AddParagraph({ Title = T("Economy", "เศรษฐกิจ"), Content = "-" })
    xDTaraZ.UI.Labels.Roll = status:AddParagraph({ Title = T("Rolling", "การทอย"), Content = "-" })
    xDTaraZ.UI.Labels.Units = status:AddParagraph({ Title = T("Units", "ตัวละคร"), Content = "-" })
    xDTaraZ.UI.Labels.Tower = status:AddParagraph({ Title = T("Tower", "หอคอย"), Content = "-" })

    local stats = tab:AddLeftGroupbox(T("Session Stats", "สถิติรอบนี้"), "flag")
    xDTaraZ.UI.Labels.Stats = stats:AddParagraph({ Title = T("This session", "รอบนี้"), Content = "-" })

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

    local master = tab:AddRightGroupbox(T("Kaitun", "ไคตุน"), "qblock")
    master:AddToggle("Kaitun", {
        Text = T("Kaitun (full auto)", "ไคตุน (อัตโนมัติทั้งหมด)"),
        Description = T("Rolls, levels, upgrades, grades, climbs towers and rebirths on its own", "ทอย อัปเลเวล อัปเกรด รีเกรด ไต่หอคอย และรีเบิร์ธเองทั้งหมด"),
        Callback = xDTaraZ.UI.StartStop(xDTaraZ.Kaitun),
    })
    xDTaraZ.UI.Labels.Kaitun = master:AddParagraph({ Title = T("Progress", "ความคืบหน้า"), Content = "-" })
end

function xDTaraZ.UI.BuildFarm(window)
    local tab = window:AddTab(T("Auto Farm", "ฟาร์มอัตโนมัติ"), "coin", T("Rolling, plot and levels", "ทอย ฐาน และเลเวล"))
    local rarities = xDTaraZ.UI.Values(GameLib.UnitRarities)

    local roll = tab:AddLeftGroupbox(T("Rolling", "การทอย"), "star")
    roll:AddToggle("AutoRoll", { Text = T("Fast roll", "ทอยเร็ว"), Description = T("Rolls non-stop with no roll animation", "ทอยต่อเนื่องไม่มีแอนิเมชัน") })
    roll:AddSlider("RollInterval", { Text = T("Roll interval", "ความถี่ทอย"), Min = 0.02, Max = 0.5, Default = 0.02, Rounding = 2, Suffix = "s" })
    roll:AddButton({ Text = T("Roll Once", "ทอย 1 ครั้ง"), Func = xDTaraZ.UI.Detach(function() xDTaraZ.Roll.Once() end) })
    roll:AddButton({ Text = T("Reset roll counter", "รีเซ็ตตัวนับการทอย"), Func = xDTaraZ.UI.Detach(xDTaraZ.Roll.ResetCounter) })

    local plot = tab:AddLeftGroupbox(T("Placement", "วางตัว"), "castle")
    plot:AddToggle("EquipBestUnitsAuto", { Text = T("Auto equip best", "วางตัวดีสุดอัตโนมัติ") })
    plot:AddDropdown("PlacementMode", {
        Text = T("Pick units by", "เลือกตัวตาม"),
        Description = T("Potential places your strongest units even at level 1", "ศักยภาพ = วางตัวที่เก่งจริงแม้ยังเลเวล 1"),
        Values = { "Potential", "Current income" },
        Default = "Potential",
    })
    plot:AddSlider("EquipInterval", { Text = T("Equip interval", "ความถี่วางตัว"), Min = 1, Max = 120, Default = 5, Rounding = 0, Suffix = "s" })
    plot:AddButton({ Text = T("Equip Best Now", "วางตัวดีสุดตอนนี้"), Func = xDTaraZ.UI.Detach(xDTaraZ.Plot.EquipBest) })

    local collect = tab:AddRightGroupbox(T("Collect", "เก็บเงิน"), "coin")
    collect:AddToggle("AutoCollect", { Text = T("Auto collect", "เก็บเงินอัตโนมัติ") })
    collect:AddSlider("CollectInterval", { Text = T("Collect interval", "ความถี่เก็บเงิน"), Min = 0.5, Max = 60, Default = 1, Rounding = 1, Suffix = "s" })
    collect:AddButton({ Text = T("Collect Now", "เก็บเงินตอนนี้"), Func = xDTaraZ.UI.Detach(xDTaraZ.Plot.CollectNow) })

    local level = tab:AddRightGroupbox(T("Level Up", "อัปเลเวล"), "oneup")
    level:AddToggle("AutoLevelUp", { Text = T("Auto level up", "อัปเลเวลอัตโนมัติ"), Description = T("Levels plotted units when you can afford it", "อัปเลเวลตัวบนฐานเมื่อเงินพอ") })
    level:AddDropdown("LevelMinRarity", { Text = T("Minimum rarity (plotted units)", "rarity ขั้นต่ำ (ตัวบนฐาน)"), Values = rarities, Default = xDTaraZ.UI.Prefer(rarities, "Common", 1), Searchable = true })
    level:AddSlider("LevelTarget", { Text = T("Target level", "เลเวลเป้าหมาย"), Min = 2, Max = 200, Default = 10, Rounding = 0 })
    level:AddSlider("LevelPayback", { Text = T("Max payback time", "คืนทุนไม่เกิน"), Description = T("Buys levels that pay back fast without delaying dice or rebirth", "อัปเฉพาะเลเวลที่คืนทุนเร็ว ไม่ทำให้เต๋า/รีเบิร์ธช้าลง"), Min = 10, Max = 3600, Default = 180, Rounding = 0, Suffix = "s" })
    level:AddButton({ Text = T("Run a pass", "อัปเลเวล 1 รอบ"), Func = xDTaraZ.UI.Detach(function()
        xDTaraZ.UI.Notify(T("Level Up", "อัปเลเวล"), xDTaraZ.Plot.LevelPass(true) .. " levelled", "Success")
    end) })
end

function xDTaraZ.UI.BuildEconomy(window)
    local tab = window:AddTab(T("Economy", "เศรษฐกิจ"), "shop", T("Dice, upgrades, selling, rebirth", "เต๋า อัปเกรด ขาย รีเบิร์ธ"))
    local rarities = xDTaraZ.UI.Values(GameLib.UnitRarities)

    local dice = tab:AddLeftGroupbox(T("Dice", "เต๋า"), "qblock")
    dice:AddToggle("AutoBuyDice", { Text = T("Auto buy dice", "ซื้อเต๋าอัตโนมัติ"), Description = T("Buys the luckiest dice you can afford", "ซื้อเต๋าที่ดวงดีสุดเท่าที่เงินถึง") })
    dice:AddToggle("AutoEquipBestDice", { Text = T("Equip best owned dice", "ใส่เต๋าดีสุดที่มี") })
    dice:AddButton({ Text = T("Equip Best Now", "ใส่เต๋าดีสุดตอนนี้"), Func = xDTaraZ.UI.Detach(xDTaraZ.Dice.EquipBest) })

    local upgrade = tab:AddRightGroupbox(T("Upgrades", "อัปเกรด"), "star")
    upgrade:AddToggle("AutoBuyUpgrades", { Text = T("Auto upgrades", "อัปเกรดอัตโนมัติ") })
    xDTaraZ.UI.MultiDropdown(upgrade, "UpgradeFilter", T("Branches to upgrade", "สายที่จะอัปเกรด"),
        T("Empty buys every branch", "ไม่เลือก = ซื้อทุกสาย"), xDTaraZ.UI.Values(xDTaraZ.Upgrade.Branches))
    upgrade:AddSlider("UpgradePayback", { Text = T("Max income payback", "คืนทุนรายได้ไม่เกิน"), Description = T("Buys money and luck upgrades only when they are worth it", "ซื้ออัปเกรดเงินและดวงเฉพาะตอนคุ้ม"), Min = 30, Max = 7200, Default = 1800, Rounding = 0, Suffix = "s" })
    upgrade:AddButton({ Text = T("Buy available upgrades", "ซื้ออัปเกรดที่ซื้อได้"), Func = xDTaraZ.UI.Detach(function()
        xDTaraZ.UI.Notify(T("Upgrades", "อัปเกรด"), xDTaraZ.Upgrade.BuyAll() .. " bought", "Success")
    end) })

    local sell = tab:AddLeftGroupbox(T("Sell", "ขาย"), "coin")
    sell:AddToggle("AutoSell", { Text = T("Auto sell", "ขายอัตโนมัติ"), Description = T("Never sells units on your plot or tower team", "ไม่ขายตัวที่อยู่บนฐานหรือในทีมหอคอย") })
    xDTaraZ.UI.MultiDropdown(sell, "SellRarities", T("Rarities to sell", "rarity ที่จะขาย"), nil, rarities)
    xDTaraZ.UI.MultiDropdown(sell, "SellKeepMutations", T("Mutations to keep", "mutation ที่เก็บไว้"), nil, xDTaraZ.UI.Values(GameLib.MutationNames))
    sell:AddSlider("KeepPerRarity", { Text = T("Keep best per rarity", "เก็บตัวดีสุดต่อ rarity"), Min = 0, Max = 20, Default = 0, Rounding = 0 })
    sell:AddSlider("SellInterval", { Text = T("Interval", "ความถี่"), Min = 0.5, Max = 60, Default = 2, Rounding = 1, Suffix = "s" })
    sell:AddButton({ Text = T("Sell Now", "ขายตอนนี้"), Style = "Warning", Func = xDTaraZ.UI.Detach(function()
        xDTaraZ.UI.Notify(T("Sell", "ขาย"), xDTaraZ.Sell.SellNow(), "Coin")
    end) })

    local storage = tab:AddRightGroupbox(T("Full Storage", "กระเป๋าเต็ม"), "bomb")
    storage:AddToggle("AutoClearStorage", { Text = T("Auto clear full storage", "เคลียร์กระเป๋าเมื่อเต็ม"), Description = T("Sells your weakest spare units so rolling never stops", "ขายตัวสำรองที่อ่อนสุดเพื่อให้ทอยได้ไม่หยุด") })
    storage:AddDropdown("ClearKeepRarity", { Text = T("Never clear rarity and above", "ไม่เคลียร์ rarity นี้ขึ้นไป"), Values = rarities, Default = xDTaraZ.UI.Prefer(rarities, "Mythical", math.ceil(#rarities / 2)), Searchable = true })

    local rebirth = tab:AddRightGroupbox(T("Rebirth", "รีเบิร์ธ"), "flag")
    rebirth:AddToggle("AutoRebirth", { Text = T("Auto rebirth", "รีเบิร์ธอัตโนมัติ"), Description = T("Rebirths the moment you can afford it", "รีเบิร์ธทันทีที่เงินถึง") })
    rebirth:AddButton({ Text = T("Rebirth Now", "รีเบิร์ธตอนนี้"), Style = "Primary", Func = xDTaraZ.UI.Detach(function()
        xDTaraZ.Rebirth.RebirthNow()
        xDTaraZ.UI.Notify(T("Rebirth", "รีเบิร์ธ"), xDTaraZ.Rebirth.Status)
    end) })

    local statNames = xDTaraZ.UI.Values(GameLib.RebirthStatNames)
    local stats = tab:AddLeftGroupbox(T("Rebirth Stats", "สเตตัสรีเบิร์ธ"), "oneup")
    stats:AddToggle("AutoRebirthStats", { Text = T("Auto spend points", "ลงแต้มอัตโนมัติ"), Description = T("Puts every new rebirth point into the stat below", "ลงแต้มรีเบิร์ธใหม่ทุกแต้มที่สเตตัสด้านล่าง") })
    stats:AddDropdown("RebirthStat", { Text = T("Stat", "สเตตัส"), Values = statNames, Default = xDTaraZ.UI.Prefer(statNames, "Money", 1) })
    stats:AddButton({ Text = T("Spend Points Now", "ลงแต้มตอนนี้"), Func = xDTaraZ.UI.Detach(function()
        xDTaraZ.UI.Notify(T("Rebirth Stats", "สเตตัสรีเบิร์ธ"), xDTaraZ.Rebirth.SpendPoints() .. " points spent")
    end) }):AddButton({ Text = T("Reset Stats", "รีเซ็ตสเตตัส"), Func = xDTaraZ.UI.Detach(function()
        local ok, why = xDTaraZ.Rebirth.ResetStats()
        xDTaraZ.UI.Notify(T("Rebirth Stats", "สเตตัสรีเบิร์ธ"), ok and "Reset Token used" or why)
    end) })
end

function xDTaraZ.UI.BuildUnits(window)
    local tab = window:AddTab(T("Units", "ตัวละคร"), "heart", T("Grades, traits, fusing", "เกรด trait หลอมรวม"))
    local rarities = xDTaraZ.UI.Values(GameLib.UnitRarities)
    local mutations = xDTaraZ.UI.Values(GameLib.MutationNames)
    local grades, traits = xDTaraZ.UI.Values(GameLib.GradeNames), xDTaraZ.UI.Values(GameLib.TraitNames)

    local grade = tab:AddLeftGroupbox(T("Grades", "เกรด"), "star")
    grade:AddToggle("AutoGrade", { Text = T("Auto grade", "รีเกรดอัตโนมัติ"), Description = T("Rerolls units on your plot and tower team up to the minimum", "รีเกรดตัวบนฐานและในทีมหอคอยจนถึงขั้นต่ำ") })
    grade:AddDropdown("GradeTarget", { Text = T("Minimum grade", "เกรดขั้นต่ำ"), Values = grades, Default = xDTaraZ.UI.Prefer(grades, "S", math.ceil(#grades / 2)) })
    grade:AddToggle("GradeOverwrite", { Text = T("Overwrite protected tiers (S+)", "ยอมทับเกรดที่ป้องกันไว้ (S+)"), Risky = true })
    grade:AddButton({ Text = T("Grade Once", "รีเกรด 1 ครั้ง"), Func = xDTaraZ.UI.Detach(xDTaraZ.Grade.RollOne) })

    local trait = tab:AddLeftGroupbox(T("Traits", "trait"), "shell")
    trait:AddToggle("AutoTrait", { Text = T("Auto trait", "รี trait อัตโนมัติ"), Description = T("Rerolls units on your plot and tower team up to the minimum", "รี trait ตัวบนฐานและในทีมหอคอยจนถึงขั้นต่ำ") })
    trait:AddDropdown("TraitTarget", { Text = T("Minimum trait", "trait ขั้นต่ำ"), Values = traits, Default = xDTaraZ.UI.Prefer(traits, "Samurai", math.ceil(#traits / 2)), Searchable = true })
    trait:AddToggle("TraitOverwrite", { Text = T("Overwrite protected tiers (Samurai/Shogun)", "ยอมทับ trait ที่ป้องกันไว้ (Samurai/Shogun)"), Risky = true })
    trait:AddButton({ Text = T("Trait Once", "รี trait 1 ครั้ง"), Func = xDTaraZ.UI.Detach(xDTaraZ.Trait.RollOne) })

    local lock = tab:AddRightGroupbox(T("Auto Lock", "ล็อกอัตโนมัติ"), "key")
    lock:AddToggle("AutoLock", { Text = T("Auto lock rare units", "ล็อกตัวหายากอัตโนมัติ"), Description = T("Locked units are never sold or fused", "ตัวที่ล็อกจะไม่ถูกขายหรือหลอม") })
    lock:AddDropdown("LockRarity", { Text = T("Lock rarity and above", "ล็อก rarity นี้ขึ้นไป"), Values = rarities, Default = xDTaraZ.UI.Prefer(rarities, "Secret I", #rarities - 3), Searchable = true })
    xDTaraZ.UI.MultiDropdown(lock, "LockMutations", T("Lock mutations", "ล็อก mutation"), nil, mutations)

    local gear = tab:AddRightGroupbox(T("Gear", "อุปกรณ์"), "shield")
    gear:AddToggle("AutoGear", { Text = T("Auto equip best gear", "ใส่อุปกรณ์ดีสุดอัตโนมัติ"), Description = T("Wears your rarest gear in every slot", "ใส่ชิ้นที่หายากสุดทุกช่อง") })
    gear:AddButton({ Text = T("Equip Best Now", "ใส่ดีสุดตอนนี้"), Func = xDTaraZ.UI.Detach(function()
        xDTaraZ.UI.Notify(T("Gear", "อุปกรณ์"), xDTaraZ.Gear.EquipBest() .. " slots upgraded", "Success")
    end) })

    local fuse = tab:AddRightGroupbox(T("Fusing", "หลอมรวม"), "bomb")
    fuse:AddToggle("AutoFuse", { Text = T("Auto Fuse", "หลอมอัตโนมัติ"), Description = T("Fuses spare trios only when the result is expected to be rarer and the cost is small", "หลอมตัวสำรองเฉพาะเมื่อผลที่คาดไว้หายากกว่าเดิมและค่าหลอมถูก"), Risky = true })
    xDTaraZ.UI.MultiDropdown(fuse, "FuseRarities", T("Rarities to fuse", "rarity ที่จะหลอม"), T("Empty uses any spare below the never-clear rarity", "ไม่เลือก = ใช้ตัวสำรองที่ต่ำกว่า rarity ที่ไม่เคลียร์"), rarities)
    fuse:AddButton({ Text = T("Fuse Now", "หลอมตอนนี้"), Func = xDTaraZ.UI.Detach(xDTaraZ.Fuse.FuseNow) })
end

function xDTaraZ.UI.BuildTower(window)
    local tab = window:AddTab(T("Tower", "หอคอย"), "castle", T("Tower climbing for Gems", "ไต่หอคอยเก็บ Gems"))

    local group = tab:AddLeftGroupbox(T("Auto Tower", "ไต่หอคอยอัตโนมัติ"), "castle")
    group:AddToggle("AutoTower", { Text = T("Auto tower", "ไต่หอคอยอัตโนมัติ"), Description = T("Climbs, restarts after each run and keeps going", "ไต่ จบรอบแล้วเริ่มใหม่ต่อเนื่อง") })
    local labels = xDTaraZ.UI.Values(xDTaraZ.Tower.Labels)
    group:AddDropdown("TowerDifficulty", {
        Text = T("Difficulty", "ความยาก"),
        Values = labels,
        Default = labels[1],
        Callback = function(label) xDTaraZ.Options.TowerName = xDTaraZ.Tower.NameFromLabel(label) end,
    })
    group:AddToggle("TowerSmart", { Text = T("Auto Difficulty", "ปรับความยากอัตโนมัติ"), Description = T("Moves up after a full clear and down when the team falls early", "ขึ้นหอยากขึ้นเมื่อผ่านหมด ลดลงเมื่อแพ้เร็ว") })
    if labels[1] then xDTaraZ.Options.TowerName = xDTaraZ.Tower.NameFromLabel(labels[1]) end

    local run = tab:AddRightGroupbox(T("Run Settings", "ตั้งค่ารอบ"), "flag")
    run:AddSlider("TowerStopFloor", { Text = T("Stop at floor", "หยุดที่ชั้น"), Min = 1, Max = 500, Default = 100, Rounding = 0 })
    run:AddToggle("TowerReequip", { Text = T("Re-equip before each run", "จัดทีมใหม่ก่อนทุกรอบ") })
    run:AddButton({ Text = T("Equip best team", "จัดทีมดีสุด"), Func = xDTaraZ.UI.Detach(xDTaraZ.Tower.EquipTeam) })
end

function xDTaraZ.UI.BuildItems(window)
    local tab = window:AddTab(T("Items", "ไอเทม"), "flower", T("Potions, spins, ticket shop", "ยา สปิน ร้านตั๋ว"))

    local potion = tab:AddLeftGroupbox(T("Potions", "ยาบัฟ"), "flower")
    potion:AddToggle("AutoPotion", { Text = T("Auto potion", "ใช้ยาอัตโนมัติ"), Description = T("Uses each boost only when it helps", "ใช้บัฟแต่ละตัวเฉพาะตอนมีประโยชน์") })
    xDTaraZ.UI.MultiDropdown(potion, "PotionFilter", T("Potions to use", "ยาที่จะใช้"), T("Empty uses every potion", "ไม่เลือก = ใช้ทุกชนิด"), xDTaraZ.UI.Values(GameLib.NamesOfKind, "Boost"))
    potion:AddButton({ Text = T("Use Now", "ใช้ตอนนี้"), Func = xDTaraZ.UI.Detach(function()
        xDTaraZ.UI.Notify(T("Potions", "ยาบัฟ"), xDTaraZ.Items.UsePotions(true) .. " used", "Power")
    end) })

    local spin = tab:AddRightGroupbox(T("Spins", "สปิน"), "star")
    spin:AddToggle("AutoSpin", { Text = T("Auto use spins", "ใช้สปินอัตโนมัติ"), Description = T("Uses Lucky and Jackpot spins", "ใช้ Lucky และ Jackpot spin") })
    spin:AddButton({ Text = T("Use Spins Now", "ใช้สปินตอนนี้"), Func = xDTaraZ.UI.Detach(function()
        xDTaraZ.UI.Notify(T("Spins", "สปิน"), xDTaraZ.Items.UseSpins() .. " used")
    end) })
    spin:AddToggle("AutoGamepass", { Text = T("Auto use gamepass items", "ใช้ไอเทมเกมพาสอัตโนมัติ"), Description = T("Unlocks gamepasses you got from codes and rewards", "ปลดล็อกเกมพาสที่ได้จากโค้ดและรางวัล") })

    local shop = tab:AddRightGroupbox(T("Ticket Shop", "ร้านตั๋ว"), "shop")
    shop:AddToggle("AutoTicketShop", { Text = T("Auto buy with tickets", "ซื้อด้วยตั๋วอัตโนมัติ"), Description = T("Spends quest tickets on what you pick", "ใช้ตั๋วเควสต์ซื้อของที่เลือก") })
    xDTaraZ.UI.MultiDropdown(shop, "TicketShopItems", T("Items to buy", "ของที่จะซื้อ"), nil, xDTaraZ.UI.Values(GameLib.ShopNames))
    shop:AddButton({ Text = T("Buy Now", "ซื้อตอนนี้"), Func = xDTaraZ.UI.Detach(function()
        xDTaraZ.UI.Notify(T("Ticket Shop", "ร้านตั๋ว"), xDTaraZ.Items.BuyTicketShop() .. " bought", "Coin")
    end) })
end

function xDTaraZ.UI.BuildRewards(window)
    local tab = window:AddTab(T("Rewards", "รางวัล"), "key", T("Codes, daily, quests", "โค้ด รายวัน เควสต์"))

    local codes = tab:AddLeftGroupbox(T("Codes", "โค้ด"), "qblock")
    codes:AddButton({ Text = T("Redeem All Codes", "แลกโค้ดทั้งหมด"), Style = "Primary", Func = xDTaraZ.UI.Detach(function()
        xDTaraZ.UI.Notify(T("Codes", "โค้ด"), xDTaraZ.Rewards.RedeemAll(), "Success")
    end) })

    local quest = tab:AddLeftGroupbox(T("Quests", "เควสต์"), "flag")
    quest:AddToggle("AutoQuest", { Text = T("Auto claim quests", "รับรางวัลเควสต์อัตโนมัติ") })
    quest:AddButton({ Text = T("Claim now", "รับตอนนี้"), Func = xDTaraZ.UI.Detach(function()
        xDTaraZ.UI.Notify(T("Quests", "เควสต์"), xDTaraZ.Rewards.ClaimQuests() .. " claimed", "Success")
    end) })

    local claims = tab:AddRightGroupbox(T("Claims", "รับรางวัล"), "coin")
    claims:AddToggle("AutoDaily", { Text = T("Auto daily reward", "รับรางวัลรายวันอัตโนมัติ") })
    claims:AddToggle("AutoGroup", { Text = T("Auto group reward", "รับรางวัลกลุ่มอัตโนมัติ") })
    claims:AddToggle("AutoOffline", { Text = T("Auto offline earnings", "รับรายได้ออฟไลน์อัตโนมัติ") })
end

function xDTaraZ.UI.BuildPlayer(window)
    local tab = window:AddTab(T("Player", "ผู้เล่น"), "oneup", T("Movement and utility", "การเคลื่อนที่และอรรถประโยชน์"))

    local move = tab:AddLeftGroupbox(T("Movement", "การเคลื่อนที่"), "gear")
    move:AddToggle("WalkSpeed", { Text = T("Walk speed", "ความเร็วเดิน"), Callback = xDTaraZ.UI.Detach(function(on)
        if on then xDTaraZ.Move.SpeedStart() else xDTaraZ.Move.SpeedStop() end
    end) })
    move:AddSlider("WalkSpeedValue", { Text = T("Speed", "ความเร็ว"), Min = 16, Max = 200, Default = 32, Rounding = 0 })
    move:AddToggle("InfiniteJump", { Text = T("Infinite jump", "กระโดดไม่จำกัด"), Callback = xDTaraZ.UI.Detach(function(on)
        if on then xDTaraZ.Move.JumpStart() else xDTaraZ.Move.JumpStop() end
    end) })

    local util = tab:AddLeftGroupbox(T("Utility", "อรรถประโยชน์"), "star")
    util:AddToggle("AntiAfk", { Text = T("Anti-AFK", "กันหลุด AFK"), Callback = xDTaraZ.UI.StartStop(xDTaraZ.AntiAfk) })
    util:AddToggle("AutoRejoin", { Text = T("Auto rejoin", "รีจอยน์อัตโนมัติ"), Description = T("Rejoins after a disconnect and resumes Kaitun", "เข้าเกมใหม่เมื่อหลุดและทำไคตุนต่อ"), Callback = xDTaraZ.UI.StartStop(xDTaraZ.Rejoin) })
    util:AddToggle("DisableCutscene", { Text = T("Disable cutscenes", "ปิดคัตซีน"), Description = T("Skips roll and fuse reveal cutscenes", "ข้ามคัตซีนตอนทอยและหลอม"), Callback = function(on)
        if not on then xDTaraZ.Cutscene.Restore() end
    end })

    local air = tab:AddRightGroupbox(T("Fly and No Clip", "บินและทะลุกำแพง"), "pipe")
    air:AddToggle("NoClip", { Text = T("No clip", "ทะลุกำแพง"), Callback = xDTaraZ.UI.Detach(function(on)
        if on then xDTaraZ.Move.NoClipStart() else xDTaraZ.Move.NoClipStop() end
    end) }):AddKeyPicker("NoClipKey", { Default = "None", Mode = "Toggle" })
    air:AddToggle("Fly", { Text = T("Fly", "บิน"), Callback = xDTaraZ.UI.Detach(function(on)
        if on then xDTaraZ.Move.FlyStart() else xDTaraZ.Move.FlyStop() end
    end) }):AddKeyPicker("FlyKey", { Default = "None", Mode = "Toggle" })
    air:AddSlider("FlySpeed", { Text = T("Fly speed", "ความเร็วบิน"), Min = 20, Max = 300, Default = 60, Rounding = 0 })

    local alerts = tab:AddRightGroupbox(T("Rare Alerts", "แจ้งเตือนของหายาก"), "bell")
    alerts:AddToggle("RareNotify", { Text = T("Alert on rare pulls", "แจ้งเตือนเมื่อได้ของหายาก") })
    xDTaraZ.UI.MultiDropdown(alerts, "NotifyRarities", T("Rarities", "rarity"), nil, xDTaraZ.UI.Values(GameLib.UnitRarities))
    xDTaraZ.UI.MultiDropdown(alerts, "NotifyMutations", T("Mutations", "mutation"), nil, xDTaraZ.UI.Values(GameLib.MutationNames))
    alerts:AddInput("WebhookUrl", { Text = T("Discord webhook", "Discord webhook"), Default = "", Placeholder = T("Optional webhook URL", "ลิงก์ webhook (ไม่ใส่ก็ได้)"), Finished = true })
    alerts:AddButton({ Text = T("Send test alert", "ทดสอบแจ้งเตือน"), Func = xDTaraZ.UI.Detach(function()
        local rarities, mutations = xDTaraZ.UI.Lists.Rarities, xDTaraZ.UI.Lists.Mutations
        xDTaraZ.Watch.Alert({ Name = "Test", Rarity = rarities[#rarities] or "?", Mutation = mutations[#mutations] })
    end) })
end

function xDTaraZ.UI.RefreshStatus()
    local labels = xDTaraZ.UI.Labels
    if not labels.Kaitun then return end

    labels.Economy:SetContent(string.format("$%s · R%d · Gems %s · Tickets %s",
        Util.FormatNumber(xDTaraZ.Data.Money()), xDTaraZ.Data.Rebirth(),
        Util.FormatNumber(xDTaraZ.Data.Token("Gems")), Util.FormatNumber(xDTaraZ.Data.Token("Tickets"))))
    labels.Roll:SetContent(xDTaraZ.Roll.GetStatus())
    labels.Units:SetContent(string.format("Storage %s · Grade: %s · Trait: %s", xDTaraZ.Storage.Status, xDTaraZ.Grade.Status, xDTaraZ.Trait.Status))
    labels.Tower:SetContent(xDTaraZ.Tower.GetStatus())
    labels.Kaitun:SetContent(xDTaraZ.Kaitun.GetStatus() .. "\nUpgrades: " .. xDTaraZ.Upgrade.Status .. "\nLevels: " .. xDTaraZ.Plot.Status)
    labels.Stats:SetContent(table.concat(xDTaraZ.Watch.Stats(), "\n"))
end

function xDTaraZ.UI.BindOptions()
    for key in pairs(xDTaraZ.Options) do
        local widget = Library.Options[key]
        if widget and widget.OnChanged then
            xDTaraZ.Options[key] = widget.Value
            widget:OnChanged(function(value)
                xDTaraZ.Options[key] = value
                if value == true then xDTaraZ.Scheduler.Resume(key) end
            end)
        end
    end
end

function xDTaraZ.UI.Build()
    local window = Library.Window
    xDTaraZ.UI.Lists = { Rarities = xDTaraZ.UI.Values(GameLib.UnitRarities), Mutations = xDTaraZ.UI.Values(GameLib.MutationNames) }
    local layout = {
        { T("Main", "หลัก"), "Main", xDTaraZ.UI.BuildMain },
        { T("Farming", "ฟาร์ม"), "Farm", xDTaraZ.UI.BuildFarm },
        { nil, "Tower", xDTaraZ.UI.BuildTower },
        { T("Progression", "พัฒนา"), "Units", xDTaraZ.UI.BuildUnits },
        { nil, "Economy", xDTaraZ.UI.BuildEconomy },
        { nil, "Items", xDTaraZ.UI.BuildItems },
        { nil, "Rewards", xDTaraZ.UI.BuildRewards },
        { T("Misc", "อื่นๆ"), "Player", xDTaraZ.UI.BuildPlayer },
    }
    for _, section in ipairs(layout) do
        if section[1] then window:AddTabSection(section[1]) end
        Util.Try("ui " .. section[2], section[3], window)
    end
    Util.Try("ui settings", window.AddSettingsTab, window)

    Util.Try("ui bind", xDTaraZ.UI.BindOptions)
    Util.Try("ui gate", xDTaraZ.UI.Gate)
    Library:Every(xDTaraZ.Config.StatusInterval, xDTaraZ.UI.RefreshStatus)
    Library:Every(xDTaraZ.Config.StatusInterval, xDTaraZ.UI.DrainHalted)
    Library:Every(xDTaraZ.Config.StatusInterval, xDTaraZ.UI.DrainNotices)
end

local function BuildInterface()
    local lib, problem = Util.LoadLibrary(xDTaraZ.Config.UiSource)
    if not lib then
        Util.Alert(problem)
        return
    end
    Library = lib
    pcall(NovaBanner.Step, "UI library")
    xDTaraZ.Library = Library
    T = function(en, th) return Library:T(en, th) end
    Library:CreateWindow({
        Title = "Nova Hub",
        SubTitle = "Anime Dice by xDTaraZ",
        MenuKey = Enum.KeyCode.LeftControl,
        ConfigFolder = xDTaraZ.Config.SaveFolder,
        Language = "Auto",
        Theme = "Nova",
        Intro = true,
        OnUnlocked = function()
            xDTaraZ.UI.Build()
            task.defer(Util.Try, "boot", xDTaraZ.Boot)
            task.defer(function()
                Util.Try("autoload config", Library.LoadAutoloadConfig, Library)
                if environment.AnimeDiceResume then
                    environment.AnimeDiceResume = nil
                    if Library.Toggles.Kaitun then Library.Toggles.Kaitun:SetValue(true) end
                end
            end)
        end,
    })
    Library:OnUnload(function()
        xDTaraZ:Unload()
    end)
    return true
end

function xDTaraZ.Boot()
    xDTaraZ:Connect(LocalPlayer.CharacterAdded, function(character)
        xDTaraZ.Player:Bind(character)
        task.defer(xDTaraZ.Move.Rebind)
    end)
    xDTaraZ.Roll.ResetCounter()

    local options, config = xDTaraZ.Options, xDTaraZ.Config
    local every = xDTaraZ.Scheduler.Every
    every("Roll", function() return options.RollInterval end, xDTaraZ.Roll.Step, { "AutoRoll" })
    every("Collect", function() return options.CollectInterval end, xDTaraZ.Plot.CollectStep, { "AutoCollect" })
    every("Equip", function() return options.EquipInterval end, xDTaraZ.Plot.EquipStep, { "EquipBestUnitsAuto" })
    every("Economy", 1, xDTaraZ.Economy.Step, { "AutoBuyDice", "AutoEquipBestDice", "AutoRebirth", "AutoRebirthStats", "AutoBuyUpgrades", "AutoLevelUp" })
    every("Sell", function() return options.SellInterval end, xDTaraZ.Sell.Step, { "AutoSell" })
    every("Storage", 1, xDTaraZ.Storage.Step, { "AutoClearStorage" })
    every("Grade", config.GradeDelay, xDTaraZ.Grade.Step, { "AutoGrade" })
    every("Trait", config.TraitDelay, xDTaraZ.Trait.Step, { "AutoTrait" })
    every("Fuse", config.FuseDelay, xDTaraZ.Fuse.Step, { "AutoFuse" })
    every("Tower", config.TowerTick, xDTaraZ.Tower.Step, { "AutoTower" })
    every("Items", config.RewardsInterval, xDTaraZ.Items.Step, { "AutoPotion", "AutoSpin", "AutoGamepass", "AutoTicketShop" })
    every("Gear", config.RewardsInterval, xDTaraZ.Gear.Step, { "AutoGear" })
    every("Watch", 1, xDTaraZ.Watch.Step, { "RareNotify" })
    every("Lock", config.RewardsInterval, xDTaraZ.Lock.Step, { "AutoLock" })
    every("Rewards", config.RewardsInterval, xDTaraZ.Rewards.Step, { "AutoDaily", "AutoGroup", "AutoOffline", "AutoQuest" })
    every("Speed", 1, xDTaraZ.Move.ApplyWalkSpeed, { "WalkSpeed" })
    every("Cutscene", 1, xDTaraZ.Cutscene.Step, { "DisableCutscene" })
    xDTaraZ.Scheduler.Boot()
end

function xDTaraZ:Unload()
    self.State.Alive = false
    if environment.AnimeDiceUnload == self.State.UnloadEntry then environment.AnimeDiceUnload = nil end
    self.Options.AutoTower = false
    if xDTaraZ.Tower.State ~= "Idle" then xDTaraZ.Tower.Leave() end
    xDTaraZ.Move.SpeedStop()
    xDTaraZ.Move.NoClipStop()
    xDTaraZ.Move.FlyStop()
    xDTaraZ.Cutscene.Restore()
    for _, connection in ipairs(self.State.Connections) do
        pcall(function() connection:Disconnect() end)
    end
    table.clear(self.State.Connections)
end

xDTaraZ.State.UnloadEntry = function()
    if xDTaraZ.Library and not xDTaraZ.Library.Unloaded then
        xDTaraZ.Library:Unload()
    else
        xDTaraZ:Unload()
    end
end
environment.AnimeDiceUnload = xDTaraZ.State.UnloadEntry

if LocalPlayer.Character then
    xDTaraZ.Player:Bind(LocalPlayer.Character)
end

pcall(NovaBanner.Step, "Systems")
if BuildInterface() then
    pcall(NovaBanner.Step, "Interface")
    pcall(NovaBanner.Ready)
end]==]

NOVA_HUB_MODULES[10035204815] = [==[if not game:IsLoaded() then game.Loaded:Wait() end
if game.GameId ~= 10035204815 then game:GetService("Players").LocalPlayer:Kick("Nova Hub: this script is for Ride A Pet only") return end

do
    local ok, env = pcall(getgenv)
    if ok and type(env) == "table" and type(env.RideAPetUnload) == "function" then
        pcall(env.RideAPetUnload)
    end
end

if not LPH_OBFUSCATED then
    local function Passthrough(fn) return fn end
    LPH_JIT, LPH_JIT_MAX, LPH_NO_VIRTUALIZE = Passthrough, Passthrough, Passthrough
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")
local VirtualUser = game:GetService("VirtualUser")

local LocalPlayer = Players.LocalPlayer
local Library

local xDTaraZ = setmetatable({}, {
    __newindex = function(self, key, value)
        rawset(self, key, type(value) == "function" and LPH_JIT(value) or value)
    end,
})

xDTaraZ.Config = {
    GameId = 10035204815, PlaceId = 124216119978534,
    Tag = "[RideAPet]",

    Discord = "https://discord.gg/FHVfmeSceA",
    UiSource = "NovaHub://embedded-ui",
    LoadTimeout = 10, GameLibDeadline = 8,
    AlertTries = 8, AlertGap = 1.5, WarnGap = 5,

    PickupReach = 84,
    PickupLimit = 90,
    PickupRetryStep = 0.04,
    PickupReplyTimeout = 0.6,
    PickupTotalTimeout = 1.5,
    TpSettle = 0.1, VolcanoSettle = 0.3, DismountTimeout = 10, DismountToolWindow = 2,
    DropOutside = 4,
    DropSettle = 0.2,
    DropSettleMax = 0.35,
    DropEndsSlack = 0.03,
    DropAppearTimeout = 1.0,
    StaleDropDistance = 20,
    DepositTimeout = 1.5,
    RunBudget = 4.0,
    DirectFactor = 2.5,
    DirectFactorAfterFail = 2.0,
    ReturnBackoff = { 2.0, 1.5 }, ReturnStopCount = 3, ReturnWindow = 300, ReturnDedupe = 3,
    UnmountedDirect = 90, WeightPenalty = 0.01, CherubWeightPenalty = 0.0125, WeightPenaltyMax = 0.8,
    ContainsSlack = 2, EdgeInset = 1, StandLift = 3,
    TripCost = { Plot = 0.35, Direct = 0.62, Drop = 1.25 },
    ContestWeight = 1.5, ContestWeightMax = 3, ContestHorizon = 6, UnmountedPlayerSpeed = 36,
    CycleLength = 420, CycleOffset = 418.5, WaveSurge = 12, WaveWakeEarly = 2,
    GoneBlacklistSec = 2,
    MountTimeout = 1.5, MountTries = 3, MountGap = 0.35,
    CarryDeferCap = 3,
    EggTick = 0.05, SlowTick = 1, EspTick = 0.25, EspTickMobile = 0.5,
    EspRange = 4000, EspRangeMobile = 1500,
    FailLimit = 5, FailWindow = 10,
    PlantSpacing = 6, PlantCapDefault = 10, HatchGap = 0.3,
    CollectMinPending = 60, SellRange = 9, SellBatch = 50, ConfirmWindow = 2,
    ShopBuyGap = 0.15, AfkRejoinSec = 1100,
    HunterHopsPerCycle = 5, HunterMinLeft = 90,
    VolcanoCenter = Vector3.new(-5103, 41406, -3489), VolcanoResultTimeout = 20, VolcanoMinBreakLeft = 3,
    PumpTick = 0.5, PlotRetry = 1, MobileViewport = 900,
    UnloadCarryTimeout = 2,
    JobTick = {
        Volcano = 0.25, Junk = 0.25, Hatch = 1, Plant = 2, Pets = 2,
        Feed = 1, Sell = 10, Fusion = 2, Economy = 3, Shop = 5, Rewards = 30, Boosts = 5, Server = 5,
        Webhook = 1, Settle = 1, Kaitun = 2,
    },
    JobBackoff = 40,

    VolcanoStreamTimeout = 5,
    VolcanoTouchEvery = 0.25,
    VolcanoStepWait = 5,
    VolcanoStandLift = 3,
    VolcanoRetry = 30,
    VolcanoDipSettle = 0.7,
    VolcanoTpTries = 4,
    VolcanoRefire = 0.3,
    VolcanoTailEggs = 1,
    VolcanoClaimSec = 2,

    PlantReplyTimeout = 1.5,
    PlantTries = 3,
    EquipSettle = 0.1,
    HatchPending = 5,
    PlotEggsRefresh = 60, PlotFullRecheck = 10,
    PlantStandLift = 3,
    PlantLongGrow = 3600,
    PlantLongShare = 0.5,

    JunkEquipSettle = 0.1,
    JunkSpacing = 0.2,
    JunkSpacingMin = 0.1,
    JunkSpacingMax = 1,
    JunkSpacingUp = 0.05,
    JunkSpacingDown = 0.02,
    JunkSpacingEase = 20,
    JunkPlantTimeout = 0.9,
    JunkPlantFails = 8,
    JunkHatchRetry = 0.8,
    JunkHatchSlack = 0.02,
    JunkHatchSlackMax = 0.3,
    JunkHatchGapMax = 0.3,
    JunkHatchGapStep = 0.02,
    JunkSellEvery = 60,
    JunkQueueTtl = 30,
    JunkIdleCheck = 5,
    JunkResyncIdle = 8,
    JunkFullPause = 0.6,
    JunkAutoShare = 0.2,
    JunkShareSample = 200,
    JunkSessionMax = 45,
    JunkYieldGap = 3,
    JunkBackoff = 10,
    JunkRateWindow = 60,
    JunkReportGap = 0.5,
    JunkAnchorNear = 4,
    JunkPlotShare = 0.5,
    JunkYieldTo = {
        "AutoEquipBest", "AutoCollectCash", "AutoFeed", "AutoFusion", "AutoPlaceEggs",
    },

    PetReplyTimeout = 1.5,
    PetSwapGain = 1.01,
    PetSpread = 0.35,
    PetStandLift = 3,
    PetBaseKg = 10,
    PetMaxAge = 100,
    CollectGap = 0.15,
    FeedGap = 0.36, FeedBurst = 8, FeedMissLimit = 3, FeedReplyTimeout = 1,
    TopCacheSec = 1,
    AutoCollectPass = { "AutoCollect", "1940707069" },
    PetAgeRefresh = 30,
    PetWatchedAttrs = {
        PetKey = true, PetName = true, Weight = true, BaseWeight = true, Mutation = true,
        SpawnMutation = true, Age = true, BirthTime = true, Favorited = true,
    },

    SellReplyTimeout = 8,
    SellRetry = 0.45,
    SellTries = 5,
    SellNear = 3,
    SellPriceMult = 600,
    SellStand = 5,
    IncomeSettle = 1.5,
    SellSettle = 0.6,
    FuseSlots = 4,
    FuseStand = 3,
    FuseLift = 3,
    FuseSettle = 0.15,
    FuseReplyTimeout = 2,
    FuseGap = 0.3,
    FusePlaceSettle = 1,
    FuseResultTimeout = 5,
    WeekSec = 604800,
    SellKeepTopRarities = 3,

    UpgradePayback = 300,
    UpgradeBatch = 25,
    UpgradeGap = 0.1,
    UpgradeVerify = 1.5,
    UpgradeBackoff = 30,
    UpgradeMaxBuy = 1000,
    RebirthSaveWindow = 1800,
    RebirthVerify = 3,
    RebirthBackoff = 60,
    ShopReplyTimeout = 3,
    ShopRecheck = 300,
    ClaimVerify = 2,
    PromptRetry = 3600,
    GroupRewardCooldown = 86400,
    BoostAttributes = {
        "HatchLuckEventMultiplier", "HatchLuckEventUntil", "HatchMutationEventMultiplier",
        "HatchMutationEventUntil", "HatchSpeedBoostAmount", "HatchSpeedBoostUntil", "GlobalCashBoostUntil",
    },

    KaitunToggles = {
        "AutoEggs", "EggHunter", "AutoPlaceEggs", "AutoHatch", "AutoEquipBest",
        "AutoCollectCash", "AutoUpgrade", "AutoClaim", "SmartSpend",
    },
    KaitunHuntRarity = "Mythic",
    KaitunSteerEvery = 60,

    UpdateLog = {
        { "2026-10-05", "Teleport To Best Egg is back (Home tab)\nFixed Volcano Dip sometimes not reaching the volcano after picking up an egg\nAuto Feed is about 5x faster\nFixed Auto Place Eggs saying the plot is full when it is not\nFixed Volcano Dip and Auto Volcano Egg doing nothing unless Auto Eggs was on\nA returned egg no longer stops the whole farm, it slows delivery and keeps going\nAuto Reconnect after a disconnect\nWeather alerts now name the storm type\nScript rebuilt from scratch for the new game update\nEggs reach your base every time, no more returned eggs\nMuch less lag while farming with a big inventory\nClear Junk Eggs: hatch cheap eggs and sell the pets\nMinimum Egg Rarity to farm rare eggs only\nFixed Auto Place Best Pets swapping out good pets\nPerformance: Boost FPS, hide other pets and eggs, FPS cap, disable 3D\nFixed the inventory bar not coming back after farming\nRemoved the Stop All button" },
        { "2026-10-04", "Rebuilt egg collecting: faster trips and no more returned eggs\nRide pet picker, rare egg hunter and plant order\nPet protect list, safer selling and smarter spending\nClear Junk Eggs now sells what it hatches, and Minimum Egg Rarity skips cheap eggs" },
    },
}

xDTaraZ.State = {
    Alive = true, Connections = {}, Halted = {}, Errors = {},
    Tune = { DropSettle = 0.2, ContestWeight = 1.5, DirectFactor = 2.5 },
    Status = {},
    PendingSet = {},
    PendingToggleOff = {},
    PendingNotify = {},
    LastFail = nil,
    Stats = { delivered = 0, lost = 0, returned = 0, plot = 0, direct = 0, drop = 0, staleDrops = 0, window = {} },
    PlotEggs = {}, PlantCap = 10, Weather = {},
    WarnedAt = {},
}

xDTaraZ.Options = {}

local Config, State = xDTaraZ.Config, xDTaraZ.State

Config.JobTick.Eggs, Config.JobTick.Hunter = Config.EggTick, Config.EggTick

State.Tune.DropSettle = Config.DropSettle
State.Tune.ContestWeight = Config.ContestWeight
State.Tune.DirectFactor = Config.DirectFactor
State.PlantCap = Config.PlantCapDefault

xDTaraZ.Util = {}

---@return boolean, any  ok, fn result or the error
function xDTaraZ.Util.Try(label, fn, ...)
    local ok, err = pcall(fn, ...)
    if ok then return true, err end

    local now = os.clock()
    if now - (State.WarnedAt[label] or -math.huge) >= Config.WarnGap then
        State.WarnedAt[label] = now
        warn(Config.Tag .. " " .. label .. ":", err)
    end
    return false, err
end

---@return string|nil, string|nil  body, or nil and why every transport failed
function xDTaraZ.Util.HttpGet(url)
    if url == "NovaHub://embedded-ui" then return NOVA_HUB_UI_SOURCE end
    local ok, body = pcall(game.HttpGet, game, url)
    if ok and type(body) == "string" then return body end

    local requester = (syn and syn.request) or (http and http.request) or http_request or request
    if not requester then return nil, "no http function" end

    local sent, response = pcall(requester, { Url = url, Method = "GET" })
    if not sent or type(response) ~= "table" then return nil, tostring(response) end
    if response.StatusCode ~= 200 or type(response.Body) ~= "string" then
        return nil, "HTTP " .. tostring(response.StatusCode)
    end
    return response.Body
end

---@param detail any  console only
function xDTaraZ.Util.Alert(text, detail)
    warn(Config.Tag, text, detail or "")
    task.spawn(function()
        for _ = 1, Config.AlertTries do
            local shown = pcall(StarterGui.SetCore, StarterGui, "SendNotification", { Title = "Nova Hub", Text = text, Duration = 10 })
            if shown then return end
            task.wait(Config.AlertGap)
        end
    end)
end

---@return table|nil  UI library, nil after an on-screen alert
function xDTaraZ.Util.LoadLibrary(url)
    local source, why = xDTaraZ.Util.HttpGet(url)
    if not source or not source:sub(-64):find("return%s+Library%s*$") then
        xDTaraZ.Util.Alert("Could not download the menu. Check your connection and run it again.", why or "truncated download")
        return nil
    end

    local chunk, compileErr = loadstring(source)
    if type(chunk) ~= "function" then
        xDTaraZ.Util.Alert("The menu failed to load on this executor.", compileErr)
        return nil
    end

    local ok, lib = pcall(chunk)
    if not ok or type(lib) ~= "table" then
        xDTaraZ.Util.Alert("The menu failed to load on this executor.", lib)
        return nil
    end
    return lib
end

function xDTaraZ.Util.Copy(text)
    local copier = setclipboard or toclipboard
    if not copier then return false end
    return (pcall(copier, text))
end

---@return boolean  queued for the next server
function xDTaraZ.Util.Queue(src)
    if not (Library and Library.Compat and Library.Compat.Caps.Queue) then return false end
    local queue = queue_on_teleport or queueonteleport
    if not queue then return false end
    return (pcall(queue, src))
end

function xDTaraZ.Util.ServerNow()
    return Workspace:GetServerTimeNow()
end

---@return number  XZ distance
function xDTaraZ.Util.Flat(a, b)
    local dx, dz = a.X - b.X, a.Z - b.Z
    return math.sqrt(dx * dx + dz * dz)
end

function xDTaraZ.Util.Format(n)
    n = tonumber(n) or 0
    if n ~= n or n == math.huge then return "-" end

    local suffixes = { "", "K", "M", "B", "T", "Qa", "Qi", "Sx" }
    local step = 1
    repeat
        if math.abs(n) < 1000 then break end
        n /= 1000
        step += 1
    until step == #suffixes
    if step == 1 then return tostring(math.floor(n)) end
    return string.format("%.2f%s", n, suffixes[step])
end

---@return any  option value; the UI mirror first, then the live option
function xDTaraZ.Util.Opt(idx)
    local mirrored = xDTaraZ.Options[idx]
    if mirrored ~= nil then return mirrored end
    local option = Library and Library.Options and Library.Options[idx]
    return option and option.Value
end

---@param seconds number|nil
function xDTaraZ.Util.Notify(title, text, seconds)
    table.insert(State.PendingNotify, { title, text, seconds or 5 })
end

do
    local camera = Workspace.CurrentCamera
    local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
    local touch = UserInputService.TouchEnabled
    local noKeys = not UserInputService.KeyboardEnabled and not UserInputService.MouseEnabled

    xDTaraZ.Platform = {
        Touch = touch,
        Mobile = touch and (noKeys or viewport.X < Config.MobileViewport),
        Console = GuiService:IsTenFootInterface(),
        Viewport = viewport,
    }
end

---@return boolean  false when the executor has no working fps cap
function xDTaraZ.Util.SetFpsCap(fps)
    local ok = pcall(function() setfpscap(fps) end)
    return ok
end

function xDTaraZ:Connect(signal, handler)
    local conn = signal:Connect(handler)
    table.insert(self.State.Connections, conn)
    return conn
end

xDTaraZ.StopOrder = {
    "Kaitun", "Guard", "Eggs", "Hunter", "Volcano", "Junk", "Hatch", "Pets", "Sell", "Fusion",
    "Economy", "Shop", "Rewards", "Boosts", "Troll", "Server", "Webhook", "Visual",
}

function xDTaraZ:Unload()
    if not State.Alive or State.Unloading then return end
    State.Unloading = true
    local try = xDTaraZ.Util.Try

    try("unload carry", function() xDTaraZ.Eggs.FinishCarry(Config.UnloadCarryTimeout) end)
    State.Alive = false
    try("unload tasks", function() xDTaraZ.Tasks.ReleaseAll("unload") end)
    for _, name in ipairs(xDTaraZ.StopOrder) do
        local module = rawget(xDTaraZ, name)
        if module and module.Stop then try("unload " .. name, module.Stop) end
    end
    try("unload character", function() xDTaraZ.Player:Release() end)
    try("unload inventory", function() xDTaraZ.Eggs.QuietInventory(false, true) end)
    State.TeardownPending = true
    if not State.TeardownConn then xDTaraZ.Teardown() end
end

function xDTaraZ.Teardown()
    State.TeardownPending = false
    if State.TeardownConn then
        State.TeardownConn:Disconnect()
        State.TeardownConn = nil
    end
    local try = xDTaraZ.Util.Try

    try("unload move", function() xDTaraZ.Move.Restore() end)
    try("unload esp", function() xDTaraZ.Esp.Clear() end)
    try("unload hooks", function() Library.Compat.RestoreAll() end)

    try("unload player", function() xDTaraZ.Player:Unbind() end)
    for _, conn in ipairs(State.Connections) do
        if type(conn) == "function" then conn() else conn:Disconnect() end
    end
    table.clear(State.Connections)

    try("unload ui", function() Library:Unload() end)
end

---@param signal RBXScriptSignal  fired on a thread that never calls game code
function xDTaraZ.BindTeardown(signal)
    State.TeardownConn = signal:Connect(function()
        if State.TeardownPending then xDTaraZ.Teardown() end
    end)
end

do
    local ok, env = pcall(getgenv)
    if ok and type(env) == "table" then
        env.RideAPetUnload = function() xDTaraZ:Unload() end
    end
end

xDTaraZ.GameLib = {
    Data = {}, Svc = {}, Missing = {},
    Cache = {}, NetSearched = false,
    EggInfo = {}, PetInfo = {}, RarityOrder = {}, RarityRank = {},
    Foods = {}, FoodOrder = {}, ShopItems = {}, Rebirths = { Cap = 0, Costs = {} }, RebirthReq = {},
    IndexStages = {}, Mutations = {},
}

local GameLib = xDTaraZ.GameLib

GameLib.DataModules = {
    "Pets", "Eggs", "Spawns", "General", "Rebirths", "HatchLuck", "Mutations", "Weather",
    "Foods", "Shop", "IndexRewards", "Volcano", "Fusion", "EggBaskets",
}
GameLib.ServiceModules = { "General", "EggCycle", "DayNight", "EggDeliveryRules", "SellValue", "PetAging" }

GameLib.Denied = {
    Restock = true, SetOpenShop = true, RegisterSkipTarget = true, RegisterSkipAllTarget = true,
    UpdatePlayerToGift = true, CanGiftGamepass = true, CmdrFunction = true, PetMove = true,
    EggTimerPause = true, EggArrivalClaim = true,
    ["Reusable.Ban"] = true, ["Reusable.GetPlayerData"] = true, ["Reusable.InitiatePlot"] = true,
    ["Reusable.ClaimGroupReward"] = true, ["Reusable.ClaimEventReward"] = true, ["Reusable.Teleporting"] = true,
}
GameLib.DeniedPrefix = { "SkipGrowth" }
GameLib.ListenOnly = { Restock = true }

GameLib.Needs = {
    AutoEggs = { "EggPickup", "BasketDrop", "Mounting", "GameMessage", "ActiveEggs" },
    EggHunter = { "EggPickup", "BasketDrop", "ActiveEggs" },
    VolcanoDip = { "EggPickup", "BasketDrop", "VolcanoDip", "VolcanoDipResult" },
    VolcanoObby = { "EggPickup", "BasketDrop", "ActiveEggs" },
    AutoPlaceEggs = { "EggPlaced" },
    AutoHatch = { "Hatch" },
    ClearJunk = { "EggPlaced", "Hatch", "SellItems", "ConfirmRequest" },
    AutoEquipBest = { "PlacePet", "PickupPet" },
    AutoCollectCash = { "PetCollect" },
    AutoFeed = { "FeedPet" },
    AutoSell = { "SellItems", "ConfirmRequest" },
    AutoFusion = { "FusionPetPlace", "FusionAction" },
    AutoUpgrade = { "Plot.Upgrades" },
    AutoRebirth = { "Rebirth" },
    AutoShop = { "ShopStock", "BuyWithCash" },
    AutoClaim = { "ClaimIndexReward", "OfflineEarnings" },
    Kaitun = { "EggPickup", "BasketDrop", "ActiveEggs" },
}

---@return boolean, any  ok, module or error; retried from an identity-2 thread
function GameLib.RequireAsGame(module)
    local done, ok, loaded = false, false, nil
    task.spawn(function()
        local switched = pcall(setthreadidentity, 2)
        if switched then ok, loaded = pcall(require, module) end
        done = true
    end)

    local deadline = os.clock() + xDTaraZ.Config.LoadTimeout
    repeat
        if done then break end
        task.wait()
    until os.clock() > deadline
    return ok, loaded
end

---@return table|nil
function GameLib.Require(module)
    if typeof(module) ~= "Instance" or not module:IsA("ModuleScript") then return nil end

    local ok, loaded
    if Library and Library.Compat then
        ok, loaded = Library.Compat.Require(module)
    else
        ok, loaded = pcall(require, module)
        if not ok and tostring(loaded):find("non-RobloxScript", 1, true) then
            ok, loaded = GameLib.RequireAsGame(module)
        end
    end

    if ok and type(loaded) == "table" then return loaded end
    warn(xDTaraZ.Config.Tag, "require " .. module.Name .. ":", loaded)
    return nil
end

---@return boolean, ...  ok, then the game function's results or the error
function GameLib.Call(fn, ...)
    if type(fn) ~= "function" then return false, "not a function" end
    if Library and Library.Compat then
        return pcall(Library.Compat.Call, fn, ...)
    end
    return pcall(fn, ...)
end

---@return boolean
function GameLib.IsDenied(name)
    if GameLib.Denied[name] then return true end
    for _, prefix in ipairs(GameLib.DeniedPrefix) do
        if name:sub(1, #prefix) == prefix then return true end
    end
    return false
end

---@return Instance|nil  the packages Net folder, found once whatever the _Index version
function GameLib.NetFolder()
    if GameLib.NetSearched then return GameLib.NetFolderRef end
    GameLib.NetSearched = true

    local packages = ReplicatedStorage:FindFirstChild("packages")
    if not packages then return nil end
    local direct = packages:FindFirstChild("Net")
    if direct then
        GameLib.NetFolderRef = direct
        return direct
    end

    for _, node in ipairs(packages:GetDescendants()) do
        if node.Name ~= "Net" then continue end
        for _, child in ipairs(node:GetChildren()) do
            if child.Name:sub(1, 3) == "RE/" then
                GameLib.NetFolderRef = node
                return node
            end
        end
    end
    return nil
end

---@param name string  "EggPickup", "Plot.Upgrades" or a packages Net name without "RE/"
---@return Instance|nil
function GameLib.Remote(name)
    if GameLib.IsDenied(name) then return nil end
    local cached = GameLib.Cache[name]
    if cached and cached.Parent then return cached end

    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local gameFolder = remotes and remotes:FindFirstChild("Game")
    local reusable = remotes and remotes:FindFirstChild("Reusable")
    local found

    local folder, leaf = name:match("^(%w+)%.(.+)$")
    if folder then
        local parent = gameFolder and gameFolder:FindFirstChild(folder)
        found = parent and parent:FindFirstChild(leaf)
    else
        found = gameFolder and gameFolder:FindFirstChild(name)
        if not found and reusable and not GameLib.IsDenied("Reusable." .. name) then
            found = reusable:FindFirstChild(name)
        end
        if not found then
            local net = GameLib.NetFolder()
            found = net and net:FindFirstChild("RE/" .. name)
        end
    end

    GameLib.Cache[name] = found
    return found
end

---@return Instance|nil  a denied remote that is only ever listened to, never fired
function GameLib.Listen(name)
    if not GameLib.ListenOnly[name] then return GameLib.Remote(name) end
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local gameFolder = remotes and remotes:FindFirstChild("Game")
    return gameFolder and gameFolder:FindFirstChild(name)
end

xDTaraZ.Net = setmetatable({}, {
    __index = function(self, name)
        local remote = GameLib.Remote(name)
        if remote then rawset(self, name, remote) end
        return remote
    end,
})

---@return Instance|nil
function GameLib.ActiveEggs()
    local serverData = ReplicatedStorage:FindFirstChild("ServerData")
    return serverData and serverData:FindFirstChild("ActiveEggs")
end

---@return Model|nil
function GameLib.Plot()
    local general = GameLib.Svc.General
    if general and general.GetPlot then
        local ok, plot = GameLib.Call(general.GetPlot, general, LocalPlayer)
        if ok and typeof(plot) == "Instance" then return plot end
    end

    local plots = Workspace:FindFirstChild("Plots")
    if not plots then return nil end
    for _, plot in ipairs(plots:GetChildren()) do
        local data = plot:FindFirstChild("Data")
        local owner = data and data:FindFirstChild("Owner")
        if owner and owner.Value == LocalPlayer then return plot end
    end
    return nil
end

---@return boolean  same rule as the game's delivery check, Y ignored
function GameLib.Contains(bp, pos)
    local rel = bp.CFrame:PointToObjectSpace(pos)
    local slack = xDTaraZ.Config.ContainsSlack
    return math.abs(rel.X) <= bp.Size.X / 2 + slack and math.abs(rel.Z) <= bp.Size.Z / 2 + slack
end

function GameLib.CycleIndex()
    local cycle = GameLib.Svc.EggCycle
    if cycle then
        local ok, index = GameLib.Call(cycle.Index)
        if ok and type(index) == "number" then return index end
    end
    return math.floor((xDTaraZ.Util.ServerNow() - xDTaraZ.Config.CycleOffset) / xDTaraZ.Config.CycleLength)
end

---@return number  seconds until the next egg wave
function GameLib.CycleLeft()
    local cycle = GameLib.Svc.EggCycle
    if cycle then
        local ok, left = GameLib.Call(cycle.SecondsRemaining)
        if ok and type(left) == "number" then return left end
    end
    local length = xDTaraZ.Config.CycleLength
    return length - (xDTaraZ.Util.ServerNow() - xDTaraZ.Config.CycleOffset) % length
end

---@param mult number  hatch luck multiplier, event included
---@return table|nil   { {pet, chance} }
function GameLib.Odds(egg, mult)
    local hatchLuck, eggs = GameLib.Data.HatchLuck, GameLib.Data.Eggs
    local info = GameLib.EggInfo[egg]
    if not (hatchLuck and hatchLuck.GetOdds and eggs and eggs[egg] and info) then return nil end

    local ok, odds = GameLib.Call(hatchLuck.GetOdds, info.luck * (mult or 1), eggs[egg])
    if not ok or type(odds) ~= "table" then return nil end

    local out = {}
    for _, row in ipairs(odds) do
        if type(row) == "table" and row.PetName then
            out[#out + 1] = { row.PetName, tonumber(row.Chance) or 0 }
        end
    end
    return out
end

---@return number|nil  growth seconds an egg of this weight needs, nil when the game module is missing
function GameLib.GrowthSeconds(base, weight)
    local general = GameLib.Data.General
    if not (general and general.GrowthTimeFor) then return nil end

    local ok, total = GameLib.Call(general.GrowthTimeFor, base, weight)
    return ok and tonumber(total) or nil
end

---@return number|nil  growth seconds still needed, nil when the game modules are missing
function GameLib.GrowthLeft(placeTime, base, weight)
    local dayNight = GameLib.Svc.DayNight
    local total = GameLib.GrowthSeconds(base, weight)
    if not (total and dayNight and dayNight.GrowthElapsed) then return nil end

    local ok, elapsed = GameLib.Call(dayNight.GrowthElapsed, placeTime)
    if not ok then return nil end
    return total - (tonumber(elapsed) or 0)
end

---@return number|nil  real seconds until a placed egg is grown, night counts faster; nil when unknown
function GameLib.GrowthRealLeft(placeTime, base, weight)
    local dayNight = GameLib.Svc.DayNight
    local total = GameLib.GrowthSeconds(base, weight)
    if not (total and dayNight and dayNight.GrowthRealRemaining) then return nil end

    local ok, left = GameLib.Call(dayNight.GrowthRealRemaining, placeTime, total)
    return ok and tonumber(left) or nil
end

---@param into   table   GameLib.Data or GameLib.Svc
---@param stopAt number  shared deadline for every require
function GameLib.LoadFolder(folder, names, into, label, stopAt)
    for _, name in ipairs(names) do
        local module = folder and folder:FindFirstChild(name)
        if module and os.clock() < stopAt then into[name] = GameLib.Require(module) end
        if not into[name] then GameLib.Missing[label .. "." .. name] = module and "load timeout" or "module not found" end
    end
end

function GameLib.LoadModules()
    local deadline = xDTaraZ.Config.GameLibDeadline
    local dataFolder = ReplicatedStorage:WaitForChild("GameData", deadline)
    local svcFolder = ReplicatedStorage:FindFirstChild("GameServices") or ReplicatedStorage:WaitForChild("GameServices", 1)
    local stopAt = os.clock() + deadline

    GameLib.LoadFolder(dataFolder, GameLib.DataModules, GameLib.Data, "GameData", stopAt)
    GameLib.LoadFolder(svcFolder, GameLib.ServiceModules, GameLib.Svc, "GameServices", stopAt)
end

local function BuildRarities()
    local order, rank = GameLib.RarityOrder, GameLib.RarityRank
    table.clear(order)
    table.clear(rank)

    local general = GameLib.Data.General or {}
    local levels = general.RarityLevelRequirementMultiplier or {}
    local weight = {}
    for rarity, level in pairs(levels) do
        weight[rarity] = tonumber(level) or 0
    end

    local floor = {}
    for _, pet in pairs(GameLib.PetInfo) do
        floor[pet.rarity] = math.min(floor[pet.rarity] or math.huge, pet.income)
    end
    for _, egg in pairs(GameLib.EggInfo) do
        floor[egg.rarity] = floor[egg.rarity] or math.huge
    end
    for rarity, income in pairs(floor) do
        if not weight[rarity] then weight[rarity] = 1e9 + math.min(income, 1e12) end
    end

    for rarity in pairs(weight) do
        order[#order + 1] = rarity
    end
    table.sort(order, function(a, b) return weight[a] < weight[b] end)
    for index, rarity in ipairs(order) do
        rank[rarity] = index
    end
end

local function BuildEggsAndPets()
    table.clear(GameLib.EggInfo)
    table.clear(GameLib.PetInfo)
    local breakTimer = (GameLib.Data.General or {}).EggBreakTimer or {}

    for name, egg in pairs(GameLib.Data.Eggs or {}) do
        if type(egg) ~= "table" then continue end
        local rarity = egg.Rarity or "Common"
        GameLib.EggInfo[name] = {
            rarity = rarity,
            luck = tonumber(egg.Luck) or 0,
            growth = tonumber(egg.GrowthTime) or 0,
            breakSec = tonumber(breakTimer[rarity]) or 0,
            ethereal = rarity == "Ethereal",
            volcanic = egg.RequiresVolcano == true,
        }
    end

    for name, pet in pairs(GameLib.Data.Pets or {}) do
        if type(pet) ~= "table" or not pet.Rarity then continue end
        GameLib.PetInfo[name] = {
            rarity = pet.Rarity,
            speed = tonumber(pet.Speed) or 0,
            income = tonumber(pet.Income) or 0,
            fusionOnly = pet.FusionOnly == true,
            moveSpeed = tonumber(pet.MovementSpeed) or 0,
        }
    end
end

local function BuildEconomy()
    local data = GameLib.Data

    table.clear(GameLib.Foods)
    table.clear(GameLib.FoodOrder)
    for name, food in pairs(data.Foods or {}) do
        if type(food) ~= "table" then continue end
        GameLib.Foods[name] = { cost = tonumber(food.Cost) or 0, xp = tonumber(food.XP) or 0, rarity = food.Rarity, noFeedAll = food.NoFeedAll == true }
        table.insert(GameLib.FoodOrder, name)
    end
    table.sort(GameLib.FoodOrder, function(a, b) return GameLib.Foods[a].cost < GameLib.Foods[b].cost end)

    table.clear(GameLib.ShopItems)
    local categories = data.Shop and data.Shop.Categories or {}
    for category, items in pairs(categories) do
        for item, entry in pairs(items) do
            if type(entry) ~= "table" or entry.Source == "Lanterns" then continue end
            local price = tonumber(entry.Price) or (GameLib.Foods[item] and GameLib.Foods[item].cost) or 0
            GameLib.ShopItems[#GameLib.ShopItems + 1] = { cat = category, item = item, price = price, rarity = entry.Rarity }
        end
    end
    table.sort(GameLib.ShopItems, function(a, b) return a.price < b.price end)

    local rebirths = data.Rebirths
    GameLib.Rebirths.Cap = rebirths and tonumber(rebirths.Cap) or 0
    table.clear(GameLib.Rebirths.Costs)
    for n = 1, GameLib.Rebirths.Cap do
        local ok, cost = GameLib.Call(rebirths.GetCost, n - 1)
        GameLib.Rebirths.Costs[n] = ok and tonumber(cost) or math.huge
    end

    table.clear(GameLib.RebirthReq)
    for index, pet in ipairs((data.General or {}).RebirthRequirements or {}) do
        GameLib.RebirthReq[index] = pet
    end

    table.clear(GameLib.IndexStages)
    for _, stage in ipairs(data.IndexRewards and data.IndexRewards.Stages or {}) do
        table.insert(GameLib.IndexStages, { goal = tonumber(stage.Goal) or 0, reward = tonumber(stage.Reward) or 0 })
    end

    table.clear(GameLib.Mutations)
    for name, mutation in pairs(data.Mutations or {}) do
        if type(mutation) == "table" and mutation.StatMultiplier then
            GameLib.Mutations[name] = 1 + (tonumber(mutation.StatMultiplier) or 0) / 100
        end
    end
end

function GameLib.Build()
    BuildEggsAndPets()
    BuildRarities()
    BuildEconomy()
end

---@return string|nil  why the option cannot run
function GameLib.Blocked(idx)
    for _, name in ipairs(GameLib.Needs[idx] or {}) do
        local reason = GameLib.Missing[name]
        if reason then return reason end
    end
    return nil
end

function GameLib.Check()
    local started = os.clock()
    local deadline = xDTaraZ.Config.GameLibDeadline
    local seen = {}

    for _, names in pairs(GameLib.Needs) do
        for _, name in ipairs(names) do
            if seen[name] then continue end
            seen[name] = true
            if os.clock() - started > deadline then
                GameLib.Missing[name] = "check timed out"
                continue
            end

            local found
            if name == "ActiveEggs" then
                found = GameLib.ActiveEggs()
            else
                found = GameLib.Remote(name)
            end
            if not found then GameLib.Missing[name] = "not found after a game update" end
        end
    end

    if not GameLib.Data.Eggs or not GameLib.Data.Pets then
        GameLib.Missing.ActiveEggs = GameLib.Missing.ActiveEggs or "egg data not readable"
    end
end

xDTaraZ.Player = {
    Client = LocalPlayer,
    Char = nil, Humanoid = nil, Root = nil,
    Epoch = 0,
    CharConns = {},
    PlotModel = nil, Baseplate = nil, PlotConn = nil, PlotRetryAt = 0,
}

function xDTaraZ.Player:Lose(char)
    if self.LostChar == char then return end
    self.LostChar = char
    self.Epoch += 1
    xDTaraZ.Util.Try("abort on death", function() xDTaraZ.Tasks.Abort("death") end)
    xDTaraZ.Util.Try("forget mount", function() xDTaraZ.Mount.Forget() end)
end

function xDTaraZ.Player:Unbind()
    for _, conn in ipairs(self.CharConns) do
        conn:Disconnect()
    end
    table.clear(self.CharConns)
    if self.PlotConn then
        self.PlotConn:Disconnect()
        self.PlotConn = nil
    end
end

function xDTaraZ.Player:Bind(char)
    for _, conn in ipairs(self.CharConns) do
        conn:Disconnect()
    end
    table.clear(self.CharConns)
    self.Char, self.Humanoid, self.Root = char, nil, nil

    task.spawn(function()
        local hum = char:WaitForChild("Humanoid", Config.LoadTimeout)
        local hrp = char:WaitForChild("HumanoidRootPart", Config.LoadTimeout)
        if self.Char ~= char then return end
        if not hum or not hrp then
            warn(Config.Tag, "character parts missing after", Config.LoadTimeout, "s")
            return
        end

        self.Humanoid, self.Root = hum, hrp
        table.insert(self.CharConns, hum.Died:Connect(function() self:Lose(char) end))
    end)
end

function xDTaraZ.Player:IsAlive()
    local hum, hrp = self.Humanoid, self.Root
    return hum ~= nil and hum.Health > 0 and hrp ~= nil and hrp.Parent ~= nil
end

---@return Model|nil, BasePart|nil  plot and its baseplate
function xDTaraZ.Player:Plot()
    local plot, bp = self.PlotModel, self.Baseplate
    if plot and bp and plot.Parent and bp.Parent then return plot, bp end

    local now = os.clock()
    if now < self.PlotRetryAt then return nil, nil end
    self.PlotRetryAt = now + Config.PlotRetry

    plot = xDTaraZ.GameLib.Plot()
    bp = plot and plot:FindFirstChild("Baseplate")
    if not bp then return nil, nil end
    self.PlotModel, self.Baseplate = plot, bp

    if self.PlotConn then self.PlotConn:Disconnect() end
    local owner = plot:FindFirstChild("Data") and plot.Data:FindFirstChild("Owner")
    if owner then
        self.PlotConn = owner.Changed:Connect(function()
            self.PlotModel, self.Baseplate, self.PlotRetryAt = nil, nil, 0
        end)
    end
    return plot, bp
end

---@return Instance[]
function xDTaraZ.Player:BasketItems()
    local basket = LocalPlayer:FindFirstChild("Basket")
    return basket and basket:GetChildren() or {}
end

function xDTaraZ.Player:BasketCount()
    local basket = LocalPlayer:FindFirstChild("Basket")
    return basket and #basket:GetChildren() or 0
end

function xDTaraZ.Player:Riding()
    return LocalPlayer:GetAttribute("IsRiding") == true
end

---@async
---@return boolean  off the mount with empty hands, yields until the landing tool is put away
function xDTaraZ.Player:Release()
    local hum = self.Humanoid
    local remote = self:Riding() and xDTaraZ.GameLib.Remote("PetDismount")
    if remote and hum and hum.Parent then
        local landed = false
        local conn = hum.Parent.ChildAdded:Connect(function(child)
            if child:IsA("Tool") then landed = true end
        end)
        remote:FireServer()

        local deadline = os.clock() + Config.DismountTimeout
        while self:Riding() and os.clock() < deadline do task.wait() end
        local toolBy = os.clock() + Config.DismountToolWindow
        while not landed and os.clock() < toolBy and hum.Parent do task.wait() end
        conn:Disconnect()
    end

    if self:BasketCount() > 0 or not hum then return not self:Riding() end
    hum:UnequipTools()
    return not self:Riding()
end

---@return number  server delivery-failure counter
function xDTaraZ.Player:Flags()
    return tonumber(LocalPlayer:GetAttribute("TeleportFlags")) or 0
end

xDTaraZ.Geo = {}

---@return Vector3  nearest point inside the baseplate edge, standing height
function xDTaraZ.Geo.EdgeInside(bp, target)
    local rel = bp.CFrame:PointToObjectSpace(target)
    local hx, hz = bp.Size.X / 2 - Config.EdgeInset, bp.Size.Z / 2 - Config.EdgeInset
    local clamped = Vector3.new(math.clamp(rel.X, -hx, hx), bp.Size.Y / 2 + Config.StandLift, math.clamp(rel.Z, -hz, hz))
    return bp.CFrame:PointToWorldSpace(clamped)
end

---@param dist number  studs past the edge
---@return Vector3     point outside the baseplate on the side facing target
function xDTaraZ.Geo.Outside(bp, target, dist)
    local rel = bp.CFrame:PointToObjectSpace(target)
    local hx, hz = bp.Size.X / 2, bp.Size.Z / 2
    local cx, cz = math.clamp(rel.X, -hx, hx), math.clamp(rel.Z, -hz, hz)
    local dx, dz = rel.X - cx, rel.Z - cz
    local len = math.sqrt(dx * dx + dz * dz)
    if len < 1e-3 then dx, dz, len = 1, 0, 1 end

    return bp.CFrame:PointToWorldSpace(Vector3.new(cx + dx / len * dist, bp.Size.Y / 2 + Config.StandLift, cz + dz / len * dist))
end

---@return Vector3  pickup spot on the egg-to-plot line, within reach of the egg
function xDTaraZ.Geo.StandPoint(bp, eggPos)
    local edge = xDTaraZ.Geo.EdgeInside(bp, eggPos)
    local dir = (edge - eggPos) * Vector3.new(1, 0, 1)
    local span = dir.Magnitude
    if span < 1e-3 then return Vector3.new(eggPos.X, eggPos.Y + Config.StandLift, eggPos.Z) end

    local spot = eggPos + dir.Unit * math.min(Config.PickupReach, span)
    return Vector3.new(spot.X, eggPos.Y + Config.StandLift, spot.Z)
end

---@return number  flat studs from a point to the plot edge
function xDTaraZ.Geo.Trip(bp, from)
    return xDTaraZ.Util.Flat(from, xDTaraZ.Geo.EdgeInside(bp, from))
end

function xDTaraZ.Geo.InPlot(pos)
    local _, bp = xDTaraZ.Player:Plot()
    return bp ~= nil and xDTaraZ.GameLib.Contains(bp, pos)
end

if LocalPlayer.Character then xDTaraZ.Player:Bind(LocalPlayer.Character) end
xDTaraZ:Connect(LocalPlayer.CharacterAdded, function(char) xDTaraZ.Player:Bind(char) end)
xDTaraZ:Connect(LocalPlayer.CharacterRemoving, function(char) xDTaraZ.Player:Lose(char) end)

xDTaraZ.Tasks = { Current = nil, Prio = { Recover = 100, Volcano = 80, Hunter = 70, Mount = 65, Eggs = 60, Plot = 40, Travel = 30, Manual = 20 } }

function xDTaraZ.Tasks.Carrying()
    return xDTaraZ.Player:BasketCount() > 0
end

function xDTaraZ.Tasks.EggsBusy()
    local eggs = xDTaraZ.Eggs
    if not eggs or not eggs.Waiting then return false end
    return not eggs.Waiting()
end

---@return table|nil  token { owner, prio, epoch, dead, preempt }
function xDTaraZ.Tasks.Request(owner, prio)
    if not xDTaraZ.State.Alive then return nil end

    if prio <= xDTaraZ.Tasks.Prio.Manual and xDTaraZ.Tasks.Carrying() then
        table.insert(xDTaraZ.State.PendingNotify, { "Nova Hub", "Finish the egg delivery first" })
        return nil
    end
    if prio <= xDTaraZ.Tasks.Prio.Plot and prio > xDTaraZ.Tasks.Prio.Manual and xDTaraZ.Tasks.EggsBusy() then return nil end

    local cur = xDTaraZ.Tasks.Current
    if cur and (cur.dead or cur.epoch ~= xDTaraZ.Player.Epoch) then
        cur.dead = true
        cur = nil
        xDTaraZ.Tasks.Current = nil
    end

    if cur then
        if prio > cur.prio then cur.preempt = true end
        return nil
    end

    local token = { owner = owner, prio = prio, epoch = xDTaraZ.Player.Epoch, dead = false, preempt = false }
    local hrp = xDTaraZ.Player.Root
    if prio <= xDTaraZ.Tasks.Prio.Plot and hrp then token.home = hrp.CFrame end
    xDTaraZ.Tasks.Current = token
    return token
end

function xDTaraZ.Tasks.Release(token)
    if not token or token.dead then return end
    token.dead = true
    if xDTaraZ.Tasks.Current == token then xDTaraZ.Tasks.Current = nil end

    local opts = xDTaraZ.Options
    local back = opts and opts.ReturnAfter
    if not token.home or not back or xDTaraZ.Tasks.Carrying() then return end
    local hrp = xDTaraZ.Player.Root
    if hrp and xDTaraZ.Player:IsAlive() and token.epoch == xDTaraZ.Player.Epoch then
        hrp.CFrame = token.home
        hrp.AssemblyLinearVelocity = Vector3.zero
    end
end

---@return boolean  false after preempt, death or unload
function xDTaraZ.Tasks.Holds(token)
    if not token or token.dead or not xDTaraZ.State.Alive then return false end
    if xDTaraZ.Tasks.Current ~= token or token.epoch ~= xDTaraZ.Player.Epoch then return false end
    if not token.preempt or token.critical then return true end
    local delivering = token.owner == "Eggs" or token.owner == "Hunter" or token.owner == "Recover" or token.owner == "Volcano"
    if delivering and ((xDTaraZ.Eggs and xDTaraZ.Eggs.CarryCritical) or xDTaraZ.Tasks.Carrying()) then return true end

    xDTaraZ.Tasks.Release(token)
    return false
end

---@param cond     function|nil  nil waits the full timeout
---@return boolean, string        "ok"|"timeout"|"preempted"|"death"|"unload"
function xDTaraZ.Tasks.Await(token, cond, timeout)
    local deadline = os.clock() + timeout
    repeat
        if not xDTaraZ.State.Alive then return false, "unload" end
        if not token or token.epoch ~= xDTaraZ.Player.Epoch then return false, "death" end
        if not xDTaraZ.Tasks.Holds(token) then return false, "preempted" end
        if cond and cond() then return true, "ok" end
        task.wait()
    until os.clock() >= deadline
    return false, "timeout"
end

---@return boolean  refuses dead tokens
function xDTaraZ.Tasks.Teleport(token, cf)
    if not token or token.dead or xDTaraZ.Tasks.Current ~= token then return false end
    if token.epoch ~= xDTaraZ.Player.Epoch or not xDTaraZ.Player:IsAlive() then return false end
    local hrp = xDTaraZ.Player.Root
    if not hrp then return false end

    hrp.CFrame = cf
    hrp.AssemblyLinearVelocity = Vector3.zero
    return true
end

function xDTaraZ.Tasks.Abort(why)
    local cur = xDTaraZ.Tasks.Current
    if not cur then return end
    cur.dead, cur.why = true, why
    xDTaraZ.Tasks.Current = nil
end

function xDTaraZ.Tasks.ReleaseAll(why)
    xDTaraZ.Tasks.Abort(why or "release")
end

function xDTaraZ.Tasks.Owner()
    local cur = xDTaraZ.Tasks.Current
    return cur and not cur.dead and cur.owner or nil
end

xDTaraZ.Scheduler = { Jobs = {}, Order = {}, Booted = false }

xDTaraZ.Scheduler.Defaults = {
    { "Eggs", "Eggs", "Step", { "AutoEggs" } },
    { "Hunter", "Hunter", "Step", { "EggHunter" } },
    { "Volcano", "Volcano", "Step", { "VolcanoDip", "VolcanoObby" } },
    { "Junk", "Junk", "Step", { "ClearJunk" } },
    { "Hatch", "Hatch", "Step", { "AutoHatch" } },
    { "Plant", "Hatch", "PlantStep", { "AutoPlaceEggs" } },
    { "Pets", "Pets", "Step", { "AutoEquipBest", "AutoCollectCash" } },
    { "Feed", "Pets", "FeedStep", { "AutoFeed" } },
    { "Sell", "Sell", "Step", { "AutoSell" } },
    { "Fusion", "Fusion", "Step", { "AutoFusion" } },
    { "Economy", "Economy", "Step", { "AutoUpgrade", "AutoRebirth", "SmartSpend" } },
    { "Shop", "Shop", "Step", { "AutoShop" } },
    { "Rewards", "Rewards", "Step", { "AutoClaim" } },
    { "Boosts", "Boosts", "Step", nil },
    { "Server", "Server", "Step", nil },
    { "Esp", "Esp", "Step", { "EggEsp" } },
    { "Webhook", "Webhook", "Step", nil },
    { "Settle", "Eggs", "SettleStep", nil },
    { "Kaitun", "Kaitun", "Step", { "Kaitun" } },
}

---@param enabledFn function|nil  nil = any of toggles is on, or always when toggles is nil too
---@param toggles string[]|nil    switched off when the job halts
function xDTaraZ.Scheduler.Add(name, interval, fn, enabledFn, toggles)
    local job = xDTaraZ.Scheduler.Jobs[name]
    if not job then
        job = { name = name, due = 0, busy = false }
        job.runner = function()
            local ok, err = pcall(job.fn)
            job.busy = false
            if ok then return end
            xDTaraZ.Scheduler.Fail(job, err)
        end
        xDTaraZ.Scheduler.Jobs[name] = job
        table.insert(xDTaraZ.Scheduler.Order, job)
    end
    job.interval, job.fn, job.enabledFn, job.toggles = interval, fn, enabledFn, toggles or {}
    return job
end

---@return boolean
function xDTaraZ.Scheduler.Enabled(job)
    if State.Halted[job.name] then return false end
    if job.enabledFn then return job.enabledFn() == true end
    if #job.toggles == 0 then return true end

    for _, idx in ipairs(job.toggles) do
        if xDTaraZ.Util.Opt(idx) == true then return true end
    end
    return false
end

function xDTaraZ.Scheduler.Fail(job, err)
    local now = os.clock()
    local log = State.Errors[job.name] or {}
    State.Errors[job.name] = log

    local kept = {}
    for _, at in ipairs(log) do
        if now - at <= Config.FailWindow then kept[#kept + 1] = at end
    end
    kept[#kept + 1] = now
    State.Errors[job.name] = kept

    if #kept == 1 then warn(Config.Tag, job.name .. " failing:", err) end
    if #kept < Config.FailLimit then return end

    if #job.toggles == 0 then
        State.Errors[job.name] = nil
        job.due = now + Config.JobBackoff
        warn(Config.Tag, job.name .. " backing off:", err)
        return
    end

    State.Halted[job.name] = true
    for _, idx in ipairs(job.toggles) do
        table.insert(State.PendingToggleOff, idx)
    end
    local line = tostring(err):match("^[^\n]*") or "unknown error"
    xDTaraZ.Util.Notify("Nova Hub", job.name .. " stopped: " .. line, 8)
end

function xDTaraZ.Scheduler.Run(job)
    job.busy = true
    task.spawn(job.runner)
end

function xDTaraZ.Scheduler.Tick()
    if not State.Alive then return end
    local now = os.clock()
    for _, job in ipairs(xDTaraZ.Scheduler.Order) do
        if job.busy or now < job.due then continue end
        job.due = now + job.interval
        if not xDTaraZ.Scheduler.Enabled(job) then continue end
        xDTaraZ.Scheduler.Run(job)
    end
end

---@param key string  job name or toggle idx
function xDTaraZ.Scheduler.Resume(key)
    for name, job in pairs(xDTaraZ.Scheduler.Jobs) do
        if name == key or table.find(job.toggles, key) then
            State.Halted[name] = nil
            State.Errors[name] = nil
            job.due = 0
        end
    end
end

function xDTaraZ.Scheduler.Pump()
    if not Library then return end
    if #State.PendingToggleOff == 0 and #State.PendingNotify == 0 then return end

    local offList = State.PendingToggleOff
    State.PendingToggleOff = {}
    for _, idx in ipairs(offList) do
        local option = Library.Options and Library.Options[idx]
        if option and option.Value then option:SetValue(false) end
        xDTaraZ.Options[idx] = false
    end

    local notes = State.PendingNotify
    State.PendingNotify = {}
    for _, note in ipairs(notes) do
        Library:Notify(note[1], note[2], note[3] or 5)
    end
end

function xDTaraZ.Scheduler.AddDefaults()
    local espTick = xDTaraZ.Platform.Mobile and Config.EspTickMobile or Config.EspTick
    for _, row in ipairs(xDTaraZ.Scheduler.Defaults) do
        local name, owner, method, toggles = row[1], row[2], row[3], row[4]
        local interval = Config.JobTick[name] or espTick
        if xDTaraZ.Scheduler.Jobs[name] then continue end

        local module = rawget(xDTaraZ, owner)
        local fn = module and module[method]
        if type(fn) ~= "function" then
            warn(Config.Tag, "no job function " .. owner .. "." .. method)
            continue
        end
        xDTaraZ.Scheduler.Add(name, interval, fn, nil, toggles)
    end
end

function xDTaraZ.Scheduler.Boot()
    if xDTaraZ.Scheduler.Booted then return end
    xDTaraZ.Scheduler.Booted = true

    xDTaraZ.Scheduler.AddDefaults()
    xDTaraZ:Connect(RunService.Heartbeat, xDTaraZ.Scheduler.Tick)
end

xDTaraZ.Signal = {}
xDTaraZ.Signal.__index = xDTaraZ.Signal

function xDTaraZ.Signal.new()
    return setmetatable({ handlers = {} }, xDTaraZ.Signal)
end

---@return function  call to disconnect
function xDTaraZ.Signal:Connect(fn)
    local handlers = self.handlers
    handlers[#handlers + 1] = fn
    return function()
        local at = table.find(handlers, fn)
        if at then table.remove(handlers, at) end
    end
end

function xDTaraZ.Signal:Fire(...)
    for _, fn in ipairs(table.clone(self.handlers)) do
        xDTaraZ.Util.Try("signal", fn, ...)
    end
end

xDTaraZ.EggIndex = {
    Entries = {}, Conns = {}, Waiters = {},
    Claimed = {}, LocalClaims = {}, Blacklist = {}, Failed = {}, FailCap = 2,
    Memo = {}, Mult = nil, Median = nil, ValueEpoch = 0,
    Cycle = nil, RolledAt = 0, Started = false,
    OnAdded = xDTaraZ.Signal.new(),
    OnRemoved = xDTaraZ.Signal.new(),
    OnReply = xDTaraZ.Signal.new(),
    OnRoll = xDTaraZ.Signal.new(),
}

---@return number  hatch luck multiplier: upgrades x live event
function xDTaraZ.EggIndex.LuckMult()
    local saved = LocalPlayer:FindFirstChild("SavedData")
    local upgrades = saved and saved:FindFirstChild("HatchUpgrades")
    local n = upgrades and tonumber(upgrades.Value) or 0
    local event = tonumber(ReplicatedStorage:GetAttribute("HatchLuckEventMultiplier")) or 1
    return (1 + n + 4 * math.floor(n / 5)) * event
end

---@return number  expected income of one hatch, luck-based fallback when odds are unreadable
function xDTaraZ.EggIndex.Expected(egg, mult)
    local key = egg .. "|" .. mult
    local memo = xDTaraZ.EggIndex.Memo
    if memo[key] then return memo[key] end

    local total = 0
    for _, pair in ipairs(GameLib.Odds(egg, mult) or {}) do
        local pet = GameLib.PetInfo[pair[1]]
        total += (tonumber(pair[2]) or 0) * (pet and pet.income or 0)
    end
    if total <= 0 then
        local info = GameLib.EggInfo[egg]
        total = (info and info.luck or 0) * mult
    end

    memo[key] = total
    return total
end

function xDTaraZ.EggIndex.Value(entry)
    if not entry.egg then return 0 end
    local index = xDTaraZ.EggIndex
    index.Mult = index.Mult or index.LuckMult()
    local factor = entry.mutation and GameLib.Mutations[entry.mutation] or 1
    return index.Expected(entry.egg, index.Mult) * (entry.weight or 1) * factor
end

function xDTaraZ.EggIndex.Revalue()
    local index = xDTaraZ.EggIndex
    table.clear(index.Memo)
    index.Mult = nil
    for _, entry in pairs(index.Entries) do
        entry.value = index.Value(entry)
    end
    index.Median = nil
    index.ValueEpoch += 1
end

---@param entry table?  refreshed in place when given
function xDTaraZ.EggIndex.Read(inst, entry)
    entry = entry or { guid = inst.Name, inst = inst }
    entry.egg = inst:GetAttribute("Egg")
    entry.pos = inst:GetAttribute("Position")
    entry.weight = tonumber(inst:GetAttribute("Weight")) or 1
    entry.mutation = inst:GetAttribute("Mutation")
    entry.cycle = tonumber(inst:GetAttribute("Cycle"))
    entry.privateTo = inst:GetAttribute("PrivateTo")
    entry.area = inst:GetAttribute("Area") == true
    entry.dropEndsAt = tonumber(inst:GetAttribute("DropEndsAt"))
    entry.origin = inst:GetAttribute("OriginPosition")
    entry.value = xDTaraZ.EggIndex.Value(entry)
    return entry
end

function xDTaraZ.EggIndex.Add(inst)
    local index = xDTaraZ.EggIndex
    if index.Entries[inst.Name] then return end
    local entry = index.Read(inst)
    index.Entries[inst.Name] = entry
    index.Median = nil

    index.Conns[inst.Name] = inst.AttributeChanged:Connect(function(attr)
        if attr ~= "Position" and attr ~= "DropEndsAt" and attr ~= "PrivateTo" then return end
        local wasDropped = entry.dropEndsAt ~= nil
        index.Read(inst, entry)
        if attr == "DropEndsAt" and not wasDropped and entry.dropEndsAt then index.OnAdded:Fire(entry) end
    end)

    index.OnAdded:Fire(entry)
end

function xDTaraZ.EggIndex.Remove(inst)
    local index = xDTaraZ.EggIndex
    local entry = index.Entries[inst.Name]
    if not entry then return end
    index.Entries[inst.Name] = nil
    entry.removed = true

    local conn = index.Conns[inst.Name]
    if conn then conn:Disconnect() end
    index.Conns[inst.Name] = nil
    index.Median = nil
    index.OnRemoved:Fire(entry)
end

---@param key string  egg guid, or "*carry" for Deposited/BasketFull
function xDTaraZ.EggIndex.Expect(key)
    local waiter = {}
    xDTaraZ.EggIndex.Waiters[key] = waiter
    return waiter
end

function xDTaraZ.EggIndex.Deliver(key, kind, text)
    local waiter = key and xDTaraZ.EggIndex.Waiters[key]
    if not waiter or waiter.kind then return end
    waiter.kind, waiter.text = kind, text
end

---@return string, string?  PickedUp|Refused|Gone|BasketFull|Deposited|Timeout, server text
function xDTaraZ.EggIndex.WaitReply(key, timeout)
    local index = xDTaraZ.EggIndex
    local waiter = index.Waiters[key] or index.Expect(key)
    local deadline = os.clock() + timeout
    while not waiter.kind and os.clock() < deadline and State.Alive do
        task.wait()
    end
    if index.Waiters[key] == waiter then index.Waiters[key] = nil end
    if not waiter.kind then return "Timeout" end
    return waiter.kind, waiter.text
end

function xDTaraZ.EggIndex.Route(kind, first, second)
    local index = xDTaraZ.EggIndex
    if kind == "PickedUp" then
        index.Deliver(second, "PickedUp", first)
        index.OnReply:Fire("PickedUp", second, first)
    elseif kind == "Refused" then
        local text = tostring(first)
        local verdict = text:find("already gone", 1, true) and "Gone" or "Refused"
        if verdict == "Gone" and second then index.Blacklist[second] = os.clock() + Config.GoneBlacklistSec end
        index.Deliver(second, verdict, text)
        index.OnReply:Fire(verdict, second, text)
    elseif kind == "Deposited" then
        index.Deliver("*carry", "Deposited", tostring(first))
        index.OnReply:Fire("Deposited", nil, first)
    elseif kind == "BasketFull" then
        for key in pairs(index.Waiters) do index.Deliver(key, "BasketFull") end
        index.OnReply:Fire("BasketFull")
    end
end

function xDTaraZ.EggIndex.OnMessage(text)
    if type(text) ~= "string" then return end
    if text:find("Egg Delivery Failed", 1, true) or text:find("Was Returned", 1, true) then
        xDTaraZ.Guard.Trip("message")
    end
end

function xDTaraZ.EggIndex.ReadClaims()
    local index = xDTaraZ.EggIndex
    local raw = LocalPlayer:GetAttribute("CollectedEggCycles")
    if type(raw) ~= "string" or raw == "" then return end

    local http = game:GetService("HttpService")
    local ok, decoded = pcall(http.JSONDecode, http, raw)
    if not ok or type(decoded) ~= "table" then
        index.ClaimsBroken = true
        return
    end

    table.clear(index.Claimed)
    for egg, cycle in pairs(decoded) do
        index.Claimed[egg] = tonumber(cycle)
    end
    index.ClaimsBroken = false
end

---@return number  last cycle this egg was claimed in, -1 if never
function xDTaraZ.EggIndex.ClaimedCycle(egg)
    local index = xDTaraZ.EggIndex
    return math.max(index.Claimed[egg] or -1, index.LocalClaims[egg] or -1)
end

function xDTaraZ.EggIndex.MarkClaimed(egg, cycle)
    if not egg or not cycle then return end
    local claims = xDTaraZ.EggIndex.LocalClaims
    claims[egg] = math.max(claims[egg] or -1, cycle)
end

function xDTaraZ.EggIndex.MarkGone(guid)
    if guid then xDTaraZ.EggIndex.Blacklist[guid] = os.clock() + Config.GoneBlacklistSec end
end

function xDTaraZ.EggIndex.Fail(guid)
    local failed = xDTaraZ.EggIndex.Failed
    failed[guid] = (failed[guid] or 0) + 1
end

---@return boolean  true on the tick the egg cycle rolled over
function xDTaraZ.EggIndex.CheckRoll()
    local index = xDTaraZ.EggIndex
    local cycle = GameLib.CycleIndex()
    if cycle == index.Cycle then return false end

    local rolled = index.Cycle ~= nil
    index.Cycle = cycle
    if not rolled then return false end

    table.clear(index.Blacklist)
    table.clear(index.Failed)
    index.RolledAt = os.clock()
    index.OnRoll:Fire(cycle)
    return true
end

---@return number  median value of the eggs on the map now
function xDTaraZ.EggIndex.MedianValue()
    local index = xDTaraZ.EggIndex
    if index.Median then return index.Median end

    local values = {}
    for _, entry in pairs(index.Entries) do
        local info = entry.egg and GameLib.EggInfo[entry.egg]
        if info and not info.volcanic then values[#values + 1] = entry.value or 0 end
    end
    table.sort(values)

    index.Median = values[math.max(1, math.ceil(#values / 2))] or 0
    return index.Median
end

---@return string?  reason the egg cannot be taken right now
function xDTaraZ.EggIndex.Blocked(entry, info)
    local index = xDTaraZ.EggIndex
    if entry.privateTo and entry.privateTo ~= LocalPlayer.UserId then return "private" end
    if info.volcanic then return "volcanic" end
    if entry.dropEndsAt and xDTaraZ.Util.ServerNow() < entry.dropEndsAt then return "falling" end
    if info.ethereal and entry.cycle and entry.cycle <= index.ClaimedCycle(entry.egg) then return "claimed" end
    if (index.Blacklist[entry.guid] or 0) > os.clock() then return "taken" end
    if (index.Failed[entry.guid] or 0) >= index.FailCap then return "failed" end
    return nil
end

---@return boolean  passes the user's egg filters
function xDTaraZ.EggIndex.Allowed(entry, info)
    local opts = xDTaraZ.Options
    local rarities, names = opts.EggRarities, opts.EggNames
    local floor = GameLib.RarityRank[opts.MinEggRarity or ""]
    if floor and (GameLib.RarityRank[info.rarity] or 0) < floor then return false end
    if type(rarities) == "table" and next(rarities) and not rarities[info.rarity] then return false end
    if type(names) == "table" and next(names) and not names[entry.egg] then return false end
    if (info.luck or 0) < (tonumber(opts.MinLuck) or 0) then return false end
    return entry.weight >= (tonumber(opts.MinWeight) or 0)
end

---@param ignoreFilters boolean?  hunter-only mode skips the user filters
---@return boolean, string?       wanted, reason when not
function xDTaraZ.EggIndex.Wanted(entry, ignoreFilters)
    if entry.removed or not entry.pos or not entry.egg then return false, "gone" end
    local info = GameLib.EggInfo[entry.egg]
    if not info then return false, "unknown" end

    local reason = xDTaraZ.EggIndex.Blocked(entry, info)
    if reason then return false, reason end
    if ignoreFilters then return true end

    if not xDTaraZ.EggIndex.Allowed(entry, info) then return false, "filtered" end
    if xDTaraZ.Options.SmartEggs and (entry.value or 0) < xDTaraZ.EggIndex.MedianValue() then return false, "low value" end
    return true
end

function xDTaraZ.EggIndex.WatchValues()
    local saved = LocalPlayer:FindFirstChild("SavedData")
    local upgrades = saved and saved:FindFirstChild("HatchUpgrades")
    if upgrades then xDTaraZ:Connect(upgrades.Changed, xDTaraZ.EggIndex.Revalue) end
    xDTaraZ:Connect(ReplicatedStorage:GetAttributeChangedSignal("HatchLuckEventMultiplier"), xDTaraZ.EggIndex.Revalue)
    xDTaraZ:Connect(LocalPlayer:GetAttributeChangedSignal("CollectedEggCycles"), xDTaraZ.EggIndex.ReadClaims)
end

---@return boolean  index is live
function xDTaraZ.EggIndex.Start()
    local index = xDTaraZ.EggIndex
    if index.Started then return true end
    local serverData = ReplicatedStorage:FindFirstChild("ServerData")
    local folder = serverData and serverData:FindFirstChild("ActiveEggs")
    if not folder then return false end
    index.Started = true

    xDTaraZ:Connect(folder.ChildAdded, xDTaraZ.EggIndex.Add)
    xDTaraZ:Connect(folder.ChildRemoved, xDTaraZ.EggIndex.Remove)
    for _, inst in ipairs(folder:GetChildren()) do
        index.Add(inst)
    end

    local pickup = GameLib.Remote("EggPickup")
    if pickup then xDTaraZ:Connect(pickup.OnClientEvent, xDTaraZ.EggIndex.Route) end
    local message = GameLib.Remote("GameMessage")
    if message then xDTaraZ:Connect(message.OnClientEvent, xDTaraZ.EggIndex.OnMessage) end

    index.WatchValues()
    index.ReadClaims()
    index.Cycle = GameLib.CycleIndex()
    return true
end

function xDTaraZ.EggIndex.Stop()
    local index = xDTaraZ.EggIndex
    for guid, conn in pairs(index.Conns) do
        conn:Disconnect()
        index.Conns[guid] = nil
    end
    table.clear(index.Waiters)
end

xDTaraZ.Delivery = {}

---@return "Plot"|"Direct"|"Drop", number  mode, trip studs
function xDTaraZ.Delivery.Mode(entry)
    local _, bp = xDTaraZ.Player:Plot()
    if not bp or not entry or not entry.pos then return "Drop", math.huge end

    local inside = xDTaraZ.Geo.EdgeInside(bp, entry.pos)
    if xDTaraZ.Util.Flat(inside, entry.pos) <= xDTaraZ.Config.PickupReach then return "Plot", 0 end

    local trip = xDTaraZ.Geo.Trip(bp, xDTaraZ.Geo.StandPoint(bp, entry.pos))
    local opts = xDTaraZ.Options
    if opts and opts.DeliveryMode == "Safe" then return "Drop", trip end

    if xDTaraZ.Delivery.Fits(trip, entry.weight, entry.egg) then return "Direct", trip end
    return "Drop", trip
end

---@return number  carry speed left after the egg weight slowdown
function xDTaraZ.Delivery.WeightFactor(weight, eggName)
    local cfg = xDTaraZ.Config
    local over = math.max(0, (tonumber(weight) or 1) - 1)
    local per = eggName == "Cherub" and cfg.CherubWeightPenalty or cfg.WeightPenalty
    return 1 - math.min(cfg.WeightPenaltyMax, over * 10 * per)
end

---@param weight number|nil  carried egg weight, nil = light
---@return boolean           straight trip home passes with the pet ridden right now
function xDTaraZ.Delivery.Fits(trip, weight, eggName)
    local factor = xDTaraZ.Delivery.WeightFactor(weight, eggName)
    local speed = xDTaraZ.Mount.Speed()
    if speed > 0 then return trip <= xDTaraZ.State.Tune.DirectFactor * speed * factor end
    return trip <= xDTaraZ.Config.UnmountedDirect * factor
end

---@return boolean  true when the full time passed
function xDTaraZ.Delivery.Sleep(token, sec)
    if sec <= 0 then return true end
    local _, why = xDTaraZ.Tasks.Await(token, nil, sec)
    return why == "timeout"
end

---@return boolean, string
function xDTaraZ.Delivery.Pickup(token, guid, standPos)
    local cfg = xDTaraZ.Config
    local remote = xDTaraZ.GameLib.Remote("EggPickup")
    local hrp = xDTaraZ.Player.Root
    if not remote or not hrp then return false, "missing" end

    if (hrp.Position - standPos).Magnitude > 1 then
        if not xDTaraZ.Tasks.Teleport(token, CFrame.new(standPos)) then return false, "aborted" end
        if not xDTaraZ.Delivery.Sleep(token, cfg.TpSettle) then return false, "aborted" end
    end

    local deadline = os.clock() + cfg.PickupTotalTimeout
    repeat
        if token.dead or token.epoch ~= xDTaraZ.Player.Epoch then return false, "aborted" end
        remote:FireServer(guid)
        local kind, text = xDTaraZ.EggIndex.WaitReply(guid, cfg.PickupReplyTimeout)

        if kind == "PickedUp" then return true, "ok" end
        if xDTaraZ.Player:BasketCount() > 0 then return true, "ok" end
        if kind == "BasketFull" then return false, "full" end
        if kind == "Gone" then
            xDTaraZ.EggIndex.MarkGone(guid)
            return false, "gone"
        end
        if kind == "Refused" and not tostring(text or ""):find("studs") then return false, "refused" end
        if kind == "Refused" then task.wait(cfg.PickupRetryStep) end
    until os.clock() >= deadline
    return false, "timeout"
end

---@return boolean  only true on the server's Deposited reply
function xDTaraZ.Delivery.AwaitDeposit(token, timeout)
    local kind = xDTaraZ.EggIndex.WaitReply("*carry", timeout)
    return kind == "Deposited" and not xDTaraZ.Guard.Tripped
end

function xDTaraZ.Delivery.StepHome(token, bp)
    local hrp = xDTaraZ.Player.Root
    if not hrp then return false end
    return xDTaraZ.Tasks.Teleport(token, CFrame.new(xDTaraZ.Geo.EdgeInside(bp, hrp.Position)))
end

---@return table|nil  newest dropped entry for the carried egg
---@param before table  guids that existed before our drop
function xDTaraZ.Delivery.FindDrop(eggName, origin, since, before)
    local hrp = xDTaraZ.Player.Root
    local here = hrp and hrp.Position
    local byOrigin, nearest, nearestDist = nil, nil, math.huge

    for _, entry in pairs(xDTaraZ.EggIndex.Entries) do
        if not entry.dropEndsAt or entry.dropEndsAt < since then continue end
        if before[entry.guid or ""] then continue end
        if origin and entry.origin and xDTaraZ.Util.Flat(entry.origin, origin) < 1 then
            byOrigin = entry
            break
        end
        if entry.egg == eggName and here then
            local dist = xDTaraZ.Util.Flat(entry.pos, here)
            if dist < nearestDist then nearest, nearestDist = entry, dist end
        end
    end
    return byOrigin or nearest
end

---@return table|nil
function xDTaraZ.Delivery.Drop(token, eggName, origin)
    local cfg = xDTaraZ.Config
    local remote = xDTaraZ.GameLib.Remote("BasketDrop")
    if not remote then return nil end

    local before = {}
    for _, entry in pairs(xDTaraZ.EggIndex.Entries) do
        if entry.guid then before[entry.guid] = true end
    end
    local since = xDTaraZ.Util.ServerNow() - 0.5
    remote:FireServer()

    local drop
    xDTaraZ.Tasks.Await(token, function()
        drop = xDTaraZ.Delivery.FindDrop(eggName, origin, since, before)
        return drop ~= nil
    end, cfg.DropAppearTimeout)
    return drop
end

function xDTaraZ.Delivery.WaitLanded(token, drop)
    local landAt = drop.dropEndsAt + xDTaraZ.Config.DropEndsSlack
    local ok = xDTaraZ.Tasks.Await(token, function() return xDTaraZ.Util.ServerNow() >= landAt end, xDTaraZ.Config.DropAppearTimeout)
    return ok
end

function xDTaraZ.Delivery.RaiseSettle()
    local tune = xDTaraZ.State.Tune
    tune.DropSettle = math.min(tune.DropSettle + 0.05, xDTaraZ.Config.DropSettleMax)
    xDTaraZ.State.Stats.staleDrops += 1
end

function xDTaraZ.Delivery.LowerSettle()
    local tune = xDTaraZ.State.Tune
    local floor = math.max(xDTaraZ.Config.DropSettle, tonumber(xDTaraZ.Util.Opt("DropSettle")) or 0)
    tune.DropSettle = math.max(floor, tune.DropSettle - 0.01)
end

---@return "Deposited"|"Gone"|"Refused"|"Aborted"
function xDTaraZ.Delivery.DropCycle(token, bp, eggName, origin)
    local cfg = xDTaraZ.Config

    for _ = 0, 2 do
        local hrp = xDTaraZ.Player.Root
        if not hrp or os.clock() > token.budget then return "Aborted" end

        local out = xDTaraZ.Geo.Outside(bp, hrp.Position, cfg.DropOutside)
        if not xDTaraZ.Tasks.Teleport(token, CFrame.new(out)) then return "Aborted" end
        if not xDTaraZ.Delivery.Sleep(token, xDTaraZ.State.Tune.DropSettle) then return "Aborted" end

        local drop = xDTaraZ.Delivery.Drop(token, eggName, origin)
        if not drop then return xDTaraZ.Player:BasketCount() == 0 and "Gone" or "Aborted" end
        origin = drop.origin or origin

        local fresh = xDTaraZ.Util.Flat(drop.pos, out) <= cfg.StaleDropDistance
        local stand = fresh and out or drop.pos + Vector3.new(0, 3, 0)
        if fresh then xDTaraZ.Delivery.LowerSettle() end
        if not fresh then
            xDTaraZ.Delivery.RaiseSettle()
            if not xDTaraZ.Tasks.Teleport(token, CFrame.new(stand)) then return "Aborted" end
        end
        if not xDTaraZ.Delivery.WaitLanded(token, drop) then return "Aborted" end

        local got, why = xDTaraZ.Delivery.Pickup(token, drop.guid, stand)
        if not got then return why == "gone" and "Gone" or "Aborted" end

        if fresh or xDTaraZ.Delivery.Fits(xDTaraZ.Geo.Trip(bp, stand), drop.weight, eggName) then
            if not xDTaraZ.Delivery.StepHome(token, bp) then return "Aborted" end
            return xDTaraZ.Delivery.AwaitDeposit(token, cfg.DepositTimeout) and "Deposited" or "Aborted"
        end
    end
    return "Aborted"
end

---@return "Deposited"|"Aborted"
function xDTaraZ.Delivery.DirectHome(token, bp)
    local cfg = xDTaraZ.Config
    if not xDTaraZ.Delivery.StepHome(token, bp) then return "Aborted" end
    if xDTaraZ.Delivery.AwaitDeposit(token, cfg.DepositTimeout) then return "Deposited" end
    if xDTaraZ.Player:BasketCount() > 0 and xDTaraZ.Player:Flags() <= token.flags0 then
        if xDTaraZ.Delivery.AwaitDeposit(token, cfg.DepositTimeout) then return "Deposited" end
    end
    return "Aborted"
end

---@return "Deposited"|"Gone"|"Refused"|"Aborted", number  outcome, seconds
function xDTaraZ.Delivery.Run(token, entry)
    local _, bp = xDTaraZ.Player:Plot()
    if not bp or not entry then return "Aborted", 0 end

    local t0 = os.clock()
    token.flags0 = xDTaraZ.Player:Flags()
    token.budget = t0 + xDTaraZ.Config.RunBudget

    local mode, trip = xDTaraZ.Delivery.Mode(entry)
    xDTaraZ.Delivery.LastPlan = { mode = mode, trip = math.floor(trip), speed = xDTaraZ.Mount.Speed(), settle = xDTaraZ.State.Tune.DirectFactor }
    local stand = mode == "Plot" and xDTaraZ.Geo.EdgeInside(bp, entry.pos) or xDTaraZ.Geo.StandPoint(bp, entry.pos)

    local got, why = xDTaraZ.Delivery.Pickup(token, entry.guid, stand)
    if not got then
        if why == "full" then xDTaraZ.Delivery.Recover(token) end
        return why == "gone" and "Gone" or (why == "refused" and "Refused" or "Aborted"), os.clock() - t0
    end

    xDTaraZ.Eggs.CarryCritical = true
    local outcome
    if mode == "Plot" then
        outcome = xDTaraZ.Delivery.AwaitDeposit(token, xDTaraZ.Config.DepositTimeout) and "Deposited" or "Aborted"
    elseif mode == "Direct" then
        outcome = xDTaraZ.Delivery.DirectHome(token, bp)
    else
        outcome = xDTaraZ.Delivery.DropCycle(token, bp, entry.egg, entry.origin or entry.pos)
    end

    if outcome ~= "Deposited" and xDTaraZ.Player:BasketCount() > 0 then xDTaraZ.Delivery.Recover(token) end
    xDTaraZ.Eggs.CarryCritical = false
    xDTaraZ.Guard.Check(token.flags0)

    local seconds = os.clock() - t0
    local stats = xDTaraZ.State.Stats
    if outcome == "Deposited" then
        local key = string.lower(mode)
        stats[key] = (stats[key] or 0) + 1
    end
    stats.lastRun, stats.lastMode = seconds, mode
    return outcome, seconds
end

---@return string|nil, string|nil  egg name, "Delivering"|"Carry"|"Unknown"
function xDTaraZ.Delivery.Carried()
    local items = xDTaraZ.Player:BasketItems()
    local first = items[1]
    if not first then return nil, nil end
    if first:GetAttribute("Delivering") == true then return first:GetAttribute("Egg"), "Delivering" end
    if first:GetAttribute("BreakAt") then return first:GetAttribute("Egg"), "Carry" end
    return first:GetAttribute("Egg"), "Unknown"
end

---@return boolean  deposited after stepping out of the plot and back in
function xDTaraZ.Delivery.Reenter(token, bp, hrp)
    local cfg = xDTaraZ.Config
    local out = xDTaraZ.Geo.Outside(bp, hrp.Position, cfg.DropOutside)
    if not xDTaraZ.Tasks.Teleport(token, CFrame.new(out)) then return false end
    if not xDTaraZ.Delivery.Sleep(token, cfg.TpSettle) then return false end
    if not xDTaraZ.Delivery.StepHome(token, bp) then return false end
    return xDTaraZ.Delivery.AwaitDeposit(token, cfg.DepositTimeout)
end

---@return boolean  basket empty afterwards
function xDTaraZ.Delivery.Recover(token)
    local eggName, phase = xDTaraZ.Delivery.Carried()
    if not phase then return true end

    local cfg = xDTaraZ.Config
    token.flags0 = token.flags0 or xDTaraZ.Player:Flags()
    token.budget = math.max(token.budget or 0, os.clock() + cfg.RunBudget)

    if phase ~= "Carry" then
        xDTaraZ.Tasks.Await(token, function() return xDTaraZ.Player:BasketCount() == 0 end, cfg.DepositTimeout)
        return xDTaraZ.Player:BasketCount() == 0
    end

    local _, bp = xDTaraZ.Player:Plot()
    local hrp = xDTaraZ.Player.Root
    if not bp or not hrp then return false end

    local wasCritical = xDTaraZ.Eggs.CarryCritical
    xDTaraZ.Eggs.CarryCritical = true
    if not (xDTaraZ.Geo.InPlot(hrp.Position) and xDTaraZ.Delivery.Reenter(token, bp, hrp)) then
        xDTaraZ.Delivery.DropCycle(token, bp, eggName, nil)
    end
    xDTaraZ.Eggs.CarryCritical = wasCritical
    return xDTaraZ.Player:BasketCount() == 0
end

xDTaraZ.Mount = { Name = nil, Dirty = true, AutoLabel = "Auto (fastest)" }

function xDTaraZ.Mount.PetName(inst)
    local name = inst:GetAttribute("PetName") or inst.Name
    if xDTaraZ.GameLib.PetInfo[name] then return name end
    return nil
end

function xDTaraZ.Mount.Moving(name)
    local pets = xDTaraZ.GameLib.Data and xDTaraZ.GameLib.Data.Pets
    local row = pets and pets[name]
    return type(row) == "table" and tonumber(row.MovementSpeed) or 0
end

---@return table  pet name -> Tool, Backpack and hand
function xDTaraZ.Mount.Tools()
    return xDTaraZ.Pets.ToolsByName()
end

---@return string|nil  ridden pet name from the mount joint
function xDTaraZ.Mount.Detect()
    local hrp = xDTaraZ.Player.Root
    local joint = hrp and hrp:FindFirstChild("PetMountJoint")
    local part = joint and joint.Part1
    local model = part and part:FindFirstAncestorOfClass("Model")
    if not model then return nil end
    return xDTaraZ.Mount.PetName(model)
end

function xDTaraZ.Mount.Choice()
    local opts = xDTaraZ.Options
    local pick = opts and opts.RidePet
    if type(pick) ~= "string" or pick == "" or pick == xDTaraZ.Mount.AutoLabel then return nil end
    return pick
end

---@return string|nil, number  name, ride speed
function xDTaraZ.Mount.Best()
    local info = xDTaraZ.GameLib.PetInfo
    local forced = xDTaraZ.Mount.Choice()
    if forced then return forced, info[forced] and info[forced].speed or 0 end

    local names = {}
    for name in pairs(xDTaraZ.Mount.Tools()) do names[#names + 1] = name end
    if xDTaraZ.Player:Riding() and xDTaraZ.Mount.Name then table.insert(names, xDTaraZ.Mount.Name) end

    local best, bestSpeed, bestMove = nil, 0, 0
    for _, name in ipairs(names) do
        local speed = info[name] and info[name].speed or 0
        local move = xDTaraZ.Mount.Moving(name)
        if speed > bestSpeed or (speed == bestSpeed and speed > 0 and move > bestMove) then
            best, bestSpeed, bestMove = name, speed, move
        end
    end
    return best, bestSpeed
end

function xDTaraZ.Mount.Speed()
    if not xDTaraZ.Player:Riding() then return 0 end
    local name = xDTaraZ.Mount.Name or xDTaraZ.Mount.Detect()
    if not name then return 0 end
    xDTaraZ.Mount.Name = name
    local info = xDTaraZ.GameLib.PetInfo[name]
    return info and info.speed or 0
end

function xDTaraZ.Mount.Forget()
    xDTaraZ.Mount.Name = nil
    xDTaraZ.Mount.Dirty = true
end

---@return Tool|nil  tool of a pet placed on the plot, only when the user named it
function xDTaraZ.Mount.Unplace(token, name)
    local remote = xDTaraZ.GameLib.Remote("PickupPet")
    if not remote then return nil end
    for _, pet in ipairs(xDTaraZ.Pets.Owned()) do
        if pet.name == name and pet.placed then
            remote:FireServer(pet.key)
            break
        end
    end

    local tool
    xDTaraZ.Tasks.Await(token, function()
        tool = xDTaraZ.Pets.ToolNamed(name)
        return tool ~= nil
    end, xDTaraZ.Config.MountTimeout)
    return tool
end

function xDTaraZ.Mount.Dismount(token)
    local remote = xDTaraZ.GameLib.Remote("PetDismount")
    if not remote then return false end
    remote:FireServer()
    xDTaraZ.Mount.Name = nil
    return (xDTaraZ.Tasks.Await(token, function() return not xDTaraZ.Player:Riding() end, xDTaraZ.Config.MountTimeout))
end

---@return boolean  riding the chosen pet
function xDTaraZ.Mount.Ensure(token)
    local cfg = xDTaraZ.Config
    if xDTaraZ.Player:BasketCount() > 0 or not xDTaraZ.Player:IsAlive() then return false end

    local name = xDTaraZ.Mount.Best()
    if not name then return false end
    if xDTaraZ.Player:Riding() then
        if (xDTaraZ.Mount.Name or xDTaraZ.Mount.Detect()) == name then
            xDTaraZ.Mount.Name, xDTaraZ.Mount.Dirty = name, false
            return true
        end
        if not xDTaraZ.Mount.Dismount(token) then return false end
    end

    local tool = xDTaraZ.Pets.ToolNamed(name)
    if not tool and xDTaraZ.Mount.Choice() == name then tool = xDTaraZ.Mount.Unplace(token, name) end
    local remote = xDTaraZ.GameLib.Remote("Mounting")
    local hum = xDTaraZ.Player.Humanoid
    if not tool or not remote or not hum then return false end

    hum:EquipTool(tool)
    for _ = 1, cfg.MountTries do
        remote:FireServer()
        local ok, why = xDTaraZ.Tasks.Await(token, function() return xDTaraZ.Player:Riding() end, cfg.MountGap)
        if ok then break end
        if why ~= "timeout" then return false end
    end
    xDTaraZ.Tasks.Await(token, function() return xDTaraZ.Player:Riding() end, cfg.MountTimeout)

    if not xDTaraZ.Player:Riding() then return false end
    xDTaraZ.Mount.Name, xDTaraZ.Mount.Dirty = name, false
    return true
end

function xDTaraZ.Mount.Watch(backpack)
    if not backpack then return end
    xDTaraZ:Connect(backpack.ChildAdded, function(child)
        if child:IsA("Tool") and xDTaraZ.Mount.PetName(child) then xDTaraZ.Mount.Dirty = true end
    end)
end

task.spawn(function()
    xDTaraZ.Mount.Watch(LocalPlayer:WaitForChild("Backpack", xDTaraZ.Config.LoadTimeout))
end)
xDTaraZ:Connect(LocalPlayer.CharacterAdded, function()
    task.defer(function()
        xDTaraZ.Mount.Watch(LocalPlayer:WaitForChild("Backpack", xDTaraZ.Config.LoadTimeout))
    end)
end)

xDTaraZ.Planner = {
    Ranked = {}, Contested = {},
    Dirty = true, BuiltAt = 0, Epoch = -1, MountName = nil,
    RebuildGap = 0.5, MaxAge = 2, ContestStep = 0.25,
    Started = false,
}

---@return number  studs per second this player can close on an egg
function xDTaraZ.Planner.PlayerSpeed(player, char)
    if player:GetAttribute("IsRiding") ~= true then return Config.UnmountedPlayerSpeed end
    for _, child in ipairs(char:GetChildren()) do
        local pet = GameLib.PetInfo[child.Name]
        if pet and pet.speed then return pet.speed end
    end
    return Config.UnmountedPlayerSpeed
end

---@return table  { {pos, speed} } of every other player with a body
function xDTaraZ.Planner.Riders()
    local riders = {}
    for _, player in ipairs(Players:GetPlayers()) do
        if player == LocalPlayer then continue end
        local char = player.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then continue end
        riders[#riders + 1] = { hrp.Position, xDTaraZ.Planner.PlayerSpeed(player, char) }
    end
    return riders
end

---@param riders table?  from Planner.Riders, built when nil
---@return number        0..1, 1 = someone is on it now
function xDTaraZ.Planner.Contest(entry, riders)
    if not entry.pos then return 0 end
    local best = 0
    for _, rider in ipairs(riders or xDTaraZ.Planner.Riders()) do
        local eta = xDTaraZ.Util.Flat(rider[1], entry.pos) / math.max(rider[2], 1)
        best = math.max(best, math.clamp(1 - eta / Config.ContestHorizon, 0, 1))
    end
    return best
end

---@return number, string, number  score, delivery mode, contest
function xDTaraZ.Planner.Score(entry, riders)
    local mode = xDTaraZ.Delivery.Mode(entry)
    local contest = xDTaraZ.Planner.Contest(entry, riders)
    local cost = Config.TripCost[mode] or Config.TripCost.Drop
    local score = (entry.value or 0) * (1 + contest * State.Tune.ContestWeight) / cost
    return score, mode, contest
end

function xDTaraZ.Planner.Rebuild()
    local planner = xDTaraZ.Planner
    local riders = planner.Riders()
    local ranked = planner.Ranked
    table.clear(ranked)

    for _, entry in pairs(xDTaraZ.EggIndex.Entries) do
        if not entry.pos or not entry.egg then continue end
        if entry.privateTo and entry.privateTo ~= LocalPlayer.UserId then continue end
        local score, mode, contest = planner.Score(entry, riders)
        table.insert(ranked, { entry, mode, contest, score })
    end
    table.sort(ranked, function(a, b) return a[4] > b[4] end)

    planner.Dirty, planner.BuiltAt = false, os.clock()
    planner.Epoch = xDTaraZ.EggIndex.ValueEpoch
    planner.MountName = xDTaraZ.Mount.Name
end

---@return boolean  ranking is stale
function xDTaraZ.Planner.Stale()
    local planner = xDTaraZ.Planner
    local age = os.clock() - planner.BuiltAt
    if planner.Epoch ~= xDTaraZ.EggIndex.ValueEpoch or planner.MountName ~= xDTaraZ.Mount.Name then return true end
    if age > planner.MaxAge then return true end
    if not planner.Dirty then return false end

    local surging = os.clock() - xDTaraZ.EggIndex.RolledAt <= Config.WaveSurge
    return surging or age >= planner.RebuildGap
end

---@param minRank number?  hunter-only: rarity rank floor, user filters skipped
---@return table?, string?  entry, planned mode
function xDTaraZ.Planner.Next(minRank)
    local planner = xDTaraZ.Planner
    if planner.Stale() then planner.Rebuild() end

    for _, pick in ipairs(planner.Ranked) do
        local entry = pick[1]
        if minRank then
            local info = GameLib.EggInfo[entry.egg]
            if not info or (GameLib.RarityRank[info.rarity] or 0) < minRank then continue end
        end
        if xDTaraZ.EggIndex.Wanted(entry, minRank ~= nil) then
            planner.Contested[entry.guid] = pick[3]
            return entry, pick[2]
        end
    end
    return nil
end

function xDTaraZ.Planner.OnReply(kind, guid)
    local planner = xDTaraZ.Planner
    if kind ~= "Gone" or not guid then return end
    local contest = planner.Contested[guid]
    planner.Contested[guid] = nil
    if not contest or contest <= 0 then return end

    local tune = State.Tune
    local before = tune.ContestWeight
    tune.ContestWeight = math.min(Config.ContestWeightMax, before + planner.ContestStep)
    if tune.ContestWeight == before then return end

    State.TuneLog = State.TuneLog or {}
    table.insert(State.TuneLog, { "ContestWeight", before, tune.ContestWeight, os.time() })
end

function xDTaraZ.Planner.MarkDirty()
    xDTaraZ.Planner.Dirty = true
end

function xDTaraZ.Planner.Start()
    local planner = xDTaraZ.Planner
    if planner.Started then return end
    planner.Started = true

    local index = xDTaraZ.EggIndex
    index.OnAdded:Connect(xDTaraZ.Planner.MarkDirty)
    index.OnRemoved:Connect(xDTaraZ.Planner.MarkDirty)
    index.OnRoll:Connect(function()
        table.clear(planner.Contested)
        planner.Dirty = true
    end)
    index.OnReply:Connect(xDTaraZ.Planner.OnReply)
end

xDTaraZ.Eggs = {
    Enabled = false, Manual = false, Phase = "Idle", Note = nil,
    Token = nil, CarryCritical = false,
    MountRetryAt = 0, RecoverAt = 0,
    Prio = { Eggs = 60, Hunter = 70, Recover = 100 },
    RateWindow = 60,
}

xDTaraZ.Hunter = { Enabled = false, Hops = 0, HopCycle = nil, HopAt = 0, Seen = {}, Started = false }

xDTaraZ.Guard = {
    Baseline = nil, Tripped = false, Watching = false,
    Toggles = { "AutoEggs", "EggHunter", "VolcanoDip", "VolcanoObby" },
}

---@return number  eggs delivered in the last minute
function xDTaraZ.Eggs.PerMinute()
    local window = State.Stats.window
    local cutoff = os.clock() - xDTaraZ.Eggs.RateWindow
    while window[1] and window[1] < cutoff do
        table.remove(window, 1)
    end
    return #window
end

function xDTaraZ.Eggs.Status()
    local eggs = xDTaraZ.Eggs
    if not eggs.Enabled and not eggs.Manual and not xDTaraZ.Hunter.Enabled then return "Egg farm is off" end
    return eggs.Note or eggs.Phase or "Idle"
end

---@return boolean  always false, so callers can return it
function xDTaraZ.Eggs.SetPhase(phase, note)
    local eggs = xDTaraZ.Eggs
    eggs.Phase, eggs.Note = phase, note
    State.Status.Eggs = eggs.Status()
    if not eggs.Enabled and not eggs.Manual and not xDTaraZ.Hunter.Enabled then
        State.Status.EggRate, State.Status.WaveAt = nil, nil
        return false
    end
    State.Status.EggRate = eggs.PerMinute() .. "/min"
    State.Status.WaveAt = os.clock() + GameLib.CycleLeft()
    return false
end

---@return boolean  Plot and Travel tasks may use the character now
function xDTaraZ.Eggs.Waiting()
    local eggs = xDTaraZ.Eggs
    local active = eggs.Enabled or eggs.Manual or xDTaraZ.Hunter.Enabled
    return not active or eggs.Phase == "WaveWait"
end

function xDTaraZ.Eggs.ReleaseToken()
    local eggs = xDTaraZ.Eggs
    if not eggs.Token then return end
    xDTaraZ.Tasks.Release(eggs.Token)
    eggs.Token = nil
end

---@return boolean  we hold a token at this priority
function xDTaraZ.Eggs.Claim(prio)
    local eggs = xDTaraZ.Eggs
    local token = eggs.Token
    if token and token.prio == prio and xDTaraZ.Tasks.Holds(token) then return true end

    eggs.ReleaseToken()
    local owner = prio >= eggs.Prio.Hunter and "Hunter" or "Eggs"
    eggs.Token = xDTaraZ.Tasks.Request(owner, prio)
    return eggs.Token ~= nil
end

function xDTaraZ.Eggs.EnsureMount()
    local eggs, mount = xDTaraZ.Eggs, xDTaraZ.Mount
    if os.clock() < eggs.MountRetryAt then return end
    if xDTaraZ.Player:Riding() and not mount.Dirty and mount.Best() == mount.Name then return end

    eggs.SetPhase("Mount", "Mounting")
    local ok, mounted = xDTaraZ.Util.Try("Mount.Ensure", mount.Ensure, eggs.Token)
    if ok and mounted then
        mount.Dirty = false
        return
    end
    eggs.MountRetryAt = os.clock() + Config.FailWindow
end

---@return boolean  basket is empty afterwards
function xDTaraZ.Eggs.Recover()
    local eggs = xDTaraZ.Eggs
    if eggs.CarryCritical or os.clock() < eggs.RecoverAt then return false end
    eggs.RecoverAt = os.clock() + Config.SlowTick
    eggs.ReleaseToken()

    local token = xDTaraZ.Tasks.Request("Recover", eggs.Prio.Recover)
    if not token then return eggs.SetPhase("Recover", "Waiting to finish the egg") end

    eggs.SetPhase("Recover", "Finishing the egg")
    xDTaraZ.Util.Try("Delivery.Recover", xDTaraZ.Delivery.Recover, token)
    xDTaraZ.Tasks.Release(token)
    return xDTaraZ.Player:BasketCount() == 0
end

function xDTaraZ.Eggs.Park()
    if not xDTaraZ.Options.ReturnAfter then return end
    local _, bp = xDTaraZ.Player:Plot()
    local hrp = xDTaraZ.Player.Root
    if not bp or not hrp or xDTaraZ.Geo.InPlot(hrp.Position) then return end

    local token = xDTaraZ.Tasks.Request("Eggs", xDTaraZ.Eggs.Prio.Eggs)
    if not token then return end
    xDTaraZ.Tasks.Teleport(token, CFrame.new(xDTaraZ.Geo.EdgeInside(bp, hrp.Position)))
    xDTaraZ.Tasks.Release(token)
end

function xDTaraZ.Eggs.WaveWait()
    local eggs = xDTaraZ.Eggs
    if eggs.Phase ~= "WaveWait" then
        eggs.ReleaseToken()
        eggs.Park()
    end
    local left = GameLib.CycleLeft()
    return eggs.SetPhase("WaveWait", left <= Config.WaveWakeEarly and "New wave" or nil)
end

function xDTaraZ.Eggs.Record(entry, outcome)
    local stats = State.Stats
    if outcome == "Gone" then
        stats.lost += 1
        return
    end
    if outcome == "Refused" then
        xDTaraZ.EggIndex.Fail(entry.guid)
        return
    end
    if outcome ~= "Deposited" then return end

    stats.delivered += 1
    table.insert(stats.window, os.clock())

    local info = GameLib.EggInfo[entry.egg]
    if info and info.ethereal then xDTaraZ.EggIndex.MarkClaimed(entry.egg, entry.cycle) end
end

---@return boolean  the egg reached the plot
function xDTaraZ.Eggs.Trip(entry)
    local eggs = xDTaraZ.Eggs
    eggs.SetPhase("Run", entry.egg)
    local ok, outcome = xDTaraZ.Util.Try("Delivery.Run", xDTaraZ.Delivery.Run, eggs.Token, entry)
    eggs.CarryCritical = false
    if not ok then outcome = "Aborted" end

    eggs.Record(entry, outcome)
    xDTaraZ.Planner.Dirty = true
    eggs.SetPhase("Settle")
    task.wait(Config.EggTick)
    return outcome == "Deposited"
end

---@param minRank number?  hunter-only: rarity floor, user filters skipped
---@return boolean          an egg was delivered
function xDTaraZ.Eggs.Tick(minRank)
    local eggs = xDTaraZ.Eggs
    if eggs.Ticking then return end
    eggs.Ticking = true
    local ok, err = pcall(eggs.TickOnce, minRank)
    eggs.Ticking = false
    if not ok then error(err, 0) end
end

function xDTaraZ.Eggs.TickOnce(minRank)
    local eggs = xDTaraZ.Eggs
    xDTaraZ.EggIndex.CheckRoll()

    local _, bp = xDTaraZ.Player:Plot()
    if not bp then return eggs.SetPhase("Idle", "Waiting for plot") end
    if not xDTaraZ.Player:IsAlive() then return eggs.SetPhase("Idle", "Waiting for respawn") end
    if xDTaraZ.Player:BasketCount() > 0 then return eggs.Recover() end
    if eggs.Token and not xDTaraZ.Tasks.Holds(eggs.Token) then eggs.ReleaseToken() end
    if xDTaraZ.Volcano.Pending() then
        eggs.ReleaseToken()
        return eggs.SetPhase("Pick", "Volcano dip")
    end

    local entry = xDTaraZ.Planner.Next(minRank)
    if not entry then return eggs.WaveWait() end
    if not eggs.Claim(xDTaraZ.Hunter.Priority(entry)) then return eggs.SetPhase("Pick", "Waiting for a turn") end

    eggs.EnsureMount()
    return eggs.Trip(entry)
end

function xDTaraZ.Eggs.Step()
    if not xDTaraZ.Eggs.Enabled or xDTaraZ.Guard.Tripped then return end
    xDTaraZ.Eggs.Tick(nil)
end

---@return boolean  index is live
function xDTaraZ.Eggs.Prepare()
    xDTaraZ.Guard.Arm()
    xDTaraZ.Planner.Start()
    return xDTaraZ.EggIndex.Start()
end

---@param quiet boolean  pause the game's inventory bar while farming; the game rebuilds it once when it comes back
---@param force boolean? restore even while a farming toggle is on
function xDTaraZ.Eggs.QuietInventory(quiet, force)
    local eggs = xDTaraZ.Eggs
    if quiet then
        if eggs.InventoryPaused then return end
        eggs.InventoryPaused = true
        eggs.InventoryWas = LocalPlayer:GetAttribute("SatchelEnabled")
        LocalPlayer:SetAttribute("SatchelEnabled", false)
        return
    end
    if not eggs.InventoryPaused then return end
    if not force and (eggs.Enabled or xDTaraZ.Hunter.Enabled or xDTaraZ.Util.Opt("ClearJunk")) then return end
    eggs.InventoryPaused = false
    LocalPlayer:SetAttribute("SatchelEnabled", eggs.InventoryWas)
end

function xDTaraZ.Eggs.Start()
    local eggs = xDTaraZ.Eggs
    eggs.QuietInventory(true)
    if State.LastFail then State.Tune.DirectFactor = math.min(State.Tune.DirectFactor, Config.DirectFactorAfterFail) end
    eggs.Prepare()
    eggs.Enabled, eggs.MountRetryAt = true, 0
    eggs.SetPhase("Idle")
end

function xDTaraZ.Eggs.Stop()
    local eggs = xDTaraZ.Eggs
    eggs.Enabled = false
    if xDTaraZ.Hunter.Enabled then return end
    if eggs.InFlight() then
        task.spawn(xDTaraZ.Eggs.FinishCarry, Config.RunBudget * 2)
        return
    end
    eggs.ReleaseToken()
    eggs.SetPhase("Idle")
    task.spawn(xDTaraZ.Eggs.Settle)
end

---@async
---@return boolean  dismounted and the inventory bar is back
function xDTaraZ.Eggs.Settle()
    local eggs = xDTaraZ.Eggs
    eggs.SettlePending = true
    if not eggs.LetGo() then return false end
    eggs.SettlePending = false
    eggs.QuietInventory(false)
    return true
end

function xDTaraZ.Eggs.SettleStep()
    local eggs = xDTaraZ.Eggs
    if not eggs.SettlePending then return end
    if eggs.Enabled or eggs.Manual or xDTaraZ.Hunter.Enabled or xDTaraZ.Util.Opt("ClearJunk") then
        eggs.SettlePending = false
        return
    end
    eggs.Settle()
end

---@return boolean  a trip is running or an egg is carried
function xDTaraZ.Eggs.InFlight()
    local eggs = xDTaraZ.Eggs
    return eggs.Phase == "Run" or eggs.CarryCritical or xDTaraZ.Player:BasketCount() > 0
end

---@param timeout number  seconds to wait for a running delivery
---@return boolean        basket is empty
function xDTaraZ.Eggs.FinishCarry(timeout)
    local eggs = xDTaraZ.Eggs
    local deadline = os.clock() + (timeout or Config.RunBudget)
    while (eggs.CarryCritical or eggs.Phase == "Run") and os.clock() < deadline do
        task.wait(Config.EggTick)
    end

    if xDTaraZ.Player:BasketCount() > 0 then
        eggs.RecoverAt = 0
        eggs.Recover()
    end
    eggs.ReleaseToken()
    if not eggs.Enabled and not xDTaraZ.Hunter.Enabled then eggs.Settle() end
    return xDTaraZ.Player:BasketCount() == 0
end

---@async
---@return boolean  off the mount with empty hands; false while a task or a carried egg still needs the mount
function xDTaraZ.Eggs.LetGo()
    if xDTaraZ.Tasks.Owner() or xDTaraZ.Player:BasketCount() > 0 then return false end
    return xDTaraZ.Player:Release()
end

function xDTaraZ.Eggs.ExitNow()
    local eggs = xDTaraZ.Eggs
    eggs.Enabled = false
    table.insert(State.PendingToggleOff, "AutoEggs")
    eggs.FinishCarry(Config.RunBudget)
    eggs.SetPhase("Idle", "Stopped")
end

---@async
---@return integer  eggs delivered in this pass, yields until the pass ends
function xDTaraZ.Eggs.CollectNow()
    local eggs = xDTaraZ.Eggs
    if eggs.Enabled or eggs.Manual or xDTaraZ.Hunter.Enabled then return 0 end
    if not eggs.Prepare() then return 0 end

    eggs.Manual = true
    local before = State.Stats.delivered
    local limit = 0
    for _ in pairs(xDTaraZ.EggIndex.Entries) do limit += 1 end

    for _ = 1, limit do
        if xDTaraZ.Guard.Tripped or not State.Alive then break end
        eggs.Tick(nil)
        if eggs.Phase == "WaveWait" or eggs.Phase == "Idle" or eggs.Phase == "Pick" then break end
    end

    eggs.ReleaseToken()
    eggs.Manual = false
    eggs.Settle()
    local got = State.Stats.delivered - before
    table.insert(State.PendingNotify, { "Collect Eggs", "Delivered " .. got .. " eggs" })
    return got
end

---@return number  rarity rank the hunter cares about, huge when unset
function xDTaraZ.Hunter.MinRank()
    return GameLib.RarityRank[xDTaraZ.Options.HuntMinRarity] or math.huge
end

---@return number  task priority for this egg
function xDTaraZ.Hunter.Priority(entry)
    local prio = xDTaraZ.Eggs.Prio
    if not xDTaraZ.Hunter.Enabled then return prio.Eggs end
    local info = GameLib.EggInfo[entry.egg]
    local rank = info and GameLib.RarityRank[info.rarity] or 0
    return rank >= xDTaraZ.Hunter.MinRank() and prio.Hunter or prio.Eggs
end

function xDTaraZ.Hunter.Spotted(entry)
    local hunter = xDTaraZ.Hunter
    if not hunter.Enabled or not entry.egg or hunter.Seen[entry.guid] then return end
    if entry.privateTo and entry.privateTo ~= LocalPlayer.UserId then return end
    local info = GameLib.EggInfo[entry.egg]
    if not info or info.volcanic then return end
    if (GameLib.RarityRank[info.rarity] or 0) < hunter.MinRank() then return end

    hunter.Seen[entry.guid] = true
    table.insert(State.PendingNotify, { "Rare Egg", entry.egg .. " (" .. tostring(info.rarity) .. ") spawned" })
    local webhook = xDTaraZ.Webhook
    if webhook and webhook.EggSpawned and entry.inst then task.defer(webhook.EggSpawned, entry.inst) end
end

function xDTaraZ.Hunter.TryHop()
    local hunter = xDTaraZ.Hunter
    if not xDTaraZ.Options.HunterHop or os.clock() < hunter.HopAt then return end
    if GameLib.CycleLeft() <= Config.HunterMinLeft or xDTaraZ.Player:BasketCount() > 0 then return end

    local cycle = GameLib.CycleIndex()
    if hunter.HopCycle ~= cycle then hunter.HopCycle, hunter.Hops = cycle, 0 end
    if hunter.Hops >= Config.HunterHopsPerCycle then return end
    if xDTaraZ.Planner.Next(hunter.MinRank()) then return end

    hunter.Hops += 1
    hunter.HopAt = os.clock() + Config.LoadTimeout
    xDTaraZ.Util.Try("Server.Hop", xDTaraZ.Server.Hop)
end

function xDTaraZ.Hunter.Step()
    local hunter, eggs = xDTaraZ.Hunter, xDTaraZ.Eggs
    if not hunter.Enabled or eggs.Manual or xDTaraZ.Guard.Tripped then return end
    if not eggs.Enabled then eggs.Tick(hunter.MinRank()) end
    if eggs.Phase == "WaveWait" then hunter.TryHop() end
end

function xDTaraZ.Hunter.Start()
    local hunter = xDTaraZ.Hunter
    if State.LastFail then State.Tune.DirectFactor = math.min(State.Tune.DirectFactor, Config.DirectFactorAfterFail) end
    xDTaraZ.Eggs.Prepare()
    xDTaraZ.Eggs.QuietInventory(true)
    hunter.Enabled = true
    if hunter.Started then return end

    hunter.Started = true
    xDTaraZ.EggIndex.OnAdded:Connect(xDTaraZ.Hunter.Spotted)
    xDTaraZ.EggIndex.OnRoll:Connect(function() table.clear(hunter.Seen) end)
end

function xDTaraZ.Hunter.Stop()
    xDTaraZ.Hunter.Enabled = false
    if xDTaraZ.Eggs.Enabled then return end
    if xDTaraZ.Eggs.InFlight() then
        task.spawn(xDTaraZ.Eggs.FinishCarry, Config.RunBudget * 2)
        return
    end
    xDTaraZ.Eggs.ReleaseToken()
    xDTaraZ.Eggs.SetPhase("Idle")
    task.spawn(xDTaraZ.Eggs.Settle)
end

function xDTaraZ.Guard.Arm()
    local guard = xDTaraZ.Guard
    guard.Tripped = false
    guard.Baseline = xDTaraZ.Player:Flags()
    if guard.Watching then return end
    guard.Watching = true
    xDTaraZ:Connect(LocalPlayer:GetAttributeChangedSignal("TeleportFlags"), xDTaraZ.Guard.OnFlags)
end

function xDTaraZ.Guard.OnFlags()
    local guard = xDTaraZ.Guard
    local flags = xDTaraZ.Player:Flags()
    if guard.Baseline and flags > guard.Baseline then guard.Trip("flags") end
    guard.Baseline = flags
end

function xDTaraZ.Guard.Check(flags0)
    if xDTaraZ.Player:Flags() > (flags0 or 0) then xDTaraZ.Guard.Trip("flags") end
end

---@return table  State.LastFail
function xDTaraZ.Guard.Snapshot(why)
    local plan = type(xDTaraZ.Delivery.LastPlan) == "table" and xDTaraZ.Delivery.LastPlan or {}
    return {
        why = why, at = os.time(),
        mode = plan.mode, trip = plan.trip, speed = plan.speed, settle = plan.settle, timings = plan.timings,
        flagsBefore = xDTaraZ.Guard.Baseline, flagsAfter = xDTaraZ.Player:Flags(),
    }
end

---@return boolean  true when the farm keeps going on a slower delivery pace
function xDTaraZ.Guard.Soften()
    local guard = xDTaraZ.Guard
    local now = os.clock()
    guard.Recent = guard.Recent or {}
    while guard.Recent[1] and now - guard.Recent[1] > Config.ReturnWindow do
        table.remove(guard.Recent, 1)
    end
    guard.Recent[#guard.Recent + 1] = now
    if #guard.Recent >= Config.ReturnStopCount then return false end

    local pace = Config.ReturnBackoff[#guard.Recent] or Config.ReturnBackoff[#Config.ReturnBackoff]
    State.Tune.DirectFactor = math.min(State.Tune.DirectFactor, pace)
    table.insert(State.PendingNotify, { "Egg Farm", "An egg was returned. Delivering slower and carrying on." })
    return true
end

function xDTaraZ.Guard.Trip(why)
    local guard = xDTaraZ.Guard
    if guard.Tripped or os.clock() - (guard.LastTrip or -math.huge) < Config.ReturnDedupe then return end
    guard.LastTrip = os.clock()
    State.Stats.returned += 1

    State.LastFail = guard.Snapshot(why)
    local webhook = xDTaraZ.Webhook
    if webhook and webhook.DeliveryFailed then task.defer(webhook.DeliveryFailed, State.LastFail) end
    if guard.Soften() then return end

    guard.Tripped = true
    xDTaraZ.Eggs.Enabled = false
    xDTaraZ.Hunter.Enabled = false
    local volcano = xDTaraZ.Volcano
    if volcano and volcano.Stop then xDTaraZ.Util.Try("Volcano.Stop", volcano.Stop) end
    for _, idx in ipairs(guard.Toggles) do
        table.insert(State.PendingToggleOff, idx)
    end
    table.insert(State.PendingNotify, { "Egg Farm", "Eggs keep getting returned. Egg farming stopped, switch Delivery to Safe and turn it back on." })
end

xDTaraZ.Volcano = {
    Token = nil,
    Reply = nil,
    Bound = false,
    Skip = {},
    ObbyAfter = 0,
    Dipped = 0,
    Magma = 0,
}

local function Never() return false end

function xDTaraZ.Volcano.Options()
    return xDTaraZ.Options or {}
end

function xDTaraZ.Volcano.SetStatus(text)
    xDTaraZ.State.Status.Volcano = text
end

---@return boolean  false when the token died while waiting
function xDTaraZ.Volcano.Sleep(token, sec)
    local _, why = xDTaraZ.Tasks.Await(token, Never, sec)
    return why == "timeout"
end

local function IsOurs(owner)
    return owner == LocalPlayer or owner == LocalPlayer.UserId
end

function xDTaraZ.Volcano.Bind()
    if xDTaraZ.Volcano.Bound then return end
    xDTaraZ.Volcano.Bound = true

    local result = xDTaraZ.GameLib.Remote("VolcanoDipResult")
    if result then
        xDTaraZ:Connect(result.OnClientEvent, function(reply)
            if type(reply) ~= "table" or not IsOurs(reply.Owner) then return end
            xDTaraZ.Volcano.Reply = reply
        end)
    end

    local cancelled = xDTaraZ.GameLib.Remote("VolcanoDipCancelled")
    if cancelled then
        xDTaraZ:Connect(cancelled.OnClientEvent, function(reply)
            if type(reply) == "table" and not IsOurs(reply.Owner) then return end
            xDTaraZ.Volcano.Reply = { Cancelled = true }
        end)
    end
end

---@return boolean  VolcanoTop is streamed in, not just the empty Volcano shell
function xDTaraZ.Volcano.Stream(token)
    if xDTaraZ.Volcano.Part("VolcanoTop") then return true end
    local ok, err = pcall(LocalPlayer.RequestStreamAroundAsync, LocalPlayer, xDTaraZ.Config.VolcanoCenter, xDTaraZ.Config.VolcanoStreamTimeout)
    if not ok then warn("[RideAPet] volcano stream:", err) end
    return xDTaraZ.Tasks.Await(token, function() return xDTaraZ.Volcano.Part("VolcanoTop") ~= nil end, xDTaraZ.Config.VolcanoStreamTimeout) == true
end

---@return BasePart?
function xDTaraZ.Volcano.Part(name)
    local volcano = workspace:FindFirstChild("Volcano")
    local part = volcano and volcano:FindFirstChild(name, true)
    if part and part:IsA("BasePart") then return part end

    for _, tagged in ipairs(game:GetService("CollectionService"):GetTagged(name)) do
        if tagged:IsA("BasePart") then return tagged end
    end
    return nil
end

---@return boolean  same footprint rule the game uses before it lets a dip fire
function xDTaraZ.Volcano.IsOver(top)
    local hrp = xDTaraZ.Player.Root
    local info = xDTaraZ.GameLib.Data.Volcano
    if not hrp or not top or not info then return false end

    local slack = tonumber(info.ServerRangeSlack) or 0
    local localPos = top.CFrame:PointToObjectSpace(hrp.Position)
    if localPos.Y < 0 then return false end
    return math.abs(localPos.X) <= top.Size.X / 2 + slack and math.abs(localPos.Z) <= top.Size.Z / 2 + slack
end

---@return boolean  ethereal, volcanic or already magma/eternal
local function SkipsDip(entry, info)
    if not info or info.ethereal or info.volcanic then return true end
    return entry.mutation == "Magma" or entry.mutation == "Eternal"
end

---@return boolean  egg run is idle or waiting, or the wave is down to its last free eggs
function xDTaraZ.Volcano.WaveTail()
    if xDTaraZ.Eggs.Waiting() then return true end
    local free = 0
    for _, entry in pairs(xDTaraZ.EggIndex.Entries) do
        if xDTaraZ.EggIndex.Wanted(entry) and xDTaraZ.Planner.Contest(entry) == 0 then free += 1 end
        if free > xDTaraZ.Config.VolcanoTailEggs then return false end
    end
    return true
end

---@return table?  index entry worth a dip, best score first
function xDTaraZ.Volcano.PickDip()
    local rarities = xDTaraZ.Volcano.Options().DipRarities or {}
    local info = xDTaraZ.GameLib.Data.Volcano
    local minBreak = (info and tonumber(info.BonusSeconds) or math.huge) + xDTaraZ.Config.VolcanoMinBreakLeft
    local best, bestScore = nil, -math.huge

    for guid, entry in pairs(xDTaraZ.EggIndex.Entries) do
        local egg = xDTaraZ.GameLib.EggInfo[entry.egg]
        if SkipsDip(entry, egg) or (xDTaraZ.Volcano.Skip[guid] or 0) > os.clock() then continue end
        if next(rarities) and not rarities[egg.rarity] then continue end
        if (egg.breakSec or 0) <= minBreak or not xDTaraZ.EggIndex.Wanted(entry) then continue end
        if xDTaraZ.Delivery.Mode(entry) == "Plot" then continue end

        local score = xDTaraZ.Planner.Score(entry)
        if score > bestScore then best, bestScore = entry, score end
    end
    return best
end

---@return Instance?  carried egg that can still be dipped
function xDTaraZ.Volcano.Carried()
    local now = xDTaraZ.Util.ServerNow()
    local minBreak = (tonumber(xDTaraZ.GameLib.Data.Volcano.BonusSeconds) or math.huge) + xDTaraZ.Config.VolcanoMinBreakLeft
    for _, egg in ipairs(xDTaraZ.Player:BasketItems()) do
        if egg:GetAttribute("VolcanoDipped") or egg:GetAttribute("Delivering") then continue end
        if (tonumber(egg:GetAttribute("VolcanoUntil")) or 0) > now then continue end
        local breakAt = tonumber(egg:GetAttribute("BreakAt"))
        if breakAt and breakAt - now > minBreak then return egg end
    end
    return nil
end

---@return table?  dip reply, re-fired while the server position still lags the teleport
function xDTaraZ.Volcano.FireUntilReply(token, remote)
    xDTaraZ.Volcano.Reply = nil
    local deadline = os.clock() + xDTaraZ.Config.VolcanoResultTimeout
    repeat
        remote:FireServer()
        if xDTaraZ.Tasks.Await(token, function() return xDTaraZ.Volcano.Reply ~= nil end, xDTaraZ.Config.VolcanoRefire) then
            return xDTaraZ.Volcano.Reply
        end
        if not xDTaraZ.Tasks.Holds(token) then return nil end
    until os.clock() >= deadline
    return nil
end

---@return boolean  the dip reply came back and the egg is home in the basket again
function xDTaraZ.Volcano.Dip(token)
    local remote = xDTaraZ.GameLib.Remote("VolcanoDip")
    local info = xDTaraZ.GameLib.Data.Volcano
    if not remote or not info or not xDTaraZ.Volcano.Carried() then return false end
    if not xDTaraZ.Volcano.Stream(token) then return false end

    local top = xDTaraZ.Volcano.Part("VolcanoTop")
    if not top then return false end
    local hover = CFrame.new(top.Position + Vector3.yAxis * (tonumber(info.HoverHeight) or 0))
    local over = false
    for _ = 1, xDTaraZ.Config.VolcanoTpTries do
        if not xDTaraZ.Tasks.Teleport(token, hover) then return false end
        if not xDTaraZ.Volcano.Sleep(token, xDTaraZ.Config.VolcanoDipSettle) then return false end
        over = xDTaraZ.Volcano.IsOver(top)
        if over then break end
    end
    if not over then return false end

    xDTaraZ.Volcano.SetStatus("Dipping egg")
    local reply = xDTaraZ.Volcano.FireUntilReply(token, remote)
    if not reply or reply.Cancelled then return false end

    local landAt = tonumber(reply.ArriveAt) or 0
    xDTaraZ.Tasks.Await(token, function() return xDTaraZ.Util.ServerNow() >= landAt end, xDTaraZ.Config.VolcanoResultTimeout)
    xDTaraZ.Volcano.Dipped += 1
    if reply.Success then xDTaraZ.Volcano.Magma += 1 end
    return true
end

---@return string  short outcome for the status line
function xDTaraZ.Volcano.DipRun(token, entry)
    local _, bp = xDTaraZ.Player:Plot()
    if not bp then return "no plot" end

    local ok, why = xDTaraZ.Delivery.Pickup(token, entry.guid, xDTaraZ.Geo.StandPoint(bp, entry.pos))
    if not ok then
        xDTaraZ.Volcano.Skip[entry.guid] = os.clock() + xDTaraZ.Config.GoneBlacklistSec
        return "pickup " .. tostring(why)
    end

    xDTaraZ.Eggs.CarryCritical = true
    local dipped = xDTaraZ.Volcano.Dip(token)
    xDTaraZ.Delivery.Recover(token)
    xDTaraZ.Eggs.CarryCritical = false
    return dipped and "dipped" or "dip skipped"
end

---@param canTouch boolean  executor touch works
function xDTaraZ.Volcano.Hold(token, part, canTouch)
    local hrp = xDTaraZ.Player.Root
    if not hrp or not part.Parent then return end
    hrp.AssemblyLinearVelocity = Vector3.zero
    if (hrp.Position - part.Position).Magnitude > part.Size.Magnitude / 2 then xDTaraZ.Tasks.Teleport(token, part.CFrame) end
    if not canTouch or os.clock() < (xDTaraZ.Volcano.TouchAt or 0) then return end
    xDTaraZ.Volcano.TouchAt = os.clock() + xDTaraZ.Config.VolcanoTouchEvery
    firetouchinterest(hrp, part, 0)
    task.defer(firetouchinterest, hrp, part, 1)
end

function xDTaraZ.Volcano.Climb(token)
    if xDTaraZ.Volcano.Done() then return true end
    if not xDTaraZ.Volcano.Stream(token) then return false end
    local canTouch = Library and Library.Compat and Library.Compat.Caps.Touch == true

    for _, step in ipairs({ { "VolcanoEntrance" }, { "VolcanoValidate", "InVolcano" }, { "VolcanoTop", "VolcanoValidated" } }) do
        local part = xDTaraZ.Volcano.Part(step[1])
        if not part or not xDTaraZ.Tasks.Teleport(token, part.CFrame) then return false end
        if not xDTaraZ.Volcano.Sleep(token, xDTaraZ.Config.VolcanoSettle) then return false end

        xDTaraZ.Volcano.Hold(token, part, canTouch)
        local attr = step[2]
        if attr and not xDTaraZ.Tasks.Await(token, function()
            if LocalPlayer:GetAttribute(attr) == true then return true end
            xDTaraZ.Volcano.Hold(token, part, canTouch)
            return false
        end, xDTaraZ.Config.VolcanoStepWait) then
            return false
        end
    end
    return xDTaraZ.Volcano.Done()
end

function xDTaraZ.Volcano.Done()
    return LocalPlayer:GetAttribute("VolcanoValidated") == true
end

---@return table?  Volcanic egg in the index we may pick up
function xDTaraZ.Volcano.VolcanicEgg()
    for guid, entry in pairs(xDTaraZ.EggIndex.Entries) do
        local info = xDTaraZ.GameLib.EggInfo[entry.egg]
        if not info or not info.volcanic then continue end
        if entry.privateTo and not IsOurs(entry.privateTo) then continue end
        if (xDTaraZ.Volcano.Skip[guid] or 0) > os.clock() then continue end
        return entry
    end
    return nil
end

---@return string
function xDTaraZ.Volcano.ObbyRun(token, entry)
    if not xDTaraZ.Volcano.Climb(token) then
        xDTaraZ.Volcano.ObbyAfter = os.clock() + xDTaraZ.Config.VolcanoRetry
        return "climb failed"
    end

    local stand = entry.pos + Vector3.yAxis * xDTaraZ.Config.VolcanoStandLift
    local ok, why = xDTaraZ.Delivery.Pickup(token, entry.guid, stand)
    if not ok then
        xDTaraZ.Volcano.Skip[entry.guid] = os.clock() + xDTaraZ.Config.GoneBlacklistSec
        return "pickup " .. tostring(why)
    end

    xDTaraZ.Eggs.CarryCritical = true
    xDTaraZ.Delivery.Recover(token)
    xDTaraZ.Eggs.CarryCritical = false
    return "volcanic egg run done"
end

---@return table?, function?  target and runner for this tick
function xDTaraZ.Volcano.Plan()
    local opts = xDTaraZ.Volcano.Options()
    if opts.VolcanoObby and os.clock() >= xDTaraZ.Volcano.ObbyAfter then
        local egg = xDTaraZ.Volcano.VolcanicEgg()
        if egg then return egg, xDTaraZ.Volcano.ObbyRun end
    end
    if opts.VolcanoDip and xDTaraZ.GameLib.Data.Volcano and xDTaraZ.Volcano.WaveTail() then
        local egg = xDTaraZ.Volcano.PickDip()
        if egg then return egg, xDTaraZ.Volcano.DipRun end
    end
    return nil
end

---@return boolean  the egg run must leave the character to the volcano for now
function xDTaraZ.Volcano.Pending()
    local hold = xDTaraZ.Volcano.Claimed
    if not hold then return false end
    if os.clock() < hold[2] and xDTaraZ.EggIndex.Entries[hold[1]] then return true end
    xDTaraZ.Volcano.Claimed = nil
    return false
end

---@return boolean  an egg nobody delivers is still in the basket
local function Orphaned()
    local eggs = xDTaraZ.Eggs
    if xDTaraZ.Player:BasketCount() == 0 or eggs.CarryCritical then return false end
    return not (eggs.Enabled or eggs.Manual or xDTaraZ.Hunter.Enabled)
end

function xDTaraZ.Volcano.Step()
    if not xDTaraZ.State.Alive or not xDTaraZ.Player:IsAlive() or xDTaraZ.Guard.Tripped then return end
    if Orphaned() then
        xDTaraZ.Volcano.SetStatus("Finishing the egg")
        xDTaraZ.Eggs.Recover()
        return
    end
    xDTaraZ.Volcano.Bind()

    local entry, runner = xDTaraZ.Volcano.Plan()
    if not entry then
        xDTaraZ.Volcano.Claimed = nil
        xDTaraZ.Volcano.SetStatus("Waiting")
        return
    end

    xDTaraZ.Volcano.Claimed = { entry.guid, os.clock() + xDTaraZ.Config.VolcanoClaimSec }
    if xDTaraZ.Player:BasketCount() > 0 then return end
    local token = xDTaraZ.Tasks.Request("Volcano", xDTaraZ.Tasks.Prio.Volcano)
    if not token then return end
    xDTaraZ.Volcano.Claimed = nil
    xDTaraZ.Volcano.Token = token

    local flags0 = xDTaraZ.Player:Flags()
    local ok, outcome = xDTaraZ.Util.Try("volcano", runner, token, entry)
    xDTaraZ.Guard.Check(flags0)

    xDTaraZ.Volcano.Token = nil
    xDTaraZ.Tasks.Release(token)
    xDTaraZ.Volcano.SetStatus(ok and outcome or "error")
end

function xDTaraZ.Volcano.Start()
    xDTaraZ.Eggs.Prepare()
    xDTaraZ.Volcano.Bind()
    xDTaraZ.Volcano.ObbyAfter = 0
end

function xDTaraZ.Volcano.Stop()
    xDTaraZ.Volcano.Claimed = nil
    local token = xDTaraZ.Volcano.Token
    if token and xDTaraZ.Player:BasketCount() == 0 then
        xDTaraZ.Volcano.Token = nil
        xDTaraZ.Tasks.Release(token)
    end
end

function xDTaraZ.Volcano.Status()
    return xDTaraZ.State.Status.Volcano or "Off"
end

xDTaraZ.Hatch = {
    Bound = false,
    Pending = {},
    LastPlaced = 0,
    LastRequest = 0,
    CapHit = false,
    Hatched = 0,
    Planted = 0,
    GrowCache = {},
    Signal = xDTaraZ.Signal.new(),
}

local function IsOurs(owner)
    return owner == nil or owner == LocalPlayer or owner == LocalPlayer.UserId
end

function xDTaraZ.Hatch.Options()
    return xDTaraZ.Options or {}
end

function xDTaraZ.Hatch.SetStatus(text)
    xDTaraZ.State.Status.Hatch = text
end

function xDTaraZ.Hatch.Store(placement)
    if type(placement) ~= "table" or type(placement.EggKey) ~= "string" then return end
    xDTaraZ.State.PlotEggs[placement.EggKey] = {
        key = placement.EggKey,
        egg = placement.EggName,
        placeTime = tonumber(placement.PlaceTime),
        weight = tonumber(placement.Weight) or 1,
        pos = typeof(placement.UpCFrame) == "CFrame" and placement.UpCFrame.Position or placement.Coordinate,
    }
    xDTaraZ.Hatch.LastPlaced = os.clock()
end

---@param msg table  EggPlaced reply, snapshot or one placement
function xDTaraZ.Hatch.OnPlaced(msg)
    if type(msg) ~= "table" or not IsOurs(msg.Owner) then return end
    if not msg.Snapshot then
        xDTaraZ.Hatch.Store(msg)
        return
    end

    table.clear(xDTaraZ.State.PlotEggs)
    for _, placement in pairs(type(msg.Placements) == "table" and msg.Placements or {}) do
        xDTaraZ.Hatch.Store(placement)
    end
end

function xDTaraZ.Hatch.OnHatched(msg)
    if type(msg) ~= "table" or not IsOurs(msg.Owner) or not msg.EggKey then return end
    xDTaraZ.State.PlotEggs[msg.EggKey] = nil
    xDTaraZ.Hatch.Pending[msg.EggKey] = nil
    xDTaraZ.Hatch.Hatched += 1
    xDTaraZ.Hatch.Signal:Fire(msg)
end

function xDTaraZ.Hatch.OnMessage(text)
    if type(text) ~= "string" then return end
    local used, cap = text:match("Max (%d+)/(%d+)")
    if not cap then return end
    xDTaraZ.State.PlantCap = math.max(tonumber(used), tonumber(cap))
    xDTaraZ.Hatch.CapHit = true
    xDTaraZ.Hatch.RequestSnapshot()
end

function xDTaraZ.Hatch.Bind()
    if xDTaraZ.Hatch.Bound then return end
    xDTaraZ.Hatch.Bound = true

    local placed = xDTaraZ.GameLib.Remote("EggPlaced")
    if placed then xDTaraZ:Connect(placed.OnClientEvent, xDTaraZ.Hatch.OnPlaced) end

    local hatch = xDTaraZ.GameLib.Remote("Hatch")
    if hatch then xDTaraZ:Connect(hatch.OnClientEvent, xDTaraZ.Hatch.OnHatched) end

    local message = xDTaraZ.GameLib.Remote("GameMessage")
    if message then xDTaraZ:Connect(message.OnClientEvent, xDTaraZ.Hatch.OnMessage) end

    xDTaraZ.Hatch.RequestSnapshot()
end

function xDTaraZ.Hatch.RequestSnapshot()
    local remote = xDTaraZ.GameLib.Remote("RequestPlotEggs")
    if not remote then return end
    xDTaraZ.Hatch.LastRequest = os.clock()
    remote:FireServer(true)
end

---@return boolean  a hatch luck event is running
function xDTaraZ.Hatch.BoostActive()
    local rs = game:GetService("ReplicatedStorage")
    local mult = tonumber(rs:GetAttribute("HatchLuckEventMultiplier")) or 1
    local untilAt = tonumber(rs:GetAttribute("HatchLuckEventUntil"))
    if untilAt and untilAt <= xDTaraZ.Util.ServerNow() then return false end
    return mult > 1
end

---@return number?  seconds of growth left, nil when unknown
function xDTaraZ.Hatch.Left(plotEgg)
    local info = xDTaraZ.GameLib.EggInfo[plotEgg.egg or ""]
    if not info or not plotEgg.placeTime then return nil end
    return xDTaraZ.GameLib.GrowthLeft(plotEgg.placeTime, info.growth, plotEgg.weight)
end

---@return number|nil  os.clock() moment the egg is grown, night growth included; nil when unknown
function xDTaraZ.Hatch.ReadyAt(plotEgg)
    if plotEgg.readyAt then return plotEgg.readyAt end
    local info = xDTaraZ.GameLib.EggInfo[plotEgg.egg or ""]
    if not info or not plotEgg.placeTime then return nil end

    local left = xDTaraZ.GameLib.GrowthRealLeft(plotEgg.placeTime, info.growth, plotEgg.weight)
    if not left then return nil end
    plotEgg.readyAt = os.clock() + left
    return plotEgg.readyAt
end

---@return integer  hatch fires sent this pass
function xDTaraZ.Hatch.HatchNow()
    local remote = xDTaraZ.GameLib.Remote("Hatch")
    if not remote then return 0 end
    xDTaraZ.Hatch.Bind()

    local fired, now = 0, os.clock()
    for key, plotEgg in pairs(xDTaraZ.State.PlotEggs) do
        if (xDTaraZ.Hatch.Pending[key] or 0) > now then continue end
        local left = xDTaraZ.Hatch.Left(plotEgg)
        if not left or left > 0 then continue end

        if fired > 0 then task.wait(xDTaraZ.Config.HatchGap) end
        xDTaraZ.Hatch.Pending[key] = os.clock() + xDTaraZ.Config.HatchPending
        remote:FireServer({ EggKey = key })
        fired += 1
    end
    return fired
end

function xDTaraZ.Hatch.Step()
    local opts = xDTaraZ.Hatch.Options()
    if not opts.AutoHatch then return end
    xDTaraZ.Hatch.Bind()

    if os.clock() - xDTaraZ.Hatch.LastRequest > xDTaraZ.Config.PlotEggsRefresh then
        xDTaraZ.Hatch.RequestSnapshot()
    end
    if opts.HoldHatchBoost and not xDTaraZ.Hatch.BoostActive() then
        xDTaraZ.Hatch.SetStatus("Holding for luck boost")
        return
    end

    local fired = xDTaraZ.Hatch.HatchNow()
    if fired > 0 then xDTaraZ.Hatch.SetStatus("Hatching " .. fired) end
end

---@return string?  egg name the tool plants
function xDTaraZ.Hatch.ToolEgg(tool)
    local name = tool:GetAttribute("Egg") or tool.Name:match("^(.-Egg)")
    return xDTaraZ.GameLib.EggInfo[name or ""] and name or nil
end

---@return { {Tool, string, number, string?} }  egg tools with name, weight and mutation
function xDTaraZ.Hatch.EggTools()
    local tools = {}
    for _, holder in ipairs({ LocalPlayer:FindFirstChild("Backpack"), xDTaraZ.Player.Char }) do
        if not holder then continue end
        for _, tool in ipairs(holder:GetChildren()) do
            if not tool:IsA("Tool") or not tool:GetAttribute("EggInventoryId") then continue end
            local name = xDTaraZ.Hatch.ToolEgg(tool)
            if not name then continue end
            table.insert(tools, { tool, name, tonumber(tool:GetAttribute("Weight")) or 1, tool:GetAttribute("Mutation") })
        end
    end
    return tools
end

---@return number  higher plants first
function xDTaraZ.Hat