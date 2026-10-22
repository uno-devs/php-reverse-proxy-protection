#!/bin/sh
# Builds the proxy, puts a stub backend behind it and checks the filtering.
set -eu
cd "$(dirname "$0")/.."

net=php2shell-test
docker network create "$net" >/dev/null 2>&1 || true
cleanup() { docker rm -f p2s-proxy p2s-backend >/dev/null 2>&1 || true; docker network rm "$net" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker build -q -t php-reverse-proxy-protection:test .
docker run -d --name p2s-backend --network "$net" nginxinc/nginx-unprivileged:1.28-alpine >/dev/null
docker run -d --name p2s-proxy --network "$net" -p 18080:8080 \
  --read-only --tmpfs /tmp --tmpfs /etc/nginx/conf.d --cap-drop ALL \
  -e UPSTREAM=http://p2s-backend:8080 -e UPLOAD_PATHS=/upload.php,/api/avatar \
  php-reverse-proxy-protection:test >/dev/null
sleep 3

fail=0
check() { # name expected curl-args...
  name=$1; want=$2; shift 2
  got=$(curl -s -o /dev/null -w '%{http_code}' "$@")
  if [ "$got" = "$want" ] || { [ "$want" = not403 ] && [ "$got" != 403 ]; }; then echo "ok   $name ($got)"; else echo "FAIL $name: want $want got $got"; fail=1; fi
}
u=http://127.0.0.1:18080

echo "uid: $(docker exec p2s-proxy id -u)"
check "GET passes"                 200 $u/
check "form POST passes"           not403 -X POST -d a=b $u/
check "multipart blocked"          403 -F a=b $u/index.php
check "multipart uppercase blocked" 403 -H 'Content-Type: MULTIPART/FORM-DATA; boundary=x' -d x $u/
check "multipart via PUT blocked"  403 -X PUT -H 'Content-Type: multipart/mixed; boundary=x' -d x $u/
check "upload path allowed"        not403 -F a=b $u/upload.php
check "upload path look-alike"     403 -F a=b $u/upload.php.bak
check "upload prefix trick"        403 -F a=b "$u/api/avatar/../x"
big=$(mktemp); head -c 9437184 /dev/zero > "$big"
check "oversized body"             413 -X POST -H 'Content-Type: application/x-www-form-urlencoded' --data-binary @"$big" $u/
rm -f "$big"
check "TRACE rejected"             405 -X TRACE $u/
check "health"                     200 $u/__proxy_health
exit $fail
