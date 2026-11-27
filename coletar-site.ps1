# Coleta do site (GitHub Actions, pwsh no Linux; tambem roda no PowerShell 5.1 do Windows com o Git Bash).
# Baixa os boletins diarios da B3 que faltam, calcula as linhas institucionais do proximo pregao do WIN
# e grava dados.json e historico.csv. Mesmo calculo do coletar.ps1 da pasta principal:
#   sigma = media de (maxima - minima) / fechamento anterior dos ultimos 20 pregoes
#   linhas = fechamento +- 0,55 sigma, puxadas para a maxima/minima de 1, 5 ou 20 pregoes a ate 0,20 sigma
#   stop = 0,50 sigma alem da linha; sem alvo (zera no fim do pregao); filtro da abertura (modo B)
$ErrorActionPreference = 'Stop'
$base = $PSScriptRoot
$inv = [Globalization.CultureInfo]::InvariantCulture
$b3 = Join-Path (Join-Path $base 'dados') 'b3'
$gitBash = 'C:\Program Files\Git\usr\bin\bash.exe'
$agora = [DateTime]::UtcNow.AddHours(-3)          # horario de Brasilia
function Get-Tick5([double]$x) { [math]::Round($x / 5) * 5 }
function Save-Texto([string]$arq, [string]$txt) { [IO.File]::WriteAllText((Join-Path $base $arq), $txt, (New-Object Text.UTF8Encoding $false)) }

# 1) boletins que faltam
$sh = Join-Path (Join-Path $base 'scripts') 'baixar_b3.sh'
$ult = Get-ChildItem $b3 | Where-Object { $_.Name -match '^\d{6}\.(csv|feriado)$' } | Sort-Object Name | Select-Object -Last 1
$d = [datetime]::ParseExact($ult.BaseName, 'yyMMdd', $inv).AddDays(1)
while ($d -le $agora.Date) {
    if ($d.DayOfWeek -ne 'Saturday' -and $d.DayOfWeek -ne 'Sunday') {
        $s = $d.ToString('yyMMdd')
        if (Test-Path $gitBash) { $px = '/' + $sh.Substring(0, 1).ToLower() + ($sh.Substring(2) -replace '\\', '/'); & $gitBash -lc "'$px' $s" | Out-Null }
        else { & bash $sh $s | Out-Null }
        if (Test-Path (Join-Path $b3 "$s.csv")) { Write-Host "Boletim B3 de $($d.ToString('dd/MM/yyyy')) baixado" }
    }
    $d = $d.AddDays(1)
}

# 2) serie do WIN nos ultimos pregoes (contrato do dia = o mais negociado; fechamento anterior do MESMO contrato)
$files = @(Get-ChildItem $b3 -Filter *.csv | Sort-Object Name | Select-Object -Last 45)
$rows = New-Object System.Collections.Generic.List[object]
$prev = @{}
foreach ($f in $files) {
    $dia = @(Get-Content $f.FullName | Where-Object { $_ -match '^\d{4}-\d{2}-\d{2};WIN' } | ForEach-Object {
        $p = $_.Split(';')
        [pscustomobject]@{ dt = $p[0]; t = $p[1]; o = $p[2]; h = $p[3]; l = $p[4]; c = $p[5]; aj = $p[6]; paj = $p[7]; q = $(if ($p[8]) { [double]::Parse($p[8], $inv) } else { 0 }) }
    })
    if ($dia.Count -eq 0) { continue }
    $best = $dia | Where-Object { $_.q -gt 0 -and $_.o -ne '' } | Sort-Object q -Descending | Select-Object -First 1
    if ($best) {
        $pc = $prev[$best.t]; if (-not $pc) { $pc = $best.paj }
        $rows.Add([pscustomobject]@{ D = [datetime]::ParseExact($best.dt, 'yyyy-MM-dd', $inv); Tk = $best.t
            O = [double]::Parse($best.o, $inv); H = [double]::Parse($best.h, $inv); L = [double]::Parse($best.l, $inv)
            C = [double]::Parse($best.c, $inv); Aj = [double]::Parse($best.aj, $inv); PC = [double]::Parse($pc, $inv) })
    }
    $prev = @{}; foreach ($r in $dia) { if ($r.c -ne '') { $prev[$r.t] = $r.c } }
}
$n = $rows.Count
if ($n -lt 22) { throw "Poucos pregoes na base da B3 ($n)." }
$ult = $rows[$n - 1]

# 3) calculo
$sig = ($rows[($n - 20)..($n - 1)] | ForEach-Object { ($_.H - $_.L) / $_.PC } | Measure-Object -Average).Average
$mu = $ult.C; $s = $mu * $sig
$fator = New-Object double[] $n; $fator[$n - 1] = 1.0
for ($i = $n - 1; $i -ge 1; $i--) { $fator[$i - 1] = $fator[$i]; if ($rows[$i].Tk -ne $rows[$i - 1].Tk) { $fator[$i - 1] = $fator[$i] * $rows[$i].PC / $rows[$i - 1].C } }
$ext = @{}
foreach ($k in 1, 5, 20) {
    $hi = [double]::MinValue; $lo = [double]::MaxValue
    for ($i = $n - $k; $i -le $n - 1; $i++) { $hi = [math]::Max($hi, $rows[$i].H * $fator[$i]); $lo = [math]::Min($lo, $rows[$i].L * $fator[$i]) }
    $ext["max$k"] = $hi; $ext["min$k"] = $lo
}
$baseU = $mu + 0.55 * $s; $baseD = $mu - 0.55 * $s
$linhaU = $baseU; $origU = 'Faixa de volatilidade'; $m = 0.20 * $s
foreach ($k in 1, 5, 20) { $x = $ext["max$k"]; if ([math]::Abs($x - $baseU) -le $m) { $m = [math]::Abs($x - $baseU); $linhaU = $x; $origU = "Maxima de $k pregao" + $(if ($k -gt 1) { 'es' } else { '' }) } }
$linhaD = $baseD; $origD = 'Faixa de volatilidade'; $m = 0.20 * $s
foreach ($k in 1, 5, 20) { $x = $ext["min$k"]; if ([math]::Abs($x - $baseD) -le $m) { $m = [math]::Abs($x - $baseD); $linhaD = $x; $origD = "Minima de $k pregao" + $(if ($k -gt 1) { 'es' } else { '' }) } }
$stopPts = Get-Tick5 (0.50 * $s)
$venda = Get-Tick5 $linhaU; $compra = Get-Tick5 $linhaD

