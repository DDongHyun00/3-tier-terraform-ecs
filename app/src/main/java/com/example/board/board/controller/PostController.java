package com.example.board.board.controller;

import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import com.example.board.board.dto.PostRequestDto;
import com.example.board.board.dto.PostResponseDto;
import com.example.board.board.entity.Post;
import com.example.board.board.service.PostService;
import com.example.board.comment.service.CommentService;
import com.example.board.common.exception.ForbiddenException;
import com.example.board.like.service.PostLikeService;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.validation.BindingResult;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.multipart.MultipartFile;

import java.util.List;

@Controller
@RequiredArgsConstructor
@RequestMapping("/posts")
public class PostController {

    private final PostService postService;
    private final CommentService commentService;
    private final PostLikeService postLikeService;

    // 게시글 목록
    @GetMapping
    public String list(
            Model model,
            @RequestParam(value = "q", required = false) String q,
            @RequestParam(value = "sort", required = false, defaultValue = "createdAt") String sort,
            @RequestParam(value = "dir", required = false, defaultValue = "asc") String dir,
            @RequestParam(value = "size", required = false, defaultValue = "10") int size,
            Pageable pageable
    ) {
        Sort.Direction direction = "asc".equalsIgnoreCase(dir) ? Sort.Direction.ASC : Sort.Direction.DESC;
        Pageable pageReq = PageRequest.of(pageable.getPageNumber(), size, Sort.by(direction, sort).and(Sort.by(Sort.Direction.ASC, "postId")));

        Page<PostResponseDto> page = postService.getPostList(q, pageReq);

        model.addAttribute("q", q);
        model.addAttribute("sort", sort);
        model.addAttribute("dir", dir);
        model.addAttribute("size", size);
        model.addAttribute("posts", page);

        return "board/list";
    }

    // 상세 진입 (조회수 +1)
    @GetMapping("/{id}")
    public String detail(@PathVariable Long id,
                         @AuthenticationPrincipal UserDetails principal,
                         Model model) {
        Post post = postService.viewPost(id);
        addCommonAttributes(model, post, principal);
        return "board/detail";
    }

    // redirect 복귀 (조회수 증가 없음)
    @GetMapping("/{id}/view")
    public String detailNoIncrement(@PathVariable Long id,
                                    @AuthenticationPrincipal UserDetails principal,
                                    Model model) {
        Post post = postService.getPost(id);
        addCommonAttributes(model, post, principal);
        return "board/detail";
    }

    // 공통 attribute 설정 메서드
    private void addCommonAttributes(Model model, Post post, UserDetails principal) {
        model.addAttribute("post", post);
        String currentUsername = (principal != null) ? principal.getUsername() : null;
        model.addAttribute("comments", commentService.getComments(post.getPostId(), currentUsername));
        boolean ownedByMe = principal != null && post.getUser().getUsername().equals(currentUsername);
        model.addAttribute("ownedByMe", ownedByMe);

        if (principal != null) {
            boolean likedByMe = postLikeService.isLikedByUser(currentUsername, post.getPostId());
            model.addAttribute("postLikedByMe", likedByMe);
        } else {
            model.addAttribute("postLikedByMe", false);
        }
        model.addAttribute("postLikeCount", postLikeService.countLikes(post.getPostId()));
    }

    // 게시글 작성
    @GetMapping("/new")
    public String newForm(Model model) {
        model.addAttribute("postRequestDto", new PostRequestDto());
        return "board/form";
    }

    @PostMapping
    public String create(@AuthenticationPrincipal UserDetails principal,
                         @Valid @ModelAttribute PostRequestDto dto,
                         BindingResult bindingResult,
                         @RequestParam(value = "files", required = false) List<MultipartFile> files,
                         Model model) {
        if (bindingResult.hasErrors()) {
            model.addAttribute("postRequestDto", dto);
            return "board/form";
        }
        postService.createPost(principal.getUsername(), dto, files);
        return "redirect:/posts";
    }

    // 게시글 수정
    @PostMapping("/{id}/edit")
    public String update(@PathVariable Long id,
                         @AuthenticationPrincipal UserDetails principal,
                         @Valid @ModelAttribute PostRequestDto dto,
                         BindingResult bindingResult,
                         @RequestParam(value = "files", required = false) List<MultipartFile> files,
                         Model model) {
        if (bindingResult.hasErrors()) {
            model.addAttribute("postRequestDto", dto);
            model.addAttribute("postId", id);
            return "board/form";
        }
        postService.updatePost(id, principal.getUsername(), dto, files);
        return "redirect:/posts/" + id + "/view";
    }

    @GetMapping("/{id}/editForm")
    public String editForm(@PathVariable Long id,
                           @AuthenticationPrincipal UserDetails principal,
                           Model model) {
        Post post = postService.getPost(id); // 조회수 증가 없음
        if (!post.getUser().getUsername().equals(principal.getUsername())) {
            throw new ForbiddenException("작성자 본인만 수정할 수 있습니다.");
        }

        PostRequestDto dto = new PostRequestDto();
        dto.setTitle(post.getTitle());
        dto.setContent(post.getContent());

        model.addAttribute("postRequestDto", dto);
        model.addAttribute("postId", id);
        return "board/form";
    }

    // 게시글 삭제
    @PostMapping("/{id}/delete")
    public String delete(@PathVariable Long id,
                         @AuthenticationPrincipal UserDetails principal) {
        postService.delete(id, principal.getUsername());
        return "redirect:/posts";
    }
}
