#!/bin/bash -x
# This example does exactly what test1.sh does, but it won't write out to a file, it is multicasting it
. ./whatdevices.sh
time gst-launch-1.0 filesrc location=~/Videos/sintel_trailer-1080p.mp4 ! qtdemux ! h264parse ! ${DECODER} ! queue !  ${ENCODER} extra-controls="encode,h264_level=10,h264_profile=4,frame_level_rate_control_enable=1,video_bitrate=4194304" ! h264parse config-interval=2 ! mpegtsmux ! rtpmp2tpay ! queue ! udpsink host=239.255.12.42 port=5004 auto-multicast=true sync=true
