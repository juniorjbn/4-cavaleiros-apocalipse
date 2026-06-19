# Os 4 Cavaleiros do Apocalipse no Kubernetes

Material e demos da palestra **"Os 4 Cavaleiros do Apocalipse no Kubernetes"** — a jornada de um
ataque (**Entrar → Executar → Movimentar → Roubar**) e a defesa de cada etapa, rodando ao vivo
num cluster local.

| # | Cavaleiro | Ataque | Defesa | Roteiro |
|---|-----------|--------|--------|---------|
| I   | Entrar     | Supply chain (imagem não confiável)   | Cosign + SBOM + Kyverno      | [▶](roteiros/cavaleiro-1-supply-chain.html) |
| II  | Executar   | Token de ServiceAccount + RBAC        | RBAC mínimo                  | [▶](roteiros/cavaleiro-2-privileged.html) |
| III | Movimentar | Movimentação lateral (rede plana)     | Network Policies (3 camadas) | [▶](roteiros/cavaleiro-3-network.html) |
| IV  | Roubar     | Secrets em base64                     | Vault + External Secrets     | [▶](roteiros/cavaleiro-4-secrets.html) |

## Material de apoio

- **[explicacao-4-cavaleiros.html](explicacao-4-cavaleiros.html)** — a visão completa de cada cavaleiro: cenários reais, como o ataque funciona, defesa em camadas e as perguntas que a plateia faz.
- **[roteiros/](roteiros/)** — o roteiro de palco de cada demo, com os comandos prontos para copiar.

> Os arquivos de apoio são **HTML**. No GitHub eles aparecem como código-fonte; para ver renderizado, **clone o repositório e abra no navegador** (ou use a extensão de preview do seu editor).

## Rodar as demos

Pré-requisitos: **Docker, kind, kubectl, helm, cosign, trivy** (testado com kind v0.31 / Kubernetes v1.35).

```bash
cd demo
./setup.sh              # cria o cluster kind + Calico + registry e instala Kyverno/ESO/Vault
                        # rode ANTES da palestra (precisa de internet)
# ... siga os roteiros em roteiros/*.html ...
./scripts/validate.sh   # opcional: roda as 4 demos de ponta a ponta (cold-run)
./teardown.sh           # derruba o cluster e o registry
```

Depois do `setup.sh`, **as demos rodam offline**.

## Estrutura

```
README.md                       você está aqui
explicacao-4-cavaleiros.html    material de apoio (visão geral)
roteiros/                       os 4 roteiros de palco (HTML)
demo/                           tudo que é executável
  setup.sh · teardown.sh
  kind/cluster.yaml
  scripts/validate.sh
  cavaleiro-1-supply-chain/     imagem suspeita, assinatura e policy
  cavaleiro-2-privileged/       token de SA, escalada via RBAC
  cavaleiro-3-network/          frontend → backend → banco e NetworkPolicies
  cavaleiro-4-secrets/          Secret ingênuo, Vault e External Secrets Operator
```

## Aviso

Tudo aqui é um **laboratório efêmero e local** (kind). As "imagens maliciosas" são **benignas**
(só imitam atividade suspeita e carregam segredos plantados para o scanner achar) e as credenciais
são **fictícias**. Vault em dev-mode, registry HTTP e token `root` são apenas para a demo —
**nada disso vai para produção**.

> O registry local usa a porta **5111** (para não colidir com a 5000/5001). Para trocar, ajuste
> `REG_PORT` no `demo/setup.sh` e as referências `:5111` nos arquivos do Cavaleiro 1.
