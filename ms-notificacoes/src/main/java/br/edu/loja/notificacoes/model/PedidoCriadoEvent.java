package br.edu.loja.notificacoes.model;

import java.math.BigDecimal;

import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

/** Mensagem `pedido.criado` publicada pelo ms-pedidos no RabbitMQ. */
@JsonIgnoreProperties(ignoreUnknown = true)
public record PedidoCriadoEvent(
        Long pedidoId,
        String cliente,
        Long produtoId,
        String produtoNome,
        Integer quantidade,
        BigDecimal total,
        String criadoEm,
        String origemPod) {
}
