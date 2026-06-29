package ws

import (
	"net/http"

	"github.com/britojp/collabdocs/go/collab-service/internal/hub"
	"github.com/gin-gonic/gin"
	"github.com/gorilla/websocket"
)

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	// Allow all origins in development; restrict in production.
	CheckOrigin: func(r *http.Request) bool { return true },
}

// Handler upgrades HTTP to WebSocket and registers the client with its document Hub.
func Handler(m *hub.Manager) gin.HandlerFunc {
	return func(c *gin.Context) {
		docID := c.Param("docId")
		userID := c.GetString("userID")
		userName := c.GetString("userName")

		conn, err := upgrader.Upgrade(c.Writer, c.Request, nil)
		if err != nil {
			return
		}

		h := m.GetOrCreate(docID)
		hub.RegisterClient(h, conn, userID, userName)
	}
}
