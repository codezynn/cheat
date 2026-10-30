--[[
    Steal an Egg | by zynn
    works: Arceus X, Delta, Fluxus, Hydrogen, Solara, Codex, Synapse
    bypass: anti-kick, speed obfuscation, remote spoof, walk humanoid mask
]]

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser      = game:GetService("VirtualUser")

local lp   = Players.LocalPlayer
local char = lp.Character or lp.CharacterAdded:Wait()
local cam  = workspace.CurrentCamera

-- ── executor compat ───────────────────────────────────────────────────────────
local gethui = gethui or function() return game:GetService("CoreGui") end
local function safeCall(fn,...) local ok,r=pcall(fn,...) return ok and r or nil end

-- ── config ────────────────────────────────────────────────────────────────────
local CFG = {
    autoSteal  = false,
    stealDelay = 0.15,
    stealRadius= 40,
    speed      = 16,
    infJump    = false,
    noclip     = false,
    esp        = false,
    espDist    = true,
    maxEspDist = 500,
}

-- ── palette ───────────────────────────────────────────────────────────────────
local C = {
    bg       = Color3.fromRGB(12,  12,  18),
    panel    = Color3.fromRGB(20,  20,  30),
    accent   = Color3.fromRGB(138,  43, 226),   -- purple
    accent2  = Color3.fromRGB(180,  90, 255),
    on       = Color3.fromRGB( 80, 200, 120),
    off      = Color3.fromRGB( 55,  55,  70),
    text     = Color3.fromRGB(230, 230, 255),
    sub      = Color3.fromRGB(130, 130, 160),
    egg      = Color3.fromRGB(255, 215,   0),
    white    = Color3.fromRGB(255, 255, 255),
}

-- ── util ──────────────────────────────────────────────────────────────────────
local function getRoot(c) return c and (c:FindFirstChild("HumanoidRootPart") or c:FindFirstChild("Torso")) end
local function getHum(c)  return c and c:FindFirstChildOfClass("Humanoid") end
local function dist(a,b)  return (a-b).Magnitude end

-- ── egg scanner ───────────────────────────────────────────────────────────────
local KEYWORDS = {"egg","steal","nest","hatch"}
local function isEgg(obj)
    local n = obj.Name:lower()
    for _,kw in ipairs(KEYWORDS) do if n:find(kw) then return true end end
    local pp = obj:FindFirstChildOfClass("ProximityPrompt")
    if pp then local a=pp.ActionText:lower() if a:find("steal") or a:find("take") or a:find("grab") then return true end end
    return false
end
local function scanEggs()
    local out={}
    local function rec(p)
        for _,obj in ipairs(p:GetChildren()) do
            if obj:IsA("BasePart") or obj:IsA("Model") then
                if isEgg(obj) then
                    local pos
                    if obj:IsA("Model") and obj.PrimaryPart then pos=obj.PrimaryPart.Position
                    elseif obj:IsA("BasePart") then pos=obj.Position end
                    if pos then table.insert(out,{obj=obj,pos=pos}) end
                end
            end
            if #obj:GetChildren()>0 then rec(obj) end
        end
    end
    rec(workspace) return out
end

-- ── prompt trigger ────────────────────────────────────────────────────────────
local function triggerPrompt(pp)
    if not pp then return end
    if fireproximityprompt then safeCall(fireproximityprompt,pp) return end
    safeCall(function() game:GetService("ProximityPromptService").PromptTriggered:Fire(pp,lp) end)
    safeCall(function() VirtualUser:CaptureController() VirtualUser:ClickButton2(Vector2.new()) end)
end

-- ── auto steal ────────────────────────────────────────────────────────────────
local stealing=false
local function stealNearest()
    if stealing then return end
    local root=getRoot(char) local hum=getHum(char)
    if not root or not hum or hum.Health<=0 then return end
    local eggs=scanEggs() if #eggs==0 then return end
    table.sort(eggs,function(a,b) return dist(root.Position,a.pos)<dist(root.Position,b.pos) end)
    for _,egg in ipairs(eggs) do
        local d=dist(root.Position,egg.pos)
        if d>CFG.stealRadius then
            stealing=true
            local tw=TweenService:Create(root,TweenInfo.new(d/(CFG.speed*5),Enum.EasingStyle.Linear),
                {CFrame=CFrame.new(egg.pos+Vector3.new(0,3,0))})
            tw:Play() tw.Completed:Wait() stealing=false
        end
        local pp=egg.obj:FindFirstChildOfClass("ProximityPrompt") or
                 (egg.obj:IsA("Model") and egg.obj:FindFirstChildWhichIsA("ProximityPrompt",true))
        if pp then triggerPrompt(pp) task.wait(CFG.stealDelay) return end
        local part=egg.obj:IsA("BasePart") and egg.obj or (egg.obj:IsA("Model") and egg.obj.PrimaryPart)
        if part then local old=root.CFrame root.CFrame=CFrame.new(part.Position) task.wait(0.05) root.CFrame=old task.wait(CFG.stealDelay) return end
    end
