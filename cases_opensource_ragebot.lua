local repS = cloneref(game:GetService("ReplicatedStorage"))
local plrs = cloneref(game:GetService("Players"))
local runS = cloneref(game:GetService("RunService"))
local ws = cloneref(game:GetService("Workspace"))
local lplr = plrs.LocalPlayer

local util = require(repS.Modules.Utility)
local enum = require(repS.Modules.EnumLibrary)
local FighterController = require(lplr.PlayerScripts.Controllers.FighterController)
local SpectateController = require(lplr.PlayerScripts.Controllers:WaitForChild("SpectateController"))

getgenv().Config = {
    Enabled = true,
    FireRate = 0.0005,
    WeaponSlot = "Primary", -- Initial weapon slot
    EmoteID = 83194012641579,
    StopOnMove = false,
    FadeIn = 0.1,
    FadeOut = 0.1,
    Weight = 1,
    Speed = 1,
    AllowInvisible = true,
    -- Random Teleport Settings & Bounds Protection:
    RandomTeleport = true,
    MinTeleportRadius = 3,
    MaxTeleportRadius = 8,
    HeightOffsetMin = -1,
    HeightOffsetMax = 3,
    BehindDistance = 5,
    DeathDropThreshold = -5.5,
    -- Rivals Arena Bounds Limits
    MinBoundsY = 0,
    MaxBoundsY = 200,
    MaxDistanceFromTarget = 25,
}

-- UI Setup (Status Button + Weapon Slot Dropdown)
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "ControlPanelGui"
screenGui.ResetOnSpawn = false
screenGui.Parent = game:GetService("CoreGui") or lplr:WaitForChild("PlayerGui")

local toggleBtn = Instance.new("TextButton")
toggleBtn.Name = "ToggleBtn"
toggleBtn.Size = UDim2.new(0, 140, 0, 40)
toggleBtn.Position = UDim2.new(0, 20, 0, 20)
toggleBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 40)
toggleBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleBtn.TextSize = 14
toggleBtn.Font = Enum.Font.GothamBold
toggleBtn.Text = "Status: ON"
toggleBtn.Parent = screenGui

local uiCorner = Instance.new("UICorner")
uiCorner.CornerRadius = UDim.new(0, 8)
uiCorner.Parent = toggleBtn

toggleBtn.MouseButton1Click:Connect(function()
    getgenv().Config.Enabled = not getgenv().Config.Enabled
    if getgenv().Config.Enabled then
        toggleBtn.Text = "Status: ON"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 40)
    else
        toggleBtn.Text = "Status: OFF"
        toggleBtn.BackgroundColor3 = Color3.fromRGB(160, 40, 40)
    end
end)

-- Weapon Dropdown UI
local weaponBtn = Instance.new("TextButton")
weaponBtn.Name = "WeaponBtn"
weaponBtn.Size = UDim2.new(0, 140, 0, 35)
weaponBtn.Position = UDim2.new(0, 20, 0, 70)
weaponBtn.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
weaponBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
weaponBtn.TextSize = 13
weaponBtn.Font = Enum.Font.GothamMedium
weaponBtn.Text = "Weapon: Primary"
weaponBtn.Parent = screenGui

local weaponCorner = Instance.new("UICorner")
weaponCorner.CornerRadius = UDim.new(0, 8)
weaponCorner.Parent = weaponBtn

local slotsList = {"Primary", "Secondary", "Melee"}
local currentSlotIndex = 1

weaponBtn.MouseButton1Click:Connect(function()
    currentSlotIndex = currentSlotIndex % #slotsList + 1
    local newSlot = slotsList[currentSlotIndex]
    getgenv().Config.WeaponSlot = newSlot
    weaponBtn.Text = "Weapon: " .. newSlot
end)

-- Anti-Kill / Hazard / Chainsaw & SubSpace Tripmine Void Cleaner
local function handleDangerousItems()
    for _, obj in ipairs(ws:GetDescendants()) do
        local name = obj.Name:lower()
        if name:find("kill") or name:find("lava") or name:find("death") or name:find("hazard") or name:find("damage") or name:find("chainsaw") or name:find("subspace tripmine") then
            pcall(function()
                if obj:IsA("BasePart") then
                    -- Send to void and freeze
                    obj.CFrame = CFrame.new(obj.Position.X, -500, obj.Position.Z)
                    obj.AssemblyLinearVelocity = Vector3.zero
                    obj.AssemblyAngularVelocity = Vector3.zero
                    obj.Anchored = true
                elseif obj:IsA("Model") then
                    local primary = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
                    if primary then
                        primary.CFrame = CFrame.new(primary.Position.X, -500, primary.Position.Z)
                        primary.Anchored = true
                    end
                end
            end)
        end
    end
