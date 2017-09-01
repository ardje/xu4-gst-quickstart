local M={}
local lgi = require 'lgi'
local GLib = lgi.GLib
local Gst = lgi.Gst
local log=lgi.log.domain'encodertest'

--local main_loop = GLib.MainLoop()
local web={}

local function bus_callback(_, message)
   if message.type.ERROR then
      log.warning('Error:', message:parse_error().message)
      M.app:quit()
   elseif message.type.EOS then
      log.warning 'end of stream'
      M.app:quit()
   elseif message.type.STATE_CHANGED then
      local old, new, pending = message:parse_state_changed()
      log.warning(string.format('state changed: %s->%s:%s', old, new, pending))
   elseif message.type.TAG then
      message:parse_tag():foreach(
	 function(list, tag)
	    log.warning(('tag: %s = %s'):format(tag, tostring(list:get(tag))))
	 end)
   else
	    log.warning("bus callback")
   end

   return true
end


function M:setup(app,server)
	self.app=app
	local pipeline = Gst.Pipeline.new('encodingpipe')
	self.pipeline=pipeline

	-- v4l2src do-timestamp=true device=$DEVICE num-buffers=1000 
	-- video/x-raw, format=$FORMAT,framerate=60/1, width=$width, height=$height

	log.warning("create first element")
	local src=Gst.ElementFactory.make('v4l2src','grabber')
	src.do_timestamp=true
	src.device="/dev/video0"
	src.num_buffers=1000
	pipeline:add(src)
	local srcfilter=Gst.ElementFactory.make('capsfilter','srcfilter')
	srcfilter.caps=Gst.caps_from_string"video/x-raw, format=YUY2,framerate=60/1, width=1280, height=720"
	pipeline:add(srcfilter)
	src:link(srcfilter)

	-- colorspace
	local csp = Gst.ElementFactory.make('v4l2video30convert','colorspace')
	pipeline:add(csp)
	srcfilter:link(csp)
	local cspfilter=Gst.ElementFactory.make('capsfilter','cspfilter')
	cspfilter.caps=Gst.caps_from_string"video/x-raw,format=NV12,width=1280,height=720"
	pipeline:add(cspfilter)
	csp:link(cspfilter)

	-- Encoder
	--	${ENCODER} extra-controls="encode,h264_level=10,h264_profile=4,frame_level_rate_control_enable=1,video_bitrate=4194304" 
	local encoder=Gst.ElementFactory.make('v4l2video11h264enc','encode')
	encoder.extra_controls=Gst.structure_from_string"encode,h264_level=10,h264_profile=4,frame_level_rate_control_enable=1,video_bitrate=4194304"
	pipeline:add(encoder)
	cspfilter:link(encoder)

	--	h264parse config-interval=2 ! \
	local parser=Gst.ElementFactory.make('h264parse','parser')
	parser.config_interval=2
	pipeline:add(parser)
	encoder:link(parser)

	local mux=Gst.ElementFactory.make('mp4mux','mux')
	mux.fragment_duration=10000
	pipeline:add(mux)
	parser:link(mux)


	-- filesink location=$FN
	local sink=Gst.ElementFactory.make('filesink','sink')
	sink.location="test.mp4"
	pipeline:add(sink)
	mux:link(sink)

	--pipeline:add_many(src,srcfilter,csp,cspfilter,encoder,parser,mux,sink)
	--src:link_many(colorspace,encoder,parser,mux,sink)
	--play.uri = 'http://www.cybertechmedia.com/samples/raycharles.mov'
	pipeline.bus:add_watch(GLib.PRIORITY_DEFAULT, bus_callback)
	server:add_handler('/recorder', function(s, msg, path, query, ctx) -- luacheck: no unused args
		if web[path] then
			return web[path](M,s,msg,path,query,ctx)
		else
			msg.status_code = 404
			msg.response_body:complete()
		end
	end)
end
function M:pause()
	self.pipeline.state='PAUSED'
end
function M:unpause()
	self.pipeline.state='PLAYING'
end
function M:cleanup()
	self.pipeline.state='NULL'
end
web["/recorder/pause"]=function (r,s,msg,path,query,ctx) -- luacheck: no unused args
	M:pause()
	log.warning("pause")
	msg.status_code=200
	msg.response_body:complete()
end
web["/recorder/unpause"]=function(r,s,msg,path,query,ctx) -- luacheck: no unused args
	M:unpause()
	log.warning("unpause")
	msg.status_code=200
	msg.response_body:complete()
end
web["/recorder/cleanup"]=function(r,s,msg,path,query,ctx) -- luacheck: no unused args
	M:cleanup()
	log.warning("cleanup")
	msg.status_code=200
	msg.response_body:complete()
end
return M
