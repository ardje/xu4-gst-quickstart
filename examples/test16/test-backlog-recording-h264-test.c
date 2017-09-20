/* Copyright (C) 2014 Tim-Philipp Müller <tim@centricular.com>>
 * Copyright (C) 2014 Centricular Ltd
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public
 * License along with this library; if not, write to the
 * Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 * Boston, MA 02110-1301, USA.
 *
 */

/* Test program to demonstrate use of queues to start/stop recording
 * with N seconds backlog on press of a button. Here the backlog is
 * in encoded video. We want to start a new file from a video keyframe
 * (and don't care about dropping some delta frames at the beginning
 * because we have a sufficiently large backlog anyway that the
 * interesting bit will still be in the file).
 *
 * Keeps a backlog of encoded H.264 video in a queue and starts
 * recording on demand (here timeout-based) with the
 * backlog data, whilst making sure the first encoded video
 * frame going into the muxer is a keyframe. This means we
 * drop some video data at the beginning, but it doesn't matter
 * because our backlog is large enough that we always have the
 * interesting bit in the file. Only problem is the audio now,
 * where we should set the backlog to a bit smaller than the
 * video backlog, so that we don't end up with 1-2 seconds of
 * audio before the first video frame.
 */
#include <gst/gst.h>
#include <libsoup/soup.h>
#include <string.h>
#include <stdlib.h>

// How many seconds after startup should be checked if the v4l2src
// started receiving buffers.
#define V4L2SRC_STARTUP_DELAY_MONITOR  25

// At which interval we want to continue checking if the v4l2src
// is still receiving buffers.
#define V4L2SRC_MONITOR_TIMER_INTERVAL 3

#define STOPPED   0
#define RECORDING 1
#define STOPPING  2
#define RESTART   3

typedef struct
{
  GstElement *pipeline, *vrecq, *arecq;
  GstElement *filesink;
  GstElement *muxer;
  GMainLoop *loop;
  GstPad *vrecq_src;
  GstPad *arecq_src;
  GstPad *v4l2_src;
  gulong vrecq_src_probe_id;
  gulong arecq_src_probe_id;
  guint video_buffer_count;
  guint audio_buffer_count;
  guint chunk_count;
  SoupServer *server;
  guint state;
  gchar *file_format;
  guint file_modulo;
  guint v4l2_src_frame_cnt;
} RecordApp;

static void start_recording_cb (gpointer user_data);

static void
app_update_filesink_location (RecordApp * app)
{
  gchar *fn;

  fn = g_strdup_printf (app->file_format, app->chunk_count);
  g_print ("Setting filesink location to '%s'\n", fn);
  g_object_set (app->filesink, "location", fn, NULL);

  // Set file location for next run
  app->chunk_count = (app->chunk_count + 1) % app->file_modulo;
  g_free (fn);
}

static gboolean
bus_cb (GstBus * bus, GstMessage * msg, gpointer user_data)
{
  RecordApp *app = user_data;

  switch (GST_MESSAGE_TYPE (msg)) {
    case GST_MESSAGE_ERROR: {
      GError *err = NULL;
      gchar *dbg_info = NULL;

      gst_message_parse_error (msg, &err, &dbg_info);
      g_printerr ("ERROR from element %s: %s\n",
          GST_OBJECT_NAME (msg->src), err->message);
      g_printerr ("Debugging info: %s\n", (dbg_info) ? dbg_info : "none");
      g_error_free (err);
      g_free (dbg_info);
      return FALSE;
    }
    case GST_MESSAGE_ELEMENT:{
      const GstStructure *s = gst_message_get_structure (msg);

      if (gst_structure_has_name (s, "GstBinForwarded")) {
        GstMessage *forward_msg = NULL;

        gst_structure_get (s, "message", GST_TYPE_MESSAGE, &forward_msg, NULL);
        if (GST_MESSAGE_TYPE (forward_msg) == GST_MESSAGE_EOS) {
          g_print ("EOS from element %s\n",
              GST_OBJECT_NAME (GST_MESSAGE_SRC (forward_msg)));
          gst_element_set_state (app->filesink, GST_STATE_NULL);
          gst_element_set_state (app->muxer, GST_STATE_NULL);
          app_update_filesink_location (app);
          gst_element_set_state (app->filesink, GST_STATE_PLAYING);
          gst_element_set_state (app->muxer, GST_STATE_PLAYING);
          if (app->state == RESTART) {
            app->state = STOPPED;
            g_print ("restart recording\n");
            start_recording_cb (app);
          } else {
            app->state = STOPPED;
          }
        }
        gst_message_unref (forward_msg);
      }
      break;
    }
    default:
      break;
  }

  return TRUE;
}

