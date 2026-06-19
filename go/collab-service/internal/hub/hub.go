package hub

import (
	"encoding/json"
	"log"

	"github.com/britojp/collabdocs/go/collab-service/internal/mq"
)

type incomingMsg struct {
	client  *Client
	payload []byte
}

// Hub is an actor goroutine that serialises all state mutations for one document.
// It is the only writer of content and version — no mutex needed for these fields.
type Hub struct {
	docID      string
	clients    map[*Client]bool
	content    string
	version    int
	register   chan *Client
	unregister chan *Client
	incoming   chan incomingMsg
	pub        *mq.Publisher
}

func newHub(docID, content string, pub *mq.Publisher) *Hub {
	return &Hub{
		docID:      docID,
		clients:    make(map[*Client]bool),
		content:    content,
		register:   make(chan *Client, 16),
		unregister: make(chan *Client, 16),
		incoming:   make(chan incomingMsg, 256),
		pub:        pub,
	}
}

func (h *Hub) run() {
	for {
		select {
		case c := <-h.register:
			h.clients[c] = true
			h.sendTo(c, ServerMessage{
				Type:          "resync",
				ServerVersion: h.version,
				Content:       h.content,
			})
			h.broadcastPresence()

		case c := <-h.unregister:
			if _, ok := h.clients[c]; ok {
				delete(h.clients, c)
				close(c.send)
				h.broadcastPresence()
			}

		case m := <-h.incoming:
			h.dispatch(m)
		}
	}
}

func (h *Hub) dispatch(m incomingMsg) {
	var env ClientMessage
	if err := json.Unmarshal(m.payload, &env); err != nil {
		return
	}
	switch env.Type {
	case "op":
		h.handleOp(m.client, env)
	case "cursor":
		h.handleCursor(m.client, env)
	}
}

func (h *Hub) handleOp(c *Client, env ClientMessage) {
	if env.Op == nil {
		return
	}
	op := transform(env.Op, h.version-env.ClientVersion)
	h.content = apply(h.content, op)
	h.version++

	h.broadcastExcept(c, ServerMessage{
		Type:          "op",
		ServerVersion: h.version,
		UserID:        c.userID,
		Op:            op,
	})

	go h.pub.PublishOp(mq.OpEvent{
		DocID:     h.docID,
		UserID:    c.userID,
		Version:   h.version,
		Type:      op.Type,
		Pos:       op.Pos,
		Character: op.Char,
	})
}

func (h *Hub) handleCursor(c *Client, env ClientMessage) {
	h.broadcastExcept(c, ServerMessage{
		Type:   "cursor",
		UserID: c.userID,
		Name:   c.name,
		Line:   env.Line,
		Col:    env.Col,
	})
}

func (h *Hub) broadcastPresence() {
	users := make([]PresenceUser, 0, len(h.clients))
	for c := range h.clients {
		users = append(users, PresenceUser{ID: c.userID, Name: c.name})
	}
	h.broadcast(ServerMessage{Type: "presence", Users: users})
}

func (h *Hub) broadcast(msg ServerMessage) {
	raw, _ := json.Marshal(msg)
	for c := range h.clients {
		h.sendRaw(c, raw)
	}
}

func (h *Hub) broadcastExcept(except *Client, msg ServerMessage) {
	raw, _ := json.Marshal(msg)
	for c := range h.clients {
		if c != except {
			h.sendRaw(c, raw)
		}
	}
}

func (h *Hub) sendTo(c *Client, msg ServerMessage) {
	raw, _ := json.Marshal(msg)
	h.sendRaw(c, raw)
}

func (h *Hub) sendRaw(c *Client, raw []byte) {
	select {
	case c.send <- raw:
	default:
		log.Printf("hub[%s]: client %s send buffer full, dropping message", h.docID, c.userID)
	}
}
