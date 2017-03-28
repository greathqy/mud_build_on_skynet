--[[
	room service
]]

local skynet = require "skynet"

local logger = require "logger"

local roomconf = require "roomconf"

local data = {}
local timers = {}
local user2room = {}

local CMD = {}

local function ontimer(id)
	--logger.debug("room", "timer", id, "fired")

	local room = data[id]
	local members = room.members

	if #members > 0 then
		for _, v in pairs(members) do
			local userinfo = v.userinfo
			local agent = v.agent

			local exp = userinfo.exp
			exp = exp + roomconf[id].exp
			userinfo.exp = exp

			local change = {
				exp = exp,
				added = roomconf[id].exp,
			}

			skynet.call(agent, "lua", "notify_exp_change", change)
		end
	end
end

local function get_manager_of_room(id)
	local highest_exp = 0
	local manager
	local room = data[id]

	for _, v in ipairs(room.members) do
		local exp = v.userinfo.exp

		if exp > highest_exp then
			highest_exp = exp
			manager = v
		end
	end

	return manager
end

local function initrooms()
	for _, v in ipairs(roomconf) do
		local id = v.id
		local name = v.name
		local exp = v.exp
		local expinterval = v.expinterval

		local room = {
			members = {},
			info = {
				id = id,
				name = name,
				exp = exp,
				interval = interval,
			}
		}

		data[id] = room

		--set timer
		local timername = "timer" .. id
		timers[timername] = function()
			ontimer(id)

			skynet.timeout(expinterval * 100, timers[timername])
		end 

		skynet.timeout(expinterval * 100, timers[timername])
	end
end

function CMD.enter_room(roomid, userdata, agent)
	local member = {
		agent = agent,
		userinfo = userdata,
	}

	data[roomid].members[#data[roomid].members + 1] = member 
	user2room[userdata.uid] = roomid	

	--send notify to each member in room
	for _, v in pairs(data[roomid].members) do
		local agent = v.agent

		skynet.call(agent, "lua", "notify_user_enter", roomid, userdata)
	end

	return true
end

function CMD.list_members(uid)
	local members = {}
	local roomid = user2room[uid]

	if not roomid then
		--not in room
		members = nil
	else
		local room = data[roomid]
		for _, v in pairs(room.members) do
			local member = {
				uid = v.userinfo.uid,
				username = v.userinfo.username,
				exp = v.userinfo.exp,
			}

			members[#members + 1] = member
		end
	end

	return members
end

function CMD.leave_room(userid)
	local leaved = true
	local roomid = user2room[userid]

	if not roomid then
		leaved = false
	else
		local room = data[roomid]
		local index
		local leaved_member

		for seq, member in ipairs(data[roomid].members) do
			if member.userinfo.uid == userid then
				index = seq
				leaved_member = member
				break
			end
		end

		if index then
			--notify member leave
			for _, member in pairs(data[roomid].members) do
				local agent = member.agent

				skynet.call(agent, "lua", "notify_user_leave", roomid, leaved_member.userinfo)
			end

			table.remove(data[roomid].members, index)
			user2room[userid] = nil
		end
	end

	return leaved
end

function CMD.say_public(userid, content)
	local result
	local roomid = user2room[userid]

	if not roomid then
		result = false
	else
		result = true

		local room = data[roomid]
		for _, member in pairs(room.members) do
			local agent = member.agent

			skynet.call(agent, "lua", "notify_talking_message", {
				from_uid = userid,
				to_uid = 0,
				content = content,
			})
		end
	end

	return result
end

function CMD.say_private(userid, touid, content)
	local result = false
	local roomid = user2room[userid]

	if roomid then
		local member
		local room = data[roomid]

		for _, v in ipairs(room.members) do
			if v.userinfo.uid == touid then
				member = v
				break
			end
		end

		if member then
			local agent = member.agent

			skynet.call(agent, "lua", "notify_talking_message", {
				from_uid = userid,
				to_uid = touid,
				content = content,
			})

			result = true
		end
	end

	return result
end

function CMD.kick(userid, kickuid)
	local result = false

	local roomid = user2room[userid]
	if roomid and userid ~= kickuid then
		local manager = get_manager_of_room(roomid)

		if manager and manager.userinfo.uid == userid then
			local kick_user_roomid = user2room[kickuid]

			if kick_user_roomid == roomid then
				result = true

				local index
				local kicked_member

				for k, v in ipairs(data[roomid].members) do
					if v.userinfo.uid == kickuid then
						index = k
						kicked_member = v
						break
					end
				end

				if kicked_member then
					for k, v in ipairs(data[roomid].members) do
						local agent = v.agent

						skynet.call(agent, "lua", "notify_user_leave", roomid, kicked_member.userinfo)
						skynet.call(agent, "lua", "notify_kick_message", {
							from_uid = userid,
							kicked_uid = kickuid,
						})
					end

					table.remove(data[roomid].members, index)
					user2room[kickuid] = nil
				end
			end
		end
	end

	return result
end

function CMD.send_exp(userid, touid, exp)
	local result = false

	local fromuser_roomid = user2room[userid]
	local touser_roomid = user2room[touid]
	local from_member, to_member

	if fromuser_roomid and touser_roomid and fromuser_roomid == touser_roomid and userid ~= touid then
		local from_member, to_member

		for _, v in ipairs(data[fromuser_roomid].members) do
			if v.userinfo.uid == userid then
				from_member = v
			end
			if v.userinfo.uid == touid then
				to_member = v
			end

			if from_member and to_member then
				break
			end
		end

		if from_member.userinfo.exp >= exp then
			from_member.userinfo.exp = from_member.userinfo.exp - exp
			to_member.userinfo.exp = to_member.userinfo.exp + exp

			skynet.call(from_member.agent, "lua", "notify_exp_change", {added = -exp})
			skynet.call(to_member.agent, "lua", "notify_exp_change", {added = exp})

			for _, v in ipairs(data[fromuser_roomid].members) do
				local agent = v.agent

				local data = {
					from_uid = userid,
					to_uid = touid,
					exp = exp,
				}
				skynet.call(agent, "lua", "notify_exp_message", data)
			end

			result = true
		end
	end

	return result
end

skynet.start(function()
	skynet.dispatch("lua", function(session, source, cmd, ...)
		local f = assert(CMD[cmd])

		skynet.ret(skynet.pack(f(...)))
	end)

	initrooms()
end)