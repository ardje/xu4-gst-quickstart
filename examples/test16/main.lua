#! /usr/bin/env lua
-- copied and adjusted from lua-lgi-dev soupsrv.lua
--
-- Sample server using libsoup library.  Listens on 1080 port and serves
-- local files from current directory.  Allows to be terminated by query
-- for /quit file (i.e. curl http://localhost:1080/quit)
--

local lgi = require 'lgi'
--local GLib = lgi.GLib
local Gio = lgi.Gio
local Soup = lgi.Soup

local recorder=require"recorder"

local app = Gio.Application { application_id = 'org.lgi.soupsvr' }
function app:on_activate() -- luacheck: no unused args
   app:hold()

   local server = Soup.Server { port = 1090 }

   -- Set up quit handler.
   server:add_handler('/quit', function(s, msg, path, query, ctx) -- luacheck: no unused args
      msg.status_code = 200
      msg.response_body:complete()
      s:quit()
      app:release()
   end)
   server:add_handler('/recorder', function(s, msg, path, query, ctx) -- luacheck: no unused args
      msg.status_code = 200
      msg.response_body:complete()
      s:quit()
      app:release()
   end)

   -- Start the server running asynchronously.
   server:run_async()
   recorder:setup(self,server)
end

app:run { arg[0], ... }
recorder:cleanup()
