package com.example.board.like.service;

import lombok.RequiredArgsConstructor;
import com.example.board.board.entity.Post;
import com.example.board.board.repository.PostRepository;
import com.example.board.like.entity.PostLike;
import com.example.board.like.repository.PostLikeRepository;
import com.example.board.notification.entity.Notification;
import com.example.board.notification.service.NotificationService;
import com.example.board.user.entity.User;
import com.example.board.user.repository.UserRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
public class PostLikeService {

    private final PostLikeRepository postLikeRepository;
    private final PostRepository postRepository;
    private final UserRepository userRepository;
    private final NotificationService notificationService;

    @Transactional
    public void likePost(String username, Long postId) {
        User user = userRepository.findByUsername(username).orElseThrow();
        Post post = postRepository.findById(postId).orElseThrow();

        if (postLikeRepository.existsByUserAndPost(user, post)) {
            throw new IllegalStateException("이미 좋아요를 누른 게시글입니다.");
        }
        if (!post.getUser().getUsername().equals(username)) {
            notificationService.sendNotification(
                    post.getUser().getUsername(),
                    user.getNickname() + "님이 회원님의 글 [" + post.getTitle() + "] 에 좋아요를 눌렀습니다.",
                    post
            );
        }


        postLikeRepository.save(new PostLike(user, post));
    }

    @Transactional
    public void unlikePost(String username, Long postId) {
        User user = userRepository.findByUsername(username).orElseThrow();
        Post post = postRepository.findById(postId).orElseThrow();

        postLikeRepository.findByUserAndPost(user, post)
                .ifPresent(postLikeRepository::delete);
    }

    @Transactional(readOnly = true)
    public boolean isLikedByUser(String username, Long postId) {
        User user = userRepository.findByUsername(username).orElseThrow();
        Post post = postRepository.findById(postId).orElseThrow();
        return postLikeRepository.existsByUserAndPost(user, post);
    }

    @Transactional(readOnly = true)
    public long countLikes(Long postId) {
        Post post = postRepository.findById(postId).orElseThrow();
        return postLikeRepository.countByPost(post);
    }
}
