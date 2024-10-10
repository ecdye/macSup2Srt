//
// MKVHelpers.swift
// macSubtitleOCR
//
// Created by Ethan Dye on 9/16/24.
// Copyright © 2024 Ethan Dye. All rights reserved.
//

import Foundation

// Function to read a fixed length number of bytes and convert in into a (Un)signed integer
func readFixedLengthNumber(fileHandle: FileHandle, length: Int, signed: Bool = false) -> Int64 {
    let data = fileHandle.readData(ofLength: length)
    var result: Int64 = 0

    for byte in data {
        result = result << 8 | Int64(byte)
    }

    if signed, data.first! & 0x80 != 0 {
        result -= Int64(1) << (8 * length) // Apply two's complement for signed integers
    }

    return result
}

// Encode the absolute timestamp as 4 bytes in big-endian format for PGS
func encodePTSForPGS(_ timestamp: Int64) -> [UInt8] {
    withUnsafeBytes(of: UInt32(timestamp).bigEndian) { Array($0) }
}

// Calculate the absolute timestamp with 90 kHz accuracy for PGS format
func calcAbsPTSForPGS(_ clusterTimestamp: Int64, _ blockTimestamp: Int64, _ timestampScale: Double) -> Int64 {
    // The block timestamp is relative, so we add it to the cluster timestamp
    Int64(((Double(clusterTimestamp) + Double(blockTimestamp)) / timestampScale) * 90000000)
}
