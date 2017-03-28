--[[
	agent service
]]
local skynet = require "skynet"
local socket = require "socket"
local sproto = require "sproto"
local sprotoloader = require "sprotoloader"

local datetimeutils = require "datetime_utils"
local libpersistent = require "libpersistent"
local libstatelogging = require "libstatelogging"

local logger = require "logger"
local libroom = require "libroom"

local roomconf = require "roomconf"

local watchdog = ...
local host
local make_request

local agent_session_expire = skynet.getenv "agent_session_expire" or 300
agent_session_expire = tonumber(agent_session_expire)

local CMD = {}
local REQUEST = {}

--agent related data
local agentstate = {
	fd = nil,
	ip = nil,

	afk = false,
	last_active = skynet.time(),

	userdata = {
	},
}

local function send_package(pack)
	if not agentstate.fd then 
		return
	end

	local package = string.pack(">s2", pack)
	socket.write(agentstate.fd, package)
end

function REQUEST.login(args)
	local response = {
		userinfo = {
			uid = agentstate.userdata.uid,
			username = agentstate.userdata.username,
			exp = agentstate.userdata.exp,
		}
	}

	libstatelogging.log_user_login(agentstate.userdata.uid, agentstate.ip)

	return response
end

function REQUEST.list_rooms(args)
	local response = {
		rooms = {}
	}

	for _, v in ipairs(roomconf) do
		local roominfo = {
			room_id = v.id,
			room_name = v.name,
			room_exp = v.exp,
			room_exp_interval = v.expinterval,
		}

		response.rooms[#response.rooms + 1] = roominfo
	end

	return response
end

function REQUEST.enter_room(args)
	local roomid = args.roomid

	local response = {
		result = false,
	}

	if roomconf[roomid] then
		libroom.enter_room(roomid, agentstate.userdata, skynet.self())

		response.result = true

		libstatelogging.log_system_activity(agentstate.userdata.uid, "enterroom", "user enter room id:" .. roomid)
	end

	return response
end

function REQUEST.list_members(args)
	local members = libroom.list_members(agentstate.userdata.uid)

	local response = {
		result = true,
		members = {},
	}

	if members == nil then
		--not in room
		response.result = false
	else
		response.result = true
		response.members = members
	end

	return response
end

function REQUEST.leave_room(args)
	local roomid = args.roomid

	local response = {
		result = false,
	}

	response.result = libroom.leave_room(agentstate.userdata.uid)

	return response
end

function REQUEST.say_public(args)
	local response = {
		result = false,
	}

	local content = args.content
	response.result = libroom.say_public(agentstate.userdata.uid, content)

	return response
end

function REQUEST.say_private(args)
	local response = {
		result = false,
	}

	local to_uid = args.uid
	local content = args.content

	response.result = libroom.say_private(agentstate.userdata.uid, to_uid, content)

	return response
end

function REQUEST.kick(args)
	local response = {
		result = false,
	}

	local kick_uid = args.uid

	response.result = libroom.kick(agentstate.userdata.uid, kick_uid)

	return response
end

function REQUEST.send_exp(args)
	local response = {
		result = false,
	}

	local to_uid = args.uid
	local exp = args.exp

	response.result = libroom.send_exp(agentstate.userdata.uid, to_uid, exp)

	return response
end

function REQUEST.logout(args)
	--leave from room
	libroom.leave_room(agentstate.userdata.uid)

	skynet.call(watchdog, "lua", "logout", agentstate.userdata.uid)
end

-------------------------------------------------------------------------------------------

function CMD.notify_exp_change(args)
	local added = args.added

	libstatelogging.log_exp_change(agentstate.userdata.uid, "expchange", added)

	agentstate.userdata.exp = agentstate.userdata.exp + added
end

function CMD.notify_user_enter(roomid, userdata)
	local uid = userdata.uid
	local username = userdata.username
	local exp = userdata.exp

	local data = {
		uid = uid,
		username = username,
		exp = exp,
		roomid = roomid,
	}

	send_package(make_request("enter_room_message", data))
end

function CMD.notify_user_leave(roomid, userdata)
	local uid = userdata.uid
	local username = userdata.username

	local data = {
		uid = uid,
		username = username,
		roomid = roomid,
	}

	send_package(make_request("leave_room_message", data))
end

function CMD.notify_talking_message(args)
	local from_uid = args.from_uid
	local to_uid = args.to_uid
	local content = args.content

	local data = {
		from_uid = from_uid,
		to_uid = to_uid,
		content = content,
	}

	send_package(make_request("talking_message", data))
end

function CMD.notify_kick_message(args)
	local from_uid = args.from_uid
	local kicked_uid = args.kicked_uid

	local data = {
		from_uid = from_uid,
		kicked_uid = kicked_uid,
	}

	send_package(make_request("kick_message", data))
end

function CMD.notify_exp_message(args)
	local from_uid = args.from_uid
	local to_uid = args.to_uid
	local exp = args.exp

	local data = {
		from_uid = from_uid,
		to_uid = to_uid,
		exp = exp,
	}

	send_package(make_request("exp_message", data))
end

function CMD.load_user_data(uid)
	logger.debug("agent", "load data from database for uid", uid)
	uid = tonumber(uid)
	local init_status = false
	local userdata = libpersistent.load_user_data(uid)

	if not userdata then
		init_status = false
	else
		agentstate.userdata = userdata

		init_status = true
	end

	return init_status
end

function CMD.associate_fd_ip(fd, ip)
	logger.debug("agent", "associate fd", fd, "ip", ip)

	local s, e = string.find(ip, ":")
	if s and e then
		ip = string.sub(ip, 1, s - 1)
	end

	agentstate.fd = fd
	agentstate.ip = ip
	agentstate.afk = false
end

function CMD.afk()
	logger.info("agent", "uid", agentstate.userdata.uid, "username", agentstate.userdata.username, "away from keyboard")

	agentstate.fd = nil
	agentstate.ip = nil
	agentstate.afk = true

	CMD.persistent()
end

--[[
	tell watchdog if current agent allow to logout
	sometimes the agent may not allow to logout doing something
	for example, the agent is delegated playing as the player away from keyboard
]]
function CMD.logout()
	agentstate.fd = nil
	agentstate.ip = nil
	agentstate.afk = true

	libroom.leave_room(agentstate.userdata.uid)

	return true
end

--agent data persistence
function CMD.persistent()
	logger.debug("agent", "uid", agentstate.userdata.uid, "start to save data")
	local userdata = agentstate.userdata

	libpersistent.save_user_data(userdata.uid, userdata)
end

--clean agent state for reuse
function CMD.recycle()
	logger.debug("agent", "agent uid", agentstate.userdata.uid, "data reset for reuse")
	local uid = agentstate.userdata.uid

	agentstate.fd = nil
	agentstate.ip = nil
	agentstate.afk = true
	agentstate.last_active = 0
	agentstate.userdata = {}
end

function CMD.check_idle()
	local now = skynet.time()
	local last_active = agentstate.last_active

	local timepassed = now - last_active
	if timepassed >= agent_session_expire then
		logger.debug("agent", "user uid", agentstate.userdata.uid, "recycleable detected")
		skynet.call(watchdog, "lua", "recycle_agent", agentstate.userdata.uid, skynet.self())
	end
end

local function handle_client_request(name, args, response)
	local f = assert(REQUEST[name])
	local result = f(args)

	if response then
		return response(result)
	end
end

local function keep_alive()
	agentstate.last_active = skynet.time()
end

skynet.register_protocol {
	name = "client",
	id = skynet.PTYPE_CLIENT,
	unpack = function(msg, sz)
		return host:dispatch(msg, sz)
	end,
	dispatch = function(_, _, type, ...)
		if type == "REQUEST" then
			local ok, result = pcall(handle_client_request, ...)

			if ok then
				if result then
					send_package(result)
				end
			else
				logger.error("agent", "error when handle request", result)
			end
		else
			--type == RESPONSE
		end

		keep_alive()
	end,
}

skynet.start(function()
	host = sprotoloader.load(1):host("package")
	make_request = host:attach(sprotoloader.load(2))

	skynet.dispatch("lua", function(_, _, command, ...) 
		local f = assert(CMD[command])
		skynet.ret(skynet.pack(f(...)))
	end)
end)
