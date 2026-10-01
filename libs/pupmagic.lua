-- Magic-delay model, implemented for PUPMan. Timing values and spell groups
-- checked against Zaldas/PetsReborn data/automatonCooldowns.lua (2026-09-16).
-- These are estimates, not recasts reported by Horizon. No attachment/gear
-- adjustments are assumed without verified server behavior.
local lib = {}

local names = { 'Magic Delay', 'Healing', 'Elemental', 'Enfeebling',
    'Enhancing', 'Status Removal' }
local keys = { 'magic', 'heal', 'elemental', 'enfeeble', 'enhance', 'status' }
local seconds = {
    [1] = { 12.8, 12, false, 10, false, false },
    [2] = { 12.8, 20, false, false, false, false },
    [3] = { 12.8, 20, false, 10, false, false },
    [4] = { 12.8, 20, 25, 10, 25, false },
    [5] = { 6.4, 10, false, 10, 15, 10 },
    [6] = { 12.8, false, 35, 5, 35, false },
}

function lib.definitions(frame, head)
    local result = {}
    if frame ~= 0x20 and frame ~= 0x23 then return result end
    for index, duration in ipairs(seconds[head] or {}) do
        if duration then
            result[#result + 1] = {
                key = 'magic_' .. keys[index], name = names[index],
                cooldown = duration, spawn_delay = false, magic = true,
            }
        end
    end
    return result
end

local groups = {}
local function add(category, ids)
    for _, id in ipairs(ids) do groups[id] = 'magic_' .. category end
end
add('enfeeble', { 23, 24, 56, 58, 59, 220, 221, 230, 231,
    245, 247, 248, 254, 260, 270, 286 })
add('enhance', { 54, 57, 106, 108, 110, 111, 129, 134, 277, 477, 511 })
add('status', { 14, 15, 16, 17, 18, 19, 20, 143 })

function lib.category(spell_id)
    if spell_id >= 1 and spell_id <= 6 then return 'magic_heal' end
    if spell_id >= 43 and spell_id <= 52 then return 'magic_enhance' end
    if spell_id >= 144 and spell_id <= 173 then return 'magic_elemental' end
    return groups[spell_id]
end

return lib
