package com.example.board;

import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.context.annotation.Bean;
import org.testcontainers.postgresql.PostgreSQLContainer;

/**
 * 테스트용 PostgreSQL 컨테이너. 운영 DB(RDS PostgreSQL)와 같은 엔진으로 테스트한다.
 * {@link ServiceConnection}이 컨테이너의 접속 정보를 DataSource에 자동 연결한다.
 */
@TestConfiguration(proxyBeanMethods = false)
class TestcontainersConfiguration {

	@Bean
	@ServiceConnection
	PostgreSQLContainer postgresContainer() {
		return new PostgreSQLContainer("postgres:16");
	}

}
