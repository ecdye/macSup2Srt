//
// SubtitleProcessor.swift
// macSubtitleOCR
//
// Created by Ethan Dye on 10/17/24.
// Copyright © 2024-2026 Ethan Dye. All rights reserved.
//

import CoreGraphics
import Foundation
import UniformTypeIdentifiers
import Vision

private typealias TextRecognizer = @Sendable (CGImage) async -> (String, [SubtitleLine])

/// A copy of `image` at twice the size, sitting on a white margin, or nil if it cannot be drawn.
///
/// The margin is there for a stroke that runs to the edge of the frame. Subtitle frames are cropped
/// to their visible pixels, so a glyph can end up flush against the border with nowhere for the
/// recognizer's box to extend, and it reads the line without that glyph: an image of "I can't." comes
/// back as "can't." Any margin of a few pixels restores it.
private func enlarged(_ image: CGImage) -> CGImage? {
    let margin = 4
    let width = image.width * 2 + margin * 2
    let height = image.height * 2 + margin * 2
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    guard let context else { return nil }
    context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: margin, y: margin, width: image.width * 2, height: image.height * 2))
    return context.makeImage()
}

private struct OCRSubtitleTaskInput {
    let index: Int
    let startTimestamp: TimeInterval?
    let endTimestamp: TimeInterval?
    let imageSource: SubtitleImageSource?

    init(_ subtitle: Subtitle) {
        index = subtitle.index
        startTimestamp = subtitle.startTimestamp
        endTimestamp = subtitle.endTimestamp
        imageSource = subtitle.makeImageSource()
    }

    func makeSubtitle(text: String) -> Subtitle {
        Subtitle(index: index, text: text, startTimestamp: startTimestamp, endTimestamp: endTimestamp)
    }
}

struct SubtitleProcessor {
    private let subtitles: [Subtitle]
    private let trackNumber: Int
    private let invert: Bool
    private let saveImages: Bool
    private let language: String
    private let customWords: [String]?
    private let fastMode: Bool
    private let disableLanguageCorrection: Bool
    private let disableICorrection: Bool
    private let forceOldAPI: Bool
    private let outputDirectory: String
    private let maxConcurrentTasks: Int

    init(for subtitles: [Subtitle], from trackNumber: Int, withOptions invert: Bool, _ saveImages: Bool, _ language: String,
         _ customWords: [String]?, _ fastMode: Bool, _ disableLanguageCorrection: Bool, _ disableICorrection: Bool,
         _ forceOldAPI: Bool, _ outputDirectory: String, _ maxConcurrentTasks: Int) {
        self.subtitles = subtitles
        self.trackNumber = trackNumber
        self.invert = invert
        self.saveImages = saveImages
        self.language = language
        self.customWords = customWords
        self.fastMode = fastMode
        self.disableLanguageCorrection = disableLanguageCorrection
        self.disableICorrection = disableICorrection
        self.forceOldAPI = forceOldAPI
        self.outputDirectory = outputDirectory
        self.maxConcurrentTasks = maxConcurrentTasks
    }

    func process() async throws -> macSubtitleOCRResult {
        let accumulator = SubtitleAccumulator()
        let taskInputs = subtitles.map(OCRSubtitleTaskInput.init)
        let recognizer = makeTextRecognizer()

        // Keep at most `maxConcurrentTasks` subtitles in flight by refilling the group as tasks finish.
        // Adding every subtitle up front and gating on a semaphore leaves the surplus tasks spinning on
        // the cooperative thread pool, which starves the continuations Vision needs to complete a request.
        try await withThrowingTaskGroup(of: Void.self) { group in
            var pending = taskInputs.makeIterator()

            for _ in 0 ..< maxConcurrentTasks {
                guard let taskInput = pending.next() else { break }
                group.addTask { await recognize(taskInput, into: accumulator, using: recognizer) }
            }

            while try await group.next() != nil {
                guard let taskInput = pending.next() else { continue }
                group.addTask { await recognize(taskInput, into: accumulator, using: recognizer) }
            }
        }

        let recognized = await accumulator.subtitles
        reportSubtitlesWithoutText(in: recognized)

        return await macSubtitleOCRResult(trackNumber: trackNumber, srt: recognized, json: accumulator.json)
    }

