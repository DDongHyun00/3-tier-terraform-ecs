package com.example.board.config;

import com.example.board.user.repository.UserRepository;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;

/**
 * 시드(V2__seed.sql)의 admin 비밀번호를 ADMIN_PASSWORD 값으로 바꾼다.
 * 운영은 Secrets Manager에서 ADMIN_PASSWORD를 받아, 공개 레포에 있는 시드 비밀번호로는 관리자로 로그인할 수 없다.
 * 값이 비어 있으면(로컬) 아무것도 하지 않는다. 시드 파일은 Flyway 체크섬 때문에 고치지 않는다.
 */
@Slf4j
@Component
public class AdminPasswordInitializer implements ApplicationRunner {

    static final String ADMIN_USERNAME = "admin";

    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;
    private final String adminPassword;

    public AdminPasswordInitializer(UserRepository userRepository,
                                    PasswordEncoder passwordEncoder,
                                    @Value("${ADMIN_PASSWORD:}") String adminPassword) {
        this.userRepository = userRepository;
        this.passwordEncoder = passwordEncoder;
        this.adminPassword = adminPassword;
    }

    @Override
    @Transactional
    public void run(ApplicationArguments args) {
        if (!StringUtils.hasText(adminPassword)) {
            return;
        }
        userRepository.findByUsername(ADMIN_USERNAME).ifPresentOrElse(admin -> {
            // 태스크가 뜰 때마다 해시를 다시 쓰지 않도록, 이미 같은 비밀번호면 건너뛴다
            if (admin.getPassword() != null && passwordEncoder.matches(adminPassword, admin.getPassword())) {
                log.info("관리자 비밀번호가 이미 ADMIN_PASSWORD와 같아 바꾸지 않았습니다");
                return;
            }
            admin.setPassword(passwordEncoder.encode(adminPassword));
            userRepository.save(admin);
            log.info("관리자 비밀번호를 ADMIN_PASSWORD 값으로 설정했습니다");
        }, () -> log.info("관리자 계정이 없어 ADMIN_PASSWORD를 적용하지 않았습니다"));
    }
}
