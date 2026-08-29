FROM condaforge/miniforge3:latest@sha256:609d8012d8ad3ea46c8e531ce2de9e727031960067b3a1e412c6e2954ef551c9

# Create the Conda environment with the required Python version
RUN mamba create -n earlgrey -y -c conda-forge -c bioconda earlgrey=7.3.1 python=3.11 && \
    mamba clean -a -y

# awscli in the base env (on PATH without activation) so the entrypoint can
# move genome input/output to/from S3 when running on AWS Batch
RUN mamba install -n base -y -c conda-forge awscli && \
    mamba clean -a -y

# Generate the initial configure scripts
# (This ensures the necessary directory structures are created by earlGrey.
# It exits non-zero when run with no arguments by design, so the failure is
# ignored here — but --no-capture-output means a *real* failure still shows
# up in the build log instead of being hidden.)
RUN conda run --no-capture-output -n earlgrey earlGrey || true

# Dfam data is bind-mounted at runtime while iterating (see run command below)
# instead of being baked in with COPY. Switch back to COPY once things work.

# Set the default working directory for runtime operations
WORKDIR /genomes

# Wraps `conda run -n earlgrey earlGrey`, transparently handling s3:// URIs
# for -g/-o (AWS Batch) alongside plain local paths (local testing) — see
# entrypoint.sh
COPY entrypoint.sh /opt/earlgrey/entrypoint.sh
RUN chmod +x /opt/earlgrey/entrypoint.sh
ENTRYPOINT ["/opt/earlgrey/entrypoint.sh"]



# Build the Docker image with the following command (run from this
# directory, docker/earlgrey/):
# docker build -t earlgrey-insects:7.3.1 .
#
# Run locally with dfam_data bind-mounted and a local genome file (path is
# absolute, so this works from anywhere; adjust the host-side path if your
# repo lives elsewhere):
# docker run --rm -it \
#   -v /home/nick/Documents/projects/Projects-School/Atallah-Lab/data/dfam_data:/opt/conda/envs/earlgrey/share/famdb-3.0.0/Libraries/famdb \
#   -v /home/nick/Documents/projects/Projects-School/Atallah-Lab/data/genomes:/genomes \
#   -v /home/nick/Documents/projects/Projects-School/Atallah-Lab/data/output:/output \
#   earlgrey-insects:7.3.1 -g /genomes/raw_data/genome.fna -s dmel -o /output -t 8
#
# On AWS Batch, same image/entrypoint, but -g/-o take s3:// URIs instead
# (dfam_data still needs to reach the container — bake it in with COPY, or
# mount an EFS volume at the famdb path above, before this runs on Batch):
#   -g s3://my-bucket/genomes/genome.fna.gz -s dmel -o s3://my-bucket/output/dmel
