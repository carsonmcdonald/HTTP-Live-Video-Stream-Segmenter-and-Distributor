/*
 * Copyright (c) 2009-2013 Carson McDonald
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License version 2
 * as published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 *
 * Originaly created by and Copyright (c) 2009 Chase Douglas
 */

#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include "libavformat/avformat.h"

struct config_info
{
  const char *input_filename;
  int segment_length;
  const char *temp_directory;
  const char *filename_prefix;
  const char *encoding_profile;
};

static AVStream *add_output_stream(AVFormatContext *output_format_context, AVStream *input_stream) 
{
  AVCodecContext *input_codec_context;
  AVCodecContext *output_codec_context;
  AVStream *output_stream;

  output_stream = avformat_new_stream(output_format_context, 0);
  if (!output_stream) 
  {
    fprintf(stderr, "Segmenter error: Could not allocate stream\n");
    exit(1);
  }

  input_codec_context = input_stream->codec;
  output_codec_context = output_stream->codec;

  output_codec_context->codec_id = input_codec_context->codec_id;
  output_codec_context->codec_type = input_codec_context->codec_type;
  output_codec_context->codec_tag = input_codec_context->codec_tag;
  output_codec_context->bit_rate = input_codec_context->bit_rate;
  output_codec_context->extradata = input_codec_context->extradata;
  output_codec_context->extradata_size = input_codec_context->extradata_size;

  if(av_q2d(input_codec_context->time_base) * input_codec_context->ticks_per_frame > av_q2d(input_stream->time_base) && av_q2d(input_stream->time_base) < 1.0/1000) 
  {
    output_codec_context->time_base = input_codec_context->time_base;
    output_codec_context->time_base.num *= input_codec_context->ticks_per_frame;
  }
  else 
  {
    output_codec_context->time_base = input_stream->time_base;
  }

  switch (input_codec_context->codec_type) 
  {
    case AVMEDIA_TYPE_AUDIO:
      output_codec_context->channel_layout = input_codec_context->channel_layout;
      output_codec_context->sample_rate = input_codec_context->sample_rate;
      output_codec_context->channels = input_codec_context->channels;
      output_codec_context->frame_size = input_codec_context->frame_size;
      if ((input_codec_context->block_align == 1 && input_codec_context->codec_id == CODEC_ID_MP3) || input_codec_context->codec_id == CODEC_ID_AC3) 
      {
        output_codec_context->block_align = 0;
      }
      else 
      {
        output_codec_context->block_align = input_codec_context->block_align;
      }
      break;
    case AVMEDIA_TYPE_VIDEO:
      output_codec_context->pix_fmt = input_codec_context->pix_fmt;
      output_codec_context->width = input_codec_context->width;
      output_codec_context->height = input_codec_context->height;
      output_codec_context->has_b_frames = input_codec_context->has_b_frames;

      if (output_format_context->oformat->flags & AVFMT_GLOBALHEADER) 
      {
          output_codec_context->flags |= CODEC_FLAG_GLOBAL_HEADER;
      }
      break;
    default:
      break;
  }

  return output_stream;
}

void output_transfer_command(const unsigned int first_segment, const unsigned int last_segment, const int end, const char *encoding_profile)
{
  char buffer[1024 * 10];
  memset(buffer, 0, sizeof(char) * 1024 * 10);

  sprintf(buffer, "%d, %d, %d, %s", first_segment, last_segment, end, encoding_profile);

  fprintf(stderr, "segmenter: %s\n\r", buffer);
}

