--[[
	watchdog service, responsible for:
	manage agent pool 
	agent data periodically saving
	kick long time idle agents
]]
local skynet = require "skynet"
local netpack = require "netpack"

local logger = require "logger"

local CMD = {}
local SOCKET = {}

local gateservice
local loginservice

--agent free pool
local agentpool = {}
-- uid => {agent = xx, }
local user_agent = {}
local recycle_queue = {}
local recycled_agents = 0

local agentpool_min_size = skynet.getenv "watchdog_agentpool_min_size" or 10
local agent_bgsave_interval = skynet.getenv "watchdog_bgsave_interval" or 600
local agent_checkidle_interval = skynet.getenv "watchdog_check_idle_interval" or 60

agentpool_min_size = tonumber(agentpool_min_size)
agent_bgsave_interval = tonumber(agent_bgsave_interval)
agent_checkidle_interval = tonumber(agent_checkidle_interval)

function logout_user(uid)
	local agent = user_agent[uid]

	if agent then
		--logout from gateserver, gateserver then informs loginserver to logout
		skynet.call(gateservice, "lua", "logout", uid)

		local can_recycle = skynet.call(agent, "lua", "logout")
		if can_recycle then
			skynet.call(agent, "lua", "persistent")
			skynet.call(agent, "lua", "recycle")

			user_agent[uid] = nil
			agentpool[#agentpool + 1] = agent

			recycled_agents = recycled_agents + 1
		end
	end
end

local function precreate_agents_to_freepool()
	if #agentpool < agentpool_min_size then
		local need_create = agentpool_min_size - #agentpool
		logger.info("watchdog", "precreate", need_create, "agents in freepool")
		for i = 1, need_create do
			local agent = skynet.newservice("agent", skynet.self())
			agentpool[#agentpool + 1] = agent
		end
	end
end

local function check_idle_agents()
	logger.debug("watchdog", "let agent get chance to report recycleable")

	for _, agent in pairs(user_agent) do
		skynet.call(agent, "lua", "check_idle")
	end
end

local function bgsave_agent_state()
	logger.debug("watchdog", "let agent do state persistent when necessary")

	for _, agent in pairs(user_agent) do
		skynet.call(agent, "lua", "persistent")
	end
end

local check_idle_accumulated = 0
local persistent_accumulated = 0
local recycle_accumulated = 0

local function watchdog_timer()
	precreate_agents_to_freepool()

	check_idle_accumulated = check_idle_accumulated + 1
	persistent_accumulated = persistent_accumulated + 1
	recycle_accumulated = recycle_accumulated + 1

	if check_idle_accumulated >= agent_checkidle_interval then
		check_idle_accumulated = 0
		
		check_idle_agents()
	end

	if persistent_accumulated >= agent_bgsave_interval then
		persistent_accumulated = 0

		bgsave_agent_state()
	end

	if recycle_accumulated >= 60 then
		recycle_accumulated = 0

		if #recycle_queue > 0 then
			for _, item in pairs(recycle_queue) do
				local uid = item.uid
				logout_user(uid)
			end

			recycle_queue = {}
		end
	end

	skynet.timeout(100, watchdog_timer)
end

function SOCKET.data(agent, msg)
	logger.error("watchdog", "unexpected receiving msg of agent", agent)
end

function CMD.start(conf)
	gateservice = conf.gateservice
	loginservice = conf.loginservice

	skynet.call(gateservice, "lua", "open", conf)
end

function CMD.recycle_agent(uid, agent)
	recycle_queue[#recycle_queue + 1] = {
		uid = uid,
		agent = agent,
	}
end

function CMD.alloc_agent(uid)
	local agent 
	if user_agent[uid] then
		logger.debug("watchdog", "user uid", uid, "is online, ignore realloc")
		agent = user_agent[uid]
	else
		logger.debug("watchdog", "alloc agent for user uid", uid)
		if #agentpool > 0 then
			agent = table.remove(agentpool)
		else
			agent = skynet.newservice("agent", skynet.self())
		end

		user_agent[uid] = agent
			
		local init = skynet.call(agent, "lua", "load_user_data", uid)

		if not init then
			logger.debug("agent", "agent init failed and must recycle, add to free pool")
			agentpool[#agentpool + 1] = agent

			agent = nil
			user_agent[uid] = nil
		end
	end

	return agent
end

function CMD.query_service_status()
	local recycled_count = recycled_agents
	local total_online = 0

	for _, v in pairs(user_agent) do
		total_online = total_online + 1
	end

	local state = {
		online_users = total_online,
		agentpool_size = #agentpool,
		recycled_agents = recycled_count,
	}

	return state
end

--[[
	logout user, notify gate & login service to logout
	gate service, agent may call this method
]]
function CMD.logout(uid)
	logger.debug("watchdog", "uid", uid, "logout")
	logout_user(uid)

	return true
end

--client away from keyboard
function CMD.afk(uid, agent)
	logger.debug("watchdog", "uid", uid, "agent", agent, "away from keyboard")
	skynet.call(agent, "lua", "afk")
end

function CMD.client_auth_completed(agent, fd, ip)
	skynet.call(agent, "lua", "associate_fd_ip", fd, ip)
end

skynet.start(function()
	skynet.dispatch("lua", function(session, source, cmd, subcmd, ...)
		if cmd == "socket" then
			local f = SOCKET[subcmd]
			f(...)
		else
			local f = assert(CMD[cmd])

			skynet.ret(skynet.pack(f(subcmd, ...)))
		end
	end)

	precreate_agents_to_freepool()

	skynet.timeout(100, watchdog_timer)
end)
