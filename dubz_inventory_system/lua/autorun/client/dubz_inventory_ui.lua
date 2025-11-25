local accent = DubzInventoryConfig.Accent or Color(52, 152, 255)

local function accentButton(btn)
    btn:SetTextColor(Color(255, 255, 255))
    btn.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, accent)
    end
end

local function darkPanel(pnl)
    pnl.Paint = function(self, w, h)
        draw.RoundedBox(8, 0, 0, w, h, Color(18, 20, 24))
    end
end

local function buildInventoryList(body, items)
    local list = body:Add("DScrollPanel")
    list:Dock(FILL)
    list:DockMargin(0, 8, 0, 0)

    local sbar = list:GetVBar()
    function sbar:Paint(w, h) end
    function sbar.btnGrip:Paint(w, h)
        draw.RoundedBox(6, 0, 0, w, h, accent)
    end

    for idx, item in ipairs(items or {}) do
        local row = list:Add("DPanel")
        row:SetTall(46)
        row:Dock(TOP)
        row:DockMargin(0, 0, 0, 8)
        darkPanel(row)

        local name = string.upper(item.type or "item") .. " - " .. (item.class or "unknown")

        local lbl = row:Add("DLabel")
        lbl:SetFont("DermaDefaultBold")
        lbl:SetTextColor(Color(230, 235, 240))
        lbl:SetText(name)
        lbl:Dock(LEFT)
        lbl:DockMargin(12, 0, 0, 0)
        lbl:SetWide(260)
        lbl:SetContentAlignment(4)

        local take = row:Add("DButton")
        take:SetText("Withdraw")
        take:Dock(RIGHT)
        take:DockMargin(0, 8, 12, 8)
        take:SetWide(100)
        accentButton(take)
        take.DoClick = function()
            DubzInventoryRequest("withdraw", idx)
        end
    end
end

local function openInventory(capacity, items)
    if IsValid(DubzInventoryFrame) then
        DubzInventoryFrame:Remove()
    end

    local frame = vgui.Create("DFrame")
    frame:SetSize(420, 420)
    frame:Center()
    frame:SetTitle("Dubz Inventory")
    frame:MakePopup()
    frame.lblTitle:SetTextColor(Color(255, 255, 255))
    frame.Paint = function(self, w, h)
        draw.RoundedBox(12, 0, 0, w, h, Color(13, 15, 18))
        draw.RoundedBox(12, 0, 0, w, 32, accent)
    end
    DubzInventoryFrame = frame

    local header = vgui.Create("DPanel", frame)
    header:Dock(TOP)
    header:SetTall(72)
    header:DockMargin(12, 8, 12, 0)
    darkPanel(header)

    local subtitle = header:Add("DLabel")
    subtitle:SetFont("DermaLarge")
    subtitle:SetTextColor(Color(255, 255, 255))
    subtitle:SetText("Simple blue-lined Dubz kit")
    subtitle:Dock(TOP)
    subtitle:DockMargin(12, 8, 12, 0)

    local capText = header:Add("DLabel")
    capText:SetFont("DermaDefaultBold")
    capText:SetTextColor(Color(170, 180, 190))
    capText:SetText(string.format("%d / %d slots used", #items, capacity))
    capText:Dock(TOP)
    capText:DockMargin(12, 4, 12, 8)

    local buttonBar = vgui.Create("DPanel", frame)
    buttonBar:Dock(TOP)
    buttonBar:SetTall(44)
    buttonBar:DockMargin(12, 8, 12, 0)
    buttonBar.Paint = function() end

    local storeWeapon = buttonBar:Add("DButton")
    storeWeapon:SetText("Store current weapon")
    storeWeapon:Dock(LEFT)
    storeWeapon:SetWide(190)
    accentButton(storeWeapon)
    storeWeapon.DoClick = function()
        DubzInventoryRequest("store_weapon")
    end

    local storeEntity = buttonBar:Add("DButton")
    storeEntity:SetText("Store looked-at entity")
    storeEntity:Dock(RIGHT)
    storeEntity:SetWide(190)
    accentButton(storeEntity)
    storeEntity.DoClick = function()
        DubzInventoryRequest("store_entity")
    end

    local body = vgui.Create("DPanel", frame)
    body:Dock(FILL)
    body:DockMargin(12, 8, 12, 12)
    darkPanel(body)

    buildInventoryList(body, items)
end

net.Receive("DubzInventory_Data", function()
    local capacity = net.ReadUInt(8)
    local items = net.ReadTable() or {}
    openInventory(capacity, items)
end)

concommand.Add("dubz_inventory_open", function()
    DubzInventoryRequest("open")
end)
