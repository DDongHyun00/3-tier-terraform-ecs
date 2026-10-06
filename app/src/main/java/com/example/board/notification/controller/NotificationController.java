package com.example.board.notification.controller;

import lombok.RequiredArgsConstructor;
import com.example.board.notification.dto.NotificationResponseDto;
import com.example.board.notification.entity.Notification;
import com.example.board.notification.repository.NotificationRepository;
import com.example.board.notification.service.NotificationService;
import com.example.board.user.entity.User;
import com.example.board.user.repository.UserRepository;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import java.util.Collections;
import java.util.List;

@RestController
@RequiredArgsConstructor
public class NotificationController {

    private final NotificationService notificationService;

    // SSE 구독
    @GetMapping("/api/notifications/subscribe")
    public SseEmitter subscribe(@AuthenticationPrincipal UserDetails principal) {
        if (principal == null) {
            // 로그인하지 않은 경우 SSE 연결 안 함
            return new SseEmitter(0L); // 바로 만료 처리
        }
        // 30분 타임아웃 설정
        return notificationService.subscribe(principal.getUsername());
    }

    // 내 알림 내역 조회 (마이페이지)
    @GetMapping("/api/notifications")
    public List<NotificationResponseDto> getMyNotifications(@AuthenticationPrincipal UserDetails principal) {
        if (principal == null) {
            return Collections.emptyList(); // 로그인 안 했으면 빈 리스트 반환
        }
        return notificationService.getMyNotifications(principal.getUsername());
    }

    // 전체 읽음 처리
    @GetMapping("/api/notifications/read-all")
    public void markAllAsRead(@AuthenticationPrincipal UserDetails principal) {
        if (principal != null) {
            notificationService.markAllAsRead(principal.getUsername());
        }
    }

    // 읽지 않은 알림 개수 조회
    @GetMapping("/api/notifications/unreadCount")
    public long getUnreadCount(@AuthenticationPrincipal UserDetails principal) {
        if (principal == null) {
            return 0L;
        }
        return notificationService.getUnreadCount(principal.getUsername());
    }
}