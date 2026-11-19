# Same Crystal as CI. The non-alpine image is Ubuntu-based, which dev container
# features (sshd for `gh codespace ssh`, for one) need.
FROM crystallang/crystal:1.22.0

# The Crystal image already has most of what the build links against; what
# it lacks is libzstd-dev (and curl, for the step below).
#
# archive.ubuntu.com is not always reachable from cloud build hosts: the first
# build of this image timed out on it from both a GitHub runner and a
# Codespace. `apt-get update` still exits 0 when that happens, so the install
# is what fails. On failure, switch to the Azure mirror, which is the one
# GitHub's own runners use, and try once more.
RUN set -eu; \
    install() { \
      apt-get update -o Acquire::Retries=1 -o Acquire::http::Timeout=15 \
      && apt-get install -y --no-install-recommends \
           libyaml-dev libzstd-dev zlib1g-dev pkg-config git curl ca-certificates; \
    }; \
    install || { \
      find /etc/apt -name '*.sources' -o -name 'sources.list' | xargs -r sed -i \
        -e 's|http://archive.ubuntu.com/ubuntu|http://azure.archive.ubuntu.com/ubuntu|g' \
        -e 's|http://security.ubuntu.com/ubuntu|http://azure.archive.ubuntu.com/ubuntu|g'; \
      install; \
    }; \
    rm -rf /var/lib/apt/lists/*

# `just` is not packaged for every Ubuntu release this image has been based on.
RUN curl --proto '=https' --tlsv1.2 -sSf https://just.systems/install.sh \
  | bash -s -- --to /usr/local/bin
