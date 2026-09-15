//
// VobSubRLETests.swift
// macSubtitleOCR
//
// Created by Tim Jenness on 9/14/26.
// Copyright © 2026-2026 Tim Jenness. All rights reserved.
//

import Foundation
@testable import macSubtitleOCR
import Testing

@Test func vobSubExtractedPacketsIncludeTheirHeaderBytesInTheLength() throws {
    let parser = try MKVTrackParser(filePath: TestFilePaths.mkv.path)
    try parser.parseTracks(for: ["S_VOBSUB"])
    let track = try #require(parser.tracks.first)
    let bytes = Array(track.trackData)
    var offset = 0
    while offset < bytes.count {
        try #require(offset + 20 <= bytes.count)
        try #require(Array(bytes[offset ..< offset + 4]) == [0, 0, 1, 0xBA])
        try #require(Array(bytes[offset + 14 ..< offset + 18]) == [0, 0, 1, 0xBD])
        let length = Int(bytes[offset + 18]) << 8 | Int(bytes[offset + 19])
        offset += 20 + length
    }
    #expect(offset == bytes.count)
}

@Test func vobSubUsesFieldOffsetsAndSkipsPadding() throws {
    let decoder = RLEData(data: Data([0xAA, 0xBB, 0x11, 0x13, 0xEE, 0xEE, 0xEE, 0x12, 0x10]),
                          width: 4, height: 4, evenOffset: 2, oddOffset: 7)
    #expect(try decoder.decodeVobSub() == Data([1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 0, 0, 0, 0]))
}

@Test func vobSubOddHeightKeepsTheLastEvenRow() throws {
    let decoder = RLEData(data: Data([0x11, 0x13, 0xEE, 0x12]),
                          width: 4, height: 3, evenOffset: 0, oddOffset: 3)
    #expect(try decoder.decodeVobSub() == Data([1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3]))
}

@Test func vobSubAlignsEachRowToAByte() throws {
    let decoder = RLEData(data: Data([0x9F, 0xBF, 0xAF]),
                          width: 2, height: 3, evenOffset: 0, oddOffset: 2)
    #expect(try decoder.decodeVobSub() == Data([1, 1, 2, 2, 3, 3]))
}

@Test func vobSubFieldsCanBeStoredInReverseOrder() throws {
    let decoder = RLEData(data: Data([0x12, 0x11]), width: 4, height: 2, evenOffset: 1, oddOffset: 0)
    #expect(try decoder.decodeVobSub() == Data([1, 1, 1, 1, 2, 2, 2, 2]))
}

@Test func vobSubDecodesAllRunLengthsAndFillToEnd() throws {
    for (bytes, width, color) in [
        ([UInt8(0xD0)], 3, UInt8(1)),
        ([0x3D], 15, 1),
        ([0x04, 0x20], 16, 2),
        ([0x01, 0x03], 64, 3),
        ([0, 3], 7, 3)
    ] {
        let decoder = RLEData(data: Data(bytes), width: width, height: 1, evenOffset: 0)
        #expect(try decoder.decodeVobSub() == Data(repeating: color, count: width))
    }
}

@Test func vobSubRejectsTruncatedRunsAndInvalidOffsets() {
    for decoder in [
        RLEData(data: Data([0]), width: 4, height: 1, evenOffset: 0),
        RLEData(data: Data([0x11]), width: 4, height: 1, evenOffset: -1),
        RLEData(data: Data([0x11]), width: 4, height: 2, evenOffset: 0, oddOffset: 1),
        RLEData(data: Data([0x11]), width: 4, height: 2, evenOffset: 0),
        RLEData(data: Data([0x11]), width: 3, height: 1, evenOffset: 0)
    ] {
        #expect(throws: macSubtitleOCRError.self) { try decoder.decodeVobSub() }
    }
}