// It could happen that after a random time (sometimes few mintues,
// sometimes few hours) the v4l2src is not receiving any new buffers
// anymore.
//
// To check this, a monitor timer is used to simply count
// the frames we received during the timer interval. If this value
// is greater than 0, we're still receiving buffers. If not, exit
// the application because if we're not receiving any buffers anymore,
// it doesn't make sense to continue...
gboolean v4l2_src_monitor_timer_expired(gpointer user_data)
{
  RecordApp *app = user_data;

  if(app->v4l2_src_frame_cnt > 0) {
    GstClock *clk = gst_element_get_clock(app->pipeline);
    g_print("%"  GST_TIME_FORMAT ": Received %u frames since last check\n", GST_TIME_ARGS(gst_clock_get_time(clk)), app->v4l2_src_frame_cnt);
    gst_object_unref (clk);
  } else {
    g_print("Capturing data stopped :(\n");
    g_print("Exit now..\n");
    gst_element_set_state (app->pipeline, GST_STATE_NULL);
    gst_object_unref (app->pipeline);
    exit(0);
  }

  app->v4l2_src_frame_cnt = 0;

  return TRUE; // Call us again after the next interval
}

// Function called after x seconds when the application is started.
// The device I use for testing takes about 20 seconds to probe. This
// function will be called when probing is over and after the first buffers
// should already have been received.
//
// If this function is called and still no buffers were received from the
// source, something went wrong and it doesn't make sense to continue so
// then exit the application.
gboolean startup_monitor(gpointer user_data)
{
  RecordApp *app = user_data;

  if(app->v4l2_src_frame_cnt > 0) {
    // Initial startup succeeded
    GstClock *clk = gst_element_get_clock(app->pipeline);
    g_print("%"  GST_TIME_FORMAT ": Received %u frames after startup\n", GST_TIME_ARGS(gst_clock_get_time(clk)), app->v4l2_src_frame_cnt);
    gst_object_unref (clk);

    // Start timer to periodically check for incoming buffers from v4l2src
    g_timeout_add_seconds(V4L2SRC_MONITOR_TIMER_INTERVAL, v4l2_src_monitor_timer_expired, app);
  } else {
    g_print("No data after initial startup\n");
    g_print("Exit now..\n");
    gst_element_set_state (app->pipeline, GST_STATE_NULL);
    gst_object_unref (app->pipeline);
    exit(0);
  }

  app->v4l2_src_frame_cnt = 0;

  return FALSE; // Don't call us anymore
}

// Buffer probe on the v4l2src element to count the incoming frames.
// This counter is checked at a regular interval to check if we're
// still receiving buffers on our source.
static GstPadProbeReturn
v4l2_src_monitor_probe (GstPad * pad, GstPadProbeInfo * info, gpointer user_data)
{
  RecordApp *app = user_data;

  app->v4l2_src_frame_cnt++;

  return GST_PAD_PROBE_OK;
}

static GstPadProbeReturn
probe_drop_one_cb (GstPad * pad, GstPadProbeInfo * info, gpointer user_data)
{
  RecordApp *app = user_data;
  GstBuffer *buf = info->data;

  if (app->video_buffer_count++ == 0) {
    g_print ("Drop one video buffer with ts %" GST_TIME_FORMAT "\n",
        GST_TIME_ARGS (GST_BUFFER_PTS (info->data)));
    return GST_PAD_PROBE_DROP;
  } else {
    gboolean is_keyframe;

    is_keyframe = !GST_BUFFER_FLAG_IS_SET (buf, GST_BUFFER_FLAG_DELTA_UNIT);
    g_print ("video buffer with ts %" GST_TIME_FORMAT " (keyframe=%d)\n",
        GST_TIME_ARGS (GST_BUFFER_PTS (buf)), is_keyframe);

    if (is_keyframe) {
      g_print ("Letting video buffer through and removing drop probe\n");
      gst_pad_remove_probe (app->arecq_src, app->arecq_src_probe_id);
      app->arecq_src_probe_id = 0;
      return GST_PAD_PROBE_REMOVE;
    } else {
      g_print ("Dropping video buffer, wait for a keyframe.\n");
      return GST_PAD_PROBE_DROP;
    }
  }
}

