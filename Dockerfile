# syntax=docker/dockerfile:1.4

FROM --platform=$BUILDPLATFORM grafana/alloy-build-image:v0.1.17 as build
ARG BUILDPLATFORM
ARG TARGETPLATFORM
ARG TARGETOS
ARG TARGETARCH
ARG TARGETVARIANT
ARG RELEASE_BUILD=1
ARG VERSION
ARG GOEXPERIMENT

WORKDIR /src/alloy

# Copy and download root module dependencies
COPY go.mod go.sum ./
COPY syntax/go.mod syntax/go.sum ./syntax/
COPY prometheus/go.mod prometheus/go.sum ./prometheus/
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    go mod download

# Copy the rest of the source code
COPY . .

# Build the UI before building Alloy
RUN --mount=type=cache,target=/src/alloy/web/ui/node_modules,sharing=locked \
    make generate-ui

# Build the Alloy binary
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    GOOS=$TARGETOS GOARCH=$TARGETARCH GOARM=${TARGETVARIANT#v} \
    RELEASE_BUILD=${RELEASE_BUILD} VERSION=${VERSION} \
    GO_TAGS="netgo builtinassets promtail_journal_enabled" \
    GOEXPERIMENT=${GOEXPERIMENT} \
    make alloy

FROM public.ecr.aws/ubuntu/ubuntu:noble

ARG UID=473
ARG USERNAME="alloy"

LABEL org.opencontainers.image.source="https://github.com/grafana/alloy"

# Install runtime dependencies
RUN apt-get update \
 && apt-get install -qy libsystemd-dev tzdata ca-certificates \
 && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Copy the built binary and config
COPY --from=build --chown=$UID /src/alloy/build/alloy /bin/alloy
COPY --chown=$UID example-config.alloy /etc/alloy/config.alloy

# Create user and set permissions
RUN groupadd --gid $UID $USERNAME
RUN useradd -m -u $UID -g $UID $USERNAME

RUN mkdir -p /var/lib/alloy/data
RUN chown -R $USERNAME:$USERNAME /var/lib/alloy
RUN chmod -R 770 /var/lib/alloy

ENTRYPOINT ["/bin/alloy"]
ENV ALLOY_DEPLOY_MODE=docker
CMD ["run", "/etc/alloy/config.alloy", "--storage.path=/var/lib/alloy/data"]
