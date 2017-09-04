local M={}
local lgi = require 'lgi'
local GLib = lgi.GLib
local Gst = lgi.Gst
local log=lgi.log.domain'encodertest'

--local main_loop = GLib.MainLoop()
local web={}

local PROBE_OK=Gst.PadProbeReturn.OK
local PROBE_REMOVE=Gst.PadProbeReturn.REMOVE
local PROBE_DROP=Gst.PadProbeReturn.DROP
local PROBET_BLOCK=Gst.PadProbeType.BLOCK
local PROBET_BUFFER=Gst.PadProbeType.BUFFER

local function wrap(first,func)
	if type(func) == "string" then
		func=first[func]
	end
	return function(...) return func(first,...) end
end
function M:block_probe(pad, _)
	log.warning("pad blocked")
	log.warning(("pad %s:%s blocked"):format(pad.parent.name,pad.name))
	return PROBE_OK
end

function M:drop_one_probe(pad,info)
	self.buffer_count=self.buffer_count+1
	local buffer=info:get_buffer()
	local buffer_flags=buffer:get_flags()
	if self.buffer_count==1 then
		log.warning("drop one buffer: %d",buffer.pts)
    		-- g_print ("Drop one buffer with ts %" GST_TIME_FORMAT "\n",
		--         GST_TIME_ARGS (GST_BUFFER_PTS (info->data)));
    		-- return GST_PAD_PROBE_DROP;
		return PROBE_DROP
	else
	--  } else {
	--    gboolean is_keyframe;
		if buffer_flags.DELTA_UNIT then
			--log.warning"Waiting for keyframe"
			return PROBE_DROP
		else
			log.warning"Found keyframe"
			return PROBE_REMOVE
		end
	end
end


function M:update_filename()
	self.chunk_count=(self.chunk_count or -1) +1
	local fn=("/var/tmp/test-%03d.mp4"):format(self.chunk_count)
	log.warning(("Setting sink to %s"):format(fn))
	self.sink.location=fn
end

function M:bus_callback(_, message)
	if message.type.ERROR then
		log.warning('Error:', message:parse_error().message)
		self.app:quit()
	elseif message.type.EOS then
		log.warning 'end of stream'
		self.sink.state='NULL'
		self.mux.state='NULL'
		self:update_filename()
		self.sink.state='PLAYING'
		self.mux.state='PLAYING'
	--M.app:quit()
	elseif message.type.STATE_CHANGED then
		local old, new, pending = message:parse_state_changed()
			log.warning(string.format('state changed: %s->%s:%s', old, new, pending))
	elseif message.type.TAG then
			message:parse_tag():foreach(
				function(list, tag)
				log.warning(('tag: %s = %s'):format(tag, tostring(list:get(tag))))
			end)
	end
	return true
end

function M:block()
	self.vrecq_src_probe_id=self.vrecq_src:add_probe(PROBET_BLOCK+PROBET_BUFFER,wrap(self,"block_probe"))
end

function M:setup(app,server)
	self.app=app
	local me=self
	local pipeline = Gst.parse_launch(
		"v4l2src do-timestamp=true \z
		! video/x-raw, format=YUY2,framerate=60/1, width=1280, height=720 \z
		! v4l2video30convert \z
		! video/x-raw,format=NV12,width=1280,height=72 \z
		! v4l2video11h264enc extra-contols=\"encode,h264_level=10,h264_profile=4,frame_level_rate_control_enable=1,video_bitrate=4194304\" \z
		! h264parse \z
		! queue name=vrecq ! mp4mux name=mux ! filesink async=false name=filesink",
	      nil)
		
	self.pipeline=pipeline

	local vrecq=pipeline:get_by_name"vrecq"
	self.vrecq=vrecq
	print(vrecq)
	vrecq.max_size_time=3000000
	vrecq.max_size_bytes=0
	vrecq.max_size_buffers=0
	vrecq.leaky=2
	self.vrecq_src=vrecq:get_static_pad"src"
	self:block()
	self.chunk_count=0
	self.sink=pipeline:get_by_name"filesink"
	self:update_filename()
	self.mux=pipeline:get_by_name"mux"
	pipeline.bus:add_watch(GLib.PRIORITY_DEFAULT, wrap(self,"bus_callback"))
	pipeline.state='PLAYING'
	--pipeline.message_forward = true
	server:add_handler('/recorder', function(s, msg, path, query, ctx) -- luacheck: no unused args
		if web[path] then
			return web[path](me,s,msg,path,query,ctx)
		else
			msg.status_code = 404
			msg.response_body:complete()
		end
	end)
end

function M:start()
	if not self.recording then
		log.warning("start recording")
		self.buffer_count=0
		self.vrecq_src:add_probe(PROBET_BUFFER,wrap(self,"drop_one_probe"))
		self.vrecq_src:remove_probe(self.vrecq_src_probe_id)
		self.vrecq_src_probe_id=0
		self.recording=true
	end
	return false;
end

function M:push_eos()
	local peer=self.vrecq_src:get_peer()
	log.warning(("pushing eos event on pad %s:%s"):format(peer.parent.name,peer.name))
	self.pipeline.message_forward=true
	peer:send_event(Gst.Event.new_eos())
end
function M:stop()
	if self.recording then
		log.warning("stop recording")
		self:block()
		-- maybe we should push_eos after the block probe reports blocked?
		self:push_eos()
		self.recording=false
	end
end
function M:cleanup()
	self.pipeline.state='NULL'
end
web["/recorder/stop"]=function(r,s,msg,path,query,ctx) -- luacheck: no unused args
	M:stop()
	log.warning("stop")
	msg.status_code=200
	msg.response_body:complete()
	return true
end
web["/recorder/start"]=function(r,s,msg,path,query,ctx) -- luacheck: no unused args
	M:start()
	log.warning("stop")
	msg.status_code=200
	msg.response_body:complete()
	return true
end
return M
