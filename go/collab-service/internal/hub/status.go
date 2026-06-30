package hub

import (
	"context"
)

// DocumentReplicationStatus exposes runtime replication diagnostics for a document.
// It is used by the failover test guide and the /replication/documents/:docId endpoint.
type DocumentReplicationStatus struct {
	NodeID           string `json:"nodeId"`
	DocID            string `json:"docId"`
	ActiveHub        bool   `json:"activeHub"`
	IsLocalLeader    bool   `json:"isLocalLeader"`
	RedisLeader      string `json:"redisLeader"`
	Version          int    `json:"version"`
	ConnectedClients int    `json:"connectedClients"`
	ContentLength    int    `json:"contentLength"`
}

// NodeID returns this Go instance identifier.
func (m *Manager) NodeID() string {
	if m.bus == nil {
		return ""
	}
	return m.bus.NodeID()
}

// DocumentReplicationStatus returns local hub state and the leader recorded in Redis.
func (m *Manager) DocumentReplicationStatus(ctx context.Context, docID string) DocumentReplicationStatus {
	status := DocumentReplicationStatus{
		NodeID: m.NodeID(),
		DocID:  docID,
	}

	if m.bus != nil {
		leader, err := m.bus.GetLeader(ctx, docID)
		if err == nil {
			status.RedisLeader = leader
		}
	}

	m.mu.RLock()
	h, ok := m.hubs[docID]
	m.mu.RUnlock()
	if !ok {
		return status
	}

	status.ActiveHub = true
	snap := h.snapshot()
	status.IsLocalLeader = snap.isLeader
	status.Version = snap.version
	status.ConnectedClients = snap.clients
	status.ContentLength = len(snap.content)
	return status
}
