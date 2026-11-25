--!strict
-- FunnelSteps - which steps of a funnel to log, in order (batch 6, task 6, change E).
-- Pure, no requires. A later step can be reached before an earlier one is seen (the FirstPurchase receipt can
-- arrive before its prompt closes), so reaching a step also logs every earlier step not logged yet, and the
-- dashboard always receives the steps in order. Each step is logged at most once.

local FunnelSteps = {}

-- The steps to log now, lowest first, when `step` is reached. `logged[n]` is true for steps already logged.
-- Returns an empty list if `step` itself was already logged or isn't a whole number of 1 or more.
function FunnelSteps.toLog(logged: { [number]: boolean }, step: number): { number }
	local out = {}
	if type(step) ~= "number" or step < 1 or step % 1 ~= 0 or logged[step] == true then
		return out
	end
	for n = 1, step do
		if logged[n] ~= true then
			table.insert(out, n)
		end
	end
	return out
end

-- Marks the given steps as logged (changes `logged` in place).
function FunnelSteps.mark(logged: { [number]: boolean }, steps: { number })
	for _, n in steps do
		logged[n] = true
	end
end

return FunnelSteps
