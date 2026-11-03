package br.edu.loja.notificacoes.model;

import java.math.BigDecimal;
import java.time.Instant;

import org.springframework.data.annotation.Id;
import org.springframework.data.mongodb.core.index.Indexed;
import org.springframework.data.mongodb.core.mapping.Document;

/** Notificação gravada no MongoDB (banco exclusivo do ms-notificacoes). */
@Document("notificacoes")
public record Notificacao(
        @Id String id,
        @Indexed(unique = true) Long pedidoId, // garante idempotência: uma notificação por pedido
        String cliente,
        String produtoNome,
        Integer quantidade,
        BigDecimal total,
        String mensagem,
        String status,
        Instant processadoEm,
        String processadoPorPod) {
}
