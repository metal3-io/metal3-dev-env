# Push model agent with swtpm for testing
# Based on upstream fedora Dockerfile but adds swtpm for TPM emulation
FROM registry.fedoraproject.org/fedora-minimal AS builder

# Packaged dependencies
RUN microdnf install -y \
    cargo \
    clang \
    clang-devel \
    dnf-plugins-core \
    git \
    make \
    openssl-devel \
    rust \
    systemd \
    tpm2-tss \
    tpm2-tss-devel

# Build rust-keylime from local checkout
ARG RUST_KEYLIME_PATH=/src/rust-keylime
COPY rust-keylime/ ${RUST_KEYLIME_PATH}/
WORKDIR ${RUST_KEYLIME_PATH}
RUN make RELEASE=1 TARGETDIR=target target/release/keylime_push_model_agent

# Runtime image with swtpm
FROM registry.fedoraproject.org/fedora-minimal
ARG VERSION=latest
LABEL org.opencontainers.image.title="Keylime Push Model Agent with swtpm"
LABEL org.opencontainers.image.description="Keylime Push Model Agent with software TPM for testing"

# Install runtime dependencies including swtpm and dbus
RUN microdnf makecache && \
    microdnf -y install \
        tpm2-tss \
        openssl \
        util-linux-core \
        swtpm \
        swtpm-tools \
        tpm2-abrmd \
        tpm2-tools \
        procps-ng \
        dbus \
        dbus-daemon \
        iproute \
        && \
    microdnf clean all && \
    rm -rf /var/cache/dnf/*

# Copy agent binary from builder
COPY --from=builder /src/rust-keylime/target/release/keylime_push_model_agent /bin/keylime_push_model_agent

# Copy D-Bus policy, config, and startup script
COPY dbus-policy.conf /etc/dbus-1/system.d/
COPY keylime-agent.conf /etc/keylime/agent.conf
COPY swtpm-init.sh /swtpm-init.sh
COPY start.sh /start.sh
RUN chmod +x /swtpm-init.sh /start.sh

# Create keylime user with explicit UID/GID
ARG KEYLIME_UID=490
ARG KEYLIME_GID=490
RUN groupadd -g "${KEYLIME_GID}" keylime && \
    useradd -u "${KEYLIME_UID}" -g "${KEYLIME_GID}" -s /sbin/nologin -r -G tss keylime

# Create directories owned by keylime
RUN mkdir -p /var/lib/keylime/secure /var/lib/swtpm /run/swtpm && \
    chown -R keylime:keylime /var/lib/keylime /var/lib/swtpm /run/swtpm

ENV RUST_LOG=keylime_push_model_agent=info

ENTRYPOINT ["/start.sh"]
