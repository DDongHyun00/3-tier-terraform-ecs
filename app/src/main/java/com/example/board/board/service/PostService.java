package com.example.board.board.service;

import lombok.RequiredArgsConstructor;
import com.example.board.board.dto.PostRequestDto;
import com.example.board.board.dto.PostResponseDto;
import com.example.board.board.entity.Post;
import com.example.board.board.repository.PostRepository;
import com.example.board.file.entity.FileEntity;
import com.example.board.file.repository.FileRepository;
import com.example.board.file.storage.FileStorage;
import com.example.board.like.repository.PostLikeRepository;
import com.example.board.user.entity.User;
import com.example.board.user.repository.UserRepository;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.StringUtils;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.util.List;

@Service
@RequiredArgsConstructor
public class PostService {

    private final PostRepository postRepository;
    private final UserRepository userRepository;
    private final PostLikeRepository postLikeRepository;
    private final FileRepository fileRepository;
    private final FileStorage fileStorage;

    @Transactional(readOnly = true)
    public Page<PostResponseDto> getPostList(String keyword, Pageable pageable) {
        Page<Post> posts = (keyword == null || keyword.isBlank())
                ? postRepository.findAllWithUser(pageable)
                : postRepository.search(keyword.trim(), pageable);

        return posts.map(post -> PostResponseDto.builder()
                .postId(post.getPostId())
                .title(post.getTitle())
                .content(post.getContent())
                .author(post.getUser().getNickname())
                .viewCount(post.getViewCount())
                .likeCount(post.getLikes().size()) // 또는 likeRepository.countByPost(post)
                .createdAt(post.getCreatedAt())
                .updatedAt(post.getUpdatedAt())
                .hasFiles(!post.getFiles().isEmpty())
                .build()
        );
    }
//    상세 조회 시 조회수 +1
    @Transactional
    public Post viewPost(Long id) {
        Post post = postRepository.findById(id)
                .orElseThrow(() -> new IllegalArgumentException("게시글을 찾을 수 없습니다."));
        post.setViewCount(post.getViewCount() + 1);
        return post;
    }

//    조회수 증가 없는 단순 조회
    @Transactional(readOnly = true)
    public Post getPost(Long id) {
        return postRepository.findById(id)
                .orElseThrow(() -> new IllegalArgumentException("게시글을 찾을 수 없습니다."));
    }

    @Transactional
    public Long createPost(String username, PostRequestDto dto, List<MultipartFile> files) {
        User writer = userRepository.findByUsername(username)
                .orElseThrow(() -> new IllegalArgumentException("작성자를 찾을 수 없습니다."));
        if (dto == null || !StringUtils.hasText(dto.getTitle()) || !StringUtils.hasText(dto.getContent())) {
            throw new IllegalArgumentException("제목과 내용은 비어 있을 수 없습니다.");
        }
        Post post = Post.builder()
                .user(writer)
                .title(dto.getTitle())
                .content(dto.getContent())
                .build();
        postRepository.save(post);

        saveFiles(post, files);
        return post.getPostId();
    }

    @Transactional
    public void updatePost(Long id, String username, PostRequestDto dto, List<MultipartFile> files) {
        Post post = postRepository.findById(id)
                .orElseThrow(() -> new IllegalArgumentException("게시글을 찾을 수 없습니다."));
        if (!post.getUser().getUsername().equals(username)) {
            throw new SecurityException("작성자 본인만 수정할 수 있습니다.");
        }
        if (dto == null || !StringUtils.hasText(dto.getTitle()) || !StringUtils.hasText(dto.getContent())) {
            throw new IllegalArgumentException("제목과 내용은 비어 있을 수 없습니다.");
        }
        post.update(dto.getTitle().trim(), dto.getContent().trim());
        saveFiles(post, files);
    }

    @Transactional
    public void delete(Long id, String username) {
        Post post = postRepository.findById(id)
                .orElseThrow(() -> new IllegalArgumentException("게시글을 찾을 수 없습니다."));
        if (!post.getUser().getUsername().equals(username)) {
            throw new SecurityException("작성자 본인만 삭제할 수 있습니다.");
        }
        postRepository.delete(post);
    }

    private void saveFiles(Post post, List<MultipartFile> files) {
        for (MultipartFile file : files) {
            if (!file.isEmpty()) {
                try {
                    String savedName = fileStorage.store(file);

                    FileEntity fe = FileEntity.builder()
                            .post(post)
                            .originalName(file.getOriginalFilename())
                            .savedName(savedName)
                            .build();
                    fileRepository.save(fe);
                } catch (IOException e) {
                    throw new RuntimeException("파일 저장 실패", e);
                }
            }
        }
    }
}
