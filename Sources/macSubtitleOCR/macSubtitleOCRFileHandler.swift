//
// macSubtitleOCRFileHandler.swift
// macSubtitleOCR
//
// Created by Ethan Dye on 10/17/24.
// Copyright © 2024-2026 Ethan Dye. All rights reserved.
//

import Foundation

struct macSubtitleOCRFileHandler {
    private let outputDirectory: URL

    init(outputDirectory: String) throws {
        self.outputDirectory = URL(fileURLWithPath: outputDirectory)
        try FileManager.default.createDirectory(
            at: self.outputDirectory,
            withIntermediateDirectories: true,
            attributes: nil)
    }

    func saveSRTFile(for result: macSubtitleOCRResult) throws {
        if result.srt.isEmpty {
            return
        }
        let srtFilePath = outputDirectory.appendingPathComponent("track_\(result.trackNumber).srt")
        let srt = SRT(subtitles: result.srt.sorted { $0.index < $1.index })
        srt.write(toFileAt: srtFilePath)
    }

    func saveJSONFile(for result: macSubtitleOCRResult) throws {
        let jsonResults = result.json.sorted { $0.index < $1.index }.map { jsonResult in
            [
                "image": jsonResult.index,
                "lines": jsonResult.lines.map { line in
                    [
                        "text": line.text,
                        "confidence": line.confidence,
                        "x": line.x,
                        "width": line.width,
                        "y": line.y,
                        "height": line.height,
                        "alternates": line.alternates
                    ] as [String: Any]
                },
                "text": jsonResult.text
            ] as [String: Any]
        }

        let jsonData = try JSONSerialization.data(withJSONObject: jsonResults, options: [.prettyPrinted, .sortedKeys])
        let jsonString = String(data: jsonData, encoding: .utf8) ?? "[]"
        let jsonFilePath = outputDirectory.appendingPathComponent("track_\(result.trackNumber).json")
        try jsonString.write(to: jsonFilePath, atomically: true, encoding: .utf8)
    }
}
