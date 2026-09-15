//
// Subtitle.swift
// macSubtitleOCR
//
// Created by Ethan Dye on 9/19/24.
// Copyright © 2024-2026 Ethan Dye. All rights reserved.
//

import CoreGraphics
import Foundation

/// Subtitle instances are no longer shared across OCR tasks; they are only moved
/// between isolated contexts when collecting final results.
final class Subtitle: @unchecked Sendable {
    var index: Int
    var text: String?
    var startTimestamp: TimeInterval?
    var imageXOffset: Int?
    var imageYOffset: Int?
    var imageWidth: Int?
    var imageHeight: Int?
    var imageData: Data?
    var imagePalette: [UInt8]?
    var imageAlpha: [UInt8]?
    var numberOfColors: Int?
    var endTimestamp: TimeInterval?
    var evenOffset: Int?
    var oddOffset: Int?

    init(index: Int, text: String? = nil, startTimestamp: TimeInterval? = nil, endTimestamp: TimeInterval? = nil,
         imageXOffset: Int? = nil, imageYOffset: Int? = nil, imageWidth: Int? = nil, imageHeight: Int? = nil,
         imageData: Data? = nil, imagePalette: [UInt8]? = nil, imageAlpha: [UInt8]? = nil, numberOfColors: Int? = nil,
         evenOffset: Int? = nil, oddOffset: Int? = nil) {
        self.index = index
        self.text = text
        self.startTimestamp = startTimestamp
        self.endTimestamp = endTimestamp
        self.imageXOffset = imageXOffset
        self.imageYOffset = imageYOffset
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.imageData = imageData
        self.imagePalette = imagePalette
        self.imageAlpha = imageAlpha
        self.numberOfColors = numberOfColors
        self.evenOffset = evenOffset
        self.oddOffset = oddOffset
    }

    // MARK: - Functions

    func makeImageSource() -> SubtitleImageSource? {
        guard
            let imageWidth,
            let imageData,
            let imagePalette,
            let numberOfColors,
            imageWidth > 0
        else {
            return nil
        }

        let availableHeight = imageData.count / imageWidth
        let resolvedHeight = min(imageHeight ?? availableHeight, availableHeight)
        guard resolvedHeight > 0 else {
            return nil
        }

        return SubtitleImageSource(width: imageWidth,
                                   height: resolvedHeight,
                                   imageData: imageData,
                                   imagePalette: imagePalette,
                                   numberOfColors: numberOfColors)
    }
}

struct SubtitleImageSource {
    let width: Int
    let height: Int
    let imageData: Data
    let imagePalette: [UInt8]
    let numberOfColors: Int

    // MARK: - Methods

    /// Converts the image data to RGBA format using the palette
    private func imageDataToRGBA() -> Data {
        let bytesPerPixel = 4
        let pixelCount = width * height
        var rgbaData = Data(capacity: pixelCount * bytesPerPixel)

        for index in 0 ..< pixelCount {
            let colorIndex = Int(imageData[index])
            let paletteOffset = colorIndex * bytesPerPixel
            guard
                colorIndex >= 0,
                colorIndex < numberOfColors,
                paletteOffset + 3 < imagePalette.count
            else {
                rgbaData.append(contentsOf: [255, 255, 255, 255])
                continue
            }

            rgbaData.append(contentsOf: [
                imagePalette[paletteOffset],
                imagePalette[paletteOffset + 1],
                imagePalette[paletteOffset + 2],
                imagePalette[paletteOffset + 3]
            ])
        }

        return rgbaData
    }

    /// Converts the RGBA data to a CGImage
    func createImage(_ invert: Bool) -> CGImage? {
        var rgbaData = imageDataToRGBA()
        guard rgbaData.count == width * height * 4 else {
            return nil
        }

        var minX = width
        var maxX = -1
        var minY = height
        var maxY = -1

        for y in 0 ..< height {
            for x in 0 ..< width {
                let pixelIndex = (y * width + x) * 4
                let alpha = rgbaData[pixelIndex + 3]
                if alpha > 0 {
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                    minY = min(minY, y)
                    maxY = max(maxY, y)
                    // Invert rather than flatten to a single color: subtitle glyphs are anti-aliased
                    // and usually carry an outline, and forcing every visible pixel to one value fattens
                    // the strokes until counters close up and OCR misreads them.
                    if !invert {
                        rgbaData[pixelIndex] = 255 - rgbaData[pixelIndex]
                        rgbaData[pixelIndex + 1] = 255 - rgbaData[pixelIndex + 1]
                        rgbaData[pixelIndex + 2] = 255 - rgbaData[pixelIndex + 2]
                    }
                } else {
                    // Transparent pixels become opaque white so the glyphs sit on a plain background.
                    rgbaData[pixelIndex] = 255
                    rgbaData[pixelIndex + 1] = 255
                    rgbaData[pixelIndex + 2] = 255
                    rgbaData[pixelIndex + 3] = 255
                }
            }
        }

        guard minX < width, maxX >= 0, minY < height, maxY >= 0 else {
            return nil
        }

        guard let provider = CGDataProvider(data: rgbaData as CFData) else { return nil }
        // Subtitle palettes carry straight alpha, so `premultipliedLast` is not what the buffer holds.
        // It composites to the same pixels regardless: wherever alpha is partial these palettes pin the
        // color to black or white, and both readings agree at either end. Recognition does not agree,
        // though. Vision reads the two differently despite the identical pixels, and declaring the
        // straight alpha it really is reads measurably worse, so the buffer is described this way on
        // purpose.
        let bitmapInfo = CGBitmapInfo.byteOrder32Big
            .union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent)

        let croppedRect = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        return image?.cropping(to: croppedRect)
    }
}
