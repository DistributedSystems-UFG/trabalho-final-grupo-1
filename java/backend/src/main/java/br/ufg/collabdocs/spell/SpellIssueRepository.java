package br.ufg.collabdocs.spell;

import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;
import java.util.UUID;

public interface SpellIssueRepository extends JpaRepository<SpellIssue, Long> {
    List<SpellIssue> findByDocIdOrderByCheckedAtDesc(UUID docId);
}
