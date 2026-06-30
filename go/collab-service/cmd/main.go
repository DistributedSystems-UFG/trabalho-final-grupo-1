package main

import (
	"log"
	"os"

	"github.com/britojp/collabdocs/go/collab-service/internal/api"
	"github.com/britojp/collabdocs/go/collab-service/internal/hub"
	"github.com/britojp/collabdocs/go/collab-service/internal/middleware"
	"github.com/britojp/collabdocs/go/collab-service/internal/mq"
	"github.com/britojp/collabdocs/go/collab-service/internal/replication"
	"github.com/britojp/collabdocs/go/collab-service/internal/ws"
	"github.com/gin-gonic/gin"
)

func main() {
	javaURL := env("JAVA_BACKEND_URL", "http://localhost:8081")
	secret := env("JWT_SECRET", "collabdocs-dev-secret-key-32chars!!")

	pub, err := mq.NewPublisher(env("RABBITMQ_URL", "amqp://guest:guest@localhost:5672/"))
	if err != nil {
		log.Fatalf("rabbitmq: %v", err)
	}
	defer pub.Close()

	bus, err := replication.NewRedisBus(env("REDIS_URL", "redis://localhost:6379/0"))
	if err != nil {
		log.Fatalf("redis: %v", err)
	}
	defer bus.Close()
	log.Printf("redis: replication bus connected as %s", bus.NodeID())

	manager := hub.NewManager(pub, bus, javaURL)

	r := gin.Default()
	r.Use(cors())

	// Observability — used by failover/replication runtime tests (no auth).
	r.GET("/health", api.Health(bus))
	r.GET("/replication/documents/:docId", api.DocumentReplication(manager))

	// Public — proxied to Java
	r.POST("/auth/register", api.Proxy(javaURL))
	r.POST("/auth/login", api.Proxy(javaURL))

	// Protected
	g := r.Group("/")
	g.Use(middleware.JWT(secret))
	{
		g.GET("/documents", api.Proxy(javaURL))
		g.POST("/documents", api.Proxy(javaURL))
		g.GET("/documents/:id", api.Proxy(javaURL))
		g.DELETE("/documents/:id", api.Proxy(javaURL))
		g.GET("/metrics/:docId", api.Proxy(javaURL))

		// Real-time WebSocket — handled entirely by Go
		g.GET("/ws/:docId", ws.Handler(manager))
	}

	log.Fatal(r.Run(":" + env("PORT", "8080")))
}

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func cors() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Header("Access-Control-Allow-Origin", "*")
		c.Header("Access-Control-Allow-Methods", "GET,POST,PUT,DELETE,OPTIONS")
		c.Header("Access-Control-Allow-Headers", "Authorization,Content-Type")
		if c.Request.Method == "OPTIONS" {
			c.AbortWithStatus(204)
			return
		}
		c.Next()
	}
}
