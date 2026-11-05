package com.example.board;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.data.jpa.repository.config.EnableJpaAuditing;

/**
 * 게시판 앱 진입점. 운영에서는 ECS(EC2 용량 공급자) 태스크가 {@code java -jar app.jar}로 띄운다(app/Dockerfile).
 */
@SpringBootApplication
@EnableJpaAuditing
public class BoardApplication {

	public static void main(String[] args) {
		SpringApplication.run(BoardApplication.class, args);
	}

}
