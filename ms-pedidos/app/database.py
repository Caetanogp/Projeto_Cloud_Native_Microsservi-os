from datetime import datetime, timezone
from decimal import Decimal

from sqlalchemy import DateTime, Integer, Numeric, String, create_engine
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker

from app.config import DATABASE_URL

engine = create_engine(DATABASE_URL, pool_pre_ping=True, pool_size=5, max_overflow=5)
SessionLocal = sessionmaker(bind=engine, expire_on_commit=False)


def agora() -> datetime:
    return datetime.now(timezone.utc)


class Base(DeclarativeBase):
    pass


class Pedido(Base):
    __tablename__ = "pedidos"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    cliente: Mapped[str] = mapped_column(String(120), nullable=False)
    produto_id: Mapped[int] = mapped_column(Integer, nullable=False)
    produto_nome: Mapped[str] = mapped_column(String(120), nullable=False)
    quantidade: Mapped[int] = mapped_column(Integer, nullable=False)
    preco_unitario: Mapped[Decimal] = mapped_column(Numeric(10, 2), nullable=False)
    total: Mapped[Decimal] = mapped_column(Numeric(12, 2), nullable=False)
    status: Mapped[str] = mapped_column(String(30), nullable=False, default="CRIADO")
    criado_por_pod: Mapped[str] = mapped_column(String(120), nullable=False)
    criado_em: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=agora)
    atualizado_em: Mapped[datetime] = mapped_column(DateTime(timezone=True), default=agora, onupdate=agora)
