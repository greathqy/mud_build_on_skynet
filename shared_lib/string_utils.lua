--[[
	String manipulation library
]]
local lib = {}

local function stringify(v)
	if type(v) == "string" then
		v = string.format("%q", v)
	end

	return tostring(v)
end

function lib.stringify_table(args)
	local result = {}

	if type(args) == "table" then
		for k, v in pairs(args) do
			k = stringify(k)
			v = stringify(v)

			result[k] = v
		end
	end

	return result
end

function lib.stringify_table_val(args)
	local result = {}

	if type(args) == "table" then
		for k, v in pairs(args) do
			v = stringify(v)

			result[k] = v
		end
	end

	return result
end

function lib.split_string(str)
	local arr = {}

	for i in string.gmatch(str, "%S+") do
		table.insert(arr, i)
	end

	return arr
end

--only support one dimension table
function lib.dump(args)
	local result = {}
	if type(args) == "table" then
		local indent = "    "
		result[#result + 1] = "{\n"

		for k, v in pairs(args) do
			k = stringify(k)

			if type(v) == "table" then
				v = " * table * "
			else
				v = stringify(v)
			end

			result[#result + 1] = indent
			result[#result + 1] = k
			result[#result + 1] = " = "
			result[#result + 1] = v
			result[#result + 1] = "\n"
		end

		result[#result + 1] = "}"
	else
		args = stringify(args)
		result[#result + 1] = args
	end

	result = table.concat(result, "")

	return result
end

function lib.dumpprint(args)
	local result = lib.dump(args)
	print(result)
end

return lib