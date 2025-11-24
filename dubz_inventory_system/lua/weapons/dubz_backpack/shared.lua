AddCSLuaFile()

SWEP.PrintName = "Dubz Backpack"
SWEP.Author = "Dubz"
SWEP.Instructions = "Primary: place backpack | Secondary: open inventory"
SWEP.Spawnable = false
SWEP.AdminOnly = false
SWEP.Category = "Dubz Utilities"

SWEP.ViewModel = "models/weapons/c_arms.mdl"
SWEP.WorldModel = "models/props_c17/BriefCase001a.mdl"
SWEP.UseHands = true
SWEP.HoldType = "slam"

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

SWEP.StoredItems = SWEP.StoredItems or {}

local config = DUBZ_BACKPACK and DUBZ_BACKPACK.Config or { Capacity = 8 }

function SWEP:Initialize()
    self:SetHoldType(self.HoldType)
    self.StoredItems = self.StoredItems or {}
end

function SWEP:Deploy()
    self:SetHoldType(self.HoldType)
    return true
end

function SWEP:PrimaryAttack()
    if CLIENT then return end

    local owner = self:GetOwner()
    if not IsValid(owner) then return end

    self:SetNextPrimaryFire(CurTime() + 1)

    local tr = util.TraceHull({
        start = owner:EyePos(),
        endpos = owner:EyePos() + owner:GetAimVector() * 80,
        mins = Vector(-10, -10, -10),
        maxs = Vector(10, 10, 10),
        filter = owner
    })

    if not tr.Hit then
        owner:ChatPrint("Aim at the ground to place the backpack.")
        return
    end

    local ent = ents.Create("dubz_backpack")
    if not IsValid(ent) then return end

    ent:SetPos(tr.HitPos + tr.HitNormal * 4)
    ent:SetAngles(Angle(0, owner:EyeAngles().y, 0))
    ent:Spawn()

    ent.StoredItems = table.Copy(self.StoredItems or {})

    owner:StripWeapon(self:GetClass())
end

function SWEP:SecondaryAttack()
    if CLIENT then return end
    self:SetNextSecondaryFire(CurTime() + 0.5)

    local owner = self:GetOwner()
    if not IsValid(owner) then return end

    DUBZ_BACKPACK.SendInventory(owner, self, "weapon")
end

function SWEP:Reload()
    if CLIENT then return end
    local owner = self:GetOwner()
    if not IsValid(owner) then return end

    owner:ChatPrint("Primary: place backpack | Secondary: open inventory")
end
