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
                            log.debug("Received PING from {}", session.id)
                            Mono.empty<Void>()
                        }

                        // 🟢 ИСПРАВЛЕНО: Правильная обработка SUBSCRIBE
                        WsMessage.Type.SUBSCRIBE -> mono {
                            log.info("Processing SUBSCRIBE for session {}", session.id)
                            
                            val (feed, roleIds) = try {
                                adminNotifications.feed()
                            } catch (e: Exception) {
                                log.error("Failed to get feed for {}: {}", session.id, e.message, e)
                                val errorMsg = WsMessage.error("Authentication failed: ${e.message}")
                                // 🟢 Возвращаем Mono для отправки ошибки
                                return@mono session.send(
                                    Mono.just(session.textMessage(errorMsg.toJson()))
                                )
                            }

                            log.info("Subscribed session {} with roles: {}, feed size: {}", 
                                session.id, roleIds, feed.size)

                            // Регистрируем клиента
                            BroadcastRegistry.register(session.id, session, roleIds, feed)

                            // 🟢 Отправляем начальный feed как часть реактивной цепочки
                            val wsMsg = WsMessage.data(feed)
                            session.textMessage(wsMsg.toJson())
                        }.flatMap { message ->
                            // 🟢 ВАЖНО: Отправляем сообщение как часть цепочки, а не через subscribe()
                            session.send(Mono.just(message))
                        }

                        else -> {
                            log.warn("Unknown WSMessage type: {} from {}", wsMessage.type, session.id)
                            val err = WsMessage.error("Unknown WSMessage type: ${wsMessage.type}")
                            session.send(Mono.just(session.textMessage(err.toJson())))
                        }
                    }
                } catch (e: Exception) {
                    log.error("WS processing error for {}: {}", session.id, e.message, e)
                    val errorMsg = WsMessage.error("Invalid WSMessage: ${e.message}")
                    session.send(Mono.just(session.textMessage(errorMsg.toJson())))
                }
            }
            .doFinally { signal ->
                log.info("Closing WS connection: {} by signal: {}", session.id, signal)
                BroadcastRegistry.unregister(session.id)
            }

        val heartbeatFlux = heartbeat(lastSeen, session)

        return Flux.merge(receiveFlux, heartbeatFlux).then()
    }

    private fun heartbeat(lastSeen: AtomicLong, session: WebSocketSession): Flux<Void> =
        Flux.interval(Duration.ofSeconds(180))
            .flatMap {
                val now = System.currentTimeMillis()
                val timeSinceLastSeen = now - lastSeen.get()
                
                if (timeSinceLastSeen >= 600_000) {
                    log.warn("Session {} timed out (no activity for {}ms). Closing.", 
                        session.id, timeSinceLastSeen)
                    BroadcastRegistry.unregister(session.id)
                    session.close()
                } else {
                    log.debug("Sending PING to session {}", session.id)
                    val ping = session.textMessage(WsMessage.ping().toJson())
                    session.send(Mono.just(ping))
                }
            }
            .then(Mono.empty<Void>())
}