end

task.spawn(function()
    while true do
        handleDangerousItems()
        task.wait(0.5)
    end
end)

ws.DescendantAdded:Connect(function(obj)
    local name = obj.Name:lower()
    if name:find("kill") or name:find("lava") or name:find("death") or name:find("hazard") or name:find("damage") or name:find("chainsaw") or name:find("subspace tripmine") then
        pcall(function()
            if obj:IsA("BasePart") then
                obj.CFrame = CFrame.new(obj.Position.X, -500, obj.Position.Z)
                obj.AssemblyLinearVelocity = Vector3.zero
                obj.AssemblyAngularVelocity = Vector3.zero
                obj.Anchored = true
            elseif obj:IsA("Model") then
                local primary = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
                if primary then
                    primary.CFrame = CFrame.new(primary.Position.X, -500, primary.Position.Z)
                    primary.Anchored = true
                end
            end
        end)
    end
end)

local slots = {
    Primary = 1,
    Secondary = 2,
    Melee = 3
}

local function getSlotNumber()
    return slots[getgenv().Config.WeaponSlot] or 1
end

task.spawn(function()
    local localFighter = FighterController.LocalFighter
    while not localFighter do
        task.wait(0.1)
        localFighter = FighterController.LocalFighter
    end
    pcall(function() localFighter:EquipItem(getSlotNumber()) end)
end)

task.spawn(function()
    while true do
        task.wait(1)
        if not getgenv().Config.Enabled then continue end
        local localFighter = FighterController.LocalFighter
        if localFighter then
            pcall(function() localFighter:EquipItem(getSlotNumber()) end)
        end
    end
end)

-- Emote Player Logic
local CurrentTrack
local character = lplr.Character or lplr.CharacterAdded:Wait()
local humanoid = character:WaitForChild("Humanoid")
local lastPosition = character.PrimaryPart and character.PrimaryPart.Position or Vector3.new()

lplr.CharacterAdded:Connect(function(newCharacter)
    character = newCharacter
    humanoid = character:WaitForChild("Humanoid")
    lastPosition = character.PrimaryPart and character.PrimaryPart.Position or Vector3.new()
end)

local function LoadTrack(id)
    if CurrentTrack then CurrentTrack:Stop(0) end
    local animId = "rbxassetid://" .. tostring(id)
    local ok, result = pcall(function() return game:GetObjects(animId) end)
    if ok and result and #result > 0 then
        local anim = result[1]
        if anim:IsA("Animation") then animId = anim.AnimationId end
    end
    local newAnim = Instance.new("Animation")
    newAnim.AnimationId = animId
    local newTrack = humanoid:LoadAnimation(newAnim)
    newTrack.Priority = Enum.AnimationPriority.Action4
    local weight = getgenv().Config.Weight == 0 and 0.001 or getgenv().Config.Weight
    newTrack:Play(getgenv().Config.FadeIn, weight, getgenv().Config.Speed)
    CurrentTrack = newTrack
    return newTrack
end

task.spawn(function()
    task.wait(1)
    pcall(function() LoadTrack(getgenv().Config.EmoteID) end)
end)

-- Collision / Invisibility Handling
local originalCollisionStates = {}
local humanoidRootPart = character:WaitForChild("HumanoidRootPart")

local function saveCollisionStates()
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") and part ~= humanoidRootPart then
            originalCollisionStates[part] = part.CanCollide
        end
    end
end

local function disableCollisionsExceptRootPart()
    if not getgenv().Config.AllowInvisible then return end
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") and part ~= humanoidRootPart then
            part.CanCollide = false
        end
    end
end

local function restoreCollisionStates()
    for part, canCollide in pairs(originalCollisionStates) do
        if part and part.Parent then part.CanCollide = canCollide end
    end
    originalCollisionStates = {}
end

saveCollisionStates()

runS.Stepped:Connect(function()
    if character and character.Parent and getgenv().Config.AllowInvisible then
        disableCollisionsExceptRootPart()
    end
end)

