//
// DataExtensions.swift
// macSubtitleOCR
//
// Created by Ethan Dye on 9/16/24.
// Copyright © 2024 Ethan Dye. All rights reserved.
//

import Foundation

extension Data {
    // Function to remove null bytes (0x00) from Data
    mutating func removeNullBytes() {
        self = filter { $0 != 0x00 }
    }

    func value<T: BinaryInteger>(ofType _: T.Type, at offset: Int = 0, convertEndian: Bool = false) -> T? {
        let right = offset &+ MemoryLayout<T>.size
        guard offset >= 0, right > offset, right <= count else {
            return nil
        }
        let bytes = self[offset ..< right]
        if convertEndian {
            return bytes.reversed().reduce(0) { T($0) << 8 + T($1) }
        } else {
            return bytes.reduce(0) { T($0) << 8 + T($1) }
        }
    }

    // Extracts and removes a certain number of bytes from the beginning of the Data object.
    //
    // - Parameter count: The number of bytes to extract and remove.
    // - Returns: A Data object containing the extracted bytes, or empty if there aren't enough bytes.
    mutating func extractBytes(_ count: Int) -> Data {
        guard count > 0, count <= self.count else {
            return Data()
        }

        // Extract the range from the beginning
        let extractedData = subdata(in: 0 ..< count)

        // Remove the extracted bytes from the original data
        removeSubrange(0 ..< count)

        return extractedData
    }

    /* Useful for debugging purposes
     func hexEncodedString() -> String {
         map { String(format: "%02hhx", $0) }.joined()
     }
     */
}
