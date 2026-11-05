package com.example.board.user.controller;

import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import com.example.board.notification.service.NotificationService;
import com.example.board.user.dto.TimelineItemDto;
import com.example.board.user.dto.UserJoinDto;
import com.example.board.user.entity.User;
import com.example.board.user.repository.UserRepository;
import com.example.board.user.service.TimelineService;
import com.example.board.user.service.UserService;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.stereotype.Controller;
import org.springframework.ui.Model;
import org.springframework.validation.BindingResult;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@Controller
@RequiredArgsConstructor
public class UserController {

    private final UserService userService;
    private final UserRepository userRepository;
    private final TimelineService timelineService;
    private final NotificationService notificationService;

    // 회원가입 폼
    @GetMapping("/signup")
    public String signupForm() {
        return "user/signup";
    }

    // 회원가입 처리
    @PostMapping("/signup")
    public String signup(@Valid @ModelAttribute UserJoinDto userJoinDto,
                         BindingResult bindingResult,
                         Model model) {
        if (bindingResult.hasErrors()) {
            return "user/signup"; // 검증 실패 시 다시 폼
        }

        try {
            userService.signup(userJoinDto);
            return "redirect:/login";
        } catch (IllegalArgumentException e) {
            model.addAttribute("error", e.getMessage());
            return "user/signup";
        }
    }

    @GetMapping("/login")
    public String loginForm() {
        return "user/login"; // login.html 뷰
    }

    @GetMapping("/mypage")
    public String myPage(@AuthenticationPrincipal UserDetails principal, Model model) {
        if (principal == null) {
            return "redirect:/login"; // 로그인 안 했으면 로그인 페이지로
        }

        // 마이페이지 진입 시 모든 알림을 읽음 처리
        notificationService.markAllAsRead(principal.getUsername());

        User user = userRepository.findByUsername(principal.getUsername()).orElseThrow();
        List<TimelineItemDto> timeline = timelineService.getUserTimeline(user.getUsername());

        model.addAttribute("timeline", timeline);
        model.addAttribute("currentUserNickname", user.getNickname());
        return "user/mypage";
    }
}
