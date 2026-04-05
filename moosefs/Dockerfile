ARG BUILD_FROM=ghcr.io/hassio-addons/base:20.0.1

# hadolint ignore=DL3006
FROM ${BUILD_FROM} AS builder

ARG MOOSEFS_VERSION=v4.58.4

RUN apk add --no-cache \
    autoconf \
    automake \
    build-base \
    fuse3-dev \
    git \
    libpcap-dev \
    libtool \
    linux-headers \
    pkgconf \
    python3 \
    zlib-dev \
    && git clone --branch "${MOOSEFS_VERSION}" --depth 1 \
        https://github.com/moosefs/moosefs.git /tmp/moosefs \
    && cd /tmp/moosefs \
    && ./configure \
        --prefix=/usr \
        --mandir=/share/man \
        --sysconfdir=/etc \
        --localstatedir=/var/lib \
        --with-default-user=mfs \
        --with-default-group=mfs \
        --disable-mfsmaster \
        --disable-mfsmetalogger \
        --disable-mfschunkserver \
        --disable-mfsnetdump \
        --disable-mfsbdev \
    && make install DESTDIR=/tmp/moosefs-install

# hadolint ignore=DL3006
FROM ${BUILD_FROM}

# Copy MooseFS from the build stage
COPY --from=builder /tmp/moosefs-install/ /

# Copy root filesystem
COPY rootfs /

# Setup runtime dependencies
RUN apk add --no-cache \
    coreutils \
    fuse3 \
    libpcap \
    lighttpd \
    nfs-utils \
    python3 \
    rpcbind \
    util-linux \
    zlib \
    && addgroup -S mfs \
    && adduser -S -D -H -h /var/lib/mfs -G mfs mfs \
    && mkdir -p \
        /mnt/mfs \
        /run/lighttpd \
        /run/rpcbind \
        /run/moosefs \
        /var/lib/nfs/rpc_pipefs \
        /var/lib/mfs/gui \
    && chown -R mfs:mfs /var/lib/mfs \
    && chmod a+x \
        /usr/bin/moosefs-*.sh \
        /etc/s6-overlay/s6-rc.d/gui/run \
        /etc/s6-overlay/s6-rc.d/init-moosefs/run \
        /etc/s6-overlay/s6-rc.d/mount/run \
        /etc/s6-overlay/s6-rc.d/nfs/run \
        /etc/s6-overlay/s6-rc.d/proxy/run

# Build arguments
ARG BUILD_ARCH
ARG BUILD_DATE
ARG BUILD_DESCRIPTION
ARG BUILD_NAME
ARG BUILD_REF
ARG BUILD_REPOSITORY
ARG BUILD_VERSION

# Labels
LABEL \
    io.hass.name="${BUILD_NAME}" \
    io.hass.description="${BUILD_DESCRIPTION}" \
    io.hass.arch="${BUILD_ARCH}" \
    io.hass.type="addon" \
    io.hass.version=${BUILD_VERSION} \
    maintainer="Tyler Levy Conde <yonstib@gmail.com>" \
    org.opencontainers.image.title="${BUILD_NAME}" \
    org.opencontainers.image.description="${BUILD_DESCRIPTION}" \
    org.opencontainers.image.vendor="Tyler Levy Conde" \
    org.opencontainers.image.authors="Tyler Levy Conde <yonstib@gmail.com>" \
    org.opencontainers.image.licenses="MIT" \
    org.opencontainers.image.url="https://github.com/${BUILD_REPOSITORY}" \
    org.opencontainers.image.source="https://github.com/${BUILD_REPOSITORY}" \
    org.opencontainers.image.documentation="https://github.com/${BUILD_REPOSITORY}/blob/main/README.md" \
    org.opencontainers.image.created=${BUILD_DATE} \
    org.opencontainers.image.revision=${BUILD_REF} \
    org.opencontainers.image.version=${BUILD_VERSION}
