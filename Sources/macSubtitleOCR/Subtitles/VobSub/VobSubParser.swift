//
// VobSubParser.swift
// macSubtitleOCR
//
// Created by Ethan Dye on 10/4/24.
// Copyright © 2024-2026 Ethan Dye. All rights reserved.
//

import Foundation
import os

struct VobSubParser {
    // MARK: - Properties

    let subtitle: Subtitle
    private let masterPalette: [UInt8]
    private let minimumControlHeaderSize = 22

    // MARK: - Lifecycle

    init(index: Int, buffer: UnsafeRawBufferPointer, timestamp: TimeInterval, offset: UInt64,
         nextOffset: UInt64, idxPalette: [UInt8]) throws {
        subtitle = Subtitle(index: index, startTimestamp: timestamp, imageData: .init(), numberOfColors: 16)
        masterPalette = idxPalette
        try readSubFrame(buffer: buffer, offset: offset, nextOffset: nextOffset)
        try decodeImage()
        try decodePalette()
    }

    // MARK: - Methods

    func readSubFrame(buffer: UnsafeRawBufferPointer, offset: UInt64, nextOffset: UInt64) throws {
        var firstPacketFound = false
        var controlOffset: Int?
        var controlSize: Int?
        var controlHeaderCopied = 0
        var controlHeader = Data()
        var relativeControlOffset = 0
        var rleLengthFound = 0

        var offset = Int(offset)
        repeat {
            let startOffset = offset
            guard buffer.loadUnaligned(fromByteOffset: offset, as: UInt32.self).bigEndian == MPEG2PacketType.psPacket else {
                print("No VobSub PS packet at offset \(offset), trying to decode anyway")
                break
            }
            offset += 4

            offset += 6 // System clock reference
            offset += 3 // Multiplexer rate
            let stuffingLength = buffer.loadUnaligned(fromByteOffset: offset, as: UInt8.self) & 7
            offset += 1 + Int(stuffingLength)

            guard buffer.loadUnaligned(fromByteOffset: offset, as: UInt32.self).bigEndian == MPEG2PacketType.pesPacket
            else {
                print("No VobSub PES packet at offset \(offset), trying to decode anyway")
                break
            }
            offset += 4

            let pesLength = Int(buffer.loadUnaligned(fromByteOffset: offset, as: UInt16.self).bigEndian)
            if pesLength == 0 {
                throw macSubtitleOCRError.invalidInputFile("VobSub PES packet length is 0 at offset: \(offset)")
            }
            offset += 2
            let nextPSOffset = offset + pesLength

            offset += 1 // Skip PES miscellaneous data
            let extByteOne = buffer.loadUnaligned(fromByteOffset: offset, as: UInt8.self)
            offset += 1
            let firstPacket = (extByteOne & 0x80) == 0x80 || (extByteOne & 0xC0) == 0xC0

            let ptsDataLength = Int(buffer.loadUnaligned(fromByteOffset: offset, as: UInt8.self))
            offset += 1
            if ptsDataLength == 5 {
                var presentationTimestamp: UInt64 = 0
                presentationTimestamp = UInt64(buffer[offset + 4]) >> 1
                presentationTimestamp += UInt64(buffer[offset + 3]) << 7
                presentationTimestamp += UInt64(buffer[offset + 2] & 0xFE) << 14
                presentationTimestamp += UInt64(buffer[offset + 1]) << 22
                presentationTimestamp += UInt64(buffer[offset] & 0x0E) << 29
                subtitle.startTimestamp = TimeInterval(presentationTimestamp) / 90000
            }
            offset += ptsDataLength

            offset += 1 // Stream ID

            var trueHeaderSize = offset - startOffset
            if firstPacket, ptsDataLength >= 5 {
                let size = Int(buffer.loadUnaligned(fromByteOffset: offset, as: UInt16.self).bigEndian)
                offset += 2
                relativeControlOffset = Int(buffer.loadUnaligned(fromByteOffset: offset, as: UInt16.self).bigEndian)
                offset += 2
                let rleSize = relativeControlOffset - 4
                controlSize = size - rleSize - 4 // 4 bytes for the size and control offset
                controlOffset = offset + rleSize
                trueHeaderSize = offset - startOffset
                firstPacketFound = true
            } else if firstPacketFound {
                controlOffset! += trueHeaderSize
            }

            let difference = max(0, nextPSOffset - controlOffset! - controlHeaderCopied)
            let rleFragmentSize = nextPSOffset - offset - difference
            subtitle.imageData!.append(contentsOf: buffer[offset ..< offset + rleFragmentSize])
            rleLengthFound += rleFragmentSize
            offset += rleFragmentSize

            let bytesToCopy = difference <= 0 ? 0 : min(difference, controlSize! - controlHeaderCopied)
            controlHeader.append(contentsOf: buffer[offset ..< offset + bytesToCopy])
            controlHeaderCopied += bytesToCopy

            offset = nextPSOffset
        } while offset < nextOffset && controlHeaderCopied < controlSize!

        if controlHeaderCopied < controlSize! {
            print("Failed to read control header completely, \(controlHeaderCopied)/\(controlSize!), errors may occur")
            for _ in controlHeaderCopied ..< controlSize! {
                controlHeader.append(0xFF)
            }
        }

        parseCommandHeader(controlHeader, offset: relativeControlOffset)
    }

