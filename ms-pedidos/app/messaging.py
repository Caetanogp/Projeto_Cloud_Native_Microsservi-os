import json
import logging
import time

import pika

from app import config

log = logging.getLogger("ms-pedidos.rabbitmq")


def _conectar() -> pika.BlockingConnection:
    credenciais = pika.PlainCredentials(config.RABBITMQ_USER, config.RABBITMQ_PASSWORD)
    parametros = pika.ConnectionParameters(
        host=config.RABBITMQ_HOST,
        port=config.RABBITMQ_PORT,
        credentials=credenciais,
        heartbeat=30,
        blocked_connection_timeout=10,
        socket_timeout=5,
    )
    return pika.BlockingConnection(parametros)


def _declarar_topologia(canal) -> None:
    """Declara exchange, fila principal (com DLQ) e bindings. Idempotente."""
    canal.exchange_declare(exchange=config.EXCHANGE, exchange_type="topic", durable=True)
    canal.exchange_declare(exchange=config.DLX, exchange_type="direct", durable=True)
    canal.queue_declare(queue=config.DLQ, durable=True)
    canal.queue_bind(queue=config.DLQ, exchange=config.DLX, routing_key=config.DLQ_ROUTING_KEY)
    canal.queue_declare(
        queue=config.QUEUE,
        durable=True,
        arguments={
            "x-dead-letter-exchange": config.DLX,
            "x-dead-letter-routing-key": config.DLQ_ROUTING_KEY,
        },
    )
    canal.queue_bind(queue=config.QUEUE, exchange=config.EXCHANGE, routing_key=config.ROUTING_KEY)


def publicar_pedido_criado(evento: dict, tentativas: int = 3) -> None:
    """Publica o evento `pedido.criado` com confirmação do broker (publisher confirms)."""
    corpo = json.dumps(evento, ensure_ascii=False).encode("utf-8")
    ultimo_erro: Exception | None = None
    for tentativa in range(1, tentativas + 1):
        try:
            conexao = _conectar()
            try:
                canal = conexao.channel()
                canal.confirm_delivery()
                _declarar_topologia(canal)
                canal.basic_publish(
                    exchange=config.EXCHANGE,
                    routing_key=config.ROUTING_KEY,
                    body=corpo,
                    properties=pika.BasicProperties(
                        content_type="application/json",
                        delivery_mode=pika.DeliveryMode.Persistent,
                    ),
                    mandatory=True,
                )
            finally:
                conexao.close()
            log.info("mensagem pedido.criado publicada (pedido %s)", evento.get("pedidoId"))
            return
        except Exception as erro:  # noqa: BLE001 - qualquer falha de rede/broker entra no retry
            ultimo_erro = erro
            log.warning("falha ao publicar no RabbitMQ (tentativa %d/%d): %s", tentativa, tentativas, erro)
            time.sleep(1)
    raise RuntimeError(f"não foi possível publicar no RabbitMQ: {ultimo_erro}")


def rabbitmq_disponivel() -> bool:
    try:
        _conectar().close()
        return True
    except Exception:  # noqa: BLE001
        return False
