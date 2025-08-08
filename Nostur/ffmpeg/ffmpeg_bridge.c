//
//  ffmpeg_bridge.c
//  Nostur
//
//  Created by Fabian Lachman on 07/08/2025.
//

#include "ffmpeg_bridge.h"

#include <libavutil/opt.h>
#include <libavutil/samplefmt.h>
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libswresample/swresample.h>
#include <libavutil/audio_fifo.h>

int convert_webm_to_m4a(const char *input_path, const char *output_path) {
    AVFormatContext *input_format_ctx = NULL;
    AVFormatContext *output_format_ctx = NULL;
    AVCodecContext *decoder_ctx = NULL;
    AVCodecContext *encoder_ctx = NULL;
    AVStream *input_stream = NULL;
    AVStream *output_stream = NULL;
    AVPacket *packet = NULL;
    AVFrame *frame = NULL;
    AVFrame *output_frame = NULL;
    SwrContext *swr_ctx = NULL;
    AVAudioFifo *audio_fifo = NULL;
    int ret = 0;
    int audio_stream_index = -1;
    int64_t next_pts = 0;

    av_log_set_level(AV_LOG_ERROR);

    ret = avformat_open_input(&input_format_ctx, input_path, NULL, NULL);
    if (ret < 0) {
        fprintf(stderr, "Could not open input file '%s'\n", input_path);
        goto cleanup;
    }

    ret = avformat_find_stream_info(input_format_ctx, NULL);
    if (ret < 0) {
        fprintf(stderr, "Failed to retrieve input stream information\n");
        goto cleanup;
    }

    for (int i = 0; i < input_format_ctx->nb_streams; i++) {
        if (input_format_ctx->streams[i]->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
            audio_stream_index = i;
            input_stream = input_format_ctx->streams[i];
            break;
        }
    }

    if (audio_stream_index == -1) {
        fprintf(stderr, "No audio stream found in input file\n");
        ret = -1;
        goto cleanup;
    }

    const AVCodec *decoder = avcodec_find_decoder(input_stream->codecpar->codec_id);
    if (!decoder) {
        fprintf(stderr, "Failed to find decoder for stream\n");
        ret = -1;
        goto cleanup;
    }

    decoder_ctx = avcodec_alloc_context3(decoder);
    if (!decoder_ctx) {
        fprintf(stderr, "Failed to allocate decoder context\n");
        ret = AVERROR(ENOMEM);
        goto cleanup;
    }

    ret = avcodec_parameters_to_context(decoder_ctx, input_stream->codecpar);
    if (ret < 0) {
        fprintf(stderr, "Failed to copy decoder parameters to input decoder context\n");
        goto cleanup;
    }

    ret = avcodec_open2(decoder_ctx, decoder, NULL);
    if (ret < 0) {
        fprintf(stderr, "Failed to open decoder\n");
        goto cleanup;
    }

    ret = avformat_alloc_output_context2(&output_format_ctx, NULL, "mp4", output_path);
    if (!output_format_ctx) {
        fprintf(stderr, "Could not create output context\n");
        ret = AVERROR_UNKNOWN;
        goto cleanup;
    }

    const AVCodec *encoder = avcodec_find_encoder(AV_CODEC_ID_AAC);
    if (!encoder) {
        fprintf(stderr, "AAC encoder not found\n");
        ret = -1;
        goto cleanup;
    }

    output_stream = avformat_new_stream(output_format_ctx, NULL);
    if (!output_stream) {
        fprintf(stderr, "Failed allocating output stream\n");
        ret = AVERROR_UNKNOWN;
        goto cleanup;
    }

    encoder_ctx = avcodec_alloc_context3(encoder);
    if (!encoder_ctx) {
        fprintf(stderr, "Failed to allocate encoder context\n");
        ret = AVERROR(ENOMEM);
        goto cleanup;
    }

    av_channel_layout_copy(&encoder_ctx->ch_layout, &decoder_ctx->ch_layout);
    encoder_ctx->sample_rate = decoder_ctx->sample_rate;
    encoder_ctx->sample_fmt = encoder->sample_fmts[0];
    encoder_ctx->bit_rate = 128000;
    encoder_ctx->time_base = (AVRational){1, encoder_ctx->sample_rate};

    if (output_format_ctx->oformat->flags & AVFMT_GLOBALHEADER)
        encoder_ctx->flags |= AV_CODEC_FLAG_GLOBAL_HEADER;

    ret = avcodec_open2(encoder_ctx, encoder, NULL);
    if (ret < 0) {
        fprintf(stderr, "Failed to open encoder\n");
        goto cleanup;
    }

    audio_fifo = av_audio_fifo_alloc(encoder_ctx->sample_fmt, encoder_ctx->ch_layout.nb_channels, 1024 * 10);
    if (!audio_fifo) {
        fprintf(stderr, "Failed to allocate audio FIFO\n");
        ret = AVERROR(ENOMEM);
        goto cleanup;
    }

    if (decoder_ctx->sample_fmt != encoder_ctx->sample_fmt ||
        decoder_ctx->sample_rate != encoder_ctx->sample_rate ||
        av_channel_layout_compare(&decoder_ctx->ch_layout, &encoder_ctx->ch_layout)) {
        
        swr_ctx = swr_alloc();
        if (!swr_ctx) {
            fprintf(stderr, "Could not allocate resampler context\n");
            ret = AVERROR(ENOMEM);
            goto cleanup;
        }
        
        av_opt_set_chlayout(swr_ctx, "in_chlayout", &decoder_ctx->ch_layout, 0);
        av_opt_set_int(swr_ctx, "in_sample_rate", decoder_ctx->sample_rate, 0);
        av_opt_set_sample_fmt(swr_ctx, "in_sample_fmt", decoder_ctx->sample_fmt, 0);
        
        av_opt_set_chlayout(swr_ctx, "out_chlayout", &encoder_ctx->ch_layout, 0);
        av_opt_set_int(swr_ctx, "out_sample_rate", encoder_ctx->sample_rate, 0);
        av_opt_set_sample_fmt(swr_ctx, "out_sample_fmt", encoder_ctx->sample_fmt, 0);
        
        ret = swr_init(swr_ctx);
        if (ret < 0) {
            fprintf(stderr, "Failed to initialize the resampling context\n");
            goto cleanup;
        }
    }

    ret = avcodec_parameters_from_context(output_stream->codecpar, encoder_ctx);
    if (ret < 0) {
        fprintf(stderr, "Failed to copy encoder parameters to output stream\n");
        goto cleanup;
    }

    output_stream->time_base = encoder_ctx->time_base;

    if (!(output_format_ctx->oformat->flags & AVFMT_NOFILE)) {
        ret = avio_open(&output_format_ctx->pb, output_path, AVIO_FLAG_WRITE);
        if (ret < 0) {
            fprintf(stderr, "Could not open output file '%s'\n", output_path);
            goto cleanup;
        }
    }

    ret = avformat_write_header(output_format_ctx, NULL);
    if (ret < 0) {
        fprintf(stderr, "Error occurred when opening output file\n");
        goto cleanup;
    }

    packet = av_packet_alloc();
    if (!packet) {
        ret = AVERROR(ENOMEM);
        goto cleanup;
    }

    frame = av_frame_alloc();
    if (!frame) {
        ret = AVERROR(ENOMEM);
        goto cleanup;
    }

    output_frame = av_frame_alloc();
    if (!output_frame) {
        ret = AVERROR(ENOMEM);
        goto cleanup;
    }

    while (av_read_frame(input_format_ctx, packet) >= 0) {
        if (packet->stream_index == audio_stream_index) {
            ret = avcodec_send_packet(decoder_ctx, packet);
            if (ret < 0) {
                fprintf(stderr, "Error sending packet to decoder\n");
                break;
            }

            while (ret >= 0) {
                ret = avcodec_receive_frame(decoder_ctx, frame);
                if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF)
                    break;
                else if (ret < 0) {
                    fprintf(stderr, "Error during decoding\n");
                    goto cleanup;
                }

                if (swr_ctx) {
                    int out_samples = av_rescale_rnd(swr_get_out_samples(swr_ctx, frame->nb_samples),
                                                    encoder_ctx->sample_rate,
                                                    decoder_ctx->sample_rate, AV_ROUND_UP);
                    uint8_t **out_data = NULL;
                    ret = av_samples_alloc_array_and_samples(&out_data, NULL, encoder_ctx->ch_layout.nb_channels,
                                                            out_samples, encoder_ctx->sample_fmt, 0);
                    if (ret < 0) {
                        fprintf(stderr, "Error allocating output buffer\n");
                        goto cleanup;
                    }

                    ret = swr_convert(swr_ctx, out_data, out_samples,
                                      (const uint8_t **)frame->data, frame->nb_samples);
                    if (ret < 0) {
                        fprintf(stderr, "Error while converting\n");
                        av_freep(&out_data[0]);
                        av_free(out_data);
                        goto cleanup;
                    }

                    ret = av_audio_fifo_write(audio_fifo, (void **)out_data, ret);
                    if (ret < 0) {
                        fprintf(stderr, "Error writing to audio FIFO\n");
                        av_freep(&out_data[0]);
                        av_free(out_data);
                        goto cleanup;
                    }

                    av_freep(&out_data[0]);
                    av_free(out_data);
                } else {
                    ret = av_audio_fifo_write(audio_fifo, (void **)frame->data, frame->nb_samples);
                    if (ret < 0) {
                        fprintf(stderr, "Error writing to audio FIFO\n");
                        goto cleanup;
                    }
                }
            }
        }
        av_packet_unref(packet);
    }

    ret = avcodec_send_packet(decoder_ctx, NULL);
    while (ret >= 0) {
        ret = avcodec_receive_frame(decoder_ctx, frame);
        if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF)
            break;
        else if (ret < 0) {
            fprintf(stderr, "Error during decoding flush\n");
            goto cleanup;
        }

        if (swr_ctx) {
            int out_samples = av_rescale_rnd(swr_get_out_samples(swr_ctx, frame->nb_samples),
                                            encoder_ctx->sample_rate,
                                            decoder_ctx->sample_rate, AV_ROUND_UP);
            uint8_t **out_data = NULL;
            ret = av_samples_alloc_array_and_samples(&out_data, NULL, encoder_ctx->ch_layout.nb_channels,
                                                    out_samples, encoder_ctx->sample_fmt, 0);
            if (ret < 0) {
                fprintf(stderr, "Error allocating output buffer\n");
                goto cleanup;
            }

            ret = swr_convert(swr_ctx, out_data, out_samples,
                              (const uint8_t **)frame->data, frame->nb_samples);
            if (ret < 0) {
                fprintf(stderr, "Error while converting\n");
                av_freep(&out_data[0]);
                av_free(out_data);
                goto cleanup;
            }

            ret = av_audio_fifo_write(audio_fifo, (void **)out_data, ret);
            if (ret < 0) {
                fprintf(stderr, "Error writing to audio FIFO\n");
                av_freep(&out_data[0]);
                av_free(out_data);
                goto cleanup;
            }

            av_freep(&out_data[0]);
            av_free(out_data);
        } else {
            ret = av_audio_fifo_write(audio_fifo, (void **)frame->data, frame->nb_samples);
            if (ret < 0) {
                fprintf(stderr, "Error writing to audio FIFO\n");
                goto cleanup;
            }
        }
    }

    while (av_audio_fifo_size(audio_fifo) >= encoder_ctx->frame_size ||
           (av_audio_fifo_size(audio_fifo) > 0 && !input_format_ctx)) {
        int samples_to_read = encoder_ctx->frame_size;
        if (av_audio_fifo_size(audio_fifo) < encoder_ctx->frame_size && !input_format_ctx) {
            samples_to_read = av_audio_fifo_size(audio_fifo);
        }

        output_frame->nb_samples = samples_to_read;
        output_frame->format = encoder_ctx->sample_fmt;
        av_channel_layout_copy(&output_frame->ch_layout, &encoder_ctx->ch_layout);
        output_frame->sample_rate = encoder_ctx->sample_rate;
        output_frame->pts = next_pts;

        ret = av_frame_get_buffer(output_frame, 0);
        if (ret < 0) {
            fprintf(stderr, "Error allocating output frame buffer\n");
            goto cleanup;
        }

        ret = av_audio_fifo_read(audio_fifo, (void **)output_frame->data, samples_to_read);
        if (ret < 0) {
            fprintf(stderr, "Error reading from audio FIFO\n");
            goto cleanup;
        }

        ret = avcodec_send_frame(encoder_ctx, output_frame);
        if (ret < 0) {
            fprintf(stderr, "Error sending frame to encoder\n");
            goto cleanup;
        }

        while (ret >= 0) {
            AVPacket *out_packet = av_packet_alloc();
            if (!out_packet) {
                ret = AVERROR(ENOMEM);
                goto cleanup;
            }

            ret = avcodec_receive_packet(encoder_ctx, out_packet);
            if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) {
                av_packet_free(&out_packet);
                break;
            } else if (ret < 0) {
                fprintf(stderr, "Error during encoding\n");
                av_packet_free(&out_packet);
                goto cleanup;
            }

            out_packet->stream_index = output_stream->index;
            av_packet_rescale_ts(out_packet, encoder_ctx->time_base, output_stream->time_base);

            ret = av_interleaved_write_frame(output_format_ctx, out_packet);
            av_packet_free(&out_packet);
            if (ret < 0) {
                fprintf(stderr, "Error muxing packet\n");
                goto cleanup;
            }
        }

        next_pts += samples_to_read;
        av_frame_unref(output_frame);
    }

    ret = avcodec_send_frame(encoder_ctx, NULL);
    while (ret >= 0) {
        AVPacket *out_packet = av_packet_alloc();
        if (!out_packet) {
            ret = AVERROR(ENOMEM);
            goto cleanup;
        }

        ret = avcodec_receive_packet(encoder_ctx, out_packet);
        if (ret == AVERROR(EAGAIN) || ret == AVERROR_EOF) {
            av_packet_free(&out_packet);
            break;
        } else if (ret < 0) {
            fprintf(stderr, "Error during encoding flush\n");
            av_packet_free(&out_packet);
            goto cleanup;
        }

        out_packet->stream_index = output_stream->index;
        av_packet_rescale_ts(out_packet, encoder_ctx->time_base, output_stream->time_base);
        ret = av_interleaved_write_frame(output_format_ctx, out_packet);
        av_packet_free(&out_packet);
        if (ret < 0) {
            fprintf(stderr, "Error muxing packet\n");
            goto cleanup;
        }
    }

    ret = av_write_trailer(output_format_ctx);
    if (ret < 0) {
        fprintf(stderr, "Error writing trailer\n");
        goto cleanup;
    }

    ret = 0;

cleanup:
    if (packet) {
        av_packet_free(&packet);
        packet = NULL;
    }
    if (frame) {
        av_frame_free(&frame);
        frame = NULL;
    }
    if (output_frame) {
        av_frame_free(&output_frame);
        output_frame = NULL;
    }
    if (audio_fifo) {
        av_audio_fifo_free(audio_fifo);
        audio_fifo = NULL;
    }
    if (swr_ctx) {
        swr_free(&swr_ctx);
        swr_ctx = NULL;
    }
    if (decoder_ctx) {
        avcodec_free_context(&decoder_ctx);
        decoder_ctx = NULL;
    }
    if (encoder_ctx) {
        avcodec_free_context(&encoder_ctx);
        encoder_ctx = NULL;
    }
    if (input_format_ctx) {
        avformat_close_input(&input_format_ctx);
        input_format_ctx = NULL;
    }
    if (output_format_ctx) {
        if (!(output_format_ctx->oformat->flags & AVFMT_NOFILE))
            avio_closep(&output_format_ctx->pb);
        avformat_free_context(output_format_ctx);
        output_format_ctx = NULL;
    }

    return ret;
}
