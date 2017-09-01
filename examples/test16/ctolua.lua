#!/usr/bin/lua5.2
local lgi = require 'lgi'
--local GLib = lgi.GLib
local Gst = lgi.Gst
local log=lgi.log.domain'c test'
--local dh=require"dumphash"
--local pretty=require"pl.pretty"

local app={}

local VIDEO_CAPS="video/x-raw,width=1920,height=1080,format=I420"

local function block_probe_cb(pad, info)
	log.warning(("pad %s blocked"):format(pad))
	return true
end
local function main()
	local pipeline=Gst.parse_launch( "videotestsrc ! ".. VIDEO_CAPS..
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
	local vrecq_src_probe_id=app.vreqc_src:add_probe(Gst.PadProbeType.Block+Gst.PadProbeType.Buffer,block_probe_cb,nil,nil)
	print(vrecq_src_probe_id)
	app.vrecq_src_probe_id=vrecq_src_probe_id
end


main()	
