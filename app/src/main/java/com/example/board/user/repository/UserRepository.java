package com.example.board.user.repository;

import com.example.board.user.entity.User;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Optional;

public interface UserRepository extends JpaRepository<User, Long> {
    // username으로 유저 찾기 (로그인 시 필요)
    Optional<User> findByUsername(String username);

    // 닉네임 중복 체크 (회원가입 시 유용)
    boolean existsByNickname(String nickname);

    boolean existsByUsername(String username);
}
