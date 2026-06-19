package br.ufg.collabdocs.operation;

public record OpEvent(
        String docId,
        String userId,
        int version,
        String type,
        int pos,
        String character) {}
