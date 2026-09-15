//
// macSubtitleOCRError.swift
// macSubtitleOCR
//
// Created by Ethan Dye on 9/16/24.
// Copyright © 2024-2026 Ethan Dye. All rights reserved.
//

enum macSubtitleOCRError: Error {
    case fileReadError(_ string: String)
    case fileCreationError
    case fileWriteError
    case ffmpegError(_ string: String)
    case invalidInputFile(_ string: String)
    case invalidRLE(_ string: String)
    case invalidODSDataLength(length: Int)
    case invalidPDSDataLength(length: Int)
    case invalidODSDimensions(_ string: String)
}
