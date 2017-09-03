#!/usr/bin/lua5.2
local lgi = require 'lgi'
local GLib = lgi.GLib
local Gst = lgi.Gst
local log=lgi.log.domain'c test'
--local dh=require"dumphash"
--local pretty=require"pl.pretty"

local VIDEO_CAPS="video/x-raw,width=640,height=480,format=I420,framerate=25/1"
local PROBE_OK=Gst.PadProbeReturn.OK
local PROBE_REMOVE=Gst.PadProbeReturn.REMOVE
local PROBE_DROP=Gst.PadProbeReturn.DROP
local function block_probe_cb(pad, info)
	log.warning("pad blocked")
	log.warning(("pad %s:%s blocked"):format(pad.parent.name,pad.name))
	return PROBE_OK
end
local function app_update_filesink_location(app)
	local fn=("/var/tmp/test-%03d.mp4"):format(app.chunk_count)
	app.chunk_count=app.chunk_count+1
	log.warning(("Setting filesink to %s"):format(fn))
	app.filesink.location=fn
end
local function bus_cb(app,bus, message)
   if message.type.ERROR then
      log.warning('Error:', message:parse_error().message)
      app.loop:quit()
   elseif message.type.EOS then
      log.warning 'end of stream'
      --app.loop:quit()
   elseif message.type.STATE_CHANGED then
      local old, new, pending = message:parse_state_changed()
      log.warning(string.format('state changed: %s->%s:%s %s', old, new, pending,bus))
   elseif message.type.ELEMENT then
	log.warning 'message'
   elseif message.type.TAG then
      message:parse_tag():foreach(
	 function(list, tag)
	    log.warning(('tag: %s = %s'):format(tag, tostring(list:get(tag))))
	 end)
   end

   return true
end

function push_eos_thread(app)
	local peer=app.vrecq_src:get_peer()
	log.warning(("pusing eos event on pad %s"):format(peer))
end

local function stop_recording_cb(app)
	log.warning("stop recording")
	app.vrecq_src_probe_id=app.vrecq_src:add_probe(Gst.PadProbeType.BLOCK+Gst.PadProbeType.BUFFER,block_probe_cb,nil,nil)
	return false;
end

-- static GstPadProbeReturn
-- probe_drop_one_cb (GstPad * pad, GstPadProbeInfo * info, gpointer user_data)
-- {
--  RecordApp *app = user_data;
--  GstBuffer *buf = info->data;
local function probe_drop_one_cb(app,pad,info)
	app.buffer_count=app.buffer_count+1
	local buffer=info:get_buffer()
	local buffer_flags=buffer:get_flags()
  	-- if (app->buffer_count++ == 0) {
	for k,v in pairs(buffer:get_flags()) do
		log.warning(("%s:%s"):format(k,v))
	end
	if app.buffer_count==1 then
		log.warning"drop one buffer"
    		-- g_print ("Drop one buffer with ts %" GST_TIME_FORMAT "\n",
		--         GST_TIME_ARGS (GST_BUFFER_PTS (info->data)));
    		-- return GST_PAD_PROBE_DROP;
		return PROBE_DROP
	else
	--  } else {
	--    gboolean is_keyframe;
		if buffer_flags.DELTA_UNIT then
			log.warning"Waiting for keyframe"
			return PROBE_DROP
		else
			log.warning"Found keyframe"
			return PROBE_REMOVE
		end
	end
end
--[[
    is_keyframe = !GST_BUFFER_FLAG_IS_SET (buf, GST_BUFFER_FLAG_DELTA_UNIT);
    g_print ("Buffer with ts %" GST_TIME_FORMAT " (keyframe=%d)\n",
        GST_TIME_ARGS (GST_BUFFER_PTS (buf)), is_keyframe);

    if (is_keyframe) {
      g_print ("Letting buffer through and removing drop probe\n");
      return GST_PAD_PROBE_REMOVE;
    } else {
      g_print ("Dropping buffer, wait for a keyframe.\n");
      return GST_PAD_PROBE_DROP;
    }
  }
}
]]

local function start_recording_cb(app)
	log.warning("timeout, unblocking pad to start recording")
	app.buffer_count=0
	app.vrecq_src:add_probe(Gst.PadProbeType.BUFFER,function(...) return probe_drop_one_cb(app,...) end)
	app.vrecq_src:remove_probe(app.vrecq_src_probe_id)
	app.vrecq_src_probe_id=0
	GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 15, function() return stop_recording_cb(app) end)
	return false;
end

local function main()
	local app={}
	app.loop = GLib.MainLoop()
	local pipeline=Gst.parse_launch( "videotestsrc is-live=true ! ".. VIDEO_CAPS..
		" ! clockoverlay ! x264enc tune=zerolatency bitrate=8000 "..
		" ! queue name=vrecq ! mp4mux name=mux ! filesink async=false name=filesink",
	      nil)
	--pretty.dump((Gst.Pipeline:_resolve(true)))
	app.pipeline=pipeline
	print(pipeline)
	local vrecq=pipeline:get_by_name"vrecq"
	app.vrecq=vrecq
	print(vrecq)
	vrecq.max_size_time=3000000
	vrecq.max_size_bytes=0
	vrecq.max_size_buffers=0
	vrecq.leaky=2
	local vrecq_src=app.vrecq:get_static_pad"src"
	app.vrecq_src=vrecq_src
	print(vrecq_src)
	print(Gst.PadProbeType.BLOCK)
	local vrecq_src_probe_id=vrecq_src:add_probe(Gst.PadProbeType.BLOCK+Gst.PadProbeType.BUFFER,block_probe_cb)
	print(vrecq_src_probe_id)
	app.vrecq_src_probe_id=vrecq_src_probe_id
	app.chunk_count=0
	app.filesink=pipeline:get_by_name"filesink"
	print(app.filesink)
	app_update_filesink_location(app)
	app.muxer=pipeline:get_by_name"mux"
	pipeline.bus:add_watch(GLib.PRIORITY_DEFAULT, function(...) return bus_cb(app,...) end)
	pipeline.state='PLAYING'
	GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 15, function() return start_recording_cb(app) end)
	app.loop:run()
	pipeline.state='NULL'
end

main()	
