package br.ufg.collabdocs.auth;

import br.ufg.collabdocs.auth.dto.AuthResponse;
import br.ufg.collabdocs.auth.dto.LoginRequest;
import br.ufg.collabdocs.auth.dto.RegisterRequest;
import org.springframework.http.HttpStatus;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

@Service
public class AuthService {

    private final UserRepository users;
    private final PasswordEncoder encoder;
    private final JwtService jwt;

    public AuthService(UserRepository users, PasswordEncoder encoder, JwtService jwt) {
        this.users = users;
        this.encoder = encoder;
        this.jwt = jwt;
    }

    public AuthResponse register(RegisterRequest req) {
        if (users.existsByEmail(req.email())) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "email already in use");
        }
        var user = new User();
        user.setEmail(req.email());
        user.setName(req.name());
        user.setPasswordHash(encoder.encode(req.password()));
        users.save(user);

        String token = jwt.generate(user.getId().toString(), user.getName(), user.getEmail());
        return new AuthResponse(token, user.getId().toString(), user.getName(), user.getEmail());
    }

    public AuthResponse login(LoginRequest req) {
        var user = users.findByEmail(req.email())
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.UNAUTHORIZED, "invalid credentials"));

        if (!encoder.matches(req.password(), user.getPasswordHash())) {
            throw new ResponseStatusException(HttpStatus.UNAUTHORIZED, "invalid credentials");
        }

        String token = jwt.generate(user.getId().toString(), user.getName(), user.getEmail());
        return new AuthResponse(token, user.getId().toString(), user.getName(), user.getEmail());
    }
}
