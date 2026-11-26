#!/bin/bash
# Baixa o boletim BVBG.086 (B3, pesquisa por pregao) de um dia e extrai so o mini indice (WIN).
# Uso: baixar_b3.sh AAMMDD  -> grava dados/b3/AAMMDD.csv (vazio = feriado)
d=$1
base="$(cd "$(dirname "$0")/.." && pwd)/dados"
out="$base/b3/$d.csv"
[ -s "$out" ] && exit 0
[ -f "$base/b3/$d.feriado" ] && exit 0
CURL=$(command -v curl.exe || command -v curl)
tmp="${TMPDIR:-/tmp}/b3_$d"; mkdir -p "$tmp"
"$CURL" -s --retry 3 -o "$tmp/o.zip" "https://www.b3.com.br/pesquisapregao/download?filelist=PR$d.zip"
sz=$(stat -c %s "$tmp/o.zip" 2>/dev/null || echo 0)
# boletim ainda nao publicado (dias recentes): sai sem marcar feriado, para tentar de novo depois
if [ "$sz" -lt 1000 ]; then
  dd=$(( ($(date +%s) - $(date -d "20${d:0:2}-${d:2:2}-${d:4:2}" +%s)) / 86400 ))
  if [ "$dd" -le 4 ]; then rm -rf "$tmp"; exit 3; fi
  touch "$base/b3/$d.feriado"; rm -rf "$tmp"; exit 0; fi
unzip -o -q "$tmp/o.zip" -d "$tmp" || { rm -rf "$tmp"; exit 1; }
inner=$(ls "$tmp"/PR*.zip 2>/dev/null | head -1)
x=$(unzip -Z1 "$inner" | sort | tail -1)
unzip -p "$inner" "$x" | grep -E -B5 -A50 "<TckrSymb>WIN[FGHJKMNQUVXZ][0-9][0-9]</TckrSymb>" | awk '
/<PricRpt>/ {t="";dt="";o="";h="";l="";c="";aj="";paj="";q="";oi=""}
/<Dt>/ {gsub(/.*<Dt>|<\/Dt>.*/,""); dt=$0}
/<TckrSymb>/ {gsub(/.*<TckrSymb>|<\/TckrSymb>.*/,""); t=$0}
/<FrstPric/ {gsub(/.*">|<\/.*/,""); o=$0}
/<MaxPric/ {gsub(/.*">|<\/.*/,""); h=$0}
/<MinPric/ {gsub(/.*">|<\/.*/,""); l=$0}
/<LastPric/ {gsub(/.*">|<\/.*/,""); c=$0}
/<AdjstdQt /||/<AdjstdQt>/ {gsub(/.*">|<\/.*/,""); aj=$0}
/<PrvsAdjstdQt / {gsub(/.*">|<\/.*/,""); paj=$0}
/<RglrTraddCtrcts>/ {gsub(/.*<RglrTraddCtrcts>|<\/.*/,""); q=$0}
/<OpnIntrst>/ {gsub(/.*<OpnIntrst>|<\/.*/,""); oi=$0}
/<\/PricRpt>/ { if (t ~ /^WIN[FGHJKMNQUVXZ][0-9][0-9]$/) print dt";"t";"o";"h";"l";"c";"aj";"paj";"q";"oi }
' > "$out.tmp" && mv "$out.tmp" "$out"
rm -rf "$tmp"
