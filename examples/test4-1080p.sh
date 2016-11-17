#!/bin/bash -x
. ./whatdevices.sh
# videosrc encoding test

FORMAT=YUY2
width=1920
height=1080
pattern=${1:-0}
gst-launch-1.0 -v \
	videotestsrc is-live=true do-timestamp=true pattern=$pattern ! \
        video/x-raw, framerate=50/1, width=$width, height=$height ! \
	queue ! \
	${ENCODER} extra-controls="encode,h264_level=10,h264_profile=4,frame_level_rate_control_enable=1,video_bitrate=4194304" ! h264parse config-interval=2 ! mpegtsmux ! rtpmp2tpay ! queue ! udpsink host=239.255.12.42 port=5004 auto-multicast=true sync=true
