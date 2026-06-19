package mq

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"time"

	amqp "github.com/rabbitmq/amqp091-go"
)

const exchange = "collab"

// OpEvent is published to RabbitMQ for each confirmed document operation.
type OpEvent struct {
	DocID     string `json:"docId"`
	UserID    string `json:"userId"`
	Version   int    `json:"version"`
	Type      string `json:"type"`
	Pos       int    `json:"pos"`
	Character string `json:"character,omitempty"`
}

// Publisher wraps an AMQP channel for publishing collab events.
type Publisher struct {
	conn *amqp.Connection
	ch   *amqp.Channel
}

func NewPublisher(amqpURL string) (*Publisher, error) {
	conn, err := amqp.Dial(amqpURL)
	if err != nil {
		return nil, fmt.Errorf("dial: %w", err)
	}
	ch, err := conn.Channel()
	if err != nil {
		conn.Close()
		return nil, fmt.Errorf("channel: %w", err)
	}

	// Declare exchange — idempotent
	if err := ch.ExchangeDeclare(exchange, "topic", true, false, false, false, nil); err != nil {
		conn.Close()
		return nil, fmt.Errorf("exchange declare: %w", err)
	}

	log.Println("mq: publisher connected")
	return &Publisher{conn: conn, ch: ch}, nil
}

// PublishOp publishes an operation event to three routing keys:
// op.persist (persistence), op.spell (spell check), op.metric (metrics).
func (p *Publisher) PublishOp(ev OpEvent) {
	body, err := json.Marshal(ev)
	if err != nil {
		log.Printf("mq: marshal error: %v", err)
		return
	}

	keys := []string{"op.persist", "op.spell", "op.metric"}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()

	for _, key := range keys {
		if err := p.ch.PublishWithContext(ctx, exchange, key, false, false,
			amqp.Publishing{
				ContentType:  "application/json",
				DeliveryMode: amqp.Persistent,
				Body:         body,
			}); err != nil {
			log.Printf("mq: publish to %s failed: %v", key, err)
		}
	}
}

func (p *Publisher) Close() {
	p.ch.Close()
	p.conn.Close()
}
