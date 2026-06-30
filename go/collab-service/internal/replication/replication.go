package replication

import (
	"context"
	"time"
)

// Operation is the wire representation of a character-level editor operation.
// It intentionally mirrors hub.Op without importing the hub package, keeping the
// replication layer independent from WebSocket and OT concerns.
type Operation struct {
	Type string `json:"type"`
	Pos  int    `json:"pos"`
	Char string `json:"char,omitempty"`
}

// Proposal is an operation submitted by any Go instance for a document leader
// to order and commit. Proposals are ephemeral: Redis Pub/Sub is used for
// low-latency fan-out, while RabbitMQ/PostgreSQL remain the durable path.
type Proposal struct {
	DocID          string    `json:"docId"`
	OriginNodeID   string    `json:"originNodeId"`
	OriginClientID string    `json:"originClientId"`
	UserID         string    `json:"userId"`
	ClientVersion  int       `json:"clientVersion"`
	Op             Operation `json:"op"`
}

// Commit is an operation after it has been ordered by the document leader.
// Every Go instance applies commits to its local Hub state and broadcasts them
// only to the WebSocket clients connected to that instance.
type Commit struct {
	DocID          string    `json:"docId"`
	OriginNodeID   string    `json:"originNodeId"`
	OriginClientID string    `json:"originClientId"`
	UserID         string    `json:"userId"`
	ServerVersion  int       `json:"serverVersion"`
	Op             Operation `json:"op"`
}

// ResyncRequest is sent by a follower when it detects a version gap, asking
// the leader to publish the authoritative document state.
type ResyncRequest struct {
	DocID        string `json:"docId"`
	FromNodeID   string `json:"fromNodeId"`
	KnownVersion int    `json:"knownVersion"`
}

// ResyncResponse carries the full document state from the leader to all nodes.
type ResyncResponse struct {
	DocID   string `json:"docId"`
	Content string `json:"content"`
	Version int    `json:"version"`
}

// Message is delivered by a Bus subscription. A document Hub subscribes once
// and receives proposals, commits and resync control messages for that document.
type Message struct {
	Kind           string          `json:"kind"`
	Proposal       *Proposal       `json:"proposal,omitempty"`
	Commit         *Commit         `json:"commit,omitempty"`
	ResyncRequest  *ResyncRequest  `json:"resyncRequest,omitempty"`
	ResyncResponse *ResyncResponse `json:"resyncResponse,omitempty"`
}

const (
	// MessageKindProposal identifies operations waiting for leader ordering.
	MessageKindProposal = "proposal"
	// MessageKindCommit identifies operations confirmed by the document leader.
	MessageKindCommit = "commit"
	// MessageKindResyncRequest is sent by a follower that detected a version gap.
	// It travels via the proposals channel so only the leader processes it.
	MessageKindResyncRequest = "resync_request"
	// MessageKindResyncResponse carries the full document state from the leader.
	// It travels via the commits channel so every node receives it.
	MessageKindResyncResponse = "resync_response"
)

// Bus is the replication boundary used by the Hub Actor. Implementations may
// use Redis, an in-memory fake for tests, or a no-op adapter for local-only
// development.
type Bus interface {
	NodeID() string
	Subscribe(ctx context.Context, docID string) (<-chan Message, func() error, error)
	PublishProposal(ctx context.Context, proposal Proposal) error
	PublishCommit(ctx context.Context, commit Commit) error
	// PublishResyncRequest asks the leader to publish the full document state.
	// It is sent when a follower detects a version gap.
	PublishResyncRequest(ctx context.Context, req ResyncRequest) error
	// PublishResyncResponse broadcasts the authoritative document state to all nodes.
	// Only the leader should call this.
	PublishResyncResponse(ctx context.Context, resp ResyncResponse) error
	TryAcquireLeadership(ctx context.Context, docID string, ttl time.Duration) (bool, error)
	RenewLeadership(ctx context.Context, docID string, ttl time.Duration) (bool, error)
	// GetLeader returns the node ID currently holding the document lock in Redis.
	// An empty string means no leader is registered (yet or after TTL expiry).
	GetLeader(ctx context.Context, docID string) (string, error)
	Close() error
}

// DocumentLeaderKey returns the Redis key used for per-document leader election.
func DocumentLeaderKey(docID string) string {
	return leaderKey(docID)
}
