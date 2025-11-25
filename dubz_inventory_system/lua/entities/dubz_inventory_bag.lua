AddCSLuaFile()

ENT.Type = "anim"
ENT.Base = "base_anim"
ENT.PrintName = "Dubz Backpack"
ENT.Spawnable = false
ENT.RenderGroup = RENDERGROUP_OPAQUE

local BAG_MODEL = "models/props_c17/BriefCase001a.mdl"

function ENT:Initialize()
    if CLIENT then return end

    self:SetModel(BAG_MODEL)
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetUseType(SIMPLE_USE)

    local phys = self:GetPhysicsObject()
    if IsValid(phys) then
        phys:Wake()
    end
end

function ENT:Use(activator)
    if CLIENT then return end
    if not (IsValid(activator) and activator:IsPlayer()) then return end

    if activator:HasWeapon("dubz_inventory") then
        if DUBZ_INVENTORY and DUBZ_INVENTORY.SendTip then
            DUBZ_INVENTORY.SendTip(activator, "Drop your current backpack first")
        end
        return
    end

    local stored = table.Copy(self.StoredItems or {})

    local function giveAndOpen()
        local swep = activator:GetWeapon("dubz_inventory")
        if not IsValid(swep) then return end

        swep.StoredItems = stored
        swep:SetHoldType("slam")

        if DUBZ_INVENTORY and DUBZ_INVENTORY.OpenFor then
            DUBZ_INVENTORY.OpenFor(activator, swep)
        end

        self:Remove()
    end

    activator:Give("dubz_inventory")

    timer.Simple(0, giveAndOpen)
end
