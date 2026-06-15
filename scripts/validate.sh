#!/usr/bin/env bash
# Loop de validacao "cold-run" dos 4 cavaleiros.
#
# Destroi tudo, recria o cluster do zero e executa exatamente os comandos do
# roteiro de cada cavaleiro, verificando o par ataque -> defesa. Falha (exit 1)
# no PRIMEIRO passo cujo resultado nao seja o esperado. Se chegar ao fim, as 4
# demos funcionam num cluster novo, sem ajustes manuais.
#
# Uso:  ./scripts/validate.sh           (cold-run completo: teardown + setup)
#       SKIP_SETUP=1 ./scripts/validate.sh   (so as demos, no cluster atual)
set -uo pipefail
cd "$(dirname "$0")/.."

ok()   { printf '\033[32m  [OK]\033[0m %s\n' "$*"; }
fail() { printf '\033[31m  [FALHOU]\033[0m %s\n' "$*"; exit 1; }
hdr()  { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }

# expect_success "desc" cmd...  -> espera exit 0
expect_success() { local d="$1"; shift; if "$@" >/tmp/v.out 2>&1; then ok "$d"; else echo "--- saida:"; sed 's/^/    /' /tmp/v.out; fail "$d"; fi; }
# expect_fail "desc" cmd...     -> espera exit != 0 (ou seja, bloqueio)
expect_fail() { local d="$1"; shift; if "$@" >/tmp/v.out 2>&1; then echo "--- saida:"; sed 's/^/    /' /tmp/v.out; fail "$d (esperava BLOQUEIO, mas passou)"; else ok "$d"; fi; }

# ---------- ambiente do zero ----------
if [ "${SKIP_SETUP:-0}" != "1" ]; then
  hdr "Ambiente (teardown + setup do zero)"
  ./teardown.sh >/tmp/v.out 2>&1 || true
  ./setup.sh    || { sed 's/^/    /' /tmp/v.out; fail "setup.sh"; }
fi

# ================= Cavaleiro 1 — Supply Chain =================
hdr "Cavaleiro 1 — Supply Chain"
C1=cavaleiro-1-supply-chain
rm -f "$C1/cosign.key" "$C1/cosign.pub"

expect_success "deploy da imagem suspeita sobe sem friccao" kubectl apply -f "$C1/deploy.yaml"
expect_success "pod suspeito fica pronto" kubectl -n c1-supply-chain rollout status deploy/app-suspeito --timeout=120s
trivy image --scanners secret --quiet "localhost:5111/cavaleiro1:suspeita" >/tmp/v.out 2>&1
grep -qiE 'credentials.env|aws|github' /tmp/v.out && ok "trivy detectou o segredo plantado na imagem" || { sed 's/^/    /' /tmp/v.out; fail "trivy nao achou o segredo"; }

( cd "$C1" && COSIGN_PASSWORD="" cosign generate-key-pair ) >/tmp/v.out 2>&1 && ok "par de chaves cosign gerado" || { sed 's/^/    /' /tmp/v.out; fail "cosign generate-key-pair"; }
expect_success "policy de assinatura aplicada (Kyverno)" ./"$C1"/apply-policy.sh
sleep 6  # deixa o webhook da policy registrar
kubectl delete -f "$C1/deploy.yaml" --ignore-not-found >/dev/null 2>&1
expect_fail "redeploy da imagem NAO assinada e negado pelo Kyverno" kubectl apply -f "$C1/deploy.yaml"
expect_success "assinatura da imagem (cosign sign)" ./"$C1"/sign.sh
expect_success "redeploy da imagem ASSINADA passa" kubectl apply -f "$C1/deploy.yaml"

