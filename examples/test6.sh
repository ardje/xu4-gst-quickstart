#!/bin/bash -x
. ./whatdevices.sh
DECODER=$(gst-inspect-1.0 | awk '/v4l2video[0-9]videodec/ { gsub(":",""); print $2 ; nextfile }')
ENCODER=$(gst-inspect-1.0 | awk '/v4l2video[0-9]h264enc/ { gsub(":",""); print $2 ; nextfile }')
#gst-launch-1.0 filesrc location=~/Videos/sintel_trailer-720p.mp4 ! qtdemux ! h264parse ! ${DECODER} ! queue !  ${ENCODER} extra-controls="encode,h264_level=10,h264_profile=4,frame_level_rate_control_enable=1,video_bitrate=2097152" ! h264parse ! mpegtsmux ! rtpmp2tpay ! queue ! udpsink host=239.255.12.42 port=5004 auto-multicast=true sync=true
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
	h264parse ! \
	tsmux. \
	alsasrc device="hw:CARD=Video,DEV=0" ! audio/x-raw,rate=48000 ! queue ! voaacenc ! aacparse ! \
	mpegtsmux name=tsmux ! \
	rtpmp2tpay ! \
	queue ! \
	udpsink host=239.255.12.42 port=5004 auto-multicast=true sync=true \
	
