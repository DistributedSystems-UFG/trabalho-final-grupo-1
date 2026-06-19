package hub

import (
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"sync"

	"github.com/britojp/collabdocs/go/collab-service/internal/mq"
)

// Manager holds all active document hubs.
type Manager struct {
	mu          sync.RWMutex
	hubs        map[string]*Hub
	pub         *mq.Publisher
	javaBaseURL string
}

func NewManager(pub *mq.Publisher, javaBaseURL string) *Manager {
	return &Manager{
		hubs:        make(map[string]*Hub),
		pub:         pub,
		javaBaseURL: javaBaseURL,
	}
}

// GetOrCreate returns the Hub for a document, creating one if it doesn't exist.
func (m *Manager) GetOrCreate(docID string) *Hub {
	m.mu.RLock()
	if h, ok := m.hubs[docID]; ok {
		m.mu.RUnlock()
		return h
	}
	m.mu.RUnlock()

	m.mu.Lock()
	defer m.mu.Unlock()

	// Double-check after acquiring write lock
	if h, ok := m.hubs[docID]; ok {
		return h
	}

	content := m.fetchContent(docID)
	h := newHub(docID, content, m.pub)
	m.hubs[docID] = h
	go h.run()
	log.Printf("manager: started hub for doc %s", docID)
	return h
}

// fetchContent loads the current document snapshot from Java.
func (m *Manager) fetchContent(docID string) string {
	url := fmt.Sprintf("%s/internal/documents/%s/content", m.javaBaseURL, docID)
	resp, err := http.Get(url)
	if err != nil {
		log.Printf("manager: fetch content %s: %v", docID, err)
		return ""
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		body, _ := io.ReadAll(resp.Body)
		log.Printf("manager: fetch content %s status %d: %s", docID, resp.StatusCode, body)
		return ""
	}

	var result struct {
		Content string `json:"content"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&result); err != nil {
		log.Printf("manager: decode content %s: %v", docID, err)
		return ""
	}
	return result.Content
}
