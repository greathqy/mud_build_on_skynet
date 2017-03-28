--[[
	interface to room service
]]

local skynet = require "skynet"

local roomd

local libroom = {}

function libroom.enter_room(roomid, userdata, agent)
	return skynet.call(roomd, "lua", "enter_room", roomid, userdata, agent)
end

function libroom.list_members(uid)
	return skynet.call(roomd, "lua", "list_members", uid)
end

function libroom.leave_room(userid)
	return skynet.call(roomd, "lua", "leave_room", userid)
end

function libroom.say_public(userid, content)
	return skynet.call(roomd, "lua", "say_public", userid, content)
end

function libroom.say_private(userid, touid, content)
	return skynet.call(roomd, "lua", "say_private", userid, touid, content)
end

function libroom.kick(userid, kickuid)
	return skynet.call(roomd, "lua", "kick", userid, kickuid)
end

function libroom.send_exp(userid, touid, exp)
	return skynet.call(roomd, "lua", "send_exp", userid, touid, exp)
end

local function init()
	roomd = skynet.uniqueservice "room"
end

skynet.init(init)

return libroom