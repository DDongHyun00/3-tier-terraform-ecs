package com.example.board.notification.service;

import lombok.RequiredArgsConstructor;
import com.example.board.board.entity.Post;
import com.example.board.notification.dto.NotificationResponseDto;
import com.example.board.notification.entity.Notification;
import com.example.board.notification.repository.NotificationRepository;
import com.example.board.user.entity.User;
import com.example.board.user.repository.UserRepository;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import java.io.IOException;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

@Service
@RequiredArgsConstructor
public class NotificationService {

    private final NotificationRepository notificationRepository;
    private final UserRepository userRepository;

    // 유저별 SSE 연결 관리
    private final Map<String, SseEmitter> emitters = new ConcurrentHashMap<>();

//    알림 구독 (헤더 종 모양 클릭 시 or 자동 연결)
    public SseEmitter subscribe(String username) {
        // 30분 타임아웃 설정 (30 * 60 * 1000 = 1,800,000ms)
        SseEmitter emitter = new SseEmitter(30 * 60 * 1000L);
        emitters.put(username, emitter);

        emitter.onCompletion(() -> {
            emitters.remove(username);
//            System.out.println("SSE 연결 완료: " + username);
        });
        emitter.onTimeout(() -> {
            emitters.remove(username);
//            System.out.println("SSE 연결 타임아웃: " + username);
        });
        emitter.onError((ex) -> {
            emitters.remove(username);
//            System.out.println("SSE 연결 오류: " + username + " - " + ex.getMessage());
        });

        return emitter;
    }

//    알림 전송 + DB 저장
    @Transactional
    public void sendNotification(String targetUsername, String message, Post post) {
        User targetUser = userRepository.findByUsername(targetUsername)
                .orElseThrow(() -> new IllegalArgumentException("사용자를 찾을 수 없습니다."));

        // DB 저장
        Notification notification = new Notification(targetUser, message, false, post);
        notificationRepository.save(notification);

        // SSE 전송
        SseEmitter emitter = emitters.get(targetUsername);
        if (emitter != null) {
            try {
                emitter.send(SseEmitter.event()
                        .name("notification")
                        .data(message, MediaType.TEXT_PLAIN));
            } catch (IOException e) {
                emitters.remove(targetUsername); // 연결 끊기면 제거
            }
        }
    }

    @Transactional
    public void markAllAsRead(String username) {
        User user = userRepository.findByUsername(username)
                .orElseThrow(() -> new IllegalArgumentException("사용자를 찾을 수 없습니다."));
        List<Notification> unread = notificationRepository.findByTargetUserAndReadFalse(user);
        unread.forEach(Notification::markAsRead);
        notificationRepository.saveAll(unread);
    }

    @Transactional(readOnly = true)
    public List<NotificationResponseDto> getMyNotifications(String username) {
        User user = userRepository.findByUsername(username)
                .orElseThrow(() -> new IllegalArgumentException("사용자를 찾을 수 없습니다."));

        return notificationRepository.findByTargetUserOrderByCreatedAtDesc(user)
                .stream()
                .map(n -> new NotificationResponseDto(
                        n.getId(),
                        n.getMessage(),
                        n.isRead(),
                        n.getCreatedAt(),
                        n.getPost() != null ? n.getPost().getPostId() : null,
                        n.getPost() != null ? n.getPost().getTitle() : null
                ))
                .toList();
    }

    @Transactional(readOnly = true)
    public long getUnreadCount(String username) {
        User user = userRepository.findByUsername(username)
                .orElseThrow(() -> new IllegalArgumentException("사용자를 찾을 수 없습니다."));
        return notificationRepository.countByTargetUserAndReadFalse(user);
    }

}


