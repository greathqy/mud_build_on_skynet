--[[
	Datetime related utility
]]

local lib = {}

function lib.get_current_datetime()
	local datetime = os.date("%Y-%m-%d %H:%M:%S")

	return datetime
end

return lib