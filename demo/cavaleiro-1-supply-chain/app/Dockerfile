# Imagem "suspeita" do Cavaleiro 1 (Supply Chain).
#
# IMPORTANTE: e BENIGNA. Nao minera, nao conecta em lugar nenhum, nao causa
# dano. Ela so (1) carrega um "segredo" plantado para o scanner achar e
# (2) imprime um log que IMITA um beacon de C2, para a plateia "ver" atividade
# suspeita. Serve apenas para a demonstracao de supply chain.
FROM alpine:3.20

# "Segredos" plantados de proposito para o scanner achar. Sao FAKE, mas no
# formato real (o trivy ignora as chaves de EXEMPLO da AWS, entao usamos outras).
RUN printf 'github_pat=ghp_A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8\naws_access_key_id=AKIA4ZX7QMHTK3DNWPL2\naws_secret_access_key=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\n' > /opt/credentials.env

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
