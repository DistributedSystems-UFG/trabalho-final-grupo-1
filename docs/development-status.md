# Relatório de Desenvolvimento — CollabDocs

**Disciplina:** Sistemas Concorrentes e Distribuídos (SCD 2026.1)  
**Professor:** Fábio Moreira Costa — UFG  
**Prazo:** 28/06/2026  
**Data do relatório:** 19/06/2026

---

## Status Geral

| Camada | Status | Observações |
|--------|--------|-------------|
| Infraestrutura (Docker) | Completo | 5 containers rodando |
| Banco de dados (PostgreSQL) | Completo | Schema + seed funcionais |
| Mensageria (RabbitMQ) | Completo | Exchange + 3 filas configurados |
| Java Backend (auth + docs) | Completo | REST, JWT, JPA operacionais |
| Go Collab Service | Completo | Proxy + Hub Actor + OT |
| Frontend (React) | Completo | SPA, login, editor, presença |
| Edição colaborativa em tempo real | Em ajuste | WebSocket funcional; bug de OT simplificado |
| Workers assíncronos | Parcial | Persist e Metric funcionais; Spell é stub |

---

## O que está implementado

### Infraestrutura
- Docker Compose orquestando todos os 5 serviços com healthchecks
- Rede interna Docker; apenas portas necessárias expostas ao host
- PostgreSQL com volume persistente e schema versionado via `init.sql`
- Seed automático com usuário admin de desenvolvimento

### Autenticação
- Registro e login via Java (`/api/auth/register`, `/api/auth/login`)
- JWT HMAC-SHA256 com secret de 280 bits (acima do mínimo de 256 bits)
- Validade de 24h; validado no Go antes de qualquer rota protegida
- WebSocket autenticado via query param `?token=JWT`

### Documentos
- Criação, listagem e remoção de documentos
- Todos os usuários autenticados visualizam todos os documentos (modelo de workspace compartilhado)
- Restrição: somente o criador pode deletar seu próprio documento (403 para outros)
- Carregamento do conteúdo atual no Hub Go via chamada interna `GET /internal/documents/:id/content`

### Edição Colaborativa (WebSocket)
- Padrão Hub Actor: um goroutine Go por documento aberto
- Presença em tempo real: avatares coloridos de quem está no documento
- `diffToOps`: calcula operações mínimas (insert/delete) entre estado anterior e novo do textarea, suportando digitação e colagem
- Operational Transformation simplificado: servidor é autoridade; operações defasadas passam por `transform()` antes de aplicação
- Cursor preservado após aplicação de ops remotas via `adjustCursor` + `requestAnimationFrame`

### Pipeline de Mensagens (RabbitMQ)
- Cada operação publicada em 3 filas simultaneamente (`op.persist`, `op.metric`, `op.spell`)
- `OperationConsumer`: persiste operação no PostgreSQL (tabela particionada)
- `MetricWorker`: upsert em `metrics` — total_ops, chars_inserted, chars_deleted
- Painel de métricas no editor com polling a cada 10s

### Frontend
- SPA React com roteamento client-side (recarregar página mantém a rota)
- Design inspirado no Notion (paleta neutra, sidebar, área de editor centralizada)
- Login e registro na mesma tela com alternância de modo
- Indicador visual de conexão WebSocket (ponto verde/vermelho "ao vivo")
- Sidebar com indicador "(meu)" nos documentos criados pelo usuário logado

---

## Bugs resolvidos durante o desenvolvimento

| Bug | Causa raiz | Solução |
|-----|-----------|---------|
| Login retornava 401 | Hash bcrypt no seed não correspondia a "admin123" | Geração de hash verificado com Python `bcrypt.checkpw` |
| `column "content" does not exist` | Volume PostgreSQL antigo sem a coluna | `docker compose down -v` para recriar volumes |
| JWT `WeakKeyException` | Secret com 31 chars (248 bits < 256 mínimo) | Secret aumentado para 35 chars (280 bits) |
| Wildcard conflict no Gin | Rota `/documents/:id/history` conflitava com `/documents/:id` | Rota de histórico removida |
| nginx falha ao iniciar | DNS `go-collab` não resolvido no startup | `resolver 127.0.0.11` + `set $upstream` para resolução lazy |
| `nil pointer` em `fetchContent` | `resp` nil testado junto com `resp.StatusCode` | Separação em dois `if` independentes |
| JSON field mismatch | Go publicava `"char"` mas Java esperava `"character"` | Ajuste do json tag no struct Go |
| `ddl-auto: validate` com tabela particionada | JPA não consegue validar partições | Alterado para `ddl-auto: none` |
| Recarregar `/documents` redirecionava para login | nginx proxiava `/documents` para o Go (sem token) | Prefixo `/api/` para rotas de backend; SPA serve o resto |
| FK violation ao criar documento (500) | Token stale no localStorage com UUID de sessão antiga | Usuário precisa relogar; seed corrigido |
| Erro `Cannot read properties of undefined` | `content` em `ServerMessage` com `omitempty`: `""` não serializado → `msg.content` undefined no frontend | Removido `omitempty` do campo `Content` no struct Go |
| `versionRef` desatualizado no remetente | Sender não recebia próprio op de volta (`broadcastExcept`) | Incremento local de `versionRef` após cada `sendOp` |

---

## Pendências e limitações conhecidas

### OT Simplificado
A função `transform()` no Go retorna a operação sem modificação quando há delta de versão. Isso funciona corretamente quando apenas um usuário edita por vez, mas pode gerar divergência de estado quando dois usuários editam a **mesma posição simultaneamente**. Uma implementação completa de OT exigiria buffer de operações do servidor para composição de transformações.

### SpellWorker
O `SpellWorker` consome as mensagens da fila `q.ops.spell` mas não implementa verificação ortográfica real — apenas loga a operação. A tabela `spell_issues` existe no banco mas não é populada.

### Persistência de conteúdo
O conteúdo do documento é mantido em memória no Hub Go e reconstruído a partir do estado inicial carregado do Java. Quando o Hub é destruído (todos saem do documento), o conteúdo acumulado **não é persistido automaticamente** de volta ao banco. O histórico de operações está no PostgreSQL via RabbitMQ, mas não há lógica de replay para reconstruir o documento a partir das ops.

### doc_permissions
A tabela `doc_permissions` existe no schema mas não é utilizada. O modelo atual permite que todos os usuários autenticados vejam e editem qualquer documento (workspace compartilhado).

### Ausência de reconexão automática
O `useWebSocket` no frontend não implementa reconexão automática com backoff. Se o WebSocket cair (reinício do Go), o usuário precisa recarregar a página manualmente.

---

## Requisitos da disciplina

| Requisito | Atendido | Mecanismo |
|-----------|----------|-----------|
| Sistemas distribuídos (múltiplos processos) | Sim | Go + Java + RabbitMQ + PostgreSQL como processos independentes |
| Comunicação entre processos | Sim | HTTP (Go→Java), AMQP (Go→RabbitMQ→Java workers) |
| Concorrência | Sim | Hub Actor (goroutines + channels), workers AMQP concorrentes |
| Sincronização de estado | Sim | OT simplificado com servidor como autoridade |
| Mensageria assíncrona | Sim | RabbitMQ topic exchange com 3 consumers |
| Particionamento de dados | Sim | `operations` particionada por HASH(doc_id) em 4 partições |
| Containerização | Sim | Docker Compose com 5 serviços |
