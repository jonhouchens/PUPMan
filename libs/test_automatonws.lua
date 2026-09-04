package.path = './?.lua;' .. package.path

local ws = require('automatonws')

local function equal(actual, expected, label)
    assert(actual == expected, ('%s: expected %s, got %s'):format(
        label, tostring(expected), tostring(actual)))
end

local prediction = ws.predict({
    frame = ws.FRAME.VALOREDGE,
    skill = 245,
    maneuvers = { Fire = 2, Light = 1 },
    tp = 1200,
})
equal(prediction.name, 'Chimera Ripper', 'most matching maneuvers win')
equal(prediction.maneuvers, 2, 'matching maneuver count is retained')
equal(prediction.ready, true, 'TP readiness is retained')

prediction = ws.predict({
    frame = ws.FRAME.VALOREDGE,
    skill = 245,
    maneuvers = { Fire = 1, Light = 1 },
})
equal(prediction.name, 'Bone Crusher', 'higher skill breaks maneuver tie')

prediction = ws.predict({
    frame = ws.FRAME.VALOREDGE,
    skill = 244,
    maneuvers = { Light = 3, Dark = 1 },
})
equal(prediction.name, 'Cannibal Blade', 'locked WS is excluded')

prediction = ws.predict({
    frame = ws.FRAME.SHARPSHOT,
    skill = 245,
    maneuvers = { Thunder = 2, Dark = 1 },
})
equal(prediction.name, 'Daze', 'Sharpshot maneuver priority')

prediction = ws.predict({
    frame = ws.FRAME.STORMWAKER,
    skill = 225,
    maneuvers = { Light = 2, Wind = 1 },
    inhibitor = true,
})
equal(prediction.name, 'Magic Mortar', 'Stormwaker uses Harlequin WS list')
equal(prediction.conditional, true, 'Inhibitor marks projection conditional')

local missing, reason = ws.predict({ frame = ws.FRAME.SHARPSHOT })
equal(missing, nil, 'missing skill has no projection')
equal(reason, 'unknown_skill', 'missing skill reason')

print('automatonws: all assertions passed')
