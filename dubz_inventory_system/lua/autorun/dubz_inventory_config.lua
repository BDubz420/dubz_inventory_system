DUBZ_BACKPACK = DUBZ_BACKPACK or {}

DUBZ_BACKPACK.Config = {
    Capacity = 8,
    Model = "models/props_c17/BriefCase001a.mdl",
    Price = 2500,
    Command = "buydubzbackpack",
    Category = "Dubz Utilities",
    ColorPrimary = Color(18, 18, 28),
    ColorPanel = Color(28, 28, 40),
    ColorAccent = Color(80, 145, 255),
    ColorMuted = Color(180, 180, 195),

    -- Leave AllowedWeapons / AllowedEntities empty to permit any class.
    AllowedWeapons = {
        -- "stunstick",
        -- "weapon_arrest_stick",
    },

    AllowedEntities = {
        -- "spawned_money",
    }
}

local config = DUBZ_BACKPACK.Config

local function asLookup(tbl)
    local map = {}
    for _, class in ipairs(tbl or {}) do
        map[class] = true
    end
    return map
end

config.AllowedWeaponLookup = asLookup(config.AllowedWeapons)
config.AllowedEntityLookup = asLookup(config.AllowedEntities)

function DUBZ_BACKPACK.IsWeaponAllowed(class)
    if not class or class == "" then return false end
    if not config.AllowedWeapons or #config.AllowedWeapons == 0 then return true end
    return config.AllowedWeaponLookup[class] or false
end

function DUBZ_BACKPACK.IsEntityAllowed(class)
    if not class or class == "" then return false end
    if not config.AllowedEntities or #config.AllowedEntities == 0 then return true end
    return config.AllowedEntityLookup[class] or false
end

if SERVER then
    util.AddNetworkString("DubzBackpack_Open")
    util.AddNetworkString("DubzBackpack_Deposit")
    util.AddNetworkString("DubzBackpack_Withdraw")

    function DUBZ_BACKPACK.GetItems(container)
        if not IsValid(container) then return {} end
        container.StoredItems = container.StoredItems or {}
        return container.StoredItems
    end

    function DUBZ_BACKPACK.SendInventory(ply, container, containerType)
        if not IsValid(ply) or not IsValid(container) then return end
        if container:IsWeapon() then return end
        local items = DUBZ_BACKPACK.GetItems(container)

        net.Start("DubzBackpack_Open")
        net.WriteString(containerType)
        net.WriteEntity(container)
        net.WriteUInt(config.Capacity, 8)
        net.WriteUInt(#items, 8)
        for _, data in ipairs(items) do
            net.WriteString(data.class or "")
            net.WriteString(data.name or data.class or "Unknown Item")
        end
        net.Send(ply)
    end

    local function canInteract(ply, container)
        if not (IsValid(ply) and IsValid(container)) then return false end
        return ply:GetPos():DistToSqr(container:GetPos()) <= (200 * 200)
    end

    local function removeWeapon(ply, class)
        if not IsValid(ply) then return end
        if ply:HasWeapon(class) then
            if IsValid(ply:GetActiveWeapon()) and ply:GetActiveWeapon():GetClass() == class then
                ply:SelectWeapon("keys")
            end
            ply:StripWeapon(class)
        end
    end

    net.Receive("DubzBackpack_Deposit", function(_, ply)
        local containerType = net.ReadString()
        local container = net.ReadEntity()
        local class = net.ReadString()

        if not canInteract(ply, container) then return end
        if class == "" or class == container:GetClass() then return end

        if not DUBZ_BACKPACK.IsWeaponAllowed(class) then
            ply:ChatPrint("You can't store that weapon in this backpack.")
            return
        end

        local items = DUBZ_BACKPACK.GetItems(container)
        if #items >= config.Capacity then
            ply:ChatPrint("This backpack is full!")
            return
        end

        if not ply:HasWeapon(class) then return end

        local wep = ply:GetWeapon(class)
        if not IsValid(wep) then return end

        if container:IsWeapon() then return end

        table.insert(items, {
            class = class,
            name = wep.PrintName or class
        })

        removeWeapon(ply, class)
        DUBZ_BACKPACK.SendInventory(ply, container, containerType)
    end)

    net.Receive("DubzBackpack_Withdraw", function(_, ply)
        local containerType = net.ReadString()
        local container = net.ReadEntity()
        local index = net.ReadUInt(8)

        if not canInteract(ply, container) then return end
        if container:IsWeapon() then return end

        local items = DUBZ_BACKPACK.GetItems(container)
        local data = items[index]
        if not data then return end

        if not ply:Alive() then return end

        local given = ply:Give(data.class)
        if IsValid(given) then
            given.PrintName = data.name
        end

        table.remove(items, index)
        DUBZ_BACKPACK.SendInventory(ply, container, containerType)
    end)

    local pickupRangeSqr = 200 * 200

    hook.Add("KeyPress", "DubzBackpack_PickupSecondary", function(ply, key)
        if key ~= IN_ATTACK2 then return end
        if not IsValid(ply) or ply:HasWeapon("dubz_backpack") then return end

        local tr = util.TraceLine({
            start = ply:EyePos(),
            endpos = ply:EyePos() + ply:GetAimVector() * 90,
            filter = ply
        })

        local ent = tr.Entity
        if not IsValid(ent) or ent:GetClass() ~= "dubz_backpack" then return end
        if ply:GetPos():DistToSqr(ent:GetPos()) > pickupRangeSqr then return end

        if ent.PickupIntoWeapon then
            ent:PickupIntoWeapon(ply)
        end
    end)

    if DarkRP and DarkRP.createEntity then
        DarkRP.createEntity("Dubz Backpack", {
            ent = "dubz_backpack",
            model = config.Model,
            price = config.Price,
            max = 2,
            cmd = config.Command,
            allowed = TEAM_CITIZEN and {TEAM_CITIZEN} or nil,
            category = config.Category
        })
    end
end