static GstPadProbeReturn
probe_audio_drop_one_cb (GstPad * pad, GstPadProbeInfo * info, gpointer user_data)
{
  RecordApp *app = user_data;
  GstBuffer *buf = info->data;

  if (app->audio_buffer_count++ == 0) {
    g_print ("Drop one audio buffer with ts %" GST_TIME_FORMAT "\n",
        GST_TIME_ARGS (GST_BUFFER_PTS (info->data)));
    return GST_PAD_PROBE_DROP;
  }

  g_print ("Letting audio buffer through and removing drop probe\n");
  return GST_PAD_PROBE_REMOVE;
}

static gpointer
push_eos_thread (gpointer user_data)
{
  RecordApp *app = user_data;
  GstPad *peer;

  peer = gst_pad_get_peer (app->vrecq_src);
  g_print ("pushing EOS event on pad %s:%s\n", GST_DEBUG_PAD_NAME (peer));

  /* tell pipeline to forward EOS message from filesink immediately and not
   * hold it back until it also got an EOS message from the video sink */
  g_object_set (app->pipeline, "message-forward", TRUE, NULL);

  gst_pad_send_event (peer, gst_event_new_eos ());
  gst_object_unref (peer);

  return NULL;
}

static gpointer
push_audio_eos_thread (gpointer user_data)
{
  RecordApp *app = user_data;
  GstPad *peer;

  peer = gst_pad_get_peer (app->arecq_src);
  g_print ("pushing audio EOS event on pad %s:%s\n", GST_DEBUG_PAD_NAME (peer));

  /* tell pipeline to forward EOS message from filesink immediately and not
   * hold it back until it also got an EOS message from the video sink */
  g_object_set (app->pipeline, "message-forward", TRUE, NULL);

  gst_pad_send_event (peer, gst_event_new_eos ());
  gst_object_unref (peer);

  return NULL;
}

static GstPadProbeReturn
block_video_probe_cb (GstPad * pad, GstPadProbeInfo * info, gpointer user_data)
{
  RecordApp *app = user_data;
  g_print ("video pad %s:%s blocked!\n", GST_DEBUG_PAD_NAME (pad));
  g_assert ((info->type & GST_PAD_PROBE_TYPE_BUFFER) ==
      GST_PAD_PROBE_TYPE_BUFFER);
  /* FIXME: this doesn't work: gst_buffer_replace ((GstBuffer **) &info->data, NULL); */

  if(app->state == STOPPING || app->state == RESTART) {
    GThread *thread;
    g_print ("Starting eos-push-thread\n");
    thread = g_thread_new ("eos-push-thread", push_eos_thread, app);
    g_thread_unref(thread);
  }

  return GST_PAD_PROBE_OK;
}

static GstPadProbeReturn
block_audio_probe_cb (GstPad * pad, GstPadProbeInfo * info, gpointer user_data)
{
  RecordApp *app = user_data;
  g_print ("audio pad %s:%s blocked!\n", GST_DEBUG_PAD_NAME (pad));
  g_assert ((info->type & GST_PAD_PROBE_TYPE_BUFFER) ==
      GST_PAD_PROBE_TYPE_BUFFER);
  /* FIXME: this doesn't work: gst_buffer_replace ((GstBuffer **) &info->data, NULL); */

  if(app->state == STOPPING || app->state == RESTART) {
    GThread *thread;
    g_print ("Starting eos-audio-push-thread\n");
    thread = g_thread_new ("eos-audio-push-thread", push_audio_eos_thread, app);
    g_thread_unref(thread);
  }
  return GST_PAD_PROBE_OK;
}

