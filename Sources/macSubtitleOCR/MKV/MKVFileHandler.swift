//
// MKVFileHandler.swift
// macSubtitleOCR
//
// Created by Ethan Dye on 9/22/24.
// Copyright © 2024 Ethan Dye. All rights reserved.
//

import Foundation
import os

class MKVFileHandler {
    // MARK: - Properties

    var filePath: String
    var fileHandle: FileHandle
    var endOfFile: UInt64
    var timestampScale: TimeInterval = 1000000.0 // Default value if not specified in a given MKV file
    var logger = Logger(subsystem: "github.ecdye.macSubtitleOCR", category: "MKV")

    // MARK: - Lifecycle

    init(filePath: String) {
        self.filePath = filePath
        guard FileManager.default.fileExists(atPath: filePath) else {
            fatalError("Error: File does not exist at path: \(filePath)")
        }
        do {
            try fileHandle = FileHandle(forReadingFrom: URL(fileURLWithPath: filePath))
        } catch {
            fatalError("Error: Failed to open file for file at path: \(filePath), error: \(error.localizedDescription)")
        }
        endOfFile = fileHandle.seekToEndOfFile()
        fileHandle.seek(toFileOffset: 0)
    }

    deinit {
        fileHandle.closeFile()
    }

    // MARK: - Functions

    func locateSegment() -> UInt64? {
        if let (segmentSize, _) = findElement(withID: EBML.segmentID) as? (UInt64, UInt32) {
            return segmentSize
        }
        return nil
    }

    func locateCluster() -> UInt64? {
        if let (clusterSize, _) = findElement(withID: EBML.cluster, avoidCluster: false) as? (UInt64, UInt32) {
            return clusterSize
        }
        return nil
    }

    // Find EBML element by ID, avoiding Cluster header
    func findElement(withID targetID: UInt32, _ tgtID2: UInt32? = nil, avoidCluster: Bool = true) -> (UInt64?, UInt32?) {
        var previousOffset = fileHandle.offsetInFile
        while let (elementID, elementSize) = tryParseElement() {
            // Ensure we stop if we have reached or passed the EOF
            guard fileHandle.offsetInFile < endOfFile else { return (nil, nil) }

            // If, by chance, we find a TimestampScale element, update it from the default
            if elementID == EBML.timestampScale {
                timestampScale = Double(readFixedLengthNumber(fileHandle: fileHandle, length: Int(elementSize)))
                // swiftformat:disable:next redundantSelf
                logger.debug("Found timestamp scale: \(self.timestampScale)")
                continue
            }

            // If a Cluster header is encountered, seek back to the start of the Cluster
            if elementID == EBML.cluster && avoidCluster {
                logger.debug("Encountered Cluster: seeking back to before the cluster header")
                fileHandle.seek(toFileOffset: previousOffset)
                return (nil, nil)
            }

            // If the element matches the target ID (or secondary ID), return its size
            if elementID == targetID || (tgtID2 != nil && elementID == tgtID2!) {
                return (elementSize, elementID)
            } else {
                // Skip over the element's data by seeking to its end
                logger.debug("Found: \(elementID), but not \(targetID), skipping element")
                fileHandle.seek(toFileOffset: fileHandle.offsetInFile + elementSize)
            }
            previousOffset = fileHandle.offsetInFile
        }
        return (nil, nil)
    }

    func tryParseElement() -> (elementID: UInt32, elementSize: UInt64)? {
        let (elementID, elementSize) = readEBMLElement(from: fileHandle)
        return (elementID, elementSize)
    }
}
