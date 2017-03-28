--[[
	interface to persistent service
]]
local skynet = require "skynet"

local persistentd
local libpersistent = {}

function libpersistent.load_user_data(uid)
	local userdata = skynet.call(persistentd, "lua", "load_user_data", uid)
	
	return userdata
end

function libpersistent.save_user_data(uid, userdata)
	skynet.send(persistentd, "lua", "save_user_data", uid, userdata)
end

function libpersistent.query_service_status()
	return skynet.call(persistentd, "lua", "query_service_status")
end

local function init()
	persistentd = skynet.uniqueservice "persistent"
end

skynet.init(init)

return libpersistent
