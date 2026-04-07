FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive
ENV USE_CCACHE=1
ENV CCACHE_DIR=/ccache

RUN apt-get update && apt-get install -y \
    bc bison build-essential ccache curl flex g++-multilib gcc-multilib \
    git gnupg gperf lib32ncurses5-dev lib32readline-dev lib32z1-dev \
    liblz4-tool libncurses5 libncurses5-dev libsdl1.2-dev libssl-dev \
    libxml2 libxml2-utils lzop pngcrush rsync schedtool squashfs-tools \
    xsltproc zip zlib1g-dev python3 python2 python-is-python2 openjdk-8-jdk \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://storage.googleapis.com/git-repo-downloads/repo \
    -o /usr/local/bin/repo && chmod a+x /usr/local/bin/repo

RUN update-java-alternatives --set java-1.8.0-openjdk-amd64

RUN git config --global user.email "build@local" && \
    git config --global user.name "LocalBuild" && \
    git config --global color.ui false && \
    git config --global --add safe.directory '*'

WORKDIR /build
