# Teste runtime de consistencia multi-cliente e failover.
# Uso: powershell -ExecutionPolicy Bypass -File .\infra\runtime-consistency-test.ps1

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)

function Invoke-Json {
    param(
        [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][string]$Url,
        [object]$Body = $null,
        [string]$Token = ""
    )

    $headers = @{}
    if ($Token) {
        $headers["Authorization"] = "Bearer $Token"
    }

    $params = @{
        Method = $Method
        Uri = $Url
        Headers = $headers
        UseBasicParsing = $true
    }

    if ($null -ne $Body) {
        $params.ContentType = "application/json"
        $params.Body = ($Body | ConvertTo-Json -Depth 10)
    }

    Invoke-RestMethod @params
}

function Wait-Until {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Condition,
        [string]$Message = "condition",
        [int]$TimeoutSeconds = 30
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    do {
        $result = & $Condition
        if ($result) {
            return $result
        }
        Start-Sleep -Milliseconds 500
    } while ((Get-Date) -lt $deadline)

    throw "Timed out waiting for $Message"
}

function New-TestUser {
    param([string]$Prefix)

    $suffix = [guid]::NewGuid().ToString("N").Substring(0, 8)
    $email = "$Prefix-$suffix@collabdocs.test"
    Invoke-Json POST "http://localhost:4000/api/auth/register" @{
        email = $email
        name = $Prefix
        password = "test123"
    }
}

