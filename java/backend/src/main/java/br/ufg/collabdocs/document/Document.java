package br.ufg.collabdocs.document;

import jakarta.persistence.*;
import java.time.LocalDateTime;
import java.util.UUID;

@Entity
@Table(name = "documents")
public class Document {

    @Id
    @GeneratedValue(strategy = GenerationType.UUID)
    private UUID id;

    @Column(nullable = false)
    private String title;

    @Column(name = "owner_id")
    private UUID ownerId;

    @Column(columnDefinition = "TEXT")
    private String content = "";

    private int version = 0;

    @Column(name = "created_at")
    private LocalDateTime createdAt = LocalDateTime.now();

    @Column(name = "updated_at")
    private LocalDateTime updatedAt = LocalDateTime.now();

    public UUID getId()                  { return id; }
    public String getTitle()             { return title; }
    public void setTitle(String v)       { title = v; }
    public UUID getOwnerId()             { return ownerId; }
    public void setOwnerId(UUID v)       { ownerId = v; }
    public String getContent()           { return content; }
    public void setContent(String v)     { content = v; }
    public int getVersion()              { return version; }
    public void setVersion(int v)        { version = v; }
    public LocalDateTime getCreatedAt()  { return createdAt; }
    public LocalDateTime getUpdatedAt()  { return updatedAt; }
    public void setUpdatedAt(LocalDateTime v) { updatedAt = v; }
}
