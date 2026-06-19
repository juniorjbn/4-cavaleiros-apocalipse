# Cavaleiro 4 — Roubar Credenciais (Secrets)

> "Base64 nunca foi criptografia."
> O cluster é temporário. As credenciais sobrevivem.

Esta é a **senha do banco** que o backend do [Cavaleiro 3](cavaleiro-3-network.md) usa para
falar com o `payments-db`. No Cavaleiro 3 garantimos que **só o backend** alcança o banco na rede;
aqui garantimos que nem o backend carrega a senha fixa — ela vem do cofre, curta e rotacionada.

**Ataque:** Secret do Kubernetes é só base64. Qualquer um com permissão de leitura vê em texto puro.
**Defesa:** a senha vive no Vault e é sincronizada sob demanda pelo External Secrets Operator —
nunca em manifest/git.

Pré-requisito: `./setup.sh` já instalou o ESO e o Vault (dev-mode, token `root`).

---

## Roteiro

### 1. A senha do banco do jeito ingênuo
```bash
kubectl apply -f insecure-secret.yaml
```

### 2. "Roubar" a senha é um comando
```bash
kubectl -n c4-secrets get secret db-credentials -o jsonpath='{.data.password}' | base64 -d; echo
```
*Resultado esperado:* a senha do banco aparece em **texto puro**.
*Fala:* "Não está criptografada, está codificada. E essa é a senha do banco que o backend usa. Quem lê secrets, lê o banco inteiro."

### 3. A defesa: a senha vai para o cofre (Vault)
```bash
kubectl -n vault exec vault-0 -- sh -c \
  'VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root vault kv put secret/db password=senha-ROTACIONADA-pelo-vault'
```

### 4. Conecta o cluster ao cofre (External Secrets Operator)
```bash
kubectl -n c4-secrets create secret generic vault-token --from-literal=token=root
kubectl apply -f secretstore.yaml
kubectl apply -f externalsecret.yaml
```

### 5. O ESO materializa a senha — sem ela estar no git
```bash
kubectl -n c4-secrets get externalsecret
kubectl -n c4-secrets get secret db-credentials-managed -o jsonpath='{.data.password}' | base64 -d; echo
```
*Resultado esperado:* `db-credentials-managed` existe, com o valor que veio **do Vault** (e que nunca passou por um manifest). É essa credencial que o backend consumiria.
*Fala:* "A senha não mora mais no cluster nem no repositório. Mora no cofre, e o backend pega emprestado quando precisa — com rotação automática."

---

## Reset
```bash
kubectl delete -f externalsecret.yaml -f secretstore.yaml -f insecure-secret.yaml --ignore-not-found
kubectl -n c4-secrets delete secret vault-token db-credentials-managed --ignore-not-found
```

## Produção (o que muda)
- **Nada de token estático.** Troque o `tokenSecretRef` por Kubernetes auth / AppRole / **Workload Identity** (a identidade vem da própria carga, sem segredo de bootstrap).
- **Credenciais dinâmicas:** o Vault pode emitir usuário/senha de banco **sob demanda, com TTL curto** (database secrets engine) — a senha que vaza expira sozinha.
- Vault aqui está em **dev-mode** (memória, token `root`) — só para a demo. Em produção: HA, storage persistente, unseal, auditoria.
- Alternativa mais leve para começar: **Sealed Secrets** (criptografa o segredo para poder versioná-lo no git com segurança).

---

[I · Entrar](cavaleiro-1-supply-chain.md) · [II · Executar](cavaleiro-2-privileged.md) · [III · Movimentar](cavaleiro-3-network.md) · **IV · Roubar**