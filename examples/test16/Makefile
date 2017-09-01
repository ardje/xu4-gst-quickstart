ALL: ctest
CFLAGS=$(shell pkg-config --cflags gstreamer-1.0)
LFLAGS=$(shell pkg-config --libs gstreamer-1.0)

ctest: test-backlog-recording-h264-test.c
	cc -o ctest $(CFLAGS) test-backlog-recording-h264-test.c $(LFLAGS) 