    /// Names every subtitle that came back with no text at all.
    ///
    /// A cue carrying correct timing and an empty body reads as valid output, so losing one is only
    /// visible to someone scanning the file for blanks. Saying which cues they are makes the loss
    /// something the run reports rather than something the output hides.
    private func reportSubtitlesWithoutText(in subtitles: [Subtitle]) {
        let blank = subtitles.filter { $0.text?.isEmpty ?? true }.sorted { $0.index < $1.index }
        guard !blank.isEmpty else { return }

        for subtitle in blank {
            let at = subtitle.startTimestamp?.srtTimestamp ?? "an unknown time"
            print("No text recognized for track \(trackNumber), subtitle \(subtitle.index) at \(at)", to: &stderr)
        }
        print("Track \(trackNumber): \(blank.count) of \(subtitles.count) subtitles produced no text", to: &stderr)
    }

    private func recognize(_ taskInput: OCRSubtitleTaskInput, into accumulator: SubtitleAccumulator,
                           using recognizer: TextRecognizer) async {
        let subIndex = taskInput.index

        guard !shouldSkip(taskInput), let imageSource = taskInput.imageSource,
              let subImage = imageSource.createImage(invert) else {
            print("Found invalid image for track: \(trackNumber), index: \(subIndex), creating an empty placeholder!")
            await accumulator.append(taskInput.makeSubtitle(text: ""),
                                     SubtitleJSONResult(index: subIndex, lines: [], text: ""))
            return
        }

        // Save subtitle image as PNG if requested
        if saveImages {
            do {
                try saveImage(subImage, index: subIndex)
            } catch {
                print("Error saving image \(trackNumber)-\(subIndex): \(error.localizedDescription)", to: &stderr)
            }
        }

        let (subtitleText, subtitleLines) = await recognizer(subImage)
        let correctedText: String
        if language.contains("en"), !disableICorrection {
            let pattern = #"\bl\b"# // Replace l with I when it's a single character
            correctedText = subtitleText.replacingOccurrences(of: pattern, with: "I", options: .regularExpression)
        } else {
            correctedText = subtitleText
        }

        let jsonOut = SubtitleJSONResult(index: subIndex, lines: subtitleLines, text: correctedText)

        await accumulator.append(taskInput.makeSubtitle(text: correctedText), jsonOut)
    }

    /// Vision's recognizer draws on a multilingual character inventory whatever `recognitionLanguages`
    /// asks for, so an English only track comes back with the odd Cyrillic or Greek letter. A lower
    /// ranked candidate is usually the same words spelled in the expected script, so ask for a few.
    private var candidatesToConsider: Int {
        expectsLatinScript ? 5 : 1
    }

    /// Chooses the candidate to keep, along with the text to record for it and the readings not taken.
    ///
    /// If the best candidate is wrong only in being spelled with characters drawn as Latin ones, it is
    /// repaired in place; the reading was right and the alternatives are worse. If a foreign letter
    /// survives that, the glyph was genuinely misread rather than substituted, and the ranking among
    /// candidates already in the right script is more trustworthy than repairing a worse one.
    private func bestCandidate<T>(among candidates: [(T, String)]) -> (candidate: T, text: String,
                                                                       alternates: [String])? {
        guard let first = candidates.first else { return nil }
        guard expectsLatinScript else {
            return (first.0, first.1, candidates.dropFirst().map(\.1))
        }

        let repaired = candidates.map { ($0.0, LatinConfusables.normalize($0.1)) }
        let chosen = !containsForeignLetters(repaired[0].1)
            ? repaired[0]
            : repaired.first { !containsForeignLetters($0.1) } ?? repaired[0]
        let alternates = repaired.map(\.1).filter { $0 != chosen.1 }
        return (chosen.0, chosen.1, alternates)
    }

