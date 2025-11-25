DubzInventoryConfig = DubzInventoryConfig or {}

DubzInventoryConfig.Accent = DubzInventoryConfig.Accent or Color(52, 152, 255)
DubzInventoryConfig.Capacity = DubzInventoryConfig.Capacity or 12
DubzInventoryConfig.AllowedWeapons = DubzInventoryConfig.AllowedWeapons or {
    "weapon_fists",
    "weapon_crowbar",
    "weapon_pistol",
    "weapon_357"
}
DubzInventoryConfig.AllowedEntities = DubzInventoryConfig.AllowedEntities or {
    "spawned_weapon",
    "spawned_food",
    "spawned_money"
}

local allowedWeaponLookup = {}
local allowedEntityLookup = {}

local function rebuildLookups()
    table.Empty(allowedWeaponLookup)
    table.Empty(allowedEntityLookup)

    for _, class in ipairs(DubzInventoryConfig.AllowedWeapons or {}) do
        allowedWeaponLookup[class] = true
    end

    for _, class in ipairs(DubzInventoryConfig.AllowedEntities or {}) do
        allowedEntityLookup[class] = true
    end
end

rebuildLookups()

if SERVER then
    AddCSLuaFile()
    AddCSLuaFile("autorun/client/dubz_inventory_ui.lua")

    util.AddNetworkString("DubzInventory_Action")
    util.AddNetworkString("DubzInventory_Data")

    local storedItems = {}

    local function getInventory(ply)
        storedItems[ply] = storedItems[ply] or {}
        return storedItems[ply]
    end

    local function notify(ply, msg)
        if not IsValid(ply) then return end
        ply:ChatPrint("[Dubz Inventory] " .. msg)
    end

    local function sendInventory(ply)
        local inventory = table.Copy(getInventory(ply))

        net.Start("DubzInventory_Data")
        net.WriteUInt(math.min(DubzInventoryConfig.Capacity or 0, 254), 8)
        net.WriteTable(inventory)
        net.Send(ply)
    end

    local function addItem(ply, itemType, class)
        if not IsValid(ply) or not class or class == "" then return end

        local inventory = getInventory(ply)
        if #inventory >= (DubzInventoryConfig.Capacity or 0) then
            notify(ply, "Your Dubz inventory is full.")
            return
        end

        inventory[#inventory + 1] = {
            type = itemType,
            class = class
        }

        sendInventory(ply)
    end

    local function removeItem(ply, idx)
        local inventory = getInventory(ply)
        if not inventory[idx] then return end

        table.remove(inventory, idx)
        sendInventory(ply)
    end

    local function storeActiveWeapon(ply)
        local wep = ply:GetActiveWeapon()
        if not IsValid(wep) then
            notify(ply, "You need to hold a weapon to store it.")
            return
        end

        local class = wep:GetClass()
        if class == "dubz_inventory" then
            notify(ply, "You cannot store the inventory SWEP.")
            return
        end

        if not allowedWeaponLookup[class] then
            notify(ply, "That weapon cannot be stored in Dubz inventory.")
            return
        end

        addItem(ply, "weapon", class)
        ply:StripWeapon(class)
        ply:SelectWeapon("dubz_inventory")
    end

    local function storeLookedEntity(ply)
        local trace = ply:GetEyeTrace()
        if not trace or not IsValid(trace.Entity) then
            notify(ply, "Look at an entity to store it.")
            return
        end

        if trace.HitPos:DistToSqr(ply:GetShootPos()) > (140 * 140) then
            notify(ply, "Get closer to store that item.")
            return
        end

        local ent = trace.Entity
        local class = ent:GetClass()

        if ent:IsPlayer() or ent:IsWeapon() then
            notify(ply, "That cannot be stored.")
            return
        end

        if not allowedEntityLookup[class] then
            notify(ply, "That entity is not allowed in Dubz inventory.")
            return
        end

        addItem(ply, "entity", class)
        ent:Remove()
    end

    local function withdrawItem(ply, idx)
        local inventory = getInventory(ply)
        local item = inventory[idx]
        if not item then return end

        if item.type == "weapon" then
            ply:Give(item.class)
            ply:SelectWeapon(item.class)
        elseif item.type == "entity" then
            local spawnPos = ply:GetShootPos() + ply:GetAimVector() * 40
            local ent = ents.Create(item.class)
            if not IsValid(ent) then
                notify(ply, "Failed to spawn stored entity (" .. item.class .. ").")
                return
            end

            ent:SetPos(spawnPos)
            ent:Spawn()
            ent:Activate()
        end

        removeItem(ply, idx)
    end

    net.Receive("DubzInventory_Action", function(_, ply)
        if not IsValid(ply) then return end

        local action = net.ReadString()

        if action == "open" then
            sendInventory(ply)
            return
        elseif action == "store_weapon" then
            storeActiveWeapon(ply)
        elseif action == "store_entity" then
            storeLookedEntity(ply)
        elseif action == "withdraw" then
            local idx = net.ReadUInt(8)
            withdrawItem(ply, idx)
        end
    end)

    hook.Add("PlayerDisconnected", "DubzInventory_Clear", function(ply)
        storedItems[ply] = nil
    end)
else
    -- Client helper to request actions.
    function DubzInventoryRequest(action, data)
        net.Start("DubzInventory_Action")
        net.WriteString(action)

        if action == "withdraw" then
            net.WriteUInt(data or 0, 8)
        end

        net.SendToServer()
    end
end
