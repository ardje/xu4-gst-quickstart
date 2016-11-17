#!/bin/bash

# Flags are set to no try to do subtitleing and such.
# With memeka's gstreamer for u3 this results in a hardware decode, and a gles blit to screen.
# On a xu4 it uses gles blit to screen. Maybe with this release it also can use the hardware decoder.

gst-launch-1.0 -v playbin uri='udp://239.255.12.42:5004' video-sink=cluttersink flags=0x00000253
