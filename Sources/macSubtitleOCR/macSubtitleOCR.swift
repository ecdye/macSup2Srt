//
// macSubtitleOCR.swift
// macSubtitleOCR
//
// Created by Ethan Dye on 9/2/24.
// Copyright © 2024-2026 Ethan Dye. All rights reserved.
//

import ArgumentParser
import os
import UniformTypeIdentifiers

private let logger = Logger(subsystem: "com.ecdye.macSubtitleOCR", category: "main")
nonisolated(unsafe) var stderr = FileHandleOutputStream(.standardError)

@main
struct macSubtitleOCR: AsyncParsableCommand {
    // MARK: - Properties

    static let configuration = CommandConfiguration(
        commandName: "macSubtitleOCR",
        abstract: "macSubtitleOCR - Convert bitmap subtitles into SubRip format using the macOS Vision framework")

    @Argument(help: "Input subtitle file (supported formats: .sup, .sub, .idx, .mkv)")
    var input: String

    @Argument(help: "Directory to save the output files")
    var outputDirectory: String

    @OptionGroup(title: "Options")
    var options: Options

    @OptionGroup(title: "Experimental Options", visibility: .hidden)
    var experimentalOptions: ExperimentalOptions

    // MARK: - Entrypoint

    mutating func run() async {
        // swiftformat:disable all
        do {
            let fileHandler = try macSubtitleOCRFileHandler(outputDirectory: outputDirectory)
            let results = try await processInput()
            try await saveResults(fileHandler: fileHandler, results: results)
        } catch let macSubtitleOCRError.fileReadError(string), let macSubtitleOCRError.invalidInputFile(string),
                let macSubtitleOCRError.ffmpegError(string), let macSubtitleOCRError.invalidRLE(string),
                let macSubtitleOCRError.invalidODSDimensions(string) {
            print("Error: \(string), exiting...", to: &stderr)
        } catch {
            print("Error: \(error.localizedDescription), exiting...", to: &stderr)
        }
        // swiftformat:enable all
    }

    // MARK: - Methods

    private func processInput() async throws -> [macSubtitleOCRResult] {
        #if FFMPEG
        if options.ffmpegDecoder {
            try await processFFmpegDecoder()
        } else {
            try await processInternalDecoder()
        }
        #else
        try await processInternalDecoder()
        #endif
    }

    private func processInternalDecoder() async throws -> [macSubtitleOCRResult] {
        var results: [macSubtitleOCRResult] = []

        if input.hasSuffix(".sub") || input.hasSuffix(".idx") {
            let sub = try VobSub(
                URL(fileURLWithPath: input.replacingOccurrences(of: ".idx", with: ".sub")),
                URL(fileURLWithPath: input.replacingOccurrences(of: ".sub", with: ".idx")))
            let result = try await processSubtitle(sub.subtitles, trackNumber: 0,
                                                   languages: languages(adding: sub.language))
            results.append(result)
        } else if input.hasSuffix(".mkv") || input.hasSuffix(".mks") {
            let mkvStream = try MKVSubtitleExtractor(filePath: input)
            try mkvStream.parseTracks(for: ["S_HDMV/PGS", "S_VOBSUB"])
            for track in mkvStream.tracks {
                logger.debug("Found subtitle track: \(track.trackNumber), Codec: \(track.codecID)")
                if experimentalOptions.saveSubtitleFile {
                    mkvStream.saveSubtitleTrackData(
                        trackNumber: track.trackNumber,
                        outputDirectory: URL(fileURLWithPath: outputDirectory))
                }

                if track.codecID == "S_HDMV/PGS" {
                    let pgs: PGS = try track.trackData
                        .withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
                            try PGS(buffer)
                        }
                    let result = try await processSubtitle(pgs.subtitles, trackNumber: track.trackNumber,
                                                           languages: languages(adding: track.language))
                    results.append(result)
                } else if track.codecID == "S_VOBSUB" {
                    let vobSub: VobSub = try track.trackData
                        .withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
                            try VobSub(buffer, track.idxData ?? "")
                        }
                    let result = try await processSubtitle(vobSub.subtitles, trackNumber: track.trackNumber,
                                                           languages: languages(adding: track.language))
                    results.append(result)
                }
            }
        } else if input.hasSuffix(".sup") {
            // Open the PGS data stream
            let PGS = try PGS(URL(fileURLWithPath: input))
            let result = try await processSubtitle(PGS.subtitles, trackNumber: 0,
                                                   languages: options.languages)
            results.append(result)
        } else {
            throw macSubtitleOCRError.invalidInputFile("Invalid input file type \((input as NSString).pathExtension)")
        }

        return results
    }

    #if FFMPEG
    private func processFFmpegDecoder() async throws -> [macSubtitleOCRResult] {
        var results: [macSubtitleOCRResult] = []
        let ffmpeg = try FFmpeg(input)

        for result in ffmpeg.subtitleTracks {
            logger.debug("Processing subtitle track: \(result.key)")
            let result = try await processSubtitle(result.value, trackNumber: result.key,
                                                   languages: options.languages)
            results.append(result)
        }

        return results
    }
    #endif

    /// The recognition languages for one track: the requested list plus the track's own language.
    ///
    /// Built fresh for each track. Appending onto `options.languages` instead leaves every track
    /// carrying the languages of the tracks before it, so in a file with several subtitle tracks the
    /// later ones are recognized with the earlier tracks' languages taking priority.
    private func languages(adding trackLanguage: String?) -> String {
        guard let trackLanguage else { return options.languages }
        return "\(options.languages),\(trackLanguage)"
    }

    private func processSubtitle(_ subtitles: [Subtitle], trackNumber: Int,
                                 languages: String) async throws -> macSubtitleOCRResult {
        let processor = createSubtitleProcessor(subtitles, trackNumber, languages)
        return try await processor.process()
    }

    private func createSubtitleProcessor(_ subtitles: [Subtitle], _ trackNumber: Int,
                                         _ languages: String) -> SubtitleProcessor {
        SubtitleProcessor(for: subtitles, from: trackNumber,
                          withOptions: options.invert, options.saveImages, languages,
                          options.customWords?.split(separator: ",").map(String.init), experimentalOptions.fastMode,
                          experimentalOptions.disableLanguageCorrection, options.disableICorrection,
                          experimentalOptions.forceOldAPI, outputDirectory, options.maxThreads)
    }

    private func saveResults(fileHandler: macSubtitleOCRFileHandler, results: [macSubtitleOCRResult]) async throws {
        for result in results {
            autoreleasepool {
                try? fileHandler.saveSRTFile(for: result)
                if options.json {
                    try? fileHandler.saveJSONFile(for: result)
                }
            }
        }
    }
}
