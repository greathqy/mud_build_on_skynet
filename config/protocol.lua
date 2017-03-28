--[[
	client server protocol defination
]]
local sparser = require "sprotoparser"

local protocol = {}

local typedefs = [[
	.package {
		type 0 : integer
		session 1 : integer
	}
 
	.user {
		uid 0 : integer
		username 1 : string
		exp 2 : integer
	}

	.roominfo {
		room_id 0 : integer
		room_name 1 : string
		room_exp 2 : integer
		room_exp_interval 3 : integer
	}
]]

--message from client send to server
local client2server = [[
	#login to retrieve userinfo
	login 1 {
		request {
		}
		response {
			userinfo 0 : user
		}
	}

	#list rooms
	list_rooms 2 {
		request {
		}
		response {
			rooms 0 : *roominfo
		}
	}

	#enter specific room
	enter_room 3 {
		request {
			roomid 0 : integer
		}
		response {
			result 0 : boolean
		}
	}

	#list members in current room
	list_members 4 {
		request {
		}
		response {
			result 0 : boolean
			members 1 : *user
		}
	}

	#leave specific room
	leave_room 5 {
		request {
		}
		response {
			result 0 : boolean
		}
	}

	#talk publicly
	say_public 6 {
		request {
			content 0 : string
		}
		response {
			result 0 : boolean
		}
	}

	#talk to specific user
	say_private 7 {
		request {
			uid 0 : integer
			content 1 : string
		}
		response {
			result 0 : boolean
		}
	}

	#kick specific user out
	kick 8 {
		request {
			uid 1 : integer
		}
		response {
			result 0 : boolean
		}
	}

	#give exp to specific user
	send_exp 9 {
		request {
			uid 0 : integer
			exp 1 : integer
		}
		response {
			result 0 : boolean
		}
	}

	#logout from server
	logout 10 {
		request {
		}
	}
]]

--message from server push to client
local server2client = [[
	enter_room_message 1 {
		request {
			uid 0 : integer
			username 1 : string
			exp 2 : integer
			roomid 3 : integer
		}
	}
	leave_room_message 2 {
		request {
			uid 0 : integer
			username 1 : string
			roomid 3 : integer
		}
	}
	talking_message 3 {
		request {
			from_uid 0 : integer
			to_uid 1 : integer
			content 2 : string
		}
	}
	kick_message 4 {
		request {
			from_uid 0 : integer
			kicked_uid 1 : integer
		}
	}
	exp_message 5 {
		request {
			from_uid 0 : integer
			to_uid 1 : integer
			exp 2 : integer
		}
	}
]]

protocol.typedefs = sparser.parse(typedefs)
protocol.c2s = sparser.parse(typedefs .. client2server)
protocol.s2c = sparser.parse(typedefs .. server2client)

return protocol