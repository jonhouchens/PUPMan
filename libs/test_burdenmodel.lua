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

now = 110
model:on_activate()
gauge, quality = model:get(burden.ELEMENT.LIGHT)
equal(gauge, 30, 'DAD Activate reseeds gauge')
equal(quality, burden.QUALITY.EXACT, 'DAD Activate reseeds quality')

print('burdenmodel: all assertions passed')
