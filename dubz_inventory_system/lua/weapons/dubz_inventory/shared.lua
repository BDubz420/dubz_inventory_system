AddCSLuaFile()

DUBZ_INVENTORY = DUBZ_INVENTORY or {}

SWEP.PrintName = "Dubz Inventory"
SWEP.Author = "BDubz"
SWEP.Instructions = "Primary/Secondary: Open inventory menu"
SWEP.Category = (DUBZ_INVENTORY and DUBZ_INVENTORY.Config.Category) or "Dubz Utilities"
SWEP.Spawnable = true
SWEP.AdminOnly = false

SWEP.ViewModel = "models/weapons/c_arms_citizen.mdl"
SWEP.WorldModel = "models/weapons/w_toolgun.mdl"
SWEP.UseHands = true
SWEP.ViewModelFOV = 62
SWEP.DrawCrosshair = false

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
    ColorBackground = Color(14, 16, 24),
    ColorPanel = Color(24, 28, 38),
    ColorAccent = Color(25, 178, 208),
    ColorText = Color(230, 234, 242)
}

if SERVER then
    util.AddNetworkString("DubzInventory_Open")
    util.AddNetworkString("DubzInventory_Deposit")
    util.AddNetworkString("DubzInventory_Withdraw")

    function SWEP:Initialize()
        self:SetHoldType("slam")
        self.StoredItems = {}
    end

    local function cleanItems(swep)
        if not IsValid(swep) then return {} end
        swep.StoredItems = swep.StoredItems or {}
        return swep.StoredItems
    end

    function SWEP:PrimaryAttack()
        self:SetNextPrimaryFire(CurTime() + 0.25)
        DUBZ_INVENTORY.OpenFor(self:GetOwner(), self)
    end

    function SWEP:SecondaryAttack()
        self:SetNextSecondaryFire(CurTime() + 0.25)
        DUBZ_INVENTORY.OpenFor(self:GetOwner(), self)
    end

    function DUBZ_INVENTORY.OpenFor(ply, swep)
        if not (IsValid(ply) and IsValid(swep)) then return end
        if swep:GetOwner() ~= ply then return end

        local items = cleanItems(swep)

        net.Start("DubzInventory_Open")
        net.WriteEntity(swep)
        net.WriteUInt(#items, 8)
        for _, data in ipairs(items) do
            net.WriteString(data.class or "")
            net.WriteString(data.name or data.class or "Unknown Item")
        end
        net.Send(ply)
    end

    local function verifySwep(ply, swep)
        return IsValid(ply) and IsValid(swep) and swep:GetOwner() == ply and swep:GetClass() == "dubz_inventory"
    end

    net.Receive("DubzInventory_Deposit", function(_, ply)
        local swep = net.ReadEntity()
        local class = net.ReadString()
        if not verifySwep(ply, swep) then return end
        if class == swep:GetClass() or class == "" then return end

        local items = cleanItems(swep)
        if #items >= config.Capacity then
            ply:ChatPrint("Inventory is full")
            return
        end

        if not ply:HasWeapon(class) then return end

        local wep = ply:GetWeapon(class)
        if not IsValid(wep) then return end

        table.insert(items, {
            class = class,
            name = wep.PrintName or class
        })

        if IsValid(ply:GetActiveWeapon()) and ply:GetActiveWeapon():GetClass() == class then
            ply:SelectWeapon("hands")
        end

        ply:StripWeapon(class)
        DUBZ_INVENTORY.OpenFor(ply, swep)
    end)

    net.Receive("DubzInventory_Withdraw", function(_, ply)
        local swep = net.ReadEntity()
        local index = net.ReadUInt(8)
        if not verifySwep(ply, swep) then return end

        local items = cleanItems(swep)
        local data = items[index]
        if not data then return end

        local given = ply:Give(data.class)
        if IsValid(given) then
            given.PrintName = data.name
        end

        table.remove(items, index)
        DUBZ_INVENTORY.OpenFor(ply, swep)
    end)
else
    local accent = config.ColorAccent or Color(25, 178, 208)
    local bg = config.ColorBackground or Color(14, 16, 24)
    local panelCol = config.ColorPanel or Color(24, 28, 38)
    local textColor = config.ColorText or color_white

    surface.CreateFont("DubzInv_Title", {
        font = "Montserrat",
        size = 26,
        weight = 600
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

    local function drawPanelOutline(w, h)
        draw.RoundedBox(12, 0, 0, w, h, panelCol)
        surface.SetDrawColor(accent)
        surface.DrawRect(0, 0, w, 3)
    end

    local function buildList(parent, header, height)
        local wrap = vgui.Create("DPanel", parent)
        wrap:Dock(TOP)
        wrap:DockMargin(0, 8, 0, 0)
        wrap:SetTall(height)
        wrap.Paint = function(self, w, h)
            drawPanelOutline(w, h)
            draw.SimpleText(header, "DubzInv_Label", 12, 10, textColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        end
        local scroll = vgui.Create("DScrollPanel", wrap)
        scroll:Dock(FILL)
        scroll:DockMargin(8, 32, 8, 8)
        return wrap, scroll
    end

    local function weaponRows(scroll, weapons, swep)
        for _, wep in ipairs(weapons) do
            local class = wep:GetClass()
            local display = wep.PrintName or class
            local row = scroll:Add("DPanel")
            row:Dock(TOP)
            row:DockMargin(0, 6, 0, 0)
            row:SetTall(46)
            row.Paint = function(self, w, h)
                draw.RoundedBox(8, 0, 0, w, h, bg)
                draw.SimpleText(display, "DubzInv_Label", 12, h / 2, textColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText(class, "DubzInv_Button", w / 2, h / 2, ColorAlpha(textColor, 140), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end

            local addBtn = row:Add("DButton")
            addBtn:Dock(RIGHT)
            addBtn:DockMargin(6, 6, 6, 6)
            addBtn:SetWide(110)
            addBtn:SetText("Store")
            addBtn:SetFont("DubzInv_Button")
            addBtn:SetTextColor(textColor)
            addBtn.Paint = function(self, w, h)
                draw.RoundedBox(8, 0, 0, w, h, accent)
            end
            addBtn.DoClick = function()
                net.Start("DubzInventory_Deposit")
                net.WriteEntity(swep)
                net.WriteString(class)
                net.SendToServer()
            end
        end
    end

    local function storageRows(scroll, items, swep)
        for idx, data in ipairs(items) do
            local itemIndex = idx
            local row = scroll:Add("DPanel")
            row:Dock(TOP)
            row:DockMargin(0, 6, 0, 0)
            row:SetTall(46)
            row.Paint = function(self, w, h)
                draw.RoundedBox(8, 0, 0, w, h, bg)
                draw.SimpleText(data.name, "DubzInv_Label", 12, h / 2, textColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText(data.class, "DubzInv_Button", w / 2, h / 2, ColorAlpha(textColor, 140), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end

            local takeBtn = row:Add("DButton")
            takeBtn:Dock(RIGHT)
            takeBtn:DockMargin(6, 6, 6, 6)
            takeBtn:SetWide(110)
            takeBtn:SetText("Withdraw")
            takeBtn:SetFont("DubzInv_Button")
            takeBtn:SetTextColor(textColor)
            takeBtn.Paint = function(self, w, h)
                draw.RoundedBox(8, 0, 0, w, h, accent)
            end
            takeBtn.DoClick = function()
                net.Start("DubzInventory_Withdraw")
                net.WriteEntity(swep)
                net.WriteUInt(itemIndex, 8)
                net.SendToServer()
            end
        end
    end

    net.Receive("DubzInventory_Open", function()
        local swep = net.ReadEntity()
        local count = net.ReadUInt(8)
        local items = {}
        for i = 1, count do
            items[i] = {
                class = net.ReadString(),
                name = net.ReadString()
            }
        end

        if not IsValid(swep) then return end

        local frame = vgui.Create("DFrame")
        frame:SetSize(640, 520)
        frame:Center()
        frame:MakePopup()
        frame:SetTitle("")
        frame:ShowCloseButton(false)
        frame.Paint = function(self, w, h)
            draw.RoundedBox(12, 0, 0, w, h, bg)
            draw.SimpleText("Dubz Inventory", "DubzInv_Title", 14, 10, textColor)
            draw.SimpleText(string.format("%d / %d slots", #items, config.Capacity), "DubzInv_Button", 16, 42, ColorAlpha(textColor, 180))
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

        local body = vgui.Create("DPanel", frame)
        body:Dock(FILL)
        body:DockMargin(12, 70, 12, 12)
        body.Paint = nil

        local storageWrap, storageScroll = buildList(body, "Stored weapons", 220)
        storageRows(storageScroll, items, swep)

        local weaponsWrap, weaponsScroll = buildList(body, "Your weapons", 180)
        local weapons = LocalPlayer():GetWeapons()
        local filtered = {}
        for _, wep in ipairs(weapons) do
            if IsValid(wep) and wep:GetClass() ~= swep:GetClass() then
                table.insert(filtered, wep)
            end
        end

        if #items >= config.Capacity then
            local fullLabel = weaponsScroll:Add("DLabel")
            fullLabel:Dock(TOP)
            fullLabel:SetTall(28)
            fullLabel:SetText("Inventory is full")
            fullLabel:SetFont("DubzInv_Button")
            fullLabel:SetTextColor(ColorAlpha(textColor, 180))
            fullLabel:DockMargin(0, 6, 0, 0)
        else
            weaponRows(weaponsScroll, filtered, swep)
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

