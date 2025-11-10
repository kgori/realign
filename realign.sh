#!/bin/bash
Help() {
  echo "Usage: $0 [options] <input.bam> <reference.fa>"
  echo
  echo "Realign reads in the input BAM file to the reference genome using BWA-MEM2 or BWA."
  echo
  echo "Options:"
  echo "  -o, --output <file>   Output CRAM file name. If not provided, defaults to <input>_realigned.cram."
  echo "  -t, --threads <num>   Number of threads to use (default: 16)."
  echo "  --dry-run             Print the commands without executing them."
  echo "  -h, --help            Display this help message."
}

# Defaults
THREADS=16
DRY_RUN=0
OUT=""

# Getopt
ARGS=$(getopt -o o:t:h --long output:,threads:,dry-run,help -n '$0' -- "$@")
if [ $? -ne 0 ]; then
    Help
    exit 1
fi
eval set -- "$ARGS"

while true; do
  case "$1" in
    -o|--output)
      OUT="$2"
      shift 2
      ;;
    -t|--threads)
      THREADS="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
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

# Positional arguments
BAM=$1
REF=$2

if [ -z "$BAM" ] || [ -z "$REF" ]; then
  Help
  exit 1
fi

if [ ! -f "$BAM" ]; then
  echo "Error: Input BAM file '$BAM' not found!" >&2
  exit 1
fi

if [ ! -f "$REF" ]; then
  echo "Error: Reference genome file '$REF' not found!" >&2
  exit 1
fi

# Check which programs are available, bwa-mem2 or bwa?
HAVE_BWA2=$(command -v bwa-mem2)
HAVE_BWA=$(command -v bwa)

if [ -z "$HAVE_BWA2" ] && [ -z "$HAVE_BWA" ]; then
  echo "Error: Neither bwa-mem2 nor bwa is installed or in PATH" >&2
  exit 1
fi

# Check which index files are available
HAVE_BWA2_INDEX=$([ -f "${REF}.bwt.2bit.64" ] && echo 1 || echo 0)
HAVE_BWA_INDEX=$([ -f "${REF}.bwt" ] && echo 1 || echo 0)

# Select bwa program based on what's available. Prefer bwa-mem2.
if [ -n "$HAVE_BWA2" ] && [ "$HAVE_BWA2_INDEX" -eq 1 ]; then
  BWA="bwa-mem2"
elif [ -n "$HAVE_BWA" ] && [ "$HAVE_BWA_INDEX" -eq 1 ]; then
  BWA="bwa"
else
  echo "Error: Index files are missing for available aligners." >&2
  if [ -n "$HAVE_BWA2" ]; then
    echo "Please run bwa-mem2 index on the reference genome." >&2
  else
    echo "Please run bwa index on the reference genome." >&2
  fi
  exit 1
fi

re='^[0-9]+$'
if ! [[ $THREADS =~ $re ]] ; then
  echo "Error: Number of threads is not a number" >&2
  exit 1
fi

if [ $THREADS -lt 1 ]; then
  echo "Error: Number of threads must be at least 1" >&2
  exit 1
fi

if [ -z "$OUT" ]; then
  OUT=${BAM%.*am}_realigned.cram
fi

ALIGN_THREADS=$THREADS
SORT_THREADS=$((THREADS / 2))
if [ $SORT_THREADS -lt 1 ]; then
  SORT_THREADS=1
fi

echo -e "\033[4;32m$(basename $0)\033[0m" >&2
echo -e "Using aligner:    \033[1;34m$BWA\033[0m" >&2
echo -e "Input BAM:        \033[1;34m$BAM\033[0m" >&2
echo -e "Reference genome: \033[1;34m$REF\033[0m" >&2
echo -e "Output file:      \033[1;34m$OUT\033[0m" >&2
echo -e "Total threads:    \033[1;34m$THREADS \033[34m(Align: $ALIGN_THREADS, Sort: $SORT_THREADS)\033[0m" >&2

CMD="samtools collate -Oun128 ${BAM} \
    | samtools fastq -OT RG,BC - \
    | ${BWA} mem -p -Y -K 100000000 -t ${ALIGN_THREADS} -CH <(samtools view -H ${BAM} \
    | grep ^@RG) ${REF} - \
    | samtools sort -n -@ ${SORT_THREADS} -o - \
    | samtools fixmate -m - - \
    | samtools sort -@ ${SORT_THREADS} -o - \
    | samtools markdup -@ ${SORT_THREADS} -O CRAM --reference ${REF} - ${OUT}"

if [ $DRY_RUN -eq 1 ]; then
  echo ""
  echo -e "\033[1;31m**Dry run mode. The following command would be executed:**\033[0m" >&2
  echo "$CMD" >&2
else
  eval "$CMD"
fi
