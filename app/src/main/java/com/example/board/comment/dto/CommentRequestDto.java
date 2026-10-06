package com.example.board.comment.dto;

import jakarta.validation.constraints.NotBlank;
import lombok.Getter;
import lombok.Setter;

@Getter
@Setter
public class CommentRequestDto {
    @NotBlank(message = "댓글 내용은 비어 있을 수 없습니다.")
    private String content;
    private Long parentId; // 대댓글이면 부모 댓글 ID
}
