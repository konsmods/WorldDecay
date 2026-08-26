local WDecay_Carry = {}

function WDecay_Carry.preview(markerData, carryKey, eligibleCount, basePercent,
                              multBefore, multNow, maxObjects, alreadyPlaced)
    if not markerData or eligibleCount <= 0 or basePercent <= 0 then return 0, markerData and markerData[carryKey] or 0 end
    local gainMult = multNow - multBefore
    if gainMult <= 0 then return 0, markerData[carryKey] or 0 end
    local carry = (markerData[carryKey] or 0) + eligibleCount * (basePercent / 100) * gainMult
    local whole = math.floor(carry)
    if whole < 0 then whole = 0 end
    if maxObjects ~= nil then
        local room = maxObjects - (alreadyPlaced or 0)
        if room < 0 then room = 0 end
        if whole > room then whole = room end
    end
    return whole, carry - whole
end

function WDecay_Carry.accumulate(markerData, carryKey, eligibleCount, basePercent,
                                 multBefore, multNow, maxObjects, alreadyPlaced)
    local whole, remainder = WDecay_Carry.preview(markerData, carryKey, eligibleCount, basePercent, multBefore, multNow, maxObjects, alreadyPlaced)
    if markerData then markerData[carryKey] = remainder end
    return whole
end

return WDecay_Carry
