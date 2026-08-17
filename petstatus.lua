-- Lightweight pet status reconstruction based on the packet strategy used by
-- XIUI's pet bar. Pet effects are not exposed as a direct client buff list.

require 'common';

local exports = {};
local effects = {};
local current_pet_id = 0;

local status_on = {
    [29]=true, [84]=true, [186]=true, [203]=true, [205]=true,
    [230]=true, [236]=true, [237]=true, [242]=true, [243]=true,
    [266]=true, [277]=true, [278]=true, [374]=true, [420]=true, [421]=true,
};

local status_off = {
    [206]=true, [343]=true, [378]=true, [426]=true, [427]=true,
};

local death_messages = {
    [6]=true, [20]=true, [97]=true, [113]=true, [406]=true, [605]=true, [646]=true,
};

-- Common negative effects from XIUI's status classification. Unknown effects
-- are treated as buffs so unusual positive automaton effects fail benignly.
local debuffs = {};
local function mark_range(first, last)
    for id = first, last do
        debuffs[id] = true;
    end
end
mark_range(1, 23);
mark_range(28, 31);
mark_range(128, 149);
mark_range(259, 264);
mark_range(391, 400);
mark_range(448, 452);
for _, id in ipairs({
    155, 156, 168, 171, 172, 173, 174, 175, 186, 189, 192, 193, 194,
    291, 298, 299, 309,
    404, 536, 557, 558, 559, 560, 561, 562, 563, 564, 565, 566, 567,
    572, 576, 597, 630, 631,
}) do
    debuffs[id] = true;
end

local short_names = {
    [2]='SLEEP', [3]='POISON', [4]='PARA', [5]='BLIND', [6]='SILENCE',
    [7]='PETRIFY', [8]='DISEASE', [9]='CURSE', [10]='STUN', [11]='BIND',
    [12]='WEIGHT', [13]='SLOW', [15]='DOOM', [16]='AMNESIA', [31]='PLAGUE',
    [33]='HASTE', [36]='BLINK', [37]='STONESKIN', [40]='PROTECT',
    [41]='SHELL', [42]='REGEN', [43]='REFRESH', [128]='BURN', [129]='FROST',
    [130]='CHOKE', [131]='RASP', [132]='SHOCK', [133]='DROWN', [134]='DIA',
    [135]='BIO', [156]='FLASH', [299]='OVERLOAD',
};

local function sync_pet(pet_id)
    pet_id = tonumber(pet_id) or 0;
    if (pet_id ~= current_pet_id) then
        effects = {};
        current_pet_id = pet_id;
    end
    return pet_id ~= 0;
end

local function apply_effect(effect_id)
    effect_id = tonumber(effect_id);
    if (effect_id == nil or effect_id <= 0 or effect_id >= 1000) then
        return;
    end
    effects[effect_id] = {
        id = effect_id,
        is_buff = debuffs[effect_id] ~= true,
    };
end

local function remove_effect(effect_id)
    effect_id = tonumber(effect_id);
    if (effect_id ~= nil) then
        effects[effect_id] = nil;
    end
end

local function process_result(message, param)
    if (status_on[message]) then
        apply_effect(param);
    elseif (status_off[message]) then
        remove_effect(param);
    end
end

function exports.handle_action(packet, pet_id)
    if (packet == nil or not sync_pet(pet_id)) then
        return;
    end
    for _, target in ipairs(packet.Targets or {}) do
        if (target.Id == current_pet_id) then
            for _, action in ipairs(target.Actions or {}) do
                if (death_messages[action.Message]) then
                    effects = {};
                else
                    process_result(action.Message, action.Param);
                    if (action.AdditionalEffect ~= nil) then
                        process_result(
                            action.AdditionalEffect.Message, action.AdditionalEffect.Param);
                    end
                end
            end
        end
    end
end

function exports.handle_message(data, pet_id)
    if (data == nil or #data < 0x1A or not sync_pet(pet_id)) then
        return;
    end
    local sender = struct.unpack('I', data, 0x04 + 1);
    local target = struct.unpack('I', data, 0x08 + 1);
    local param = struct.unpack('I', data, 0x0C + 1);
    local message = bit.band(struct.unpack('H', data, 0x18 + 1), 0x7FFF);
    if (target ~= current_pet_id and not (message == 206 and sender == current_pet_id)) then
        return;
    end
    if (death_messages[message]) then
        effects = {};
        return;
    end
    process_result(message, param);
end

function exports.clear()
    effects = {};
    current_pet_id = 0;
end

function exports.get_effects(pet_id)
    if (not sync_pet(pet_id)) then
        return {};
    end
    local result = {};
    for id, effect in pairs(effects) do
        local name = short_names[id];
        if (name == nil) then
            name = AshitaCore:GetResourceManager():GetString('buffs.names', id);
            name = name ~= nil and string.upper(name) or ('#' .. tostring(id));
            if (#name > 9) then
                name = name:sub(1, 8);
            end
        end
        result[#result + 1] = {
            id = id,
            name = name,
            is_buff = effect.is_buff,
        };
    end
    table.sort(result, function(left, right)
        if (left.is_buff ~= right.is_buff) then
            return left.is_buff == false;
        end
        return left.id < right.id;
    end);
    return result;
end

return exports;
