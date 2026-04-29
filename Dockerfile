# syntax=docker/dockerfile:1.6

FROM emscripten/emsdk:3.1.74

ARG GS_GIT_URL=https://github.com/ArtifexSoftware/ghostpdl.git
ARG GS_VERSION=dedddcb
ARG MAKE_JOBS=2

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        autoconf \
        automake \
        libtool \
        pkg-config \
        bison \
        flex \
        ca-certificates \
        curl \
        git \
        make \
        xz-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build

COPY patches/ /build/patches/
COPY build.sh /build/build.sh
RUN chmod +x /build/build.sh

VOLUME ["/output"]

ENTRYPOINT ["/build/build.sh"]
CMD []