    private func shouldSkip(_ taskInput: OCRSubtitleTaskInput) -> Bool {
        guard let imageSource = taskInput.imageSource else {
            return true
        }
        return imageSource.width == 0 || imageSource.height == 0
    }

    /// Builds the text recognizer shared by every subtitle in the track.
    ///
    /// Vision builds its recognition engine while performing a request, so creating a request per image
    /// makes it build a fresh engine per image. Those constructions are not thread safe and corrupt each
    /// other when they overlap, so a single request is reused for the whole track instead.
    ///
    /// An image that recognizes as nothing at all is read twice more before it is written off as blank,
    /// because a cue carrying correct timing and no text reads as valid output and hides its own loss.
    /// Language correction can discard an observation outright rather than return a reading its language
    /// model cannot account for, so a short line offering it no context, a subtitle holding nothing but
    /// a team name for instance, comes back empty; switching correction off recovers the text the
    /// detector already had. A small image can also fall under whatever size the recognizer wants,
    /// which doubling it clears. Both readings are only ever reached from nothing, so neither can cost
    /// a subtitle a reading it already had.
    private func makeTextRecognizer() -> TextRecognizer {
        if !forceOldAPI, #available(macOS 15.0, *) {
            let request = createRecognizeTextRequest(usingLanguageCorrection: !disableLanguageCorrection)
            let uncorrected = disableLanguageCorrection
                ? nil
                : createRecognizeTextRequest(usingLanguageCorrection: false)

            @Sendable func read(_ image: CGImage) async -> [RecognizedTextObservation] {
                if let observations = try? await request.perform(on: image), !observations.isEmpty {
                    return observations
                }
                guard let uncorrected else { return [] }
                return await (try? uncorrected.perform(on: image)) ?? []
            }

            return { image in
                var observations = await read(image)
                if observations.isEmpty, let enlarged = enlarged(image) {
                    observations = await read(enlarged)
                }
                var text = ""
                var lines: [SubtitleLine] = []
                // Bounding boxes arrive normalized, so scaling them by the original image keeps them in
                // its coordinates whichever copy was read.
                let size = CGSize(width: image.width, height: image.height)
                processRecognizedText(observations, &text, &lines, size)
                return (text, lines)
            }
        }

