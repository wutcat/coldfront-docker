FROM docker.io/ubuntu:23.04 as builder

###
# Build stage
###

RUN export DEBIAN_FRONTEND=noninteractive \
    && apt-get update -qq \
    && apt-get upgrade \
      --yes -qq --no-install-recommends \
    && apt-get install \
      --yes -qq --no-install-recommends \
      build-essential \
      ca-certificates \
      libldap-dev \
      libpq-dev \
      libsasl2-dev \
      libssl-dev \
      libxml2-dev \
      libxmlsec1 \
      libxmlsec1-dev \
      libxmlsec1-openssl \
      libxslt-dev \
      pkg-config \
      python3-dev \
      python3-pip \
      python3-venv \
    && python3 -m venv /srv/coldfront/venv \
    && /srv/coldfront/venv/bin/python3 -m pip install --upgrade \
      pip \
      setuptools \
      wheel \
      coldfront \
      psycopg \
      ldap3 \
      django_auth_ldap \
      mozilla_django_oidc

###
# Main stage
###

FROM docker.io/ubuntu:23.04 as main

RUN export DEBIAN_FRONTEND=noninteractive \
    && apt-get update -qq \
    && apt-get upgrade \
      --yes -qq --no-install-recommends \
    && apt-get install \
      --yes -qq --no-install-recommends \
      bzip2 \
      ca-certificates \
      curl \
      libldap-common \
      libpq5 \
      libxmlsec1-openssl \
      openssh-client \
      openssl \
      python3 \
      python3-distutils \
      tini \
    && curl --silent --output /usr/share/keyrings/nginx-keyring.gpg \
      https://unit.nginx.org/keys/nginx-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/nginx-keyring.gpg] https://packages.nginx.org/unit/ubuntu/ lunar unit" \
      > /etc/apt/sources.list.d/unit.list \
    && apt-get update -qq \
    && apt-get install \
      --yes -qq --no-install-recommends \
      unit=1.30.0-1~lunar \
      unit-python3.11=1.30.0-1~lunar \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /srv/coldfront /srv/coldfront

COPY docker/docker-entrypoint.sh /srv/coldfront/docker-entrypoint.sh
COPY docker/launch-coldfront.sh /srv/coldfront/launch-coldfront.sh
COPY docker/nginx-unit.json /etc/unit/

WORKDIR /srv/coldfront/

RUN mkdir -p static /opt/unit/state/ /opt/unit/tmp/ \
      && chown -R unit:root /opt/unit/ \
      && chmod -R g+w /opt/unit/ \
      && STATIC_ROOT="/srv/coldfront/static" SECRET_KEY="dummyKeyWithMinimumLength-------------------------" /srv/coldfront/venv/bin/coldfront collectstatic --no-input

ENV LANG=C.utf8 PATH=/srv/coldfront/venv/bin:$PATH
ENTRYPOINT [ "/usr/bin/tini", "--" ]

CMD [ "/srv/coldfront/docker-entrypoint.sh", "/srv/coldfront/launch-coldfront.sh" ]
