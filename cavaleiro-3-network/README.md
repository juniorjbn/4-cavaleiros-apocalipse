# Cavaleiro 3 — Movimentar (Network Policies)

> "Sem Network Policy, cada pod vira um ponto de partida."
> Movimentação lateral é o verdadeiro superpoder do atacante.

Topologia de 3 camadas — como deveria ser:

```
frontend  →  backend  →  payments-db
(exposto)     (API)        (banco)
```

O **frontend nunca deveria tocar o banco** direto; quem fala com o banco é o **backend**.
**Ataque:** sem segmentação, o frontend comprometido pula o backend e vai direto no banco.
**Defesa:** segmentar por camada — o frontend só alcança o backend; só o backend alcança o banco.

> Requer um CNI que aplique NetworkPolicy. Este ambiente usa **Calico** (o `kindnet` padrão do kind ignora). Já vem pronto pelo `./setup.sh`.

---

## Roteiro

### 1. O cenário: frontend, backend e banco
```bash
kubectl apply -f app.yaml
kubectl -n c3-network get pods -w
```
Espere os 3 pods ficarem `Running` (Ctrl+C para sair do `-w`). `frontend` é o pod comprometido.

### 2. O frontend comprometido vai DIRETO no banco (lateral)
```bash
kubectl -n c3-network exec frontend -- wget -qO- http://payments-db:8080
```
*Resultado esperado:* o frontend recebe o conteúdo sensível do banco — pulando o backend.
*Fala:* "Esse pod nunca deveria falar com o banco. Mas a rede é plana, então ele fala. Se tudo conversa com tudo, qualquer invasão escala."

### 3. A defesa: segmentar por camada
```bash
kubectl apply -f default-deny.yaml
kubectl apply -f allow.yaml
```
`default-deny` corta tudo; `allow` libera só `frontend→backend` e `backend→db`.

### 4. O atacante perde o banco — e não volta
```bash
kubectl -n c3-network exec frontend -- wget -qO- -T 5 http://payments-db:8080
```
*Resultado esperado:* **timeout**. O frontend está cortado do banco. E continua cortado — não há regra que o devolva.
*Fala:* "O frontend não tem mais caminho para o banco. Nunca deveria ter tido."

### 5. Mas o serviço continua de pé
```bash
kubectl -n c3-network exec backend -- wget -qO- http://payments-db:8080
kubectl -n c3-network exec frontend -- wget -qO- http://backend:8080
```
*Resultado esperado:* o **backend** continua lendo o banco (caminho legítimo), e o **frontend** continua falando com o backend (caminho normal). Só o atalho perigoso sumiu.
*Fala:* "Zero Trust não derruba o serviço. Derruba os caminhos que não deviam existir."

---

## Reset
```bash
kubectl delete -f allow.yaml -f default-deny.yaml -f app.yaml --ignore-not-found
```

## Notas
- A segmentação é por **label** (`tier: frontend|backend|db`), não por IP. O `db-ingress` só aceita `tier: backend` — o frontend nunca entra.
- `default-deny` também corta o **DNS**; por isso o `allow.yaml` reabre a porta 53, senão os nomes nem resolvem.
- **Camada seguinte (Cavaleiro 4):** mesmo o backend não usa senha fixa para o banco — ele pega uma credencial **curta e rotacionada** do Vault. Rede + segredo = defesa em profundidade: para roubar o banco, o atacante teria que furar a segmentação **e** roubar uma senha que expira.
