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

# ============= Cavaleiro 2 — Privilege Escalation (RBAC) =============
hdr "Cavaleiro 2 — Privilege Escalation (RBAC)"
C2=cavaleiro-2-privileged
expect_success "cenario criado (SA pode 'create pods' + pod com curl)" kubectl apply -f "$C2/cenario.yaml"
expect_success "pod comprometido pronto" kubectl -n c2-privileged wait --for=condition=Ready pod/app-comprometido --timeout=120s
# de dentro do pod: o token montado alcanca a API interna, sem kubeconfig nenhum
kubectl -n c2-privileged exec app-comprometido -- sh -c 'curl -sk -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" https://kubernetes.default.svc/version' >/tmp/v.out 2>&1
grep -q 'gitVersion\|"major"' /tmp/v.out && ok "de dentro do pod, o token fala com a API interna (kubernetes.default.svc)" || { sed 's/^/    /' /tmp/v.out; fail "curl in-pod nao alcancou a API"; }
# escalada: cria um pod privilegiado via POST na API, usando so o token montado
CODE=$(kubectl -n c2-privileged exec -i app-comprometido -- sh -c 'curl -sk -o /dev/null -w "%{http_code}" -X POST -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" -H "Content-Type: application/yaml" https://kubernetes.default.svc/api/v1/namespaces/c2-privileged/pods --data-binary @-' < "$C2/pod-privilegiado.yaml" 2>/dev/null)
[ "$CODE" = "201" ] && ok "atacante cria pod privilegiado via API (HTTP $CODE)" || fail "POST do pod privilegiado != 201 (foi $CODE)"
expect_success "pod do atacante fica pronto" kubectl -n c2-privileged wait --for=condition=Ready pod/pod-do-atacante --timeout=90s
kubectl -n c2-privileged exec pod-do-atacante -- cat /host/etc/os-release >/tmp/v.out 2>&1
grep -qi 'NAME=' /tmp/v.out && ok "pod do atacante le o filesystem do NODE" || { sed 's/^/    /' /tmp/v.out; fail "pod do atacante nao leu o host"; }
# defesa: remove o verbo 'create' do Role (least privilege)
kubectl delete pod pod-do-atacante -n c2-privileged --force --grace-period=0 >/dev/null 2>&1
expect_success "defesa: RBAC sem 'create'" kubectl apply -f "$C2/defesa.yaml"
sleep 4
CODE=$(kubectl -n c2-privileged exec -i app-comprometido -- sh -c 'curl -sk -o /dev/null -w "%{http_code}" -X POST -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" -H "Content-Type: application/yaml" https://kubernetes.default.svc/api/v1/namespaces/c2-privileged/pods --data-binary @-' < "$C2/pod-privilegiado.yaml" 2>/dev/null)
[ "$CODE" = "403" ] && ok "mesmo token, criar pod agora e NEGADO (HTTP $CODE)" || fail "POST apos defesa deveria ser 403 (foi $CODE)"

# ============ Cavaleiro 3 — Network (frontend -> backend -> db) ============
hdr "Cavaleiro 3 — Network (3 camadas)"
C3=cavaleiro-3-network
expect_success "app (frontend, backend, payments-db) criado" kubectl apply -f "$C3/app.yaml"
expect_success "payments-db pronto" kubectl -n c3-network wait --for=condition=Ready pod/payments-db --timeout=120s
expect_success "backend pronto"     kubectl -n c3-network wait --for=condition=Ready pod/backend --timeout=120s
expect_success "frontend pronto"    kubectl -n c3-network wait --for=condition=Ready pod/frontend --timeout=120s
# ataque (sem segmentacao): o frontend comprometido alcanca o banco DIRETO
# (retry: espera o CoreDNS registrar os Services recem-criados)
for _ in $(seq 1 12); do
  kubectl -n c3-network exec frontend -- wget -qO- -T 5 http://payments-db:8080 >/tmp/v.out 2>&1 && grep -qi SECRET /tmp/v.out && break
  sleep 3
