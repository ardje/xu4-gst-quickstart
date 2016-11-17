#!/bin/bash -x
. ./whatdevices.sh
# Screencast your desktop
# You need a 1280x720 desktop to work, else you need to add a scaler...
gst-launch-1.0 -e -v \
	ximagesrc use-damage=false ! \
	video/x-raw, width=1280, height=720, rate=50/1 ! \
        videoconvert ! \
	queue ! \
	${ENCODER} extra-controls="encode,h264_level=10,h264_profile=4,frame_level_rate_control_enable=1,video_bitrate=4194304" ! \
	h264parse config-interval=2 ! \
	mpegtsmux ! \
	rtpmp2tpay ! \
	queue ! \
	udpsink host=239.255.12.42 port=5004 auto-multicast=true sync=true
	
