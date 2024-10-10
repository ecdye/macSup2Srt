//
// PDS.swift
// macSubtitleOCR
//
// Created by Ethan Dye on 9/8/24.
// Copyright © 2024 Ethan Dye. All rights reserved.
//

import Foundation
import simd

struct PDS {
    // MARK: - Properties

    private(set) var palette = [UInt8](repeating: 0, count: 1024)

    // MARK: - Lifecycle

    init(_ data: Data) throws {
        guard data.count >= 7, (data.count - 2) % 5 == 0 else {
            throw macSubtitleOCRError.invalidPDSDataLength(length: data.count)
        }
        parsePDS(data.advanced(by: 2))
    }

    // MARK: - Methods

    // Parses the Palette Definition Segment (PDS) to extract the RGBA palette.
    // PDS structure:
    //   1 byte: Segment Type (0x16); already checked by the caller
    //   1 byte: Palette ID (unused by us)
    //   1 byte: Palette Version (unused by us)
    //   Followed by a series of palette entries:
    //       Each entry is 5 bytes: (Index, Y, Cr, Cb, Alpha)
    private mutating func parsePDS(_ data: Data) {
        // Start reading after the first 2 bytes (Palette ID and Version)
        var i = 0
        while i + 4 <= data.count {
            let index = data[i]
            let y = data[i + 1]
            let cr = data[i + 2]
            let cb = data[i + 3]
            let alpha = data[i + 4]

            // Convert YCrCb to RGB
            let rgb = yCrCbToRGB(y: y, cr: cr, cb: cb)

            // Store RGBA values to palette table
            palette[Int(index) * 4 + 0] = rgb.red
            palette[Int(index) * 4 + 1] = rgb.green
            palette[Int(index) * 4 + 2] = rgb.blue
            palette[Int(index) * 4 + 3] = alpha
            i += 5
        }
    }

    private func yCrCbToRGB(y: UInt8, cr: UInt8, cb: UInt8) -> (red: UInt8, green: UInt8, blue: UInt8) {
        let y = min(max(Double(y) - 16.0, 0), 255.0)
        let cr = min(max(Double(cr) - 128, 0), 255.0)
        let cb = min(max(Double(cb) - 128.0, 0), 255.0)
        let yCbCr = simd_double3(y, cb, cr)

        // Color conversion matrix for BT.709
        let matrix = simd_double3x3(simd_double3(1.164, 0, 1.793),
                                    simd_double3(1.164, -0.213, -0.533),
                                    simd_double3(1.164, 2.112, 0))

        let rgb = yCbCr * matrix

        // Clamp to 0-255
        let red = UInt8(min(max(rgb[0], 0), 255))
        let green = UInt8(min(max(rgb[1], 0), 255))
        let blue = UInt8(min(max(rgb[2], 0), 255))

        return (red: red, green: green, blue: blue)
    }
}
