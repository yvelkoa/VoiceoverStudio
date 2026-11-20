package voiceover.shared.elevenlabs

import platform.Foundation.NSString
import platform.Foundation.localizedCaseInsensitiveCompare

@Suppress("CAST_NEVER_SUCCEEDS")
internal actual fun compareLocalizedCaseInsensitive(a: String, b: String): Int =
    (a as NSString).localizedCaseInsensitiveCompare(b).toInt()
