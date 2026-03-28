#!/usr/bin/env bash

# fail on error
set -e

# Retry 5 times with a wait of 10 seconds between each retry
tryfail() {
    for i in $(seq 1 5);
        do [ $i -gt 1 ] && sleep 10; $* && s=0 && break || s=$?; done;
    (exit $s)
}

# Import Ubiquiti signing key into /etc/apt/keyrings/ (replaces deprecated apt-key)
addKey() {
    mkdir -p /etc/apt/keyrings
    GNUPGHOME=$(mktemp -d)
    export GNUPGHOME
    for server in hkp://keyserver.ubuntu.com:80 \
        keyserver.ubuntu.com \
        hkp://pgp.mit.edu:80; do
        if gpg --keyserver "$server" --recv-keys "$1" 2>/dev/null; then
            gpg --export "$1" | gpg --dearmor -o /etc/apt/keyrings/ubnt-unifi.gpg
            rm -rf "$GNUPGHOME"
            return 0
        fi
    done
    rm -rf "$GNUPGHOME"
    return 1
}

if [ "x${1}" == "x" ]; then
    echo please pass PKGURL as an environment variable
    exit 0
fi

apt-get update
apt-get install -qy --no-install-recommends \
    apt-transport-https \
    curl \
    dirmngr \
    gpg \
    gpg-agent \
    openjdk-21-jre-headless \
    procps \
    libcap2-bin \
    tzdata
echo 'deb [signed-by=/etc/apt/keyrings/ubnt-unifi.gpg] https://www.ui.com/downloads/unifi/debian stable ubiquiti' | tee /etc/apt/sources.list.d/100-ubnt-unifi.list
tryfail addKey 06E85760C0A52C50

# Add MongoDB 8.0 repo so apt can satisfy the UniFi package dependency.
# Ubuntu 24.04 does not ship MongoDB in its default repos.
# MongoDB 8.0 is the first release with native Ubuntu 24.04 (Noble) support.
curl -fsSL https://www.mongodb.org/static/pgp/server-8.0.asc | \
    gpg --dearmor -o /etc/apt/keyrings/mongodb-server-8.0.gpg
echo "deb [ arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu noble/mongodb-org/8.0 multiverse" | \
    tee /etc/apt/sources.list.d/mongodb-org-8.0.list
apt-get update

if [ -d "/usr/local/docker/pre_build/$(dpkg --print-architecture)" ]; then
    find "/usr/local/docker/pre_build/$(dpkg --print-architecture)" -type f -exec '{}' \;
fi

curl -L -o ./unifi.deb "${1}"
apt -qy install ./unifi.deb
rm -f ./unifi.deb
chown -R unifi:unifi /usr/lib/unifi
rm -rf /var/lib/apt/lists/*

rm -rf ${ODATADIR} ${OLOGDIR} ${ORUNDIR} ${BASEDIR}/data ${BASEDIR}/run ${BASEDIR}/logs
mkdir -p ${DATADIR} ${LOGDIR} ${RUNDIR}
ln -s ${DATADIR} ${BASEDIR}/data
ln -s ${RUNDIR} ${BASEDIR}/run
ln -s ${LOGDIR} ${BASEDIR}/logs
ln -s ${DATADIR} ${ODATADIR}
ln -s ${LOGDIR} ${OLOGDIR}
ln -s ${RUNDIR} ${ORUNDIR}
mkdir -p /var/cert ${CERTDIR}
ln -s ${CERTDIR} /var/cert/unifi

rm -rf "${0}"
