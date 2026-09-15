# macSubtitleOCR

[![License](https://img.shields.io/github/license/ecdye/macSubtitleOCR)](https://github.com/ecdye/macSubtitleOCR/blob/main/LICENSE.md)
[![CodeQL](https://github.com/ecdye/macSubtitleOCR/actions/workflows/codeql.yml/badge.svg)](https://github.com/ecdye/macSubtitleOCR/actions/workflows/codeql.yml)
[![Test](https://github.com/ecdye/macSubtitleOCR/actions/workflows/test.yml/badge.svg)](https://github.com/ecdye/macSubtitleOCR/actions/workflows/test.yml)
[![Lint](https://github.com/ecdye/macSubtitleOCR/actions/workflows/lint.yml/badge.svg)](https://github.com/ecdye/macSubtitleOCR/actions/workflows/lint.yml)

## Overview

**macSubtitleOCR** converts bitmap subtitles into the SubRip subtitle format (SRT) using the macOS Vision framework to perform OCR.
Currently PGS and VobSub subtitles are supported.

For more details on OCR accuracy, refer to the [Accuracy](#accuracy) section below.

[Release](https://github.com/ecdye/macSubtitleOCR/releases/latest) and [Nightly](https://github.com/ecdye/macSubtitleOCR/releases/tag/nightly) builds are provided for `arm64`.
Unfortunately, GitHub Actions doesn't provide a runner I can build `x86_64` binaries on, sorry.
However, you should be able to compile for `x86_64` on you own machine by following the directions in the [Building the Project](#building-the-project) section below.

### Features

- Export raw JSON output from Vision for further analysis
- Save `.png` images of subtitles for manual correction of OCR output
- Optional support for FFmpeg in case of any issues with internal decoder

### Supported Formats

- PGS (`.mkv`, `.sup`)
- VobSub (`.mkv`, `.sub`, `.idx`)

## Building the Project

> [!IMPORTANT]
> macSubtitleOCR requires Swift 6 support to compile

To make and install the project, follow the directions below:

### Build Internal Decoder Only

To build macSubtitleOCR, follow these steps:

``` shell
git clone https://github.com/ecdye/macSubtitleOCR
cd macSubtitleOCR
swift build --configuration release
```

### Build With FFmpeg Decoder

To build with FFmpeg support, follow these steps:

``` shell
brew install ffmpeg
git clone https://github.com/ecdye/macSubtitleOCR
cd macSubtitleOCR
USE_FFMPEG=1 swift build --configuration release
```

## Running Tests

The testing process compares OCR output against known correct results.
Tests aim for at least 95% accuracy, as there are slight differences in Vision results between machines.

``` shell
swift test
```

## Accuracy

In general, Vision produces a highly accurate output for almost all subtitles.
If you find an edge case with degraded performance, open an issue so it can be investigated.

DVD (VobSub) subtitle bitmaps store alternating rows in two separate fields, independently of whether the video is interlaced.
The internal decoder reads each field from its recorded offset and interleaves the rows, including the extra first-field row in odd-height bitmaps.
This avoids horizontal striping from misaligned fields; no video deinterlacing is needed for subtitle extraction.
VobSub packets extracted directly from MKV also include their header bytes in the packet lengths, so short packets retain all their pixel and control data.

In tests comparing Vision's output with [Tesseract](https://github.com/tesseract-ocr/tesseract), Vision consistently gave better results, particularly with tricky cases like properly recognizing `I`.

While some tools, like [SubtitleEdit](https://github.com/SubtitleEdit/subtitleedit), may use binary image compare for marginally better accuracy, Vision offers more flexibility with built-in language support.

> [!NOTE]
> A `--save-images` PNG holds the same pixels the run recognized, but it does not always recognize the same.
> The file records the image as having straight alpha where the run described it as premultiplied, and Vision answers differently for the two even though they resolve to identical pixels.
> A saved image is therefore reliable for seeing what was extracted, and not for deciding what Vision should have read from it.

## Contribution and TODO

For information on how to contribute to the project, please refer to [CONTRIBUTING.md](CONTRIBUTING.md).

If you're interested in working on specific features or improvements, check out issues tagged as [enhancements](https://github.com/ecdye/macSubtitleOCR/issues?q=is%3Aissue+is%3Aopen+label%3Aenhancement).

## References

- [Presentation Graphic Stream (PGS) Files](https://blog.thescorpius.com/index.php/2017/07/15/presentation-graphic-stream-sup-files-bluray-subtitle-format/)
- [DVD Subtitle Stream (VobSub) Files](http://www.mpucoder.com/DVD/index.html)
- [Matroska Technical Specifications](https://www.matroska.org/technical/elements.html)
