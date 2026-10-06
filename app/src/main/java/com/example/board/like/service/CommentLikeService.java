package com.example.board.like.service;

import lombok.RequiredArgsConstructor;
import com.example.board.comment.entity.Comment;
import com.example.board.comment.repository.CommentRepository;
import com.example.board.like.entity.CommentLike;
import com.example.board.like.repository.CommentLikeRepository;
import com.example.board.user.entity.User;
import com.example.board.user.repository.UserRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class CommentLikeService {

    private final CommentLikeRepository commentLikeRepository;
    private final CommentRepository commentRepository;
    private final UserRepository userRepository;

    @Transactional
    public void likeComment(String username, Long commentId) {
        User user = userRepository.findByUsername(username).orElseThrow();
        Comment comment = commentRepository.findById(commentId).orElseThrow();

        if (commentLikeRepository.existsByUserAndComment(user, comment)) {
            throw new IllegalStateException("이미 좋아요를 누른 댓글입니다.");
        }

        commentLikeRepository.save(new CommentLike(user, comment));
    }

    @Transactional
    public void unlikeComment(String username, Long commentId) {
        User user = userRepository.findByUsername(username).orElseThrow();
        Comment comment = commentRepository.findById(commentId).orElseThrow();

        commentLikeRepository.findByUserAndComment(user, comment)
                .ifPresent(commentLikeRepository::delete);
    }

    @Transactional(readOnly = true)
    public boolean isLikedByUser(String username, Long commentId) {
        User user = userRepository.findByUsername(username).orElseThrow();
        Comment comment = commentRepository.findById(commentId).orElseThrow();
        return commentLikeRepository.existsByUserAndComment(user, comment);
    }

    @Transactional(readOnly = true)
    public long countLikes(Long commentId) {
        Comment comment = commentRepository.findById(commentId).orElseThrow();
        return commentLikeRepository.countByComment(comment);
    }

    @Transactional(readOnly = true)
    public Map<Long, Long> countLikesInBatch(List<Long> commentIds) {
        if (commentIds.isEmpty()) return Map.of();
        return commentLikeRepository.countByCommentIds(commentIds).stream()
                .collect(Collectors.toMap(
                        r -> (Long) r[0],
                        r -> (Long) r[1]
                ));
    }

    @Transactional(readOnly = true)
    public Map<Long, Boolean> likedByUserInBatch(String username, List<Long> commentIds) {
        if (username == null || commentIds.isEmpty()) return Map.of();
        List<Long> likedIds = commentLikeRepository.findLikedCommentIds(username, commentIds);
        return commentIds.stream().collect(Collectors.toMap(
                id -> id,
                likedIds::contains
        ));
    }
}
