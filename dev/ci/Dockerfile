# The frozen Debian snapshot fixes the package index, including transitive tools.
FROM python@sha256:2a928e11761872b12003515ea59b3c40bb5340e2e5ecc1108e043f92be7e473d
SHELL ["/bin/bash", "-euo", "pipefail", "-c"]
RUN printf 'deb [check-valid-until=no] https://snapshot.debian.org/archive/debian/20260921T000000Z/ trixie main\n' > /etc/apt/sources.list \
    && rm /etc/apt/sources.list.d/debian.sources \
    && apt-get update \
    && apt-get install --no-install-recommends -y ca-certificates curl git unzip xz-utils zip libglu1-mesa \
    && rm -rf /var/lib/apt/lists/*
COPY toolchain.lock.json install_tools.py json_boundary.py /opt/haruka-ci/
RUN python /opt/haruka-ci/install_tools.py \
    && ln -s /opt/node-v24.18.0-linux-x64 /opt/node \
    && git config --global --add safe.directory /opt/flutter
ENV PATH="/opt/flutter/bin:/opt/node/bin:${PATH}" \
    CI=true \
    FLUTTER_SUPPRESS_ANALYTICS=true \
    DART_SUPPRESS_ANALYTICS=true \
    UV_PYTHON_DOWNLOADS=never
RUN flutter config --no-analytics \
    && flutter precache --web \
    && dpkg-query -W > /opt/haruka-ci/debian-packages.txt \
    && python --version && uv --version && flutter --version && node --version && npm --version
WORKDIR /work
CMD ["/bin/bash"]
