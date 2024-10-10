//
// SRT.swift
// macSubtitleOCR
//
// Created by Ethan Dye on 9/19/24.
// Copyright © 2024 Ethan Dye. All rights reserved.
//

import Foundation

struct SRT {
    // MARK: - Properties

    private var subtitles: [Subtitle] = []

    // MARK: - Getters / Setters

    init(subtitles: [Subtitle]) {
        self.subtitles = subtitles
    }

    // MARK: - Functions

    // Writes the SRT object to the file at the given URL
    func write(toFileAt url: URL) {
        let srtContent = encodeSRT()
        do {
            try srtContent.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            fatalError("Error: Failed to write SRT content to file: \(error)")
        }
    }

    // MARK: - Methods

    // Encodes the SRT object into SRT format and returns it as a string
    private func encodeSRT() -> String {
        var srtContent = ""

        for subtitle in subtitles {
            let startTime = formatTime(subtitle.startTimestamp!)
            let endTime = formatTime(subtitle.endTimestamp!)

            srtContent += "\(subtitle.index!)\n"
            srtContent += "\(startTime) --> \(endTime)\n"
            srtContent += "\(subtitle.text!)\n\n"
        }

        return srtContent
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time - TimeInterval(Int(time))) * 1000)

        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
    }
}
