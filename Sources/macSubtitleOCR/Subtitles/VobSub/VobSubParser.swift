//
// VobSubParser.swift
// macSubtitleOCR
//
// Created by Ethan Dye on 9/30/24.
// Copyright © 2024 Ethan Dye. All rights reserved.
//

import Foundation
import os

struct VobSubParser {
    // MARK: - Properties

    private let logger = Logger(subsystem: "github.ecdye.macSubtitleOCR", category: "VobSubParser")
    private(set) var subtitle: Subtitle = .init(imageData: .init(), numberOfColors: 16)
    private let masterPalette: [UInt8]

    // MARK: - Lifecycle

    init(subFile: FileHandle, timestamp: TimeInterval, offset: UInt64, nextOffset: UInt64, idxPalette: [UInt8]) {
        masterPalette = idxPalette
        subtitle.startTimestamp = timestamp
        readSubFrame(subFile: subFile, offset: offset, nextOffset: nextOffset, idxPalette: idxPalette)
        decodeImage()
        decodePalette()
    }

    // MARK: - Methods

    func readSubFrame(subFile: FileHandle, offset: UInt64, nextOffset: UInt64, idxPalette _: [UInt8]) {
        var firstPacketFound = false
        var controlOffset: Int?
        var controlSize: Int?
        var controlHeaderCopied = 0
        var controlHeader = Data()
        var relativeControlOffset = 0
        var rleLengthFound = 0

        subFile.seek(toFileOffset: offset)
        repeat {
            let startOffset = subFile.offsetInFile
            guard subFile.readData(ofLength: 4).value(ofType: UInt32.self, at: 0) == MPEG2PacketType.psPacket else {
                fatalError("Error: Failed to find PS packet at offset \(subFile.offsetInFile)")
            }
            logger.debug("Found PS packet at offset \(subFile.offsetInFile)")

            subFile.readData(ofLength: 6) // System clock reference
            subFile.readData(ofLength: 3) // Multiplexer rate
            let stuffingLength = Int(subFile.readData(ofLength: 1)[0] & 7)
            subFile.readData(ofLength: stuffingLength) // Stuffing bytes
            logger.debug("Skipped \(stuffingLength) stuffing bytes")
            let psHeaderLength = subFile.offsetInFile - startOffset
            logger.debug("PS header length: \(psHeaderLength)")

            guard subFile.readData(ofLength: 4).value(ofType: UInt32.self, at: 0) == MPEG2PacketType.pesPacket else {
                fatalError("Error: Failed to find PES packet at offset \(subFile.offsetInFile)")
            }
            logger.debug("Found PES packet at offset \(subFile.offsetInFile)")

            let pesLength = Int(subFile.readData(ofLength: 2).value(ofType: UInt16.self, at: 0) ?? 0)
            if pesLength == 0 {
                fatalError("Error: PES packet length is 0 at offset \(subFile.offsetInFile)")
            }
            let nextPSOffset = subFile.offsetInFile + UInt64(pesLength)
            logger.debug("pesLength: \(pesLength), nextPSOffset: \(nextPSOffset)")

            let extByteOne = subFile.readData(ofLength: 1)[0]
            let firstPacket = (extByteOne >> 2 & 0x01) == 0
            logger.debug("firstPacket: \(firstPacket)")

            subFile.readData(ofLength: 1) // PTS DTS flags
            let ptsDataLength = Int(subFile.readData(ofLength: 1)[0])
            subFile.readData(ofLength: ptsDataLength) // Skip PES Header data bytes
            logger.debug("Skipped \(ptsDataLength) PTS bytes")

            let streamID = Int(subFile.readData(ofLength: 1)[0] - 0x20)
            logger.debug("Stream ID: \(streamID)")

            var trueHeaderSize = Int(subFile.offsetInFile - startOffset)
            if firstPacket, ptsDataLength >= 5 {
                let size = Int(subFile.readData(ofLength: 2).value(ofType: UInt16.self, at: 0) ?? 0)
                relativeControlOffset = Int(subFile.readData(ofLength: 2).value(ofType: UInt16.self, at: 0) ?? 0)
                let rleSize = relativeControlOffset - 2
                controlSize = size - rleSize - 4 // 4 bytes for the size and control offset
                logger.debug("Size: \(size), RLE Size: \(rleSize), Control Size: \(controlSize!)")

                controlOffset = Int(subFile.offsetInFile) + rleSize
                trueHeaderSize = Int(subFile.offsetInFile - startOffset)
                firstPacketFound = true
            } else if firstPacketFound {
                controlOffset! += trueHeaderSize
            }

            let savedOffset = subFile.offsetInFile
            let difference = max(0, Int(nextPSOffset) - controlOffset! - controlHeaderCopied)
            let copied = controlHeaderCopied
            var i = 0
            subFile.seek(toFileOffset: UInt64(controlOffset! + i + copied))
            while i < difference, controlHeaderCopied < controlSize! {
                controlHeader.append(subFile.readData(ofLength: 1)[0])
                controlHeaderCopied += 1
                i += 1
            }
            logger.debug("Obtained \(controlHeaderCopied) of \(controlSize!) bytes of control header")

            let rleFragmentSize = Int(nextPSOffset - savedOffset) - difference
            subFile.seek(toFileOffset: savedOffset)
            subtitle.imageData!.append(subFile.readData(ofLength: rleFragmentSize))
            rleLengthFound += rleFragmentSize
            logger.debug("RLE fragment size: \(rleFragmentSize), Total RLE length: \(rleLengthFound)")

            subFile.seek(toFileOffset: nextPSOffset)
        } while subFile.offsetInFile < nextOffset && controlHeaderCopied < controlSize!

        if controlHeaderCopied < controlSize! {
            logger.warning("Failed to read control header completely")
            for _ in controlHeaderCopied ..< controlSize! {
                controlHeader.append(0xFF)
            }
        }

        var index = 0
        var endOfControl = Int(controlHeader.value(ofType: UInt16.self, at: index)!) - relativeControlOffset - 4
        if endOfControl < 0 || endOfControl > controlSize! {
            logger.warning("Invalid control header size \(endOfControl). Setting to \(controlSize!)")
            endOfControl = Int(controlSize!)
        }
        index += 2

        var alphaSum = 0

        // This is a hacky way to get the end timestamp, but it works somewhat accurately
        let relativeEndTimestamp = controlHeader.value(ofType: UInt16.self, at: endOfControl - 1)! << 10
        subtitle.endTimestamp = subtitle.startTimestamp! + TimeInterval(relativeEndTimestamp) / 90.0 - 9

        while index < endOfControl {
            let command = controlHeader[index]
            index += 1

            switch command {
            case 0:
                break // Set subtitle as forced
            case 1:
                break // Start display
            case 2:
                let displayDelay = controlHeader.value(ofType: UInt16.self, at: 0)
                logger.debug("Display delay is \(displayDelay!)")
            case 3:
                var byte = controlHeader[index]
                index += 1
                if subtitle.imagePalette == nil {
                    subtitle.imagePalette = [UInt8](repeating: 0, count: 4)
                }
                subtitle.imagePalette![3] = byte >> 4
                subtitle.imagePalette![2] = byte & 0x0F
                byte = controlHeader[index]
                index += 1
                subtitle.imagePalette![1] = byte >> 4
                subtitle.imagePalette![0] = byte & 0x0F
            case 4:
                var byte = controlHeader[index]
                index += 1
                if subtitle.imageAlpha == nil {
                    subtitle.imageAlpha = [UInt8](repeating: 0, count: 4)
                }
                subtitle.imageAlpha![3] = byte >> 4
                subtitle.imageAlpha![2] = byte & 0x0F
                byte = controlHeader[index]
                index += 1
                subtitle.imageAlpha![1] = byte >> 4
                subtitle.imageAlpha![0] = byte & 0x0F
                for i in 0 ..< 4 {
                    alphaSum += Int(subtitle.imageAlpha![i])
                }
            case 5:
                subtitle.imageXOffset = Int(controlHeader[index]) << 4 | Int(controlHeader[index + 1] >> 4)
                subtitle.imageWidth = (Int(controlHeader[index + 1] & 0x0F) << 8 | Int(controlHeader[index + 2])) - subtitle
                    .imageXOffset! + 1
                index += 3
                subtitle.imageYOffset = Int(controlHeader[index]) << 4 | Int(controlHeader[index + 1] >> 4)
                subtitle.imageHeight = (Int(controlHeader[index + 1] & 0x0F) << 8 | Int(controlHeader[index + 2])) - subtitle
                    .imageYOffset! + 1
                index += 3
            default:
                break
            }
        }
    }

    private func decodePalette() {
        var palette = [UInt8](repeating: 0, count: 4 * 4)

        for i in 0 ..< 4 {
            let index = subtitle.imagePalette![i]
            palette[4 * i] = masterPalette[3 * Int(index)]
            palette[4 * i + 1] = masterPalette[3 * Int(index) + 1]
            palette[4 * i + 2] = masterPalette[3 * Int(index) + 2]
            palette[4 * i + 3] = UInt8(subtitle.imageAlpha![i] * 0x11)
        }

        subtitle.imagePalette = palette
    }

    private func decodeImage() {
        let rleData = RLEData(data: subtitle.imageData!, width: subtitle.imageWidth!, height: subtitle.imageHeight!)
        subtitle.imageData = rleData.decodeVobSub()
    }
}
