AddCSLuaFile("shared.lua")
AddCSLuaFile("cl_init.lua")
include("shared.lua")

local config = DUBZ_BACKPACK and DUBZ_BACKPACK.Config or {}

function ENT:Initialize()
    self:SetModel(config.Model or self.Model)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
        phys:SetMass(15)
    end

    self.StoredItems = self.StoredItems or {}
end

function ENT:Use(activator)
    if not IsValid(activator) or not activator:IsPlayer() then return end
    DUBZ_BACKPACK.SendInventory(activator, self, "entity")
end

function ENT:PickupIntoWeapon(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    if ply:HasWeapon("dubz_backpack") then
        ply:ChatPrint("You are already carrying a backpack.")
        return
    end

    local swep = ply:Give("dubz_backpack")
    if not IsValid(swep) then return end

    swep.StoredItems = table.Copy(self.StoredItems or {})
    swep:SetNWBool("DubzBackpackCarried", true)

    self:Remove()
end

function ENT:OnTakeDamage(dmg)
    self:TakePhysicsDamage(dmg)
end
