package br.ufg.collabdocs.operation;

import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;
import java.util.UUID;

public interface OperationRepository extends JpaRepository<Operation, UUID> {
    List<Operation> findByDocIdOrderByServerVersionAsc(UUID docId);
    long countByDocId(UUID docId);
}
