package hub

import "github.com/britojp/collabdocs/go/collab-service/internal/replication"

// Op is a character-level document operation.
type Op struct {
	Type string `json:"type"` // "insert" | "delete"
	Pos  int    `json:"pos"`
	Char string `json:"char,omitempty"`
}

// ClientMessage is received from a WebSocket client.
type ClientMessage struct {
	Type          string `json:"type"` // "op" | "cursor"
	ClientVersion int    `json:"clientVersion"`
	Op            *Op    `json:"op,omitempty"`
	Line          int    `json:"line,omitempty"`
	Col           int    `json:"col,omitempty"`
}

// ServerMessage is sent to WebSocket clients.
type ServerMessage struct {
	Type          string         `json:"type"`
	ServerVersion int            `json:"serverVersion,omitempty"`
	UserID        string         `json:"userId,omitempty"`
	Name          string         `json:"name,omitempty"`
	Op            *Op            `json:"op,omitempty"`
	Content       string         `json:"content"`
	Line          int            `json:"line,omitempty"`
	Col           int            `json:"col,omitempty"`
	Users         []PresenceUser `json:"users,omitempty"`
}

// PresenceUser is a user currently editing a document.
type PresenceUser struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

func toReplicationOp(op *Op) replication.Operation {
	if op == nil {
		return replication.Operation{}
	}
	return replication.Operation{
		Type: op.Type,
		Pos:  op.Pos,
		Char: op.Char,
	}
}

func fromReplicationOp(op replication.Operation) *Op {
	return &Op{
		Type: op.Type,
		Pos:  op.Pos,
		Char: op.Char,
	}
}
