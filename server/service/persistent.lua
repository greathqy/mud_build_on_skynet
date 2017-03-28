--[[
	persistent service, responsible for load and save user data
	use a queue to mimic async saving
]]

local skynet = require "skynet"
local logger = require "logger"
local mysql = require "mysql"
local socketchannel = require "socketchannel"

local datetime_utils = require "datetime_utils"

local persistent_types = {
	save_user_data = 'save_user_data',
}

local mode = ...

if mode == "slave" then
	local mysql_host = skynet.getenv "mysql_host" or ""
	local mysql_port = tonumber(skynet.getenv "mysql_port" or 3306)
	local mysql_username = skynet.getenv "mysql_username" or ""
	local mysql_password = skynet.getenv "mysql_password" or ""
	local mysql_database = skynet.getenv "mysql_database" or ""

	local db
	local master

	local function dbquery(sql, multirows)
		local res = db:query(sql)
		local results = {}

		if res['errcode'] then
			--error happen
			logger.error("persistent", "mysql error", sql)
			return nil
		end

		if multirows then
			--need return multiple rows
			if #res >= 1 then
				for k, v in pairs(res) do
					results[#results + 1] = v
				end
			else
				results = false
			end
		else
			--need exact one row
			if res[1] then
				results = res[1]
			else
				results = false
			end
		end

		-- nil means error, false means empty data

		return results
	end

	local CMD = {}
	local PERSISTENT_HANDLER = {}

	function PERSISTENT_HANDLER.save_user_data(task)
		local uid = task.uid
		local userdata = task.data

		local sql, res

		local exp = userdata.exp
		local now = datetime_utils.get_current_datetime()

		local fmt = [===[
			update users set exp = %d, updated = '%s' where id = %d limit 1
		]===]
		sql = string.format(fmt, exp, now, uid)
		--logger.debug("persistentd", "execute sql:", sql)

		res = db:query(sql)

		return true
	end

	function CMD.do_persistent(taskid, task)
		local tasktype = task.type
		if PERSISTENT_HANDLER[tasktype] then
			local f = PERSISTENT_HANDLER[tasktype]
			local result = f(task)

			if result then
				skynet.send(master, "lua", "finish_task", taskid)
			end
		end
	end

	function CMD.load_user_data(uid)
		logger.debug("persistent_slave", "load_user_data uid", uid)
		local uid = tonumber(uid)

		local userdata = {}
		local sql, row

		sql = string.format("select * from users where id = %d limit 1", uid)
		row = dbquery(sql)

		if row == false then
			logger.error("persistent_slave", "try to load non-exists user uid", uid)
			return false
		end

		local uid = row['id']
		local username = row['username']
		local exp = row['exp']
		local created = row['created']
		local updated = row['updated']

		userdata = {
			uid = uid,
			username = username,
			exp = exp,
			created = created,
			updated = updated,
		}

		return userdata
	end

	function CMD.init(persistent_master)
		master = persistent_master

		return true
	end

	skynet.start(function()
		skynet.dispatch("lua", function(_, _, cmd, ...) 
			local f = assert(CMD[cmd])
			local result = f(...)

			if result ~= nil then
				skynet.ret(skynet.pack(result))
			end
		end)

		local function on_connected(db)
			db:query("set names utf8")
		end

		local ok
		ok, db = pcall(mysql.connect, {
			host = mysql_host,
			port = mysql_port,
			database = mysql_database,
			user = mysql_username,
			password = mysql_password,
			max_packet_size = 1024 * 1024,
			on_connect = on_connected
		})

		if not ok or not db then
			logger.error("persistent_slave", "connect to mysql failed")
		end

		--keep mysql alive
		skynet.fork(function()
			while true do
				if db and db ~= socketchannel.error then
					local sql = string.format("select %s", skynet.time())
					db:query(sql)
				end

				--sleep 60 seconds
				skynet.sleep(6000)
			end
		end)
	end)

else
	local slaves = {}
	local save_queue = {} --taskid -> taskdata
	--[[
		save task defination:
		{
			taskid = xxx
			type = tasktype,
			uid = xx, who's data
			data = xxx, data
		}
	]]

	-- uid -> taskid
	local save_queue_uid2taskid = {}
	-- taskid -> uid
	local save_queue_taskid2uid = {}

	local function is_userdata_pending_persistent(uid)
		if save_queue_uid2taskid[uid] then
			return save_queue_uid2taskid[uid]
		end

		return false
	end
	
	local balance = 1
	local taskid = 0

	local function gettaskid()
		local id = taskid

		taskid = taskid + 1

		return id
	end

	local function getslave()
		local slave = slaves[balance]

		balance = balance + 1

		if balance > #slaves then
			balance = 1
		end

		return slave
	end

	local CMD = {}

	function CMD.load_user_data(cmd, uid)
		logger.debug("persistent", "load_user_data uid", uid)

		local result 

		local taskid = is_userdata_pending_persistent(uid)
		if taskid then
			logger.debug("persistent_master", "uid", uid, "data in save queue, load from queue instead of database")
			local data = save_queue[taskid]
			result = data.data
		else
			local slave = getslave()
			result = skynet.call(slave, "lua", cmd, uid)
		end

		return result
	end

	function CMD.save_user_data(cmd, uid, userdata)
		local taskid = save_queue_uid2taskid[uid]
		local newtaskid = gettaskid()

		if taskid then
			logger.debug("persistent_master", "overwrite obsolete task id", taskid)
			save_queue_uid2taskid[uid] = nil
			save_queue_taskid2uid[taskid] =  nil

			save_queue[taskid] = nil
		end

		local task = {
			taskid = newtaskid,
			type = persistent_types.save_user_data,
			uid = uid,
			data = userdata,
			sended_to_slave = false,
		}

		save_queue[newtaskid] = task
		save_queue_uid2taskid[uid] = newtaskid
		save_queue_taskid2uid[newtaskid] = uid
	end

	local function process_task_queue()
		for taskid, task in pairs(save_queue) do
			if not task.sended_to_slave then
				local slave = getslave()
				skynet.send(slave, "lua", "do_persistent", taskid, task)

				task.sended_to_slave = true
			end
		end

		skynet.timeout(100, process_task_queue)
	end

	--called by persistent slave
	function CMD.finish_task(cmd, taskid)
		local task = save_queue[taskid]

		if task then
			save_queue[taskid] = nil

			local uid = save_queue_taskid2uid[taskid]
			if uid then
				save_queue_taskid2uid[taskid] = nil
				save_queue_uid2taskid[uid] = nil
			end
		end
	end

	function CMD.query_service_status(cmd)
		local state = {
			pending_tasks = 0,
			finished_tasks = 0,
		}

		local queue_size = 0
		for _, _ in pairs(save_queue) do
			queue_size = queue_size + 1
		end

		state.finished_tasks = taskid
		state.pending_tasks = queue_size

		return state
	end

	skynet.start(function()
		local slavesize = skynet.getenv("persistent_slave_poolsize") or 8
		slavesize = tonumber(slavesize)

		for i = 1, slavesize do
			slave = skynet.newservice(SERVICE_NAME, "slave")
			skynet.call(slave, "lua", "init", skynet.self())

			slaves[#slaves + 1] = slave
		end

		skynet.dispatch("lua", function(session, source, cmd, ...)
			local f = assert(CMD[cmd])

			local ret = f(cmd, ...)
			if ret ~= nil then
				skynet.ret(skynet.pack(ret))
			end
		end)

		skynet.timeout(100, process_task_queue)
	end)
end
