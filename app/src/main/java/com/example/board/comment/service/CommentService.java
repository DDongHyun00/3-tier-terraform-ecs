package com.example.board.comment.service;

import com.example.board.common.exception.ForbiddenException;
import com.example.board.common.exception.NotFoundException;
import lombok.RequiredArgsConstructor;
import com.example.board.board.entity.Post;
import com.example.board.board.repository.PostRepository;
import com.example.board.comment.dto.CommentRequestDto;
import com.example.board.comment.dto.CommentResponseDto;
import com.example.board.comment.entity.Comment;
import com.example.board.comment.repository.CommentRepository;
import com.example.board.like.service.CommentLikeService;
import com.example.board.notification.service.NotificationService;
import com.example.board.user.entity.User;
import com.example.board.user.repository.UserRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

@Service
@RequiredArgsConstructor
public class CommentService {

    private final CommentRepository commentRepository;
    private final PostRepository postRepository;
    private final UserRepository userRepository;
    private final CommentLikeService commentLikeService;
    private final NotificationService notificationService;

    // 댓글 작성 (parentId 있으면 대댓글)
    @Transactional
    public Long createComment(Long postId,
                              String username,
                              CommentRequestDto dto,
                              Long parentId) {

        Post post = postRepository.findById(postId)
                .orElseThrow(() -> new NotFoundException("게시글을 찾을 수 없습니다."));
        User user = userRepository.findByUsername(username)
                .orElseThrow(() -> new IllegalArgumentException("사용자를 찾을 수 없습니다."));

        if (dto == null || dto.getContent() == null || dto.getContent().trim().isEmpty()) {
            throw new IllegalArgumentException("댓글 내용은 비어 있을 수 없습니다.");
        }

        Comment parent = null;
        if (parentId != null) {
            parent = commentRepository.findById(parentId)
                    .orElseThrow(() -> new NotFoundException("부모 댓글을 찾을 수 없습니다."));
        }

        Comment comment = Comment.builder()
                .post(post)
                .user(user)
                .content(dto.getContent().trim())
                .parent(parent)
                .build();

        Comment saved = commentRepository.save(comment);

        // 대댓글 알림
        if (parent != null && !parent.getUser().getUsername().equals(username)) {
            notificationService.sendNotification(
                    parent.getUser().getUsername(),
                    user.getNickname() + "님이 회원님의 댓글이 달린 글 [" + post.getTitle() + "] 에 대댓글을 남겼습니다.",
                    post
            );
        }
// 일반 댓글 알림
        else if (!post.getUser().getUsername().equals(username)) {
            notificationService.sendNotification(
                    post.getUser().getUsername(),
                    user.getNickname() + "님이 회원님의 글 [" + post.getTitle() + "] 에 댓글을 남겼습니다.",
                    post
            );
        }

        return saved.getCommentId();
    }

    // 댓글 조회 (게시글 기준)
    @Transactional(readOnly = true)
    public List<CommentResponseDto> getComments(Long postId, String currentUsername) {
        Post post = postRepository.findById(postId)
                .orElseThrow(() -> new NotFoundException("게시글을 찾을 수 없습니다."));

        // 1) 댓글 + 작성자(User) 함께 조회
        List<Comment> comments = commentRepository.findByPostWithUser(postId);

        // 2) 좋아요 정보 배치 조회
        List<Long> ids = comments.stream().map(Comment::getCommentId).toList();
        Map<Long, Long> likeCountMap = commentLikeService.countLikesInBatch(ids);
        Map<Long, Boolean> likedMap = commentLikeService.likedByUserInBatch(currentUsername, ids);

        // 3) 자식 댓글 그룹핑
        Map<Long, List<Comment>> childrenMap = comments.stream()
                .filter(c -> c.getParent() != null)
                .collect(Collectors.groupingBy(c -> c.getParent().getCommentId()));

        // 4) 부모 댓글 + 자식 댓글 DTO 변환
        List<CommentResponseDto> result = new ArrayList<>();
        comments.stream()
                .filter(c -> c.getParent() == null)
                .forEach(parent -> {
                    result.add(toDto(parent, likeCountMap, likedMap));
                    List<Comment> children = childrenMap.getOrDefault(parent.getCommentId(), List.of());
                    children.forEach(child -> result.add(toDto(child, likeCountMap, likedMap)));
                });

        return result;
    }

    // DTO 변환 (배치용)
    private CommentResponseDto toDto(Comment comment,
                                     Map<Long, Long> likeCountMap,
                                     Map<Long, Boolean> likedMap) {
        return CommentResponseDto.builder()
                .commentId(comment.getCommentId())
                .content(comment.getContent())
                .author(comment.getUser().getNickname())
                .username(comment.getUser().getUsername())
                .parentId(comment.getParent() != null ? comment.getParent().getCommentId() : null)
                .createdAt(comment.getCreatedAt())
                .updatedAt(comment.getUpdatedAt())
                .likeCount(likeCountMap.getOrDefault(comment.getCommentId(), 0L))
                .likedByMe(likedMap.getOrDefault(comment.getCommentId(), false))
                .build();
    }

    // DTO 변환 (단건 조회용)
    private CommentResponseDto toDto(Comment comment, String currentUsername) {
        long likeCount = commentLikeService.countLikes(comment.getCommentId());
        boolean likedByMe = (currentUsername != null)
                && commentLikeService.isLikedByUser(currentUsername, comment.getCommentId());

        return CommentResponseDto.builder()
                .commentId(comment.getCommentId())
                .content(comment.getContent())
                .author(comment.getUser().getNickname())
                .username(comment.getUser().getUsername())
                .parentId(comment.getParent() != null ? comment.getParent().getCommentId() : null)
                .createdAt(comment.getCreatedAt())
                .updatedAt(comment.getUpdatedAt())
                .likeCount(likeCount)
                .likedByMe(likedByMe)
                .build();
    }

    // 댓글 수정
    @Transactional
    public void updateComment(Long commentId, String username, CommentRequestDto dto) {
        Comment comment = commentRepository.findById(commentId)
                .orElseThrow(() -> new NotFoundException("댓글을 찾을 수 없습니다."));
        if (!comment.getUser().getUsername().equals(username)) {
            throw new ForbiddenException("본인 댓글만 수정할 수 있습니다.");
        }
        comment.update(dto.getContent());
    }

    // 댓글 삭제
    @Transactional
    public void deleteComment(Long commentId, String username) {
        Comment comment = commentRepository.findById(commentId)
                .orElseThrow(() -> new NotFoundException("댓글을 찾을 수 없습니다."));
        if (!comment.getUser().getUsername().equals(username)) {
            throw new ForbiddenException("본인 댓글만 삭제할 수 있습니다.");
        }
        commentRepository.delete(comment);
    }

    // 단건 댓글 조회
    @Transactional(readOnly = true)
    public CommentResponseDto getCommentDto(Long commentId, String currentUsername) {
        Comment comment = commentRepository.findById(commentId)
                .orElseThrow(() -> new NotFoundException("댓글을 찾을 수 없습니다."));
        return toDto(comment, currentUsername);
    }
}
