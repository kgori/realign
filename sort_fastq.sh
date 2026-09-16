#!/bin/bash

set -eo pipefail

Help() {
  echo -e "\033[1;4;37mFastq sorter\033[0m"
  echo
  echo -e " Usage: \033[1m$(basename "$0")\033[0m [\033[36moptions\033[0m] \033[32m<input.fq.gz>\033[0m"
  echo
  echo " Sort a fastq file by read name"
  echo
  echo -e " \033[36mOptions\033[0m:"
  echo "  -V, --version-sort    Use the 'version-sort' option of the unix sort tool. Sorts x.10 after x.2, for example."
  echo "  -o, --output  <file>  Writes output to this file. Automatically gzips the contents. If not given, writes to standard output without compression"
  echo "  -h, --help            Displays this help message"
}

# Defaults
VERSIONSORT=0
WRITETOFILE=0
OUT=""
IN=""

# Getopt
ARGS=$(getopt -o Vo:h --long version-sort,output:,help -n "$0" -- "$@")
if [ $? -ne 0 ]; then
  Help
  exit 1
fi
eval set -- "$ARGS"

while true; do
  case "$1" in
    -V|--version-sort)
      VERSIONSORT="1"
      shift 1
      ;;
    -o|--output)
      OUT="$2"
      WRITETOFILE="1"
      shift 2
      ;;
    -h|--help)
      Help
      exit 0
      ;;
    --)
      shift
      break
      ;;
    *)
      echo "Error: Invalid option '$1'" >&2
      Help
      exit 1
      ;;
  esac
done

# Positional arg
IN="${1:-}"

if [ -z "$IN" ]; then
  echo e "\033[1;31mError: Missing required input fastq.\033[0m" >&2
  Help
  exit 1
fi

if [ ! -e "$IN" ]; then
  echo -e "\033[1;31mError: Input file '$IN' not found!\033[0m" >&2
fi

if [ "$VERSIONSORT" -eq 1 ]; then
  extraargs=" --version-sort "
else
  extraargs=""
fi

if [ "$WRITETOFILE" -eq 1 ]; then
  zcat "$IN" | paste - - - - | sort -k1,1 -S 3G $extraargs | tr '\t' '\n' | gzip > "$OUT"
else 
  zcat "$IN" | paste - - - - | sort -k1,1 -S 3G $extraargs | tr '\t' '\n'
fi

echo "Done."
