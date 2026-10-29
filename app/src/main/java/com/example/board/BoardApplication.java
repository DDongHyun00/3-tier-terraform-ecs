package com.example.board;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.data.jpa.repository.config.EnableJpaAuditing;

/**
 * 게시판 앱 진입점. 운영에서는 ECS Fargate 태스크가 {@code java -jar app.jar}로 띄운다(app/Dockerfile).
 * 빌드 캐시 mode=min 전환 뒤 코드 변경 빌드 시간을 재기 위해 주석을 바꿨다(#72).
 */
@SpringBootApplication
@EnableJpaAuditing
public class BoardApplication {

	public static void main(String[] args) {
		SpringApplication.run(BoardApplication.class, args);
	}

}
