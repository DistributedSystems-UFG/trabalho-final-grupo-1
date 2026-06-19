package br.ufg.collabdocs.metrics;

import jakarta.persistence.*;
import java.time.LocalDateTime;
import java.util.UUID;

@Entity
@Table(name = "metrics")
public class Metric {

    @Id
    private UUID docId;

    @Column(name = "total_ops")
    private long totalOps = 0;

    @Column(name = "chars_inserted")
    private long charsInserted = 0;

    @Column(name = "chars_deleted")
    private long charsDeleted = 0;

    @Column(name = "last_activity")
    private LocalDateTime lastActivity = LocalDateTime.now();

    public UUID getDocId()                  { return docId; }
    public void setDocId(UUID v)            { docId = v; }
    public long getTotalOps()               { return totalOps; }
    public void setTotalOps(long v)         { totalOps = v; }
    public long getCharsInserted()          { return charsInserted; }
    public void setCharsInserted(long v)    { charsInserted = v; }
    public long getCharsDeleted()           { return charsDeleted; }
    public void setCharsDeleted(long v)     { charsDeleted = v; }
    public LocalDateTime getLastActivity()  { return lastActivity; }
    public void setLastActivity(LocalDateTime v) { lastActivity = v; }
}
