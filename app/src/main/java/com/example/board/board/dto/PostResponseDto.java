package com.example.board.board.dto;

import lombok.Builder;
import lombok.Getter;

import java.time.LocalDateTime;

@Getter
@Builder
public class PostResponseDto {
    private Long postId;
    private String title;
    private String content;
    private String author;
    private long viewCount;
    private long likeCount;
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;

    private boolean hasFiles;
}
