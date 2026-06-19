package br.ufg.collabdocs.auth.dto;

public record AuthResponse(String token, String userId, String name, String email) {}
