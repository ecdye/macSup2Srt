//
// macSubtitleOCRError.swift
// macSubtitleOCR
//
// Created by Ethan Dye on 9/16/24.
// Copyright © 2024 Ethan Dye. All rights reserved.
//

public enum macSubtitleOCRError: Error {
    case invalidFormat
    case fileReadError
    case fileCreationError
    case fileWriteError
    case unsupportedFormat
    case invalidFile
}
