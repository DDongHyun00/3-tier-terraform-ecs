package com.example.board.like.controller;

import lombok.RequiredArgsConstructor;
import com.example.board.like.dto.LikeResponseDto;
import com.example.board.like.service.PostLikeService;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequiredArgsConstructor
@RequestMapping("/posts/{postId}/like")
public class PostLikeController {

    private final PostLikeService postLikeService;

    @PostMapping
    public ResponseEntity<LikeResponseDto> like(@PathVariable Long postId,
                                                @AuthenticationPrincipal UserDetails principal) {
        postLikeService.likePost(principal.getUsername(), postId);
        long count = postLikeService.countLikes(postId);
        boolean liked = true;
        return ResponseEntity.ok(new LikeResponseDto(liked, count));
    }

    @DeleteMapping
    public ResponseEntity<LikeResponseDto> unlikePost(@PathVariable Long postId,
                                                      @AuthenticationPrincipal UserDetails principal) {
        postLikeService.unlikePost(principal.getUsername(), postId);
        long count = postLikeService.countLikes(postId);
        boolean liked = false;
        return ResponseEntity.ok(new LikeResponseDto(liked, count));
    }

}