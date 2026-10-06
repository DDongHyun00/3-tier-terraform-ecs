package com.example.board.user.service;

import lombok.RequiredArgsConstructor;
import com.example.board.board.repository.PostRepository;
import com.example.board.comment.repository.CommentRepository;
import com.example.board.like.repository.PostLikeRepository;
import com.example.board.user.dto.TimelineItemDto;
import com.example.board.user.entity.User;
import com.example.board.user.repository.UserRepository;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.Comparator;
import java.util.List;

@Service
@RequiredArgsConstructor
public class TimelineService {

    private final PostRepository postRepository;
    private final CommentRepository commentRepository;
    private final PostLikeRepository postLikeRepository;
    private final UserRepository userRepository;

    public List<TimelineItemDto> getUserTimeline(String username) {
        User user = userRepository.findByUsername(username).orElseThrow();

        List<TimelineItemDto> timeline = new ArrayList<>();

        // 게시글 작성
        user.getPosts().forEach(p ->
                timeline.add(new TimelineItemDto(
                        "POST",
                        p.getTitle(),
                        null, // 대상 글 없음
                        null,
                        p.getCreatedAt()
                ))
        );

        // 댓글 작성
        user.getComments().forEach(c ->
                timeline.add(new TimelineItemDto(
                        "COMMENT",
                        c.getContent(),
                        c.getPost().getTitle(),
                        c.getPost().getUser().getNickname(),
                        c.getCreatedAt()
                ))
        );

        // 좋아요
        user.getPostLikes().forEach(l ->
                timeline.add(new TimelineItemDto(
                        "LIKE",
                        "좋아요",
                        l.getPost().getTitle(),
                        l.getPost().getUser().getNickname(),
                        l.getCreatedAt()
                ))
        );

        return timeline.stream()
                .sorted(Comparator.comparing(TimelineItemDto::getCreatedAt).reversed())
                .toList();
        }
}

