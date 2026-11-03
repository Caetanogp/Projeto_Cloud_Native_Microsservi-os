package br.edu.loja.notificacoes.model;

import java.util.List;
import java.util.Optional;

import org.springframework.data.mongodb.repository.MongoRepository;

public interface NotificacaoRepository extends MongoRepository<Notificacao, String> {

    Optional<Notificacao> findFirstByPedidoId(Long pedidoId);

    List<Notificacao> findAllByOrderByProcessadoEmDesc();
}
