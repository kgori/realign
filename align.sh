#!/bin/bash
Help() {
  echo -e "\033[1;4;37mAlign FASTQ Reads Script\033[0m"
  echo ""
  echo -e " Usage: \033[1m$(basename "$0")\033[0m [\033[36moptions\033[0m] \033[32m<reference.fa>\033[0m"
  echo
  echo " Align FASTQ reads to a reference genome using BWA-MEM2 or BWA."
  echo
  echo -e " \033[36mOptions\033[0m:"
  echo "  -1, --fq1            <file>               FASTQ R1 (paired or single-end)"
  echo "  -2, --fq2            <file>               FASTQ R2 (paired-end)"
  echo "  -i, --fq-interleaved <file>               Interleaved FASTQ (paired-end)"
  echo "  -R, --read-group     <@RG line>           Read group string for bwa mem (e.g. '@RG\\tID:foo\\tSM:bar')"
  echo "  -o, --output         <file>               Output file name (default: <fq>_aligned.{bam|cram})"
  echo "  -O, --output-format  <BAM|CRAM|CRAM3.1>   Output format (default: CRAM, aka CRAMv3.0)"
  echo "  -t, --threads        <num>                Number of threads to use (default: 16)."
  echo "      --single-end                          Treat --fq1 as single-end"
  echo "      --dry-run                             Print the commands without executing them."
  echo "      --write-index                         Write an index for the output file."
  echo "  -h, --help                                Display this help message."
}

# Defaults
OUTPUT_FORMAT="CRAM"
THREADS=16
DRY_RUN=0
WRITE_INDEX=0
OUT=""
FQ1=""
FQ2=""
FQINT=""
READ_GROUP=""
SINGLE_END=0

# Getopt
ARGS=$(getopt -o 1:2:i:R:o:O:t:h --long fq1:,fq2:,fq-interleaved:,read-group:,output:,output-format:,threads:,single-end,dry-run,write-index,help -n "$0" -- "$@")
if [ $? -ne 0 ]; then
    Help
    exit 1
fi
eval set -- "$ARGS"

while true; do
  case "$1" in
    -1|--fq1)
      FQ1="$2"
      shift 2
      ;;
    -2|--fq2)
      FQ2="$2"
      shift 2
      ;;
    -i|--fq-interleaved)
      FQINT="$2"
      shift 2
      ;;
    -R|--read-group)
      READ_GROUP="$2"
      shift 2
      ;;
    -o|--output)
      OUT="$2"
      shift 2
      ;;
    -O|--output-format)
      OUTPUT_FORMAT="$2"
      shift 2
      ;;
    -t|--threads)
      THREADS="$2"
      shift 2
      ;;
    --single-end)
      SINGLE_END=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --write-index)
      WRITE_INDEX=1
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
REF="${1:-}"

if [ -z "$REF" ]; then
  echo -e "\033[1;31mError: Missing required reference genome.\033[0m" >&2
  Help
  exit 1
fi

if [ ! -e "$REF" ]; then
  echo -e "\033[1;31mError: Reference genome file '$REF' not found!\033[0m" >&2
  exit 1
fi

# Input validation: require either interleaved or fq1(/fq2)
if [ -n "$FQINT" ] && { [ -n "$FQ1" ] || [ -n "$FQ2" ]; }; then
  echo -e "\033[1;31mError: Use either --fq-interleaved OR --fq1/--fq2, not both.\033[0m" >&2
  exit 1
fi

if [ -z "$FQINT" ] && [ -z "$FQ1" ]; then
  echo -e "\033[1;31mError: FASTQ input missing. Provide --fq-interleaved or --fq1 (and --fq2 for paired-end).\033[0m" >&2
  exit 1
fi

if [ -n "$FQ2" ] && [ -z "$FQ1" ]; then
  echo -e "\033[1;31mError: --fq2 provided without --fq1.\033[0m" >&2
  exit 1
fi

if [ "$SINGLE_END" -eq 1 ] && [ -n "$FQ2" ]; then
  echo -e "\033[1;31mError: --single-end cannot be used with --fq2.\033[0m" >&2
  exit 1
fi

if [ -n "$FQ1" ] && [ ! -e "$FQ1" ]; then
  echo -e "\033[1;31mError: FASTQ file '$FQ1' not found!\033[0m" >&2
  exit 1
fi

if [ -n "$FQ2" ] && [ ! -e "$FQ2" ]; then
  echo -e "\033[1;31mError: FASTQ file '$FQ2' not found!\033[0m" >&2
  exit 1
fi

if [ -n "$FQINT" ] && [ ! -e "$FQINT" ]; then
  echo -e "\033[1;31mError: FASTQ file '$FQINT' not found!\033[0m" >&2
  exit 1
fi

OUTDIR=$(dirname "$OUT")
OUTFILE=$(basename "$OUT")

