//
// ODS.swift
// macSubtitleOCR
//
// Created by Ethan Dye on 9/19/24.
// Copyright © 2024 Ethan Dye. All rights reserved.
//

import Foundation

struct ODS {
    // MARK: - Properties

    private(set) var objectWidth: Int = 0
    private(set) var objectHeight: Int = 0
    private var rawImageData: Data = .init()
    private(set) var imageData: Data = .init()

    // MARK: - Lifecycle

    init(_ data: Data) throws {
        try parseODS(data)
    }

    mutating func appendSegment(_ data: Data) throws {
        try parseODS(data)
    }

    // MARK: - Methods

    // Parses the Object Definition Segment (ODS) to extract the subtitle image bitmap.
    // ODS structure (simplified):
    //   0x17: Segment Type; already checked by the caller
    //   2 bytes: Object ID (unused by us)
    //   1 byte: Version number (unused by us)
    //   1 byte: Sequence flag (0x80: First in sequence, 0x40: Last in sequence,
    //                          0xC0: First and last in sequence (0x40 | 0x80))
    //   3 bytes: Object data length (unused by us)
    //   2 bytes: Object width
    //   2 bytes: Object height
    //   Rest: Image data (run-length encoded, RLE)
    private mutating func parseODS(_ data: Data) throws {
        let sequenceFlag = data[3]
        if sequenceFlag != 0x40 {
            objectWidth = Int(data.value(ofType: UInt16.self, at: 7) ?? 0)
            objectHeight = Int(data.value(ofType: UInt16.self, at: 9) ?? 0)
        }

        // PGS includes the width and height as part of the image data length calculations
        guard data.count > 7 else {
            throw macSubtitleOCRError.invalidODSDataLength(length: data.count)
        }

        switch sequenceFlag {
        case 0x40:
            rawImageData.append(data[4...])
            imageData = decodeRLEData()
        case 0x80:
            rawImageData.append(data[11...])
        default:
            rawImageData.append(data[11...])
            imageData = decodeRLEData()
        }
    }

    private func decodeRLEData() -> Data {
        let rleImageData = RLEData(data: rawImageData, width: objectWidth, height: objectHeight)
        return rleImageData.decodePGS()
    }
}
