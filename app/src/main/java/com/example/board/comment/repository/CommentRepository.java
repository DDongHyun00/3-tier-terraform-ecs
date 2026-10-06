package com.example.board.comment.repository;

import com.example.board.comment.entity.Comment;
import com.example.board.board.entity.Post;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;
import java.util.List;

public interface CommentRepository extends JpaRepository<Comment, Long> {
    @Query("SELECT c FROM Comment c JOIN FETCH c.user WHERE c.post.postId = :postId ORDER BY c.createdAt ASC")
    List<Comment> findByPostWithUser(@Param("postId") Long postId);


    @Query("SELECT COUNT(c) FROM Comment c WHERE c.createdAt BETWEEN :start AND :end")
    long countTodayComments(@Param("start") LocalDateTime start,
                            @Param("end") LocalDateTime end);

}
