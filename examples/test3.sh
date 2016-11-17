#!/bin/bash -x
. ./whatdevices.sh
# Same as test2, using 1080p file
time gst-launch-1.0 filesrc location=~/Videos/sintel_trailer-1080p.mp4 ! qtdemux ! h264parse config-interval=2 ! mpegtsmux ! rtpmp2tpay ! queue ! udpsink host=239.255.12.42 port=5004 auto-multicast=true sync=true
