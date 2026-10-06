package com.example.board.comment.controller;

import lombok.RequiredArgsConstructor;
import com.example.board.comment.dto.CommentUpdateResponseDto;
import com.example.board.comment.dto.CommentRequestDto;
import com.example.board.comment.dto.CommentResponseDto;
import com.example.board.comment.service.CommentService;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.web.bind.annotation.*;

@RestController
@RequiredArgsConstructor
@RequestMapping("/posts/{postId}/comments")
public class CommentController {

    private final CommentService commentService;

    @PostMapping
    public ResponseEntity<CommentResponseDto> create(@PathVariable Long postId,
                                                     @RequestBody CommentRequestDto dto,
                                                     @AuthenticationPrincipal UserDetails principal) {
        Long commentId = commentService.createComment(postId, principal.getUsername(), dto, dto.getParentId());

        CommentResponseDto response = commentService.getCommentDto(commentId, principal.getUsername());
        return ResponseEntity.ok(response);
    }


    @PutMapping("/{commentId}")
    public ResponseEntity<CommentUpdateResponseDto> update(@PathVariable Long postId,
                                                           @PathVariable Long commentId,
                                                           @RequestBody CommentRequestDto dto,
                                                           @AuthenticationPrincipal UserDetails principal) {
        commentService.updateComment(commentId, principal.getUsername(), dto);

        CommentResponseDto updated = commentService.getCommentDto(commentId, principal.getUsername());
        return ResponseEntity.ok(new CommentUpdateResponseDto(updated.getContent()));
    }


    @DeleteMapping("/{commentId}")
    public ResponseEntity<Void> delete(@PathVariable Long postId,
                                       @PathVariable Long commentId,
                                       @AuthenticationPrincipal UserDetails principal) {
        commentService.deleteComment(commentId, principal.getUsername());
        return ResponseEntity.noContent().build(); // 204
    }


}