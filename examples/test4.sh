#!/bin/bash -x
. ./whatdevices.sh
# Bouncing ball test using videosrc

FORMAT=YUY2
width=1280
height=720
gst-launch-1.0 -v \
	videotestsrc is-live=true do-timestamp=true pattern=18 ! \
        video/x-raw, format=$FORMAT,framerate=25/1, width=$width, height=$height ! \
        videoconvert ! \
	queue ! \
	${ENCODER} extra-controls="encode,h264_level=10,h264_profile=4,frame_level_rate_control_enable=1,video_bitrate=4194304" ! h264parse ! mpegtsmux ! rtpmp2tpay ! queue ! udpsink host=239.255.12.42 port=5004 auto-multicast=true sync=true