static gboolean
stop_recording_cb (gpointer user_data)
{
  RecordApp *app = user_data;

  if (app->state == RECORDING) {
    g_print ("stop recording\n");

    app->arecq_src_probe_id = gst_pad_add_probe (app->arecq_src,
        GST_PAD_PROBE_TYPE_BLOCK | GST_PAD_PROBE_TYPE_BUFFER, block_audio_probe_cb,
        app, NULL);
    app->vrecq_src_probe_id = gst_pad_add_probe (app->vrecq_src,
        GST_PAD_PROBE_TYPE_BLOCK | GST_PAD_PROBE_TYPE_BUFFER, block_video_probe_cb,
        app, NULL);

    g_print ("vrecq_src_probe_id = %lu \n", app->vrecq_src_probe_id);
    g_print ("arecq_src_probe_id = %lu \n", app->arecq_src_probe_id);

    app->state = STOPPING;
  } else {
    g_print ("Ignoring stop\n");
  }

  return FALSE;                 /* don't call us again */
}

static void
start_recording_cb (gpointer user_data)
{
  RecordApp *app = user_data;

  if (app->state == STOPPED) {
    g_print ("Start recording\n");

    /* need to hook up another probe to drop the initial old buffer stuck
     * in the blocking pad probe */
    app->video_buffer_count = 0;
    app->audio_buffer_count = 0;
    gst_pad_add_probe (app->vrecq_src,
        GST_PAD_PROBE_TYPE_BUFFER, probe_drop_one_cb, app, NULL);
    gst_pad_add_probe (app->arecq_src,
        GST_PAD_PROBE_TYPE_BUFFER, probe_audio_drop_one_cb, app, NULL);

    /* now remove the blocking probe to unblock the pad */
    g_print ("unblocking pad to start recording\n");
    gst_pad_remove_probe (app->vrecq_src, app->vrecq_src_probe_id);
    app->vrecq_src_probe_id = 0;
    app->state = RECORDING;
  } else if (app->state == STOPPING) {
    // Restart if we're currently busy stopping
    app->state = RESTART;
  } else {
    g_print ("Ignoring start\n");
  }
}

static void
start_callback (SoupServer        *server,
                 SoupMessage       *msg,
                 const char        *path,
                 GHashTable        *query,
                 SoupClientContext *client,
                 gpointer           user_data)
{
    RecordApp *app = user_data;
    const char *mime_type;
    const char *body;

    g_print ("In start_callback\n");
    if (msg->method != SOUP_METHOD_GET) {
        soup_message_set_status (msg, SOUP_STATUS_NOT_IMPLEMENTED);
        return;
    }

    mime_type = "text/html";
    body = "OK";

    start_recording_cb (app);

    g_print ("Sending status OK with body text/html: OK\n");
    soup_message_set_status (msg, SOUP_STATUS_OK);
    soup_message_set_response (msg, mime_type, SOUP_MEMORY_COPY,
                               body, 2);
}

static void
stop_callback (SoupServer        *server,
                 SoupMessage       *msg,
                 const char        *path,
                 GHashTable        *query,
                 SoupClientContext *client,
                 gpointer           user_data)
{
    RecordApp *app = user_data;
    const char *mime_type;
    gchar *loc;

    g_print ("In stop_callback\n");
    if (msg->method != SOUP_METHOD_GET) {
        soup_message_set_status (msg, SOUP_STATUS_NOT_IMPLEMENTED);
        return;
    }

    g_object_get (app->filesink, "location", &loc, NULL);

    mime_type = "text/html";

    stop_recording_cb (app);

    g_print ("Sending status OK with body text/html: OK\n");
    soup_message_set_status (msg, SOUP_STATUS_OK);
    soup_message_set_response (msg, mime_type, SOUP_MEMORY_COPY,
                               loc, strlen(loc));
    g_free(loc);
}

