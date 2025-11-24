include("shared.lua")

local config = DUBZ_BACKPACK and DUBZ_BACKPACK.Config or {}
local accent = config.ColorAccent or Color(140, 90, 255)
local primary = config.ColorPrimary or Color(18, 18, 28)
local muted = config.ColorMuted or Color(180, 180, 195)

function ENT:Draw()
    self:DrawModel()

    local ang = self:GetAngles()
    local pos = self:GetPos() + ang:Up() * 8

    ang:RotateAroundAxis(ang:Forward(), 90)
    ang:RotateAroundAxis(ang:Right(), -90)

    cam.Start3D2D(pos, ang, 0.1)
        surface.SetDrawColor(primary)
        surface.DrawRect(-120, -20, 240, 80)

        surface.SetDrawColor(accent)
        surface.DrawRect(-120, -20, 10, 80)

        draw.SimpleText("Dubz Backpack", "DermaLarge", 0, 5, muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("Use: open | Crouch+Use: pick up", "DermaDefaultBold", 0, 40, muted, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    cam.End3D2D()
end
