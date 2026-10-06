package com.example.board.user.dto;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import lombok.Getter;
import lombok.Setter;

@Getter @Setter
public class UserJoinDto {
    @NotBlank(message = "아이디를 입력해 주세요.")
    @Size(min = 4, max = 15, message = "아이디는 4~15자여야 합니다.")
    private String username;

    @NotBlank(message = "닉네임을 입력해 주세요.")
    @Size(min = 2, max = 10, message = "닉네임은 2~10자여야 합니다.")
    private String nickname;

    @NotBlank(message = "비밀번호를 입력해 주세요.")
    @Size(min = 4, max = 50, message = "비밀번호는 4~50자여야 합니다.")
    private String password;
}
