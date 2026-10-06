package com.example.board.like.entity;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.NoArgsConstructor;
import com.example.board.board.entity.Post;
import com.example.board.common.entity.BaseTimeEntity;
import com.example.board.user.entity.User;

@Entity
@Getter
@NoArgsConstructor
@Table(name = "post_likes",
        uniqueConstraints = {@UniqueConstraint(columnNames = {"user_id", "post_id"})})
public class PostLike extends BaseTimeEntity {

    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "user_id")
    private User user;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "post_id")
    private Post post;

    public PostLike(User user, Post post) {
        this.user = user;
        this.post = post;
    }
}
