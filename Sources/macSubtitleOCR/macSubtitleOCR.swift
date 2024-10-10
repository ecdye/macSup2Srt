//
// macSubtitleOCR.swift
// macSubtitleOCR
//
// Created by Ethan Dye on 9/2/24.
// Copyright © 2024 Ethan Dye. All rights reserved.
//

import ArgumentParser
import os
import UniformTypeIdentifiers
import Vision

private let logger: Logger = .init(subsystem: "github.ecdye.macSubtitleOCR", category: "main")

// The main struct representing the macSubtitleOCR command-line tool.
@main
struct macSubtitleOCR: ParsableCommand {
    // MARK: - Properties

    @Argument(help: "Input file containing the subtitle stream (.sup, .sub, .idx, or .mkv)")
    var input: String

    @Argument(help: "Directory to output files to")
    var outputDirectory: String

    @Option(wrappedValue: "en", help: "The input image language(s)")
    var language: String

    @Flag(help: "Use internal decoder (experimental)")
    var internalDecoder = false

    @Flag(help: "Save image files for subtitle track (optional)")
    var saveImages = false

    @Flag(help: "Save the raw json results from OCR (optional)")
    var json = false

    @Flag(help: "Enable fast mode (less accurate)")
    var fastMode = false

    @Flag(help: "Enable language correction")
    var languageCorrection = false

    @Flag(help: "Save extracted subtitle file to disk (MKV input only)")
    var saveSubtitleFile = false

    // MARK: - Entrypoint

