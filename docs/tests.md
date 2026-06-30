# Testes do CollabDocs

Este documento centraliza os testes manuais e automatizados do projeto. O objetivo é validar colaboração em tempo real, replicação entre instâncias Go, persistência do conteúdo e failover de liderança Redis.

---

## Pré-requisitos

- Docker e Docker Compose instalados.
- Stack rodando com:

```bash
docker compose -f infra/docker-compose.yml up -d --build
```

- Portas livres no host:

| Porta | Serviço |
|-------|---------|
| 4000 | Frontend nginx |
| 8080 | Go Collab instância 1 |
| 8081 | Java Backend |
| 8082 | Go Collab instância 2 |
| 5432 | PostgreSQL |
| 6379 | Redis |
| 15672 | RabbitMQ Management |

---

## Teste Automatizado Principal

O teste automatizado principal é `infra/runtime-consistency-test.ps1`. Ele executa um cenário completo em runtime, usando HTTP e WebSocket reais contra os containers em execução.

### O Que Ele Valida

| Etapa | Validação |
|-------|-----------|
| Health | As duas instâncias Go respondem em `8080` e `8082` |
| Usuários | Dois usuários temporários conseguem se registrar |
| Criação de documento | Documento criado por um usuário aparece para outro |
| WebSocket multi-instância | Cliente em `go-collab` replica operação para cliente em `go-collab-2` |
| Snapshot persistido | Conteúdo editado aparece em `GET /documents/{id}` via Java/PostgreSQL |
| Troca de documento | Abrir doc 2 e voltar para doc 1 não mistura conteúdo |
| Exclusão | Documento apagado pelo dono desaparece para outro cliente |
| Failover | Ao parar o líder, a outra instância assume liderança e mantém o conteúdo |

### Formatos Disponíveis

Escolha o script de acordo com o sistema operacional:

| Sistema | Comando |
|---------|---------|
| Windows PowerShell | `powershell -ExecutionPolicy Bypass -File .\infra\runtime-consistency-test.ps1` |
| Windows BAT | `.\infra\runtime-consistency-test.bat` |
| Linux / WSL | `bash ./infra/runtime-consistency-test.sh` |
| macOS | `./infra/runtime-consistency-test.command` |

> No Linux/macOS, o wrapper usa PowerShell Core (`pwsh`). Se não estiver instalado, instale pelo guia oficial da Microsoft: https://learn.microsoft.com/powershell/scripting/install/installing-powershell

### Saída Esperada

```text
1/8 Verificando stack...
2/8 Criando usuarios de teste...
3/8 Criando documento e validando propagacao da lista...
4/8 Validando WebSocket entre as duas instancias Go...
5/8 Validando snapshot persistido no Java/PostgreSQL...
6/8 Validando troca de documento sem vazamento de conteudo...
7/8 Validando exclusao visivel para outro cliente...
8/8 Validando failover de lideranca...
OK: runtime consistency and failover checks passed.
```

### Estado Após o Teste

- O teste cria usuários/documentos temporários no banco em execução.
- Durante o failover, ele para o container líder e depois tenta reiniciá-lo automaticamente.
- Para voltar ao estado inicial, rode:

```powershell
.\infra\reset.ps1
docker compose -f infra/docker-compose.yml up -d --build
```

---

## Teste Manual de Colaboração

Use este teste para observar a UI em dois navegadores.

1. Abra `http://localhost:4000` em dois navegadores diferentes, ou em uma janela normal e uma anônima.
2. Faça login com contas diferentes.
3. Crie um documento no cliente A.
4. Verifique se o documento aparece no cliente B em poucos segundos.
5. Abra o mesmo documento nos dois clientes.
6. Digite no cliente A e observe o texto aparecer no cliente B.
7. Troque para outro documento e volte; o conteúdo não deve misturar entre documentos.
8. Apague um documento pelo usuário dono; ele deve desaparecer do outro cliente.

---

## Teste Manual de Failover

O roteiro detalhado está em [failover-test.md](failover-test.md). Use-o quando quiser demonstrar a troca de liderança passo a passo com inspeção de Redis e logs.

Resumo:

1. Abra o mesmo documento em dois clientes.
2. Consulte os endpoints:

```powershell
curl http://localhost:8080/replication/documents/<DOC_ID>
curl http://localhost:8082/replication/documents/<DOC_ID>
```

3. Identifique quem tem `isLocalLeader: true`.
4. Pare o container líder:

```powershell
docker stop infra-go-collab-1
```

ou:

```powershell
docker stop infra-go-collab-2-1
```

5. Aguarde 10-15 segundos.
6. Confirme que a instância sobrevivente assumiu:

```powershell
docker exec infra-redis-1 redis-cli GET "collabdocs:doc:<DOC_ID>:leader"
```

---

## Testes de Build e Unidade

### Go

```bash
docker run --rm -v "$PWD/go/collab-service:/app" -w /app golang:1.22-alpine sh -c "gofmt -w ./cmd ./internal && go test ./..."
```

### Build Docker Completo

```bash
docker compose -f infra/docker-compose.yml build frontend java-backend go-collab go-collab-2
```

---

## Solução de Problemas

| Sintoma | Causa provável | Correção |
|---------|----------------|----------|
| Usuários antigos continuam aparecendo | Volume PostgreSQL não foi apagado | Rode `docker compose -f infra/docker-compose.yml down -v` ou `.\infra\reset.ps1` |
| Wrapper `.sh`/`.command` falha com `pwsh not found` | PowerShell Core não instalado | Instale `pwsh` ou execute o `.ps1` no Windows |
| Teste para no health check | Stack não está rodando ou porta ocupada | Rode `docker compose -f infra/docker-compose.yml ps` |
| Failover demora | Lock Redis ainda não expirou | Aguarde 10-15 segundos |
| Cliente fica vermelho após matar líder | WebSocket estava conectado ao container morto | O hook tenta reconectar; recarregue a página se estiver testando manualmente |

