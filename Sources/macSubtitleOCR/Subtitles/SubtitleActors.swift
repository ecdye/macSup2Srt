//
// SubtitleActors.swift
// macSubtitleOCR
//
// Created by Ethan Dye on 10/25/24.
// Copyright © 2024-2026 Ethan Dye. All rights reserved.
//

actor SubtitleAccumulator {
    var subtitles = [Subtitle]()
    var json = [SubtitleJSONResult]()

    func append(_ subtitle: Subtitle, _ json: SubtitleJSONResult) {
        subtitles.append(subtitle)
        self.json.append(json)
    }
}
