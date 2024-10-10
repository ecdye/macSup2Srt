//
// FFmpeg.swift
// macSubtitleOCR
//
// Created by Ethan Dye on 10/9/24.
// Copyright © 2024 Ethan Dye. All rights reserved.
//

import CFFmpeg
import Foundation
import os

struct FFmpeg {
    // MARK: - Properties

    private var logger = Logger(subsystem: "github.ecdye.macSubtitleOCR", category: "FFmpeg")
    private(set) var subtitles = [Subtitle]()

    // MARK: - Lifecycle

    init(_ sub: String) throws {
        var fmtCtx: UnsafeMutablePointer<AVFormatContext>?
        var codecCtx: UnsafeMutablePointer<AVCodecContext>?

        // Open the input file
        if avformat_open_input(&fmtCtx, sub, nil, nil) != 0 {
            fatalError("Could not open input file")
        }

        // Retrieve stream information
        if avformat_find_stream_info(fmtCtx, nil) < 0 {
            fatalError("Could not find stream info")
        }

        var subtitleStreamIndex: Int?
        var timeBase = 0.0
        var subtitleTimeBase: AVRational?
        for i in 0 ..< Int(fmtCtx!.pointee.nb_streams) {
            let stream = fmtCtx!.pointee.streams[i]
            if stream!.pointee.codecpar.pointee.codec_type == AVMEDIA_TYPE_SUBTITLE,
               stream!.pointee.codecpar.pointee.codec_id == AV_CODEC_ID_DVD_SUBTITLE ||
               stream!.pointee.codecpar.pointee.codec_id == AV_CODEC_ID_HDMV_PGS_SUBTITLE {
                subtitleStreamIndex = i
                subtitleTimeBase = stream!.pointee.time_base
                if stream!.pointee.codecpar.pointee.codec_id == AV_CODEC_ID_DVD_SUBTITLE {
                    timeBase = 1000
                } else {
                    timeBase = 900000000
                }
                break
            }
        }

        guard let subtitleStreamIndex else {
            fatalError("Could not find a VobSub subtitle stream")
        }
        guard let codec = avcodec_find_decoder(fmtCtx!.pointee.streams[subtitleStreamIndex]!.pointee.codecpar.pointee
            .codec_id) else {
            fatalError("Could not find subtitle decoder")
        }
        codecCtx = avcodec_alloc_context3(codec)
        guard codecCtx != nil else {
            fatalError("Could not allocate codec context")
        }
        if avcodec_parameters_to_context(codecCtx,
                                         fmtCtx!.pointee.streams[subtitleStreamIndex]!.pointee.codecpar) < 0 {
            fatalError("Failed to copy codec parameters")
        }
        if avcodec_open2(codecCtx, codec, nil) < 0 {
            fatalError("Could not open codec")
        }
        var packet = av_packet_alloc()
        var subtitle = AVSubtitle()

        // Read frames from the subtitle stream
        while av_read_frame(fmtCtx, packet) >= 0 {
            if packet!.pointee.stream_index == subtitleStreamIndex {
                var gotSubtitle: Int32 = 0

                // Decode subtitle packet
                let ret = avcodec_decode_subtitle2(codecCtx, &subtitle, &gotSubtitle, packet)
                if ret < 0 {
                    logger.warning("Error decoding subtitle, skipping...")
                    continue
                }

                if gotSubtitle != 0 {
                    for i in 0 ..< Int(subtitle.num_rects) {
                        let rect = subtitle.rects[i]!
                        let sub = extractImageData(from: rect)
                        let pts = convertPTSToTimeInterval(
                            pts: packet!.pointee.pts,
                            timeBase: subtitleTimeBase!)
                        sub.startTimestamp = pts + TimeInterval(subtitle.start_display_time) / timeBase
                        sub.endTimestamp = pts + TimeInterval(subtitle.end_display_time) / timeBase
                        logger.debug("Start timestamp: \(sub.startTimestamp!), End timestamp: \(sub.endTimestamp!)")
                        subtitles.append(sub)
                    }
                    let count = subtitles.count
                    logger.debug("Got subtitle for index: \(count)")

                    avsubtitle_free(&subtitle)
                }
            }

            av_packet_unref(packet)
        }

        // Clean up
        avcodec_free_context(&codecCtx) // This will set codecCtx to nil
        avformat_close_input(&fmtCtx)
        av_packet_free(&packet)
    }

    func extractImageData(from rect: UnsafeMutablePointer<AVSubtitleRect>) -> Subtitle {
        let subtitle = Subtitle(numberOfColors: Int(rect.pointee.nb_colors))

        // Check if the subtitle is an image (bitmap)
        if rect.pointee.type == SUBTITLE_BITMAP {
            // Extract palette (if available)
            if rect.pointee.nb_colors > 0, let paletteData = rect.pointee.data.1 {
                if subtitle.imagePalette == nil {
                    subtitle.imagePalette = []
                }
                for i in 0 ..< 256 {
                    let r = paletteData[i * 4 + 0]
                    let g = paletteData[i * 4 + 1]
                    let b = paletteData[i * 4 + 2]
                    let a = paletteData[i * 4 + 3]

                    subtitle.imagePalette?.append(contentsOf: [r, g, b, a])
                }
            }

            // Extract image data (bitmap)
            subtitle.imageWidth = Int(rect.pointee.w)
            subtitle.imageHeight = Int(rect.pointee.h)
            subtitle.imageXOffset = Int(rect.pointee.linesize.0)
            logger.debug("Image size: \(subtitle.imageWidth!)x\(subtitle.imageHeight!)")

            let imageSize = (subtitle.imageXOffset ?? 0) * (subtitle.imageHeight ?? 0)
            if let bitmapData = rect.pointee.data.0 {
                let buffer = UnsafeBufferPointer(start: bitmapData, count: imageSize)
                subtitle.imageData = Data(buffer)
            }
        }

        return subtitle
    }

    func convertPTSToTimeInterval(pts: Int64, timeBase: AVRational) -> TimeInterval {
        // Time base num is the number of units in one second.
        // Time base den is the number of units in one second divided by the base.
        let seconds = Double(pts) * av_q2d(timeBase)
        return TimeInterval(seconds)
    }
}
