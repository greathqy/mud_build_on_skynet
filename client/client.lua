--[[
	Game Client, support these commands:

	login
	listrooms
	enterroom roomid
	leaveroom
	listmembers
	say content
	sayto userid content
	kick userid
	sendexp to_userid points
	logout
]]
local root = "../../../"
package.cpath = root .. "skynet/luaclib/?.so"
package.path = 	root .. "skynet/lualib/?.lua;" .. 
				root .. "server/lib/?.lua;" .. 
				root .. "shared_lib/?.lua;" .. 
				root .. "client/?.lua;" ..
				root .. "config/?.lua;"

if _VERSION ~= "Lua 5.3" then
	error "Use lua 5.3"
end

local socket = require "clientsocket"
local sockhelper = require "sockhelper"
local protocol = require "protocol"
local sproto = require "sproto"

local string_utils = require "string_utils"

local host = sproto.new(protocol.s2c):host("package")
local make_request = host:attach(sproto.new(protocol.c2s))

local loginserver_host
local loginserver_port
local gameserver_host
local gameserver_port
local username
local password

local REQ_FROM_SERVER = {}
local RESP_FROM_SERVER = {}

local session = 0
local index = 1
local session_map = {}

local function send_request(name, args)
	session = session + 1
	session_map[session] = name
	local str = make_request(name, args, session)

	sockhelper.send_package(str)
end

local function handle_package(t, ...)
	local arr = {...}
	if t == "REQUEST" then
		local name = arr[1]
		local args = arr[2]

		assert(REQ_FROM_SERVER[name], "no REQ_FROM_SERVER handler found for: " .. name)
		local f = REQ_FROM_SERVER[name]
		f(args)
	elseif t == "RESPONSE" then
		local session = arr[1]
		local args = arr[2]

		local name = session_map[session]
		if name then
			session_map[session] = nil

			assert(RESP_FROM_SERVER[name], "no RESP_FROM_SERVER handler found for: " .. name)
			local f = RESP_FROM_SERVER[name]
			f(args)
		end
	end
end

local function dispatch_package()
	while true do
		local v = sockhelper.try_read_package()
		if not v then
			break
		end

		handle_package(host:dispatch(v))
	end
end

function REQ_FROM_SERVER.enter_room_message(args)
	local roomid = args.roomid
	local uid = args.uid
	local username = args.username
	local exp = args.exp

	print("user", username, "uid", uid, "enter room", roomid, "with exp", exp)
end

function REQ_FROM_SERVER.leave_room_message(args)
	local roomid = args.roomid
	local uid = args.uid
	local username = args.username
	local exp = args.exp
	local roomid = args.roomid

	print("user", username, "uid", uid, "leave room", roomid)
end

function REQ_FROM_SERVER.talking_message(args)
	if args.to_uid == 0 then
		print("userid:", args.from_uid, "said:", args.content)
	else
		print("userid:", args.from_uid, "said:", args.content, "to userid:", args.to_uid)
	end
end

function REQ_FROM_SERVER.kick_message(args)
	local from_uid = args.from_uid
	local kicked_uid = args.kicked_uid

	print("user:", from_uid, "kicked the user:", kicked_uid, "out of room")
end

function REQ_FROM_SERVER.exp_message(args)
	local from_uid = args.from_uid
	local to_uid = args.to_uid
	local exp = args.exp

	print("user:", from_uid, "sended", exp, "exp to user:", to_uid)
end

function RESP_FROM_SERVER.login(args)
	local userinfo = args.userinfo

	local uid = userinfo.uid
	local username = userinfo.username
	local exp = userinfo.exp

	print("retrieved userinfo uid:", uid, "username:", username, "exp:", exp)
end

function RESP_FROM_SERVER.list_rooms(args)
	local rooms = args.rooms

	print("server have these rooms available")
	for _, v in ipairs(rooms) do
		local id = v.room_id
		local name = v.room_name
		local exp = v.room_exp
		local interval = v.room_exp_interval

		print("room_id:", id, "room_name:", name, "increase", exp, "exp each", interval, "seconds")
	end
end

function RESP_FROM_SERVER.enter_room(args)
	local result = args.result

	if result then
		print("enter room success")
	else
		print("enter room failed")
	end
