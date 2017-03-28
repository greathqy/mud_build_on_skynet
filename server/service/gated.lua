--[[
	gateway service
]]
local skynet = require "skynet"
local crypt = require "crypt"
local gatewayserver = require "gatewayserver"

local logger = require "logger"

local loginservice
local watchdog
local servername

local server = {}
local users = {}

local CMD = {}

--called by login server after login complete
function server.login_handler(uid, secret)
	if users[uid] then
		error(string.format("%s is already login", uid))
	end

	local agent = skynet.call(watchdog, "lua", "alloc_agent", uid)
	if not agent then
		logger.error("gated", "user uid", uid, "authed success, but login failed")
		error("init agent failed, maybe invalid login credential")
	end

	local user = {
		agent = agent,
		uid = uid,
	}

	users[uid] = user

	--logger.debug("gated", "server.login_handler uid", uid, "secret", secret)
	gatewayserver.login(uid, secret)

	return true
end

--called by watchdog
function server.logout_handler(uid)
	local user = users[uid]
	if user then
		gatewayserver.logout(uid)
		users[uid] = nil

		--inform login server to exit
		skynet.call(loginservice, "lua", "logout", uid)
	end
end

--called by login server
function server.kick_handler(uid)
	logger.info("gated", "server.kick_handler uid", uid)

	local user = users[uid]
	if user then
		--let watchdog to do rest job
		skynet.call(watchdog, "lua", "logout", uid)
	end
end

function server.disconnect_handler(uid)
	local user = users[uid]

	if user then
		skynet.call(watchdog, "lua", "afk", user.uid, user.agent)
	end
end

function server.request_handler(uid, msg)
	local user = users[uid]

	local agent = user.agent
	if agent then
		skynet.redirect(agent, 0, "client", 0, msg)
	else
		skynet.send(watchdog, "lua", "socket", "data", agent, msg)
	end
end

function server.authed_handler(uid, fd, ip)
	logger.debug("gated", "server.authed_handler uid", uid, "fd", fd, "ip", ip)
	local user = users[uid]

	local agent = user.agent
	if agent then
		skynet.call(watchdog, "lua", "client_auth_completed", agent, fd, ip)
	else
		logger.error("gated", "fd", fd, "auth success but not found associated agent, ip", ip)
	end
end

function server.register_handler(source, loginsrv, name)
	watchdog = source
	servername = name
	loginservice = loginsrv

	skynet.call(loginservice, "lua", "register_gate", servername, skynet.self())
end

function server.command_handler(cmd, source, ...)
	local f = assert(CMD[cmd])
	return f(source, ...)
end

gatewayserver.start(server)
