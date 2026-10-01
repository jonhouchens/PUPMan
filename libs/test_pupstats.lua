package.path = './?.lua;' .. package.path

local master = {
    [0] = { 50, 10 }, -- STR 60 in idle gear.
    [4] = { 45, 5 },  -- INT 50 in idle gear.
}
local now = 100

AshitaCore = {
    GetMemoryManager = function()
        return {
            GetPlayer = function()
                return {
                    GetStat = function(_, index)
                        return master[index] and master[index][1] or 0
                    end,
                    GetStatModifier = function(_, index)
                        return master[index] and master[index][2] or 0
                    end,
                }
            end,
        }
    end,
}

local pupstats = require('pupstats')
local stats = pupstats.new({ now = function() return now end })

local function equal(actual, expected, label)
    assert(actual == expected, ('%s: expected %s, got %s'):format(
        label, tostring(expected), tostring(actual)))
end

stats.pet_base[pupstats.STAT.STR] = 45
stats.pet_additional[pupstats.STAT.STR] = 10
stats.pet_total[pupstats.STAT.STR] = 55
stats.pet_updated = now

local diff, context = stats:stat_diff(0, 'estimate')
equal(diff, 5, 'unobserved estimate uses live idle gear')
equal(context.stat_source, 'live', 'unobserved estimate source')

-- LuAshitacast has equipped Fire's STR set by the outgoing packet.
master[0] = { 50, 24 }
stats:snapshot_maneuver(0)
master[0] = { 50, 10 } -- Aftercast restored idle gear.

diff, context = stats:stat_diff(0, 'estimate')
equal(diff, 19, 'estimate reuses maneuver-gear master stat')
equal(context.master_stat, 74, 'maneuver-gear master total')
equal(context.stat_source, 'maneuver_snapshot', 'observed estimate source')

-- A new pet stat packet updates the projection without losing the saved
-- maneuver-gear master stat.
now = 103
stats.pet_total[pupstats.STAT.STR] = 60
diff, context = stats:stat_diff(0, 'estimate')
equal(diff, 14, 'projection uses current pet stat')
equal(context.maneuver_stat_age, 3, 'maneuver snapshot age')

-- The real maneuver phase still consumes the exact outgoing snapshot.
diff, context = stats:stat_diff(0, 'maneuver')
equal(diff, 19, 'maneuver consumes the exact outgoing master-pet snapshot')
equal(context.stat_source, 'outgoing_snapshot', 'maneuver source is unchanged')

stats:clear()
diff, context = stats:stat_diff(0, 'estimate')
equal(diff, nil, 'zone clear removes maneuver snapshot and pet stats')
equal(context.stat_source, 'live', 'zone clear restores live fallback')

print('pupstats: all assertions passed')
