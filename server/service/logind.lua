--[[
	login service
	the token format client sent: base64(platform):base64(token)@base64(dest server)
	the platform user login with, token from the issued by the platform, the game server want login
]]
local login = require "loginserver"
local crypt = require "crypt"
local skynet = require "skynet"

local httpc = require "http.httpc"

local string_utils = require "string_utils"
local logger = require "logger"

-- read configuration
local host = skynet.getenv "loginserver_host"
local port = skynet.getenv "loginserver_port"

assert(host ~= nil, "loginserver_host must specified in config file")
assert(port ~= nil, "loginserver_port must specified in config file")

host = host
port = tonumber(port)

local login_slave_instance = skynet.getenv "loginserver_slave_instance"
login_slave_instance = login_slave_instance or 8
login_slave_instance = tonumber(login_slave_instance)

local auth_backend = skynet.getenv "loginserver_authenticate_backend"
local auth_endpoint = skynet.getenv "loginserver_authenticate_endpoint"
assert(auth_backend ~= nil, "loginserver_authenticate_backend must specified in config file")
assert(auth_endpoint ~= nil, "loginserver_authenticate_endpoint must specified in config file")

local server = {
	host = host,
	port = port,
	multilogin = false,
	name = "logind",
	instance = login_slave_instance,
}

local gameserver_lists = {}
local onlineuser_lists = {}

local onlinecount = 0
local auth_requests = 0

local authenticators = {}

function authenticators.skynetmud(platform, token)
	local uid = nil

	--skynetmud platform token format, username\tpassword
	local postfields = {
		platform = platform,
		token = token,
	}
	local recvheader = {}
	local ok, status, body = pcall(httpc.post, auth_backend, auth_endpoint, postfields, recvheader)
	--logger.debug("logined", "ok", ok, "status", status, "body", body)

	if ok then
		local resp = string_utils.split_string(body)
		if ok and #resp == 2 then
			local code = tonumber(resp[1])
			if code == 0 then
				uid = tonumber(resp[2])
			end
		end
	end

	return uid
end

local function authenticate(platform, token)
	local uid

	if authenticators[platform] then
		local func = authenticators[platform]
		uid = func(platform, token)

		if not uid then
			logger.warn("logind", "verify platform", platform, "token", token, "failed to retrieve uid")
			error(string.format("platform: %s unexpected error verify token: %s", platform, token))
		end
	else
		logger.error("logind", "invalid platform id", platform)
		error("invalid platform id" .. platform)
	end

	return uid
end

function server.auth_handler(token)
	logger.info("logind", "auth_handler token", token)

	auth_requests = auth_requests + 1

	local platform, plt_token, server = token:match("([^:]*):([^@]*)@(.*)")

	platform = crypt.base64decode(platform)
	plt_token = crypt.base64decode(plt_token)
	server = crypt.base64decode(server)

	local ok, uid = pcall(authenticate, platform, plt_token)
	
	if not ok then
		logger.info("logind", "authenticate failed, token", token)
		error("authentication failed")
	end

	return server, uid
end

--return the server user should login
function server.login_handler(server, uid, secret)
	if not gameserver_lists[server] then
		logger.error("logind", "user", uid, "want login to unknown server", server)
		error("unknown server")
	end

	local server_addr = gameserver_lists[server]
	local exists = onlineuser_lists[uid]

	if exists then
		logger.info("logind", "user", uid, "is already online, notify gateway to kick this user")
		skynet.call(exists.address, "lua", "kick", uid)
	end

	if onlineuser_lists[uid] then
		error(string.format("user %d is already online", uid))
	end

	--notify server to prepare data for this user
	skynet.call(server_addr, "lua", "login", uid, secret)

	onlineuser_lists[uid] = {
		uid = uid,
		address = server_addr,
		server = server, 
	}

	onlinecount = onlinecount + 1

	return server
end

local CMD = {}

function CMD.register_gate(server, address)
	gameserver_lists[server] = address
end

function CMD.logout(uid)
	local user = onlineuser_lists[uid]

	if user then
		logger.info("logind", "user", uid, "logout at server", user.server)

		onlineuser_lists[uid] = nil
		onlinecount = onlinecount - 1
	end
end

function CMD.query_service_status()
	local data = {
		onlinecount = onlinecount,
		auth_requests = auth_requests,
	}

	return data
end

function server.command_handler(command, ...)
	local f = assert(CMD[command])
	return f(...)
end

login(server)
