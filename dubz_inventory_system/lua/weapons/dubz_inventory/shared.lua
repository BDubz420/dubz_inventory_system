if SERVER then
    AddCSLuaFile()
end

SWEP.PrintName = "Dubz Inventory"
SWEP.Author = "Dubz"
SWEP.Instructions = "Primary: Open inventory | Secondary: Store looked entity | Reload: Store current weapon"
SWEP.Category = "Dubz"
SWEP.Spawnable = true
SWEP.AdminOnly = false
SWEP.UseHands = true
SWEP.DrawAmmo = false
SWEP.ViewModelFOV = 62
SWEP.ViewModel = "models/weapons/c_arms.mdl"
SWEP.WorldModel = "models/weapons/w_bugbait.mdl"
SWEP.Slot = 1
SWEP.SlotPos = 1

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

function SWEP:Initialize()
    self:SetHoldType("slam")
end

function SWEP:PrimaryAttack()
    self:SetNextPrimaryFire(CurTime() + 0.5)

    if CLIENT then
        DubzInventoryRequest("open")
    end
end

function SWEP:SecondaryAttack()
    self:SetNextSecondaryFire(CurTime() + 0.8)

    if CLIENT then
        DubzInventoryRequest("store_entity")
    end
end

function SWEP:Reload()
    if CLIENT then
        DubzInventoryRequest("store_weapon")
    end
end

function SWEP:Deploy()
    if CLIENT then return true end
    return true
end

function SWEP:ShouldDropOnDie()
    return false
end
