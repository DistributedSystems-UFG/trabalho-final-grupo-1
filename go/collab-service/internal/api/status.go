package api

import (
	"net/http"

	"github.com/britojp/collabdocs/go/collab-service/internal/hub"
	"github.com/britojp/collabdocs/go/collab-service/internal/replication"
	"github.com/gin-gonic/gin"
)

// Health exposes basic liveness information for a Go collab instance.
func Health(bus replication.Bus) gin.HandlerFunc {
	return func(c *gin.Context) {
		c.JSON(http.StatusOK, gin.H{
			"status": "ok",
			"nodeId": bus.NodeID(),
		})
	}
}

// DocumentReplication exposes leader and hub diagnostics for failover testing.
func DocumentReplication(manager *hub.Manager) gin.HandlerFunc {
	return func(c *gin.Context) {
		docID := c.Param("docId")
		status := manager.DocumentReplicationStatus(c.Request.Context(), docID)
		c.JSON(http.StatusOK, status)
	}
}
