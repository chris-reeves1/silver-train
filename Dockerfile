# syntax=docker/dockerfile:1.7
# parser directives:
# syntax is the main directive it selects Dockerfile frontend version and enables 
# new abilities/syntax like extra caching options. 
# v1.0 is always stable and doesnt change but 1.7 has caching features we want... default is v0.
# Others are escape and check. Escape sets escape character(rarely needed) and 
# check checks syntax(rarely used or supported).
# Absolutly must be the first line - buildkit scans only first lines for parser directives. 

# Note: Assuming no prod-changes to app.py or further reqs...

ARG PYTHON_VERSION=3.12-slim 
# version pinned but flexible, slim good option if it works - alpine can have compatibility issues. 
# An image like gcr.io/distroless/python3-debian12 - a good shell-less image - very small. 
FROM python:${PYTHON_VERSION} AS runtime 
# Only FROM commands can be aliased - this makes them a stage and allows multi-stage builds. 
# Useful for languages that need to be complied first. Also usful as i can build just specific stages if
# needed:
    #docker build --target runtime .
# ... also add later stages that reference the first:
    #eg:
        # Stage 1: builder
        # FROM python:3.12-slim AS builder
        # RUN pip install --upgrade pip

        # # Stage 2: runtime
        # FROM python:3.12-slim AS runtime
        # COPY --from=builder /usr/local /usr/local

# ENV's for runtime and pip - the python interpretor checks for specific ENV's at runtime so we can
# set their values here if we want to.
# pip also checks so pip envs can be included.
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

# pip examples:
# PIP_DISABLE_PIP_VERSION_CHECK=1: skips the version check
# PIP_NO_CACHE_DIR=off: controls caching
# PIP_ROOT_USER_ACTION=ignore: suppresses root warnings

# python interpretor examples:

# PYTHONDONTWRITEBYTECODE=1	Prevents creation of .pyc files (no bytecode caching)
# PYTHONUNBUFFERED=1	Forces stdout/stderr to be unbuffered — useful for real-time logging
# PYTHONPATH=/some/path	Adds directories to the module search path
# PYTHONWARNINGS=default	Enables warnings (e.g., deprecations)
# PYTHONHASHSEED=0	Makes hash operations deterministic

WORKDIR /app

# Now lets focus on setting up the OS to be as small and clean as possible:

# Arg to store and give flexibility to a list of base packages to install -
# kept light here. Could Store a list in a file or in a repo too. 
ARG BASE_PACKAGES="curl"

# A run command to deal with updating the apt cache and installing tools 
# we may need. --mount=type=cache is a feature of syntax 1.7.
# WARNING - VERY COMPLICATED:
    # the cache directive has its own caching behaviour diff to
    # layer caching. It makes a hash that includes build contexts 
    # so we can scope its use to build contexts or ID's. It doesnt 
    # time-out so be wary of stale caches (docker builder prune --cache removes it).
    # We can give an ID or it can be anonmymous (a volume gets created to handle it).
    # The first run the cache is empty, apt update fills the cache and 
    # subsequent builds will be quicker as it will now use the cache.
    # From the docs:
        #"Apt needs exclusive access to its data, so the caches use the option 
        # sharing=locked to ensure parallel builds using the same cache mount 
        # wait for each other and not access the same cache files at the same time"  
    # precedence:
#- layer cache: (same Dockerfile instruction, same context: layer reused, cache mount not invoked)
#- named cache volume: (same cache id, command changed: layer rebuilt, cache volume reused)
#- unnamed cache volume: (no cache id, same context, command changed: layer rebuilt, anonymous cache volume reused)
#- rebuild no caches: (no cache id, changed context or command: layer rebuilt, no cache volume reused)
RUN --mount=type=cache,target=/var/cache/apt,id=apt-cache,sharing=locked \
    apt-get update && apt-get install -y --no-install-recommends \
        ${BASE_PACKAGES}

# removes doc and man pages for installed packages, locale for translations.
# purge removes left over bits and named packages you wan to remove. 
# AS the apt cache is now itself cached, we can save 10+mbs in the image. 
RUN apt-get purge -y --auto-remove && \
    rm -rf /var/lib/apt/lists/* /usr/share/doc /usr/share/man /usr/share/locale

# ok...... now pip!
COPY requirements.txt .
# Use cache mount for pip too
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install --no-cache-dir -r requirements.txt
# If requirements.txt is unchanged: layer is reused, pip step is skipped.
# If requirements.txt is changed: layer is rebuilt, pip runs again, but uses the cache.
# The cache stores .whl, tars, zips, metadata, artifacts etc. 
# --no-cache-dir: This tells pip not to write to its internal cache.

# Now copy the rest - pip is out of the way, so 
# any changes to other files is safe - the previous steps
# wont re-run. 
COPY . .

# OCI labels (if we dont just make them up ourselves).
# Useful with docker inspect, pipelines and general organisation.
# Be sure to set AUTHOR as a --build-arg
ARG AUTHOR="n/a"
LABEL org.opencontainers.image.title="Some app" \
      org.opencontainers.image.version="1.9.7" \
      org.opencontainers.image.authors="${AUTHOR}" \
      org.opencontainers.image.description="python app..."

# roooooooooot...! !
# Non-root (good default)
# Creates a new system user named appuser, Assigns user ID 10001.
# -r == no home directory or login.
# -s /usr/sbin/nologin -- cant log into a shell at all!
RUN useradd -u 10001 -r -m -d /home/appuser -s /usr/sbin/nologin appuser \
 && chmod +x /app/run.sh \
 && chown -R appuser:appuser /app /home/appuser
# changes ownership of the /app directory to appuser recurrsivly (all files + user and group)
USER appuser
# Active user is now no longer root - all remaining lines are safe.

EXPOSE 5500

# Healthchecks -  we can use this to mark the container unhealthy (can see this in inspect):
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD curl -fsS http://127.0.0.1:5500/health || exit 1

# lets use a script for our entrypoint
# Ensure its executable
ENTRYPOINT ["/app/run.sh"]
