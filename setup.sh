#!/usr/bin/env bash
# Monta TODO o ambiente das demos dos "4 Cavaleiros do Apocalipse no Kubernetes":
#   - cluster kind (1 node) com Calico (NetworkPolicy de verdade)
#   - registry local (HTTP) para o Cavaleiro 1
#   - Kyverno          (Cavaleiro 1 - verificacao de assinatura)
#   - External Secrets Operator + Vault dev-mode (Cavaleiro 4)
#   - imagem "suspeita" do Cavaleiro 1 publicada no registry
#   - imagens das demos pre-carregadas (para o palco rodar OFFLINE)
#
# Rode ANTES da palestra (precisa de internet). No palco, so os comandos do
# roteiro de cada cavaleiro. Para um ambiente 100% limpo: ./teardown.sh primeiro.
set -euo pipefail
cd "$(dirname "$0")"

CLUSTER_NAME="${CLUSTER_NAME:-cavaleiros}"
REG_NAME="${REG_NAME:-kind-registry}"
REG_PORT="${REG_PORT:-5111}"
CALICO_VERSION="${CALICO_VERSION:-v3.32.0}"
KYVERNO_CHART_VERSION="${KYVERNO_CHART_VERSION:-3.8.1}"
DEMO_IMAGES=(alpine:3.20 hashicorp/http-echo:1.0)

log() { printf '\n\033[1m>> %s\033[0m\n' "$*"; }

# --- 1. Registry local (HTTP, mesma porta no host e no cluster) -------------
if [ "$(docker inspect -f '{{.State.Running}}' "${REG_NAME}" 2>/dev/null || true)" != "true" ]; then
  log "criando registry local ${REG_NAME} (localhost:${REG_PORT})"
  docker run -d --restart=always \
    -e REGISTRY_HTTP_ADDR="0.0.0.0:${REG_PORT}" \
    -p "127.0.0.1:${REG_PORT}:${REG_PORT}" \
    --name "${REG_NAME}" registry:2 >/dev/null
fi

# --- 2. Cluster kind (sem CNI default; Calico assume) -----------------------
if ! kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  log "criando cluster kind '${CLUSTER_NAME}'"
  kind create cluster --name "${CLUSTER_NAME}" --config kind/cluster.yaml
fi

# --- 3. Conecta o registry a rede 'kind' (vira o DNS kind-registry) ---------
if [ "$(docker inspect -f '{{json .NetworkSettings.Networks.kind}}' "${REG_NAME}" 2>/dev/null || echo null)" = "null" ]; then
  log "conectando ${REG_NAME} a rede 'kind'"
  docker network connect kind "${REG_NAME}"
fi

# --- 4. containerd dos nodes: kind-registry:${REG_PORT} via HTTP ------------
log "apontando o containerd dos nodes para o registry (HTTP)"
REGISTRY_DIR="/etc/containerd/certs.d/${REG_NAME}:${REG_PORT}"
for node in $(kind get nodes --name "${CLUSTER_NAME}"); do
  docker exec "${node}" mkdir -p "${REGISTRY_DIR}"
  cat <<EOF | docker exec -i "${node}" cp /dev/stdin "${REGISTRY_DIR}/hosts.toml"
[host."http://${REG_NAME}:${REG_PORT}"]
  capabilities = ["pull", "resolve"]
EOF
done

# --- 5. Calico: NetworkPolicy de verdade (kindnet nao aplica) ---------------
log "instalando Calico ${CALICO_VERSION}"
kubectl apply -f "https://raw.githubusercontent.com/projectcalico/calico/${CALICO_VERSION}/manifests/calico.yaml"
log "aguardando Calico e os nodes ficarem prontos"
kubectl -n kube-system rollout status daemonset/calico-node --timeout=300s
kubectl wait --for=condition=Ready nodes --all --timeout=300s

# --- 6. Kyverno (Cavaleiro 1) ----------------------------------------------
log "instalando Kyverno ${KYVERNO_CHART_VERSION}"
helm repo add kyverno https://kyverno.github.io/kyverno/ >/dev/null 2>&1 || true
helm repo update kyverno >/dev/null
helm upgrade --install kyverno kyverno/kyverno --version "${KYVERNO_CHART_VERSION}" \
  -n kyverno --create-namespace --wait --timeout 5m

# Registry local e HTTP: o admission controller precisa aceitar registry inseguro.
# O Kyverno ja inclui '--allowInsecureRegistry=false' por padrao, entao
# SUBSTITUIMOS esse argumento (nao adianta adicionar um segundo).
log "habilitando registry inseguro no admission controller do Kyverno"
ARGS_TMP="$(mktemp)"
kubectl -n kyverno get deploy kyverno-admission-controller \
  -o jsonpath='{range .spec.template.spec.containers[0].args[*]}{@}{"\n"}{end}' > "$ARGS_TMP"
LINE="$(grep -n 'allowInsecureRegistry' "$ARGS_TMP" | head -1 | cut -d: -f1)"
rm -f "$ARGS_TMP"
if [ -n "${LINE:-}" ]; then
  kubectl -n kyverno patch deployment kyverno-admission-controller --type=json \
    -p="[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/args/$((LINE-1))\",\"value\":\"--allowInsecureRegistry=true\"}]"
else
  kubectl -n kyverno patch deployment kyverno-admission-controller --type=json \
    -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--allowInsecureRegistry=true"}]'
fi
kubectl -n kyverno rollout status deploy/kyverno-admission-controller --timeout=180s

# --- 7. External Secrets Operator (Cavaleiro 4) ----------------------------
log "instalando External Secrets Operator"
helm repo add external-secrets https://charts.external-secrets.io >/dev/null 2>&1 || true
helm repo update external-secrets >/dev/null
helm upgrade --install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace --set installCRDs=true --wait --timeout 5m

# --- 8. Vault dev-mode (Cavaleiro 4) ---------------------------------------
log "instalando Vault (dev-mode, root token = 'root')"
helm repo add hashicorp https://helm.releases.hashicorp.com >/dev/null 2>&1 || true
helm repo update hashicorp >/dev/null
helm upgrade --install vault hashicorp/vault -n vault --create-namespace \
  --set "server.dev.enabled=true" \
  --set "server.dev.devRootToken=root" \
  --set "injector.enabled=false" --wait --timeout 5m
kubectl -n vault wait --for=condition=Ready pod/vault-0 --timeout=180s

# --- 9. Imagem "suspeita" do Cavaleiro 1 no registry -----------------------
log "publicando a imagem suspeita do Cavaleiro 1 no registry"
docker build -t "localhost:${REG_PORT}/cavaleiro1:suspeita" cavaleiro-1-supply-chain/app
docker push "localhost:${REG_PORT}/cavaleiro1:suspeita"

# --- 10. Pre-carrega imagens das demos nos nodes (palco offline) -----------
log "pre-carregando imagens das demos nos nodes"
for img in "${DEMO_IMAGES[@]}"; do
  docker pull "$img" >/dev/null
  kind load docker-image "$img" --name "${CLUSTER_NAME}"
done

# --- 11. Namespaces das demos ----------------------------------------------
log "criando namespaces das demos"
for ns in c1-supply-chain c2-privileged c3-network c4-secrets; do
  kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done

log "setup completo. Cluster '${CLUSTER_NAME}' pronto para os 4 cavaleiros."