        let queue = DispatchQueue(label: "com.ecdye.macSubtitleOCR.textRecognition", attributes: .concurrent)
        return { image in
            await withCheckedContinuation { continuation in
                // `VNImageRequestHandler.perform` blocks its caller until Vision is done. Running it on a
                // Swift concurrency executor would tie up one of the cooperative pool's fixed number of
                // threads, and enough concurrent requests deadlock the pool, so it runs on its own queue.
                queue.async {
                    func read(_ image: CGImage) -> [VNRecognizedTextObservation] {
                        let request = createLegacyRecognizeTextRequest(
                            usingLanguageCorrection: !disableLanguageCorrection)
                        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
                        if let results = request.results, !results.isEmpty {
                            return results
                        }
                        guard !disableLanguageCorrection else { return [] }
                        let uncorrected = createLegacyRecognizeTextRequest(usingLanguageCorrection: false)
                        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([uncorrected])
                        return uncorrected.results ?? []
                    }

                    var results = read(image)
                    if results.isEmpty, let enlarged = enlarged(image) {
                        results = read(enlarged)
                    }
                    var text = ""
                    var lines: [SubtitleLine] = []
                    processRecognizedText(results, &text, &lines, image.width, image.height)
                    continuation.resume(returning: (text, lines))
                }
            }
        }
    }

    /// True when every requested language is written in the Latin script.
    private var expectsLatinScript: Bool {
        language.split(separator: ",").allSatisfy { code in
            Locale.Language(identifier: String(code)).script == Locale.Script.latin
        }
    }

    /// True if `string` holds a letter no Latin script language is written with.
    ///
    /// Latin here means the blocks a Latin script language actually draws on: ASCII letters, the
    /// Latin-1 Supplement through Latin Extended-B, and Latin Extended Additional.
    private func containsForeignLetters(_ string: String) -> Bool {
        string.unicodeScalars.contains { scalar in
            guard scalar.properties.isAlphabetic else { return false }
            switch scalar.value {
            case 0x41 ... 0x5A, 0x61 ... 0x7A, 0xC0 ... 0x24F, 0x1E00 ... 0x1EFF:
                return false
            default:
                return true
            }
        }
    }

    @available(macOS 15.0, *)
    private func createRecognizeTextRequest(usingLanguageCorrection: Bool) -> RecognizeTextRequest {
        var request = RecognizeTextRequest()
        request.recognitionLevel = getOCRMode()
        request.usesLanguageCorrection = usingLanguageCorrection
        request.recognitionLanguages = language.split(separator: ",").map { Locale.Language(identifier: String($0)) }
        if let customWords {
            request.customWords = customWords
        }
        return request
    }

    private func createLegacyRecognizeTextRequest(usingLanguageCorrection: Bool) -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = getOCRMode()
        request.usesLanguageCorrection = usingLanguageCorrection
        request.revision = VNRecognizeTextRequestRevision3
        request.recognitionLanguages = language.split(separator: ",").map { String($0) }
        if let customWords {
            request.customWords = customWords
        }
        return request
    }

    @available(macOS 15.0, *)
    private func processRecognizedText(_ result: [RecognizedTextObservation]?, _ text: inout String,
                                       _ lines: inout [SubtitleLine], _ size: CGSize) {
        text = result?.compactMap { observation in
            let candidates = observation.topCandidates(candidatesToConsider)
            guard let (candidate, string, alternates) = bestCandidate(among: candidates.map { ($0, $0.string) })
            else { return "" }
            let confidence = candidate.confidence
            let stringRange = string.startIndex ..< string.endIndex
            let boundingBox = candidate.boundingBox(for: stringRange)?.boundingBox
            let rect = boundingBox?.toImageCoordinates(size, origin: .upperLeft) ?? .zero
            let line = SubtitleLine(
                text: string,
                confidence: confidence,
                x: max(0, Int(rect.minX)),
                width: Int(rect.size.width),
                y: max(0, Int(size.height - rect.minY - rect.size.height)),
                height: Int(rect.size.height),
                alternates: alternates)
            lines.append(line)

            return string
        }.joined(separator: "\n") ?? ""
    }

    private func processRecognizedText(_ observations: [VNRecognizedTextObservation]?, _ text: inout String,
                                       _ lines: inout [SubtitleLine], _ width: Int, _ height: Int) {
        text = observations?.compactMap { observation in
            let candidates = observation.topCandidates(candidatesToConsider)
            guard let (candidate, string, alternates) = bestCandidate(among: candidates.map { ($0, $0.string) })
            else { return "" }
            let confidence = candidate.confidence
            let stringRange = string.startIndex ..< string.endIndex
            let boundingBox = try? candidate.boundingBox(for: stringRange)?.boundingBox
            let rect = VNImageRectForNormalizedRect(boundingBox ?? .zero, width, height)

            let line = SubtitleLine(
                text: string,
                confidence: confidence,
                x: max(0, Int(rect.minX)),
                width: Int(rect.size.width),
                y: max(0, Int(CGFloat(height) - rect.minY - rect.size.height)),
                height: Int(rect.size.height),
                alternates: alternates)
            lines.append(line)

            return string
        }.joined(separator: "\n") ?? ""
    }

    private func saveImage(_ image: CGImage, index: Int) throws {
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

    @available(macOS 15.0, *)
    private func getOCRMode() -> RecognizeTextRequest.RecognitionLevel {
        fastMode ? .fast : .accurate
    }

    private func getOCRMode() -> VNRequestTextRecognitionLevel {
        fastMode ? .fast : .accurate
    }
}
