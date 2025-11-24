DUBZ_BACKPACK = DUBZ_BACKPACK or {}

DUBZ_BACKPACK.Config = {
    Capacity = 8,
    Model = "models/props_c17/BriefCase001a.mdl",
    Price = 2500,
    Command = "buydubzbackpack",
    Category = "Dubz Utilities",
    ColorPrimary = Color(18, 18, 28),
    ColorPanel = Color(28, 28, 40),
    ColorAccent = Color(140, 90, 255),
    ColorMuted = Color(180, 180, 195)
}

local config = DUBZ_BACKPACK.Config

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
        if container:IsWeapon() then
            return container:GetOwner() == ply
        end
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

        local items = DUBZ_BACKPACK.GetItems(container)
        if #items >= config.Capacity then
            ply:ChatPrint("This backpack is full!")
            return
        end

        if not ply:HasWeapon(class) then return end

        local wep = ply:GetWeapon(class)
        if not IsValid(wep) then return end

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