lplr.CharacterAdded:Connect(function(newCharacter)
    restoreCollisionStates()
    character = newCharacter
    humanoidRootPart = character:WaitForChild("HumanoidRootPart")
    saveCollisionStates()
    task.wait(1)
    pcall(function() LoadTrack(getgenv().Config.EmoteID) end)
end)

runS.RenderStepped:Connect(function()
    if character.PrimaryPart then
        if getgenv().Config.StopOnMove and CurrentTrack and CurrentTrack.IsPlaying then
            local moved = (character.PrimaryPart.Position - lastPosition).Magnitude > 0.1
            local jumped = humanoid and humanoid:GetState() == Enum.HumanoidStateType.Jumping
            if moved or jumped then
                CurrentTrack:Stop(getgenv().Config.FadeOut)
                CurrentTrack = nil
            end
        end
        lastPosition = character.PrimaryPart.Position
    end
end)

local lastFire = 0
local deflecting = {}
plrs.PlayerRemoving:Connect(function(player) deflecting[player] = nil end)

local function updateDeflection()
    if not FighterController or not FighterController.Objects then return end
    for _, fighterObj in FighterController.Objects do
        local player = fighterObj.Player
        if not player then continue end
        if not fighterObj.Entity or not fighterObj.Entity:IsAlive() or fighterObj:Get("IsSpectating") then
            deflecting[player] = false
            continue
        end
        local equipped = fighterObj.EquippedItem
        local itemName = equipped and equipped.ViewModel and equipped.ViewModel.Name or ""
        local isDeflecting = (itemName == "Katana" or itemName == "Chainsaw") and (equipped._attack_cooldown and equipped._attack_cooldown > tick()) or false
        deflecting[player] = isDeflecting
    end
end

local function isEnemy(player)
    if player == lplr then return false end
    local duel = SpectateController.CurrentDuelSubject
    local localDueler = duel and duel:GetDueler(lplr)
    local localTeam = localDueler and localDueler:Get("TeamID") or nil
    if localTeam and duel and duel.Duelers then
        for _, dueler in duel.Duelers do
            if dueler.Player == player then
                return dueler:Get("TeamID") ~= localTeam
            end
        end
    end
    local pTeam = player:GetAttribute("TeamID")
    local lTeam = lplr:GetAttribute("TeamID")
    if pTeam and lTeam then return pTeam ~= lTeam end
    return true
end

local function getClosestTarget()
    local char = lplr.Character
    if not char then return nil, nil, nil end
    local myRoot = char:FindFirstChild("HumanoidRootPart")
    if not myRoot then return nil, nil, nil end
    local closestPlayer, closestRoot, closestHead = nil, nil, nil
    local closestDist = 500
    for _, player in plrs:GetPlayers() do
        if not isEnemy(player) then continue end
        local pChar = player.Character
        if not pChar then continue end
        local pRoot = pChar:FindFirstChild("HumanoidRootPart")
        local pHead = pChar:FindFirstChild("Head")
        local pHum = pChar:FindFirstChildWhichIsA("Humanoid")
        if not (pRoot and pHead and pHum) then continue end
        local dist = (myRoot.Position - pRoot.Position).Magnitude
        if dist < closestDist then
            closestDist = dist
            closestPlayer = player
            closestRoot = pRoot
            closestHead = pHead
        end
    end
    return closestPlayer, closestRoot, closestHead
end