    func run() throws {
        let fileManager = FileManager.default
        var intermediateFiles: [Int: String] = [:]
        var results: [macSubtitleOCRResult] = []
        let outputDirectory = URL(fileURLWithPath: outputDirectory)

        if internalDecoder {
            if input.hasSuffix(".sub") || input.hasSuffix(".idx") {
                let sub = try VobSub(
                    input.replacingOccurrences(of: ".idx", with: ".sub"),
                    input.replacingOccurrences(of: ".sub", with: ".idx"))
                let result = try processSubtitles(subtitles: sub.subtitles, trackNumber: 0)
                results.append(result)
            } else if input.hasSuffix(".mkv") {
                let mkvStream = MKVSubtitleExtractor(filePath: input)
                try mkvStream.parseTracks(codec: "S_HDMV/PGS")
                for track in mkvStream.tracks {
                    logger.debug("Found subtitle track: \(track.trackNumber), Codec: \(track.codecId)")
                    if saveSubtitleFile {
                        intermediateFiles[track.trackNumber] = try mkvStream.getSubtitleTrackData(
                            trackNumber: track.trackNumber,
                            outputDirectory: outputDirectory)!
                    }

                    // Open the PGS data stream
                    let PGS = try PGS(mkvStream.tracks[track.trackNumber].trackData)

                    let result = try processSubtitles(subtitles: PGS.subtitles, trackNumber: track.trackNumber)
                    results.append(result)
                }
            } else if input.hasSuffix(".sup") {
                // Open the PGS data stream
                let PGS = try PGS(URL(fileURLWithPath: input))
                let result = try processSubtitles(subtitles: PGS.subtitles, trackNumber: 0)
                results.append(result)
            }
        } else {
            let ffmpeg = try FFmpeg(input)
            let result = try processSubtitles(subtitles: ffmpeg.subtitles, trackNumber: 0)
            results.append(result)
        }

        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true, attributes: nil)
        for result in results {
            autoreleasepool {
                // Save srt file
                let srtFilePath = outputDirectory.appendingPathComponent("track_\(result.trackNumber).srt")
                let srt = SRT(subtitles: result.srt)
                srt.write(toFileAt: srtFilePath)

                // Save json file
                if json {
                    // Convert subtitle data to JSON
                    let jsonData = try? JSONSerialization.data(
                        withJSONObject: result.json,
                        options: [.prettyPrinted, .sortedKeys])
                    let jsonString = (String(data: jsonData ?? Data(), encoding: .utf8) ?? "[]")
                    let jsonFilePath = outputDirectory.appendingPathComponent("track_\(result.trackNumber).json")
                    try? jsonString.write(to: jsonFilePath, atomically: true, encoding: .utf8)
                }
            }
        }
    }

    // MARK: - Methods

    private func getOCRMode() -> VNRequestTextRecognitionLevel {
        if fastMode {
            VNRequestTextRecognitionLevel.fast
        } else {
            VNRequestTextRecognitionLevel.accurate
        }
    }

    private func saveImages(image: CGImage, trackNumber: Int = 0, index: Int) throws {
        let outputDirectory = URL(fileURLWithPath: outputDirectory)
        let imageDirectory = outputDirectory.appendingPathComponent("images/" + "track_\(trackNumber)/")
        let pngPath = imageDirectory.appendingPathComponent("subtitle_\(index).png")

        try FileManager.default.createDirectory(at: imageDirectory, withIntermediateDirectories: true, attributes: nil)

        let destination = CGImageDestinationCreateWithURL(pngPath as CFURL, UTType.png.identifier as CFString, 1, nil)
        guard let destination else {
            throw macSubtitleOCRError.fileCreationError
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw macSubtitleOCRError.fileWriteError
        }
    }

    private func processSubtitles(subtitles: [Subtitle], trackNumber: Int) throws -> macSubtitleOCRResult {
        var subIndex = 1
        var json: [Any] = []
        var srtSubtitles: [Subtitle] = []

        for subtitle in subtitles {
            if subtitle.imageWidth == 0, subtitle.imageHeight == 0 {
                logger.debug("Skipping subtitle index \(subIndex) with empty image data!")
                continue
            }

            if subIndex < subtitles.count, subtitles[subIndex].startTimestamp! <= subtitle.endTimestamp! {
                logger.warning("Fixing subtitle index \(subIndex) end timestamp!")
                subtitle.endTimestamp = subtitles[subIndex].startTimestamp! - 0.1
            }

            guard let subImage = subtitle.createImage()
            else {
                logger.info("Could not create image for index \(subIndex)! Skipping...")
                continue
            }

            // Save subtitle image as PNG if requested
            if saveImages {
                do {
                    try saveImages(image: subImage, trackNumber: trackNumber, index: subIndex)
                } catch {
                    logger.error("Error saving image \(trackNumber)-\(subIndex): \(error.localizedDescription)")
                }
            }

            // Perform text recognition
            let request = VNRecognizeTextRequest { request, _ in
                guard let observations = request.results as? [VNRecognizedTextObservation] else { return }

                var subtitleLines: [[String: Any]] = []
                var subtitleText = ""
                var index = 0
                for observation in observations {
                    let candidate = observation.topCandidates(1).first
                    let string = candidate?.string ?? ""
                    let confidence = candidate?.confidence ?? 0.0
                    let stringRange = string.startIndex ..< string.endIndex
                    let boxObservation = try? candidate?.boundingBox(for: stringRange)
                    let boundingBox = boxObservation?.boundingBox ?? .zero
                    let rect = VNImageRectForNormalizedRect(boundingBox, subtitle.imageWidth!, subtitle.imageHeight!)

                    let line: [String: Any] = [
                        "text": string,
                        "confidence": confidence,
                        "x": Int(rect.minX),
                        "width": Int(rect.size.width),
                        "y": Int(CGFloat(subtitle.imageHeight!) - rect.minY - rect.size.height),
                        "height": Int(rect.size.height)
                    ]

                    subtitleLines.append(line)
                    subtitleText += string
                    index += 1
                    if index != observations.count {
                        subtitleText += "\n"
                    }
                }

                if self.json {
                    let subtitleData: [String: Any] = [
                        "image": subIndex,
                        "lines": subtitleLines,
                        "text": subtitleText
                    ]
                    json.append(subtitleData)
                }

                srtSubtitles.append(Subtitle(index: subIndex,
                                             text: subtitleText,
                                             startTimestamp: subtitle.startTimestamp,
                                             endTimestamp: subtitle.endTimestamp))
            }

            request.recognitionLevel = getOCRMode()
            request.usesLanguageCorrection = languageCorrection
            request.revision = VNRecognizeTextRequestRevision3
            request.recognitionLanguages = language.split(separator: ",").map { String($0) }

            try? VNImageRequestHandler(cgImage: subImage, options: [:]).perform([request])

            subIndex += 1
        }
        return macSubtitleOCRResult(trackNumber: trackNumber, srt: srtSubtitles, json: json)
    }
}
