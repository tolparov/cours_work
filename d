package ru.sber.poirot.notifications.admin.dto

import com.fasterxml.jackson.annotation.JsonProperty

data class WsMessage(
    val type: Type,
    val data: Any? = null,
    val message: String? = null
) {
    enum class Type {
        @JsonProperty("data") DATA,
        @JsonProperty("delete") DELETE,
        @JsonProperty("subscribe") SUBSCRIBE,
        @JsonProperty("ping") PING,
        @JsonProperty("error") ERROR
    }

    companion object {
        fun data(payload: List<FeedResponse>) = WsMessage(Type.DATA, data = payload)
        fun delete(ids: List<Long>) = WsMessage(Type.DELETE, data = ids)
        fun ping() = WsMessage(Type.PING)
        fun error(msg: String) = WsMessage(Type.ERROR, message = msg)
    }
}
