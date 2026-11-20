package voiceover.shared.elevenlabs

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Every failure the UI can meet. Messages are English only: localisation stays in the Swift string catalog,
 * so the app maps a case to its own text and uses [message] only where the server supplied it.
 */
public sealed class ElevenLabsError(message: String, cause: Throwable? = null) : Exception(message, cause) {
    public class MissingApiKey : ElevenLabsError("Add your ElevenLabs API key to get started.")
    public class InvalidApiKey : ElevenLabsError("Your API key was rejected. Check it in Settings.")

    /** The key is valid but wasn't granted the permission this endpoint needs; [detail] names it. */
    public class MissingPermission(public val detail: String) : ElevenLabsError(detail)
    public class QuotaExceeded : ElevenLabsError("You've used up your ElevenLabs credits for this period.")
    public class RateLimited : ElevenLabsError("Too many requests right now. Try again in a moment.")
    public class InvalidRequest(public val detail: String) : ElevenLabsError(detail)
    public class Server(public val status: Int) : ElevenLabsError("ElevenLabs is having trouble (HTTP $status). Try again.")

    /**
     * The request never got an HTTP answer. Swift carries `URLError.Code` here; the engines Ktor runs on throw
     * different exception types per platform, so only the original [cause] is kept.
     */
    public class Network(cause: Throwable) :
        ElevenLabsError("No connection to ElevenLabs. Check your network and retry.", cause)
    public class Decoding : ElevenLabsError("Got an unexpected response from ElevenLabs.")

    public enum class Recovery { OPEN_SETTINGS, RETRY, EDIT_INPUT, NONE }

    public val recovery: Recovery
        get() = when (this) {
            is MissingApiKey, is InvalidApiKey -> Recovery.OPEN_SETTINGS
            is RateLimited, is Server, is Network -> Recovery.RETRY
            is InvalidRequest -> Recovery.EDIT_INPUT
            is MissingPermission, is QuotaExceeded, is Decoding -> Recovery.NONE
        }

    // Exceptions need fresh instances for their stack traces, so the cases are classes rather than data objects;
    // equality is by case and payload, like the Swift enum's synthesized `Equatable`.
    override fun equals(other: Any?): Boolean = when {
        other !is ElevenLabsError || other::class != this::class -> false
        this is MissingPermission -> detail == (other as MissingPermission).detail
        this is InvalidRequest -> detail == (other as InvalidRequest).detail
        this is Server -> status == (other as Server).status
        else -> true
    }

    override fun hashCode(): Int = when (this) {
        is MissingPermission -> detail.hashCode()
        is InvalidRequest -> detail.hashCode()
        is Server -> status
        else -> this::class.hashCode()
    }

    override fun toString(): String = "${this::class.simpleName}($message)"

    internal companion object {
        /**
         * Maps an HTTP error response to a typed error.
         * ElevenLabs returns `{"detail": {"status": "...", "message": "..."}}` for most failures
         * and `{"detail": [{"msg": "..."}]}` for validation errors.
         */
        fun from(status: Int, body: String): ElevenLabsError {
            val detail = ErrorDetail.parse(body)
            return when {
                detail?.status == "quota_exceeded" -> QuotaExceeded()
                detail?.status == "missing_permissions" ->
                    MissingPermission(detail.message ?: "The API key is missing a permission this feature needs.")
                status == 401 || detail?.status == "invalid_api_key" -> InvalidApiKey()
                status == 429 -> RateLimited()
                status == 400 || status == 422 -> InvalidRequest(detail?.message ?: "The request was rejected.")
                else -> Server(status)
            }
        }
    }
}

internal class ErrorDetail(val status: String?, val message: String?) {
    companion object {
        /** Null whenever Swift's `ErrorBody` decoding would leave `detail` nil. */
        fun parse(body: String): ErrorDetail? {
            val root = runCatching { Json.parseToJsonElement(body) }.getOrNull() as? JsonObject ?: return null
            return when (val detail = root["detail"]) {
                is JsonObject -> runCatching {
                    ErrorDetail(detail.optionalString("status"), detail.optionalString("message"))
                }.getOrNull()
                is JsonArray -> runCatching {
                    val messages = detail.map { (it as JsonObject).optionalString("msg") }
                    ErrorDetail("validation_error", messages.firstOrNull())
                }.getOrNull()
                else -> null
            }
        }

        /** A missing key or JSON null is fine; any other non-string fails, as `Decodable` does for `String?`. */
        private fun JsonObject.optionalString(key: String): String? = when (val value: JsonElement? = this[key]) {
            null, JsonNull -> null
            is JsonPrimitive -> if (value.isString) value.content else throw IllegalArgumentException(key)
            else -> throw IllegalArgumentException(key)
        }
    }
}
