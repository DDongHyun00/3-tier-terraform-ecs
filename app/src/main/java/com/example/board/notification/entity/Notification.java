package com.example.board.notification.entity;

import jakarta.persistence.*;
import lombok.Getter;
import lombok.NoArgsConstructor;
import com.example.board.board.entity.Post;
import com.example.board.common.entity.BaseTimeEntity;
import com.example.board.user.entity.User;
import org.hibernate.annotations.OnDelete;
import org.hibernate.annotations.OnDeleteAction;

@Entity
@Getter
@NoArgsConstructor
public class Notification extends BaseTimeEntity {

    @Id @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne(fetch = FetchType.LAZY, optional = false)
    private User targetUser;

    private String message;

    private boolean read; // 읽음 여부

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "post_id", nullable = false)
    @OnDelete(action = OnDeleteAction.CASCADE)
    private Post post;

    public Notification(User targetUser, String message, boolean read, Post post) {
        this.targetUser = targetUser;
        this.message = message;
        this.read = read;
        this.post = post;
    }

    public void markAsRead() {
        this.read = true;
    }
}