# Custom Forgejo Actions runner with CI toolchain
# Used by K8s runner deployment with DinD sidecar
FROM code.forgejo.org/forgejo/runner:6.3.1 AS runner

FROM debian:bookworm-slim

# Install base tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git openssh-client jq unzip xz-utils \
    && rm -rf /var/lib/apt/lists/*

# Copy Forgejo runner binary from official image
COPY --from=runner /bin/forgejo-runner /usr/local/bin/forgejo-runner

# Install Go
ARG GO_VERSION=1.24.1
RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" | tar -C /usr/local -xzf -
ENV PATH="/usr/local/go/bin:${PATH}"

# Install Node.js via fnm-compatible direct download
ARG NODE_VERSION=22.22.1
RUN curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz" \
    | tar -xJf - -C /usr/local --strip-components=1

# Install golangci-lint
ARG GOLANGCI_LINT_VERSION=v2.1.6
RUN curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/HEAD/install.sh \
    | sh -s -- -b /usr/local/bin ${GOLANGCI_LINT_VERSION}

# Install crane (for Harbor image push)
ARG CRANE_VERSION=v0.20.3
RUN curl -fsSL "https://github.com/google/go-containerregistry/releases/download/${CRANE_VERSION}/go-containerregistry_Linux_x86_64.tar.gz" \
    | tar -xzf - -C /usr/local/bin crane

# Install Docker CLI (for DinD communication)
RUN curl -fsSL https://download.docker.com/linux/static/stable/x86_64/docker-27.5.1.tgz \
    | tar -xzf - --strip-components=1 -C /usr/local/bin docker/docker

# Create runner user and workspace
RUN useradd -m -s /bin/bash runner
WORKDIR /data
RUN chown runner:runner /data

USER runner
ENTRYPOINT ["forgejo-runner"]
CMD ["daemon"]
