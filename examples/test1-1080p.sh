#!/bin/bash -x
# You can find the video files here: https://download.blender.org/durian/trailer/
# This example basically does what memeka said in: http://forum.odroid.com/viewtopic.php?f=95&t=23163&start=50#p157279
# The examples are important because these mp4 files are perfect.
# gstreamer can't handle the mp4's I've created from ts using avidemux.
. ./whatdevices.sh
time gst-launch-1.0 filesrc location=~/Videos/sintel_trailer-1080p.mp4 ! qtdemux ! h264parse ! ${DECODER} !  ${ENCODER} extra-controls="encode,h264_level=10,h264_profile=4,frame_level_rate_control_enable=1,video_bitrate=2097152" ! h264parse ! matroskamux ! filesink location=~/output.mkv
