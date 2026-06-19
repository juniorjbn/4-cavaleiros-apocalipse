# Cavaleiro 1 — Entrar (Supply Chain)

> "O invasor não precisa invadir seu cluster se você fizer o deploy dele."
> `docker pull` é o novo phishing.

**Ataque:** você sobe uma imagem em que confiou sem verificar — e traz o atacante para dentro.
**Defesa:** só admitir imagens **assinadas** (Cosign) + visibilidade do que há dentro (SBOM/scan).

Pré-requisito: `./setup.sh` já rodou (ele publica a imagem suspeita no registry local e instala o Kyverno).

---

## Roteiro

### 1. O deploy do atacante sobe sem fricção
```bash
kubectl apply -f deploy.yaml
kubectl -n c1-supply-chain get pods
```
*Fala:* "Ninguém invadiu nada. Fui **eu** que fiz o deploy. A imagem veio de um registry, tinha um nome amigável, e o cluster confiou."

### 2. O que tem dentro da imagem?
```bash
trivy image --scanners secret localhost:5111/cavaleiro1:suspeita
```
*Resultado esperado:* o trivy aponta um par de credenciais AWS **plantado dentro da imagem**.
*Fala:* "Nem toda imagem pública é open source. Algumas são *open doors*."

### 3. A fronteira de confiança: assinatura
```bash
COSIGN_PASSWORD="" cosign generate-key-pair
```
Gera `cosign.key` (privada) e `cosign.pub` (pública). A política vai exigir que toda imagem seja assinada com essa chave.

### 4. Liga a exigência de assinatura (Kyverno)
```bash
./apply-policy.sh
```
Aplica uma `ClusterPolicy` que **exige assinatura Cosign** para `kind-registry:5111/cavaleiro1*`.

### 5. Tenta subir de novo a imagem NÃO assinada → bloqueado
```bash
kubectl delete -f deploy.yaml
kubectl apply -f deploy.yaml
```
*Resultado esperado:* **`admission webhook ... denied the request`** — a imagem não tem assinatura válida.
*Fala:* "A política não julga se a imagem é boa. Ela exige que **alguém de confiança tenha assinado**. Sem assinatura, não entra."

### 6. Assina a imagem e sobe de novo → passa
```bash
./sign.sh
kubectl apply -f deploy.yaml
kubectl -n c1-supply-chain get pods
```
*Fala:* "A mesma imagem, agora assinada, é admitida. O malware moderno chega por CI/CD — e é exatamente ali que a gente coloca a assinatura."

---

## Reset
```bash
kubectl delete -f deploy.yaml --ignore-not-found
kubectl delete clusterpolicy exigir-assinatura-cavaleiro1 --ignore-not-found
rm -f cosign.key cosign.pub
```

## Como funciona (para curiosos)
- O registry local é o mesmo container, acessível por dois nomes: `localhost:5111` (do seu terminal, para assinar) e `kind-registry:5111` (de dentro do cluster, para o Kyverno verificar). O Cosign indexa a assinatura pelo **digest** da imagem, então o Kyverno a encontra no mesmo repositório.
- A política usa `verifyImages` com a sua chave pública. `failureAction: Enforce` = bloqueia de verdade (troque por `Audit` para só registrar).

---

**I · Entrar** · [II · Executar](cavaleiro-2-privileged.md) · [III · Movimentar](cavaleiro-3-network.md) · [IV · Roubar](cavaleiro-4-secrets.md)