function New-WsClient {
    param(
        [string]$Port,
        [string]$DocId,
        [string]$Token
    )

    $ws = [System.Net.WebSockets.ClientWebSocket]::new()
    $uri = [Uri]"ws://localhost:$Port/ws/$DocId`?token=$Token"
    $null = $ws.ConnectAsync($uri, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
    return $ws
}

function Send-WsJson {
    param(
        [System.Net.WebSockets.ClientWebSocket]$Ws,
        [object]$Payload
    )

    $json = $Payload | ConvertTo-Json -Compress -Depth 10
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $segment = [ArraySegment[byte]]::new($bytes)
    $null = $Ws.SendAsync($segment, [System.Net.WebSockets.WebSocketMessageType]::Text, $true, [Threading.CancellationToken]::None).GetAwaiter().GetResult()
}

function Receive-WsJson {
    param(
        [System.Net.WebSockets.ClientWebSocket]$Ws,
        [int]$TimeoutSeconds = 10
    )

    $buffer = New-Object byte[] 8192
    $stream = New-Object System.IO.MemoryStream
    $cts = [Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds($TimeoutSeconds))
    try {
        do {
            $segment = [ArraySegment[byte]]::new($buffer)
            $result = $Ws.ReceiveAsync($segment, $cts.Token).GetAwaiter().GetResult()
            if ($result.MessageType -eq [System.Net.WebSockets.WebSocketMessageType]::Close) {
                throw "WebSocket closed"
            }
            $stream.Write($buffer, 0, $result.Count)
        } while (-not $result.EndOfMessage)

        $json = [Text.Encoding]::UTF8.GetString($stream.ToArray())
        $json | ConvertFrom-Json
    }
    finally {
        $stream.Dispose()
        $cts.Dispose()
    }
}

function Receive-WsType {
    param(
        [System.Net.WebSockets.ClientWebSocket]$Ws,
        [string]$Type,
        [int]$TimeoutSeconds = 10
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $remaining = [Math]::Max(1, [int]($deadline - (Get-Date)).TotalSeconds)
        $msg = Receive-WsJson $Ws $remaining
        if ($msg.type -eq $Type) {
            return $msg
        }
    }
    throw "Timed out waiting for WebSocket message type '$Type'"
}

function Close-Ws {
    param([System.Net.WebSockets.ClientWebSocket]$Ws)
    if ($null -eq $Ws) {
        return
    }
    if ($Ws.State -eq [System.Net.WebSockets.WebSocketState]::Open) {
        $Ws.Abort()
    }
    $Ws.Dispose()
}

$stoppedContainer = ""
$wsA = $null
$wsB = $null
$wsDoc2 = $null
$wsDoc1Again = $null
$wsFailoverA = $null
$wsFailoverB = $null
$wsSurvivor = $null

Push-Location $Root
try {
    Write-Host "1/8 Verificando stack..." -ForegroundColor Cyan
    Invoke-Json GET "http://localhost:8080/health" | Out-Null
    Invoke-Json GET "http://localhost:8082/health" | Out-Null

    Write-Host "2/8 Criando usuarios de teste..." -ForegroundColor Cyan
    $userA = New-TestUser "runtime-a"
    $userB = New-TestUser "runtime-b"

    Write-Host "3/8 Criando documento e validando propagacao da lista..." -ForegroundColor Cyan
    $doc1 = Invoke-Json POST "http://localhost:4000/api/documents" @{ title = "runtime-doc-1" } $userA.token
    Wait-Until {
        $docs = Invoke-Json GET "http://localhost:4000/api/documents" $null $userB.token
        $docs | Where-Object { $_.id -eq $doc1.id }
    } "document created by user A to appear for user B" | Out-Null

    Write-Host "4/8 Validando WebSocket entre as duas instancias Go..." -ForegroundColor Cyan
    $wsA = New-WsClient 8080 $doc1.id $userA.token
    $wsB = New-WsClient 8082 $doc1.id $userB.token
    Receive-WsType $wsA "resync" | Out-Null
    Receive-WsType $wsB "resync" | Out-Null
    Send-WsJson $wsA @{ type = "op"; clientVersion = 0; op = @{ type = "insert"; pos = 0; char = "A" } }
    $op = Receive-WsType $wsB "op"
    if ($op.op.char -ne "A") {
        throw "Expected replicated char 'A', got '$($op.op.char)'"
    }

    Write-Host "5/8 Validando snapshot persistido no Java/PostgreSQL..." -ForegroundColor Cyan
    Wait-Until {
        $doc = Invoke-Json GET "http://localhost:4000/api/documents/$($doc1.id)" $null $userB.token
        if ($doc.content -eq "A") { $doc } else { $null }
    } "document snapshot content to become 'A'" | Out-Null

    Write-Host "6/8 Validando troca de documento sem vazamento de conteudo..." -ForegroundColor Cyan
    $doc2 = Invoke-Json POST "http://localhost:4000/api/documents" @{ title = "runtime-doc-2" } $userA.token
    $wsDoc2 = New-WsClient 8082 $doc2.id $userB.token
    $resync2 = Receive-WsType $wsDoc2 "resync"
    if ($resync2.content -ne "") {
        throw "Expected empty doc2 content, got '$($resync2.content)'"
    }
    Close-Ws $wsDoc2
    $wsDoc1Again = New-WsClient 8082 $doc1.id $userB.token
    $resync1 = Receive-WsType $wsDoc1Again "resync"
    if ($resync1.content -ne "A") {
        throw "Expected doc1 content 'A' after switching back, got '$($resync1.content)'"
    }
    Close-Ws $wsDoc1Again

    Write-Host "7/8 Validando exclusao visivel para outro cliente..." -ForegroundColor Cyan
    Invoke-Json DELETE "http://localhost:4000/api/documents/$($doc1.id)" $null $userA.token | Out-Null
    Wait-Until {
        $docs = Invoke-Json GET "http://localhost:4000/api/documents" $null $userB.token
        -not ($docs | Where-Object { $_.id -eq $doc1.id })
    } "deleted document to disappear for user B" | Out-Null

    Write-Host "8/8 Validando failover de lideranca..." -ForegroundColor Cyan
    $wsFailoverA = New-WsClient 8080 $doc2.id $userA.token
    $wsFailoverB = New-WsClient 8082 $doc2.id $userB.token
    Receive-WsType $wsFailoverA "resync" | Out-Null
    Receive-WsType $wsFailoverB "resync" | Out-Null
    Send-WsJson $wsFailoverA @{ type = "op"; clientVersion = 0; op = @{ type = "insert"; pos = 0; char = "B" } }
    Receive-WsType $wsFailoverB "op" | Out-Null

    $status8080 = Invoke-Json GET "http://localhost:8080/replication/documents/$($doc2.id)"
    $status8082 = Invoke-Json GET "http://localhost:8082/replication/documents/$($doc2.id)"
    $stoppedContainer = if ($status8080.isLocalLeader) { "infra-go-collab-1" } elseif ($status8082.isLocalLeader) { "infra-go-collab-2-1" } else { throw "No local leader found for doc2" }
    $survivorPort = if ($stoppedContainer -eq "infra-go-collab-1") { 8082 } else { 8080 }
    docker stop $stoppedContainer | Out-Null

    Wait-Until {
        try {
            $status = Invoke-Json GET "http://localhost:$survivorPort/replication/documents/$($doc2.id)"
            if ($status.isLocalLeader) { $status } else { $null }
        } catch {
            $null
        }
    } "survivor to become leader after failover" 20 | Out-Null

    $wsSurvivor = New-WsClient $survivorPort $doc2.id $userB.token
    $resyncAfterFailover = Receive-WsType $wsSurvivor "resync"
    if ($resyncAfterFailover.content -ne "B") {
        throw "Expected doc2 content 'B' after failover, got '$($resyncAfterFailover.content)'"
    }

    Write-Host "OK: runtime consistency and failover checks passed." -ForegroundColor Green
}
finally {
    Close-Ws $wsA
    Close-Ws $wsB
    Close-Ws $wsDoc2
    Close-Ws $wsDoc1Again
    Close-Ws $wsFailoverA
    Close-Ws $wsFailoverB
    Close-Ws $wsSurvivor
    if ($stoppedContainer) {
        docker start $stoppedContainer | Out-Null
    }
    Pop-Location
}
