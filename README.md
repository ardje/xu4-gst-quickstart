PREREQUISITES:
you must use the latest HK ubuntu 16.04 image for xu4.
(2017-08-24 at least)

Examples:
This directory contains my gst-launch tests to make everything multicastable.
clients:
Example player stuff.

Sources:
I am violating the GPL a bit here... This is a quicky and I will add my kernel compile stuff to github soon.
The gstreamer source is here:
https://github.com/mihailescu2m/gst-plugins-good
with an extra patch here:
patch/....

If you want to use the multicast setup, but you don't have a default ipv4 route, do this:
ip ro add multicast 224.0.0.0/4 dev $IFACE

I also added an udev directory containing some rules to fix your eth devices...

BTW:
You might need to rm -fr ~/.cache/gstreamer-1.0
to remove the cached plugin status
