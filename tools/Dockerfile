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

COPY entrypoint.sh /opt/tools/entrypoint.sh
RUN chmod +x /opt/tools/entrypoint.sh
ENTRYPOINT ["/opt/tools/entrypoint.sh"]
CMD ["bash"]

# Build (run from this directory, docker/tools/):
#   docker build -t bioinfo-tools:latest .
#
# No fixed data mount — bind-mount whatever host path you're working with at
# the same path inside the container, e.g. to unmask a genome:
#   docker run --rm -v /data/bioinfo/data/genomes:/data/bioinfo/data/genomes bioinfo-tools:latest \
#     seqkit seq -u /data/bioinfo/data/genomes/raw_data/genome.fna -o /data/bioinfo/data/genomes/raw_data/genome.unmasked.fna
#
# Drop into an interactive shell with every tool on PATH:
#   docker run --rm -it -v /data/bioinfo/data/genomes:/data/bioinfo/data/genomes bioinfo-tools:latest bash
#
# Prefer tools/bin/run-bio, unmask-genome, fetch-genome (see tools/README.md)
# — they compute and pass the right -v mounts for you from plain host paths.
