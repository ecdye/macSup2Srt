//
// VobSub.swift
// macSubtitleOCR
//
// Created by Ethan Dye on 9/30/24.
// Copyright © 2024 Ethan Dye. All rights reserved.
//

import Foundation
import os

struct VobSub {
    // MARK: - Properties

    private var logger = Logger(subsystem: "github.ecdye.macSubtitleOCR", category: "VobSub")
    private(set) var subtitles = [Subtitle]()

    // MARK: - Lifecycle

    init(_ sub: String, _ idx: String) throws {
        let subFile = try FileHandle(forReadingFrom: URL(filePath: sub))
        let idx = VobSubIDX(URL(filePath: idx))
        try extractSubtitleImages(subFile: subFile, idx: idx)
    }

    // MARK: - Methods

    private mutating func extractSubtitleImages(subFile: FileHandle, idx: VobSubIDX) throws {
        for index in idx.offsets.indices {
            let offset = idx.offsets[index]
            let timestamp = idx.timestamps[index]
            let nextOffset: UInt64 = if index + 1 < idx.offsets.count {
                idx.offsets[index + 1]
            } else {
                subFile.seekToEndOfFile()
            }
            var subtitle = Subtitle(startTimestamp: timestamp, endTimestamp: 0, imageData: .init(), numberOfColors: 16)
            try readSubFrame(pic: &subtitle, subFile: subFile, offset: offset, nextOffset: nextOffset, idxPalette: idx.palette)
            logger.debug("Found image at offset \(offset) with timestamp \(timestamp)")
            logger.debug("Image size: \(subtitle.imageWidth!) x \(subtitle.imageHeight!)")
            subtitles.append(subtitle)
        }
    }
}
