package br.edu.loja.notificacoes.listener;

import java.time.Instant;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.rabbit.annotation.RabbitListener;
import org.springframework.stereotype.Component;

import br.edu.loja.notificacoes.client.PedidosClient;
import br.edu.loja.notificacoes.config.RabbitConfig;
import br.edu.loja.notificacoes.model.Notificacao;
import br.edu.loja.notificacoes.model.NotificacaoRepository;
import br.edu.loja.notificacoes.model.PedidoCriadoEvent;
import br.edu.loja.notificacoes.web.PodInfo;

/**
 * Consome `pedido.criado`: grava a notificação no MongoDB e confirma o pedido no ms-pedidos via REST.
 * Se algo falhar, o listener tenta 3 vezes e depois a mensagem vai para a DLQ.
 */
@Component
public class PedidoCriadoListener {

    private static final Logger log = LoggerFactory.getLogger(PedidoCriadoListener.class);

    private final NotificacaoRepository repository;
    private final PedidosClient pedidosClient;
    private final PodInfo pod;

    public PedidoCriadoListener(NotificacaoRepository repository, PedidosClient pedidosClient, PodInfo pod) {
        this.repository = repository;
        this.pedidosClient = pedidosClient;
        this.pod = pod;
    }

    @RabbitListener(queues = RabbitConfig.QUEUE)
    public void processar(PedidoCriadoEvent evento) {
        log.info("[{}] mensagem recebida: pedido {} de {} ({}x {})", pod.nome(), evento.pedidoId(),
                evento.cliente(), evento.quantidade(), evento.produtoNome());

        // Idempotente: se a mensagem for reentregue, não duplica a notificação.
        repository.findFirstByPedidoId(evento.pedidoId()).orElseGet(() -> {
            String mensagem = String.format("Olá, %s! Recebemos seu pedido #%d (%dx %s, total R$ %.2f).",
                    evento.cliente(), evento.pedidoId(), evento.quantidade(), evento.produtoNome(), evento.total());
            Notificacao salva = repository.save(new Notificacao(null, evento.pedidoId(), evento.cliente(),
                    evento.produtoNome(), evento.quantidade(), evento.total(), mensagem, "PROCESSADA",
                    Instant.now(), pod.nome()));
            log.info("[{}] notificação gravada no MongoDB para o pedido {}", pod.nome(), evento.pedidoId());
            return salva;
        });

        // REST síncrono de volta ao ms-pedidos. Exceção aqui aciona o retry e, por fim, a DLQ.
        pedidosClient.confirmarPedido(evento.pedidoId());
        log.info("[{}] pedido {} confirmado no ms-pedidos", pod.nome(), evento.pedidoId());
    }
}
