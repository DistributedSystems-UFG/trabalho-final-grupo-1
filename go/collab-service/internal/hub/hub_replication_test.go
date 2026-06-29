package hub

import (
	"context"
	"encoding/json"
	"sync"
	"testing"
	"time"

	"github.com/britojp/collabdocs/go/collab-service/internal/replication"
)

func TestLeaderProposalCommitsOperationAndSkipsOriginClient(t *testing.T) {
	bus := newFakeBus("node-a")
	h := newHub("doc-1", "", nil, bus)
	h.isLeader = true

	origin := newTestClient("client-1", "user-1")
	peer := newTestClient("client-2", "user-2")
	h.clients[origin] = true
	h.clients[peer] = true

	h.handleProposal(replication.Proposal{
		DocID:          "doc-1",
		OriginNodeID:   bus.NodeID(),
		OriginClientID: origin.id,
		UserID:         origin.userID,
		ClientVersion:  0,
		Op:             replication.Operation{Type: "insert", Pos: 0, Char: "a"},
	})

	if h.content != "a" {
		t.Fatalf("content = %q, want %q", h.content, "a")
	}
	if h.version != 1 {
		t.Fatalf("version = %d, want 1", h.version)
	}

	if len(bus.commits) != 1 {
		t.Fatalf("commits = %d, want 1", len(bus.commits))
	}
	if bus.commits[0].ServerVersion != 1 {
		t.Fatalf("commit version = %d, want 1", bus.commits[0].ServerVersion)
	}

	assertNoMessage(t, origin.send)
	msg := receiveServerMessage(t, peer.send)
	if msg.Type != "op" || msg.ServerVersion != 1 || msg.Op == nil || msg.Op.Char != "a" {
		t.Fatalf("unexpected peer message: %#v", msg)
	}
}

func TestFollowerAppliesCommitFromAnotherNode(t *testing.T) {
	bus := newFakeBus("node-b")
	h := newHub("doc-1", "", nil, bus)

	peer := newTestClient("client-2", "user-2")
	h.clients[peer] = true

	h.handleCommit(replication.Commit{
		DocID:          "doc-1",
		OriginNodeID:   "node-a",
		OriginClientID: "client-1",
		UserID:         "user-1",
		ServerVersion:  3,
		Op:             replication.Operation{Type: "insert", Pos: 0, Char: "b"},
	})

	if h.content != "b" {
		t.Fatalf("content = %q, want %q", h.content, "b")
	}
	if h.version != 3 {
		t.Fatalf("version = %d, want 3", h.version)
	}

	msg := receiveServerMessage(t, peer.send)
	if msg.Type != "op" || msg.ServerVersion != 3 || msg.Op == nil || msg.Op.Char != "b" {
		t.Fatalf("unexpected peer message: %#v", msg)
	}
}

func TestHubIgnoresOwnRedisCommitAfterLocalLeaderBroadcast(t *testing.T) {
	bus := newFakeBus("node-a")
	h := newHub("doc-1", "a", nil, bus)
	h.version = 1

	h.handleCommit(replication.Commit{
		DocID:          "doc-1",
		OriginNodeID:   bus.NodeID(),
		OriginClientID: "client-1",
		UserID:         "user-1",
		ServerVersion:  2,
		Op:             replication.Operation{Type: "insert", Pos: 1, Char: "z"},
	})

	if h.content != "a" {
		t.Fatalf("content = %q, want unchanged %q", h.content, "a")
	}
	if h.version != 1 {
		t.Fatalf("version = %d, want unchanged 1", h.version)
	}
}

func newTestClient(id, userID string) *Client {
	return &Client{
		id:     id,
		userID: userID,
		name:   userID,
		send:   make(chan []byte, 8),
	}
}

func receiveServerMessage(t *testing.T, messages <-chan []byte) ServerMessage {
	t.Helper()
	select {
	case raw := <-messages:
		var msg ServerMessage
		if err := json.Unmarshal(raw, &msg); err != nil {
			t.Fatalf("unmarshal server message: %v", err)
		}
		return msg
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for server message")
		return ServerMessage{}
	}
}

func assertNoMessage(t *testing.T, messages <-chan []byte) {
	t.Helper()
	select {
	case raw := <-messages:
		t.Fatalf("unexpected message: %s", raw)
	default:
	}
}

type fakeBus struct {
	nodeID    string
	mu        sync.Mutex
	commits   []replication.Commit
	proposals []replication.Proposal
}

func newFakeBus(nodeID string) *fakeBus {
	return &fakeBus{nodeID: nodeID}
}

func (b *fakeBus) NodeID() string {
	return b.nodeID
}

func (b *fakeBus) Subscribe(context.Context, string) (<-chan replication.Message, func() error, error) {
	ch := make(chan replication.Message)
	return ch, func() error { close(ch); return nil }, nil
}

func (b *fakeBus) PublishProposal(_ context.Context, proposal replication.Proposal) error {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.proposals = append(b.proposals, proposal)
	return nil
}

func (b *fakeBus) PublishCommit(_ context.Context, commit replication.Commit) error {
	b.mu.Lock()
	defer b.mu.Unlock()
	b.commits = append(b.commits, commit)
	return nil
}

func (b *fakeBus) TryAcquireLeadership(context.Context, string, time.Duration) (bool, error) {
	return true, nil
}

func (b *fakeBus) RenewLeadership(context.Context, string, time.Duration) (bool, error) {
	return true, nil
}

func (b *fakeBus) GetLeader(context.Context, string) (string, error) {
	return b.nodeID, nil
}

func (b *fakeBus) Close() error {
	return nil
}
