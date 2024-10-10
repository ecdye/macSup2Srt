//
// MKVTrack.swift
// macSubtitleOCR
//
// Created by Ethan Dye on 9/16/24.
// Copyright © 2024 Ethan Dye. All rights reserved.
//

import Foundation

struct MKVTrack {
    var trackNumber: Int
    var codecId: String
    var trackData: Data
}
