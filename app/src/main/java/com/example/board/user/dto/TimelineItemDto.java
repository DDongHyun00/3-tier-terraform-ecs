package com.example.board.user.dto;

import lombok.AllArgsConstructor;
import lombok.Getter;

import java.time.LocalDateTime;

@Getter
@AllArgsConstructor
public class TimelineItemDto {
    private String type; // POST, COMMENT, LIKE
    private String content;
    private String targetTitle;
    private String targetAuthor;
    private LocalDateTime createdAt;
}
