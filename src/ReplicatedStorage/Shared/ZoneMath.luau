-- ZoneMath: where the Royale play zone is at a given server time, from the zone snapshot
-- (RoyaleService.Serialize). The server only sends where a shrink starts / ends and when, so
-- every client can move the zone smoothly each frame instead of in snapshot steps.
local ZoneMath = {}

-- returns x, z, radius
function ZoneMath.At(zone, now)
	if not zone then
		return 0, 0, math.huge
	end
	local startAt, endAt = zone.ShrinkStart, zone.ShrinkEnd
	if zone.State ~= "Shrinking" or not startAt or not endAt or endAt <= startAt then
		return zone.X, zone.Z, zone.Radius
	end
	local t = math.clamp((now - startAt) / (endAt - startAt), 0, 1)
	return zone.FromX + (zone.ToX - zone.FromX) * t, zone.FromZ + (zone.ToZ - zone.FromZ) * t, zone.FromRadius + (zone.ToRadius - zone.FromRadius) * t
end

return ZoneMath
