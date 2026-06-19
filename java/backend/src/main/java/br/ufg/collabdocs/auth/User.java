package br.ufg.collabdocs.auth;

import jakarta.persistence.*;
import java.time.LocalDateTime;
import java.util.UUID;

@Entity
@Table(name = "users")
public class User {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(unique = true, nullable = false)
    private String email;

    @Column(nullable = false)
    private String name;

    @Column(name = "password_hash", nullable = false)
    private String passwordHash;

    @Column(name = "created_at")
    private LocalDateTime createdAt = LocalDateTime.now();

    public UUID getId()              { return id; }
    public String getEmail()         { return email; }
    public void setEmail(String v)   { email = v; }
    public String getName()          { return name; }
    public void setName(String v)    { name = v; }
    public String getPasswordHash()  { return passwordHash; }
    public void setPasswordHash(String v) { passwordHash = v; }
}
