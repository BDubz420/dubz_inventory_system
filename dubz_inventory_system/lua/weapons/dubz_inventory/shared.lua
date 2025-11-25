AddCSLuaFile()

DUBZ_INVENTORY = DUBZ_INVENTORY or {}

SWEP.PrintName = "Dubz Inventory"
SWEP.Author = "BDubz"
SWEP.Instructions = "Secondary: Drop backpack    Use dropped bag: Open inventory"
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
    util.AddNetworkString("DubzInventory_TradeInvite")
    util.AddNetworkString("DubzInventory_TradeReply")
    util.AddNetworkString("DubzInventory_TradeStart")
    util.AddNetworkString("DubzInventory_TradeSync")
    util.AddNetworkString("DubzInventory_TradeEnd")
    util.AddNetworkString("DubzInventory_TradeAction")

    local ActiveTrades = {}
    local PendingInvites = {}

    function SWEP:Initialize()
        self:SetHoldType("slam")
        self.StoredItems = {}
    end

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

        if (a.weaponClass or b.weaponClass) and a.weaponClass ~= b.weaponClass then return false end

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

    function DUBZ_INVENTORY.SendTip(ply, msg)
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

    local function tradeKey(a, b)
        if not (IsValid(a) and IsValid(b)) then return nil end
        local ids = {a:SteamID64() or a:UserID(), b:SteamID64() or b:UserID()}
        table.sort(ids)
        return table.concat(ids, ":")
    end

    local function addToOffer(list, item)
        if not item then return false end
        item.quantity = item.quantity or 1
        for _, data in ipairs(list) do
            if DUBZ_INVENTORY.CanStack(data, item) then
                data.quantity = (data.quantity or 1) + item.quantity
                return true
            end
        end

        table.insert(list, item)
        return true
    end

    local function removeFromOffer(list, index, amount)
        local data = list[index]
        if not data then return nil end

        local take = math.min(amount or 1, data.quantity or 1)
        data.quantity = (data.quantity or 1) - take

        if data.quantity <= 0 then
            table.remove(list, index)
        end

        data.quantity = take
        return data
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
        if dupe then
            dupe.Pos = nil
            dupe.Angle = nil
            dupe.EntityPos = nil
            dupe.EntityAngle = nil
        end
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

    local function spawnedWeaponData(ent)
        local weaponClass = (ent.GetWeaponClass and ent:GetWeaponClass()) or ent.weaponClass or ent.weaponclass or
            ent:GetNWString("weaponclass", ent:GetNWString("WeaponClass", ""))

        local stored = weaponClass ~= "" and weapons.GetStored(weaponClass)
        local name = (stored and stored.PrintName) or ent.PrintName or weaponClass or "Weapon"
        local model = ent:GetModel() or (stored and stored.WorldModel) or "models/weapons/w_pist_deagle.mdl"

        local clip1 = ent.clip1 or (ent.GetNWInt and ent:GetNWInt("clip1")) or ent.clip1 or 0
        local clip2 = ent.clip2 or (ent.GetNWInt and ent:GetNWInt("clip2")) or ent.clip2 or 0
        local ammoAdd = ent.ammoadd or (ent.GetNWInt and ent:GetNWInt("ammoadd"))

        return {
            class = ent:GetClass(),
            weaponClass = weaponClass ~= "" and weaponClass or nil,
            name = name,
            model = model,
            quantity = 1,
            itemType = "weapon",
            clip1 = clip1,
            clip2 = clip2,
            ammoAdd = ammoAdd
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
            DUBZ_INVENTORY.SendTip(ply, "Aim at a weapon or whitelisted item to pick it up")
            return
        end

        if ent:IsPlayer() or ent:IsNPC() then
            DUBZ_INVENTORY.SendTip(ply, "You can't store that")
            return
        end

        if isPocketBlacklisted(ent:GetClass()) then
            DUBZ_INVENTORY.SendTip(ply, "This item is pocket blacklisted")
            return
        end

        local item
        if ent:GetClass() == "spawned_weapon" then
            item = spawnedWeaponData(ent)
            if not item.weaponClass then
                DUBZ_INVENTORY.SendTip(ply, "This weapon has no class data")
                return
            end
        elseif ent:IsWeapon() then
            if ent:GetOwner() == ply then
                DUBZ_INVENTORY.SendTip(ply, "Drop the weapon first")
                return
            end
            item = weaponData(ent)
        elseif next(config.PocketWhitelist) == nil or config.PocketWhitelist[ent:GetClass()] then
            item = entityData(ent)
        else
            DUBZ_INVENTORY.SendTip(ply, "Item is not allowed in this inventory")
            return
        end

        if not DUBZ_INVENTORY.AddItem(swep, item) then
            DUBZ_INVENTORY.SendTip(ply, "Inventory is full")
            return
        end

        ent:Remove()
        DUBZ_INVENTORY.SendTip(ply, string.format("Stored %s", item.name))
    end

    local function validModelPath(path)
        return path and path ~= "" and util.IsValidModel(path)
    end

    local function resolveSpawnModel(data)
        if validModelPath(data.model) then
            return data.model
        end

        if data.weaponClass then
            local stored = weapons.GetStored(data.weaponClass)
            if stored and validModelPath(stored.WorldModel) then
                return stored.WorldModel
            end
        end

        return "models/weapons/w_pist_deagle.mdl"
    end

    local function spawnWorldItem(ply, data)
        if not (IsValid(ply) and data and data.class) then return false end

        local eyePos = ply:EyePos()
        local eyeAng = ply:EyeAngles()
        local tr = util.TraceLine({
            start = eyePos,
            endpos = eyePos + eyeAng:Forward() * 85,
            filter = ply
        })

        local pos = tr.HitPos + tr.HitNormal * 8
        if not tr.Hit then
            pos = eyePos + eyeAng:Forward() * 30
        end

        local ang = Angle(0, eyeAng.yaw, 0)
        local ent = ents.Create(data.class)

        if not IsValid(ent) then return false end

        if data.class == "spawned_weapon" then
            if not data.weaponClass then return false end

            if ent.SetWeaponClass then
                ent:SetWeaponClass(data.weaponClass)
            else
                ent.weaponClass = data.weaponClass
                ent.weaponclass = data.weaponClass
            end

            ent:SetNWString("weaponclass", data.weaponClass)
            ent:SetNWString("WeaponClass", data.weaponClass)

            ent:SetModel(resolveSpawnModel(data))
            
            ent.clip1 = data.clip1
            ent.clip2 = data.clip2
            ent.ammoadd = data.ammoAdd
            ent:SetNWInt("clip1", data.clip1 or 0)
            ent:SetNWInt("clip2", data.clip2 or 0)
            if data.ammoAdd then
                ent:SetNWInt("ammoadd", data.ammoAdd)
            end
        end

        ent:SetPos(pos)
        ent:SetAngles(ang)
        ent:Spawn()
        ent:Activate()

        if data.itemType == "weapon" and ent:IsWeapon() then
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

        if data.entState and data.entState.mods and duplicator and duplicator.ApplyEntityModifier then
            for mod, info in pairs(data.entState.mods) do
                duplicator.ApplyEntityModifier(ply, ent, mod, info)
            end
        end

        local phys = ent:GetPhysicsObject()
        if not IsValid(phys) then
            ent:PhysicsInit(SOLID_VPHYSICS)
            ent:SetMoveType(MOVETYPE_VPHYSICS)
            ent:SetSolid(SOLID_VPHYSICS)
            phys = ent:GetPhysicsObject()
        end

        if IsValid(phys) then
            phys:Wake()
        end

        return IsValid(ent)
    end

    local function writeNetItem(data)
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

    local function dropBackpack(ply, swep)
        if not (IsValid(ply) and IsValid(swep)) then return end

        local eyePos = ply:EyePos()
        local eyeAng = ply:EyeAngles()
        local tr = util.TraceLine({
            start = eyePos,
            endpos = eyePos + eyeAng:Forward() * 85,
            filter = ply
        })

        local pos = tr.HitPos + tr.HitNormal * 8
        if not tr.Hit then
            pos = eyePos + eyeAng:Forward() * 30
        end

        local bag = ents.Create("dubz_inventory_bag")
        if not IsValid(bag) then
            DUBZ_INVENTORY.SendTip(ply, "Couldn't drop the backpack")
            return
        end

        bag:SetPos(pos)
        bag:SetAngles(Angle(0, eyeAng.yaw, 0))
        bag.StoredItems = table.Copy(cleanItems(swep))
        bag:Spawn()
        bag:Activate()

        local phys = bag:GetPhysicsObject()
        if IsValid(phys) then
            phys:Wake()
        end

        swep.StoredItems = {}
        ply:StripWeapon("dubz_inventory")

        DUBZ_INVENTORY.SendTip(ply, "Dropped your backpack")
    end

    function SWEP:PrimaryAttack()
        self:SetNextPrimaryFire(CurTime() + 0.25)
        DUBZ_INVENTORY.SendTip(self:GetOwner(), "Drop the backpack with right click; press E on it to open.")
    end

    function SWEP:SecondaryAttack()
        self:SetNextSecondaryFire(CurTime() + 0.25)
        dropBackpack(self:GetOwner(), self)
    end

    function SWEP:Reload()
        self:SetNextPrimaryFire(CurTime() + 0.25)
        self:SetNextSecondaryFire(CurTime() + 0.25)
    end

    function DUBZ_INVENTORY.OpenFor(ply, swep)
        if not verifySwep(ply, swep) then return end

        local items = cleanItems(swep)

        net.Start("DubzInventory_Open")
        net.WriteEntity(swep)
        net.WriteUInt(#items, 8)
        for _, data in ipairs(items) do
            writeNetItem(data)
        end
        net.Send(ply)
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
                local giveClass = removed.weaponClass or removed.class
                local given = giveClass and ply:Give(giveClass)
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
                    if removed.ammoAdd and given:GetPrimaryAmmoType() >= 0 then
                        ply:GiveAmmo(removed.ammoAdd, given:GetPrimaryAmmoType())
                    end
                    DUBZ_INVENTORY.SendTip(ply, "Equipped " .. removed.name)
                end
            else
                if spawnWorldItem(ply, removed) then
                    DUBZ_INVENTORY.SendTip(ply, "Spawned " .. removed.name)
                end
            end
        elseif action == "drop" then
            local removed = DUBZ_INVENTORY.RemoveItem(swep, index, math.max(amount, 1))
            if not removed then return end

            local dropCount = math.max(removed.quantity or 0, 0)
            if dropCount <= 0 then return end

            removed.quantity = 1
            local spawned = 0
            for _ = 1, dropCount do
                if spawnWorldItem(ply, removed) then
                    spawned = spawned + 1
                else
                    break
                end
            end

            local remaining = dropCount - spawned
            if remaining > 0 then
                removed.quantity = remaining
                DUBZ_INVENTORY.AddItem(swep, removed)
            end

            DUBZ_INVENTORY.SendTip(ply, string.format("Dropped %s", removed.name or "item"))
        elseif action == "destroy" then
            DUBZ_INVENTORY.RemoveItem(swep, index, math.max(amount, 1))
            DUBZ_INVENTORY.SendTip(ply, "Destroyed item")
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
                DUBZ_INVENTORY.SendTip(ply, "Split stack")
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
            DUBZ_INVENTORY.SendTip(ply, "Could not move item")
        else
            DUBZ_INVENTORY.OpenFor(ply, src)
            if dst ~= src then
                DUBZ_INVENTORY.OpenFor(ply, dst)
            end
        end
    end)

    local function playerInventory(ply)
        if not IsValid(ply) then return nil end
        local swep = ply:GetWeapon("dubz_inventory")
        if verifySwep(ply, swep) then return swep end
        return nil
    end

    local function sendTradeInvite(target, requester)
        net.Start("DubzInventory_TradeInvite")
        net.WriteEntity(requester)
        net.Send(target)
    end

    local function sendTradeStart(trade)
        for _, ply in ipairs(trade.players) do
            local partner = ply == trade.players[1] and trade.players[2] or trade.players[1]
            net.Start("DubzInventory_TradeStart")
            net.WriteString(trade.id)
            net.WriteEntity(partner)
            net.Send(ply)
        end
    end

    local function sendTradeSync(trade)
        if not trade then return end

        for _, ply in ipairs(trade.players) do
            local partner = ply == trade.players[1] and trade.players[2] or trade.players[1]
            net.Start("DubzInventory_TradeSync")
            net.WriteString(trade.id)
            net.WriteEntity(partner)
            net.WriteBool(trade.ready[ply] or false)
            net.WriteBool(trade.ready[partner] or false)

            local myOffer = trade.offers[ply] or {}
            net.WriteUInt(#myOffer, 8)
            for _, data in ipairs(myOffer) do
                writeNetItem(data)
            end

            local partnerOffer = trade.offers[partner] or {}
            net.WriteUInt(#partnerOffer, 8)
            for _, data in ipairs(partnerOffer) do
                writeNetItem(data)
            end

            net.Send(ply)
        end
    end

    local function returnTradeItems(trade)
        if not trade then return end

        for _, ply in ipairs(trade.players) do
            local swep = playerInventory(ply)
            local offer = trade.offers[ply] or {}

            for _, data in ipairs(offer) do
                local copy = table.Copy(data)
                if swep then
                    if not DUBZ_INVENTORY.AddItem(swep, copy) then
                        spawnWorldItem(ply, copy)
                    end
                else
                    spawnWorldItem(ply, copy)
                end
            end
        end
    end

    local function endTrade(trade, reason)
        if not trade then return end
        ActiveTrades[trade.id] = nil

        returnTradeItems(trade)

        for _, ply in ipairs(trade.players) do
            net.Start("DubzInventory_TradeEnd")
            net.WriteString(trade.id)
            net.WriteString(reason or "")
            net.Send(ply)
        end
    end

    local function finishTrade(trade)
        local a, b = trade.players[1], trade.players[2]
        if not (IsValid(a) and IsValid(b)) then returnTradeItems(trade) end

        local swepA = playerInventory(a)
        local swepB = playerInventory(b)

        if not (swepA and swepB) then
            endTrade(trade, "Trade canceled (missing inventory)")
            return
        end

        for _, data in ipairs(trade.offers[a] or {}) do
            local copy = table.Copy(data)
            if not DUBZ_INVENTORY.AddItem(swepB, copy) then
                spawnWorldItem(b, copy)
            end
        end

        for _, data in ipairs(trade.offers[b] or {}) do
            local copy = table.Copy(data)
            if not DUBZ_INVENTORY.AddItem(swepA, copy) then
                spawnWorldItem(a, copy)
            end
        end

        DUBZ_INVENTORY.OpenFor(a, swepA)
        DUBZ_INVENTORY.OpenFor(b, swepB)

        ActiveTrades[trade.id] = nil

        for _, ply in ipairs(trade.players) do
            net.Start("DubzInventory_TradeEnd")
            net.WriteString(trade.id)
            net.WriteString("Trade complete")
            net.Send(ply)
        end
    end

    local function createTrade(ply, target)
        local id = tradeKey(ply, target)
        if not id then return end

        ActiveTrades[id] = {
            id = id,
            players = {ply, target},
            offers = {[ply] = {}, [target] = {}},
            ready = {[ply] = false, [target] = false}
        }

        sendTradeStart(ActiveTrades[id])
        sendTradeSync(ActiveTrades[id])

        local swepA = playerInventory(ply)
        local swepB = playerInventory(target)
        if swepA then DUBZ_INVENTORY.OpenFor(ply, swepA) end
        if swepB then DUBZ_INVENTORY.OpenFor(target, swepB) end
    end

    local function requestTrade(ply)
        if not IsValid(ply) then return end
        local tr = ply:GetEyeTrace()
        local target = tr.Entity

        if not (IsValid(target) and target:IsPlayer()) then
            DUBZ_INVENTORY.SendTip(ply, "Look at a player to trade")
            return
        end

        if target == ply then
            DUBZ_INVENTORY.SendTip(ply, "You can't trade with yourself")
            return
        end

        local id = tradeKey(ply, target)
        if ActiveTrades[id] then
            DUBZ_INVENTORY.SendTip(ply, "You are already trading with this player")
            return
        end

        if PendingInvites[target] and PendingInvites[target] == ply then
            DUBZ_INVENTORY.SendTip(ply, "Trade request already pending")
            return
        end

        PendingInvites[target] = ply
        sendTradeInvite(target, ply)
        DUBZ_INVENTORY.SendTip(ply, "Trade request sent")
    end

    concommand.Add("trade", function(ply)
        if not IsValid(ply) then return end
        requestTrade(ply)
    end)

    hook.Add("PlayerSay", "DubzInventoryTradeChat", function(ply, text)
        if string.lower(string.Trim(text)) == "trade" then
            requestTrade(ply)
            return ""
        end
    end)

    net.Receive("DubzInventory_TradeReply", function(_, ply)
        local requester = net.ReadEntity()
        local accepted = net.ReadBool()

        if not IsValid(requester) or PendingInvites[ply] ~= requester then return end

        PendingInvites[ply] = nil

        if not accepted then
            DUBZ_INVENTORY.SendTip(requester, "Trade declined")
            return
        end

        local id = tradeKey(ply, requester)
        if ActiveTrades[id] then return end

        if not (playerInventory(ply) and playerInventory(requester)) then
            DUBZ_INVENTORY.SendTip(ply, "Both players need the inventory equipped")
            DUBZ_INVENTORY.SendTip(requester, "Both players need the inventory equipped")
            return
        end

        createTrade(ply, requester)
    end)

    net.Receive("DubzInventory_TradeAction", function(_, ply)
        local id = net.ReadString()
        local action = net.ReadString()
        local trade = ActiveTrades[id]

        if not trade then return end
        if ply ~= trade.players[1] and ply ~= trade.players[2] then return end

        local partner = ply == trade.players[1] and trade.players[2] or trade.players[1]
        local myOffer = trade.offers[ply]

        if action == "offer" then
            local invIndex = net.ReadUInt(8)
            local amount = net.ReadUInt(16)
            local swep = playerInventory(ply)
            if not swep then return end

            local removed = DUBZ_INVENTORY.RemoveItem(swep, invIndex, math.max(amount, 1))
            if not removed then return end

            removed.quantity = math.max(amount, 1)
            addToOffer(myOffer, removed)
            trade.ready[ply] = false
            trade.ready[partner] = false
            DUBZ_INVENTORY.OpenFor(ply, swep)
            sendTradeSync(trade)
        elseif action == "retrieve" then
            local offerIndex = net.ReadUInt(8)
            local amount = net.ReadUInt(16)
            local swep = playerInventory(ply)
            if not swep then return end

            local removed = removeFromOffer(myOffer, offerIndex, math.max(amount, 1))
            if not removed then return end

            trade.ready[ply] = false
            trade.ready[partner] = false

            if not DUBZ_INVENTORY.AddItem(swep, removed) then
                spawnWorldItem(ply, removed)
            end

            DUBZ_INVENTORY.OpenFor(ply, swep)
            sendTradeSync(trade)
        elseif action == "ready" then
            local readyState = net.ReadBool()
            trade.ready[ply] = readyState
            sendTradeSync(trade)

            if readyState and trade.ready[partner] then
                finishTrade(trade)
            end
        elseif action == "cancel" then
            endTrade(trade, "Trade canceled")
        end
    end)

    hook.Add("PlayerDisconnected", "DubzInventoryTradeCleanup", function(ply)
        for id, trade in pairs(ActiveTrades) do
            if trade.players[1] == ply or trade.players[2] == ply then
                endTrade(trade, "Trade canceled (player left)")
            end
        end

        PendingInvites[ply] = nil
    end)
end


if CLIENT then
    local bg = config.ColorBackground or Color(0, 0, 0, 190)
    local panelCol = config.ColorPanel or Color(24, 28, 38)
    local accent = config.ColorAccent or Color(25, 178, 208)
    local textColor = config.ColorText or Color(230, 234, 242)
    local tileW, tileH, tileSpacing = 92, 110, 8
    local framePad, headerH = 12, 46

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
        draw.RoundedBox(10, 0, 0, w, h, panelCol)
        surface.SetDrawColor(accent)
        surface.DrawRect(0, 0, w, 2)
    end

    local function readNetItem()
        local item = {
            class = net.ReadString(),
            name = net.ReadString(),
            model = net.ReadString(),
            quantity = net.ReadUInt(16),
            itemType = net.ReadString(),
            material = net.ReadString()
        }

        local subMaterials = {}
        local subCount = net.ReadUInt(5)
        for _ = 1, subCount do
            local idx = net.ReadUInt(5)
            subMaterials[idx] = net.ReadString()
        end

        if not table.IsEmpty(subMaterials) then
            item.subMaterials = subMaterials
        end

        return item
    end

    local function applyIconMaterials(icon, data)
        if not (data and (data.material or data.subMaterials)) then return end

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

    local function sendAction(swep, index, action, amount)
        net.Start("DubzInventory_Action")
        net.WriteEntity(swep)
        net.WriteUInt(index, 8)
        net.WriteString(action)
        net.WriteUInt(amount or 1, 16)
        net.SendToServer()
    end

    local function createItemTile(layout, data, swep, index, payload)
        local panel = layout:Add("DPanel")
        panel:SetSize(tileW, tileH)
        panel.DragPayload = payload
        panel:Droppable("DubzInvItem")
        panel.Paint = function(self, w, h)
            draw.RoundedBox(8, 0, 0, w, h, bg)
            draw.SimpleText(data.name, "DubzInv_Small", w / 2, h - 20, textColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText("x" .. (data.quantity or 1), "DubzInv_Small", w / 2, h - 7, ColorAlpha(textColor, 170),
                TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end

        local icon = vgui.Create("SpawnIcon", panel)
        icon:SetModel(data.model ~= "" and data.model or "models/props_junk/PopCan01a.mdl")
        icon:SetPos(6, 6)
        icon:SetSize(tileW - 12, tileW - 12)
        icon:SetTooltip(nil)
        icon.PaintOver = function(_, w, h)
            surface.SetDrawColor(accent)
            surface.DrawOutlinedRect(0, 0, w, h, 1)
        end

        applyIconMaterials(icon, data)

        panel.OnMousePressed = function(self, mc)
            if mc == MOUSE_LEFT then
                self:DragMousePress(mc)
            end
        end

        panel.OnMouseReleased = function(self, mc)
            if mc == MOUSE_LEFT then
                self:DragMouseRelease(mc)
            end
        end

        if swep and index then
            icon.DoClick = function()
                sendAction(swep, index, "use", 1)
            end

            icon.DoRightClick = function()
                local menu = DermaMenu()
                if data.itemType == "weapon" then
                    menu:AddOption("Equip", function()
                        sendAction(swep, index, "use", 1)
                    end):SetIcon("icon16/gun.png")
                end

                menu:AddOption("Drop", function()
                    Derma_StringRequest("Drop amount", "How many do you want to drop?", tostring(data.quantity or 1), function(text)
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
        end

        return panel
    end

    local inventoryFrames = {}
    local inventoryData = {}

    local tradeState = {
        id = nil,
        partner = nil,
        frame = nil,
        myReady = false,
        partnerReady = false,
        myOffer = {},
        partnerOffer = {},
        swep = nil
    }

    local function sendTradeAction(action, a, b)
        if not tradeState.id then return end
        net.Start("DubzInventory_TradeAction")
        net.WriteString(tradeState.id)
        net.WriteString(action)

        if action == "offer" or action == "retrieve" then
            net.WriteUInt(a or 0, 8)
            net.WriteUInt(b or 1, 16)
        elseif action == "ready" then
            net.WriteBool(a)
        end

        net.SendToServer()
    end

    local function buildGrid(parent, opts)
        opts = opts or {}
        local grid = vgui.Create("DIconLayout", parent)
        grid:SetSpaceX(opts.spaceX or tileSpacing)
        grid:SetSpaceY(opts.spaceY or tileSpacing)

        if opts.noDock then
            grid:SetSize(opts.w or parent:GetWide(), opts.h or parent:GetTall())
            grid:SetPos(opts.x or 0, opts.y or 0)
        else
            grid:Dock(FILL)
            grid:DockMargin(opts.margin or 10, opts.top or 36, opts.margin or 10, opts.bottom or 10)
        end

        return grid
    end

    local function inventoryGridMetrics()
        local capacity = math.max(config.Capacity or 10, 1)
        local availableWidth = ScrW() - 80 - (framePad * 2)
        local maxCols = math.max(3, math.floor((availableWidth + tileSpacing) / (tileW + tileSpacing)))
        local cols = math.Clamp(capacity, 1, maxCols)
        local rows = math.max(1, math.ceil(capacity / cols))
        local gridW = cols * tileW + (cols - 1) * tileSpacing
        local gridH = rows * tileH + (rows - 1) * tileSpacing

        return cols, rows, gridW, gridH
    end

    local function refreshInventoryFrame(swep)
        local frame = inventoryFrames[swep]
        if not IsValid(frame) then return end
        local items = inventoryData[swep] or {}
        frame.ItemLabel:SetText(string.format("%d / %d slots", #items, config.Capacity))
        frame.Grid:Clear()

        frame.Grid:Receiver("DubzInvItem", function(_, panels, dropped)
            if not dropped then return end
            local payload = panels[1] and panels[1].DragPayload
            if not payload or not tradeState.id then return end
            if payload.type == "offer" and payload.owner == LocalPlayer() then
                local maxAmt = payload.data.quantity or 1
                Derma_StringRequest("Retrieve", "Take how many back?", tostring(maxAmt), function(text)
                    local amt = math.Clamp(tonumber(text) or 1, 1, maxAmt)
                    sendTradeAction("retrieve", payload.index, amt)
                end)
            end
        end)

        for idx, data in ipairs(items) do
            local payload = {type = "inventory", swep = swep, index = idx, data = data}
            createItemTile(frame.Grid, data, swep, idx, payload)
        end
    end

    local function ensureInventoryFrame(swep)
        if IsValid(inventoryFrames[swep]) then return inventoryFrames[swep] end

        local cols, rows, gridW, gridH = inventoryGridMetrics()
        local frameW = gridW + framePad * 2
        local frameH = headerH + gridH + framePad * 2

        local frame = vgui.Create("DFrame")
        frame:SetSize(frameW, frameH)
        frame:SetTitle("")
        frame:ShowCloseButton(false)
        frame:SetDraggable(false)
        frame:MakePopup()
        frame:SetPos((ScrW() - frame:GetWide()) / 2, ScrH() - frame:GetTall() - 10)
        frame.Paint = function(self, w, h)
            draw.RoundedBox(12, 0, 0, w, h, bg)
            surface.SetDrawColor(accent)
            surface.DrawRect(0, 0, w, 3)

            draw.RoundedBox(10, framePad, framePad, w - framePad * 2, headerH - 10, ColorAlpha(panelCol, 220))
            draw.SimpleText("Inventory", "DubzInv_Title", framePad + 8, framePad + 6, textColor, TEXT_ALIGN_LEFT,
                TEXT_ALIGN_TOP)
        end

        local close = vgui.Create("DButton", frame)
        close:SetText("✕")
        close:SetFont("DubzInv_Button")
        close:SetTextColor(textColor)
        close:SetSize(32, 24)
        close:SetPos(frame:GetWide() - framePad - 32, framePad + 6)
        close.Paint = function(self, w, h)
            draw.RoundedBox(6, 0, 0, w, h, panelCol)
        end
        close.DoClick = function()
            frame:Close()
        end

        frame.OnClose = function()
            inventoryFrames[swep] = nil
        end

        local info = vgui.Create("DLabel", frame)
        info:SetPos(framePad + 8, framePad + 24)
        info:SetSize(frame:GetWide() - framePad * 2, 16)
        info:SetTextColor(ColorAlpha(textColor, 160))
        info:SetFont("DubzInv_Small")
        info:SetText("Left click items on ground to store. Secondary drops last. R opens this panel.")

        local label = vgui.Create("DLabel", frame)
        label:SetPos(frame:GetWide() - framePad - 200, framePad + 24)
        label:SetSize(180, 16)
        label:SetTextColor(ColorAlpha(textColor, 200))
        label:SetFont("DubzInv_Small")
        label:SetText("")
        frame.ItemLabel = label

        local gridWrap = vgui.Create("DPanel", frame)
        gridWrap:SetSize(gridW, gridH)
        gridWrap:SetPos((frame:GetWide() - gridW) / 2, framePad + headerH)
        gridWrap.Paint = function(_, w, h)
            draw.RoundedBox(12, 0, 0, w, h, ColorAlpha(panelCol, 230))
            surface.SetDrawColor(ColorAlpha(accent, 60))
            surface.DrawOutlinedRect(0, 0, w, h, 1)

            for r = 0, rows - 1 do
                for c = 0, cols - 1 do
                    local x = c * (tileW + tileSpacing)
                    local y = r * (tileH + tileSpacing)
                    draw.RoundedBox(6, x, y, tileW, tileH, Color(0, 0, 0, 120))
                    surface.SetDrawColor(ColorAlpha(accent, 30))
                    surface.DrawOutlinedRect(x, y, tileW, tileH, 1)
                end
            end
        end

        local grid = buildGrid(gridWrap, {noDock = true, w = gridW, h = gridH, spaceX = tileSpacing, spaceY = tileSpacing})
        frame.Grid = grid

        inventoryFrames[swep] = frame
        return frame
    end

    local function refreshTradeFrame()
        local frame = tradeState.frame
        if not IsValid(frame) then return end

        frame.MyReady:SetText(tradeState.myReady and "Ready" or "Not ready")
        frame.PartnerReady:SetText(tradeState.partnerReady and "Partner ready" or "Partner not ready")
        frame.MyReady:SetTextColor(tradeState.myReady and Color(100, 255, 140) or textColor)
        frame.PartnerReady:SetTextColor(tradeState.partnerReady and Color(100, 255, 140) or textColor)

        frame.MyOffer:Clear()
        frame.MyOffer:Receiver("DubzInvItem", function(_, panels, dropped)
            if not dropped then return end
            local payload = panels[1] and panels[1].DragPayload
            if not payload or payload.type ~= "inventory" then return end
            local maxAmt = payload.data.quantity or 1
            Derma_StringRequest("Offer", "How many do you want to offer?", tostring(maxAmt), function(text)
                local amt = math.Clamp(tonumber(text) or 1, 1, maxAmt)
                sendTradeAction("offer", payload.index, amt)
            end)
        end)

        for idx, data in ipairs(tradeState.myOffer or {}) do
            local payload = {type = "offer", owner = LocalPlayer(), index = idx, data = data}
            createItemTile(frame.MyOffer, data, nil, nil, payload)
        end

        frame.PartnerOffer:Clear()
        for _, data in ipairs(tradeState.partnerOffer or {}) do
            createItemTile(frame.PartnerOffer, data)
        end

        if tradeState.swep then
            refreshInventoryFrame(tradeState.swep)
        end
    end

    local function openTradeFrame(partner)
        if IsValid(tradeState.frame) then
            tradeState.frame:Close()
        end

        local frame = vgui.Create("DFrame")
        frame:SetSize(940, 420)
        frame:Center()
        frame:SetTitle("")
        frame:ShowCloseButton(false)
        frame:MakePopup()
        frame.Paint = function(self, w, h)
            draw.RoundedBox(12, 0, 0, w, h, bg)
            surface.SetDrawColor(accent)
            surface.DrawRect(0, 0, w, 3)
            draw.SimpleText("Trading with " .. (IsValid(partner) and partner:Nick() or "player"), "DubzInv_Title", 14, 10,
                textColor)
        end

        local close = vgui.Create("DButton", frame)
        close:SetText("✕")
        close:SetFont("DubzInv_Button")
        close:SetTextColor(textColor)
        close:SetSize(32, 22)
        close:SetPos(frame:GetWide() - 40, 8)
        close.Paint = function(self, w, h)
            draw.RoundedBox(6, 0, 0, w, h, panelCol)
        end
        close.DoClick = function()
            sendTradeAction("cancel")
            frame:Close()
        end

        local offers = vgui.Create("DPanel", frame)
        offers:Dock(TOP)
        offers:SetTall(200)
        offers:DockMargin(10, 40, 10, 10)
        offers.Paint = function(self, w, h)
            drawPanelOutline(w, h)
            draw.SimpleText("Your offer", "DubzInv_Button", 16, 8, textColor)
            draw.SimpleText("Their offer", "DubzInv_Button", w / 2 + 16, 8, textColor)
        end

        local left = vgui.Create("DPanel", offers)
        left:Dock(LEFT)
        left:SetWide(offers:GetWide() / 2)
        left:DockMargin(8, 28, 4, 8)
        left.Paint = nil

        local right = vgui.Create("DPanel", offers)
        right:Dock(FILL)
        right:DockMargin(4, 28, 8, 8)
        right.Paint = nil

        local myOffer = buildGrid(left)
        local partnerOffer = buildGrid(right)

        frame.MyOffer = myOffer
        frame.PartnerOffer = partnerOffer

        local status = vgui.Create("DPanel", frame)
        status:Dock(TOP)
        status:SetTall(50)
        status:DockMargin(10, 0, 10, 0)
        status.Paint = nil

        local myReady = vgui.Create("DLabel", status)
        myReady:SetFont("DubzInv_Button")
        myReady:SetTextColor(textColor)
        myReady:SetPos(10, 10)
        myReady:SetSize(200, 24)
        myReady:SetText("Not ready")
        frame.MyReady = myReady

        local partnerReady = vgui.Create("DLabel", status)
        partnerReady:SetFont("DubzInv_Button")
        partnerReady:SetTextColor(textColor)
        partnerReady:SetPos(220, 10)
        partnerReady:SetSize(220, 24)
        partnerReady:SetText("Partner not ready")
        frame.PartnerReady = partnerReady

        local toggleReady = vgui.Create("DButton", status)
        toggleReady:SetSize(140, 30)
        toggleReady:SetPos(frame:GetWide() - 160, 10)
        toggleReady:SetText("Toggle ready")
        toggleReady:SetFont("DubzInv_Button")
        toggleReady:SetTextColor(textColor)
        toggleReady.Paint = function(self, w, h)
            draw.RoundedBox(8, 0, 0, w, h, panelCol)
        end
        toggleReady.DoClick = function()
            sendTradeAction("ready", not tradeState.myReady)
        end

        local invWrap = vgui.Create("DPanel", frame)
        invWrap:Dock(FILL)
        invWrap:DockMargin(10, 6, 10, 10)
        invWrap.Paint = function(self, w, h)
            drawPanelOutline(w, h)
            draw.SimpleText("Your inventory", "DubzInv_Button", 12, 8, textColor)
        end

        local invGrid = buildGrid(invWrap)
        invGrid:Receiver("DubzInvItem", function(_, panels, dropped)
            if not dropped then return end
            local payload = panels[1] and panels[1].DragPayload
            if not payload or payload.type ~= "offer" then return end
            if payload.owner ~= LocalPlayer() then return end
            local maxAmt = payload.data.quantity or 1
            Derma_StringRequest("Retrieve", "Take how many back?", tostring(maxAmt), function(text)
                local amt = math.Clamp(tonumber(text) or 1, 1, maxAmt)
                sendTradeAction("retrieve", payload.index, amt)
            end)
        end)

        frame.InventoryGrid = invGrid

        frame.OnClose = function()
            if tradeState.id then
                sendTradeAction("cancel")
            end
            tradeState.frame = nil
            tradeState.id = nil
            tradeState.partner = nil
            tradeState.myOffer = {}
            tradeState.partnerOffer = {}
            tradeState.myReady = false
            tradeState.partnerReady = false
            tradeState.swep = nil
        end

        tradeState.frame = frame
        refreshTradeFrame()
    end

    local function refreshTradeInventory()
        if not (tradeState.swep and IsValid(tradeState.frame) and IsValid(tradeState.frame.InventoryGrid)) then return end
        local items = inventoryData[tradeState.swep] or {}
        local grid = tradeState.frame.InventoryGrid
        grid:Clear()
        for idx, data in ipairs(items) do
            local payload = {type = "inventory", swep = tradeState.swep, index = idx, data = data}
            createItemTile(grid, data, tradeState.swep, idx, payload)
        end
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
            items[i] = readNetItem()
        end

        if not IsValid(swep) then return end

        inventoryData[swep] = items

        local frame = ensureInventoryFrame(swep)
        refreshInventoryFrame(swep)

        if tradeState.swep == swep then
            refreshTradeInventory()
        end
    end)

    net.Receive("DubzInventory_TradeInvite", function()
        local requester = net.ReadEntity()
        if not IsValid(requester) then return end

        Derma_Query(requester:Nick() .. " wants to trade", "Trade Request",
            "Accept", function()
                net.Start("DubzInventory_TradeReply")
                net.WriteEntity(requester)
                net.WriteBool(true)
                net.SendToServer()
            end,
            "Decline", function()
                net.Start("DubzInventory_TradeReply")
                net.WriteEntity(requester)
                net.WriteBool(false)
                net.SendToServer()
            end)
    end)

    net.Receive("DubzInventory_TradeStart", function()
        tradeState.id = net.ReadString()
        tradeState.partner = net.ReadEntity()
        tradeState.swep = LocalPlayer():GetWeapon("dubz_inventory")
        openTradeFrame(tradeState.partner)
        refreshTradeInventory()
    end)

    net.Receive("DubzInventory_TradeSync", function()
        local id = net.ReadString()
        if tradeState.id ~= id then return end

        tradeState.partner = net.ReadEntity()
        tradeState.myReady = net.ReadBool()
        tradeState.partnerReady = net.ReadBool()

        local myCount = net.ReadUInt(8)
        local mine = {}
        for i = 1, myCount do
            mine[i] = readNetItem()
        end

        local theirCount = net.ReadUInt(8)
        local theirs = {}
        for i = 1, theirCount do
            theirs[i] = readNetItem()
        end

        tradeState.myOffer = mine
        tradeState.partnerOffer = theirs
        refreshTradeFrame()
    end)

    net.Receive("DubzInventory_TradeEnd", function()
        local id = net.ReadString()
        local message = net.ReadString()
        if tradeState.id ~= id then return end

        if message ~= "" then
            notification.AddLegacy(message, NOTIFY_GENERIC, 4)
        end

        if IsValid(tradeState.frame) then
            tradeState.frame:Close()
        else
            tradeState.id = nil
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
