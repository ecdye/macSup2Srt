//
// macSubtitleOCRError.swift
// macSubtitleOCR
//
// Created by Ethan Dye on 9/16/24.
// Copyright © 2024 Ethan Dye. All rights reserved.
//

enum macSubtitleOCRError: Error {
    case fileReadError
    case fileCreationError
    case fileWriteError
    case invalidODSDataLength(length: Int)
    case invalidPDSDataLength(length: Int)
}
