//
// EBML.swift
// macSubtitleOCR
//
// Created by Ethan Dye on 9/16/24.
// Copyright © 2024 Ethan Dye. All rights reserved.
//

import Foundation

enum EBML {
    static let block: UInt32 = 0xA1
    static let blockGroup: UInt32 = 0xA0
    static let chapters: UInt32 = 0x1043_A770
    static let cluster: UInt32 = 0x1F43_B675
    static let codecID: UInt32 = 0x86
    static let segmentID: UInt32 = 0x1853_8067
    static let simpleBlock: UInt32 = 0xA3
    static let timestamp: UInt32 = 0xE7
    static let timestampScale: UInt32 = 0x2AD7B1
    static let tracksID: UInt32 = 0x1654_AE6B
    static let trackEntryID: UInt32 = 0xAE
    static let trackTypeID: UInt32 = 0x83
    static let trackNumberID: UInt32 = 0xD7
}