done
grep -qi 'SECRET' /tmp/v.out && ok "frontend (comprometido) alcanca o db DIRETO (lateral)" || { sed 's/^/    /' /tmp/v.out; fail "frontend nao alcancou o db"; }
# o backend tambem alcanca (esse e o caminho legitimo)
kubectl -n c3-network exec backend -- wget -qO- -T 5 http://payments-db:8080 >/tmp/v.out 2>&1
grep -qi 'SECRET' /tmp/v.out && ok "backend alcanca o db (caminho legitimo)" || { sed 's/^/    /' /tmp/v.out; fail "backend nao alcancou o db"; }
# defesa: segmentacao por camada
expect_success "default-deny aplicado" kubectl apply -f "$C3/default-deny.yaml"
expect_success "allow (segmentacao 3 camadas) aplicado" kubectl apply -f "$C3/allow.yaml"
sleep 5
# o frontend (comprometido) fica CORTADO do banco — e nao volta
expect_fail "frontend NAO alcanca mais o db (cortado para sempre)" kubectl -n c3-network exec frontend -- wget -qO- -T 5 http://payments-db:8080
# o backend (legitimo) continua alcancando o banco
kubectl -n c3-network exec backend -- wget -qO- -T 8 http://payments-db:8080 >/tmp/v.out 2>&1
grep -qi 'SECRET' /tmp/v.out && ok "backend continua alcancando o db (servico de pe)" || { sed 's/^/    /' /tmp/v.out; fail "backend perdeu acesso ao db"; }
# e o caminho normal frontend -> backend segue funcionando
kubectl -n c3-network exec frontend -- wget -qO- -T 8 http://backend:8080 >/tmp/v.out 2>&1
grep -qi 'backend respondeu' /tmp/v.out && ok "frontend -> backend continua OK (caminho normal)" || { sed 's/^/    /' /tmp/v.out; fail "frontend perdeu acesso ao backend"; }

# ================= Cavaleiro 4 — Secrets =================
hdr "Cavaleiro 4 — Secrets"
C4=cavaleiro-4-secrets
expect_success "secret ingenuo criado (senha do banco)" kubectl apply -f "$C4/insecure-secret.yaml"
VAL=$(kubectl -n c4-secrets get secret db-credentials -o jsonpath='{.data.password}' | base64 -d)
echo "$VAL" | grep -qi 'banc' && ok "base64 -d revela a senha do banco em texto puro -> $VAL" || fail "nao decodificou o secret"
kubectl -n vault exec vault-0 -- sh -c 'VAULT_ADDR=http://127.0.0.1:8200 VAULT_TOKEN=root vault kv put secret/db password=senha-ROTACIONADA-pelo-vault' >/tmp/v.out 2>&1 \
  && ok "senha do banco gravada no Vault" || { sed 's/^/    /' /tmp/v.out; fail "vault kv put"; }
kubectl -n c4-secrets create secret generic vault-token --from-literal=token=root --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1 \
  && ok "token do Vault criado no namespace" || fail "criacao do vault-token"
expect_success "SecretStore aplicado"    kubectl apply -f "$C4/secretstore.yaml"
expect_success "ExternalSecret aplicado" kubectl apply -f "$C4/externalsecret.yaml"
SYNC=""
for _ in $(seq 1 20); do
  SYNC=$(kubectl -n c4-secrets get secret db-credentials-managed -o jsonpath='{.data.password}' 2>/dev/null | base64 -d 2>/dev/null || true)
  [ -n "$SYNC" ] && break
  sleep 3
done
echo "$SYNC" | grep -qi 'ROTACIONADA' && ok "ESO sincronizou a senha do Vault -> $SYNC" || fail "ESO nao sincronizou db-credentials-managed"

hdr "TODAS AS 4 DEMOS PASSARAM (cold-run verde)"
