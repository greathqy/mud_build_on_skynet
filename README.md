# A complete mud-like game demo build on skynet
***
####Introduction:
	This is a simple but complete example project that demonstrate [skynet](https://github.com/cloudwu/skynet/) game framework's usage. It implements a multi room server, that many client can connect to this server, switch between rooms, talk in the room publicly or send private message to specific user privately. User will got exp in each room and can give exp to other user, the user have highest exp will be auto elected as the room manager, who has the power to kick other member out of the room. Hopes skynet will be much more prosperous.

## Features
* Login Server, Gate Server, Watchdog, Agent Architecture, All communication encoded with builtin sproto protocol
* modify loginserver and gateserver from \n separated protocol to 2 bytes length prefixed string
* login server auth with a third party URL to verify the token offered by client during login process, demostrates facebook, weibo login mode in today's game client
* use redis to collect log data from game server, and use crontab script transfer the log data from redis to it's final destination(crontab script not implemented)
* precreate agents to agent pool and periodically check if need create more.
* load user data from mysql and save user data to mysql periodically and when user away from keyboard or logout.

## Prerequisite
mysql server listen on 3306, root with empty password
create a database named: skynetdemo, and import skynetdemo.sql

redis server listen on 6379

LAMP enviroment, and make sure web/auth.php can visited as http://127.0.0.1/auth.php

## How To Test
git clone https://github.com/greathqy/mud_build_on_skynet.git

cd mud_build_on_skynet

git submodule update --init --recursive

cd skynet

make linux

modify config/config.game.dev to suit your enviroment

./skynet ../config/config.game.dev

cd 3rd/lua

./lua ../../../client/client.lua loginserver_host loginserver_port gameserver_host gameserver_port username password

then you can use these command to act with server:
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
***


# 基于skynet开发的MUD游戏风格的完整示例
#### 介绍:
	这是一个简单但是完整的项目，展示了[skynet](https://github.com/cloudwu/skynet/)框架的用法。这个项目实现了一个多房间服务器，多个客户端可以同时连接到这个服务器，在不同的房间中切换，在房间里公开发言或者单独向某个用户发送信息。玩家呆在房间里时可以获得经验值，经验值最多的用户将自动成为房间管理员获得踢其他用户出去的权限。希望skynet使用越来越广泛。	

## 特性
* 登陆服务器，网关服务器，看门狗，用户代理架构，通讯使用sproto协议
* 修改了登录服务器和网关服务器，不用\n分割的文本协议，而使用二字节头部指定长度的字符串
* 登陆服务器向第三方网关验证客户端提交来的token，模拟客户端通过facebook微博等方式登录的情形
* 使用redis搜集服务器日志，用crontab脚本将日志转移到其他地方存储(没实现crontab脚本)
* 使用一个agent池，预创建一批agent加速登录过程，并定期检查是否要补充
* 使用mysql存取用户数据，并对用户定期存档，或在离线和退出登录时自动存档

## 环境要求
mysql服务器监听于3306端口，空密码的root账户
创建一个叫skynetdemo的数据库，并导入skynetdemo.sql

监听于6379端口的redis服务器

LAMP环境, 确保web/auth.php能通过http://127.0.0.1/auth.php被访问到

## 测试使用
git clone https://github.com/greathqy/mud_build_on_skynet.git

cd mud_build_on_skynet

git submodule update --init --recursive

cd skynet

make linux

modify config/config.game.dev to suit your enviroment

./skynet ../config/config.game.dev

cd 3rd/lua

./lua ../../../client/client.lua loginserver_host loginserver_port gameserver_host gameserver_port username password

成功连接上后可以使用以下命令与服务器交互:
	
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


