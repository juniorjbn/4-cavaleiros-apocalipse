# Cavaleiro 2 — Executar (Privileged Containers)

> "Privileged é sudo sem supervisão."
> Um container privilegiado é só um host esperando para acontecer.

**Ataque:** com `privileged` + `hostPath`, o container deixa de ser uma caixa isolada e vira o próprio node.
**Defesa:** Pod Security Standards no nível `restricted` — nativo do Kubernetes, sem instalar nada.

---

## Roteiro

### 1. Sobe um container privilegiado que monta o filesystem do node
```bash
kubectl apply -f privileged-pod.yaml
kubectl -n c2-privileged get pod fuga-do-container
```
*Fala:* "Esse pod pediu `privileged: true` e montou o disco do node em `/host`. O cluster não reclamou."

### 2. Lê arquivos do host de dentro do container
```bash
kubectl -n c2-privileged exec fuga-do-container -- cat /host/etc/os-release
kubectl -n c2-privileged exec fuga-do-container -- ls /host/var/lib/kubelet
```
*Resultado esperado:* você lê arquivos que pertencem ao **node**, não ao container.
*Fala:* "Se o atacante consegue virar root no host, Kubernetes vira detalhe. O problema não é o container escapar — é você abrir a porta."

### 3. A defesa: Pod Security Standards (restricted)
```bash
kubectl delete -f privileged-pod.yaml
kubectl apply -f pss-enforce.yaml
```
Isso rotula o namespace para **exigir** o padrão `restricted` (sem privileged, sem hostPath, sem rodar como root).

### 4. Tenta subir o pod privilegiado de novo → rejeitado
```bash
kubectl apply -f privileged-pod.yaml
```
*Resultado esperado:* **`violates PodSecurity "restricted:latest"`** — o pod é recusado na criação.
*Fala:* "Containers não deveriam administrar servidores. Com PSS, o cluster passa a recusar quem pede demais."

---

## Reset
```bash
kubectl delete -f privileged-pod.yaml --ignore-not-found
kubectl label namespace c2-privileged \
  pod-security.kubernetes.io/enforce- \
  pod-security.kubernetes.io/warn- \
  pod-security.kubernetes.io/audit- \
  pod-security.kubernetes.io/enforce-version- 2>/dev/null || true
```

## Notas
- `restricted` é o nível mais rígido dos [Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/). Os outros são `baseline` (bloqueia os abusos mais óbvios) e `privileged` (sem restrição).
- PSS atua por **namespace**, via labels. Comece com `warn`/`audit` para medir o impacto antes de mudar para `enforce`.