    private func parseCommandHeader(_ header: Data, offset: Int) {
        let date = TimeInterval((header.getUInt16BE()! << 10) / 90)
        let endOfControl = max(minimumControlHeaderSize, Int(header.getUInt16BE(at: 2)!) - 4 - offset)
        if endOfControl > header.count {
            print("Control header is too short for subtitle: \(subtitle.index), got \(header.count) bytes, errors may occur")
        }

        var index = 4

        while index < endOfControl {
            let command = header[index]
            index += 1

            switch command {
            case 1:
                subtitle.startTimestamp! += date
            case 2:
                subtitle.endTimestamp = subtitle.startTimestamp! + date
            case 3:
                var byte = header[index]
                index += 1
                if subtitle.imagePalette == nil {
                    subtitle.imagePalette = [UInt8](repeating: 0, count: 4)
                }
                subtitle.imagePalette![3] = byte >> 4
                subtitle.imagePalette![2] = byte & 0x0F
                byte = header[index]
                index += 1
                subtitle.imagePalette![1] = byte >> 4
                subtitle.imagePalette![0] = byte & 0x0F
            case 4:
                var byte = header[index]
                index += 1
                if subtitle.imageAlpha == nil {
                    subtitle.imageAlpha = [UInt8](repeating: 0, count: 4)
                } else {
                    // If the alpha is already set, don't overwrite it. This typically happens when fade in/out is used.
                    index += 1
                    break
                }
                subtitle.imageAlpha![3] = byte >> 4
                subtitle.imageAlpha![2] = byte & 0x0F
                byte = header[index]
                index += 1
                subtitle.imageAlpha![1] = byte >> 4
                subtitle.imageAlpha![0] = byte & 0x0F
            case 5:
                if subtitle.imageXOffset != nil || subtitle.imageYOffset != nil {
                    break // Don't overwrite the offsets if they're already set, only happens in bad files
                }
                subtitle.imageXOffset = Int(header[index]) << 4 | Int(header[index + 1] >> 4)
                subtitle.imageWidth = (Int(header[index + 1] & 0x0F) << 8 | Int(header[index + 2])) - subtitle
                    .imageXOffset! + 1
                index += 3
                subtitle.imageYOffset = Int(header[index]) << 4 | Int(header[index + 1] >> 4)
                subtitle.imageHeight = (Int(header[index + 1] & 0x0F) << 8 | Int(header[index + 2])) - subtitle
                    .imageYOffset! + 1
                index += 3
            case 6:
                subtitle.evenOffset = Int(header.getUInt16BE(at: index)! - 4)
                subtitle.oddOffset = Int(header.getUInt16BE(at: index + 2)! - 4)
                index += 4
            default:
                break
            }
        }
    }

    private func decodePalette() throws {
        guard subtitle.imagePalette != nil, subtitle.imageAlpha != nil else {
            throw macSubtitleOCRError.fileReadError("Failed to read image palette and alpha")
        }

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

    private func decodeImage() throws {
        let rleData = RLEData(
            data: subtitle.imageData ?? Data(),
            width: subtitle.imageWidth ?? 0,
            height: subtitle.imageHeight ?? 0,
            evenOffset: subtitle.evenOffset ?? 0,
            oddOffset: subtitle.oddOffset ?? 0)
        subtitle.imageData = try rleData.decodeVobSub()
    }
}
