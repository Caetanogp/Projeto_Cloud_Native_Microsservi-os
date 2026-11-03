package br.edu.loja.notificacoes.config;

import org.springframework.amqp.core.Binding;
import org.springframework.amqp.core.BindingBuilder;
import org.springframework.amqp.core.DirectExchange;
import org.springframework.amqp.core.Queue;
import org.springframework.amqp.core.QueueBuilder;
import org.springframework.amqp.core.TopicExchange;
import org.springframework.amqp.support.converter.Jackson2JsonMessageConverter;
import org.springframework.amqp.support.converter.MessageConverter;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

/**
 * Topologia AMQP. Precisa ser idêntica à declarada pelo ms-pedidos (app/messaging.py),
 * senão o RabbitMQ recusa a declaração com PRECONDITION_FAILED.
 */
@Configuration
public class RabbitConfig {

    public static final String EXCHANGE = "pedidos";
    public static final String ROUTING_KEY = "pedido.criado";
    public static final String QUEUE = "pedidos.criados";
    public static final String DLX = "pedidos.dlx";
    public static final String DLQ = "pedidos.criados.dlq";
    public static final String DLQ_ROUTING_KEY = "pedido.falhou";

    @Bean
    TopicExchange pedidosExchange() {
        return new TopicExchange(EXCHANGE, true, false);
    }

    @Bean
    DirectExchange deadLetterExchange() {
        return new DirectExchange(DLX, true, false);
    }

    @Bean
    Queue pedidosCriadosQueue() {
        return QueueBuilder.durable(QUEUE)
                .withArgument("x-dead-letter-exchange", DLX)
                .withArgument("x-dead-letter-routing-key", DLQ_ROUTING_KEY)
                .build();
    }

    @Bean
    Queue pedidosCriadosDlq() {
        return QueueBuilder.durable(DLQ).build();
    }

    @Bean
    Binding pedidosCriadosBinding() {
        return BindingBuilder.bind(pedidosCriadosQueue()).to(pedidosExchange()).with(ROUTING_KEY);
    }

    @Bean
    Binding pedidosCriadosDlqBinding() {
        return BindingBuilder.bind(pedidosCriadosDlq()).to(deadLetterExchange()).with(DLQ_ROUTING_KEY);
    }

    @Bean
    MessageConverter jsonMessageConverter() {
        return new Jackson2JsonMessageConverter();
    }
}
