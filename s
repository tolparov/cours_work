package ru.sber.poirot.notifications.admin

import org.springframework.security.access.prepost.PreAuthorize
import org.springframework.web.bind.annotation.*
import ru.sber.permissions.HAS_MANAGE_NOTIFICATIONS
import ru.sber.poirot.audit.AuditClient
import ru.sber.poirot.notifications.admin.dto.CreateRequest
import ru.sber.poirot.notifications.admin.dto.NotificationResponse
import ru.sber.poirot.notifications.admin.dto.UpdateRequest

@RestController
@RequestMapping("/api/adminNotification")
class AdminNotificationController(
    private val service: AdminNotifications,
    private val auditClient: AuditClient
) {

    @PostMapping("/create")
    @PreAuthorize(HAS_MANAGE_NOTIFICATIONS)
    suspend fun create(@RequestBody request: CreateRequest): NotificationResponse =
        auditClient.audit(event = "NOTIFICATION_CREATE", details = "request=$request") {
            service.create(request)
        }

    @PutMapping("/update")
    @PreAuthorize(HAS_MANAGE_NOTIFICATIONS)
    suspend fun update(@RequestBody request: UpdateRequest): Unit =
        auditClient.audit(event = "NOTIFICATION_UPDATE", details = "request=$request") {
            service.update(request)
        }

    @DeleteMapping("/archive/{id}")
    @PreAuthorize(HAS_MANAGE_NOTIFICATIONS)
    suspend fun archive(@PathVariable id: Long): Unit =
        auditClient.audit(event = "NOTIFICATION_ARCHIVE", details = "id=$id") {
            service.archive(id)
        }

    @GetMapping("/fetchAll")
    @PreAuthorize(HAS_MANAGE_NOTIFICATIONS)
    suspend fun fetchAll(): List<NotificationResponse> =
        auditClient.audit(event = "NOTIFICATION_FETCH_ALL") {
            service.fetchAll()
        }
}
