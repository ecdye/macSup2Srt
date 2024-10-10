//
// MKVSubtitleExtractor.swift
// macSubtitleOCR
//
// Created by Ethan Dye on 9/22/24.
// Copyright © 2024 Ethan Dye. All rights reserved.
//

import Foundation
import os

class MKVSubtitleExtractor: MKVTrackParser {
    func getSubtitleTrackData(trackNumber: Int, outputDirectory: URL) throws -> String? {
        let trackPath = outputDirectory.appendingPathComponent("\(trackNumber)").appendingPathExtension("sup").path

        if FileManager.default.createFile(atPath: trackPath, contents: tracks[trackNumber].trackData, attributes: nil) {
            logger.debug("Created file at path: \(trackPath).")
            return trackPath
        } else {
            fatalError("Error: Failed to create file at path: \(trackPath).")
        }
    }
}