int
main (int argc, char **argv)
{
  RecordApp app;
  GError *error = NULL;

  gst_init (NULL, NULL);

  if (argc == 4) {
    app.file_format = argv[1];
    app.file_modulo = atoi(argv[2]);
    app.pipeline = gst_parse_launch (argv[3], NULL);
  } else {
    app.file_format = "/var/tmp/test-%03d.mp4";
    app.file_modulo = 500;
    app.pipeline = gst_parse_launch ("v4l2src name=v4l2src device=/dev/video0 do-timestamp=true "
      " ! video/x-raw, format=YUY2,width=1280,height=720,framerate=30/1 "
      " ! v4l2video30convert ! video/x-raw, format=NV12 "
      " ! v4l2video11h264enc extra-controls=encode,h264_level=10,h264_profile=4,frame_level_rate_control_enable=1,video_bitrate=4194304 "
      " ! h264parse config-interval=2 "
      " ! queue name=vrecq "
      " ! mp4mux name=mux "
      " ! filesink async=false name=filesink "
      "   alsasrc device=hw:1 do-timestamp=true "
      " ! audioconvert "
      " ! voaacenc "
      " ! queue name=arecq "
      " ! mux. ",
      NULL);
  }

  // Video queue
  app.vrecq = gst_bin_get_by_name (GST_BIN (app.pipeline), "vrecq");
  g_object_set (app.vrecq, "max-size-time", (guint64) 3 * GST_SECOND,
      "max-size-bytes", 0, "max-size-buffers", 0, "leaky", 2, NULL);

  // Audio queue
  app.arecq = gst_bin_get_by_name (GST_BIN (app.pipeline), "arecq");
  g_object_set (app.arecq, "max-size-time", (guint64) 3 * GST_SECOND,
      "max-size-bytes", 0, "max-size-buffers", 0, "leaky", 2, NULL);

  // Video queue source pad
  app.vrecq_src = gst_element_get_static_pad (app.vrecq, "src");
  app.vrecq_src_probe_id = gst_pad_add_probe (app.vrecq_src,
      GST_PAD_PROBE_TYPE_BLOCK | GST_PAD_PROBE_TYPE_BUFFER, block_video_probe_cb,
      &app, NULL);

  // Audio queue source pad
  app.arecq_src = gst_element_get_static_pad (app.arecq, "src");
  app.arecq_src_probe_id = gst_pad_add_probe (app.arecq_src,
      GST_PAD_PROBE_TYPE_BLOCK | GST_PAD_PROBE_TYPE_BUFFER, block_audio_probe_cb,
      &app, NULL);

  // Monitors to check if we are still receiving buffers on the v4l2src
  app.v4l2_src = gst_element_get_static_pad(gst_bin_get_by_name (GST_BIN (app.pipeline), "v4l2src"), "src");
  gst_pad_add_probe (app.v4l2_src, GST_PAD_PROBE_TYPE_BUFFER, v4l2_src_monitor_probe, &app, NULL);
  app.v4l2_src_frame_cnt = 0;
  g_timeout_add_seconds(V4L2SRC_STARTUP_DELAY_MONITOR, startup_monitor, &app);

  // Filesink
  app.chunk_count = 0;
  app.filesink = gst_bin_get_by_name (GST_BIN (app.pipeline), "filesink");
  app_update_filesink_location (&app);
  app.muxer = gst_bin_get_by_name (GST_BIN (app.pipeline), "mux");

  gst_element_set_state (app.pipeline, GST_STATE_PLAYING);

  app.loop = g_main_loop_new (NULL, FALSE);
  gst_bus_add_watch (GST_ELEMENT_BUS (app.pipeline), bus_cb, &app);

  // Soup setup
  app.state = STOPPED;
  app.server = soup_server_new (SOUP_SERVER_SERVER_HEADER, "recorder ", NULL);
  soup_server_listen_all (app.server, 9620, 0, &error);
  soup_server_add_handler (app.server, "/start", start_callback, &app, NULL);
  soup_server_add_handler (app.server, "/stop", stop_callback, &app, NULL);
  g_print ("Listening on port 9620...\n");

  g_main_loop_run (app.loop);

  gst_element_set_state (app.pipeline, GST_STATE_NULL);
  gst_object_unref (app.pipeline);
  return 0;
}
