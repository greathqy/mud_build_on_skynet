--[[
	interface to statelogging service
]]
local skynet = require "skynet"

local stateloggingd
local libstatelogging = {}

function libstatelogging.log_system_activity(uid, eventlabel, eventdetail)
	skynet.send(stateloggingd, "lua", "log_system_activity", uid, eventlabel, eventdetail)
end

--logtype award|gift
function libstatelogging.log_exp_change(uid, logtype, value)
	skynet.send(stateloggingd, "lua", "log_exp_change", uid, logtype, value)
end

function libstatelogging.log_user_login(uid, ip)
	skynet.send(stateloggingd, "lua", "log_user_login", uid, ip)
end

function libstatelogging.query_service_status()
	return skynet.call(stateloggingd, "lua", "query_service_status")
end

local function init()
	stateloggingd = skynet.uniqueservice "statelogging"
end

skynet.init(init)

return libstatelogging
