# ProfitWay - Regiões institucionais

Site que mostra, antes da abertura da B3, a linha de venda (resistência), a linha de compra (suporte), o centro e os stops do Mini Índice (WIN).

## Cálculo

- σ = média de (máxima − mínima) ÷ fechamento anterior dos últimos 20 pregões
- Linhas = fechamento do último pregão ± 0,55σ, puxadas para a máxima/mínima de 1, 5 ou 20 pregões quando ela estiver a até 0,20σ
- Stop = 0,50σ além de cada linha; sem alvo (zera no fim do pregão)
- Às 9h: se abriu acima do centro, cancela a venda; se abriu abaixo, cancela a compra

Backtest 2023–2026 (dados diários da B3, custo de 1 tick): 237 operações, acerto 54%, ganho médio 768 / perda média 672 pontos, lucro em todos os anos.

## Coleta automática

O GitHub Actions (`.github/workflows/coletar.yml`) roda `coletar-site.ps1` todo dia às 8:50 de Brasília: baixa o boletim diário gratuito da B3 (BVBG.086) com `scripts/baixar_b3.sh`, guarda só o WIN em `dados/b3/`, calcula as linhas, grava `dados.json` e `historico.csv` e publica no GitHub Pages.

Para coletar na hora: aba **Actions** → **Coleta e publicação** → **Run workflow**.

Uso como referência, não como recomendação de investimento.
