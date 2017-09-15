Transplant backlog recording example into lua-lgi so we can give libsoup commands


Dump all of Gst:
lua -llgi -lpl.pretty -e '_ENV["pl.pretty"].dump(lgi.Gst:_resolve(true))'

Using ctest:
./ctest <file format> <file modulo> <video caps>

Example: HW encoding with file names containing a number modulo 10:
./ctest '/tmp/video-%02d.mp4' 10 " v4l2src device=/dev/video0 do-timestamp=true ! video/x-raw, format=YUY2,width=1280,height=720,framerate=30/1 ! v4l2video30convert ! video/x-raw, format=NV12 ! v4l2video11h264enc extra-controls=encode,h264_level=10,h264_profile=4,frame_level_rate_control_enable=1,video_bitrate=4194304 ! h264parse config-interval=2 ! queue name=vrecq ! mp4mux name=mux ! filesink async=false name=filesink alsasrc device=hw:1 do-timestamp=true ! audioconvert ! voaacenc ! queue name=arecq ! mux. "
