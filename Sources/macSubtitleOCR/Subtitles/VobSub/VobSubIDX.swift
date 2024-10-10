//
// VobSubIDX.swift
// macSubtitleOCR
//
// Created by Ethan Dye on 10/4/24.
// Copyright © 2024 Ethan Dye. All rights reserved.
//

import Foundation

struct VobSubIDX {
    // MARK: - Properties

    private(set) var timestamps: [TimeInterval] = []
    private(set) var offsets: [UInt64] = []
    private(set) var palette: [UInt8] = []

    // MARK: - Lifecycle

    init(_ url: URL) {
        do {
            let idxData = try String(contentsOf: url, encoding: .utf8)
            try parseIdxFile(idxData: idxData)
        } catch {
            fatalError("Error: Failed to parse IDX file: \(error)")
        }
    }

    // MARK: - Methods

    private mutating func parseIdxFile(idxData: String) throws {
        let lines = idxData.split(separator: "\n")

        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Handle palette line
            if trimmedLine.starts(with: "palette:") {
                palette = parsePalette(line: trimmedLine)
                continue
            } else if !trimmedLine.starts(with: "timestamp:") {
                continue
            }

            // Handle timestamp and filepos in one go
            guard let timestamp = extractTimestamp(from: trimmedLine),
                  let offset = extractOffset(from: trimmedLine)
            else {
                throw macSubtitleOCRError.fileReadError
            }
            offsets.append(offset)
            timestamps.append(timestamp)
        }
    }

    // Extract timestamp from a line starting with "timestamp:"
    private func extractTimestamp(from line: String) -> TimeInterval? {
        guard line.starts(with: "timestamp:") else { return nil }

        // Split line by " " to get timestamp part
        let components = line.split(separator: " ")
        guard components.count > 1 else { return nil }

        let timestampString = String(components[1].dropLast())
        return convertTimestampToTimeInterval(timestampString)
    }

    // Extract file offset from a line starting with "filepos:"
    private func extractOffset(from line: String) -> UInt64? {
        guard let fileposRange = line.range(of: "filepos:") else { return nil }

        let offsetString = line[fileposRange.upperBound...].trimmingCharacters(in: .whitespaces)
        return UInt64(offsetString, radix: 16) // Convert hex string to UInt64
    }

    // Convert "hh:mm:ss:ms" timestamp string to TimeInterval (seconds)
    private func convertTimestampToTimeInterval(_ timestamp: String) -> TimeInterval? {
        let components = timestamp.split(separator: ":")

        guard components.count == 4,
              let hours = Double(components[0]),
              let minutes = Double(components[1]),
              let seconds = Double(components[2]),
              let milliseconds = Double(components[3])
        else {
            return nil
        }

        return (hours * 3600) + (minutes * 60) + seconds + (milliseconds / 1000)
    }

    // Function to parse the palette from the line
    private func parsePalette(line: String) -> [UInt8] {
        let paletteString = line.replacingOccurrences(of: "palette: ", with: "")
        return paletteString.split(separator: ", ").compactMap { String($0).hexToBytes }.flatMap { $0 }
    }
}