end

function RESP_FROM_SERVER.list_members(args)
	local result = args.result
	local members = args.members

	if result then
		print("room members:")
		for _, v in ipairs(members) do
			print("username", v.username, "uid", v.uid, "exp", v.exp)
		end
	else
		print("you are not in any room")
	end
end

function RESP_FROM_SERVER.leave_room(args)
	local result = args.result

	if result then
		print("leave room success")
	else
		print("leave room failed, make sure you are in one room")
	end
end

function RESP_FROM_SERVER.say_public(args)
	print("talk result:", args.result)
end

function RESP_FROM_SERVER.say_private(args)
	print("talk result:", args.result)
end

function RESP_FROM_SERVER.kick(args)
	print("kicked the user?", args.result)
end

function RESP_FROM_SERVER.send_exp(args)
	print("send exp result:", args.result)
end

function mainloop(loginserver_host, loginserver_port, gameserver_host, gameserver_port, username, password)
	sockhelper.set_loginserver(loginserver_host, loginserver_port)
	sockhelper.set_gameserver(gameserver_host, gameserver_port)
	sockhelper.set_credential("server1", username, password)

	local servername
	local secret
	local uid

	--communicate with login server
	print("trying to login with login server")
	local ok, result = pcall(sockhelper.contact_loginserver)
	if not ok or not result or not result.ok then
		print("connect to login server failed")
		os.exit()
	else
		servername = result.server
		uid = result.uid
		secret = result.secret
	end

	--auth with game server
	local ok, result = pcall(sockhelper.contact_gameserver, servername, uid, index, secret)
	if not ok or not result then
		print("auth with game server failed")
		os.exit()
	end

	--[[
		kick userid
		sendexp to_userid points
		logout
	]]
	print("logined to game server")
	--chatting with game server
	while true do
		dispatch_package()
		local stdin = socket.readstdin()

		if stdin then
			local arr = string_utils.split_string(stdin)
			local cmd = arr[1]

			if cmd == "login" then
				send_request("login", {})
			elseif cmd == "listrooms" then
				send_request("list_rooms", {})
			elseif cmd == "enterroom" then
				if #arr ~= 2 then
					print("usage: enterroom roomid")
				else
					local roomid = tonumber(arr[2])
					send_request("enter_room", {roomid = roomid})
				end
			elseif cmd == "leaveroom" then
				send_request("leave_room", {})
			elseif cmd == "listmembers" then
				send_request("list_members", {})
			elseif cmd == "say" then
				if #arr < 2 then
					print("usage: say hello world")
				else
					table.remove(arr, 1)
					local content = table.concat(arr, " ")

					send_request("say_public", {content = content,})
				end
			elseif cmd == "sayto" then
				if #arr < 3 then
					print("usage: sayto userid hello")
				else
					table.remove(arr, 1)
					local uid = tonumber(arr[1])
					table.remove(arr, 1)
					local content = table.concat(arr, " ")

					send_request("say_private", {
						uid = uid,
						content = content,
					})
				end
			elseif cmd == "kick" then
				if #arr < 2 then
					print("usage: kick userid")
				else
					local uid = tonumber(arr[2])

					send_request("kick", {uid = uid})
				end
			elseif cmd == "sendexp" then
				if #arr < 3 then
					print("usage: sendexp userid exp")
				else
					local uid = tonumber(arr[2])
					local exp = tonumber(arr[3])

					send_request("send_exp", {
						uid = uid,
						exp = exp,
					})
				end
			elseif cmd == "logout" then
				send_request("logout", {})
			end
		else
			socket.usleep(100)
		end
	end	
end

local args_len = #arg

if args_len == 6 then
	loginserver_host = arg[1]
	loginserver_port = tonumber(arg[2])
	gameserver_host = arg[3]
	gameserver_port = tonumber(arg[4])

	username = arg[5]
	password = arg[6]
else
	print("usage:lua main.lua loginserver_host loginserver_port gameserver_host gameserver_port username password")
	os.exit()
end

mainloop(loginserver_host, loginserver_port, gameserver_host, gameserver_port, username, password)

