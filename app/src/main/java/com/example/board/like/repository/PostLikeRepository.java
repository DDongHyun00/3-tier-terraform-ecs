package com.example.board.like.repository;

import com.example.board.board.entity.Post;
import com.example.board.like.entity.PostLike;
import com.example.board.user.entity.User;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Optional;

public interface PostLikeRepository extends JpaRepository<PostLike, Long> {
    boolean existsByUserAndPost(User user, Post post);
    long countByPost(Post post);
    Optional<PostLike> findByUserAndPost(User user, Post post);

    @Query("SELECT COUNT(l) FROM PostLike l WHERE l.createdAt BETWEEN :start AND :end")
    long countTodayLikes(@Param("start") LocalDateTime start,
                         @Param("end") LocalDateTime end);

    @Query("SELECT l.post.postId, COUNT(l) FROM PostLike l WHERE l.post IN :posts GROUP BY l.post.postId")
    List<Object[]> countByPostIn(@Param("posts") List<Post> posts);

}
