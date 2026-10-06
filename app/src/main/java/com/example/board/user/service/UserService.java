package com.example.board.user.service;

import lombok.RequiredArgsConstructor;
import com.example.board.user.dto.UserJoinDto;
import com.example.board.user.entity.User;
import com.example.board.user.repository.UserRepository;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

@Service
@RequiredArgsConstructor
public class UserService {

    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;

    @Transactional
    public User signup(UserJoinDto dto) {
        if (userRepository.existsByUsername(dto.getUsername())) {
            throw new IllegalArgumentException("이미 사용 중인 아이디입니다.");
        }
        if (userRepository.existsByNickname(dto.getNickname())) {
            throw new IllegalArgumentException("이미 사용 중인 닉네임입니다.");
        }
        if (!StringUtils.hasText(dto.getPassword())) {
            throw new IllegalArgumentException("비밀번호는 비어 있을 수 없습니다.");
        }

        User user = User.builder()
                .username(dto.getUsername().trim())
                .password(passwordEncoder.encode(dto.getPassword()))
                .nickname(dto.getNickname().trim())
                .role("USER")
                .build();

        return userRepository.save(user);
    }

}
