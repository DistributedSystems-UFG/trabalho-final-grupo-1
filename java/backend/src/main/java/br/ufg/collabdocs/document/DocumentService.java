package br.ufg.collabdocs.document;

import br.ufg.collabdocs.document.dto.CreateDocumentRequest;
import br.ufg.collabdocs.document.dto.DocumentResponse;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDateTime;
import java.util.List;
import java.util.UUID;

@Service
public class DocumentService {

    private final DocumentRepository docs;

    public DocumentService(DocumentRepository docs) {
        this.docs = docs;
    }

    public List<DocumentResponse> listAll() {
        return docs.findAllByOrderByUpdatedAtDesc().stream()
                .map(this::toResponse)
                .toList();
    }

    public DocumentResponse create(CreateDocumentRequest req, UUID ownerId) {
        var doc = new Document();
        doc.setTitle(req.title());
        doc.setOwnerId(ownerId);
        return toResponse(docs.save(doc));
    }

    public DocumentResponse getById(UUID id) {
        return docs.findById(id)
                .map(this::toResponse)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND));
    }

    public String getContent(UUID id) {
        return docs.findById(id)
                .map(Document::getContent)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND));
    }

    public void delete(UUID id, UUID requesterId) {
        var doc = docs.findById(id)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND));
        if (!doc.getOwnerId().equals(requesterId)) {
            throw new ResponseStatusException(HttpStatus.FORBIDDEN);
        }
        docs.delete(doc);
    }

    @Transactional
    public void updateContent(UUID id, String content, int version) {
        docs.findById(id).ifPresent(doc -> {
            doc.setContent(content);
            doc.setVersion(version);
            doc.setUpdatedAt(LocalDateTime.now());
            docs.save(doc);
        });
    }

    @Transactional
    public void applyOperation(UUID id, String type, int position, String character, int version) {
        docs.findById(id).ifPresent(doc -> {
            if (version <= doc.getVersion()) {
                return;
            }

            var content = doc.getContent() == null ? "" : doc.getContent();
            doc.setContent(apply(content, type, position, character));
            doc.setVersion(version);
            doc.setUpdatedAt(LocalDateTime.now());
            docs.save(doc);
        });
    }

    private String apply(String content, String type, int position, String character) {
        var codePoints = content.codePoints().toArray();
        var pos = Math.max(0, Math.min(position, codePoints.length));

        if ("insert".equals(type)) {
            if (character == null || character.isEmpty()) {
                return content;
            }
            var inserted = character.codePointAt(0);
            var next = new int[codePoints.length + 1];
            System.arraycopy(codePoints, 0, next, 0, pos);
            next[pos] = inserted;
            System.arraycopy(codePoints, pos, next, pos + 1, codePoints.length - pos);
            return new String(next, 0, next.length);
        }

        if ("delete".equals(type)) {
            if (pos >= codePoints.length) {
                return content;
            }
            var next = new int[codePoints.length - 1];
            System.arraycopy(codePoints, 0, next, 0, pos);
            System.arraycopy(codePoints, pos + 1, next, pos, codePoints.length - pos - 1);
            return new String(next, 0, next.length);
        }

        return content;
    }

    private DocumentResponse toResponse(Document d) {
        return new DocumentResponse(
                d.getId(), d.getTitle(), d.getOwnerId(), d.getContent(),
                d.getVersion(), d.getCreatedAt(), d.getUpdatedAt());
    }
}
