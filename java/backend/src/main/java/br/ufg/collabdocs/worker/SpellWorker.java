package br.ufg.collabdocs.worker;

import br.ufg.collabdocs.config.RabbitMQConfig;
import br.ufg.collabdocs.operation.OpEvent;
import br.ufg.collabdocs.spell.SpellIssue;
import br.ufg.collabdocs.spell.SpellIssueRepository;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

import java.util.List;
import java.util.UUID;

// Runs in its own Spring-managed thread pool via @RabbitListener concurrency.
@Component
public class SpellWorker {

    private static final Logger log = LoggerFactory.getLogger(SpellWorker.class);

    // Common misspellings for demo purposes — replace with a real dictionary library.
    private static final List<String[]> DICTIONARY = List.of(
            new String[]{"teh",    "the"},
            new String[]{"adn",    "and"},
            new String[]{"recieve","receive"},
            new String[]{"occurence","occurrence"},
            new String[]{"seperate","separate"}
    );

    private final SpellIssueRepository issueRepository;

    public SpellWorker(SpellIssueRepository issueRepository) {
        this.issueRepository = issueRepository;
    }

    @RabbitListener(queues = RabbitMQConfig.Q_SPELL, concurrency = "2")
    public void onOperation(OpEvent event) {
        if (!"insert".equals(event.type()) || event.character() == null || !event.character().isBlank()) {
            return; // Only check after space/newline (word boundary)
        }
        // In a real implementation, buffer characters to form words.
        // Here we just log to demonstrate the worker is running.
        log.debug("spell-worker received op for doc={}", event.docId());
    }

    private void checkAndSave(String word, int pos, UUID docId) {
        for (var entry : DICTIONARY) {
            if (entry[0].equalsIgnoreCase(word)) {
                var issue = new SpellIssue();
                issue.setDocId(docId);
                issue.setWord(word);
                issue.setPosition(pos);
                issue.setSuggestion(entry[1]);
                issueRepository.save(issue);
                log.info("spell issue found: '{}' → '{}' in doc {}", word, entry[1], docId);
            }
        }
    }
}
