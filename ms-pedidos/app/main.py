import logging
import threading
import time
from contextlib import asynccontextmanager
from datetime import datetime
from decimal import Decimal
from typing import Literal

import httpx
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import select, text

from app import config, messaging
from app.database import Base, Pedido, SessionLocal, engine

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s [%(name)s] %(message)s")
log = logging.getLogger("ms-pedidos")

pronto = threading.Event()


def inicializar_banco() -> None:
    """Cria as tabelas; tenta de novo enquanto o PostgreSQL ainda está subindo."""
    tentativa = 0
    while True:
        tentativa += 1
        try:
            Base.metadata.create_all(engine)
            pronto.set()
            log.info("banco inicializado")
            return
        except Exception as erro:  # noqa: BLE001
            log.warning("aguardando PostgreSQL (tentativa %d): %s", tentativa, erro.__class__.__name__)
            time.sleep(3)


@asynccontextmanager
async def lifespan(_: FastAPI):
    threading.Thread(target=inicializar_banco, daemon=True).start()
    yield


app = FastAPI(title="ms-pedidos", description="Microsserviço de pedidos (FastAPI + PostgreSQL)", lifespan=lifespan)


@app.middleware("http")
async def header_pod(request: Request, call_next):
    resposta = await call_next(request)
    resposta.headers["X-Pod-Name"] = config.POD_NAME
    return resposta


class NovoPedido(BaseModel):
    cliente: str = Field(min_length=1, max_length=120)
    produto_id: int = Field(gt=0)
    quantidade: int = Field(gt=0)


class AtualizaStatus(BaseModel):
    status: Literal["CRIADO", "CONFIRMADO", "CANCELADO", "ERRO_PUBLICACAO"]


class PedidoOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    cliente: str
    produto_id: int
    produto_nome: str
    quantidade: int
    preco_unitario: Decimal
    total: Decimal
    status: str
    criado_por_pod: str
    criado_em: datetime
    atualizado_em: datetime


def _json_pedido(pedido: Pedido) -> dict:
    return PedidoOut.model_validate(pedido).model_dump(mode="json")


# Probes do Kubernetes
@app.get("/health")
def health():
    return {"status": "UP", "pod": config.POD_NAME}


@app.get("/ready")
def ready():
    try:
        if not pronto.is_set():
            raise RuntimeError("banco ainda não inicializado")
        with engine.connect() as conexao:
            conexao.execute(text("SELECT 1"))
        return {"status": "READY", "pod": config.POD_NAME}
    except Exception as erro:  # noqa: BLE001
        return JSONResponse(status_code=503, content={"status": "NOT_READY", "pod": config.POD_NAME, "erro": str(erro)})


@app.post("/pedidos", status_code=201)
def criar_pedido(dados: NovoPedido):
    # 1) REST síncrono: reserva o estoque no catálogo (balanceado entre as réplicas do ms-catalogo)
    try:
        resposta = httpx.post(
            f"{config.CATALOGO_URL}/produtos/{dados.produto_id}/reservar",
            json={"quantidade": dados.quantidade},
            timeout=5.0,
        )
    except httpx.HTTPError as erro:
        log.error("catálogo indisponível: %s", erro)
        raise HTTPException(status_code=502, detail="ms-catalogo indisponível") from erro

    if resposta.status_code == 404:
        raise HTTPException(status_code=404, detail="Produto não encontrado no catálogo")
    if resposta.status_code == 409:
        raise HTTPException(status_code=409, detail="Estoque insuficiente")
    if resposta.status_code != 200:
        raise HTTPException(status_code=502, detail=f"Erro inesperado do catálogo ({resposta.status_code})")

    corpo = resposta.json()
    produto = corpo["produto"]
    catalogo_pod = corpo.get("pod")
    preco = Decimal(str(produto["preco"]))

    # 2) Persiste o pedido no PostgreSQL (banco exclusivo deste serviço)
    with SessionLocal() as sessao:
        pedido = Pedido(
            cliente=dados.cliente,
            produto_id=produto["id"],
            produto_nome=produto["nome"],
            quantidade=dados.quantidade,
            preco_unitario=preco,
            total=preco * dados.quantidade,
            status="CRIADO",
            criado_por_pod=config.POD_NAME,
        )
        sessao.add(pedido)
        sessao.commit()
        sessao.refresh(pedido)

        # 3) Assíncrono: publica o evento no RabbitMQ para o ms-notificacoes processar
        evento = {
            "pedidoId": pedido.id,
            "cliente": pedido.cliente,
            "produtoId": pedido.produto_id,
            "produtoNome": pedido.produto_nome,
            "quantidade": pedido.quantidade,
            "total": float(pedido.total),
            "criadoEm": pedido.criado_em.isoformat(),
            "origemPod": config.POD_NAME,
        }
        try:
            messaging.publicar_pedido_criado(evento)
        except RuntimeError as erro:
            pedido.status = "ERRO_PUBLICACAO"
            sessao.commit()
            log.error("pedido %s salvo, mas a publicação falhou: %s", pedido.id, erro)
            return JSONResponse(
                status_code=502,
                content={
                    "pod": config.POD_NAME,
                    "catalogo_pod": catalogo_pod,
                    "erro": "Pedido salvo, mas a mensagem não foi publicada no RabbitMQ",
                    "pedido": _json_pedido(pedido),
                },
            )

        log.info("pedido %s criado (catálogo respondeu pelo pod %s)", pedido.id, catalogo_pod)
        return {"pod": config.POD_NAME, "catalogo_pod": catalogo_pod, "pedido": _json_pedido(pedido)}


@app.get("/pedidos")
def listar_pedidos():
    with SessionLocal() as sessao:
        pedidos = sessao.scalars(select(Pedido).order_by(Pedido.id.desc())).all()
        return {"pod": config.POD_NAME, "total": len(pedidos), "pedidos": [_json_pedido(p) for p in pedidos]}


@app.get("/pedidos/{pedido_id}")
def obter_pedido(pedido_id: int):
    with SessionLocal() as sessao:
        pedido = sessao.get(Pedido, pedido_id)
        if pedido is None:
            raise HTTPException(status_code=404, detail="Pedido não encontrado")
        return {"pod": config.POD_NAME, "pedido": _json_pedido(pedido)}


# Chamado pelo ms-notificacoes (REST) depois de processar a mensagem do RabbitMQ.
@app.patch("/pedidos/{pedido_id}/status")
def atualizar_status(pedido_id: int, dados: AtualizaStatus):
    with SessionLocal() as sessao:
        pedido = sessao.get(Pedido, pedido_id)
        if pedido is None:
            raise HTTPException(status_code=404, detail="Pedido não encontrado")
        pedido.status = dados.status
        sessao.commit()
        sessao.refresh(pedido)
        log.info("pedido %s -> %s", pedido.id, pedido.status)
        return {"pod": config.POD_NAME, "pedido": _json_pedido(pedido)}
