package br.ufg.collabdocs.document;

import br.ufg.collabdocs.document.dto.CreateDocumentRequest;
import br.ufg.collabdocs.document.dto.DocumentResponse;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
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

    public void updateContent(UUID id, String content, int version) {
        docs.findById(id).ifPresent(doc -> {
            doc.setContent(content);
            doc.setVersion(version);
            doc.setUpdatedAt(LocalDateTime.now());
            docs.save(doc);
        });
    }

    private DocumentResponse toResponse(Document d) {
        return new DocumentResponse(
                d.getId(), d.getTitle(), d.getOwnerId(), d.getContent(),
                d.getVersion(), d.getCreatedAt(), d.getUpdatedAt());
    }
}
