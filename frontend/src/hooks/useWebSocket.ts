import { useCallback, useEffect, useRef, useState } from 'react'
import { wsUrl } from '../services/api'

export type ServerMsg =
  | { type: 'resync'; serverVersion: number; content: string }
  | { type: 'op'; serverVersion: number; userId: string; op: Op }
  | { type: 'cursor'; userId: string; name: string; line: number; col: number }
  | { type: 'presence'; users: { id: string; name: string }[] }

export interface Op {
  type: 'insert' | 'delete'
  pos: number
  char?: string
}

interface Options {
  onMessage: (msg: ServerMsg) => void
}

const RECONNECT_MS = 1_000

export function useWebSocket(docId: string, options: Options) {
  const wsRef = useRef<WebSocket | null>(null)
  const versionRef = useRef(0)
  const optionsRef = useRef(options)
  optionsRef.current = options  // always up-to-date without re-subscribing effect

  const [connected, setConnected] = useState(false)

  useEffect(() => {
    let stopped = false
    let retry: number | undefined

    versionRef.current = 0
    setConnected(false)

    function connect() {
      if (stopped) return

      const ws = new WebSocket(wsUrl(docId))
      wsRef.current = ws

      ws.onopen = () => {
        if (!stopped && wsRef.current === ws) setConnected(true)
      }

      ws.onclose = () => {
        if (wsRef.current === ws) {
          wsRef.current = null
          setConnected(false)
        }
        if (!stopped) {
          retry = window.setTimeout(connect, RECONNECT_MS)
        }
      }

      ws.onerror = (e) => console.error('[ws] error', e)

      ws.onmessage = ({ data }) => {
        if (stopped || wsRef.current !== ws) return
        try {
          const msg: ServerMsg = JSON.parse(data)
          console.debug('[ws] recv', msg.type, msg)
          if (msg.type === 'resync' || msg.type === 'op') {
            versionRef.current = msg.serverVersion
          }
          optionsRef.current.onMessage(msg)
        } catch {
          console.warn('[ws] malformed message', data)
        }
      }
    }

    connect()

    return () => {
      stopped = true
      if (retry !== undefined) window.clearTimeout(retry)
      const ws = wsRef.current
      wsRef.current = null
      setConnected(false)
      if (ws) {
        ws.onopen = ws.onclose = ws.onerror = ws.onmessage = null
        ws.close()
      }
    }
  }, [docId])

  const sendOp = useCallback((op: Op) => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      wsRef.current.send(JSON.stringify({
        type: 'op',
        clientVersion: versionRef.current,
        op,
      }))
      versionRef.current++  // local version advances; server will confirm via others' ops
    }
  }, [])

  const sendCursor = useCallback((line: number, col: number) => {
    if (wsRef.current?.readyState === WebSocket.OPEN) {
      wsRef.current.send(JSON.stringify({ type: 'cursor', line, col }))
    }
  }, [])

  return { connected, sendOp, sendCursor }
}
