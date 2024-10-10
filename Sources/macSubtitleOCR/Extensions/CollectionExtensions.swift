//
// CollectionExtensions.swift
// macSubtitleOCR
//
// Created by Ethan Dye on 10/4/24.
// Copyright © 2024 Ethan Dye. All rights reserved.
//

extension Collection {
    func unfoldSubSequences(limitedTo maxLength: Int) -> UnfoldSequence<SubSequence, Index> {
        sequence(state: startIndex) { start in
            guard start < self.endIndex else { return nil }
            let end = self.index(start, offsetBy: maxLength, limitedBy: self.endIndex) ?? self.endIndex
            defer { start = end }
            return self[start ..< end]
        }
    }
}
