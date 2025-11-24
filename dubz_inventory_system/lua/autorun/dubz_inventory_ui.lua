local config = DUBZ_BACKPACK and DUBZ_BACKPACK.Config or { Capacity = 8 }
local accent = config.ColorAccent or Color(140, 90, 255)
local primary = config.ColorPrimary or Color(18, 18, 28)
local panelCol = config.ColorPanel or Color(28, 28, 40)
local muted = config.ColorMuted or Color(180, 180, 195)

local function drawBlurPanel(panel)
    local x, y = panel:LocalToScreen(0, 0)
    local w, h = panel:GetWide(), panel:GetTall()
    surface.SetDrawColor(primary)
    surface.DrawRect(0, 0, w, h)
    Derma_DrawBackgroundBlur(panel, panel.startTime)
end

local function dubzBox(parent, label)
    local box = vgui.Create("DPanel", parent)
    box:Dock(TOP)
    box:DockMargin(0, 4, 0, 4)
    box:SetTall(48)
    box.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, panelCol)
        surface.SetDrawColor(accent)
        surface.DrawRect(0, 0, 4, h)
        draw.SimpleText(label, "Trebuchet24", 12, h / 2, muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    return box
end

local function sendDeposit(containerType, container, class)
    net.Start("DubzBackpack_Deposit")
    net.WriteString(containerType)
    net.WriteEntity(container)
    net.WriteString(class or "")
    net.SendToServer()
end

local function sendWithdraw(containerType, container, index)
    net.Start("DubzBackpack_Withdraw")
    net.WriteString(containerType)
    net.WriteEntity(container)
    net.WriteUInt(index, 8)
    net.SendToServer()
end

local activePanel

local function openInventory(containerType, container, capacity, items)
    if IsValid(activePanel) then activePanel:Remove() end

    activePanel = vgui.Create("DFrame")
    activePanel:SetSize(640, 460)
    activePanel:Center()
    activePanel:MakePopup()
    activePanel:SetTitle("")
    activePanel:ShowCloseButton(false)
    activePanel.startTime = SysTime()
    activePanel.Paint = function(self, w, h)
        drawBlurPanel(self)
        draw.SimpleText("Dubz Backpack", "Trebuchet24", 16, 12, muted)
        draw.SimpleText(string.format("%d / %d slots used", #items, capacity), "Trebuchet18", 16, 34, muted)
        surface.SetDrawColor(accent)
        surface.DrawRect(0, 0, w, 2)
    end

    local close = vgui.Create("DButton", activePanel)
    close:SetText("✕")
    close:SetFont("Trebuchet18")
    close:SetColor(muted)
    close:SetSize(32, 32)
    close:SetPos(activePanel:GetWide() - 40, 8)
    close.Paint = function(self, w, h)
        draw.RoundedBox(6, 0, 0, w, h, Color(0, 0, 0, 120))
    end
    close.DoClick = function()
        activePanel:Remove()
    end

    local body = vgui.Create("DPanel", activePanel)
    body:Dock(FILL)
    body:DockMargin(12, 52, 12, 12)
    body.Paint = function(self, w, h)
        surface.SetDrawColor(Color(255, 255, 255, 2))
        surface.DrawRect(0, 0, w, h)
    end

    local inventoryTitle = dubzBox(body, "Stored Items")
    inventoryTitle:SetTall(36)

    local scroll = vgui.Create("DScrollPanel", body)
    scroll:Dock(TOP)
    scroll:DockMargin(0, 0, 0, 8)
    scroll:SetTall(220)
    scroll.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, Color(0, 0, 0, 40))
    end

    if #items == 0 then
        local empty = vgui.Create("DLabel", scroll)
        empty:SetText("This backpack is empty. Add a weapon from your loadout below.")
        empty:SetColor(muted)
        empty:SetFont("Trebuchet18")
        empty:Dock(TOP)
        empty:DockMargin(8, 8, 8, 8)
    else
        for idx, data in ipairs(items) do
            local row = vgui.Create("DPanel", scroll)
            row:Dock(TOP)
            row:DockMargin(8, 8, 8, 0)
            row:SetTall(48)
            row.Paint = function(self, w, h)
                draw.RoundedBox(8, 0, 0, w, h, panelCol)
                draw.SimpleText(data.name, "Trebuchet18", 12, h / 2, muted, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
                draw.SimpleText(data.class, "Trebuchet18", w / 2, h / 2, Color(120, 120, 135), TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
            end

            local take = vgui.Create("DButton", row)
            take:Dock(RIGHT)
            take:DockMargin(6, 6, 6, 6)
            take:SetWide(110)
            take:SetText("Withdraw")
            take:SetFont("Trebuchet18")
            take:SetColor(color_white)
            take.Paint = function(self, w, h)
                draw.RoundedBox(8, 0, 0, w, h, accent)
            end
            take.DoClick = function()
                sendWithdraw(containerType, container, idx)
            end
        end
    end

    local depositTitle = dubzBox(body, "Add a weapon")
    depositTitle:SetTall(36)

    local depositRow = vgui.Create("DPanel", body)
    depositRow:Dock(TOP)
    depositRow:DockMargin(8, 8, 8, 0)
    depositRow:SetTall(54)
    depositRow.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, panelCol)
    end

    local combo = vgui.Create("DComboBox", depositRow)
    combo:Dock(LEFT)
    combo:SetWide(360)
    combo:SetFont("Trebuchet18")
    combo:SetValue("Select a weapon to store")
    combo:SetTextColor(muted)

    for _, wep in ipairs(LocalPlayer():GetWeapons()) do
        local class = wep:GetClass()
        if class ~= "dubz_backpack" and (not DUBZ_BACKPACK or not DUBZ_BACKPACK.IsWeaponAllowed or DUBZ_BACKPACK.IsWeaponAllowed(class)) then
            combo:AddChoice((wep.PrintName or class) .. " (" .. class .. ")", class)
        end
    end

    local deposit = vgui.Create("DButton", depositRow)
    deposit:Dock(RIGHT)
    deposit:DockMargin(6, 6, 6, 6)
    deposit:SetWide(140)
    deposit:SetText("Store Weapon")
    deposit:SetFont("Trebuchet18")
    deposit:SetColor(color_white)
    deposit.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, accent)
    end
    deposit.DoClick = function()
        if #items >= capacity then
            chat.AddText(Color(255, 100, 100), "Backpack is full!")
            return
        end

        local _, class = combo:GetSelected()
        if class then
            sendDeposit(containerType, container, class)
        else
            chat.AddText(Color(255, 200, 150), "Choose a weapon first.")
        end
    end
end

net.Receive("DubzBackpack_Open", function()
    local containerType = net.ReadString()
    local container = net.ReadEntity()
    local capacity = net.ReadUInt(8)
    local count = net.ReadUInt(8)

    local items = {}
    for i = 1, count do
        local class = net.ReadString()
        local name = net.ReadString()
        table.insert(items, { class = class, name = name })
    end

    openInventory(containerType, container, capacity, items)
end)
