#!/bin/bash -x
. ./whatdevices.sh
# Stream the raw mp4 file without decode and encode
time gst-launch-1.0 filesrc location=~/Videos/sintel_trailer-720p.mp4 ! qtdemux ! h264parse config-interval=2 ! mpegtsmux ! rtpmp2tpay ! queue ! udpsink host=239.255.12.42 port=5004 auto-multicast=true sync=true
