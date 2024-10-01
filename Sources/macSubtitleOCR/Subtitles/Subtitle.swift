//
// Subtitle.swift
// macSubtitleOCR
//
// Created by Ethan Dye on 9/19/24.
// Copyright © 2024 Ethan Dye. All rights reserved.
//

import CoreGraphics
import Foundation

class Subtitle {
    var timestamp: TimeInterval = 0
    var imageWidth: Int = 0
    var imageHeight: Int = 0
    var imageData: Data = .init()
    var imagePalette: [UInt8] = []
    var endTimestamp: TimeInterval = 0

    // MARK: - Functions

    // Converts the RGBA data to a CGImage
    func createImage() -> CGImage? {
        // Convert the image data to RGBA format using the palette
        let rgbaData = imageDataToRGBA()

        let bitmapInfo = CGBitmapInfo.byteOrder32Big
            .union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue))
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let provider = CGDataProvider(data: rgbaData as CFData) else {
            return nil
        }

        let image = CGImage(width: imageWidth,
                            height: imageHeight,
                            bitsPerComponent: 8,
                            bitsPerPixel: 32,
                            bytesPerRow: imageWidth * 4, // 4 bytes per pixel (RGBA)
                            space: colorSpace,
                            bitmapInfo: bitmapInfo,
                            provider: provider,
                            decode: nil,
                            shouldInterpolate: false,
                            intent: .defaultIntent)

        return cropImageToVisibleArea(image!)
    }

    // MARK: - Methods

    // Converts the image data to RGBA format using the palette
    private func imageDataToRGBA() -> Data {
        let bytesPerPixel = 4
        let numColors = 256 // There are only 256 possible palette entries in a PGS Subtitle
        var rgbaData = Data(capacity: imageWidth * imageHeight * bytesPerPixel)

        for y in 0 ..< imageHeight {
            for x in 0 ..< imageWidth {
                let index = Int(y) * imageWidth + Int(x)
                let colorIndex = Int(imageData[index])

                guard colorIndex < numColors else {
                    continue
                }

                let paletteOffset = colorIndex * 4
                rgbaData.append(contentsOf: [
                    imagePalette[paletteOffset],
                    imagePalette[paletteOffset + 1],
                    imagePalette[paletteOffset + 2],
                    imagePalette[paletteOffset + 3],
                ])
            }
        }

        return rgbaData
    }

    private func cropImageToVisibleArea(_ image: CGImage) -> CGImage? {
        guard let dataProvider = image.dataProvider,
              let data = dataProvider.data
        else {
            return nil
        }

        let width = image.width
        let height = image.height
        let buffer = 1 // Buffer around the non-transparent pixels
        let bytesPerPixel = image.bitsPerPixel / 8
        let bytesPerRow = image.bytesPerRow

        let pixelData = CFDataGetBytePtr(data)

        var minX = width
        var maxX = 0
        var minY = height
        var maxY = 0

        // Iterate over each pixel to find the non-transparent bounding box
        for y in 0 ..< height {
            for x in 0 ..< width {
                let pixelIndex = y * bytesPerRow + x * bytesPerPixel
                let alpha = pixelData![pixelIndex + 3] // Assuming RGBA format

                if alpha > 0 { // Non-transparent pixel
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }

        // Check if the image is fully transparent, return nil if so
        if minX == width || maxX == 0 || minY == height || maxY == 0 {
            return nil // Fully transparent image
        }

        // Add buffer to the bounding box, ensuring it's clamped within the image bounds
        minX = max(0, minX - buffer)
        maxX = min(width - 1, maxX + buffer)
        minY = max(0, minY - buffer)
        maxY = min(height - 1, maxY + buffer)

        let croppedWidth = maxX - minX + 1
        let croppedHeight = maxY - minY + 1

        let croppedRect = CGRect(x: minX, y: minY, width: croppedWidth, height: croppedHeight)

        // Create a cropped image from the original image
        return image.cropping(to: croppedRect)
    }
}
