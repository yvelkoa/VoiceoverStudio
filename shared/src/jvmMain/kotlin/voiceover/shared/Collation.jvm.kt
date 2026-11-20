package voiceover.shared.elevenlabs

import java.text.Collator

internal actual fun compareLocalizedCaseInsensitive(a: String, b: String): Int =
    Collator.getInstance().apply { strength = Collator.SECONDARY }.compare(a, b)
