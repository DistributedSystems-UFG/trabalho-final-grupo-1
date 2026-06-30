# Arquitetura do Sistema — CollabDocs

## Visão Geral

CollabDocs é um editor de documentos colaborativo em tempo real construído como sistema distribuído concorrente. A arquitetura separa responsabilidades em serviços especializados que se comunicam via HTTP e mensageria assíncrona.

```
┌─────────────────────────────────────────────────────────────┐
│                        Browser                              │
│              React SPA  (localhost:4000)                    │
└────────────────────────┬────────────────────────────────────┘
                         │ HTTP / WebSocket
                         ▼
┌─────────────────────────────────────────────────────────────┐
│                  Nginx (reverse proxy)                      │
│  /api/*  →  go-collab:8080   |   /*  →  index.html (SPA)  │
└────────────────────────┬────────────────────────────────────┘
                         │
              ┌──────────┴──────────┐
              │                     │
              ▼                     ▼
   ┌──────────────────┐   ┌──────────────────────┐
   │  Go Collab Svc   │   │  Go Collab Svc       │
   │  (REST proxy +   │──▶│  Hub Manager         │
   │   JWT validate)  │   │  (WebSocket / OT)    │
   └────────┬─────────┘   └──────────┬───────────┘
            │ HTTP proxy              │ AMQP publish
            │                         ├───────────────┐
            ▼                         ▼               ▼
   ┌──────────────────┐   ┌──────────────────────┐
   │  Java Backend    │   │      RabbitMQ         │
   │  Spring Boot     │   │  exchange: collab     │
   │  (auth, docs,    │   │  (topic)             │
   │   metrics, ORM)  │   └──────────┬───────────┘
   └────────┬─────────┘              │
            │ JPA                    │ consume
            ▼                        ▼
   ┌──────────────────┐   ┌──────────────────────┐
   │   PostgreSQL 16  │◀──│  Java Workers        │
   │   (partitioned)  │   │  OperationConsumer   │
   └──────────────────┘   │  MetricWorker        │
                          │  SpellWorker         │
                          └──────────────────────┘

   ┌──────────────────────────────────────────────────────────┐
   │ Redis Pub/Sub + SETNX lock                               │
   │ doc:{id}:proposals → operações recebidas por qualquer Go │
   │ doc:{id}:commits   → operações ordenadas pelo líder      │
   │ doc:{id}:leader    → lock de liderança com TTL           │
   └──────────────────────────────────────────────────────────┘
```

---

## Serviços

### Frontend — React + Vite
- **Porta:** 4000 (via nginx)
- **Responsabilidade:** SPA que serve a interface de usuário. Comunica-se exclusivamente com o serviço Go via HTTP e WebSocket.
- **Tecnologias:** React 18, TypeScript, Vite, nginx
- **Roteamento:** React Router. nginx serve `index.html` para qualquer rota SPA; rotas `/api/*` são proxiadas para o Go.

### Go Collab Service
- **Porta:** 8080
- **Responsabilidade dual:**
  1. **Proxy autenticado:** valida JWT e encaminha requisições REST para o Java Backend, injetando cabeçalhos `X-User-ID` e `X-User-Name`.
  2. **Hub WebSocket:** gerencia edição colaborativa em tempo real usando o padrão Actor por documento.
- **Tecnologias:** Go 1.22, Gin, gorilla/websocket, golang-jwt, amqp091-go

#### Padrão Hub Actor
Cada documento aberto cria um goroutine exclusivo (`Hub.run()`) que é o único responsável por ler e escrever o estado do documento. Clientes interagem via canais Go, eliminando a necessidade de mutex no estado compartilhado.

```
Client A ──send chan──▶ Hub goroutine ──send chan──▶ Client B
                            │
                        (content, version)
                            │
                        AMQP publish
```

#### Operational Transformation (OT) simplificado
Cada operação (`insert` / `delete`) carrega `pos` e `char`. O servidor é a autoridade; operações recebidas com `clientVersion` defasado passam por `transform()` antes de serem aplicadas.

### Java Backend — Spring Boot 3.3
- **Porta:** 8081 (interna; não exposta diretamente ao frontend)
- **Responsabilidade:** autenticação, persistência de documentos, persistência de operações, métricas e verificação ortográfica — tudo via consumers AMQP assíncronos.
- **Tecnologias:** Java 21, Spring Boot, Spring Security, Spring Data JPA, Spring AMQP, jjwt 0.12

**Endpoints internos relevantes:**
| Método | Rota | Descrição |
|--------|------|-----------|
| POST | `/auth/register` | Cadastro de usuário |
| POST | `/auth/login` | Login; retorna JWT |
| GET | `/documents` | Lista todos os documentos |
| POST | `/documents` | Cria documento |
| DELETE | `/documents/:id` | Remove documento (somente dono) |
| GET | `/metrics/:docId` | Métricas de uso do documento |
| GET | `/internal/documents/:id/content` | Conteúdo atual (chamado pelo Go Hub) |

