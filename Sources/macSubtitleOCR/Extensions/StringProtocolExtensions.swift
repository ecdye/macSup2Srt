//
// StringProtocolExtensions.swift
// macSubtitleOCR
//
// Created by Ethan Dye on 10/4/24.
// Copyright © 2024 Ethan Dye. All rights reserved.
//

import Foundation

extension StringProtocol {
    var byte: UInt8? { UInt8(self, radix: 16) }
    var hexToBytes: [UInt8] { unfoldSubSequences(limitedTo: 2).compactMap(\.byte) }
}
