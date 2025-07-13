-- Remove entities on map load
hook.Add("InitPostEntity", "RemoveReflectiveGlass", function()
    -- Find all func_reflective_glass entities
    for _, ent in ipairs(ents.FindByClass("func_reflective_glass")) do
        -- Remove the entity
        ent:Remove()
    end
    
    print("[Remove Entities] Removed all func_reflective_glass entities")
end)