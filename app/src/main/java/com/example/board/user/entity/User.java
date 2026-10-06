package com.example.board.user.entity;

import jakarta.persistence.*;
import lombok.*;
import com.example.board.board.entity.Post;
import com.example.board.comment.entity.Comment;
import com.example.board.common.entity.BaseTimeEntity;
import com.example.board.like.entity.PostLike;

import java.util.ArrayList;
import java.util.List;

@Entity
@Table(name = "users")
@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class User extends BaseTimeEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long userId;

    @Column(nullable = false, unique = true, length = 15)
    private String username;   // 로그인 ID

    @Column(nullable = false)
    private String password;   // BCrypt 암호화된 비밀번호

    @Column(nullable = false, unique = true, length = 10)
    private String nickname;

    @Column(nullable = false)
    private String role;       // USER / ADMIN

//     연관 관계 매핑
    @OneToMany(mappedBy = "user", cascade = CascadeType.ALL, orphanRemoval = true)
    private List<Post> posts = new ArrayList<>();

    @OneToMany(mappedBy = "user", cascade = CascadeType.ALL, orphanRemoval = true)
    private List<Comment> comments = new ArrayList<>();
    // 좋아요 (PostLike)
    @OneToMany(mappedBy = "user", cascade = CascadeType.ALL, orphanRemoval = true)
    private List<PostLike> postLikes = new ArrayList<>();
}