--!strict
-- Purchase-history helpers for ProcessReceipt double-grant protection.
-- Pure: the history is passed in by the caller and is never mutated.

local Receipts = {}

-- True when `purchaseId` already sits in the processed history.
function Receipts.isProcessed(list: { string }, purchaseId: string): boolean
	for _, id in list do
		if id == purchaseId then
			return true
		end
	end
	return false
end

-- Returns a NEW history with `purchaseId` appended at the end, then the oldest
-- entries dropped from the front until at most `max` ids remain. An id that is
-- already recorded is never added twice. `max` below 1 is treated as 1.
function Receipts.record(list: { string }, purchaseId: string, max: number): { string }
	local limit = if max < 1 then 1 else max

	local result: { string } = {}
	for _, id in list do
		table.insert(result, id)
	end

	if Receipts.isProcessed(list, purchaseId) then
		return result
	end

	table.insert(result, purchaseId)

	while #result > limit do
		table.remove(result, 1)
	end

	return result
end

return Receipts
