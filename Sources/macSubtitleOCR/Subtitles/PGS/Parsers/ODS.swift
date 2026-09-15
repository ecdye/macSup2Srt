//
// ODS.swift
// macSubtitleOCR
//
// Created by Ethan Dye on 9/19/24.
// Copyright © 2024-2026 Ethan Dye. All rights reserved.
//

import Foundation

struct ODS {
    // MARK: - Properties

    private(set) var objectWidth: Int = 0
    private(set) var objectHeight: Int = 0
    private var encodedImageData: Data = .init()

    // MARK: - Lifecycle

    init(_ buffer: UnsafeRawBufferPointer, _ offset: Int, _ segmentLength: Int) throws {
        try ODS.validate(buffer, offset, segmentLength)
        try parseODS(buffer, offset, segmentLength)
    }

    mutating func appendSegment(_ buffer: UnsafeRawBufferPointer, _ offset: Int, _ segmentLength: Int) throws {
        try ODS.validate(buffer, offset, segmentLength)
        try parseODS(buffer, offset, segmentLength)
    }

    /// A segment must carry a full header and lie entirely inside the buffer, otherwise `parseODS`
    /// reads past the end of the stream.
    private static func validate(_ buffer: UnsafeRawBufferPointer, _ offset: Int, _ segmentLength: Int) throws {
        guard segmentLength > 11, offset >= 0, offset + segmentLength <= buffer.count else {
            throw macSubtitleOCRError.invalidODSDataLength(length: segmentLength)
        }
    }

    /// Decodes the run-length encoded (RLE) image data
    func decodeRLEData() throws -> Data {
        let rleImageData = RLEData(data: encodedImageData, width: objectWidth, height: objectHeight)
        return try rleImageData.decodePGS()
    }

    // MARK: - Methods

    // Parses the Object Definition Segment (ODS) to extract the subtitle image bitmap.
    // ODS structure (simplified):
    //   0x15: Segment Type; already checked by the caller
    //   2 bytes: Object ID (unused by us)
    //   1 byte: Version number (unused by us)
    //   1 byte: Sequence flag (0x80: First in sequence, 0x40: Last in sequence,
    //                          0xC0: First and last in sequence (0x40 | 0x80))
    //   3 bytes: Object data length (unused by us)
    //   2 bytes: Object width
    //   2 bytes: Object height
    //   Rest: Image data (run-length encoded, RLE)
    private mutating func parseODS(_ buffer: UnsafeRawBufferPointer, _ offset: Int, _ segmentLength: Int) throws {
        let sequenceFlag = buffer[offset + 3]

        // Only update object dimensions if this is the first part of the sequence
        if sequenceFlag != 0x40 {
            objectWidth = Int(buffer.loadUnaligned(fromByteOffset: offset + 7, as: UInt16.self).bigEndian)
            objectHeight = Int(buffer.loadUnaligned(fromByteOffset: offset + 9, as: UInt16.self).bigEndian)
        }

        // Append image data to the encoded image data buffer
        let dataOffset = sequenceFlag == 0x40 ? offset + 4 : offset + 11
        encodedImageData.append(contentsOf: buffer[dataOffset ..< (offset + segmentLength)])
    }
}