mkdir -p "$OUTDIR" || {
    echo -e "\033[1;31mError: Could not create output directory '$OUTDIR'\033[0m" >&2
    exit 1
}

# Normalise paths if `realpath' is available
if command -v realpath >/dev/null 2>&1; then
    REF=$(realpath "$REF")
    if [ -n "$FQ1" ]; then FQ1=$(realpath "$FQ1"); fi
    if [ -n "$FQ2" ]; then FQ2=$(realpath "$FQ2"); fi
    if [ -n "$FQINT" ]; then FQINT=$(realpath "$FQINT"); fi
    if [ -n "$OUT" ]; then
        OUTDIR_ABS=$(realpath "$OUTDIR") || {
            echo -e "\033[1;31mError: Could not resolve output directory '$OUTDIR'\033[0m" >&2
            exit 1
        }
        OUT="$OUTDIR_ABS/$OUTFILE"
    fi
fi

# File type validation warnings
if [[ -n "$FQ1" && ! "$FQ1" =~ \.(fastq|fq)(\.gz)?$ ]]; then
  echo -e "\033[1;33mWarning: '$FQ1' does not have a typical FASTQ extension.\033[0m" >&2
fi
if [[ -n "$FQ2" && ! "$FQ2" =~ \.(fastq|fq)(\.gz)?$ ]]; then
  echo -e "\033[1;33mWarning: '$FQ2' does not have a typical FASTQ extension.\033[0m" >&2
fi
if [[ -n "$FQINT" && ! "$FQINT" =~ \.(fastq|fq)(\.gz)?$ ]]; then
  echo -e "\033[1;33mWarning: '$FQINT' does not have a typical FASTQ extension.\033[0m" >&2
fi
if [[ ! "$REF" =~ \.(fa|fasta|fna)(\.gz)?$ ]]; then
  echo -e "\033[1;33mWarning: Reference file '$REF' does not have a typical FASTA extension.\033[0m" >&2
fi

# Check which programs are available, bwa-mem2 or bwa?
HAVE_BWA2=$(command -v bwa-mem2)
HAVE_BWA=$(command -v bwa)

if [ -z "$HAVE_BWA2" ] && [ -z "$HAVE_BWA" ]; then
  echo -e "\033[1;31mError: Neither bwa-mem2 nor bwa is installed or in PATH\033[0m" >&2
  exit 1
fi

# Check which index files are available
echo "Checking for ${REF} index files" >&2
HAVE_BWA2_INDEX=$([ -f "${REF}.bwt.2bit.64" ] && echo 1 || echo 0)
HAVE_BWA_INDEX=$([ -f "${REF}.bwt" ] && echo 1 || echo 0)

# Select bwa program based on what's available. Prefer bwa-mem2.
if [ -n "$HAVE_BWA2" ] && [ "$HAVE_BWA2_INDEX" -eq 1 ]; then
  BWA="bwa-mem2"
elif [ -n "$HAVE_BWA" ] && [ "$HAVE_BWA_INDEX" -eq 1 ]; then
  BWA="bwa"
else
  echo -e "\033[1;31mError: Index files are missing for available aligners.\033[0m" >&2
  if [ -n "$HAVE_BWA2" ]; then
    echo "Please run bwa-mem2 index on the reference genome." >&2
  else
    echo "Please run bwa index on the reference genome." >&2
  fi
  exit 1
fi

re='^[0-9]+$'
if ! [[ $THREADS =~ $re ]] ; then
  echo -e "\033[1;31mError: Number of threads is not a number\033[0m" >&2
  exit 1
fi

if [ "$THREADS" -lt 1 ]; then
  echo -e "\033[1;31mError: Number of threads must be at least 1\033[0m" >&2
  exit 1
fi

if [ "$OUTPUT_FORMAT" != "CRAM" ] && [ "$OUTPUT_FORMAT" != "BAM" ] && [ "$OUTPUT_FORMAT" != "CRAM3.1" ]; then
  echo -e "\033[1;31mError: Unsupported output format '$OUTPUT_FORMAT'. Use BAM, CRAM or CRAM3.1.\033[0m" >&2
  exit 1
fi

FMT="-O CRAM,version=3.0 --reference ${REF}"
if [ "$OUTPUT_FORMAT" == "BAM" ]; then
  FMT="-O BAM"
elif [ "$OUTPUT_FORMAT" == "CRAM3.1" ]; then
  FMT="-O CRAM,version=3.1 --reference ${REF}"
fi

ALIGN_THREADS=$THREADS
SORT_THREADS=$((THREADS / 2))
if [ $SORT_THREADS -lt 1 ]; then
  SORT_THREADS=1
fi

# Default output name if not provided
if [ -z "$OUT" ]; then
  if [ -n "$FQINT" ]; then
    BASE="${FQINT%.*}"
  else
    BASE="${FQ1%.*}"
  fi
  if [ "$OUTPUT_FORMAT" == "BAM" ]; then
    OUT="${BASE}_aligned.bam"
  else
    OUT="${BASE}_aligned.cram"
  fi
