//
// LatinConfusables.swift
// macSubtitleOCR
//
// Copyright © 2026 Ethan Dye. All rights reserved.
//

import Foundation

/// Characters that are drawn the same as a Latin letter or digit but belong to another script.
///
/// Vision recognizes text with a multilingual character inventory whatever `recognitionLanguages`
/// asks for, so a track known to be in a Latin script language still comes back with the occasional
/// Cyrillic or Greek letter in place of the Latin one it is indistinguishable from. Those characters
/// read correctly but break search and comparison, and unlike a misread letter there is nothing on
/// screen to reveal them.
///
/// Derived from the Unicode confusables table (UTS #39, version 17.0.0), keeping the entries whose
/// prototype is a single ASCII letter or digit, and whose source is a letter or digit from a script
/// that a Latin script language is never written in. Mathematical alphanumeric symbols are left out:
/// they map to Latin as well, but no text recognizer produces them for a subtitle.
enum LatinConfusables {
    private static let map: [Character: Character] = [
        "\u{037A}": "i", // Greek Ypogegrammeni
        "\u{037F}": "J", // Greek Capital Letter Yot
        "\u{0391}": "A", // Greek Capital Letter Alpha
        "\u{0392}": "B", // Greek Capital Letter Beta
        "\u{0395}": "E", // Greek Capital Letter Epsilon
        "\u{0396}": "Z", // Greek Capital Letter Zeta
        "\u{0397}": "H", // Greek Capital Letter Eta
        "\u{0399}": "l", // Greek Capital Letter Iota
        "\u{039A}": "K", // Greek Capital Letter Kappa
        "\u{039C}": "M", // Greek Capital Letter Mu
        "\u{039D}": "N", // Greek Capital Letter Nu
        "\u{039F}": "O", // Greek Capital Letter Omicron
        "\u{03A1}": "P", // Greek Capital Letter Rho
        "\u{03A4}": "T", // Greek Capital Letter Tau
        "\u{03A5}": "Y", // Greek Capital Letter Upsilon
        "\u{03A7}": "X", // Greek Capital Letter Chi
        "\u{03B1}": "a", // Greek Small Letter Alpha
        "\u{03B3}": "y", // Greek Small Letter Gamma
        "\u{03B9}": "i", // Greek Small Letter Iota
        "\u{03BD}": "v", // Greek Small Letter Nu
        "\u{03BF}": "o", // Greek Small Letter Omicron
        "\u{03C1}": "p", // Greek Small Letter Rho
        "\u{03C3}": "o", // Greek Small Letter Sigma
        "\u{03C5}": "u", // Greek Small Letter Upsilon
        "\u{03D2}": "Y", // Greek Upsilon With Hook Symbol
        "\u{03DC}": "F", // Greek Letter Digamma
        "\u{03E8}": "2", // Coptic Capital Letter Hori
        "\u{03EC}": "6", // Coptic Capital Letter Shima
        "\u{03ED}": "o", // Coptic Small Letter Shima
        "\u{03F1}": "p", // Greek Rho Symbol
        "\u{03F2}": "c", // Greek Lunate Sigma Symbol
        "\u{03F3}": "j", // Greek Letter Yot
        "\u{03F8}": "p", // Greek Small Letter Sho
        "\u{03F9}": "C", // Greek Capital Lunate Sigma Symbol
        "\u{03FA}": "M", // Greek Capital Letter San
        "\u{0405}": "S", // Cyrillic Capital Letter Dze
        "\u{0406}": "l", // Cyrillic Capital Letter Byelorussian-Ukrainian I
        "\u{0408}": "J", // Cyrillic Capital Letter Je
        "\u{0410}": "A", // Cyrillic Capital Letter A
        "\u{0412}": "B", // Cyrillic Capital Letter Ve
        "\u{0415}": "E", // Cyrillic Capital Letter Ie
        "\u{0417}": "3", // Cyrillic Capital Letter Ze
        "\u{041A}": "K", // Cyrillic Capital Letter Ka
        "\u{041C}": "M", // Cyrillic Capital Letter Em
        "\u{041D}": "H", // Cyrillic Capital Letter En
        "\u{041E}": "O", // Cyrillic Capital Letter O
        "\u{0420}": "P", // Cyrillic Capital Letter Er
        "\u{0421}": "C", // Cyrillic Capital Letter Es
        "\u{0422}": "T", // Cyrillic Capital Letter Te
        "\u{0423}": "Y", // Cyrillic Capital Letter U
        "\u{0425}": "X", // Cyrillic Capital Letter Ha
        "\u{042C}": "b", // Cyrillic Capital Letter Soft Sign
        "\u{0430}": "a", // Cyrillic Small Letter A
        "\u{0431}": "6", // Cyrillic Small Letter Be
        "\u{0433}": "r", // Cyrillic Small Letter Ghe
        "\u{0435}": "e", // Cyrillic Small Letter Ie
        "\u{043E}": "o", // Cyrillic Small Letter O
        "\u{0440}": "p", // Cyrillic Small Letter Er
        "\u{0441}": "c", // Cyrillic Small Letter Es
        "\u{0443}": "y", // Cyrillic Small Letter U
        "\u{0445}": "x", // Cyrillic Small Letter Ha
        "\u{0448}": "w", // Cyrillic Small Letter Sha
        "\u{0455}": "s", // Cyrillic Small Letter Dze
        "\u{0456}": "i", // Cyrillic Small Letter Byelorussian-Ukrainian I
        "\u{0458}": "j", // Cyrillic Small Letter Je
        "\u{0461}": "w", // Cyrillic Small Letter Omega
        "\u{0474}": "V", // Cyrillic Capital Letter Izhitsa
        "\u{0475}": "v", // Cyrillic Small Letter Izhitsa
        "\u{04AE}": "Y", // Cyrillic Capital Letter Straight U
        "\u{04AF}": "y", // Cyrillic Small Letter Straight U
        "\u{04BB}": "h", // Cyrillic Small Letter Shha
        "\u{04BD}": "e", // Cyrillic Small Letter Abkhasian Che
        "\u{04C0}": "l", // Cyrillic Letter Palochka
        "\u{04CF}": "l", // Cyrillic Small Letter Palochka
        "\u{04E0}": "3", // Cyrillic Capital Letter Abkhasian Dze
        "\u{0501}": "d", // Cyrillic Small Letter Komi De
        "\u{050C}": "G", // Cyrillic Capital Letter Komi Sje
        "\u{051B}": "q", // Cyrillic Small Letter Qa
        "\u{051C}": "W", // Cyrillic Capital Letter We
        "\u{051D}": "w", // Cyrillic Small Letter We
        "\u{054D}": "U", // Armenian Capital Letter Seh
        "\u{054F}": "S", // Armenian Capital Letter Tiwn
        "\u{0555}": "O", // Armenian Capital Letter Oh
        "\u{0561}": "w", // Armenian Small Letter Ayb
        "\u{0563}": "q", // Armenian Small Letter Gim
        "\u{0566}": "q", // Armenian Small Letter Za
        "\u{0570}": "h", // Armenian Small Letter Ho
        "\u{0578}": "n", // Armenian Small Letter Vo
        "\u{057C}": "n", // Armenian Small Letter Ra
        "\u{057D}": "u", // Armenian Small Letter Seh
        "\u{0581}": "g", // Armenian Small Letter Co
        "\u{0582}": "i", // Armenian Small Letter Yiwn
        "\u{0584}": "f", // Armenian Small Letter Keh
        "\u{0585}": "o", // Armenian Small Letter Oh
        "\u{13A0}": "D", // Cherokee Letter A
        "\u{13A1}": "R", // Cherokee Letter E
        "\u{13A2}": "T", // Cherokee Letter I
        "\u{13A5}": "i", // Cherokee Letter V
        "\u{13A9}": "Y", // Cherokee Letter Gi
        "\u{13AA}": "A", // Cherokee Letter Go
        "\u{13AB}": "J", // Cherokee Letter Gu
        "\u{13AC}": "E", // Cherokee Letter Gv
        "\u{13B3}": "W", // Cherokee Letter La
        "\u{13B7}": "M", // Cherokee Letter Lu
        "\u{13BB}": "H", // Cherokee Letter Mi
        "\u{13BD}": "Y", // Cherokee Letter Mu
        "\u{13C0}": "G", // Cherokee Letter Nah
        "\u{13C2}": "h", // Cherokee Letter Ni
        "\u{13C3}": "Z", // Cherokee Letter No
        "\u{13CE}": "4", // Cherokee Letter Se
        "\u{13CF}": "b", // Cherokee Letter Si
        "\u{13D2}": "R", // Cherokee Letter Sv
        "\u{13D4}": "W", // Cherokee Letter Ta
        "\u{13D5}": "S", // Cherokee Letter De
        "\u{13D9}": "V", // Cherokee Letter Do
        "\u{13DA}": "S", // Cherokee Letter Du
        "\u{13DE}": "L", // Cherokee Letter Tle
        "\u{13DF}": "C", // Cherokee Letter Tli
        "\u{13E2}": "P", // Cherokee Letter Tlv
        "\u{13E6}": "K", // Cherokee Letter Tso
        "\u{13E7}": "d", // Cherokee Letter Tsu
        "\u{13EE}": "6", // Cherokee Letter Wv
        "\u{13F3}": "G", // Cherokee Letter Yu
        "\u{13F4}": "B", // Cherokee Letter Yv
        "\u{1D26}": "r", // Greek Letter Small Capital Gamma
        "\u{2C82}": "B", // Coptic Capital Letter Vida
        "\u{2C85}": "r", // Coptic Small Letter Gamma
        "\u{2C8E}": "H", // Coptic Capital Letter Hate
        "\u{2C92}": "l", // Coptic Capital Letter Iauda
        "\u{2C93}": "i", // Coptic Small Letter Iauda
        "\u{2C94}": "K", // Coptic Capital Letter Kapa
        "\u{2C98}": "M", // Coptic Capital Letter Mi
        "\u{2C9A}": "N", // Coptic Capital Letter Ni
        "\u{2C9C}": "3", // Coptic Capital Letter Ksi
        "\u{2C9E}": "O", // Coptic Capital Letter O
        "\u{2C9F}": "o", // Coptic Small Letter O
        "\u{2CA2}": "P", // Coptic Capital Letter Ro
        "\u{2CA3}": "p", // Coptic Small Letter Ro
        "\u{2CA4}": "C", // Coptic Capital Letter Sima
        "\u{2CA5}": "c", // Coptic Small Letter Sima
        "\u{2CA6}": "T", // Coptic Capital Letter Tau
        "\u{2CA8}": "Y", // Coptic Capital Letter Ua
        "\u{2CA9}": "y", // Coptic Small Letter Ua
        "\u{2CAC}": "X", // Coptic Capital Letter Khi
        "\u{2CBD}": "w", // Coptic Small Letter Cryptogrammic Ni
        "\u{2CC4}": "3", // Coptic Capital Letter Old Coptic Shei
        "\u{2CCA}": "9", // Coptic Capital Letter Dialect-P Hori
        "\u{2CCB}": "9", // Coptic Small Letter Dialect-P Hori
        "\u{2CCC}": "3", // Coptic Capital Letter Old Coptic Hori
        "\u{2CCE}": "P", // Coptic Capital Letter Old Coptic Ha
        "\u{2CCF}": "p", // Coptic Small Letter Old Coptic Ha
        "\u{2CD0}": "L", // Coptic Capital Letter L-Shaped Ha
        "\u{2CD2}": "6", // Coptic Capital Letter Old Coptic Hei
        "\u{2CD3}": "6", // Coptic Small Letter Old Coptic Hei
        "\u{2CDC}": "6", // Coptic Capital Letter Old Nubian Shima
        "\u{A644}": "2", // Cyrillic Capital Letter Reversed Dze
        "\u{A647}": "i", // Cyrillic Small Letter Iota
        "\u{AB75}": "i", // Cherokee Small Letter V
        "\u{AB81}": "r", // Cherokee Small Letter Hu
        "\u{AB83}": "w", // Cherokee Small Letter La
        "\u{AB93}": "z", // Cherokee Small Letter No
        "\u{ABA9}": "v", // Cherokee Small Letter Do
        "\u{ABAA}": "s", // Cherokee Small Letter Du
        "\u{ABAF}": "c", // Cherokee Small Letter Tli
        "\u{FF21}": "A", // Fullwidth Latin Capital Letter A
        "\u{FF22}": "B", // Fullwidth Latin Capital Letter B
        "\u{FF23}": "C", // Fullwidth Latin Capital Letter C
        "\u{FF25}": "E", // Fullwidth Latin Capital Letter E
        "\u{FF28}": "H", // Fullwidth Latin Capital Letter H
        "\u{FF29}": "l", // Fullwidth Latin Capital Letter I
        "\u{FF2A}": "J", // Fullwidth Latin Capital Letter J
        "\u{FF2B}": "K", // Fullwidth Latin Capital Letter K
        "\u{FF2D}": "M", // Fullwidth Latin Capital Letter M
        "\u{FF2E}": "N", // Fullwidth Latin Capital Letter N
        "\u{FF2F}": "O", // Fullwidth Latin Capital Letter O
        "\u{FF30}": "P", // Fullwidth Latin Capital Letter P
        "\u{FF33}": "S", // Fullwidth Latin Capital Letter S
        "\u{FF34}": "T", // Fullwidth Latin Capital Letter T
        "\u{FF38}": "X", // Fullwidth Latin Capital Letter X
        "\u{FF39}": "Y", // Fullwidth Latin Capital Letter Y
        "\u{FF3A}": "Z", // Fullwidth Latin Capital Letter Z
        "\u{FF41}": "a", // Fullwidth Latin Small Letter A
        "\u{FF43}": "c", // Fullwidth Latin Small Letter C
        "\u{FF45}": "e", // Fullwidth Latin Small Letter E
        "\u{FF47}": "g", // Fullwidth Latin Small Letter G
        "\u{FF48}": "h", // Fullwidth Latin Small Letter H
        "\u{FF49}": "i", // Fullwidth Latin Small Letter I
        "\u{FF4A}": "j", // Fullwidth Latin Small Letter J
        "\u{FF4C}": "l", // Fullwidth Latin Small Letter L
        "\u{FF4F}": "o", // Fullwidth Latin Small Letter O
        "\u{FF50}": "p", // Fullwidth Latin Small Letter P
        "\u{FF53}": "s", // Fullwidth Latin Small Letter S
        "\u{FF56}": "v", // Fullwidth Latin Small Letter V
        "\u{FF58}": "x", // Fullwidth Latin Small Letter X
        "\u{FF59}": "y", // Fullwidth Latin Small Letter Y
        "\u{102F5}": "Z" // Coptic Epact Number Three Hundred
    ]

    /// Replaces characters from other scripts with the Latin ones they are drawn as.
    static func normalize(_ string: String) -> String {
        guard string.contains(where: { map[$0] != nil }) else { return string }
        return String(string.map { map[$0] ?? $0 })
    }
}
