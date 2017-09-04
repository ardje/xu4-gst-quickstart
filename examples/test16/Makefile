ALL: ctest gst.txt
CFLAGS=$(shell pkg-config --cflags gstreamer-1.0 libsoup-2.4)
LFLAGS=$(shell pkg-config --libs gstreamer-1.0 libsoup-2.4)

ctest: test-backlog-recording-h264-test.c
	cc -o ctest $(CFLAGS) test-backlog-recording-h264-test.c $(LFLAGS) 

gst.txt:
	lua -llgi -lpl.pretty -e '_ENV["pl.pretty"].dump(lgi.Gst:_resolve(true))' > gst.txt
