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

    // 전체 목록 (작성자 fetch join)
    @Query(value = "SELECT p FROM Post p JOIN FETCH p.user",
           countQuery = "SELECT COUNT(p) FROM Post p")
    Page<Post> findAllWithUser(Pageable pageable);

    // 작성자 닉네임까지 포함한 통합 검색. kw는 null이 아니어야 한다.
    // (PostgreSQL은 ":kw IS NULL"처럼 타입을 알 수 없는 null 파라미터를 bytea로 추론해 lower() 호출이 실패한다)
    @Query(value = """
        SELECT p
        FROM Post p
        JOIN FETCH p.user u
        WHERE lower(p.title) LIKE lower(concat('%', :kw, '%'))
           OR lower(p.content) LIKE lower(concat('%', :kw, '%'))
           OR lower(u.nickname) LIKE lower(concat('%', :kw, '%'))
        """,
        countQuery = """
        SELECT COUNT(p)
        FROM Post p
        JOIN p.user u
        WHERE lower(p.title) LIKE lower(concat('%', :kw, '%'))
           OR lower(p.content) LIKE lower(concat('%', :kw, '%'))
           OR lower(u.nickname) LIKE lower(concat('%', :kw, '%'))
        """)
    Page<Post> search(@Param("kw") String keyword, Pageable pageable);

    @Query("SELECT COUNT(p) FROM Post p WHERE p.createdAt BETWEEN :start AND :end")
    long countTodayPosts(@Param("start") LocalDateTime start,
                         @Param("end") LocalDateTime end);
}
