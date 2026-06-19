#!/usr/bin/env bash
# Destroi tudo o que o setup.sh criou: o cluster kind e o registry local.
# Idempotente — pode rodar quantas vezes quiser, mesmo sem nada criado.
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-cavaleiros}"
REG_NAME="${REG_NAME:-kind-registry}"

echo ">> deletando cluster kind '${CLUSTER_NAME}' (se existir)"
kind delete cluster --name "${CLUSTER_NAME}" || true

if [ "$(docker inspect -f '{{.State.Running}}' "${REG_NAME}" 2>/dev/null || true)" = "true" ]; then
  echo ">> removendo registry local '${REG_NAME}'"
  docker rm -f "${REG_NAME}" >/dev/null
fi

echo ">> teardown completo."
