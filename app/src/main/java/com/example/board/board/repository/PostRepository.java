package com.example.board.board.repository;

import com.example.board.board.dto.PostResponseDto;
import com.example.board.board.entity.Post;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;

public interface PostRepository extends JpaRepository<Post, Long> {

    // 작성자 닉네임까지 포함한 통합 검색
    @Query("""
        SELECT DISTINCT p
        FROM Post p
        JOIN FETCH p.user u
        WHERE (:kw IS NULL OR 
               lower(p.title) LIKE lower(concat('%', :kw, '%')) OR 
               lower(p.content) LIKE lower(concat('%', :kw, '%')) OR 
               lower(u.nickname) LIKE lower(concat('%', :kw, '%')))
        """)
    Page<Post> searchAll(@Param("kw") String keyword, Pageable pageable);

    @Query("SELECT COUNT(p) FROM Post p WHERE p.createdAt BETWEEN :start AND :end")
    long countTodayPosts(@Param("start") LocalDateTime start,
                         @Param("end") LocalDateTime end);
}
