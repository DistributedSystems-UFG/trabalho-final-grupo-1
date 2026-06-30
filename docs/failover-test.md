# Teste de Failover de Liderança — CollabDocs

Este guia testa **em tempo de execução** o cenário em que a instância Go líder de um documento cai e outra instância assume a liderança via Redis, mantendo a edição colaborativa disponível.

**Cenário validado:** matar o container líder → lock Redis expira → réplica sobrevivente vira líder → documento continua editável.

## Teste automatizado

Para validar o fluxo principal com um único comando, suba a stack e execute:

```powershell
powershell -ExecutionPolicy Bypass -File .\infra\runtime-consistency-test.ps1
```

Esse teste cria usuários/documentos temporários, valida listagem entre clientes, isolamento ao trocar documentos, persistência do snapshot, exclusão e failover de liderança.

Para todos os formatos de execução (`.ps1`, `.bat`, `.sh`, `.command`), veja [tests.md](tests.md).

---

## Pré-requisitos

- Docker e Docker Compose instalados
- Stack CollabDocs compilada com **duas instâncias Go** (`go-collab` e `go-collab-2`)
- Portas livres: **4000**, **8080**, **8081**, **8082**, **5432**, **6379** e **15672**

---

## Como funciona (resumo)

Cada documento aberto possui:

| Componente | Função |
|------------|--------|
| `collabdocs:doc:{id}:leader` | Lock Redis (SETNX + TTL 10s). Só o líder ordena operações. |
| `collabdocs:doc:{id}:proposals` | Operações enviadas por qualquer instância Go |
| `collabdocs:doc:{id}:commits` | Operações confirmadas pelo líder, replicadas para todas as instâncias |

Quando o líder morre, ele deixa de renovar o lock. Após o TTL (~10s), a outra instância adquire a liderança e continua processando propostas.

---

## 1. Subir a stack com duas instâncias Go

Na raiz do repositório:

```powershell
docker compose -f infra/docker-compose.yml up -d --build
```

Aguarde todos os serviços ficarem `running`:

```powershell
docker compose -f infra/docker-compose.yml ps
```

Você deve ver **dois** serviços Go:

| Container | Porta no host | Uso |
|-----------|---------------|-----|
| `infra-go-collab-1` | 8080 | Instância Go #1 |
| `infra-go-collab-2-1` | 8082 | Instância Go #2 |
| `infra-frontend-1` | 4000 | Frontend (balanceia entre as duas instâncias Go) |

---

## 2. Identificar o ID de cada nó Go

Cada instância Go gera um `nodeId` único ao conectar no Redis.

```powershell
curl http://localhost:8080/health
curl http://localhost:8082/health
```

Exemplo de resposta:

```json
{"nodeId":"node-a1b2c3d4","status":"ok"}
{"nodeId":"node-e5f6g7h8","status":"ok"}
```

Anote os dois valores — você usará para confirmar a troca de liderança.

Verifique também nos logs:

```powershell
docker logs infra-go-collab-1 2>&1 | Select-String "redis:"
docker logs infra-go-collab-2-1 2>&1 | Select-String "redis:"
```

---

## 3. Abrir um documento colaborativo

1. Abra http://localhost:4000 em **dois navegadores** (normal + anônimo/incógnito).
2. Faça login em cada um (contas diferentes ou a mesma — o importante é ter duas sessões).
3. Em uma janela, **crie um documento** e abra o editor.
4. Na outra janela, abra o **mesmo documento**.
5. Digite um texto inicial, por exemplo: `teste failover`.

Copie o **UUID do documento** da URL:

```text
http://localhost:4000/doc/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
                              ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                              este é o DOC_ID
```

Defina uma variável no PowerShell para facilitar os próximos passos:

