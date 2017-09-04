local M={}
M.launch=[[ v4l2src do-timestamp=true
		! video/x-raw, format=YUY2,framerate=60/1, width=1280, height=720
		! v4l2video30convert
		! video/x-raw,format=NV12,width=1280,height=720
		! v4l2video11h264enc extra-controls="encode,h264_level=10,h264_profile=4,frame_level_rate_control_enable=1,video_bitrate=4194304"
		! h264parse
		! queue name=vrecq ! mp4mux name=mux ! filesink async=false name=filesink
]]
return M
