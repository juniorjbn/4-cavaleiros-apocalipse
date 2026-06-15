# Os 4 Cavaleiros do Apocalipse no Kubernetes — Demos

Demos executáveis da palestra **"Os 4 Cavaleiros do Apocalipse no Kubernetes"**.
Cada cavaleiro é uma etapa de um ataque real — e a defesa correspondente, rodando ao vivo num cluster local.

| # | Cavaleiro | Ataque | Defesa |
|---|-----------|--------|--------|
| I   | [Entrar](cavaleiro-1-supply-chain/)    | Supply chain (imagem não confiável) | Cosign + SBOM + Kyverno |
| II  | [Executar](cavaleiro-2-privileged/)    | Container privilegiado / hostPath   | Pod Security Standards |
| III | [Movimentar](cavaleiro-3-network/)     | Movimentação lateral                | Network Policies (Calico) |
| IV  | [Roubar](cavaleiro-4-secrets/)         | Secrets em base64                   | Vault + External Secrets Operator |

> **Aviso.** Tudo aqui é um **laboratório efêmero e local** (kind). As "imagens maliciosas" são **benignas** — apenas imitam atividade suspeita em logs e carregam um segredo plantado para o scanner achar. Nada conecta na internet, minera ou causa dano. Não use nenhuma destas configurações (registry HTTP, Vault dev-mode, token `root`) em produção.

---

## Pré-requisitos

| Ferramenta | Para quê | Testado com |
|---|---|---|
| [Docker](https://docs.docker.com/get-docker/) | roda o kind e o registry | — |
| [kind](https://kind.sigs.k8s.io/) | cluster local | v0.31 |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | falar com o cluster | v1.35 |
| [helm](https://helm.sh/) | instalar Kyverno/ESO/Vault | v3 |
| [cosign](https://docs.sigstore.dev/cosign/installation/) | assinar imagens (Cavaleiro 1) | v2 |
| [trivy](https://aquasecurity.github.io/trivy/) | scan/SBOM (Cavaleiro 1) | — |

Verifique de uma vez:
```bash
for t in docker kind kubectl helm cosign trivy; do command -v $t >/dev/null && echo "$t ok" || echo "$t FALTANDO"; done
```

## Subir o ambiente
```bash
./setup.sh
```
Cria o cluster kind (com Calico), o registry local, e instala Kyverno, External Secrets Operator e Vault.
Rode **antes** da palestra (precisa de internet). Depois disso, as demos rodam offline.

## Derrubar tudo
```bash
./teardown.sh
```

## Validar as 4 demos de ponta a ponta
```bash
./scripts/validate.sh
```
Destrói tudo, recria o cluster do zero e executa os comandos de cada cavaleiro, conferindo o par **ataque → defesa**. Falha no primeiro passo que não bater. Verde = as 4 demos funcionam num cluster novo, sem ajustes.

## Precisa de internet?

Só no `./setup.sh` (baixa Calico, Kyverno, ESO, Vault e as imagens). **Depois do setup, as 4 demos rodam offline** — testado com a internet bloqueada:

- as imagens das demos ficam pré-carregadas nos nodes e no registry local;
- o `cosign sign` usa `--tlog-upload=false` (não envia a assinatura ao Rekor público);
- a policy do Kyverno usa `rekor.ignoreTlog: true` (não consulta o Rekor na verificação);
- o `trivy --scanners secret` usa regras embutidas (não baixa banco de dados).

---

## Estrutura
```
setup.sh / teardown.sh      ambiente (kind + Calico + registry + Kyverno/ESO/Vault)
kind/cluster.yaml           config do cluster (CNI desligado p/ Calico, registry)
scripts/validate.sh         loop de validação cold-run
cavaleiro-1-supply-chain/   imagem suspeita, deploy, assinatura e policy
cavaleiro-2-privileged/     pod privilegiado e Pod Security Standards
cavaleiro-3-network/        frontend/banco e Network Policies
cavaleiro-4-secrets/        Secret ingênuo, Vault e External Secrets Operator
```

Cada pasta tem um `README.md` com o roteiro: comandos, o que dizer e o resultado esperado.

## Porta do registry
O registry local usa a porta **5111** (escolhida para não colidir com a 5000/5001, comuns em outros setups). Para trocar, ajuste `REG_PORT` no `setup.sh` e as referências `:5111` nos arquivos do Cavaleiro 1.