```powershell
$DOC_ID = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

---

## 4. Descobrir qual instância é a líder **antes** do failover

Consulte o endpoint de diagnóstico nas **duas** instâncias:

```powershell
curl "http://localhost:8080/replication/documents/$DOC_ID"
curl "http://localhost:8082/replication/documents/$DOC_ID"
```

Compare os campos:

| Campo | Significado |
|-------|-------------|
| `nodeId` | ID desta instância Go |
| `isLocalLeader` | `true` se **esta** instância é a líder local do documento |
| `redisLeader` | ID do líder registrado no Redis (deve ser igual ao `nodeId` da líder) |
| `version` | Versão atual do documento neste Hub |
| `connectedClients` | Clientes WebSocket conectados nesta instância |

**Exemplo — instância líder:**

```json
{
  "nodeId": "node-a1b2c3d4",
  "docId": "...",
  "activeHub": true,
  "isLocalLeader": true,
  "redisLeader": "node-a1b2c3d4",
  "version": 14,
  "connectedClients": 1,
  "contentLength": 14
}
```

**Exemplo — instância réplica (não líder):**

```json
{
  "nodeId": "node-e5f6g7h8",
  "isLocalLeader": false,
  "redisLeader": "node-a1b2c3d4",
  "version": 14,
  "connectedClients": 1
}
```

Confirme também direto no Redis:

```powershell
docker exec infra-redis-1 redis-cli GET "collabdocs:doc:$DOC_ID:leader"
```

O valor retornado deve ser o `nodeId` da instância líder (ex.: `node-a1b2c3d4`).

Anote qual container é o líder:

| Se o líder for... | Container |
|-------------------|-----------|
| `node-a1b2c3d4` em `:8080` | `infra-go-collab-1` |
| `node-e5f6g7h8` em `:8082` | `infra-go-collab-2-1` |

---

## 5. Preparar observação dos logs (dois terminais)

Abra dois terminais e acompanhe os logs em tempo real:

**Terminal A — instância 1:**

```powershell
docker logs -f infra-go-collab-1
```

**Terminal B — instância 2:**

```powershell
docker logs -f infra-go-collab-2-1
```

---

## 6. Executar o failover (matar o líder)

Substitua `<container-lider>` pelo container identificado no passo 4:

```powershell
docker stop <container-lider>
```

Exemplo, se a líder era a instância 1:

```powershell
docker stop infra-go-collab-1
```

### O que acontece internamente

1. O container líder para de renovar o lock Redis.
2. O lock `collabdocs:doc:{id}:leader` expira em até **10 segundos** (TTL configurado).
3. A instância sobrevivente tenta adquirir o lock a cada **3 segundos**.
4. Quando adquire, registra no log: `became leader (failover)`.

---

## 7. Verificar que a outra instância assumiu a liderança

Aguarde **10 a 15 segundos** após o `docker stop`.

### 7.1 Redis

```powershell
docker exec infra-redis-1 redis-cli GET "collabdocs:doc:$DOC_ID:leader"
```

O valor deve ser o `nodeId` da instância **sobrevivente** (diferente do líder anterior).

### 7.2 Endpoint de diagnóstico

Consulte a instância que continua rodando (ex.: porta 8082 se matou a 8080):

```powershell
curl "http://localhost:8082/replication/documents/$DOC_ID"
```

Esperado:

```json
{
  "isLocalLeader": true,
  "redisLeader": "node-e5f6g7h8",
  "version": 14
}
```

### 7.3 Log da instância sobrevivente

No terminal da instância que ficou ativa, procure:

```text
hub[<doc-id>]: node node-e5f6g7h8 became leader (failover)
```

---

## 8. Validar disponibilidade — edição continua funcionando

### 8.1 Cliente conectado à instância sobrevivente

Na janela do navegador que **ainda** mostra o ponto verde **"ao vivo"**, continue digitando.

Adicione texto, por exemplo: ` após failover`.

- O texto deve aparecer normalmente.
- O campo `version` no endpoint de diagnóstico deve **aumentar**.

### 8.2 Cliente que estava na instância morta

A janela conectada ao container eliminado perderá o WebSocket (ponto vermelho **"reconectando..."**).

**Recarregue a página** (F5). O nginx encaminhará para a instância sobrevivente.

Após recarregar:

1. O documento deve exibir o conteúdo completo (incluindo o texto digitado antes e depois do failover).
2. O indicador deve voltar para **"ao vivo"**.
3. Novas digitações devem sincronizar entre as duas janelas.

---

## 9. Checklist de sucesso

Marque cada item após o teste:

- [ ] Duas instâncias Go rodando (`8080` e `8082`)
- [ ] Antes do failover: exatamente **uma** instância com `isLocalLeader: true`
- [ ] Redis `GET leader` apontava para o nó líder
- [ ] Após `docker stop` no líder: lock Redis muda para o outro nó em ≤ 15s
- [ ] Log `became leader (failover)` aparece na instância sobrevivente
- [ ] Edição continua na instância sobrevivente sem reiniciar a stack
- [ ] Cliente na instância morta recupera após recarregar a página
- [ ] Conteúdo do documento permanece consistente entre as janelas

---

## 10. Restaurar o ambiente após o teste

Suba novamente o container que foi parado:

```powershell
docker start infra-go-collab-1
```

Aguarde alguns segundos e confirme:

```powershell
docker compose -f infra/docker-compose.yml ps
curl http://localhost:8080/health
```

> Após restaurar, a liderança **não** volta automaticamente para a instância reiniciada enquanto o lock ainda pertence à sobrevivente. Isso é esperado — o líder só muda quando o lock expira ou a instância atual perde a renovação.

---

## Comandos úteis de diagnóstico

### Monitorar tráfego Redis em tempo real

```powershell
docker exec -it infra-redis-1 redis-cli MONITOR
```

Ao digitar no editor, você verá `PUBLISH` nos canais `proposals` e `commits`.

### Ver TTL restante do lock de liderança

```powershell
docker exec infra-redis-1 redis-cli TTL "collabdocs:doc:$DOC_ID:leader"
```

- Valor positivo: segundos restantes até expirar.
- `-1`: chave existe sem TTL (não deveria ocorrer).
- `-2`: chave não existe (sem líder ativo no momento).

### Listar containers Go

```powershell
docker ps --filter "name=go-collab" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
```

---

## Solução de problemas

| Sintoma | Causa provável | Ação |
|---------|----------------|------|
| `isLocalLeader: false` nas duas instâncias | Nenhum Hub abriu o documento ainda | Abra o documento no navegador e consulte de novo |
| Failover demora mais de 15s | TTL do lock ainda não expirou | Aguarde e verifique `TTL` no Redis |
| Edição para após matar líder | Cliente ainda conectado ao container morto | Recarregue a página (F5) |
| `redisLeader` vazio após failover | Hub ainda não adquiriu lock | Aguarde mais 3–5s; confira logs da sobrevivente |
| Endpoint `:8080` não responde | Container parado no teste | Use `:8082` ou `docker start infra-go-collab-1` |

---

## Referência técnica

| Parâmetro | Valor |
|-----------|-------|
| TTL do lock de liderança | 10 segundos |
| Intervalo de renovação/aquisição | 3 segundos |
| Tempo máximo esperado de failover | ~10–15 segundos |
| Endpoints de observabilidade | `GET /health`, `GET /replication/documents/:docId` |
| Chave Redis do líder | `collabdocs:doc:{docId}:leader` |

Documentação relacionada: [architecture.md](architecture.md)
