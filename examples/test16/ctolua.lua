#!/usr/bin/lua5.2
local lgi = require 'lgi'
local GLib = lgi.GLib
local Gst = lgi.Gst
local log=lgi.log.domain'c test'
local main_loop = GLib.MainLoop()
--local dh=require"dumphash"
--local pretty=require"pl.pretty"

local VIDEO_CAPS="video/x-raw,width=640,height=480,format=I420,framerate=25/1"

local function block_probe_cb(pad, info)
	log.warning(("pad %s blocked"):format(pad))
	return true
end
local function app_update_filesink_location(app)
	local fn=("/var/tmp/test-%03d.mp4"):format(app.chunk_count)
	app.chunk_count=app.chunk_count+1
	log.warning(("Setting filesink to %s"):format(fn))
	app.filesink.location=fn
end
local function bus_cb(_, message,app)
   if message.type.ERROR then
      log.warning('Error:', message:parse_error().message)
      main_loop:quit()
   elseif message.type.EOS then
      log.warning 'end of stream'
      main_loop:quit()
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

local function main()
	local app={}
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
	local vrecq_src_probe_id=vrecq_src:add_probe(Gst.PadProbeType.BLOCK+Gst.PadProbeType.BUFFER,block_probe_cb,nil,nil)
	print(vrecq_src_probe_id)
	app.vrecq_src_probe_id=vrecq_src_probe_id
	app.chunk_count=0
	app.filesink=pipeline:get_by_name"filesink"
	print(app.filesink)
	app_update_filesink_location(app)
	app.muxer=pipeline:get_by_name"mux"
	pipeline.bus:add_watch(GLib.PRIORITY_DEFAULT, bus_cb,app)
	main_loop:run()
end

main()	
