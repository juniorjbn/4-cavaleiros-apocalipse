#!/usr/bin/env bash
# Cavaleiro 1 — assina a imagem suspeita com a chave privada do cosign.
# A assinatura e gravada no MESMO registry, indexada pelo digest da imagem,
# entao o Kyverno a encontra mesmo acessando o registry por outro nome.
set -euo pipefail
cd "$(dirname "$0")"

export COSIGN_PASSWORD="${COSIGN_PASSWORD:-}"
IMG="${IMG:-localhost:5111/cavaleiro1:suspeita}"

[ -f cosign.key ] || { echo "ERRO: cosign.key nao existe. Rode antes: COSIGN_PASSWORD='' cosign generate-key-pair"; exit 1; }

# --tlog-upload=false: nao envia a assinatura para o Rekor (transparency log
# publico). Sem isso, o cosign tenta rekor.sigstore.dev e FALHA offline.
cosign sign --yes --tlog-upload=false --key cosign.key --allow-insecure-registry "$IMG"
echo ">> imagem assinada (sem Rekor, 100% offline): $IMG"
