//
// MKVTrackParser.swift
// macSubtitleOCR
//
// Created by Ethan Dye on 9/22/24.
// Copyright © 2024-2026 Ethan Dye. All rights reserved.
//

import Foundation
import os

class MKVTrackParser: MKVFileHandler {
    // MARK: - Properties

    private(set) var tracks: [MKVTrack] = []
    private var codecPrivate = [Int: String]()
    private var languages = [Int: String]()

    // MARK: - Functions

    func parseTracks(for codecs: [String]) throws {
        guard findElement(withID: EBML.segmentID) as? (UInt64, UInt32) != nil else {
            throw macSubtitleOCRError.invalidInputFile("MKV segment element not found in file")
        }

        guard let (tracksSize, _) = findElement(withID: EBML.tracksID) as? (UInt64, UInt32) else {
            throw macSubtitleOCRError.invalidInputFile("MKV tracks element not found in file")
        }

        let endOfTracksOffset = fileHandle.offsetInFile + tracksSize

        var subtitleTracks = [Int: String]()
        while fileHandle.offsetInFile < endOfTracksOffset {
            if let (elementID, elementSize) = tryParseElement() {
                if elementID == EBML.trackEntryID {
                    logger.debug("Found TrackEntry element")
                    if let track = parseTrackEntry(for: codecs) {
                        subtitleTracks[track.0] = track.1
                    }
                } else if elementID == EBML.chapters {
                    break
                } else {
                    fileHandle.seek(toFileOffset: fileHandle.offsetInFile + elementSize)
                }
            }
        }

        let trackData = extractTrackData(for: subtitleTracks)
        trackData?.forEach { trackNumber, data in
            if data.isEmpty {
                print("Found empty track data for track \(trackNumber), skipping track!")
                return
            }
            tracks.append(MKVTrack(
                trackNumber: trackNumber,
                codecID: subtitleTracks[trackNumber]!,
                trackData: data,
                idxData: codecPrivate[trackNumber],
                language: languages[trackNumber]))
        }
    }

    func extractTrackData(for tracks: [Int: String]) -> [Int: Data]? {
        fileHandle.seek(toFileOffset: 0)

        // Step 1: Locate the Segment element
        guard let segmentSize = locateSegment() else { return nil }
        let segmentEndOffset = fileHandle.offsetInFile + segmentSize
        logger.debug("Found Segment, Size: \(segmentSize), End Offset: \(segmentEndOffset)")

        var trackData = [Int: Data]()

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
            parseBlocks(until: clusterEndOffset, for: tracks, with: clusterTimestamp, into: &trackData)
        }

