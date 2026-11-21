--!strict
-- Pure surge-window math: is a surge open at a UTC Unix second, and when does the next one start?
-- The current time is passed in, so the module has no clock and no Roblox APIs.

local Surge = {}

-- Length of the hour slot that every surge is measured against, in seconds.
local HOUR = 3600

-- True while the first `minutes` of the current UTC hour are running.
function Surge.isActive(now: number, minutes: number): boolean
	return (now % HOUR) < minutes * 60
end

-- Unix second when the next surge opens: the current second while a surge is live,
-- otherwise the next whole hour boundary.
function Surge.nextStart(now: number, minutes: number): number
	if Surge.isActive(now, minutes) then
		return now
	end
	return now - (now % HOUR) + HOUR
end

return Surge
