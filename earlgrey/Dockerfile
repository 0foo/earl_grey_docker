FROM condaforge/miniforge3:latest@sha256:609d8012d8ad3ea46c8e531ce2de9e727031960067b3a1e412c6e2954ef551c9

# The base image ships with no timezone data at all (no tzdata package, no
# /etc/localtime, no /usr/share/zoneinfo), which makes Perl's
# DateTime::TimeZone module (used by RepeatModeler/RepeatMasker) print
# "Your system is mis-configured" warnings on every run, since none of the
# timezone file paths it checks exist. The actual timezone doesn't matter
# for this batch workload — installing tzdata and pointing /etc/localtime
# at a fixed zone just gives it something valid to find.
ENV TZ=Etc/UTC
# bc is required by earlGrey's own scripts (line-count/percentage math) but
# isn't present in the base image, so it's installed alongside tzdata here.
RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends tzdata bc && \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo "$TZ" >/etc/timezone && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Create the Conda environment with the required Python version
RUN mamba create -n earlgrey -y -c conda-forge -c bioconda earlgrey=7.3.1 python=3.11 && \
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

# Wraps `conda run -n earlgrey earlGrey` — see entrypoint.sh
COPY entrypoint.sh /opt/earlgrey/entrypoint.sh
RUN chmod +x /opt/earlgrey/entrypoint.sh
ENTRYPOINT ["/opt/earlgrey/entrypoint.sh"]



# Build the Docker image with the following command (run from this
# directory, docker/earlgrey/), or just `docker compose build`:
# docker build -t earlgrey-insects:latest .
#
# Run locally with dfam_data bind-mounted and a local genome file (path is
# absolute, so this works from anywhere; adjust the host-side path if your
# repo lives elsewhere):
# docker run --rm -it \
#   -v /home/nick/Documents/projects/Projects-School/Atallah-Lab/data/dfam_data:/opt/conda/envs/earlgrey/share/famdb-3.0.0/Libraries/famdb \
#   -v /home/nick/Documents/projects/Projects-School/Atallah-Lab/data/genomes:/genomes \
#   -v /home/nick/Documents/projects/Projects-School/Atallah-Lab/data/output:/output \
#   earlgrey-insects:latest -g /genomes/raw_data/genome.fna -s dmel -o /output -t 8
