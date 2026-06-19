package br.ufg.collabdocs.document.dto;

import java.time.LocalDateTime;
import java.util.UUID;

public record DocumentResponse(
        UUID id,
        String title,
        UUID ownerId,
        String content,
        int version,
        LocalDateTime createdAt,
        LocalDateTime updatedAt) {}
