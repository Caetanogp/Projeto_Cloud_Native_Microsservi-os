package br.edu.loja.notificacoes.web;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.bson.Document;
import org.springframework.data.mongodb.core.MongoTemplate;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RestController;

import br.edu.loja.notificacoes.model.Notificacao;
import br.edu.loja.notificacoes.model.NotificacaoRepository;

@RestController
public class NotificacoesController {

    private final NotificacaoRepository repository;
    private final MongoTemplate mongoTemplate;
    private final PodInfo pod;

    public NotificacoesController(NotificacaoRepository repository, MongoTemplate mongoTemplate, PodInfo pod) {
        this.repository = repository;
        this.mongoTemplate = mongoTemplate;
        this.pod = pod;
    }

    // Probes do Kubernetes
    @GetMapping("/health")
    public Map<String, Object> health() {
        return Map.of("status", "UP", "pod", pod.nome());
    }

    @GetMapping("/ready")
    public ResponseEntity<Map<String, Object>> ready() {
        try {
            mongoTemplate.getDb().runCommand(new Document("ping", 1));
            return ResponseEntity.ok(Map.of("status", "READY", "pod", pod.nome()));
        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE)
                    .body(Map.of("status", "NOT_READY", "pod", pod.nome(), "erro", String.valueOf(e.getMessage())));
        }
    }

    @GetMapping("/notificacoes")
    public Map<String, Object> listar() {
        List<Notificacao> notificacoes = repository.findAllByOrderByProcessadoEmDesc();
        Map<String, Object> corpo = new LinkedHashMap<>();
        corpo.put("pod", pod.nome());
        corpo.put("total", notificacoes.size());
        corpo.put("notificacoes", notificacoes);
        return corpo;
    }

    @GetMapping("/notificacoes/pedido/{pedidoId}")
    public ResponseEntity<Map<String, Object>> porPedido(@PathVariable Long pedidoId) {
        return repository.findFirstByPedidoId(pedidoId)
                .map(n -> ResponseEntity.ok(Map.<String, Object>of("pod", pod.nome(), "notificacao", n)))
                .orElseGet(() -> ResponseEntity.status(HttpStatus.NOT_FOUND)
                        .body(Map.<String, Object>of("pod", pod.nome(), "erro", "Notificação não encontrada para o pedido")));
    }
}
