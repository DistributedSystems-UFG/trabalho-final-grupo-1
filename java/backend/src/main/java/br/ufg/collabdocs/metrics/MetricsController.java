package br.ufg.collabdocs.metrics;

import org.springframework.web.bind.annotation.*;

import java.util.UUID;

@RestController
@RequestMapping("/metrics")
public class MetricsController {

    private final MetricRepository repository;

    public MetricsController(MetricRepository repository) {
        this.repository = repository;
    }

    @GetMapping("/{docId}")
    public Metric getMetrics(@PathVariable UUID docId) {
        return repository.findById(docId).orElseGet(() -> {
            var empty = new Metric();
            empty.setDocId(docId);
            return empty;
        });
    }
}
