package com.example.board.config;

import java.util.Optional;

import com.example.board.user.entity.User;
import com.example.board.user.repository.UserRepository;
import org.junit.jupiter.api.Test;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.when;

/**
 * 운영은 ADMIN_PASSWORD로 시드 admin 비밀번호(공개 레포의 1111)를 덮어쓴다. 비어 있으면 아무것도 하지 않는다.
 * DB·컨테이너 없이 저장소를 목으로 바꿔 돌린다.
 */
class AdminPasswordInitializerTests {

	private final UserRepository userRepository = mock(UserRepository.class);
	private final PasswordEncoder passwordEncoder = new BCryptPasswordEncoder(4);

	private User seededAdmin() {
		User admin = new User();
		admin.setUsername("admin");
		admin.setPassword(passwordEncoder.encode("1111"));
		admin.setRole("ADMIN");
		return admin;
	}

	@Test
	void setsEncodedPasswordWhenGiven() {
		User admin = seededAdmin();
		when(userRepository.findByUsername("admin")).thenReturn(Optional.of(admin));

		new AdminPasswordInitializer(userRepository, passwordEncoder, "s3cret-from-secrets-manager").run(null);

		assertThat(passwordEncoder.matches("s3cret-from-secrets-manager", admin.getPassword())).isTrue();
		assertThat(passwordEncoder.matches("1111", admin.getPassword())).isFalse();
		verify(userRepository).save(admin);
	}

	@Test
	void doesNothingWhenBlank() {
		new AdminPasswordInitializer(userRepository, passwordEncoder, "").run(null);
		new AdminPasswordInitializer(userRepository, passwordEncoder, "   ").run(null);

		verifyNoInteractions(userRepository);
	}

	@Test
	void skipsSaveWhenPasswordAlreadyMatches() {
		User admin = seededAdmin();
		admin.setPassword(passwordEncoder.encode("already-set"));
		when(userRepository.findByUsername("admin")).thenReturn(Optional.of(admin));

		new AdminPasswordInitializer(userRepository, passwordEncoder, "already-set").run(null);

		verify(userRepository, never()).save(any());
	}

	@Test
	void doesNothingWhenAdminMissing() {
		when(userRepository.findByUsername("admin")).thenReturn(Optional.empty());

		new AdminPasswordInitializer(userRepository, passwordEncoder, "s3cret").run(null);

		verify(userRepository, never()).save(any());
	}
}
