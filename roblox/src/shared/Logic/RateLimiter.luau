--!strict
-- Token-bucket rate limiter, one bucket per key (usually a Player). Pure: the caller passes the current time.

export type Limiter = {
	allow: (self: Limiter, key: any, now: number) -> boolean,
	forget: (self: Limiter, key: any) -> (),
}

type Bucket = { tokens: number, last: number }

local RateLimiter = {}

-- rate: tokens refilled per second; burst: bucket size (the most calls allowed at once).
function RateLimiter.new(rate: number, burst: number): Limiter
	assert(rate > 0 and burst >= 1, "RateLimiter.new: rate must be > 0 and burst >= 1")
	local buckets: { [any]: Bucket } = {}
	local limiter = {}

	-- Returns true and spends one token if the key has one; otherwise false.
	function limiter.allow(_self: Limiter, key: any, now: number): boolean
		local bucket = buckets[key]
		if bucket == nil then
			bucket = { tokens = burst, last = now }
			buckets[key] = bucket
		else
			-- Refill for the time passed. A clock that goes backwards never adds tokens.
			local elapsed = math.max(0, now - bucket.last)
			bucket.tokens = math.min(burst, bucket.tokens + elapsed * rate)
			bucket.last = now
		end
		if bucket.tokens >= 1 then
			bucket.tokens -= 1
			return true
		end
		return false
	end

	-- Drops a key's bucket (call on PlayerRemoving so memory doesn't grow).
	function limiter.forget(_self: Limiter, key: any)
		buckets[key] = nil
	end

	return (limiter :: any) :: Limiter
end

return RateLimiter
