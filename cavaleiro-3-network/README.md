# Cavaleiro 3 — Movimentar (Network Policies)

> "Sem Network Policy, cada pod vira um ponto de partida."
> Movimentação lateral é o verdadeiro superpoder do atacante.

**Ataque:** sem segmentação, o pod comprometido conversa com tudo — inclusive o banco interno.
**Defesa:** `default-deny` + liberar só o necessário. Zero Trust começa **dentro** do cluster.

> Requer um CNI que aplique NetworkPolicy. Este ambiente usa **Calico** (o `kindnet` padrão do kind ignora NetworkPolicy). Já vem pronto pelo `./setup.sh`.

---

## Roteiro

### 1. O cenário: um frontend e um banco interno
```bash
kubectl apply -f app.yaml
kubectl -n c3-network get pods
```
`payments-db` responde um "segredo"; `frontend` é o pod que o atacante comprometeu.

### 2. O pod comprometido alcança o banco (movimentação lateral)
```bash
kubectl -n c3-network exec frontend -- wget -qO- http://payments-db:8080
```
*Resultado esperado:* o frontend recebe o conteúdo sensível do `payments-db`.
*Fala:* "O atacante não precisa procurar o banco de dados. O cluster mostra o caminho. Se tudo fala com tudo, qualquer invasão escala."

### 3. Default deny: ninguém fala com ninguém
```bash
kubectl apply -f default-deny.yaml
kubectl -n c3-network exec frontend -- wget -qO- -T 5 http://payments-db:8080
```
*Resultado esperado:* a conexão **trava e falha** (timeout).
*Fala:* "Zero Trust não começa no firewall da borda. Começa aqui dentro."

### 4. Libera só o caminho legítimo
```bash
kubectl apply -f allow.yaml
kubectl -n c3-network exec frontend -- wget -qO- http://payments-db:8080
```
*Resultado esperado:* o acesso **legítimo** volta a funcionar — e somente ele.
*Fala:* "A regra não é bloquear tudo para sempre. É liberar exatamente o que precisa, e mais nada."

---

## Reset
```bash
kubectl delete -f allow.yaml -f default-deny.yaml -f app.yaml --ignore-not-found
```

## Notas
- `default-deny` seleciona todos os pods (`podSelector: {}`) e nega `Ingress` + `Egress`. Por isso o `allow.yaml` precisa reabrir o **DNS** (porta 53), senão o nome `payments-db` nem resolve.
- NetworkPolicy é **aditiva**: várias policies se somam. Não existe "ordem" nem "deny explícito" — o que não for permitido por nenhuma policy fica bloqueado.
