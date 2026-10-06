package com.example.board.notification.dto;

import java.time.LocalDateTime;

public record NotificationResponseDto(
        Long id,
        String message,
        boolean read,
        LocalDateTime createdAt,
        Long postId,
        String postTitle
) {}
