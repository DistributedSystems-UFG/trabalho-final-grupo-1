package br.ufg.collabdocs.operation;

import br.ufg.collabdocs.config.RabbitMQConfig;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

@Component
public class OperationConsumer {

    private static final Logger log = LoggerFactory.getLogger(OperationConsumer.class);

    private final OperationRepository repository;

    public OperationConsumer(OperationRepository repository) {
        this.repository = repository;
    }

    @RabbitListener(queues = RabbitMQConfig.Q_PERSIST)
    public void onOperation(OpEvent event) {
        try {
            repository.save(Operation.from(event));
            log.debug("persisted op doc={} v={} type={}", event.docId(), event.version(), event.type());
        } catch (Exception e) {
            log.error("failed to persist op: {}", e.getMessage());
            throw e; // re-queue on failure
        }
    }
}
