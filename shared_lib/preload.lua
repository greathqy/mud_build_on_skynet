--[[
	preload config
]]
math.randomseed(os.time())

package.path = "../shared_lib/?.lua;" .. package.path
package.path = "../server/lib/?.lua;" .. package.path
package.path = "../config/?.lua;" .. package.path