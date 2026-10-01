package.path = './?.lua;' .. package.path

local burden = require('burdenmodel')
local now = 100
local model = burden.new({
    now = function() return now end,
    thresh_gear = 5,
})

local function equal(actual, expected, label)
    assert(actual == expected, ('%s: expected %s, got %s'):format(
        label, tostring(expected), tostring(actual)))
end

local gain_cases = {
    { -1, 20 },
    {  0, 19 },
    {  1, 18 },
    {  2, 17 },
    {  3, 15 }, -- Horizon 2026-08-26 DAD telemetry; LSB would return 16.
    {  4, 14 },
}

for _, case in ipairs(gain_cases) do
    equal(model:estimated_gain(burden.ELEMENT.LIGHT, case[1]), case[2],
        ('Light gain at stat difference %+d'):format(case[1]))
end

model:on_activate()
local gauge, quality = model:get(burden.ELEMENT.LIGHT)
equal(gauge, 30, 'fresh Activate gauge')
equal(quality, burden.QUALITY.EXACT, 'fresh Activate quality')
equal(model:packet_param_for_gauge(
    gauge + model:estimated_gain(burden.ELEMENT.LIGHT, 3)), 15,
    'fresh d=3 Light packet projection')

now = 104
model:tick()
equal(model:get(burden.ELEMENT.LIGHT), 29, 'one local decay tick')
model:on_deactivate()
equal(model:get(burden.ELEMENT.LIGHT), nil, 'Deactivate discards gauge')

local assumed = burden.new({
    now = function() return now end,
    assume_fresh_on_cold_attach = true,
})
assumed:on_cold_attach()
gauge, quality = assumed:get(burden.ELEMENT.LIGHT)
equal(gauge, 30, 'cold attach assumes Activate gauge')
equal(quality, burden.QUALITY.ESTIMATE,
    'assumed cold attach remains visibly estimated')

local conservative = burden.new({ now = function() return now end })
conservative:on_cold_attach()
equal(conservative:get(burden.ELEMENT.LIGHT), nil,
    'cold attach default remains unknown for other consumers')

now = 110
model:on_activate()
gauge, quality = model:get(burden.ELEMENT.LIGHT)
equal(gauge, 30, 'DAD Activate reseeds gauge')
equal(quality, burden.QUALITY.EXACT, 'DAD Activate reseeds quality')

model:set_overload_observed(true)
model:set_water_maneuvers(2)
model._pet_missing_since = 100
model:on_deus_ex_automata()
for element = 0, 7 do
    gauge, quality = model:get(element)
    equal(gauge, 100, 'Deus seeds every element')
    equal(quality, burden.QUALITY.ESTIMATE, 'Deus baseline is estimated')
end
equal(model.water_maneuvers, 0, 'Deus clears old maneuver decay')
equal(model._pet_missing_since, nil, 'Deus resets despawn grace')
equal(model:is_overloaded(), true, 'summoning preserves master overload')
now = 126
model:tick()
equal(model:get(burden.ELEMENT.DARK), 95, 'Deus decays normally')
model:resync(burden.ELEMENT.DARK, 85)
equal(model:get(burden.ELEMENT.DARK), 115, 'server overrides seed with configured threshold')
model:on_deactivate()
model:on_activate()
equal(model:get(burden.ELEMENT.DARK), 30, 'Activate after Deus restores normal seed')

-- Replay the logged 16-second interval with the base threshold.
local replay = burden.new({ now = function() return now end })
replay:on_deus_ex_automata()
now = now + 16
equal(replay:on_maneuver(burden.ELEMENT.DARK), 85, 'logged Deus then Dark result')

-- Exercise real packet parsing and attach dispatch, including actor filtering.
local handlers = {}
ashita = { events = {
    register = function(_, alias, handler) handlers[alias] = handler end,
    unregister = function(_, alias) handlers[alias] = nil end,
} }
local attached = burden.attach({
    alias = 'test', now = function() return now end,
    get_player_id = function() return 42 end,
    get_pet_index = function() return 1 end,
})
local function packet(actor, ability)
    local bytes = {}
    for i = 1, 19 do bytes[i] = 0 end
    local function bits(offset, count, value)
        for i = 0, count - 1 do
            local b = offset + i
            bytes[math.floor(b / 8) + 1] = bytes[math.floor(b / 8) + 1]
                + (math.floor(value / 2 ^ i) % 2) * 2 ^ (b % 8)
        end
    end
    bits(40, 32, actor)
    bits(82, 4, 6)
    bits(86, 32, ability)
    local chars = {}
    for i, byte in ipairs(bytes) do chars[i] = string.char(byte) end
    return { id = 0x28, data = table.concat(chars) }
end
handlers.test_packet_in(packet(43, 310))
equal(attached.active, false, 'ignore another player summon')
handlers.test_packet_in(packet(42, 310))
equal(attached:get(0), 100, 'Deus packet seeds burden')
handlers.test_packet_in(packet(42, 139))
equal(attached:get(0), nil, 'Deactivate packet clears burden')
handlers.test_packet_in(packet(42, 136))
equal(attached:get(0), 30, 'Activate packet remains unchanged')
attached:detach()

print('burdenmodel: all assertions passed')
