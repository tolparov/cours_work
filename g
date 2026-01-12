package ru.sber.poirot.notifications.websocket

import org.springframework.context.annotation.Bean
import org.springframework.context.annotation.Configuration
import org.springframework.web.reactive.HandlerMapping
import org.springframework.web.reactive.handler.SimpleUrlHandlerMapping
import org.springframework.web.reactive.socket.server.support.WebSocketHandlerAdapter
import ru.sber.poirot.notifications.admin.AdminNotifications

@Configuration
class WebSocketConfig {

    @Bean
    fun feedWebSocketHandler(
        adminNotifications: AdminNotifications
    ): FeedWebSocketHandler = FeedWebSocketHandler(adminNotifications)

    @Bean
    fun webSocketHandlerMapping(feedWebSocketHandler: FeedWebSocketHandler): HandlerMapping {
        val map = mapOf("/ws/feed" to feedWebSocketHandler)
        return SimpleUrlHandlerMapping(map, -1)
    }

    @Bean
    fun handlerAdapter() = WebSocketHandlerAdapter()
}