# ================= Cavaleiro 2 — Privileged =================
hdr "Cavaleiro 2 — Privileged"
C2=cavaleiro-2-privileged
expect_success "pod privilegiado criado" kubectl apply -f "$C2/privileged-pod.yaml"
expect_success "pod privilegiado fica pronto" kubectl -n c2-privileged wait --for=condition=Ready pod/fuga-do-container --timeout=90s
kubectl -n c2-privileged exec fuga-do-container -- cat /host/etc/os-release >/tmp/v.out 2>&1
grep -qi 'NAME=' /tmp/v.out && ok "leu /etc/os-release do NODE (fuga do container)" || { sed 's/^/    /' /tmp/v.out; fail "nao leu arquivo do host"; }
kubectl delete -f "$C2/privileged-pod.yaml" --ignore-not-found >/dev/null 2>&1
expect_success "PSS restricted aplicado ao namespace" kubectl apply -f "$C2/pss-enforce.yaml"
expect_fail "pod privilegiado e REJEITADO sob PSS restricted" kubectl apply -f "$C2/privileged-pod.yaml"

# ================= Cavaleiro 3 — Network =================
hdr "Cavaleiro 3 — Network"
C3=cavaleiro-3-network
expect_success "app (frontend + payments-db) criado" kubectl apply -f "$C3/app.yaml"
expect_success "payments-db pronto" kubectl -n c3-network wait --for=condition=Ready pod/payments-db --timeout=120s
expect_success "frontend pronto"    kubectl -n c3-network wait --for=condition=Ready pod/frontend --timeout=120s
kubectl -n c3-network exec frontend -- wget -qO- -T 5 http://payments-db:8080 >/tmp/v.out 2>&1
grep -qi 'SECRET' /tmp/v.out && ok "frontend ALCANCA o payments-db (movimentacao lateral)" || { sed 's/^/    /' /tmp/v.out; fail "frontend nao alcancou o db"; }
expect_success "default-deny aplicado" kubectl apply -f "$C3/default-deny.yaml"
sleep 4
expect_fail "frontend NAO alcanca mais o db (NetworkPolicy bloqueia)" kubectl -n c3-network exec frontend -- wget -qO- -T 5 http://payments-db:8080
expect_success "allow (least privilege) aplicado" kubectl apply -f "$C3/allow.yaml"
sleep 4
kubectl -n c3-network exec frontend -- wget -qO- -T 8 http://payments-db:8080 >/tmp/v.out 2>&1
grep -qi 'SECRET' /tmp/v.out && ok "acesso legitimo restaurado pelo allow" || { sed 's/^/    /' /tmp/v.out; fail "allow nao restaurou o acesso"; }

# ================= Cavaleiro 4 — Secrets =================
hdr "Cavaleiro 4 — Secrets"
C4=cavaleiro-4-secrets
expect_success "secret ingenuo criado" kubectl apply -f "$C4/insecure-secret.yaml"
VAL=$(kubectl -n c4-secrets get secret payments-api -o jsonpath='{.data.api-key}' | base64 -d)
echo "$VAL" | grep -qi 'sk-live' && ok "base64 -d revela o segredo em texto puro -> $VAL" || fail "nao decodificou o secret"
kubectl -n vault exec vault-0 -- sh -c 'VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root vault kv put secret/payments api-key=sk-live-ROTACIONADA-pelo-vault' >/tmp/v.out 2>&1 \
  && ok "segredo gravado no Vault" || { sed 's/^/    /' /tmp/v.out; fail "vault kv put"; }
kubectl -n c4-secrets create secret generic vault-token --from-literal=token=root --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1 \
  && ok "token do Vault criado no namespace" || fail "criacao do vault-token"
expect_success "SecretStore aplicado"    kubectl apply -f "$C4/secretstore.yaml"
expect_success "ExternalSecret aplicado" kubectl apply -f "$C4/externalsecret.yaml"
SYNC=""
for _ in $(seq 1 20); do
  SYNC=$(kubectl -n c4-secrets get secret payments-api-managed -o jsonpath='{.data.api-key}' 2>/dev/null | base64 -d 2>/dev/null || true)
  [ -n "$SYNC" ] && break
  sleep 3
done
echo "$SYNC" | grep -qi 'ROTACIONADA' && ok "ESO sincronizou o segredo do Vault -> $SYNC" || fail "ESO nao sincronizou payments-api-managed"

hdr "TODAS AS 4 DEMOS PASSARAM (cold-run verde)"
