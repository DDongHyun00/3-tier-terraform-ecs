package com.example.board.notification.repository;

import com.example.board.notification.entity.Notification;
import com.example.board.user.entity.User;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface NotificationRepository extends JpaRepository<Notification, Long> {
    List<Notification> findByTargetUserOrderByCreatedAtDesc(User targetUser);
    List<Notification> findByTargetUserAndReadFalse(User targetUser);
    long countByTargetUserAndReadFalse(User targetUser);
}