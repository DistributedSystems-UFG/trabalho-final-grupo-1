package br.ufg.collabdocs.config;

import org.springframework.amqp.core.*;
import org.springframework.amqp.rabbit.connection.ConnectionFactory;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.amqp.support.converter.Jackson2JsonMessageConverter;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class RabbitMQConfig {

    public static final String EXCHANGE    = "collab";
    public static final String Q_PERSIST   = "q.ops.persist";
    public static final String Q_SPELL     = "q.ops.spell";
    public static final String Q_METRIC    = "q.ops.metric";

    @Bean
    TopicExchange collabExchange() {
        return ExchangeBuilder.topicExchange(EXCHANGE).durable(true).build();
    }

    @Bean Queue persistQueue()  { return QueueBuilder.durable(Q_PERSIST).build(); }
    @Bean Queue spellQueue()    { return QueueBuilder.durable(Q_SPELL).build(); }
    @Bean Queue metricQueue()   { return QueueBuilder.durable(Q_METRIC).build(); }

    @Bean Binding persistBinding(Queue persistQueue, TopicExchange collabExchange) {
        return BindingBuilder.bind(persistQueue).to(collabExchange).with("op.persist");
    }
    @Bean Binding spellBinding(Queue spellQueue, TopicExchange collabExchange) {
        return BindingBuilder.bind(spellQueue).to(collabExchange).with("op.spell");
    }
    @Bean Binding metricBinding(Queue metricQueue, TopicExchange collabExchange) {
        return BindingBuilder.bind(metricQueue).to(collabExchange).with("op.metric");
    }

    @Bean
    Jackson2JsonMessageConverter messageConverter() {
        return new Jackson2JsonMessageConverter();
    }

    @Bean
    RabbitTemplate rabbitTemplate(ConnectionFactory cf) {
        var template = new RabbitTemplate(cf);
        template.setMessageConverter(messageConverter());
        return template;
    }
}