        return trackData
    }

    // MARK: - Methods

    private func parseTrackEntry(for codecs: [String]) -> (Int, String)? {
        var trackNumber: Int?
        var trackType: UInt8?
        var codecID: String?
        var language: String?

        while let (elementID, elementSize) = tryParseElement() {
            switch elementID {
            case EBML.trackNumberID:
                trackNumber = Int((fileHandle.readData(ofLength: Int(elementSize)).first)!)
                logger.debug("Found track number: \(trackNumber!)")
            case EBML.trackTypeID: // Unused by us, left for debugging
                trackType = fileHandle.readData(ofLength: Int(elementSize)).first
                logger.debug("Found track type: \(trackType!)")
            case EBML.codecID:
                var data = fileHandle.readData(ofLength: Int(elementSize))
                data.removeNullBytes()
                codecID = String(data: data, encoding: .ascii)
                logger.debug("Found codec ID: \(codecID!)")
            case EBML.language, EBML.languageBCP47:
                var data = fileHandle.readData(ofLength: Int(elementSize))
                data.removeNullBytes()
                language = String(data: data, encoding: .ascii)
                logger.debug("Found language: \(language!)")
                languages[trackNumber!] = language
            default:
                fileHandle.seek(toFileOffset: fileHandle.offsetInFile + elementSize)
            }
            if trackNumber != nil, trackType != nil, codecID != nil {
                break
            }
        }

        if let trackNumber, let codecID {
            if codecID == "S_VOBSUB" {
                while let (elementID, elementSize) = tryParseElement() {
                    switch elementID {
                    case EBML.codecPrivate:
                        var data = fileHandle.readData(ofLength: Int(elementSize))
                        data.removeNullBytes()
                        codecPrivate[trackNumber] = "# VobSub index file, v7 (do not modify this line!)\n" +
                            (String(data: data, encoding: .ascii) ?? "")
                        if let language {
                            codecPrivate[trackNumber]!.append("langidx: 0\n")
                            codecPrivate[trackNumber]!.append("\nid: \(language), index: 0")
                        }
                    default:
                        fileHandle.seek(toFileOffset: fileHandle.offsetInFile + elementSize)
                    }
                    if codecPrivate[trackNumber] != nil {
                        break
                    }
                }
            }
            if codecs.contains(codecID) {
                return (trackNumber, codecID)
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

    private func parseBlocks(until clusterEndOffset: UInt64, for tracks: [Int: String], with clusterTimestamp: Int64,
                             into trackData: inout [Int: Data]) {
        while fileHandle.offsetInFile < clusterEndOffset {
            // swiftformat:disable:next redundantSelf
            logger.debug("Looking for Block at Offset: \(self.fileHandle.offsetInFile)/\(clusterEndOffset)")

            guard let (blockSize, blockStartOffset) = findBlockTypeAndSize() else { break }

            guard let (blockTrackNumber, blockTimestamp) = readTrackNumber(from: fileHandle) as? (UInt64, Int64)
            else { continue }

            if tracks[Int(blockTrackNumber)] == "S_HDMV/PGS" {
                handlePGSBlock(for: blockTrackNumber,
                               with: blockTimestamp, blockSize, clusterTimestamp, blockStartOffset, &trackData)
            } else if tracks[Int(blockTrackNumber)] == "S_VOBSUB" {
                handleVobSubBlock(for: blockTrackNumber,
                                  with: blockTimestamp, blockSize, clusterTimestamp, blockStartOffset, &trackData)
            } else {
                // Skip this block because it's for a different track
                fileHandle.seek(toFileOffset: blockStartOffset + blockSize)
            }
        }
    }

    private func handlePGSBlock(for blockTrackNumber: UInt64, with blockTimestamp: Int64, _ blockSize: UInt64,
                                _ clusterTimestamp: Int64, _ blockStartOffset: UInt64, _ trackData: inout [Int: Data]) {
        let absPTS = calculateAbsolutePTS(clusterTimestamp, blockTimestamp)
        let pgsPTS = encodePTSForPGS(absPTS)
        let pgsHeader = Data([0x50, 0x47] + pgsPTS + [0x00, 0x00, 0x00, 0x00])

        var blockData = Data()
        blockData.reserveCapacity(Int(blockSize))
        let raw = fileHandle.readData(ofLength: Int(blockSize - (fileHandle.offsetInFile - blockStartOffset)))

        var offset = 0
        while (offset + 3) <= raw.count {
            let segmentSize = min(Int(raw.getUInt16BE(at: offset + 1)! + 3), raw.count - offset)
            logger.debug("Segment size \(segmentSize) at \(offset) type \(raw[offset].hex())")

            blockData.append(pgsHeader)
            blockData.append(raw.subdata(in: offset ..< segmentSize + offset))
            offset += segmentSize
        }

        let trackNumber = Int(blockTrackNumber)
        if trackData[trackNumber] == nil {
            trackData[trackNumber] = Data()
        }
        trackData[trackNumber]?.append(blockData)
    }

    private func handleVobSubBlock(for blockTrackNumber: UInt64, with blockTimestamp: Int64, _ blockSize: UInt64,
                                   _ clusterTimestamp: Int64, _ blockStartOffset: UInt64, _ trackData: inout [Int: Data]) {
        let absolutePTS = calculateAbsolutePTS(clusterTimestamp, blockTimestamp)
        let vobSubPTS = encodePTSForVobSub(from: absolutePTS)

        var segmentSize = Int(blockSize - (fileHandle.offsetInFile - blockStartOffset))
        var buffer = buildVobSubHeader(pts: vobSubPTS, segmentSize: segmentSize)

        buffer.append(fileHandle.readData(ofLength: min(segmentSize, 2019)))
        segmentSize -= min(segmentSize, 2019)

        appendVobSubSegments(segmentSize: segmentSize, buffer: &buffer)

        let trackNumber = Int(blockTrackNumber)
        if trackData[trackNumber] == nil {
            trackData[trackNumber] = Data()
        }
        trackData[trackNumber]!.append(buffer)

        let offset = String(format: "%09X", trackData[trackNumber]!.count - buffer.count)
        codecPrivate[trackNumber]?.append("\ntimestamp: \(formatTime(absolutePTS)), filepos: \(offset)")
    }

    // swiftformat:disable all
    private func buildVobSubHeader(pts: [UInt8], segmentSize: Int) -> Data {
        // PES length includes the flags, header length, PTS and stream ID after it.
        let pesLength = withUnsafeBytes(of: UInt16(min(segmentSize, 2019) + 9).bigEndian) { Array($0) }
        var vobSubHeader = Data()
        vobSubHeader.reserveCapacity(segmentSize + 512)
        vobSubHeader = Data([0x00, 0x00, 0x01, 0xBA,                  // PS packet start code
                             0x00, 0x00, 0x00, 0x00, 0x00, 0x0,       // Null system clock reference
                             0x00, 0x00, 0x00,                        // Null multiplexer rate
                             0x00,                                    // Stuffing length
                             0x00, 0x00, 0x01, 0xBD])                 // PES packet start code
        vobSubHeader.append(contentsOf: pesLength)                    // PES packet length
        vobSubHeader.append(contentsOf: [0x00,                        // PES miscellaneous data
                                         0x80,                        // PTS DTS flag
                                         UInt8(pts.count)])           // PTS data length
        vobSubHeader.append(contentsOf: pts)                          // PTS data
        vobSubHeader.append(contentsOf: [0x00])                       // Null stream ID
        return vobSubHeader
    }

    private func appendVobSubSegments(segmentSize: Int, buffer: inout Data) {
        var remainingSize = segmentSize
        while remainingSize > 0 {
            // Continuation packets have three header bytes and a stream ID.
            let nextSegmentSize = min(remainingSize, 2024) + 4
            let pesLength = withUnsafeBytes(of: UInt16(nextSegmentSize).bigEndian) { Array($0) }
            buffer.append(contentsOf: [0x00, 0x00, 0x01, 0xBA,              // PS packet start code
                                       0x00, 0x00, 0x00, 0x00, 0x00, 0x0,   // Null system clock reference
                                       0x00, 0x00, 0x00,                    // Null multiplexer rate
                                       0x00,                                // Stuffing length
                                       0x00, 0x00, 0x01, 0xBD])             // PES packet start code
            buffer.append(contentsOf: pesLength)                            // PES packet length
            buffer.append(contentsOf: [0x00,                                // PES miscellaneous data
                                       0x00,                                // PTS DTS flag
                                       0x00])                               // PTS data length
            buffer.append(contentsOf: [0x00])                               // Null stream ID
            buffer.append(fileHandle.readData(ofLength: min(remainingSize, 2024)))
            remainingSize -= min(remainingSize, 2024)
        }
    }
    // swiftformat:enable all

    private func findBlockTypeAndSize() -> (blockSize: UInt64, blockStartOffset: UInt64)? {
        guard case (var blockSize?, let blockType?) = findElement(withID: EBML.simpleBlock, EBML.blockGroup) else {
            return nil
        }

        var blockStartOffset = fileHandle.offsetInFile
        if blockType == EBML.blockGroup {
            guard let (newSize, _) = findElement(withID: EBML.block) as? (UInt64, UInt32) else { return nil }
            blockSize = newSize
            blockStartOffset = fileHandle.offsetInFile
        }
        return (blockSize, blockStartOffset)
    }

    /// Function to read the track number, timestamp, and lacing type (if any) from a Block or SimpleBlock header
    private func readTrackNumber(from fileHandle: FileHandle) -> (UInt64?, Int64) {
        let trackNumber = ebmlParser.readVINT(elementSize: true)
        let timestamp = readFixedLengthNumber(fileHandle: fileHandle, length: 2)
        let suffix = fileHandle.readData(ofLength: 1).first ?? 0

        let lacingFlag = (suffix >> 1) & 0x03 // Bits 1 and 2 are the lacing type (unused by us, kept for debugging)
        logger.debug("Track number: \(trackNumber), Timestamp: \(timestamp), Lacing type: \(lacingFlag)")
        return (trackNumber, timestamp)
    }
}
