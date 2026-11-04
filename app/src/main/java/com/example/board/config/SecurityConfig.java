package com.example.board.config;

import lombok.RequiredArgsConstructor;
import com.example.board.user.service.CustomUserDetailsService;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.core.session.SessionRegistry;
import org.springframework.session.FindByIndexNameSessionRepository;
import org.springframework.session.Session;
import org.springframework.session.security.SpringSessionBackedSessionRegistry;

@Configuration
@EnableWebSecurity
@RequiredArgsConstructor
public class SecurityConfig {

    private final CustomUserDetailsService customUserDetailsService;
    private final FindByIndexNameSessionRepository<? extends Session> sessionRepository;

    @Bean
    public SecurityFilterChain securityFilterChain(HttpSecurity http) throws Exception {
        http
                .sessionManagement(session -> session
                        .sessionCreationPolicy(SessionCreationPolicy.IF_REQUIRED)
                        .invalidSessionUrl("/posts")  // 세션 만료 시 이동
                        .maximumSessions(1)                   // 동시에 1개의 세션만 허용
                        .sessionRegistry(sessionRegistry())   // 세션이 DB에 있으므로 레지스트리도 DB 기반으로 (태스크 간 공유)
                        .expiredUrl("/posts")         // 다른 로그인 발생 시 기존 세션 만료
                )

                .authorizeHttpRequests(auth -> auth
                        // 헬스체크 (비로그인, 302 없이 200이어야 함). ALB는 DB 상태와 무관한 /actuator/health/liveness를 본다
                        .requestMatchers("/actuator/health", "/actuator/health/**").permitAll()
                        // Prometheus 수집(#94). 관제 Prometheus는 피어링으로 태스크에 직접 붙어 X-Forwarded-For가 없다.
                        // ALB를 거친 요청에는 ALB가 항상 X-Forwarded-For를 붙이므로, 그 헤더가 있으면 거부한다.
                        // ALB 리스너 규칙(404)·앱 SG와 별개로 앱 스스로 막는 층이라, 배포 순서와 상관없이 공개되지 않는다
                        .requestMatchers(request -> "/actuator/prometheus".equals(request.getRequestURI())
                                && request.getHeader("X-Forwarded-For") == null).permitAll()
                        .requestMatchers("/actuator/prometheus", "/actuator/prometheus/**").denyAll()

                        // 전체 공개
                        .requestMatchers("/", "/login", "/signup",
                                "/css/**", "/js/**", "/images/**").permitAll()

                        // 게시글 목록/검색/상세는 공개
                        .requestMatchers(HttpMethod.GET, "/posts", "/posts/*").permitAll()

                        // 게시글 관련: 작성/수정/삭제 로그인 필요
                        .requestMatchers("/posts/new", "/posts/*/edit", "/posts/*/delete").authenticated()

                        // 댓글/좋아요 로그인 필요
                        .requestMatchers("/comments/**", "/likes/**").authenticated()

                        // 관리자 페이지
                        .requestMatchers("/admin/**").hasRole("ADMIN")

                        // 나머지 요청은 로그인 필요
                        .anyRequest().authenticated()
                )

                .formLogin(form -> form
                        .loginPage("/login")
                        .loginProcessingUrl("/process-login")
                        .defaultSuccessUrl("/posts", true)
                        .failureUrl("/login?error")
                        .permitAll()
                )

                .logout(logout -> logout
                        .logoutUrl("/logout")
                        .logoutSuccessUrl("/posts")
                        .invalidateHttpSession(true)      // 로그아웃 시 세션 무효화
                        .deleteCookies("JSESSIONID")
                        .permitAll()
                );


        return http.build();
    }

    @Bean
    public SessionRegistry sessionRegistry() {
        return new SpringSessionBackedSessionRegistry<>(sessionRepository);
    }

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }
}
