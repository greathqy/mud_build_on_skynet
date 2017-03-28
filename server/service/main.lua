--[[
	GameServer entrance
]]

local skynet = require "skynet"
local sprotoloader = require "sprotoloader"

local logger = require "logger"

skynet.start(function()
	logger.info("main", "server starting")

	skynet.uniqueservice "protoloader"

	local debug_console_port = skynet.getenv("debug_console_port")
	if debug_console_port then
		debug_console_port = tonumber(debug_console_port)
		skynet.newservice("debug_console", debug_console_port)
	end

	skynet.uniqueservice "statelogging"
	skynet.uniqueservice "room"

	local gameserver_host = skynet.getenv("gameserver_host")
	local gameserver_port = tonumber(skynet.getenv("gameserver_port"))

	local logind = skynet.uniqueservice "logind"
	local gated = skynet.uniqueservice "gated"

	local watchdog = skynet.uniqueservice("watchdog")

	skynet.call(watchdog, "lua", "start", {
		address = gameserver_host,
		port = gameserver_port,
		nodelay = true,
		maxclient = 1024,
		servername = "server1",

		loginservice = logind,
		gateservice = gated,
	})

	logger.info("main", "server started")

	skynet.exit()
end)