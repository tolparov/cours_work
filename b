package ru.sber.poirot.notifications.websocket

import kotlinx.coroutines.reactor.mono
import org.springframework.web.reactive.socket.WebSocketHandler
import org.springframework.web.reactive.socket.WebSocketSession
import reactor.core.publisher.Mono
import org.springframework.web.reactive.socket.*
import reactor.core.publisher.Flux
import ru.sber.parseJson
import ru.sber.poirot.notifications.admin.AdminNotifications
import ru.sber.poirot.notifications.admin.dto.WsMessage
import ru.sber.toJson
import ru.sber.utils.logger
import java.time.Duration
import java.util.concurrent.atomic.AtomicLong

class FeedWebSocketHandler(
    private val adminNotifications: AdminNotifications
) : WebSocketHandler {

    private val log = logger()

    override fun handle(session: WebSocketSession): Mono<Void> {
        log.info("New WS connection: {}", session.id)
        val lastSeen = AtomicLong(System.currentTimeMillis())

        val receiveFlux = session.receive()
            .flatMap { msg ->
                lastSeen.set(System.currentTimeMillis())
                val payload = msg.payloadAsText

                try {
                    val wsMessage = payload.parseJson<WsMessage>()

                    when (wsMessage.type) {
                        WsMessage.Type.PING -> {
                            log.info("Received ping from {}", session.id)
                            Mono.empty<Void>()
                        }

                        WsMessage.Type.SUBSCRIBE -> mono {
                            log.info("Subscribing to feed for {}", session.id)
                            val (feed, roleIds) = adminNotifications.feed()

                            val wsMsg = WsMessage.data(feed)
                            session.send(Mono.just(session.textMessage(wsMsg.toJson())))

                            BroadcastRegistry.register(session.id, session, roleIds, feed)
                        }.then()

                        else -> {
                            val err = WsMessage.error("Unknown WSMessage type: ${wsMessage.type}")
                            session.send(Mono.just(session.textMessage(err.toJson()))).then()
                        }
                    }
                } catch (e: Exception) {
                    log.error("WS processing error: {}", e.message)
                    val errorMsg = WsMessage.error("Invalid WSMessage: ${e.message}")
                    session.send(Mono.just(session.textMessage(errorMsg.toJson()))).then()
                }
            }
            .doFinally { signal ->
                log.info("Closing WS connection: {} by {}", session.id, signal)
                BroadcastRegistry.unregister(session.id)
            }

        val heartbeatFlux = heartbeat(lastSeen, session)

        return Flux.merge(receiveFlux, heartbeatFlux).then()
    }

    fun heartbeat(lastSeen: AtomicLong, session: WebSocketSession): Flux<WebSocketMessage> =
        Flux.interval(Duration.ofSeconds(180))
            .flatMap {
                val now = System.currentTimeMillis()
                if (now - lastSeen.get() >= 600_000) {
                    log.warn("Session {} did not respond to heartbeat. Closing.", session.id)
                    BroadcastRegistry.unregister(session.id)
                    session.close().subscribe()
                    Mono.empty<WebSocketMessage>()
                } else {
                    val ping = session.textMessage(WsMessage.ping().toJson())
                    session.send(Mono.just(ping))
                        .doOnError { e ->
                            log.warn("Failed to send ping to {}: {}", session.id, e.message)
                            BroadcastRegistry.unregister(session.id)
                            session.close().subscribe()
                        }
                        .subscribe()
                    Mono.just(ping)
                }
            }
}
