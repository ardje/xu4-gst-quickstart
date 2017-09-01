#!/usr/bin/lua5.2
local lgi = require 'lgi'
local GLib = lgi.GLib
local Gst = lgi.Gst
local log=lgi.log.domain'c test'


local app={}

local VIDEO_CAPS="video/x-raw,width=1920,height=1080,format=I420"
local function main()
	app.pipeline=Gst.parse_launch( "videotestsrc ! ".. VIDEO_CAPS..
      " ! clockoverlay ! x264enc tune=zerolatency bitrate=8000 "..
      " ! queue name=vrecq ! mp4mux name=mux ! filesink async=false name=filesink",
      nil)
	app.vcrecq=app.pipeline:get_by_name("vcrecq")
	app.vcrecq.max_size_time=3000000
end


main()	
