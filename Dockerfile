ARG IHD_TAG=intel-media-26.1.6
ARG GMM_TAG=intel-gmmlib-22.10.0

FROM alpine:latest AS builder
ARG IHD_TAG
ARG GMM_TAG

RUN apk add --no-cache alpine-sdk cmake libva-dev libdrm-dev libpciaccess-dev git patchelf

# Build without RELR (packed relative relocations) and with static C++ runtime.
# Plex's bundled musl is pre-1.2.3 and silently skips .relr.dyn sections, leaving
# .init_array entries unrelocated → SIGSEGV at raw file offset 0x4310.
ENV LF="-Wl,-z,nopackrelocs -static-libstdc++ -static-libgcc"

RUN git clone --depth=1 --branch "${GMM_TAG}" \
      https://github.com/intel/gmmlib /tmp/gmmlib && \
    cmake -S /tmp/gmmlib -B /tmp/gmmlib/build \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX=/tmp/sdk \
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
      -DCMAKE_SHARED_LINKER_FLAGS="${LF}" \
      -DCMAKE_EXE_LINKER_FLAGS="${LF}" && \
    cmake --build /tmp/gmmlib/build --target install -- -j$(nproc)

RUN git clone --depth=1 --branch "${IHD_TAG}" \
      https://github.com/intel/media-driver /tmp/ihd && \
    cmake -S /tmp/ihd -B /tmp/ihd/build \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_PREFIX_PATH=/tmp/sdk \
      -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
      -DBUILD_TESTING=OFF \
      -DMEDIA_RUN_TEST_SUITE=OFF \
      -DCMAKE_SHARED_LINKER_FLAGS="${LF}" \
      -DCMAKE_EXE_LINKER_FLAGS="${LF}" && \
    cmake --build /tmp/ihd/build --target iHD_drv_video -- -j$(nproc)

RUN mkdir -p /opt/vaapi && \
    cp "$(find /tmp/ihd/build -name iHD_drv_video.so | head -1)" /opt/vaapi/ && \
    cp -P /tmp/sdk/lib/libigdgmm.so* /opt/vaapi/ && \
    patchelf --set-rpath /vaapi:/usr/lib/plexmediaserver/lib /opt/vaapi/iHD_drv_video.so && \
    patchelf --set-rpath /vaapi:/usr/lib/plexmediaserver/lib \
      /opt/vaapi/libigdgmm.so.12 2>/dev/null || true

FROM alpine:latest
COPY --from=builder /opt/vaapi/ /opt/vaapi/
