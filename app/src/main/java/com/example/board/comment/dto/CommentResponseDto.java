package com.example.board.comment.dto;

import com.fasterxml.jackson.annotation.JsonFormat;
import lombok.Builder;
import lombok.Getter;

import java.time.LocalDateTime;

@Getter
@Builder
public class CommentResponseDto {
    private Long commentId;
    private String content;
    private String author;   // 보여줄 닉네임
    private String username; // 권한 체크용
    private Long parentId;
    @JsonFormat(pattern = "yyyy-MM-dd HH:mm:ss")
    private LocalDateTime createdAt;
    private LocalDateTime updatedAt;


    private long likeCount;     // 좋아요 개수
    private boolean likedByMe;  // 내가 눌렀는지 여부
}
