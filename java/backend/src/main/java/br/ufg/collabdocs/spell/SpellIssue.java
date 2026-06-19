package br.ufg.collabdocs.spell;

import jakarta.persistence.*;
import java.time.LocalDateTime;
import java.util.UUID;

@Entity
@Table(name = "spell_issues")
public class SpellIssue {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "doc_id", nullable = false)
    private UUID docId;

    @Column(nullable = false)
    private String word;

    private int position;
    private String suggestion;

    @Column(name = "checked_at")
    private LocalDateTime checkedAt = LocalDateTime.now();

    public Long getId()                { return id; }
    public UUID getDocId()             { return docId; }
    public void setDocId(UUID v)       { docId = v; }
    public String getWord()            { return word; }
    public void setWord(String v)      { word = v; }
    public int getPosition()           { return position; }
    public void setPosition(int v)     { position = v; }
    public String getSuggestion()      { return suggestion; }
    public void setSuggestion(String v){ suggestion = v; }
    public LocalDateTime getCheckedAt(){ return checkedAt; }
}
