# macSubtitleOCR

[![License](https://img.shields.io/github/license/ecdye/macSubtitleOCR)](https://github.com/ecdye/macSubtitleOCR/blob/main/LICENSE.md)
[![CodeQL](https://github.com/ecdye/macSubtitleOCR/actions/workflows/codeql.yml/badge.svg)](https://github.com/ecdye/macSubtitleOCR/actions/workflows/codeql.yml)
[![Build](https://github.com/ecdye/macSubtitleOCR/actions/workflows/build.yml/badge.svg)](https://github.com/ecdye/macSubtitleOCR/actions/workflows/build.yml)
[![Lint](https://github.com/ecdye/macSubtitleOCR/actions/workflows/lint.yml/badge.svg)](https://github.com/ecdye/macSubtitleOCR/actions/workflows/lint.yml)

## Overview

**macSubtitleOCR** is a tool written entirely in Swift that converts bitmap subtitles into the SubRip subtitle format (SRT) using Optical Character Recognition (OCR).
It currently supports both PGS and VobSub bitmap subtitles.
The tool utilizes the built-in macOS OCR engine, offering highly accurate text recognition.

For more details on performance, refer to the [Accuracy](#accuracy) section below.

### Features

- Export `.png` images of subtitles for manual correction of OCR output.
- Use the macOS OCR engine's language recognition feature to enhance accuracy by validating character sequences as real words.
- Export raw JSON output from the OCR engine for further analysis.
- Experimental internal decoder for development (mostly working, VobSub gives occasional errors)

#### Supported Formats

- PGS (`.mkv`, `.sup`)
- VobSub (`.sub`, `.idx`)

### Building the Project

> [!IMPORTANT]
> This project requires Swift 6 to compile and run correctly.
> This project also requires FFmpeg to be installed on your system.

To build macSubtitleOCR, follow these steps:

``` shell
brew install ffmpeg
git clone https://github.com/ecdye/macSubtitleOCR
cd macSubtitleOCR
swift build
```

The compiled build will be available in the `.build/debug` directory.

### Running Tests

The testing process compares OCR output against known correct results.
We aim for at least 95% accuracy, because slight differences may occur between machines.

``` shell
swift test
```

### Accuracy

In tests comparing macSubtitleOCR with the Tesseract OCR engine, the macOS OCR engine often outperforms Tesseract, particularly with challenging cases like the letter 'I'.
While methods like binary image comparison, used by tools such as [SubtitleEdit](https://github.com/SubtitleEdit/subtitleedit), may offer slightly better accuracy in some cases, the macOS OCR engine provides excellent results for most use cases.

## Contribution and TODO

For information on how to contribute to the project, please refer to [CONTRIBUTING.md](CONTRIBUTING.md).

If you're interested in working on specific features or improvements, check out issues tagged as [enhancements](https://github.com/ecdye/macSubtitleOCR/issues?q=is%3Aissue+is%3Aopen+label%3Aenhancement).

## References

- [Presentation Graphic Stream (PGS) Files](https://blog.thescorpius.com/index.php/2017/07/15/presentation-graphic-stream-sup-files-bluray-subtitle-format/)
- [Matroska Technical Specifications](https://www.matroska.org/technical/elements.html)
- [DVD Subtitle Stream (VobSub) Files](http://www.mpucoder.com/DVD/index.html)