int main(int argc, char **argv)
{
  if(argc != 5)
  {
    fprintf(stderr, "Usage: %s <segment length> <output location> <filename prefix> <encoding profile>\n", argv[0]);
    return 1;
  }

  struct config_info config;

  memset(&config, 0, sizeof(struct config_info));

  config.segment_length = atoi(argv[1]); 
  config.temp_directory = argv[2];
  config.filename_prefix = argv[3];
  config.encoding_profile = argv[4];
  config.input_filename = "pipe://1";

  char *output_filename = malloc(sizeof(char) * (strlen(config.temp_directory) + 1 + strlen(config.filename_prefix) + 10));
  if (!output_filename) 
  {
    fprintf(stderr, "Segmenter error: Could not allocate space for output filenames\n");
    exit(1);
  }

  // ------------------ Done parsing input --------------

  av_register_all();

  AVInputFormat *input_format = av_find_input_format("mpegts");
  if (!input_format) 
  {
    fprintf(stderr, "Segmenter error: Could not find MPEG-TS demuxer\n");
    exit(1);
  }

  AVFormatContext *input_context = NULL;
  int ret = avformat_open_input(&input_context, config.input_filename, input_format, NULL);
  if (ret != 0) 
  {
    fprintf(stderr, "Segmenter error: Could not open input file, make sure it is an mpegts file: %d\n", ret);
    exit(1);
  }

  if (avformat_find_stream_info(input_context, NULL) < 0)
  {
    fprintf(stderr, "Segmenter error: Could not read stream information\n");
    exit(1);
  }

//#if LIBAVFORMAT_VERSION_MAJOR >= 52 && LIBAVFORMAT_VERSION_MINOR >= 45
  AVOutputFormat *output_format = av_guess_format("mpegts", NULL, NULL);
//#else
 // AVOutputFormat *output_format = guess_format("mpegts", NULL, NULL);
//#endif
  if (!output_format) 
  {
    fprintf(stderr, "Segmenter error: Could not find MPEG-TS muxer\n");
    exit(1);
  }

  AVFormatContext *output_context = avformat_alloc_context();
  if (!output_context) 
  {
    fprintf(stderr, "Segmenter error: Could not allocated output context");
    exit(1);
  }
  output_context->oformat = output_format;

  int video_index = -1;
  int audio_index = -1;

  AVStream *video_stream;
  AVStream *audio_stream;

  int i;

  for (i = 0; i < input_context->nb_streams && (video_index < 0 || audio_index < 0); i++) 
  {
    switch (input_context->streams[i]->codec->codec_type) {
      case AVMEDIA_TYPE_VIDEO:
        video_index = i;
        input_context->streams[i]->discard = AVDISCARD_NONE;
        video_stream = add_output_stream(output_context, input_context->streams[i]);
        break;
      case AVMEDIA_TYPE_AUDIO:
        audio_index = i;
        input_context->streams[i]->discard = AVDISCARD_NONE;
        audio_stream = add_output_stream(output_context, input_context->streams[i]);
        break;
      default:
        input_context->streams[i]->discard = AVDISCARD_ALL;
        break;
    }
  }

// if (av_set_parameters(output_context, NULL) < 0)
//  {
//    fprintf(stderr, "Segmenter error: Invalid output format parameters\n");
//    exit(1);
//  }

  av_dump_format(output_context, 0, config.filename_prefix, 1);

  if(video_index >= 0)
  {
    AVCodec *codec = avcodec_find_decoder(video_stream->codec->codec_id);
    if (!codec) 
    {
      fprintf(stderr, "Segmenter error: Could not find video decoder, key frames will not be honored\n");
    }

    if (avcodec_open2(video_stream->codec, codec, NULL) < 0)
    {
      fprintf(stderr, "Segmenter error: Could not open video decoder, key frames will not be honored\n");
    }
  }

  unsigned int output_index = 1;
  snprintf(output_filename, strlen(config.temp_directory) + 1 + strlen(config.filename_prefix) + 10, "%s/%s-%05u.ts", config.temp_directory, config.filename_prefix, output_index++);
 
  if (avio_open(&output_context->pb, output_filename, AVIO_FLAG_WRITE) < 0) 
  {
    fprintf(stderr, "Segmenter error: Could not open '%s'\n", output_filename);
    exit(1);
  }

  if (avformat_write_header(output_context, NULL))
  {
    fprintf(stderr, "Segmenter error: Could not write mpegts header to first output file\n");
    exit(1);
  }

  unsigned int first_segment = 1;
  unsigned int last_segment = 0;

  double prev_segment_time = 0;
  int decode_done;
  do 
  {
    double segment_time;
    AVPacket packet;

    decode_done = av_read_frame(input_context, &packet);
    if (decode_done < 0) 
    {
      break;
    }

    if (av_dup_packet(&packet) < 0) 
    {
      fprintf(stderr, "Segmenter error: Could not duplicate packet");
      av_free_packet(&packet);
      break;
    }

    if (packet.stream_index == video_index && (packet.flags & AV_PKT_FLAG_KEY))
    {
      segment_time = (double)video_stream->pts.val * video_stream->time_base.num / video_stream->time_base.den;
    }
    else if (video_index < 0) 
    {
      segment_time = (double)audio_stream->pts.val * audio_stream->time_base.num / audio_stream->time_base.den;
    }
    else 
    {
      segment_time = prev_segment_time;
    }

    // done writing the current file?
    if (segment_time - prev_segment_time >= config.segment_length) 
    {
      avio_flush(output_context->pb);
      avio_close(output_context->pb);

      output_transfer_command(first_segment, ++last_segment, 0, config.encoding_profile);

      snprintf(output_filename, strlen(config.temp_directory) + 1 + strlen(config.filename_prefix) + 10, "%s/%s-%05u.ts", config.temp_directory, config.filename_prefix, output_index++);
      if (avio_open(&output_context->pb, output_filename, AVIO_FLAG_WRITE) < 0)
      {
        fprintf(stderr, "Segmenter error: Could not open '%s'\n", output_filename);
        break;
      }

      prev_segment_time = segment_time;
    }

    ret = av_interleaved_write_frame(output_context, &packet);
    if (ret < 0) 
    {
      fprintf(stderr, "Segmenter error: Could not write frame of stream: %d\n", ret);
    }
    else if (ret > 0) 
    {
      fprintf(stderr, "Segmenter info: End of stream requested\n");
      av_free_packet(&packet);
      break;
    }

    av_free_packet(&packet);
  } while (!decode_done);

  av_write_trailer(output_context);

  if (video_index >= 0) 
  {
    avcodec_close(video_stream->codec);
  }

  for(i = 0; i < output_context->nb_streams; i++) 
  {
    av_freep(&output_context->streams[i]->codec);
    av_freep(&output_context->streams[i]);
  }

  avio_close(output_context->pb);
  av_free(output_context);

  output_transfer_command(first_segment, ++last_segment, 1, config.encoding_profile);

  return 0;
}
