package com.example.board.like.controller;

import lombok.RequiredArgsConstructor;
import com.example.board.like.dto.LikeResponseDto;
import com.example.board.like.service.CommentLikeService;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequiredArgsConstructor
@RequestMapping("/posts/{postId}/comments/{commentId}/like")
public class CommentLikeController {

    private final CommentLikeService commentLikeService;

    @PostMapping
    public ResponseEntity<LikeResponseDto> like(@PathVariable Long postId,
                                                @PathVariable Long commentId,
                                                @AuthenticationPrincipal UserDetails principal) {
        commentLikeService.likeComment(principal.getUsername(), commentId);
        long count = commentLikeService.countLikes(commentId);
        boolean liked = true;
        return ResponseEntity.ok(new LikeResponseDto(liked, count));
    }

    @DeleteMapping
    public ResponseEntity<LikeResponseDto> unlike(@PathVariable Long postId,
                                                  @PathVariable Long commentId,
                                                  @AuthenticationPrincipal UserDetails principal) {
        commentLikeService.unlikeComment(principal.getUsername(), commentId);
        long count = commentLikeService.countLikes(commentId);
        boolean liked = false;
        return ResponseEntity.ok(new LikeResponseDto(liked, count));
    }


}