fi

# Read group option
BWA_RG_OPT=""
if [ -n "$READ_GROUP" ]; then
  BWA_RG_OPT="-R ${READ_GROUP}"
fi

# All options are valid, so make a temporary directory
JOBTMP="$(mktemp -d -t align_fastq_tmp_XXXXXX -p ${TMPDIR:-/tmp})"

cleanup() {
  rm -rf "$JOBTMP"
}

trap 'exit_code=$?; cleanup; exit $exit_code' EXIT

echo -e "\033[4;32m$(basename $0)\033[0m" >&2
echo -e "Using aligner:    \033[1;34m$BWA\033[0m" >&2
echo -e "Reference genome: \033[1;34m$REF\033[0m" >&2
echo -e "Output file:      \033[1;34m$OUT\033[0m" >&2
echo -e "Output format:    \033[1;34m$OUTPUT_FORMAT\033[0m" >&2
echo -e "Total threads:    \033[1;34m$THREADS \033[34m(Align: $ALIGN_THREADS, Sort: $SORT_THREADS)\033[0m" >&2

# Build alignment command
if [ -n "$FQINT" ]; then
  echo -e "Input FASTQ:      \033[1;34m$FQINT (interleaved)\033[0m" >&2
  BWA_CMD="${BWA} mem -p -Y -K 100000000 -t ${ALIGN_THREADS} ${BWA_RG_OPT} ${REF} ${FQINT}"
else
  if [ -n "$FQ2" ] && [ "$SINGLE_END" -eq 0 ]; then
    echo -e "Input FASTQ:      \033[1;34m$FQ1 (R1), $FQ2 (R2)\033[0m" >&2
    BWA_CMD="${BWA} mem -Y -K 100000000 -t ${ALIGN_THREADS} ${BWA_RG_OPT} ${REF} ${FQ1} ${FQ2}"
  else
    echo -e "Input FASTQ:      \033[1;34m$FQ1 (single-end)\033[0m" >&2
    BWA_CMD="${BWA} mem -Y -K 100000000 -t ${ALIGN_THREADS} ${BWA_RG_OPT} ${REF} ${FQ1}"
  fi
fi

CMD="${BWA_CMD} \
    | samtools sort -n -m 1G -@ ${SORT_THREADS} -T ${JOBTMP}/namesort -o - \
    | samtools fixmate -m - - \
    | samtools sort -m 1G -@ ${SORT_THREADS} -T ${JOBTMP}/possort -o - \
    | samtools markdup -@ ${SORT_THREADS} -T ${JOBTMP}/markdup ${FMT} - ${OUT}"

if [ $DRY_RUN -eq 1 ]; then
  echo ""
  echo -e "\033[1;31m**Dry run mode. The following command would be executed:**\033[0m" >&2
  echo "$CMD" >&2
  if [ "$WRITE_INDEX" -eq 1 ]; then
      echo "samtools index ${OUT}" >&2
  fi
  exit 0
else
  echo -e "\033[1;33mExecuting alignment command\n${CMD}\033[0m" >&2

  echo "$CMD" > "${JOBTMP}/align_command.sh"
  if ! (
      set -euo pipefail
      bash "${JOBTMP}/align_command.sh"
  ); then
    echo -e "\033[1;31mError: Alignment command failed\033[0m" >&2
    exit 1
  fi

  # Write the index and check it was created
  if [ "$WRITE_INDEX" -eq 1 ]; then
    samtools index "${OUT}"
    if [ $? -ne 0 ]; then
      echo -e "\033[1;31mError: Failed to write index for output file '${OUT}'\033[0m" >&2
      exit 1
    fi

    index_exists() {
      local f=$1
      [[ -f ${f}.bai || -f ${f}.csi || -f ${f}.crai ]]
    }

    if ! index_exists "${OUT}"; then
      echo -e "\033[1;31mError: Index file for output '${OUT}' was not created!\033[0m" >&2
      exit 1
    fi
  fi

  # Check we produced some output
  [ -s "$OUT" ] || { echo -e "\033[1;31mError: Output file '$OUT' is empty!\033[0m" >&2; exit 1; }

  # Check output file integrity
  samtools quickcheck "$OUT" || { echo -e "\033[1;31mError: Output file '$OUT' is corrupted or incomplete!\033[0m" >&2; exit 1; }

  # Check the output contains any reads
  OUT_READS=$(samtools view -c -F 0x900 "$OUT")
  (( OUT_READS > 0 )) || {
    echo -e "\033[1;31mError: No reads found in output file '$OUT'!\033[0m" >&2
    exit 1
  }

  # All looks good
  echo -e "\033[1;32mAlignment completed successfully. ${OUT_READS} reads were aligned. Output written to '$OUT'.\033[0m" >&2
  exit 0
fi
