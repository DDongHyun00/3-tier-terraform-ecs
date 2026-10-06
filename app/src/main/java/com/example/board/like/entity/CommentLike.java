package com.example.board.like.entity;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.NoArgsConstructor;
import com.example.board.comment.entity.Comment;
import com.example.board.user.entity.User;

@Entity
@Getter
@NoArgsConstructor
@Table(name = "comment_likes",
        uniqueConstraints = {@UniqueConstraint(columnNames = {"user_id", "comment_id"})})
public class CommentLike {

    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "user_id")
    private User user;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    @JoinColumn(name = "comment_id")
    private Comment comment;

    public CommentLike(User user, Comment comment) {
        this.user = user;
        this.comment = comment;
    }
}
