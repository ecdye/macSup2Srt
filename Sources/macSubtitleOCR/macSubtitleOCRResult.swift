//
// macSubtitleOCRResult.swift
// macSubtitleOCR
//
// Created by Ethan Dye on 9/25/24.
// Copyright © 2024-2026 Ethan Dye. All rights reserved.
//

struct macSubtitleOCRResult {
    var trackNumber: Int
    var srt: [Subtitle]
    var json: [SubtitleJSONResult]
}

struct SubtitleJSONResult {
    let index: Int
    let lines: [SubtitleLine]
    let text: String
}

struct SubtitleLine {
    let text: String
    let confidence: Float
    let x: Int
    let width: Int
    let y: Int
    let height: Int

    /// The other readings the recognizer returned for this line, in its own order of preference.
    ///
    /// Recognition confidence is no guide to whether a line is right: a line can be reported at full
    /// confidence and still be wrong. Carrying the alternates lets a later pass correct a line by
    /// choosing among readings the recognizer actually saw rather than inventing one.
    let alternates: [String]
}
