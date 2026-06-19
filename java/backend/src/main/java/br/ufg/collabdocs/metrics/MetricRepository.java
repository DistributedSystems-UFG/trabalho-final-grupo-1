package br.ufg.collabdocs.metrics;

import org.springframework.data.jpa.repository.JpaRepository;
import java.util.UUID;

public interface MetricRepository extends JpaRepository<Metric, UUID> {}