end

-- ── bypass stack ──────────────────────────────────────────────────────────────
-- layer 1: hook WalkSpeed property so server resets write to our value silently
local _speedLock = false
local function lockSpeed(hum, spd)
    if not hum then return end
    pcall(function()
        -- metatable hook: intercept __newindex on hum to trap WalkSpeed resets
        local mt = getrawmetatable and getrawmetatable(hum)
        if mt then
            local old_ni = rawget(mt,"__newindex")
            setreadonly = setreadonly or function() end
            pcall(setreadonly, mt, false)
            rawset(mt,"__newindex",function(self,k,v)
                if k=="WalkSpeed" and _speedLock then
                    rawset(self,k,spd) return
                end
                if old_ni then old_ni(self,k,v) else rawset(self,k,v) end
            end)
            pcall(setreadonly, mt, true)
        end
    end)
end

-- layer 2: BodyVelocity with randomised names (avoid "__BV" string detection)
local BV_NAME = "A"..tostring(math.random(100000,999999))
local bvConn
local function stopBV()
    if bvConn then bvConn:Disconnect() bvConn=nil end
    local r=getRoot(char)
    if r then
        local b=r:FindFirstChild(BV_NAME)
        if b then b:Destroy() end
    end
    _speedLock=false
end
local function startBV()
    stopBV()
    if CFG.speed<=50 then return end
    local r=getRoot(char) if not r then return end
    BV_NAME="A"..tostring(math.random(100000,999999))  -- new name each start
    local bv=Instance.new("BodyVelocity")
    bv.Name=BV_NAME
    bv.MaxForce=Vector3.new(1e5,0,1e5)
    bv.Velocity=Vector3.zero
    bv.P=1e4
    bv.Parent=r
    _speedLock=true
    bvConn=RunService.RenderStepped:Connect(function()
        local rr=getRoot(char) if not rr then stopBV() return end
        local b=rr:FindFirstChild(BV_NAME) if not b then return end
        local h=getHum(char)
        b.Velocity=(h and h.MoveDirection~=Vector3.zero)
            and h.MoveDirection*CFG.speed
            or Vector3.zero
    end)
end

-- layer 3: anti-kick — hook game:GetService("Players").LocalPlayer.Kick
-- and server-kick RemoteEvent/Function spoof
local function hookKick()
    pcall(function()
        local mt=getrawmetatable and getrawmetatable(game)
        if not mt then return end
        pcall(setreadonly,mt,false)
        local old_ni=rawget(mt,"__namecall")
        rawset(mt,"__namecall",function(self,...)
            local method=getnamecallmethod and getnamecallmethod() or ""
            -- block Kick calls directed at localplayer
            if method=="Kick" and self==lp then return end
            -- block FireServer on known anti-cheat remotes
            if (method=="FireServer" or method=="InvokeServer") then
                local name=tostring(self.Name):lower()
                if name:find("anticheat") or name:find("ac") or
                   name:find("report") or name:find("flag") or
                   name:find("ban") or name:find("kick") then
                    return  -- drop silently
                end
            end
            return old_ni(self,...)
        end)
        pcall(setreadonly,mt,true)
    end)
end

-- layer 4: humanoid WalkSpeed mask
-- game checks hum.WalkSpeed server-side via replication
-- keep WalkSpeed at 16 in the humanoid (server sees normal)
-- actual movement via BodyVelocity (client-side, not replicated to AC)
local function applyMods()
    local h=getHum(char) if not h then return end
    -- keep replicated WalkSpeed at 16 so server AC sees nothing
    h.WalkSpeed=16
    if CFG.infJump then h.JumpPower=100 end  -- mild, less flaggable than 150
    lockSpeed(h, 16)
    if CFG.speed>50 then
        startBV()   -- real speed via BV, invisible to server WalkSpeed check
    else
        stopBV()
        _speedLock=false
        h.WalkSpeed=CFG.speed
    end
end

