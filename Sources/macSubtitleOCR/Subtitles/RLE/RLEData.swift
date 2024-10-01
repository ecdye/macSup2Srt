//
// RLEData.swift
// macSubtitleOCR
//
// Created by Ethan Dye on 9/19/24.
// Copyright © 2024 Ethan Dye. All rights reserved.
//

import Foundation

struct RLEData {
    // MARK: - Properties

    private var width: Int
    private var height: Int
    private var data: Data

    // MARK: - Lifecycle

    init(data: Data, width: Int, height: Int) {
        self.width = width
        self.height = height
        self.data = data
    }

    // MARK: - Functions

    func decode() -> Data {
        var pixelCount = 0
        var lineCount = 0
        var iterator = data.makeIterator()

        var image = Data()

        while var color: UInt8 = iterator.next(), lineCount < height {
            var run = 1

            if color == 0x00 {
                let flags = iterator.next()!
                run = Int(flags & 0x3F)
                if flags & 0x40 != 0 {
                    run = (run << 8) + Int(iterator.next()!)
                }
                color = (flags & 0x80) != 0 ? iterator.next()! : 0
            }

            // Ensure run is valid and doesn't exceed pixel buffer
            if run > 0, pixelCount + run <= width * height {
                // Fill the pixel data with the decoded color
                image.append(contentsOf: repeatElement(color, count: run))
                pixelCount += run
            } else if run == 0 {
                // New Line: Check if pixels align correctly
                if pixelCount % width > 0 {
                    fatalError("Error: Decoded \(pixelCount % width) pixels, but line should be \(width) pixels.")
                }
                lineCount += 1
            }
        }

        // Check if we decoded enough pixels
        if pixelCount < width * height {
            fatalError("Error: Insufficient RLE data for subtitle.")
        }

        return image
    }

    func decodeVobSub() throws -> Data {
        var nibbles = Data()
        var odd = false
        var image = Data()

        // Convert RLE data to nibbles
        for byte in data {
            nibbles.append(byte >> 4)
            nibbles.append(byte & 0x0F)
        }
        guard nibbles.count == 2 * data.count
        else {
            fatalError("Error: Failed to create nibbles from RLE data.")
        }

        var i = 0
        var y = 0
        var x = 0
        var onlyHalf = false
        var currentNibbles: [UInt8?] = [nibbles[i], nibbles[i + 1]]
        i += 2
        while currentNibbles[1] != nil, y < height {
            var nibble = getNibble(currentNibbles: &currentNibbles, nibbles: nibbles, i: &i, odd: &odd)

            if nibble < 0x04 {
                if nibble == 0x00 {
                    nibble = nibble << 4 | getNibble(currentNibbles: &currentNibbles, nibbles: nibbles, i: &i, odd: &odd)
                    if nibble < 0x04 {
                        nibble = nibble << 4 | getNibble(currentNibbles: &currentNibbles, nibbles: nibbles, i: &i, odd: &odd)
                    }
                }
                nibble = nibble << 4 | getNibble(currentNibbles: &currentNibbles, nibbles: nibbles, i: &i, odd: &odd)
            }
            let color = UInt8(nibble & 0x03)
            var run = Int(nibble >> 2)

            if onlyHalf, color != 0 {
                print("Got something weird, fixing it \(color) \(run)")
                if run >= 1, run <= 3 {
                    i -= 4
                    currentNibbles = [nibbles[i], nibbles[i + 1]]
                    i += 2
                    continue
                } else if run >= 4, run <= 15 {
                    i -= 5
                    currentNibbles = [nibbles[i], nibbles[i + 1]]
                    i += 2
                    continue
                } // else if 16 <= run, run <= 63 {
                //     i -= 7
                //     currentNibbles = [nibbles[i], nibbles[i + 1]]
                //     i += 2
                //     continue
                // } //else if 64 <= run, run <= 255 {
                //     i -= 8
                //     currentNibbles = [nibbles[i], nibbles[i + 1]]
                //     i += 2
                //     continue
                // }
            }
            if onlyHalf {
                onlyHalf = false
            }

            x += Int(run)

            if run == 0 || x >= width {
                run += width - x
                x = 0
                // Index is byte aligned at start of new line
                // if y % 2 == 0, y > height / 2 {
                //     odd.toggle()
                // }
                y += 1
                onlyHalf = true
                image.append(contentsOf: repeatElement(color, count: run))
                image.append(contentsOf: repeatElement(0, count: width))
                continue
            }

            image.append(contentsOf: repeatElement(color, count: run))
            if image.count == 181585 {
                print("Image count is 181585")
            }
        }
        return image
    }

    func getNibble(currentNibbles: inout [UInt8?], nibbles: Data, i: inout Int, odd: inout Bool) -> UInt16 {
        if odd {
            // _ = currentNibbles.removeFirst()
            _ = currentNibbles.removeFirst()
            odd.toggle()
            // currentNibbles.append(i.next())
            currentNibbles.append(nibbles[i])
            i += 1
        }
        let nibble = UInt16(currentNibbles.removeFirst()!)
        currentNibbles.append(nibbles[i])
        i += 1
        return nibble
    }
}
