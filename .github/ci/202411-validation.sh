#!/bin/bash
set -euo pipefail

arch=$1
mode=$2
test "$(dpkg --print-architecture)" = "$arch"
mkdir -p ci-evidence
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates python3
deps="$HOME/release-202411-dependencies"
python3 .github/ci/202411-dependencies.py "$arch" "$deps" ci-evidence/dependencies.json
apt-get install -y --no-install-recommends \
    build-essential debhelper git sudo curl gcovr libevent-dev \
    libboost-system-dev libboost-thread-dev libboost-serialization-dev \
    libgtest-dev libgmock-dev libhiredis-dev redis-server "$deps"/*.deb
dpkg-query -W libboost-system1.74-dev libboost-thread1.74-dev libboost-serialization1.74-dev
dpkg-query -W > ci-evidence/packages.txt
g++ --version > ci-evidence/compiler.txt

if [ "$mode" = prepare ]; then
    exit 0
fi
test "$mode" = test
mkdir -p /var/run/redis
redis-server --daemonize yes --bind 127.0.0.1 --port 6379 \
    --save "" --appendonly no --unixsocket /var/run/redis/redis.sock --unixsocketperm 777
test "$(redis-cli -s /var/run/redis/redis.sock ping)" = PONG

dpkg-buildpackage -us -uc -b -j2
cp ../sonic-dhcp6relay*.deb ci-evidence/
cp build-test/dhcp6relay-test-test-result.xml ci-evidence/
cp build-test/dhcp6relay-test-code-coverage.xml ci-evidence/
ldd build/dhcp6relay | tee ci-evidence/linked-libraries.txt
if grep -q 'not found' ci-evidence/linked-libraries.txt; then
    echo "A runtime library is missing" >&2
    exit 1
fi
dpkg-deb -f ci-evidence/sonic-dhcp6relay_*.deb Package Version Architecture Depends \
    > ci-evidence/package-metadata.txt

# The inherited make test target masks the test process exit code.
python3 - <<'PY'
import json
import pathlib
import xml.etree.ElementTree as ET

root = ET.parse("build-test/dhcp6relay-test-test-result.xml").getroot()
cases = root.findall(".//testcase")
result = {
    "tests": int(root.attrib["tests"]),
    "failures": int(root.attrib.get("failures", 0)),
    "errors": int(root.attrib.get("errors", 0)),
    "disabled": int(root.attrib.get("disabled", 0)),
    "executed": sum(case.get("status") == "run" for case in cases),
}
pathlib.Path("ci-evidence/test-summary.json").write_text(json.dumps(result, indent=2) + "\n")
print(json.dumps(result, indent=2))
if (result["tests"] != len(cases) or not result["executed"]
        or result["failures"] or result["errors"]
        or root.findall(".//failure") or root.findall(".//error")):
    raise SystemExit("The complete existing unit suite did not pass")
PY

ASAN_OPTIONS=detect_leaks=0 ./build-test/dhcp6relay-test \
    --gtest_output=xml:ci-evidence/strict-test-result.xml
