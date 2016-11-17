#!/bin/bash -x
. ./whatdevices.sh
# This is an attempt of live streaming of a UVC webcam or similar to multicast *with* audio
# I have defined 2 resolutions and a device format. Please use the format your device can handle
# I cannot get it to work somehow
FORMAT=YUY2
width=1280
height=720
mode="${1:-480p}"
case "$mode" in
	480p)
		width=720 height=480 speed=4 ;;
	720p)
		width=1280 height=720 speed=3 ;;
esac
gst-launch-1.0 -v \
	v4l2src do-timestamp=true device=$DEVICE ! \
        video/x-raw, format=$FORMAT,framerate=25/1, width=$width, height=$height ! \
	queue ! \
        videoconvert ! \
	${ENCODER} extra-controls="encode,h264_level=10,h264_profile=4,frame_level_rate_control_enable=1,video_bitrate=4194304" ! \
	h264parse config-interval=2 ! \
	tsmux. \
	alsasrc device="hw:CARD=Video,DEV=0" ! audio/x-raw,rate=48000 ! queue ! voaacenc ! aacparse ! \
	mpegtsmux name=tsmux ! \
	rtpmp2tpay ! \
	queue ! \
	udpsink host=239.255.12.42 port=5004 auto-multicast=true sync=true \
	
