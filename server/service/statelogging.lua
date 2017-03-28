--[[
	log system important data change and event
	queue the data received and save to redis server, then can use cronjob tranfser from redis to other place
]]

local skynet = require "skynet"
local redis = require "redis"
local logger = require "logger"
local datetime_utils = require "datetime_utils"

local bson = require "bson"

local redis_host = skynet.getenv "redis_host" or "127.0.0.1"
local redis_logging_queuename = skynet.getenv "redis_logging_queuename" or "gamelogs"
local redis_port = skynet.getenv "redis_port" or 6379
redis_port = tonumber(redis_port)

local conf = {
	host = redis_host,
	port = redis_port,
	db = 0,
}

local logs_queue_name = redis_logging_queuename
local db

local CMD = {}

local save_queue = {}

local function push(key, val)
	local encoded = bson.encode(val)

	db:rpush(key, encoded)
end

local function persistent(tablename, op, args, primarykey)
	assert(op == "insert" or op == "update", "statelogging invalid op: " .. op)

	if op == "update" then
		assert(primarykey ~= nil, "statelogging missing primary key when update")
	end

	local data = {
		tbl = tablename,
		op = op,
		args = args,
		key = primarykey,
	}

	local ok = pcall(push, logs_queue_name, data)

	if not ok then
		save_queue[#save_queue + 1] = data
	end
end

function CMD.log_system_activity(uid, eventlabel, eventdetail)
	local created = datetime_utils.get_current_datetime()

	local tablename = "activity_logs"
	local operation = "insert"

	local args = {
		uid = uid,
		eventlabel = eventlabel,
		eventdetail = eventdetail,
		created = created,
	}

	persistent(tablename, operation, args)
end

function CMD.log_exp_change(uid, logtype, value)
	local created = datetime_utils.get_current_datetime()

	local tablename = "exp_logs"
	local operation = "insert"

	local args = {
		['uid'] = uid,
		['type'] = logtype,
		['value'] = value,
		['created'] = created,
	}

	persistent(tablename, operation, args)
end

function CMD.log_user_login(uid, ip)
	local login_datetime = datetime_utils.get_current_datetime()

	local tablename = "login_logs"
	local operation = "insert"

	local args = {
		uid = uid,
		login_datetime = login_datetime,
		login_ip = ip,
	}

	persistent(tablename, operation, args)
end

function CMD.query_service_status()
	local state = {
		pending_logs = 0,
	}

	local pending_count = 0
	for _, _ in pairs(save_queue) do
		pending_count = pending_count + 1
	end

	state.pending_logs = pending_count

	return state
end

local function retry_queued_logs()
	while true do
		if #save_queue > 0 then
			local item = table.remove(save_queue)

			--save, if failed append to save_queue again
			local ok = pcall(push, logs_queue_name, item)
			if not ok then
				save_queue[#save_queue + 1] = item

				skynet.sleep(1000)
			end
		else
			--sleep x seconds
			skynet.sleep(1000)
		end
	end
end

skynet.start(function()
	db = redis.connect(conf)

	skynet.fork(retry_queued_logs)

	skynet.dispatch("lua", function(session, source, cmd, ...)
		local f = assert(CMD[cmd])
		local result = f(...)

		if result then
			skynet.ret(skynet.pack(result))
		end
	end)
end)
