package com.example.board.admin.service;

import lombok.RequiredArgsConstructor;
import com.example.board.admin.dto.DashboardStatsDto;
import com.example.board.board.repository.PostRepository;
import com.example.board.comment.repository.CommentRepository;
import com.example.board.like.repository.PostLikeRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDate;
import java.time.LocalDateTime;

@Service
@RequiredArgsConstructor
public class DashboardService {

    private final PostRepository postRepository;
    private final CommentRepository commentRepository;
    private final PostLikeRepository postLikeRepository;

    @Transactional(readOnly = true)
    public DashboardStatsDto getStats() {
        LocalDate today = LocalDate.now();
        LocalDateTime start = today.atStartOfDay();
        LocalDateTime end = today.plusDays(1).atStartOfDay();

        return new DashboardStatsDto(
                postRepository.count(),
                postRepository.countTodayPosts(start, end),
                commentRepository.count(),
                commentRepository.countTodayComments(start, end),
                postLikeRepository.count(),
                postLikeRepository.countTodayLikes(start, end)
        );
    }
}
