//
// MKVTrackParser.swift
// macSubtitleOCR
//
// Created by Ethan Dye on 9/22/24.
// Copyright © 2024 Ethan Dye. All rights reserved.
//

import Foundation
import os

class MKVTrackParser: MKVFileHandler {
    // MARK: - Properties

    var tracks: [MKVTrack] = []

    // MARK: - Functions

    func parseTracks(codec: String) throws {
        guard findElement(withID: EBML.segmentID) as? (UInt64, UInt32) != nil else {
            fatalError("Error: Segment element not found in file: \(filePath)")
        }

        guard let (tracksSize, _) = findElement(withID: EBML.tracksID) as? (UInt64, UInt32) else {
            fatalError("Error: Tracks element not found in file: \(filePath)")
        }

        let endOfTracksOffset = fileHandle.offsetInFile + tracksSize

        var trackNumbers = [Int]()
        while fileHandle.offsetInFile < endOfTracksOffset {
            if let (elementID, elementSize) = tryParseElement() {
                if elementID == EBML.trackEntryID {
                    logger.debug("Found TrackEntry element")
                    if let track = parseTrackEntry(codec: codec) {
                        trackNumbers.append(track)
                    }
                } else if elementID == EBML.chapters {
                    break
                } else {
                    fileHandle.seek(toFileOffset: fileHandle.offsetInFile + elementSize)
                }
            }
        }

        let trackData = extractTrackData(trackNumber: trackNumbers)
        trackData?.enumerated().forEach { index, data in
            tracks.append(MKVTrack(trackNumber: index, codecId: codec, trackData: data))
        }
    }

    func extractTrackData(trackNumber: [Int]) -> [Data]? {
        fileHandle.seek(toFileOffset: 0)

        // Step 1: Locate the Segment element
        guard let segmentSize = locateSegment() else { return nil }
        let segmentEndOffset = fileHandle.offsetInFile + segmentSize
        // swiftformat:disable:next redundantSelf
        logger.debug("Found Segment, Size: \(segmentSize), End Offset: \(segmentEndOffset), EOF: \(self.endOfFile)")

        var trackData = [Data](repeating: Data(), count: trackNumber.count)

        // Step 2: Parse Clusters within the Segment
        while fileHandle.offsetInFile < segmentEndOffset {
            guard let clusterSize = locateCluster() else { continue }
            let clusterEndOffset = fileHandle.offsetInFile + clusterSize

            // Step 3: Extract the cluster timestamp
            guard let clusterTimestamp = extractClusterTimestamp() else {
                logger.warning("Failed to extract cluster timestamp, skipping cluster.")
                continue
            }

            // Step 4: Parse Blocks (SimpleBlock or Block) within each Cluster
            parseBlocks(
                within: clusterEndOffset,
                trackNumber: trackNumber,
                clusterTimestamp: clusterTimestamp,
                trackData: &trackData)
        }

        return trackData.isEmpty ? nil : trackData
    }

    // MARK: - Methods

    private func parseTrackEntry(codec: String) -> Int? {
        var trackNumber: Int?
        var trackType: UInt8?
        var codecId: String?

        while let (elementID, elementSize) = tryParseElement() {
            switch elementID {
            case EBML.trackNumberID:
                trackNumber = Int((fileHandle.readData(ofLength: 1).first)!)
                logger.debug("Found track number: \(trackNumber!)")
            case EBML.trackTypeID: // Unused by us, left for debugging
                trackType = fileHandle.readData(ofLength: 1).first
                logger.debug("Found track type: \(trackType!)")
            case EBML.codecID:
                var data = fileHandle.readData(ofLength: Int(elementSize))
                data.removeNullBytes()
                codecId = String(data: data, encoding: .ascii)
                logger.debug("Found codec ID: \(codecId ?? "nil")")
            default:
                fileHandle.seek(toFileOffset: fileHandle.offsetInFile + elementSize)
            }
            if trackNumber != nil, trackType != nil, codecId != nil { break }
        }

        if let trackNumber, let codecId {
            if codecId == codec {
                return trackNumber
            }
        }
        return nil
    }

    private func extractClusterTimestamp() -> Int64? {
        if let (timestampElementSize, _) = findElement(withID: EBML.timestamp) as? (UInt64, UInt32) {
            return readFixedLengthNumber(fileHandle: fileHandle, length: Int(timestampElementSize))
        }
        return nil
    }

    private func parseBlocks(within clusterEndOffset: UInt64, trackNumber: [Int], clusterTimestamp: Int64,
                             trackData: inout [Data]) {
        while fileHandle.offsetInFile < clusterEndOffset {
            // swiftformat:disable:next redundantSelf
            logger.debug("Looking for Block at Offset: \(self.fileHandle.offsetInFile)/\(clusterEndOffset)")
            guard case (var blockSize?, let blockType?) = findElement(withID: EBML.simpleBlock, EBML.blockGroup)
            else { break }

            var blockStartOffset = fileHandle.offsetInFile

            if blockType == EBML.blockGroup {
                guard let (ns, _) = findElement(withID: EBML.block) as? (UInt64, UInt32) else { return }
                blockSize = ns
                blockStartOffset = fileHandle.offsetInFile
            }

            // Step 5: Read the track number in the block and compare it
            guard let (blockTrackNumber, blockTimestamp) = readTrackNumber(from: fileHandle) as? (UInt64, Int64)
            else { continue }
            if trackNumber.contains(Int(blockTrackNumber)) {
                // Step 6: Calculate and encode the timestamp as 4 bytes in big-endian (PGS format)
                let absPTS = calcAbsPTSForPGS(clusterTimestamp, blockTimestamp, timestampScale)
                let pgsPTS = encodePTSForPGS(absPTS)

                // Step 7: Read the block data and add needed PGS headers and timestamps
                let pgsHeader = Data([0x50, 0x47] + pgsPTS + [0x00, 0x00, 0x00, 0x00])
                var blockData = Data()
                let raw = fileHandle.readData(ofLength: Int(blockSize - (fileHandle.offsetInFile - blockStartOffset)))
                var offset = 0
                while (offset + 3) <= raw.count {
                    let segmentSize = min(Int(raw.value(ofType: UInt16.self, at: offset + 1)! + 3), raw.count - offset)
                    logger.debug("Segment size \(segmentSize) at \(offset) type 0x\(String(format: "%02x", raw[offset]))")

                    blockData.append(pgsHeader)
                    blockData.append(raw.subdata(in: offset ..< segmentSize + offset))
                    offset += segmentSize
                }

                trackData[trackNumber.firstIndex { $0 == Int(blockTrackNumber) }!].append(blockData)
            } else {
                // Skip this block because it's for a different track
                fileHandle.seek(toFileOffset: blockStartOffset + blockSize)
            }
        }
    }

    // Function to read the track number, timestamp, and lacing type (if any) from a Block or SimpleBlock header
    private func readTrackNumber(from fileHandle: FileHandle) -> (UInt64?, Int64) {
        let trackNumber = readVINT(from: fileHandle, unmodified: true)
        let timestamp = readFixedLengthNumber(fileHandle: fileHandle, length: 2)
        let suffix = fileHandle.readData(ofLength: 1).first ?? 0

        let lacingFlag = (suffix >> 1) & 0x03 // Bits 1 and 2 are the lacing type (unused by us, kept for debugging)
        logger.debug("Track number: \(trackNumber), Timestamp: \(timestamp), Lacing type: \(lacingFlag)")
        return (trackNumber, timestamp)
    }
}
