FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
      build-essential meson ninja-build pkg-config git ca-certificates \
      patchelf dpkg-dev fakeroot file lintian \
      libdrm-dev libgbm-dev libpixman-1-dev libxkbcommon-dev \
      libwayland-dev wayland-protocols libjansson-dev \
      libgnutls28-dev nettle-dev libgmp-dev zlib1g-dev \
      libturbojpeg0-dev libavcodec-dev libavfilter-dev libavutil-dev \
      scdoc \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src
CMD ["/src/build.sh"]
