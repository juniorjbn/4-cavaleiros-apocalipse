# Cavaleiro 4 — Roubar Credenciais (Secrets)

> "Base64 nunca foi criptografia."
> O cluster é temporário. As credenciais sobrevivem.

**Ataque:** Secret do Kubernetes é só base64. Qualquer um com permissão de leitura vê o valor em claro.
**Defesa:** o segredo vive num cofre (Vault) e é sincronizado sob demanda pelo External Secrets Operator — nunca em manifest/git.

Pré-requisito: `./setup.sh` já instalou o ESO e o Vault (dev-mode, token `root`).

---

## Roteiro

### 1. O segredo do jeito ingênuo
```bash
kubectl apply -f insecure-secret.yaml
```

### 2. "Roubar" o segredo é um comando
```bash
kubectl -n c4-secrets get secret payments-api -o jsonpath='{.data.api-key}' | base64 -d; echo
```
*Resultado esperado:* a chave aparece em **texto puro**.
*Fala:* "Não está criptografado. Está *codificado*. Quem controla os segredos controla o ambiente. A pergunta não é *se* existem secrets expostos — é *quantos*."

### 3. A defesa: o segredo vai para o cofre (Vault)
```bash
kubectl -n vault exec vault-0 -- sh -c \
  'VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root vault kv put secret/payments api-key=sk-live-ROTACIONADA-pelo-vault'
```

### 4. Conecta o cluster ao cofre (External Secrets Operator)
```bash
kubectl -n c4-secrets create secret generic vault-token --from-literal=token=root
kubectl apply -f secretstore.yaml
kubectl apply -f externalsecret.yaml
```

### 5. O ESO materializa o segredo — sem ele estar no git
```bash
kubectl -n c4-secrets get externalsecret
kubectl -n c4-secrets get secret payments-api-managed -o jsonpath='{.data.api-key}' | base64 -d; echo
```
*Resultado esperado:* `payments-api-managed` existe, com o valor que veio **do Vault** (e que nunca passou por um manifest).
*Fala:* "O segredo não mora mais no cluster nem no repositório. Mora no cofre, e o cluster pega emprestado quando precisa — com rotação automática."

---

## Reset
```bash
kubectl delete -f externalsecret.yaml -f secretstore.yaml -f insecure-secret.yaml --ignore-not-found
kubectl -n c4-secrets delete secret vault-token payments-api-managed --ignore-not-found
```

## Produção (o que muda)
- **Nada de token estático.** Troque o `tokenSecretRef` por Kubernetes auth / AppRole / **Workload Identity** (a identidade vem da própria carga, sem segredo de bootstrap).
- Vault aqui está em **dev-mode** (dados em memória, token `root`) — apenas para a demo. Em produção: HA, storage persistente, unseal, auditoria.
- Alternativa mais leve para começar: **Sealed Secrets** (criptografa o segredo para poder versioná-lo no git com segurança).
