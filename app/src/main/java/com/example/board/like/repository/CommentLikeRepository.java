package com.example.board.like.repository;

import com.example.board.comment.entity.Comment;
import com.example.board.like.entity.CommentLike;
import com.example.board.user.entity.User;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

public interface CommentLikeRepository extends JpaRepository<CommentLike, Long> {
    boolean existsByUserAndComment(User user, Comment comment);
    long countByComment(Comment comment);
    Optional<CommentLike> findByUserAndComment(User user, Comment comment);

    @Query("SELECT cl.comment.commentId, COUNT(cl) " +
            "FROM CommentLike cl " +
            "WHERE cl.comment.commentId IN :ids " +
            "GROUP BY cl.comment.commentId")
    List<Object[]> countByCommentIds(@Param("ids") List<Long> ids);

    @Query("SELECT cl.comment.commentId FROM CommentLike cl " +
            "WHERE cl.user.username = :username AND cl.comment.commentId IN :ids")
    List<Long> findLikedCommentIds(@Param("username") String username,
                                   @Param("ids") List<Long> ids);
}
