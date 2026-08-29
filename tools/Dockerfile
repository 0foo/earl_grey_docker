FROM condaforge/miniforge3:latest@sha256:609d8012d8ad3ea46c8e531ce2de9e727031960067b3a1e412c6e2954ef551c9

# General-purpose genome toolbox: FASTA/FASTQ utilities, interval arithmetic,
# NCBI genome/annotation download, and VCF/BAM tooling.
RUN mamba create -n bioinfo -y -c conda-forge -c bioconda \
    seqkit \
    seqtk \
    bedtools \
    samtools \
    bcftools \
    gffread \
    ncbi-datasets-cli \
    unzip && \
    mamba clean -a -y

# awscli in the base env (on PATH without activation), for parity with the
# earlGrey image when pulling/pushing data to S3
RUN mamba install -n base -y -c conda-forge awscli && \
    mamba clean -a -y

WORKDIR /genomes

ENTRYPOINT ["conda", "run", "--no-capture-output", "-n", "bioinfo"]
CMD ["bash"]

# Build (run from this directory, docker/tools/):
#   docker build -t bioinfo-tools:latest .
#
# Run a single command (e.g. unmask a genome):
#   docker run --rm -v /path/to/genomes:/genomes bioinfo-tools:latest \
#     seqkit seq -u /genomes/raw_data/genome.fna > genome.unmasked.fna
#
# Drop into an interactive shell with every tool on PATH:
#   docker run --rm -it -v /path/to/genomes:/genomes bioinfo-tools:latest bash
#
# Or via docker-compose.yml (reuses GENOMES_DIR/OUTPUT_DIR from .env):
#   docker compose run --rm tools seqkit seq -u /genomes/raw_data/genome.fna
