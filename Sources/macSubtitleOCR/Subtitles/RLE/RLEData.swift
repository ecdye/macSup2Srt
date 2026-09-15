//
// RLEData.swift
// macSubtitleOCR
//
// Created by Ethan Dye on 9/19/24.
// Copyright © 2024-2026 Ethan Dye. All rights reserved.
//

import Foundation

struct RLEData {
    // MARK: - Properties

    private var width: Int
    private var height: Int
    private var data: Data
    private var evenOffset: Int?
    private var oddOffset: Int?

    // MARK: - Lifecycle

    init(data: Data, width: Int, height: Int, evenOffset: Int? = nil, oddOffset: Int? = nil) {
        self.width = width
        self.height = height
        self.data = data
        self.evenOffset = evenOffset
        self.oddOffset = oddOffset
    }

    // MARK: - Functions

    func decodePGS() throws -> Data {
        if data.isEmpty || width <= 0 || height <= 0 {
            return data
        }
        var pixelCount = 0
        var lineCount = 0
        var iterator = data.makeIterator()

        var image = Data()

        while var color: UInt8 = iterator.next(), lineCount < height {
            var run = 1

            if color == 0x00 {
                guard let flags = iterator.next() else {
                    throw macSubtitleOCRError.invalidRLE("Ran out of RLE data reading a run-length flag.")
                }
                run = Int(flags & 0x3F)
                if flags & 0x40 != 0 {
                    guard let extendedRun = iterator.next() else {
                        throw macSubtitleOCRError.invalidRLE("Ran out of RLE data reading an extended run length.")
                    }
                    run = (run << 8) + Int(extendedRun)
                }
                if flags & 0x80 != 0 {
                    guard let runColor = iterator.next() else {
                        throw macSubtitleOCRError.invalidRLE("Ran out of RLE data reading a run color.")
                    }
                    color = runColor
                } else {
                    color = 0
                }
            }

            // Ensure run is valid and doesn't exceed pixel buffer
            if run > 0, pixelCount + run <= width * height {
                // Fill the pixel data with the decoded color
                image.append(contentsOf: repeatElement(color, count: run))
                pixelCount += run
            } else if run == 0 {
                // New Line: Check if pixels align correctly
                if pixelCount % width > 0 {
                    throw macSubtitleOCRError
                        .invalidRLE("Decoded \(pixelCount % width) pixels, but line should be \(width) pixels.")
                }
                lineCount += 1
            }
        }

        // Check if we decoded enough pixels
        if pixelCount < width * height {
            throw macSubtitleOCRError.invalidRLE("Insufficient RLE data for subtitle.")
        }

        return image
    }

    func decodeVobSub() throws -> Data {
        guard !data.isEmpty, width > 0, height > 0 else { return data }
        let (pixelCount, overflow) = width.multipliedReportingOverflow(by: height)
        guard !overflow else {
            throw macSubtitleOCRError.invalidRLE("VobSub image dimensions overflow.")
        }
        let bytes = Array(data)
        var image = [UInt8](repeating: 0, count: pixelCount)

        // DVD subpictures encode alternating rows in two independently byte-aligned
        // fields. Their offsets are authoritative: padding between fields is not
        // pixel data, and an odd-height image has one extra row in its first field.
        for field in 0 ..< min(2, height) {
            guard let offset = field == 0 ? evenOffset : oddOffset,
                  offset >= 0, offset < bytes.count
            else {
                throw macSubtitleOCRError.invalidRLE("Invalid VobSub field offset.")
            }
            var position = offset * 2
            func readNibble() throws -> Int {
                guard position / 2 < bytes.count else {
                    throw macSubtitleOCRError.invalidRLE("Insufficient VobSub RLE data.")
                }
                let byte = bytes[position / 2]
                let value = position % 2 == 0 ? byte >> 4 : byte & 0x0F
                position += 1
                return Int(value)
            }

            for y in stride(from: field, to: height, by: 2) {
                var x = 0
                while x < width {
                    var code = try readNibble()
                    if code < 0x04 {
                        code = try (code << 4) | readNibble()
                        if code < 0x10 {
                            code = try (code << 4) | readNibble()
                            if code < 0x40 {
                                code = try (code << 4) | readNibble()
                            }
                        }
                    }
                    let color = UInt8(code & 0x03)
                    let run = code < 4 ? width - x : code >> 2
                    guard run <= width - x else {
                        throw macSubtitleOCRError.invalidRLE("VobSub run exceeds the row width.")
                    }
                    for column in x ..< x + run {
                        image[y * width + column] = color
                    }
                    x += run
                }
                // A row always starts on a byte boundary, even when its last run
                // used only the high nibble of a byte.
                position = (position + 1) & ~1
            }
        }
        return Data(image)
    }
}
