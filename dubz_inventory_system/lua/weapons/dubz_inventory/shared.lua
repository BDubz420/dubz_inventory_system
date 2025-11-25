AddCSLuaFile()

DUBZ_INVENTORY = DUBZ_INVENTORY or {}

SWEP.PrintName = "Dubz Inventory"
SWEP.Author = "BDubz"
SWEP.Instructions = "Primary: Pick up    Secondary: Drop last    Reload: Open inventory"
SWEP.Category = (DUBZ_INVENTORY and DUBZ_INVENTORY.Config.Category) or "Dubz Utilities"
SWEP.Spawnable = true
SWEP.AdminOnly = false

SWEP.ViewModel = "models/weapons/c_arms_citizen.mdl"
SWEP.WorldModel = "models/weapons/w_toolgun.mdl"
SWEP.UseHands = true
SWEP.ViewModelFOV = 62
SWEP.DrawCrosshair = true

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

local config = DUBZ_INVENTORY and DUBZ_INVENTORY.Config or {
    Capacity = 10,
    ColorBackground = Color(0, 0, 0, 190),
    ColorPanel = Color(24, 28, 38),
    ColorAccent = Color(25, 178, 208),
    ColorText = Color(230, 234, 242),
    PocketWhitelist = {}
}

if SERVER then
    util.AddNetworkString("DubzInventory_Open")
    util.AddNetworkString("DubzInventory_Action")
    util.AddNetworkString("DubzInventory_Move")
    util.AddNetworkString("DubzInventory_Tip")

    function SWEP:Initialize()
        self:SetHoldType("slam")
        self.StoredItems = {}
    end

    local spawnWorldItem

    local function cleanItems(swep)
        if not IsValid(swep) then return {} end
        swep.StoredItems = swep.StoredItems or {}
        return swep.StoredItems
    end

    local function subMaterialsMatch(a, b)
        if (not a) and (not b) then return true end
        if (not a) or (not b) then return false end
        if table.Count(a) ~= table.Count(b) then return false end

        for idx, mat in pairs(a) do
            if b[idx] ~= mat then
                return false
            end
        end

        return true
    end

    function DUBZ_INVENTORY.CanStack(a, b)
        if not (a and b) then return false end
        if a.class ~= b.class or a.model ~= b.model or a.itemType ~= b.itemType then return false end
        if a.material ~= b.material then return false end
        if not subMaterialsMatch(a.subMaterials, b.subMaterials) then return false end

        -- Do not stack unique-state entities so we never lose their stored data
        if a.entState or b.entState then return false end

        return true
    end

    function DUBZ_INVENTORY.AddItem(swep, itemData)
        if not IsValid(swep) or not itemData or not itemData.class then return false end
        local items = cleanItems(swep)
        for _, data in ipairs(items) do
            if DUBZ_INVENTORY.CanStack(data, itemData) then
                data.quantity = (data.quantity or 1) + (itemData.quantity or 1)
                return true
            end
        end

        if #items >= config.Capacity then return false end

        itemData.quantity = itemData.quantity or 1
        table.insert(items, itemData)
        return true
    end

    function DUBZ_INVENTORY.RemoveItem(swep, index, amount)
        local items = cleanItems(swep)
        local data = items[index]
        if not data then return nil end

        local take = math.min(amount or 1, data.quantity or 1)
        data.quantity = (data.quantity or 1) - take

        if data.quantity <= 0 then
            table.remove(items, index)
        end

        data.quantity = take
        return data
    end

    function DUBZ_INVENTORY.TransferItem(srcSwep, dstSwep, index, amount)
        if not (IsValid(srcSwep) and IsValid(dstSwep)) then return false end
        local removed = DUBZ_INVENTORY.RemoveItem(srcSwep, index, amount)
        if not removed then return false end

        removed.quantity = amount or removed.quantity or 1
        local added = DUBZ_INVENTORY.AddItem(dstSwep, removed)
        if not added then
            DUBZ_INVENTORY.AddItem(srcSwep, removed)
            return false
        end

        return true
    end

    local function sendTip(ply, msg)
        if not IsValid(ply) then return end
        net.Start("DubzInventory_Tip")
        net.WriteString(msg)
        net.Send(ply)
    end

    local function verifySwep(ply, swep)
        return IsValid(ply) and IsValid(swep) and swep:GetOwner() == ply and swep:GetClass() == "dubz_inventory"
    end

    local function pocketBlacklist()
        if DarkRP and DarkRP.getPocketBlacklist then
            return DarkRP.getPocketBlacklist() or {}
        end

        if GAMEMODE and GAMEMODE.Config and GAMEMODE.Config.PocketBlacklist then
            return GAMEMODE.Config.PocketBlacklist
        end

        return {}
    end

    local function isPocketBlacklisted(class)
        local blacklist = pocketBlacklist()
        if not blacklist then return false end

        if blacklist[class] then return true end

        for _, value in ipairs(blacklist) do
            if value == class then
                return true
            end
        end

        return false
    end

    local function captureSubMaterials(ent)
        local mats = ent:GetMaterials()
        if not mats or #mats == 0 then return nil end

        local subs = {}
        for i = 0, #mats do
            local sub = ent:GetSubMaterial(i)
            if sub and sub ~= "" then
                subs[i] = sub
            end
        end

        if table.IsEmpty(subs) then return nil end
        return subs
    end

    local function captureEntityState(ent)
        local dupe = duplicator and duplicator.CopyEntTable and duplicator.CopyEntTable(ent)
        local mods
        if duplicator and duplicator.CopyEntTable and ent.EntityMods then
            mods = duplicator.CopyEntTable(ent.EntityMods)
        end

        local material = ent:GetMaterial()
        local subMats = captureSubMaterials(ent)
        local skin = ent:GetSkin()

        if (not dupe or table.IsEmpty(dupe)) and (not mods or table.IsEmpty(mods)) and (not material or material == "") and (not subMats) and (not skin or skin == 0) then
            return nil
        end

        return {
            dupe = dupe,
            mods = mods,
            skin = skin,
            material = material,
            subMaterials = subMats
        }
    end

    local function weaponData(ent)
        local class = ent:GetClass()
        return {
            class = class,
            name = ent.PrintName or class,
            model = ent.WorldModel or ent:GetModel(),
            quantity = 1,
            itemType = "weapon",
            clip1 = ent:Clip1(),
            clip2 = ent:Clip2(),
            ammoType1 = ent:GetPrimaryAmmoType(),
            ammoType2 = ent:GetSecondaryAmmoType()
        }
    end

    local function entityData(ent)
        local class = ent:GetClass()
        return {
            class = class,
            name = ent.PrintName or class,
            model = ent:GetModel(),
            quantity = 1,
            itemType = "entity",
            material = ent:GetMaterial(),
            subMaterials = captureSubMaterials(ent),
            entState = captureEntityState(ent)
        }
    end

    local function traceTarget(ply)
        local tr = util.TraceLine({
            start = ply:EyePos(),
            endpos = ply:EyePos() + ply:EyeAngles():Forward() * 100,
            filter = ply
        })
        return tr.Entity
    end

    local function storePickup(ply, swep, ent)
        if not IsValid(ent) then
            sendTip(ply, "Aim at a weapon or whitelisted item to pick it up")
            return
        end

        if ent:IsPlayer() or ent:IsNPC() then
            sendTip(ply, "You can't store that")
            return
        end

        if isPocketBlacklisted(ent:GetClass()) then
            sendTip(ply, "This item is pocket blacklisted")
            return
        end

        local item
        if ent:IsWeapon() then
            if ent:GetOwner() == ply then
                sendTip(ply, "Drop the weapon first")
                return
            end
            item = weaponData(ent)
        elseif next(config.PocketWhitelist) == nil or config.PocketWhitelist[ent:GetClass()] then
            item = entityData(ent)
        else
            sendTip(ply, "Item is not allowed in this inventory")
            return
        end

        if not DUBZ_INVENTORY.AddItem(swep, item) then
            sendTip(ply, "Inventory is full")
            return
        end

        ent:Remove()
        sendTip(ply, string.format("Stored %s", item.name))
    end

    function SWEP:PrimaryAttack()
        self:SetNextPrimaryFire(CurTime() + 0.25)
        storePickup(self:GetOwner(), self, traceTarget(self:GetOwner()))
    end

    local function dropLast(ply, swep)
        local items = cleanItems(swep)
        local count = #items
        if count <= 0 then
            sendTip(ply, "No items to drop")
            return
        end

        local data = items[count]
        local removed = DUBZ_INVENTORY.RemoveItem(swep, count, data.quantity or 1)
        if not removed then return end

        removed.quantity = removed.quantity or 1
        for _ = 1, removed.quantity do
            spawnWorldItem(ply, removed)
        end

        sendTip(ply, string.format("Dropped %s", removed.name or "item"))
    end

    function SWEP:SecondaryAttack()
        self:SetNextSecondaryFire(CurTime() + 0.25)
        dropLast(self:GetOwner(), self)
    end

    function SWEP:Reload()
        self:SetNextPrimaryFire(CurTime() + 0.25)
        self:SetNextSecondaryFire(CurTime() + 0.25)
        DUBZ_INVENTORY.OpenFor(self:GetOwner(), self)
    end

    function DUBZ_INVENTORY.OpenFor(ply, swep)
        if not verifySwep(ply, swep) then return end

        local items = cleanItems(swep)

        net.Start("DubzInventory_Open")
        net.WriteEntity(swep)
        net.WriteUInt(#items, 8)
        for _, data in ipairs(items) do
            net.WriteString(data.class or "")
            net.WriteString(data.name or data.class or "Unknown Item")
            net.WriteString(data.model or "")
            net.WriteUInt(math.Clamp(data.quantity or 1, 1, 65535), 16)
            net.WriteString(data.itemType or "entity")
            net.WriteString(data.material or "")

            local subMats = data.subMaterials or {}
            net.WriteUInt(math.min(table.Count(subMats), 16), 5)
            for idx, mat in pairs(subMats) do
                net.WriteUInt(idx, 5)
                net.WriteString(mat)
            end
        end
        net.Send(ply)
    end

    function spawnWorldItem(ply, data)
        local pos = ply:EyePos() + ply:EyeAngles():Forward() * 30
        local ent = ents.Create(data.class)
        if not IsValid(ent) then return false end

        ent:SetPos(pos)
        ent:SetAngles(Angle(0, ply:EyeAngles().yaw, 0))
        ent:Spawn()
        ent:Activate()

        if data.itemType == "weapon" then
            if data.clip1 then
                ent:SetClip1(data.clip1)
            end
            if data.clip2 then
                ent:SetClip2(data.clip2)
            end
        end

        local material = data.material or (data.entState and data.entState.material)
        local subMaterials = data.subMaterials or (data.entState and data.entState.subMaterials)

        if material and material ~= "" then
            ent:SetMaterial(material)
        end

        if subMaterials then
            for idx, mat in pairs(subMaterials) do
                ent:SetSubMaterial(idx, mat)
            end
        end

        if data.entState and data.entState.dupe and duplicator and duplicator.DoGeneric then
            duplicator.DoGeneric(ent, data.entState.dupe)
        end

        if data.entState and data.entState.skin then
            ent:SetSkin(data.entState.skin)
        end

        ent:SetPos(pos)
        ent:SetAngles(Angle(0, ply:EyeAngles().yaw, 0))

        if data.entState and data.entState.mods and duplicator and duplicator.ApplyEntityModifier then
            for mod, info in pairs(data.entState.mods) do
                duplicator.ApplyEntityModifier(ply, ent, mod, info)
            end
        end

        return true
    end

    net.Receive("DubzInventory_Action", function(_, ply)
        local swep = net.ReadEntity()
        local index = net.ReadUInt(8)
        local action = net.ReadString()
        local amount = net.ReadUInt(16)

        if not verifySwep(ply, swep) then return end

        local items = cleanItems(swep)
        local data = items[index]
        if not data then return end

        if action == "use" then
            local removed = DUBZ_INVENTORY.RemoveItem(swep, index, 1)
            if not removed then return end

            if removed.itemType == "weapon" then
                local given = ply:Give(removed.class)
                if IsValid(given) then
                    given.PrintName = removed.name
                    if removed.clip1 then given:SetClip1(removed.clip1) end
                    if removed.clip2 then given:SetClip2(removed.clip2) end
                    if removed.ammoType1 and removed.clip1 and removed.clip1 > 0 then
                        ply:GiveAmmo(removed.clip1, removed.ammoType1)
                    end
                    if removed.ammoType2 and removed.clip2 and removed.clip2 > 0 then
                        ply:GiveAmmo(removed.clip2, removed.ammoType2)
                    end
                    sendTip(ply, "Equipped " .. removed.name)
                end
            else
                if spawnWorldItem(ply, removed) then
                    sendTip(ply, "Spawned " .. removed.name)
                end
            end
        elseif action == "drop" then
            local toDrop = math.max(amount, 1)
            local removed = DUBZ_INVENTORY.RemoveItem(swep, index, toDrop)
            if not removed then return end

            removed.quantity = 1
            for _ = 1, toDrop do
                spawnWorldItem(ply, removed)
            end
            sendTip(ply, "Dropped " .. removed.name)
        elseif action == "destroy" then
            DUBZ_INVENTORY.RemoveItem(swep, index, math.max(amount, 1))
            sendTip(ply, "Destroyed item")
        elseif action == "split" then
            local dataRef = items[index]
            if dataRef and (dataRef.quantity or 1) > 1 then
                local half = math.floor(dataRef.quantity / 2)
                dataRef.quantity = dataRef.quantity - half
                DUBZ_INVENTORY.AddItem(swep, {
                    class = dataRef.class,
                    name = dataRef.name,
                    model = dataRef.model,
                    quantity = half,
                    itemType = dataRef.itemType
                })
                sendTip(ply, "Split stack")
            end
        end

        DUBZ_INVENTORY.OpenFor(ply, swep)
    end)

    net.Receive("DubzInventory_Move", function(_, ply)
        local src = net.ReadEntity()
        local dst = net.ReadEntity()
        local index = net.ReadUInt(8)
        local amount = net.ReadUInt(16)

        if not (verifySwep(ply, src) and verifySwep(ply, dst)) then return end

        if not DUBZ_INVENTORY.TransferItem(src, dst, index, amount) then
            sendTip(ply, "Could not move item")
        else
            DUBZ_INVENTORY.OpenFor(ply, src)
            if dst ~= src then
                DUBZ_INVENTORY.OpenFor(ply, dst)
            end
        end
    end)
end

if CLIENT then
    local bg = config.ColorBackground or Color(0, 0, 0, 190)
    local panelCol = config.ColorPanel or Color(24, 28, 38)
    local accent = config.ColorAccent or Color(25, 178, 208)
    local textColor = config.ColorText or Color(230, 234, 242)

    surface.CreateFont("DubzInv_Title", {
        font = "Montserrat",
        size = 22,
        weight = 700
    })

    surface.CreateFont("DubzInv_Label", {
        font = "Montserrat",
        size = 18,
        weight = 500
    })

    surface.CreateFont("DubzInv_Button", {
        font = "Montserrat",
        size = 16,
        weight = 600
    })

    surface.CreateFont("DubzInv_Small", {
        font = "Montserrat",
        size = 14,
        weight = 500
    })

    local function drawPanelOutline(w, h)
        draw.RoundedBox(12, 0, 0, w, h, panelCol)
        surface.SetDrawColor(accent)
        surface.DrawRect(0, 0, w, 3)
    end

    local function buildSection(parent, header)
        local wrap = vgui.Create("DPanel", parent)
        wrap:Dock(FILL)
        wrap:DockMargin(0, 8, 0, 0)
        wrap.Paint = function(self, w, h)
            drawPanelOutline(w, h)
            draw.SimpleText(header, "DubzInv_Label", 12, 10, textColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText(
                "Right click items for options",
                "DubzInv_Small",
                14,
                32,
                ColorAlpha(textColor, 160),
                TEXT_ALIGN_LEFT,
                TEXT_ALIGN_TOP
            )
        end

        local layout = vgui.Create("DIconLayout", wrap)
        layout:Dock(FILL)
        layout:DockMargin(10, 52, 10, 10)
        layout:SetSpaceX(8)
        layout:SetSpaceY(8)

        return layout
    end

    local function sendAction(swep, index, action, amount)
        net.Start("DubzInventory_Action")
        net.WriteEntity(swep)
        net.WriteUInt(index, 8)
        net.WriteString(action)
        net.WriteUInt(amount or 1, 16)
        net.SendToServer()
    end

    local function addItemIcon(layout, data, index, swep)
        local panel = layout:Add("DPanel")
        panel:SetSize(100, 120)
        panel.Paint = function(self, w, h)
            draw.RoundedBox(10, 0, 0, w, h, bg)
            draw.SimpleText(data.name, "DubzInv_Button", w / 2, h - 22, textColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText(string.format("x%d", data.quantity or 1), "DubzInv_Small", w / 2, h - 8, ColorAlpha(textColor, 180), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end

        local icon = vgui.Create("SpawnIcon", panel)
        icon:SetModel(data.model ~= "" and data.model or "models/props_junk/PopCan01a.mdl")
        icon:SetPos(7, 6)
        icon:SetSize(86, 86)
        icon:SetTooltip(nil)
        icon.PaintOver = function(self, w, h)
            surface.SetDrawColor(accent)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
        end

        if (data.material and data.material ~= "") or data.subMaterials then
            timer.Simple(0, function()
                if not (IsValid(icon) and IsValid(icon.Entity)) then return end
                if data.material and data.material ~= "" then
                    icon.Entity:SetMaterial(data.material)
                end

                if data.subMaterials then
                    for idx, mat in pairs(data.subMaterials) do
                        icon.Entity:SetSubMaterial(idx, mat)
                    end
                end
            end)
        end

        icon.DoClick = function()
            sendAction(swep, index, "use", 1)
        end

        icon.DoRightClick = function()
            local menu = DermaMenu()
            if data.itemType == "weapon" then
                menu:AddOption("Equip", function()
                    sendAction(swep, index, "use", 1)
                end):SetIcon("icon16/gun.png")
            else
                menu:AddOption("Spawn", function()
                    sendAction(swep, index, "use", 1)
                end):SetIcon("icon16/brick.png")
            end

            menu:AddOption("Drop", function()
                Derma_StringRequest("Drop amount", "How many do you want to drop?", "1", function(text)
                    sendAction(swep, index, "drop", tonumber(text) or 1)
                end)
            end):SetIcon("icon16/arrow_down.png")

            menu:AddOption("Destroy", function()
                sendAction(swep, index, "destroy", data.quantity or 1)
            end):SetIcon("icon16/bin_closed.png")

            if (data.quantity or 1) > 1 then
                menu:AddOption("Split stack", function()
                    sendAction(swep, index, "split", 1)
                end):SetIcon("icon16/table_split.png")
            end

            menu:Open()
        end

        return panel
    end

    net.Receive("DubzInventory_Tip", function()
        local msg = net.ReadString()
        notification.AddLegacy(msg, NOTIFY_HINT, 3)
        surface.PlaySound("buttons/button15.wav")
    end)

    net.Receive("DubzInventory_Open", function()
        local swep = net.ReadEntity()
        local count = net.ReadUInt(8)
        local items = {}
        for i = 1, count do
            local subMaterialCount
            local subMaterials = {}

            items[i] = {
                class = net.ReadString(),
                name = net.ReadString(),
                model = net.ReadString(),
                quantity = net.ReadUInt(16),
                itemType = net.ReadString(),
                material = net.ReadString()
            }

            subMaterialCount = net.ReadUInt(5)
            for _ = 1, subMaterialCount do
                local idx = net.ReadUInt(5)
                subMaterials[idx] = net.ReadString()
            end

            if not table.IsEmpty(subMaterials) then
                items[i].subMaterials = subMaterials
            end
        end

        if not IsValid(swep) then return end

        local frames = DUBZ_INVENTORY.ActiveFrames or {}

        local function ensureFrame()
            if IsValid(frames[swep]) then return frames[swep] end

            local frame = vgui.Create("DFrame")
            frame:SetSize(700, 520)
            frame:Center()
            frame:MakePopup()
            frame:SetTitle("")
            frame:ShowCloseButton(false)
            frame.Paint = function(self, w, h)
                draw.RoundedBox(12, 0, 0, w, h, bg)
                draw.SimpleText("Dubz Inventory", "DubzInv_Title", 14, 10, textColor)
                draw.SimpleText(string.format("%d / %d stacks", self.ItemCount or 0, config.Capacity), "DubzInv_Button", 16, 42, ColorAlpha(textColor, 180))
                surface.SetDrawColor(accent)
                surface.DrawRect(0, 0, w, 3)
            end

            local close = vgui.Create("DButton", frame)
            close:SetText("✕")
            close:SetFont("DubzInv_Title")
            close:SetTextColor(textColor)
            close:SetSize(34, 34)
            close:SetPos(frame:GetWide() - 44, 10)
            close.Paint = function(self, w, h)
                draw.RoundedBox(8, 0, 0, w, h, panelCol)
            end
            close.DoClick = function()
                frame:Close()
            end

            frame.OnClose = function()
                frames[swep] = nil
            end

            local body = vgui.Create("DPanel", frame)
            body:Dock(FILL)
            body:DockMargin(12, 70, 12, 12)
            body.Paint = nil

            local info = vgui.Create("DLabel", body)
            info:Dock(TOP)
            info:SetTall(26)
            info:SetFont("DubzInv_Button")
            info:SetTextColor(ColorAlpha(textColor, 180))
            info:SetText("Left click items on the ground to store them. Secondary drops last. Reload opens this menu.")
            frame.Info = info

            local grid = buildSection(body, "Inventory")
            frame.Grid = grid

            frame.Refresh = function(self, itemList)
                self.ItemCount = #itemList
                self.Grid:Clear()
                for idx, data in ipairs(itemList) do
                    addItemIcon(self.Grid, data, idx, swep)
                end
            end

            frames[swep] = frame
            return frame
        end

        local frame = ensureFrame()
        DUBZ_INVENTORY.ActiveFrames = frames
        if IsValid(frame) then
            frame:Refresh(items)
        end
    end)
end

function SWEP:Deploy()
    if CLIENT then return true end
    self:SetNextPrimaryFire(CurTime() + 0.2)
    self:SetNextSecondaryFire(CurTime() + 0.2)
    return true
end

function SWEP:Holster()
    return true
end

function SWEP:OnRemove()
    self.StoredItems = nil
end
