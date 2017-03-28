--[[
	modify snax.gateserver to receive message from client and send message to client
	use length prefixed(2 bytes) binary string for data packing
]]
local skynet = require "skynet"
local gateserver = require "snax.gateserver"
local netpack = require "netpack"
local crypt = require "crypt"
local socketdriver = require "socketdriver"

local logger = require "logger"

local assert = assert
local base64encode = crypt.base64encode
local base64decode = crypt.base64decode

--[[
Protocol:
	first package
	client -> server
		uid@base64(server)#index:base64(hmac)

	server -> client
		404 user not found
		403 index expired
		401 unauthorized
		400 bad request
		200 ok

API:
	server.login(uid, secret)
		update user secret

	server.logout(uid)
		user logout

	server.ip(uid)
		return ip when connection establish or nil

	server.start(conf)
		start server

Supported skynet command:
	login uid secret (used by loginserver)
	logout uid (used by watchdog/agent)

Config for server.start
	conf.login_handler(uid, secret) -> subid : the function when a new user login, alloc a subid for it. (may call by login server)
	conf.logout_handler(uid, subid) : the function when a user logout. (may call by agent)
	
	conf.request_handler(uid, session, msg) : the function when recv a new request.

	conf.register_handler(source, loginsrv, servername) : called when gate open
	conf.disconnect_handler(uid) : called when a connection disconnected(afk)
]]
local server = {}

skynet.register_protocol {
	name = "client",
	id = skynet.PTYPE_CLIENT
}

local user_online = {}
local handshake = {}
local connection = {}

function server.login(uid, secret)
	assert(user_online[uid] == nil)
	
	user_online[uid] = {
		uid = uid,
		secret = secret,
		handshake_index = 0, --handshake sequence
		fd = nil,
		ip = nil,
	}
end

function server.logout(uid)
	local user = user_online[uid]

	user_online[uid] = nil

	if user.fd then
		gateserver.closeclient(user.fd)
		connection[user.fd] = nil
	end
end

function server.ip(uid)
	local user = user_online[uid]
	
	if user and user.ip then
		return user.ip
	end
end

function server.fd(uid)
	local user = user_online[uid]

	if user and user.fd then
		return user.fd
	end
end

function server.start(conf)
	local handler = {}

	local CMD = {
		login = assert(conf.login_handler),	--notify from login server
		logout = assert(conf.logout_handler), --logout request from other service
		kick = assert(conf.kick_handler), --kick request from other service

		othercmd  = assert(conf.command_handler),
	}

	function handler.command(cmd, source, ...)
		local f
		local result

		if CMD[cmd] then
			f = CMD[cmd]
			result = f(...)
		else
			f = CMD.othercmd
			result = f(cmd, ...)
		end

		return result
	end

	function handler.open(watchdog, gateconf)
		local servername = assert(gateconf.servername)

		local loginservice = gateconf.loginservice

		--register to login server
		return conf.register_handler(watchdog, loginservice, servername)
	end

	function handler.connect(fd, addr)
		--logger.debug("gated", "connect from fd", fd, "address", addr)
		handshake[fd] = addr
		gateserver.openclient(fd)
	end

	function handler.disconnect(fd)
		handshake[fd] = nil

		local c = connection[fd]
		if c then
			c.fd = nil
			connection[fd] = nil

			if conf.disconnect_handler then 
				conf.disconnect_handler(c.uid)
			end
		end
	end

	handler.error = handler.disconnect

	local request_handler = assert(conf.request_handler)
	local authed_handler = assert(conf.authed_handler)

	function handler.warning(fd, size)
		logger.warn("gated", "socket data size exceeded fd", fd, "size", size)
	end

	local function doauth(fd, message, addr)
		--format uid@base64(server)#index:base64(hmac)
		local uid, servername, index, hmac = string.match(message, "([^@]*)@([^#]*)#([^:]*):(.*)")
		hmac = base64decode(hmac)

		local user = user_online[tonumber(uid)]
		if user == nil then
			return "404 User Not Found"
		end

		local idx = assert(tonumber(index))

		if idx <= user.handshake_index then
			return "403 Index Expired"
		end

		local text = string.format("%s@%s#%d", uid, servername, index)
		local calculated = crypt.hmac_hash(user.secret, text)
		
		if calculated ~= hmac then
			return "401 Unauthorized"
		end

		user.handshake_index = idx
		user.fd = fd
		user.ip = addr

		connection[fd] = user
	end

	local function auth(fd, addr, msg, sz)
		local message = netpack.tostring(msg, sz)
		local ok, result = pcall(doauth, fd, message, addr)

		if not ok then
			logger.warn("gated", "bad request", message)
			result = "400 Bad Request"
		end

		local close = result ~= nil

		if result == nil then
			--pass
			result = "200 OK"
		end

		--notify client auth result
		socketdriver.send(fd, netpack.pack(result))

		if not close then
			--auth success
			local user = connection[fd]
			if user then
				local uid = user.uid
				local fd = user.fd
				local ip = user.ip

				authed_handler(uid, fd, ip)
			else
				logger.error("gated", "auth verify success but no associte user found for fd", fd)
			end
		else
			--auth failed
			gateserver.closeclient(fd)
		end
	end

	function handler.message(fd, msg, sz)
		local addr = handshake[fd]

		if addr then
			handshake[fd] = nil

			auth(fd, addr, msg, sz)
		else
			local user = assert(connection[fd], "invalid fd")
			local message = netpack.tostring(msg, sz)

			request_handler(user.uid, message)
		end
	end

	return gateserver.start(handler)
end

return server
