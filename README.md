Quick testing of streaming with a little help of mad_ady.
Fixes and kernels from memeka.

PREREQUISITES:
you must use the HK ubuntu 16.04 image for xu4.
Install guide:
The gstreamer stuff:
dpkg -i binaries-ma/*.deb

The kernel:
dpkg -i kernel/*.deb
cp /usr/lib/linux-image*/*.dtb /media/boot
cp kernel/boot.ini /media/boot
To be clear: the kernel image contains the dtb in /usr/lib/linux-image.../*
unlike the mdrjr kernels which puts them in /boot, overwriting other versions.
The boot.ini must be adjusted to load the xu4 dtb unless you are using a xu3.
The xu3 is not tested.

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

The kernel source is:
git@github.com:Dmole/linux
branch odroidxu4-mihailescu2m-4.8
the config is in the kernel package.

If you want to use the multicast setup, but you don't have a default ipv4 route, do this:
ip ro add multicast 224.0.0.0/4 dev $IFACE

I also added an udev directory containing some rules to fix your eth devices...

BTW:
You might need to rm -fr ~/.cache/gstreamer-1.0
to remove the cached plugin status
