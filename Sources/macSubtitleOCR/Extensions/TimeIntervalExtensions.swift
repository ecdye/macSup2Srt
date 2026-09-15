//
// TimeIntervalExtensions.swift
// macSubtitleOCR
//
// Created by Ethan Dye on 10/24/24.
// Copyright © 2024-2026 Ethan Dye. All rights reserved.
//

import Foundation

extension TimeInterval {
    /// This timestamp written the way SubRip spells one, `HH:MM:SS,mmm`.
    var srtTimestamp: String {
        let hours = Int(self) / 3600
        let minutes = (Int(self) % 3600) / 60
        let seconds = Int(self) % 60
        let milliseconds = Int((self - TimeInterval(Int(self))) * 1000)

        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
    }
}
