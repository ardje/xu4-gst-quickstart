You need to install lua5.2 lua-lgi gir1.2-soup-2.4 libsoup2.4-1 for these tests
(Next to gst-plugins-bad)
Install lua-check to check for bugs

Goal:

Set up a fully working gstreamer hardware pipeline in paused mode.

Some devices take up to 2.5 minutes to get fully probed in all places and all sizes by v4l2.

Second is to do cpu instrumentation to determine bottlenecks

I hope this will become a guideline/test in case you want to test out or work
on the kernel mfc drivers and gstreamer integration.
