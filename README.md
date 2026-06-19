# CollabDocs

Editor de documentos colaborativo em tempo real. Múltiplos usuários podem editar o mesmo documento simultaneamente e ver as alterações do outro em tempo real.

Projeto desenvolvido para a disciplina **Sistemas Concorrentes e Distribuídos — UFG 2026.1**.

---

## Tecnologias

| Camada | Stack |
|--------|-------|
| Frontend | React 18 + TypeScript + Vite + nginx |
| Serviço de tempo real | Go 1.22 + Gin + gorilla/websocket |
| Backend / API | Java 21 + Spring Boot 3.3 + Spring AMQP |
| Mensageria | RabbitMQ 3.13 |
| Banco de dados | PostgreSQL 16 |

---

## Rodando localmente

### Pré-requisitos

- [Docker](https://docs.docker.com/get-docker/) e Docker Compose instalados
- Portas **4000**, **8080**, **8081**, **5432** e **15672** disponíveis no host

### 1. Clone o repositório

```bash
git clone <url-do-repositório>
cd collab-docs
```

### 2. Suba todos os serviços

```bash
docker compose -f infra/docker-compose.yml up -d --build
```

O primeiro build leva alguns minutos (Maven baixa dependências Java, npm instala pacotes). Os próximos sobem em segundos.

### 3. Aguarde os serviços ficarem prontos

```bash
docker compose -f infra/docker-compose.yml ps
```

Todos devem estar com status `running`. O Java Backend pode levar ~20s para iniciar após o PostgreSQL ficar healthy.

### 4. Acesse a aplicação

| Serviço | URL |
|---------|-----|
| Aplicação (frontend) | http://localhost:4000 |
| RabbitMQ Management | http://localhost:15672 (user: `collabdocs` / senha: `collabdocs`) |
| Java Backend (direto) | http://localhost:8081 |
| Go Collab Service (direto) | http://localhost:8080 |

### 5. Login

Um usuário admin é criado automaticamente:

| Campo | Valor |
|-------|-------|
| E-mail | `admin@collabdocs.dev` |
| Senha | `admin123` |

Para testar a colaboração com dois usuários, use a opção **Cadastre-se** na tela de login para criar uma segunda conta.

---

## Testando a colaboração em tempo real

1. Abra http://localhost:4000 em **dois navegadores diferentes** (ou um normal + um anônimo/incógnito)
2. Faça login com contas diferentes em cada janela
3. Crie um documento em uma das janelas — ele aparecerá na sidebar de ambas
4. Abra o mesmo documento nos dois navegadores
5. Digite em um e observe as alterações aparecendo no outro em tempo real

> Usar dois navegadores diferentes (ou um em modo incógnito) é necessário porque o `localStorage` é compartilhado entre abas do mesmo navegador.

---

## Parando os serviços

```bash
# Para os containers mas mantém os dados
docker compose -f infra/docker-compose.yml down

# Para e remove todos os dados (volumes)
docker compose -f infra/docker-compose.yml down -v
```

---

## Estrutura do projeto

```
collab-docs/
├── docs/
│   ├── architecture.md       # Arquitetura detalhada do sistema
│   └── development-status.md # Relatório de desenvolvimento
├── frontend/                 # React SPA + nginx
├── go/
│   └── collab-service/       # Serviço Go (proxy + WebSocket hub)
├── java/
│   └── backend/              # Spring Boot (auth, docs, workers AMQP)
├── infra/
│   ├── docker-compose.yml    # Orquestração de todos os serviços
│   └── postgres/
│       ├── init.sql          # Schema do banco
│       └── seed.sql          # Dados iniciais (usuário admin)
└── Makefile
```

---

## Documentação

- [Arquitetura do sistema](docs/architecture.md)
- [Relatório de desenvolvimento](docs/development-status.md)
