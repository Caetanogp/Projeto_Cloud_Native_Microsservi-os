'use strict';

const os = require('os');
const express = require('express');
const mysql = require('mysql2/promise');

const PORT = Number(process.env.PORT || 3000);
// Nome do Pod (Downward API no Kubernetes). Fora do cluster usa o hostname do container.
const POD = process.env.POD_NAME || os.hostname();

const pool = mysql.createPool({
  host: process.env.DB_HOST || 'mysql-catalogo',
  port: Number(process.env.DB_PORT || 3306),
  user: process.env.DB_USER || 'catalogo',
  password: process.env.DB_PASSWORD || 'catalogo123',
  database: process.env.DB_NAME || 'catalogo',
  waitForConnections: true,
  connectionLimit: 10,
  decimalNumbers: true,
});

const PRODUTOS_INICIAIS = [
  ['Notebook Dell Inspiron', 4599.9, 25],
  ['Mouse Logitech MX Master', 449.9, 80],
  ['Teclado Mecânico Keychron', 599.0, 40],
  ['Monitor LG 27" 4K', 1899.0, 15],
  ['Headset HyperX Cloud', 349.9, 60],
];

let pronto = false;

const dormir = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// Cria o schema e popula os dados iniciais. Tenta de novo enquanto o MySQL ainda sobe.
async function inicializarBanco() {
  for (let tentativa = 1; ; tentativa++) {
    try {
      await pool.query(`
        CREATE TABLE IF NOT EXISTS produtos (
          id INT AUTO_INCREMENT PRIMARY KEY,
          nome VARCHAR(120) NOT NULL UNIQUE,
          preco DECIMAL(10,2) NOT NULL,
          estoque INT NOT NULL DEFAULT 0
        )`);
      // INSERT IGNORE + UNIQUE(nome): seguro quando várias réplicas iniciam ao mesmo tempo.
      await pool.query('INSERT IGNORE INTO produtos (nome, preco, estoque) VALUES ?', [PRODUTOS_INICIAIS]);
      pronto = true;
      console.log(`[${POD}] banco inicializado`);
      return;
    } catch (err) {
      console.log(`[${POD}] aguardando MySQL (tentativa ${tentativa}): ${err.code || err.message}`);
      await dormir(3000);
    }
  }
}

const app = express();
app.use(express.json());

// Header com o Pod que respondeu: evidência de balanceamento entre réplicas.
app.use((req, res, next) => {
  res.set('X-Pod-Name', POD);
  next();
});

// Probes do Kubernetes
app.get('/health', (req, res) => res.json({ status: 'UP', pod: POD }));
app.get('/ready', async (req, res) => {
  try {
    if (!pronto) throw new Error('banco ainda não inicializado');
    await pool.query('SELECT 1');
    res.json({ status: 'READY', pod: POD });
  } catch (err) {
    res.status(503).json({ status: 'NOT_READY', pod: POD, erro: err.message });
  }
});

app.get('/produtos', async (req, res, next) => {
  try {
    const [produtos] = await pool.query('SELECT id, nome, preco, estoque FROM produtos ORDER BY id');
    res.json({ pod: POD, total: produtos.length, produtos });
  } catch (err) {
    next(err);
  }
});

app.get('/produtos/:id(\\d+)', async (req, res, next) => {
  try {
    const [linhas] = await pool.query('SELECT id, nome, preco, estoque FROM produtos WHERE id = ?', [req.params.id]);
    if (linhas.length === 0) return res.status(404).json({ pod: POD, erro: 'Produto não encontrado' });
    res.json({ pod: POD, produto: linhas[0] });
  } catch (err) {
    next(err);
  }
});

app.post('/produtos', async (req, res, next) => {
  try {
    const { nome, preco, estoque = 0 } = req.body || {};
    if (!nome || typeof preco !== 'number' || preco < 0 || !Number.isInteger(estoque) || estoque < 0) {
      return res.status(400).json({ pod: POD, erro: 'Informe nome, preco (número >= 0) e estoque (inteiro >= 0)' });
    }
    const [resultado] = await pool.query('INSERT INTO produtos (nome, preco, estoque) VALUES (?, ?, ?)', [nome, preco, estoque]);
    res.status(201).json({ pod: POD, produto: { id: resultado.insertId, nome, preco, estoque } });
  } catch (err) {
    if (err.code === 'ER_DUP_ENTRY') return res.status(409).json({ pod: POD, erro: 'Já existe um produto com esse nome' });
    next(err);
  }
});

// Chamado pelo ms-pedidos (REST síncrono). Baixa o estoque de forma atômica e devolve o produto com o preço.
app.post('/produtos/:id(\\d+)/reservar', async (req, res, next) => {
  try {
    const quantidade = Number(req.body && req.body.quantidade);
    if (!Number.isInteger(quantidade) || quantidade <= 0) {
      return res.status(400).json({ pod: POD, erro: 'quantidade deve ser um inteiro maior que zero' });
    }
    const [resultado] = await pool.query(
      'UPDATE produtos SET estoque = estoque - ? WHERE id = ? AND estoque >= ?',
      [quantidade, req.params.id, quantidade]
    );
    const [linhas] = await pool.query('SELECT id, nome, preco, estoque FROM produtos WHERE id = ?', [req.params.id]);
    if (linhas.length === 0) return res.status(404).json({ pod: POD, erro: 'Produto não encontrado' });
    if (resultado.affectedRows === 0) {
      return res.status(409).json({ pod: POD, erro: 'Estoque insuficiente', produto: linhas[0] });
    }
    console.log(`[${POD}] reservadas ${quantidade} un. do produto ${linhas[0].id}`);
    res.json({ pod: POD, reservado: quantidade, produto: linhas[0] });
  } catch (err) {
    next(err);
  }
});

app.use((req, res) => res.status(404).json({ pod: POD, erro: 'Rota não encontrada' }));

// eslint-disable-next-line no-unused-vars
app.use((err, req, res, next) => {
  console.error(`[${POD}] erro:`, err);
  res.status(500).json({ pod: POD, erro: 'Erro interno' });
});

const servidor = app.listen(PORT, () => {
  console.log(`[${POD}] ms-catalogo ouvindo na porta ${PORT}`);
  inicializarBanco();
});

function encerrar() {
  console.log(`[${POD}] encerrando...`);
  servidor.close(() => pool.end().finally(() => process.exit(0)));
  setTimeout(() => process.exit(0), 8000).unref();
}
process.on('SIGTERM', encerrar);
process.on('SIGINT', encerrar);
