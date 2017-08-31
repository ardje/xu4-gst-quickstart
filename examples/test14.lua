#! /usr/bin/env lua

-- original gstplaystream.lua example
--
-- Sample GStreamer application, port of public Vala GStreamer Audio
-- Stream Example (http://live.gnome.org/Vala/GStreamerSample)
--

local lgi = require 'lgi'
local GLib = lgi.GLib
local Gst = lgi.Gst
local log=lgi.log.domain'encodertest'

local main_loop = GLib.MainLoop()

local function bus_callback(_, message)
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
   else
	    log.warning("bus callback")
   end

   return true
end

local pipeline = Gst.Pipeline.new('encodingpipe')

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
pipeline.state = 'PLAYING'

-- Run the loop.
main_loop:run()
pipeline.state = 'NULL'
