#!/bin/sh
# Comportamento BENIGNO que apenas IMITA atividade maliciosa nos logs.
# Nenhuma conexao de rede e feita; nenhum recurso e consumido de verdade.
echo "[cavaleiro-1] container iniciado (DEMONSTRACAO benigna)"
echo "[cavaleiro-1] lendo credenciais plantadas em /opt/credentials.env ..."
while true; do
  echo "[beacon] $(date -u) -> c2.exfil.invalid:443 (SIMULADO, sem conexao real)"
  sleep 30
done