$alvo = $ult.D.AddDays(1); while ($alvo.DayOfWeek -eq 'Saturday' -or $alvo.DayOfWeek -eq 'Sunday') { $alvo = $alvo.AddDays(1) }
$avisos = @()
if ($alvo -lt $agora.Date) { $avisos += "O boletim mais recente da B3 e de $($ult.D.ToString('dd/MM/yyyy')); o do ultimo pregao ainda pode nao ter sido publicado." }
$meses = @{ F = 1; G = 2; H = 3; J = 4; K = 5; M = 6; N = 7; Q = 8; U = 9; V = 10; X = 11; Z = 12 }
$v = New-Object datetime ((2000 + [int]$ult.Tk.Substring(4, 2)), $meses[[string]$ult.Tk[3]], 15)
$delta = [int][DayOfWeek]::Wednesday - [int]$v.DayOfWeek; if ($delta -gt 3) { $delta -= 7 }; if ($delta -lt -3) { $delta += 7 }
$venc = $v.AddDays($delta)
if (($venc - $alvo).Days -le 5 -and ($venc - $alvo).Days -ge 0) { $avisos += "$($ult.Tk) vence em $($venc.ToString('dd/MM/yyyy')). Na rolagem, confira qual contrato tem mais volume: as linhas valem para $($ult.Tk)." }

$hist = @(); for ($i = [math]::Max(0, $n - 15); $i -le $n - 1; $i++) {
    $hist += [ordered]@{ data = $rows[$i].D.ToString('yyyy-MM-dd'); abertura = [math]::Round($rows[$i].O * $fator[$i]); maxima = [math]::Round($rows[$i].H * $fator[$i]); minima = [math]::Round($rows[$i].L * $fator[$i]); fechamento = [math]::Round($rows[$i].C * $fator[$i]) }
}
$dados = [ordered]@{
    coletadoEm = $agora.ToString('yyyy-MM-ddTHH:mm:ss')
    pregaoAlvo = $alvo.ToString('yyyy-MM-dd')
    avisos     = $avisos
    win        = [ordered]@{ fonte = 'B3 (boletim diario BVBG.086)'; simbolo = $ult.Tk; vencimento = $venc.ToString('yyyy-MM-dd'); dataPregao = $ult.D.ToString('yyyy-MM-dd')
                             fechamento = $mu; abertura = $ult.O; maxima = $ult.H; minima = $ult.L; ajuste = $ult.Aj
                             url = 'https://www.b3.com.br/pt_br/market-data-e-indices/servicos-de-dados/market-data/consultas/boletim-diario/' }
    sigma      = [ordered]@{ pct = [math]::Round($sig * 100, 4); pts = [math]::Round($s); pregoes = 20 }
    estrutura  = [ordered]@{ max1 = [math]::Round($ext['max1']); max5 = [math]::Round($ext['max5']); max20 = [math]::Round($ext['max20'])
                             min1 = [math]::Round($ext['min1']); min5 = [math]::Round($ext['min5']); min20 = [math]::Round($ext['min20']) }
    linhas     = [ordered]@{ centro = $mu; baseVenda = [math]::Round($baseU); baseCompra = [math]::Round($baseD); venda = $venda; compra = $compra
                             origemVenda = $origU; origemCompra = $origD; meio = Get-Tick5 (($venda + $compra) / 2); stopPts = $stopPts; stopVenda = $venda + $stopPts; stopCompra = $compra - $stopPts
                             kLinha = 0.55; kAjuste = 0.20; kStop = 0.50 }
    backtest   = [ordered]@{ periodo = '2023-2026'; operacoes = 237; acerto = 54.0; ganhoMedio = 768; perdaMedia = 672; mediaOp = 106; fatorLucro = 1.33
                             piorQueda = 11348; piorSequencia = 6; anos = [ordered]@{ '2023' = 6984; '2024' = 1197; '2025' = 16205; '2026' = 741 } }
    historico  = $hist
}
Save-Texto 'dados.json' ($dados | ConvertTo-Json -Depth 6)
$h = Join-Path $base 'historico.csv'
if (-not (Test-Path $h)) { Save-Texto 'historico.csv' "coletado_em;pregao;contrato;centro;sigma_pct;sigma_pts;venda;stop_venda;compra;stop_compra;origem_venda;origem_compra`n" }
Add-Content -Path $h -Encoding ASCII -Value (($agora.ToString('yyyy-MM-dd HH:mm'), $alvo.ToString('yyyy-MM-dd'), $ult.Tk, $mu, ($sig * 100).ToString('0.000', $inv), [math]::Round($s),
    $venda, ($venda + $stopPts), $compra, ($compra - $stopPts), $origU, $origD) -join ';')
Write-Host ("Pregao {0} {1}: venda {2} (stop {3}) | centro {4} | compra {5} (stop {6}) | sigma {7} pts" -f $alvo.ToString('dd/MM'), $ult.Tk, $venda, ($venda + $stopPts), $mu, $compra, ($compra - $stopPts), [math]::Round($s))
