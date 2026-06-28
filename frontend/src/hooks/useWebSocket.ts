import { useCallback, useEffect, useRef, useState } from 'react'
import { wsUrl } from '../services/api'

export type ServerMsg =
  | { type: 'resync'; serverVersion: number; content: string }
  | { type: 'ack'; serverVersion: number }
  | { type: 'op'; serverVersion: number; userId: string; op: Op }
  | { type: 'cursor'; userId: string; name: string; pos: number }
  | { type: 'presence'; users: { id: string; name: string }[] }

export interface Op {
  type: 'insert' | 'delete'
  pos: number
  char?: string
}

interface PendingOp {
  op: Op
}

interface Options {
  onMessage: (msg: ServerMsg) => void
}

// ── Inclusion Transformation ──────────────────────────────────────────────────
//
// opWins controls tie-breaking on equal-position insert/insert.
// Server ops always win (opWins=false for client ops, opWins=true for server ops).

function itransform(op: Op, against: Op, opWins: boolean): Op | null {
  const result = { ...op }

  if (op.type === 'insert' && against.type === 'insert') {
    if (op.pos > against.pos) result.pos++
    else if (op.pos === against.pos && !opWins) result.pos++
  } else if (op.type === 'insert' && against.type === 'delete') {
    if (op.pos > against.pos) result.pos--
  } else if (op.type === 'delete' && against.type === 'insert') {
    if (op.pos >= against.pos) result.pos++
  } else if (op.type === 'delete' && against.type === 'delete') {
    if (op.pos > against.pos) result.pos--
    else if (op.pos === against.pos) return null // already deleted
  }

  return result
}

// Transform a server op against a pending client op (server has higher priority).
function transformServerOp(serverOp: Op, clientOp: Op): Op | null {
  return itransform(serverOp, clientOp, true)
}

// Transform a pending client op against a server op (server has higher priority).
function transformClientOp(clientOp: Op, serverOp: Op): Op | null {
  return itransform(clientOp, serverOp, false)
}

// ─────────────────────────────────────────────────────────────────────────────

export function useWebSocket(docId: string, options: Options) {
  const wsRef = useRef<WebSocket | null>(null)
  const serverVersionRef = useRef(0)
  const pendingRef = useRef<PendingOp[]>([])
  const optionsRef = useRef(options)
  optionsRef.current = options

  const [connected, setConnected] = useState(false)

  useEffect(() => {
    const ws = new WebSocket(wsUrl(docId))
    wsRef.current = ws

    ws.onopen  = () => setConnected(true)
    ws.onclose = () => setConnected(false)
    ws.onerror = (e) => console.error('[ws] error', e)

    ws.onmessage = ({ data }) => {
      try {
        const msg: ServerMsg = JSON.parse(data)
        console.debug('[ws] recv', msg.type, msg)

        if (msg.type === 'resync') {
          serverVersionRef.current = msg.serverVersion
          pendingRef.current = []
          optionsRef.current.onMessage(msg)
          return
        }

        if (msg.type === 'ack') {
          serverVersionRef.current = msg.serverVersion
          if (pendingRef.current.length > 0) {
            pendingRef.current.shift()
          }
          return
        }

        if (msg.type === 'op') {
          serverVersionRef.current = msg.serverVersion
          const remoteOp = msg.op

          // 1. Transform the incoming server op against all pending client ops
          //    so it lands in the right position relative to our local state.
          let transformed: Op | null = { ...remoteOp }
          for (const p of pendingRef.current) {
            if (!transformed) break
            transformed = transformServerOp(transformed, p.op)
          }

          // 2. Transform each pending client op against the (original) server op
          //    so they stay correct relative to the server's new state.
          const updated: PendingOp[] = []
          for (const p of pendingRef.current) {
            const newOp = transformClientOp(p.op, remoteOp)
            if (newOp) updated.push({ op: newOp })
          }
          pendingRef.current = updated

          if (transformed) {
            optionsRef.current.onMessage({ ...msg, op: transformed })
          }
          return
        }

        optionsRef.current.onMessage(msg)
      } catch {
        console.warn('[ws] malformed message', data)
      }
    }

    return () => {
      ws.onopen = ws.onclose = ws.onerror = ws.onmessage = null
      ws.close()
    }
  }, [docId])

  const sendOp = useCallback((op: Op) => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      wsRef.current.send(JSON.stringify({
        type: 'op',
        clientVersion: serverVersionRef.current,
        op,
      }))
      pendingRef.current.push({ op })
    }
  }, [])

  const sendCursor = useCallback((pos: number) => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      wsRef.current.send(JSON.stringify({ type: 'cursor', pos }))
    }
  }, [])

  return { connected, sendOp, sendCursor }
}
