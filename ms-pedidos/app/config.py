import os
import socket

# Nome do Pod (Downward API no Kubernetes). Fora do cluster usa o hostname do container.
POD_NAME = os.getenv("POD_NAME", socket.gethostname())

DB_HOST = os.getenv("DB_HOST", "postgres-pedidos")
DB_PORT = os.getenv("DB_PORT", "5432")
DB_NAME = os.getenv("DB_NAME", "pedidos")
DB_USER = os.getenv("DB_USER", "pedidos")
DB_PASSWORD = os.getenv("DB_PASSWORD", "pedidos123")
DATABASE_URL = f"postgresql+psycopg://{DB_USER}:{DB_PASSWORD}@{DB_HOST}:{DB_PORT}/{DB_NAME}"

# Service Discovery: o catálogo é acessado pelo nome do Service, nunca por IP de Pod.
CATALOGO_URL = os.getenv("CATALOGO_URL", "http://ms-catalogo:3000")

RABBITMQ_HOST = os.getenv("RABBITMQ_HOST", "rabbitmq")
RABBITMQ_PORT = int(os.getenv("RABBITMQ_PORT", "5672"))
RABBITMQ_USER = os.getenv("RABBITMQ_USER", "loja")
RABBITMQ_PASSWORD = os.getenv("RABBITMQ_PASSWORD", "loja123")

# Topologia AMQP. Precisa ser idêntica à declarada pelo ms-notificacoes (RabbitConfig.java).
EXCHANGE = "pedidos"
ROUTING_KEY = "pedido.criado"
QUEUE = "pedidos.criados"
DLX = "pedidos.dlx"
DLQ = "pedidos.criados.dlq"
DLQ_ROUTING_KEY = "pedido.falhou"
