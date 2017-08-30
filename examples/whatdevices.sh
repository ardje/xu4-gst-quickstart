DECODER=$(gst-inspect-1.0 | awk '/v4l2video[0-9]videodec/ { gsub(":",""); print $2 ; nextfile }')
ENCODER=$(gst-inspect-1.0 | awk '/v4l2video[0-9]+h264enc/ { gsub(":",""); print $2 ; nextfile }')
CONVERT1=$(gst-inspect-1.0 | awk '/v4l2video[0-9]+convert/ { gsub(":",""); print $2 ; nextfile }'|head -1)
CONVERT2=$(gst-inspect-1.0 | awk '/v4l2video[0-9]+convert/ { gsub(":",""); print $2  }'|tail -1)

# If you have webcam, define it here:
DEVICE=$(echo /dev/v4l/by-id/usb-Epiphan*)
