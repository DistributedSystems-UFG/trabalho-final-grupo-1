const BASE = '/api'

function authHeaders(): HeadersInit {
  const token = localStorage.getItem('token')
  return token ? { Authorization: `Bearer ${token}` } : {}
}

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(BASE + path, {
    ...init,
    headers: { 'Content-Type': 'application/json', ...authHeaders(), ...init?.headers },
  })
  if (!res.ok) {
    const err = await res.json().catch(() => ({ error: res.statusText }))
    throw new Error(err.error ?? err.message ?? 'request failed')
  }
  return res.json()
}

export interface AuthResponse {
  token: string
  userId: string
  name: string
  email: string
}

export interface DocumentSummary {
  id: string
  title: string
  ownerId: string
  updatedAt: string
}

export interface Metrics {
  docId: string
  totalOps: number
  charsInserted: number
  charsDeleted: number
  lastActivity: string
}

export const api = {
  login(email: string, password: string) {
    return request<AuthResponse>('/auth/login', {
      method: 'POST',
      body: JSON.stringify({ email, password }),
    })
  },
  register(email: string, name: string, password: string) {
    return request<AuthResponse>('/auth/register', {
      method: 'POST',
      body: JSON.stringify({ email, name, password }),
    })
  },
  listDocuments() {
    return request<DocumentSummary[]>('/documents')
  },
  createDocument(title: string) {
    return request<DocumentSummary>('/documents', {
      method: 'POST',
      body: JSON.stringify({ title }),
    })
  },
  deleteDocument(id: string) {
    return fetch(`${BASE}/documents/${id}`, {
      method: 'DELETE',
      headers: authHeaders() as Record<string, string>,
    })
  },
  getMetrics(docId: string) {
    return request<Metrics>(`/metrics/${docId}`)
  },
}

export function wsUrl(docId: string): string {
  const token = localStorage.getItem('token') ?? ''
  const protocol = location.protocol === 'https:' ? 'wss' : 'ws'
  return `${protocol}://${location.host}/api/ws/${docId}?token=${token}`
}