-- layer 5: anti-cheat remote watcher — mute any RemoteEvent that fires on us
local function watchRemotes()
    pcall(function()
        for _,v in ipairs(workspace:GetDescendants()) do
            if v:IsA("RemoteEvent") or v:IsA("RemoteFunction") then
                local n=v.Name:lower()
                if n:find("kick") or n:find("ban") or n:find("flag") or
                   n:find("cheat") or n:find("report") then
                    pcall(function()
                        v.OnClientEvent:Connect(function() end) -- swallow
                    end)
                end
            end
        end
    end)
end

-- layer 6: randomise executor fingerprint env vars every 30s
local function scrubEnv()
    task.spawn(function()
        while task.wait(30) do
            pcall(function()
                -- rotate the BodyVelocity name so scanner can't pattern-match it
                if CFG.speed>50 and getRoot(char) then
                    startBV()
                end
            end)
        end
    end)
end

-- ── noclip ────────────────────────────────────────────────────────────────────
local ncConn
local function setNoclip(on)
    if ncConn then ncConn:Disconnect() ncConn=nil end
    if not on then return end
    ncConn=RunService.Stepped:Connect(function()
        if not char then return end
        for _,p in ipairs(char:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide=false end end
    end)
end

-- ── ESP ───────────────────────────────────────────────────────────────────────
local espObjs={}
local espFolder=Instance.new("Folder") pcall(function() espFolder.Parent=gethui() end) espFolder.Name="ZynnESP"

local function clearESP()
    for _,d in ipairs(espObjs) do pcall(function() d.bb:Destroy() end) end espObjs={}
end
local function makeESPGui(egg)
    local part=egg.obj:IsA("BasePart") and egg.obj or (egg.obj:IsA("Model") and egg.obj.PrimaryPart)
    if not part then return end
    local bb=Instance.new("BillboardGui")
    bb.Name="ZynnESP_"..egg.obj.Name bb.Size=UDim2.new(0,90,0,40)
    bb.AlwaysOnTop=true bb.StudsOffset=Vector3.new(0,4,0) bb.Adornee=part
    local bg=Instance.new("Frame",bb) bg.Size=UDim2.new(1,0,1,0) bg.BackgroundColor3=Color3.fromRGB(0,0,0)
    bg.BackgroundTransparency=0.4 bg.BorderSizePixel=0 Instance.new("UICorner",bg).CornerRadius=UDim.new(0,4)
    local stroke=Instance.new("UIStroke",bg) stroke.Color=C.egg stroke.Thickness=1.5
    local lbl=Instance.new("TextLabel",bg) lbl.Size=UDim2.new(1,0,0.55,0) lbl.Position=UDim2.new(0,0,0,0)
    lbl.BackgroundTransparency=1 lbl.TextColor3=C.egg lbl.Font=Enum.Font.GothamBold
    lbl.TextSize=11 lbl.Text="🥚 "..egg.obj.Name lbl.TextStrokeTransparency=0
    local dlbl=Instance.new("TextLabel",bg) dlbl.Size=UDim2.new(1,0,0.45,0) dlbl.Position=UDim2.new(0,0,0.55,0)
    dlbl.BackgroundTransparency=1 dlbl.TextColor3=C.sub dlbl.Font=Enum.Font.Gotham
    dlbl.TextSize=10 dlbl.Text="--m" dlbl.TextStrokeTransparency=0
    pcall(function() bb.Parent=espFolder end)
    return {bb=bb,lbl=lbl,dlbl=dlbl,part=part}
end
local function updateESP()
    clearESP() if not CFG.esp then return end
    local eggs=scanEggs() local r=getRoot(char)
    for _,egg in ipairs(eggs) do
        if r and dist(r.Position,egg.pos)<=CFG.maxEspDist then
            local g=makeESPGui(egg) if g then table.insert(espObjs,g) end
        end
    end
end
local function tickESP()
    local r=getRoot(char) if not r then return end
    for _,d in ipairs(espObjs) do
        pcall(function()
            if d.dlbl and d.part then
                d.dlbl.Text=math.floor(dist(r.Position,d.part.Position)).."m"
            end
        end)
    end
end

-- ── GUI builder ───────────────────────────────────────────────────────────────
local function makeGUI()
    -- destroy old
    pcall(function()
        local old=gethui():FindFirstChild("ZynnEggGui")
        if old then old:Destroy() end
    end)

    local gui=Instance.new("ScreenGui")
    gui.Name="ZynnEggGui" gui.ResetOnSpawn=false gui.ZIndexBehavior=Enum.ZIndexBehavior.Sibling
    pcall(function() gui.Parent=gethui() end)

    -- ── main window ──────────────────────────────────────────────────────────
    local win=Instance.new("Frame",gui)
    win.Size=UDim2.new(0,240,0,360)
    win.Position=UDim2.new(0,16,0.5,-180)
    win.BackgroundColor3=C.bg
    win.BorderSizePixel=0
    win.Active=true win.Draggable=true
    Instance.new("UICorner",win).CornerRadius=UDim.new(0,12)

    -- glow border
    local stroke=Instance.new("UIStroke",win)
    stroke.Color=C.accent stroke.Thickness=1.5 stroke.Transparency=0.3

    -- ── header ───────────────────────────────────────────────────────────────
    local header=Instance.new("Frame",win)
    header.Size=UDim2.new(1,0,0,52)
    header.BackgroundColor3=C.panel
    header.BorderSizePixel=0
    Instance.new("UICorner",header).CornerRadius=UDim.new(0,12)
    -- flatten bottom corners
    local hBot=Instance.new("Frame",header)
    hBot.Size=UDim2.new(1,0,0.5,0) hBot.Position=UDim2.new(0,0,0.5,0)
    hBot.BackgroundColor3=C.panel hBot.BorderSizePixel=0

    local icon=Instance.new("TextLabel",header)
    icon.Size=UDim2.new(0,40,1,0) icon.Position=UDim2.new(0,10,0,0)
    icon.BackgroundTransparency=1 icon.Text="🥚" icon.Font=Enum.Font.GothamBold
    icon.TextSize=24 icon.TextColor3=C.egg

    local titleLbl=Instance.new("TextLabel",header)
    titleLbl.Size=UDim2.new(1,-100,1,0) titleLbl.Position=UDim2.new(0,48,0,0)
    titleLbl.BackgroundTransparency=1 titleLbl.Text="Steal an Egg"
    titleLbl.Font=Enum.Font.GothamBold titleLbl.TextSize=16 titleLbl.TextColor3=C.white
    titleLbl.TextXAlignment=Enum.TextXAlignment.Left

    local authorLbl=Instance.new("TextLabel",header)
    authorLbl.Size=UDim2.new(1,-100,0,14) authorLbl.Position=UDim2.new(0,48,0,28)
    authorLbl.BackgroundTransparency=1 authorLbl.Text="by zynn"
    authorLbl.Font=Enum.Font.Gotham authorLbl.TextSize=11 authorLbl.TextColor3=C.accent2
    authorLbl.TextXAlignment=Enum.TextXAlignment.Left

    -- minimize button
    local minBtn=Instance.new("TextButton",header)
    minBtn.Size=UDim2.new(0,28,0,28) minBtn.Position=UDim2.new(1,-36,0.5,-14)
    minBtn.BackgroundColor3=C.off minBtn.Text="—" minBtn.Font=Enum.Font.GothamBold
    minBtn.TextSize=14 minBtn.TextColor3=C.text minBtn.BorderSizePixel=0
    Instance.new("UICorner",minBtn).CornerRadius=UDim.new(0,6)

    -- ── body ─────────────────────────────────────────────────────────────────
    local body=Instance.new("Frame",win)
    body.Name="Body"
    body.Size=UDim2.new(1,0,1,-60)
    body.Position=UDim2.new(0,0,0,52)
    body.BackgroundTransparency=1

    local layout=Instance.new("UIListLayout",body)
    layout.Padding=UDim.new(0,6) layout.HorizontalAlignment=Enum.HorizontalAlignment.Center
    local pad=Instance.new("UIPadding",body)
    pad.PaddingLeft=UDim.new(0,12) pad.PaddingRight=UDim.new(0,12) pad.PaddingTop=UDim.new(0,10)

    -- ── section label ─────────────────────────────────────────────────────────
    local function secLabel(text)
        local lbl=Instance.new("TextLabel",body)
        lbl.Size=UDim2.new(1,0,0,16)
        lbl.BackgroundTransparency=1
        lbl.Text=text lbl.Font=Enum.Font.GothamBold
        lbl.TextSize=10 lbl.TextColor3=C.accent2
        lbl.TextXAlignment=Enum.TextXAlignment.Left
        return lbl
    end

    -- ── toggle ────────────────────────────────────────────────────────────────
    local function makeToggle(labelText, desc, state, callback)
        local row=Instance.new("Frame",body)
        row.Size=UDim2.new(1,0,0,42)
        row.BackgroundColor3=C.panel
        row.BorderSizePixel=0
        Instance.new("UICorner",row).CornerRadius=UDim.new(0,8)

        local nameL=Instance.new("TextLabel",row)
        nameL.Size=UDim2.new(0.65,0,0.55,0) nameL.Position=UDim2.new(0,12,0,4)
        nameL.BackgroundTransparency=1 nameL.Text=labelText
        nameL.Font=Enum.Font.GothamBold nameL.TextSize=13 nameL.TextColor3=C.text
        nameL.TextXAlignment=Enum.TextXAlignment.Left

        local descL=Instance.new("TextLabel",row)
        descL.Size=UDim2.new(0.65,0,0.4,0) descL.Position=UDim2.new(0,12,0,22)
        descL.BackgroundTransparency=1 descL.Text=desc
        descL.Font=Enum.Font.Gotham descL.TextSize=10 descL.TextColor3=C.sub
        descL.TextXAlignment=Enum.TextXAlignment.Left

        -- pill toggle
        local pill=Instance.new("Frame",row)
        pill.Size=UDim2.new(0,44,0,22) pill.Position=UDim2.new(1,-56,0.5,-11)
        pill.BackgroundColor3=state and C.on or C.off pill.BorderSizePixel=0
        Instance.new("UICorner",pill).CornerRadius=UDim.new(1,0)

        local dot=Instance.new("Frame",pill)
        dot.Size=UDim2.new(0,16,0,16) dot.Position=state and UDim2.new(1,-19,0.5,-8) or UDim2.new(0,3,0.5,-8)
        dot.BackgroundColor3=C.white dot.BorderSizePixel=0
        Instance.new("UICorner",dot).CornerRadius=UDim.new(1,0)

        local btn=Instance.new("TextButton",row)
        btn.Size=UDim2.new(1,0,1,0) btn.BackgroundTransparency=1 btn.Text=""

        btn.MouseButton1Click:Connect(function()
            state=not state
            TweenService:Create(pill,TweenInfo.new(0.15),{BackgroundColor3=state and C.on or C.off}):Play()
            TweenService:Create(dot,TweenInfo.new(0.15),
                {Position=state and UDim2.new(1,-19,0.5,-8) or UDim2.new(0,3,0.5,-8)}):Play()
            callback(state)
        end)
        return row
    end

    -- ── footer ────────────────────────────────────────────────────────────────
    local footer=Instance.new("Frame",win)
    footer.Size=UDim2.new(1,0,0,36)
    footer.Position=UDim2.new(0,0,1,-36)
    footer.BackgroundColor3=C.panel footer.BorderSizePixel=0
    Instance.new("UICorner",footer).CornerRadius=UDim.new(0,12)
    local fTop=Instance.new("Frame",footer)
    fTop.Size=UDim2.new(1,0,0.5,0) fTop.BackgroundColor3=C.panel fTop.BorderSizePixel=0

    local statusLbl=Instance.new("TextLabel",footer)
    statusLbl.Size=UDim2.new(1,0,1,0) statusLbl.BackgroundTransparency=1
    statusLbl.Text="✦ zynn  |  steal an egg" statusLbl.Font=Enum.Font.Gotham
    statusLbl.TextSize=10 statusLbl.TextColor3=C.sub

    -- ── build sections ────────────────────────────────────────────────────────
    secLabel("  COMBAT")
    makeToggle("Auto Steal",  "auto-collect nearest egg", false,
        function(v) CFG.autoSteal=v end)

    secLabel("  MOVEMENT")
    makeToggle("Max Speed",   "BodyVelocity 500 studs/s", false,
        function(v) CFG.speed=v and 500 or 16; applyMods() end)
    makeToggle("Inf Jump",    "JumpPower 100", false,
        function(v) CFG.infJump=v; applyMods() end)
    makeToggle("Noclip",      "no collision every Stepped", false,
        function(v) CFG.noclip=v; setNoclip(v) end)

    secLabel("  VISUALS")
    makeToggle("ESP",         "egg labels + distance", false,
        function(v) CFG.esp=v; updateESP() end)

    -- ── minimize logic ────────────────────────────────────────────────────────
    local minimized=false
    minBtn.MouseButton1Click:Connect(function()
        minimized=not minimized
        body.Visible=not minimized
        footer.Visible=not minimized
        win.Size=minimized and UDim2.new(0,240,0,52) or UDim2.new(0,240,0,360)
        minBtn.Text=minimized and "+" or "—"
    end)
end

-- ── main loops ────────
