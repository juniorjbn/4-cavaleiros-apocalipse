#!/usr/bin/env bash
# Cavaleiro 1 — aplica a ClusterPolicy do Kyverno que EXIGE assinatura cosign
# nas imagens kind-registry:5001/cavaleiro1*. A chave publica e injetada a
# partir do cosign.pub gerado na hora (cosign generate-key-pair).
set -euo pipefail
cd "$(dirname "$0")"

[ -f cosign.pub ] || { echo "ERRO: cosign.pub nao existe. Rode antes: COSIGN_PASSWORD='' cosign generate-key-pair"; exit 1; }

kubectl apply -f - <<EOF
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: exigir-assinatura-cavaleiro1
spec:
  background: false
  webhookConfiguration:
    failurePolicy: Fail
    timeoutSeconds: 30
  rules:
    - name: verificar-assinatura
      match:
        any:
          - resources:
              kinds: ["Pod"]
              namespaces: ["c1-supply-chain"]
      verifyImages:
        - imageReferences:
            - "kind-registry:5111/cavaleiro1*"
          failureAction: Enforce
          attestors:
            - entries:
                - keys:
                    publicKeys: |-
$(sed 's/^/                      /' cosign.pub)
                    rekor:
                      ignoreTlog: true
EOF
echo ">> policy 'exigir-assinatura-cavaleiro1' aplicada."
