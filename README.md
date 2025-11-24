Realign Reads Script
--

This is a script to make it easy to remap a BAM or CRAM file to a new reference. This task is common enough that, instead of repeatedly copying and
pasting from [Heng Li's blog](https://lh3.github.io/2021/07/06/remapping-an-aligned-bam), it was time to write a dedicated script.

# Usage
``` bash
Realign Reads Script

 Usage: realign.sh [options] <input.bam> <reference.fa>

 Realign reads in the input BAM file to the reference genome using BWA-MEM2 or BWA.

 Options:
  -o, --output        <file>               Output CRAM file name. If not provided, defaults to <input>_realigned.cram.
  -O, --output-format <BAM|CRAM|CRAM3.1>   Output format (choose BAM or CRAM; default: CRAM, aka CRAMv3.0).
  -t, --threads       <num>                Number of threads to use (default: 16).
      --dry-run                            Print the commands without executing them.
      --write-index                        Write an index for the output file.
  -h, --help                               Display this help message.
```

# Requirements
`samtools` and either `bwa-mem2` or `bwa`. The reference genome needs to be indexed by either `bwa-mem2` or `bwa`.
The script will check for the presence of `bwa-mem2` and `bwa`, as well as the required index files. If it finds
everything needed for `bwa-mem2`, then it will realign using `bwa-mem2`, otherwise it will use `bwa`.

The output file format defaults to CRAM v3.0, as this is the format with the best compatibility with existing tools,
at time of writing (Nov 2025). If you want CRAM v3.1, then this can be specified using `-O CRAM3.1`.
