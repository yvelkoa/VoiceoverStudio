package voiceover.shared.captions

/**
 * Swift's `Character.isWhitespace` follows the Unicode `White_Space` property. Kotlin's `Char.isWhitespace()`
 * is a different set (it adds U+001C..U+001F and leaves out U+0085), so the set is spelled out here to keep
 * word boundaries identical to the Swift implementation on every target.
 */
internal fun Char.isUnicodeWhiteSpace(): Boolean = when (code) {
    in 0x0009..0x000D, 0x0020, 0x0085, 0x00A0, 0x1680, in 0x2000..0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000 -> true
    else -> false
}

/**
 * Length in Unicode code points. Swift's `String.count` counts grapheme clusters, which the Kotlin common
 * stdlib cannot do; code points agree with it for everything except multi-scalar clusters (emoji sequences,
 * combining marks). See docs/kmp-experiment.md.
 */
internal fun String.codePointCount(): Int {
    var count = 0
    var index = 0
    while (index < length) {
        val isPair = this[index].isHighSurrogate() && index + 1 < length && this[index + 1].isLowSurrogate()
        index += if (isPair) 2 else 1
        count++
    }
    return count
}