### RabbitMQ
- **Portas:** 5672 (AMQP), 15672 (Management UI)
- **Exchange:** `collab` (topic, durable)
- **Filas e routing keys:**

| Fila | Routing Key | Consumer |
|------|-------------|----------|
| `q.ops.persist` | `op.persist` | `OperationConsumer` — persiste op no PostgreSQL |
| `q.ops.metric` | `op.metric` | `MetricWorker` — atualiza contadores de métricas |
| `q.ops.spell` | `op.spell` | `SpellWorker` — verifica ortografia (stub) |

Cada operação feita no editor é publicada simultaneamente nas três filas, permitindo processamento paralelo e desacoplado.

### Redis
- **Porta:** 6379
- **Responsabilidade:** replicação efêmera e de baixa latência entre múltiplas instâncias do serviço Go.
- **Pub/Sub por documento:**
  - `collabdocs:doc:{docId}:proposals`: recebe operações vindas de qualquer instância Go.
  - `collabdocs:doc:{docId}:commits`: distribui operações já ordenadas pelo líder do documento.
- **Liderança:** `collabdocs:doc:{docId}:leader` usa `SETNX` com TTL. Apenas o líder transforma, incrementa versão e confirma operações para o documento.

Redis não substitui RabbitMQ: Redis mantém a experiência em tempo real entre Hubs; RabbitMQ/PostgreSQL continuam sendo o caminho durável para persistência, métricas, workers e snapshot de conteúdo.

### PostgreSQL 16
- **Porta:** 5432
- **Schema principal:**

| Tabela | Descrição |
|--------|-----------|
| `users` | Usuários (UUID, email, bcrypt hash) |
| `documents` | Documentos (título, conteúdo atual, versão) |
| `doc_permissions` | Controle de acesso por documento |
| `operations` | Histórico de todas as operações — **particionada por HASH(doc_id)** em 4 partições |
| `metrics` | Contadores agregados por documento (total_ops, chars_inserted, chars_deleted) |
| `spell_issues` | Problemas ortográficos detectados |
| `audit_log` | Log de auditoria de eventos |

A tabela `operations` usa particionamento por hash para distribuir o volume de escrita entre partições físicas independentes.

---

## Fluxo de Edição em Tempo Real

```
Usuário A digita 'a'
       │
       ▼
EditorPage.handleChange()
  diffToOps(old, new) → [{insert, pos:5, char:'a'}]
  sendOp(op) via WebSocket
       │
       ▼ ws://host/api/ws/:docId?token=JWT
       │
    nginx (strip /api, upgrade)
       │
       ▼ ws://go-collab:8080/ws/:docId
       │
    Hub.ReadPump() → incoming chan
       │
    Hub.run() → PublishProposal(Redis)
       │
       ▼ collabdocs:doc:{id}:proposals
    Hub líder do documento
       ├── transform(op, serverVersion - clientVersion)
       ├── apply(content, op)
       ├── version++
       ├── PublishOp(...)            → RabbitMQ (persist + snapshot + metric + spell)
       └── PublishCommit(Redis)
       │
       ▼ collabdocs:doc:{id}:commits
    Hubs em todas as instâncias Go
       ├── apply(content, op)
       └── broadcast local           → clientes conectados naquela instância
       │
       ▼ WebSocket frame para Usuário B
       │
    useWebSocket.onmessage()
       │
    handleMessage({ type:'op', op:{...} })
       │
    setContent(prev => applyOp(prev, op))  → textarea atualiza
```

---

## Autenticação

O JWT é gerado pelo Java com chave HMAC-SHA256 (≥ 256 bits). O Go valida o token em todas as rotas protegidas — incluindo WebSocket via query param `?token=`. Após validação, o Go injeta `X-User-ID` (subject do JWT) e `X-User-Name` nos cabeçalhos antes de fazer proxy para o Java.

```
Frontend → Authorization: Bearer <JWT>
                │
            Go JWT middleware
                │ valid
                ├── c.Set("userID", claims.Subject)
                └── proxy → X-User-ID: <uuid>
                                 │
                             Java Controller
                             @RequestHeader("X-User-ID")
```

---

## Concorrência e Distribuição

| Aspecto | Mecanismo |
|---------|-----------|
| Estado do documento | Goroutine Actor exclusivo por documento (sem mutex) |
| Múltiplos clientes no mesmo doc | Canais Go (`register`, `unregister`, `incoming`) |
| Múltiplos documentos simultâneos | `Manager` com `sync.RWMutex` + double-checked locking |
| Replicação entre instâncias Go | Redis Pub/Sub (`proposals`/`commits`) + lock `SETNX` por documento |
| Processamento assíncrono de ops | RabbitMQ topic exchange; workers Java independentes |
| Workers em paralelo (spell) | `@RabbitListener(concurrency = "2")` |
| Particionamento de dados | PostgreSQL HASH partition em `operations` |
