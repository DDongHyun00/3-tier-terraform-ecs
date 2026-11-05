package com.example.board.common.exception;

import java.util.Optional;

import com.example.board.board.controller.PostController;
import com.example.board.board.entity.Post;
import com.example.board.board.repository.PostRepository;
import com.example.board.board.service.PostService;
import com.example.board.comment.controller.CommentController;
import com.example.board.comment.entity.Comment;
import com.example.board.comment.repository.CommentRepository;
import com.example.board.comment.service.CommentService;
import com.example.board.file.repository.FileRepository;
import com.example.board.file.storage.FileStorage;
import com.example.board.like.repository.PostLikeRepository;
import com.example.board.like.service.CommentLikeService;
import com.example.board.like.service.PostLikeService;
import com.example.board.notification.service.NotificationService;
import com.example.board.user.entity.User;
import com.example.board.user.repository.UserRepository;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.web.method.annotation.AuthenticationPrincipalArgumentResolver;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.setup.MockMvcBuilders;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.forwardedUrl;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 남의 글·댓글을 수정·삭제하려 하면 500이 아니라 403을 낸다. 사용자 요청 오류가 5xx 비율 알람을 울리지 않게 하려는 것이다.
 * 컨트롤러·서비스·GlobalExceptionHandler는 실제 코드, 저장소만 목으로 바꿔 DB·컨테이너 없이 돌린다.
 */
class ForbiddenTests {

	private final PostRepository postRepository = mock(PostRepository.class);
	private final CommentRepository commentRepository = mock(CommentRepository.class);
	private final UserRepository userRepository = mock(UserRepository.class);

	private MockMvc mvc;

	@BeforeEach
	void setUp() {
		PostService postService = new PostService(postRepository, userRepository,
				mock(PostLikeRepository.class), mock(FileRepository.class), mock(FileStorage.class));
		CommentService commentService = new CommentService(commentRepository, postRepository, userRepository,
				mock(CommentLikeService.class), mock(NotificationService.class));

		mvc = MockMvcBuilders
				.standaloneSetup(
						new PostController(postService, commentService, mock(PostLikeService.class)),
						new CommentController(commentService))
				.setControllerAdvice(new GlobalExceptionHandler())
				.setCustomArgumentResolvers(new AuthenticationPrincipalArgumentResolver())
				.build();

		// 로그인한 사람은 user2, 글·댓글 작성자는 user1
		UserDetails principal = org.springframework.security.core.userdetails.User
				.withUsername("user2").password("x").roles("USER").build();
		SecurityContextHolder.getContext().setAuthentication(
				new UsernamePasswordAuthenticationToken(principal, null, principal.getAuthorities()));

		User owner = new User();
		owner.setUsername("user1");
		Post post = Post.builder().postId(1L).user(owner).title("t").content("c").build();
		when(postRepository.findById(1L)).thenReturn(Optional.of(post));
		Comment comment = Comment.builder().commentId(10L).post(post).user(owner).content("c").build();
		when(commentRepository.findById(10L)).thenReturn(Optional.of(comment));
	}

	@AfterEach
	void clearContext() {
		SecurityContextHolder.clearContext();
	}

	@Test
	void nonOwnerEditFormReturns403Page() throws Exception {
		mvc.perform(get("/posts/1/editForm"))
				.andExpect(status().isForbidden())
				.andExpect(forwardedUrl("error/403"));
	}

	@Test
	void nonOwnerPostDeleteReturns403AndKeepsPost() throws Exception {
		mvc.perform(post("/posts/1/delete"))
				.andExpect(status().isForbidden());

		verify(postRepository, never()).delete(any());
	}

	@Test
	void nonOwnerCommentEditReturns403JsonForAjax() throws Exception {
		mvc.perform(put("/posts/1/comments/10")
						.header("X-Requested-With", "XMLHttpRequest")
						.contentType(MediaType.APPLICATION_JSON)
						.content("{\"content\":\"hacked\"}"))
				.andExpect(status().isForbidden())
				.andExpect(jsonPath("$.status").value(403))
				.andExpect(jsonPath("$.message").value("본인 댓글만 수정할 수 있습니다."));
	}
}