runS.Heartbeat:Connect(function()
    if lplr.Character and lplr.Character:FindFirstChild("HumanoidRootPart") then
        local myRootPart = lplr.Character.HumanoidRootPart
        if myRootPart.Position.Y < -40 then
            myRootPart.CFrame = CFrame.new(myRootPart.Position.X, 50, myRootPart.Position.Z)
            myRootPart.Velocity = Vector3.zero
        end
    end

    updateDeflection()
    local targetPlayer, targetRoot, targetHead = getClosestTarget()
    local desyncCF = nil

    if targetPlayer and targetRoot and targetHead then
        local pHum = targetPlayer.Character and targetPlayer.Character:FindFirstChildWhichIsA("Humanoid")
        local isTargetDead = (not pHum or pHum.Health <= 0 or pHum.Health <= -150)
        
        if isTargetDead then
            local dropPos = targetRoot.Position + Vector3.new(0, getgenv().Config.DeathDropThreshold, 0)
            desyncCF = CFrame.new(dropPos)
        else
            local targetPos = targetRoot.Position
            if getgenv().Config.RandomTeleport then
                local angle = math.random() * math.pi * 2
                local radius = math.random(getgenv().Config.MinTeleportRadius * 10, getgenv().Config.MaxTeleportRadius * 10) / 10
                local height = math.random(getgenv().Config.HeightOffsetMin * 10, getgenv().Config.HeightOffsetMax * 10) / 10
                local randomOffset = Vector3.new(math.cos(angle) * radius, height, math.sin(angle) * radius)
                targetPos = targetRoot.Position + randomOffset
            else
                local behindOffset = Vector3.new(0, 0, getgenv().Config.BehindDistance)
                targetPos = targetRoot.CFrame:PointToWorldSpace(behindOffset)
            end

            -- Out-of-Bounds & Arena Protection Check
            local validPos = true
            if targetPos.Y < getgenv().Config.MinBoundsY or targetPos.Y > getgenv().Config.MaxBoundsY then
                validPos = false
            end
            if (targetPos - targetRoot.Position).Magnitude > getgenv().Config.MaxDistanceFromTarget then
                validPos = false
            end

            if not validPos then
                targetPos = targetRoot.Position + Vector3.new(0, 2, 2)
            end

            desyncCF = CFrame.lookAt(targetPos, targetHead.Position) * CFrame.Angles(math.rad(180), 0, 0)
        end
    else
        local myRoot = lplr.Character and lplr.Character:FindFirstChild("HumanoidRootPart")
        if myRoot then desyncCF = myRoot.CFrame end
    end

    if desyncCF and lplr.Character then
        local myRoot = lplr.Character:FindFirstChild("HumanoidRootPart")
        if myRoot then
            local oldCF = myRoot.CFrame
            local oldVel = myRoot.Velocity
            local oldRotVel = myRoot.RotVelocity
            myRoot.CFrame = desyncCF
            runS:BindToRenderStep("__restore", 101, function()
                if myRoot then
                    myRoot.CFrame = oldCF
                    myRoot.Velocity = oldVel
                    myRoot.RotVelocity = oldRotVel
                end
                runS:UnbindFromRenderStep("__restore")
            end)
        end
    end

    if not getgenv().Config.Enabled then return end
    if not targetPlayer or not targetHead or not targetRoot then return end
    local pHum = targetPlayer.Character and targetPlayer.Character:FindFirstChildWhichIsA("Humanoid")
    if not pHum or pHum.Health <= 0 or pHum.Health <= -150 then return end
    if deflecting[targetPlayer] then return end
    if not lplr.Character or not lplr.Character:FindFirstChild("HumanoidRootPart") then return end
    if not FighterController or not FighterController.LocalFighter then return end
    local item = FighterController.LocalFighter.EquippedItem
    if not item then return end
    if tick() - lastFire < getgenv().Config.FireRate then return end
    lastFire = tick()
    
    local originPos = desyncCF and desyncCF.Position or targetRoot.Position
    local targetPos = targetHead.Position
    local aimCF = CFrame.lookAt(originPos, targetPos)
    local targetCF = targetHead.CFrame
    local randomOffset = Vector3.new((math.random() - 0.5) * 0.1, (math.random() - 0.5) * 0.1, (math.random() - 0.5) * 0.1)
    local aimedPos = targetPos + randomOffset
    local objSpaceHeadOffset = targetHead.CFrame:ToObjectSpace(CFrame.new(aimedPos))
    local cameradata = {}
    local utf8_char_1 = string.char(1)
    local utf8_char_0 = string.char(0)
    local utf8_char_2 = string.char(2)
    local utf8_char_3 = string.char(3)

    cameradata[utf8_char_1] = {
        [utf8_char_0] = util:EncodeCFrame(aimCF),
        [utf8_char_1] = util:EncodeCFrame(targetCF),
        [utf8_char_2] = targetHead,
        [utf8_char_3] = util:EncodeCFrame(objSpaceHeadOffset)
    }
    repS.Remotes.Replication.Fighter.UseItem:FireServer(
        item:Get("ObjectID"),
        enum:ToEnum("StartShooting"),
        cameradata,
        nil
    )
end) --- made by Srilangish