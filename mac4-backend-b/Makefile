# Team 1 student deliverables. Place this file next to ROLE and run/lan.
# Mac 1 DNS; Mac 2 primary edge; Mac 3 backend A/client; Mac 4 B/DNS/standby/client.
# make start starts this Mac only. Existing certificates and client trust are reused.
# make capture runs until Ctrl-C. make watch records TTL changes for one minute.
# make isolate/restore run on BOTH backend Macs. make bundle exports this role.
# Each action logs date, machine and output. Failed probes are evidence, not passes.
# Compatible with GNU Make 3.81 on macOS. No external lab shell script required.
SHELL := /bin/bash
.DEFAULT_GOAL := start

define PROGRAM
#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
role=$(cat ROLE)
mkdir -p run evidence
if [[ ${1:-} == setup ]]; then
  command -v brew >/dev/null || { echo 'Install Homebrew and enable brew in PATH first.'; exit 1; }
  brew install python
  case $role in 1|4) brew install dnsmasq;; esac
  case $role in 2|4) brew install nginx openssl@3;; esac
  python3 - <<'PY'
import ipaddress
from pathlib import Path
ips = []
with open('/dev/tty') as tty:
    for i in range(1,5):
        print(f'Mac {i} LAN IPv4: ',end='',flush=True)
        ip = str(ipaddress.IPv4Address(tty.readline().strip()))
        if ip in ips: raise SystemExit('Each Mac needs its own address')
        ips.append(ip)
Path('run/lan').write_text(''.join(f'M{i}={ip}\n' for i,ip in enumerate(ips,1)))
PY
  exit
fi
source run/lan
iface=$(route -n get default | awk '/interface:/{print $2}')
url=https://app.team1.test:8443
# Internal dispatcher: every operation is implemented here in the Makefile.
self() { /bin/bash -c "$REVIEW_PROGRAM" ./Makefile "$@"; }
stop_dns() {
  local f=run/review-dns.pid pid cmd
  [[ -s $f ]] || { echo "No DNS PID from this Makefile. Check sudo lsof -nP -iUDP:53"; return 1; }
  pid=$(cat "$f"); [[ $pid =~ ^[1-9][0-9]*$ ]]
  cmd=$(ps -ww -p "$pid" -o command=)
  [[ $cmd == *dnsmasq* && $cmd == *"--conf-file=$PWD/run/dns.conf"* ]] || return 1
  sudo kill -TERM "$pid"
  for i in {1..30}; do sudo kill -0 "$pid" 2>/dev/null || return 0; sleep .1; done
  return 1
}
start_backend() {
  local port=3001; [[ $role == 3 ]] || port=3002
  if curl --noproxy '*' -fsS --max-time 1 "http://127.0.0.1:$port/api/status" >/dev/null 2>&1; then
    echo "Port $port already active. Check make status."; return
  fi
  nohup /bin/bash -c "$REVIEW_PROGRAM" ./Makefile backend </dev/null >run/backend.log 2>&1 &
  local pid=$!
  for i in {1..30}; do
    kill -0 "$pid" || { cat run/backend.log; return 1; }
    if curl --noproxy '*' -fsS --max-time 1 "http://127.0.0.1:$port/api/status" >/dev/null 2>&1; then
      echo "$pid" >run/review-backend.pid; return 0
    fi
    sleep .1
  done
  echo "Backend failed readiness check; inspect run/backend.log"; return 1
}
case ${1:-} in
 start)
  var=M$role
  [[ $(ipconfig getifaddr "$iface") == "${!var}" ]] || { echo "Local LAN IP differs from run/lan. Check interface and team addresses."; exit 1; }
  case $role in 3|4) start_backend;; esac
  case $role in 2|4)
    if [[ -s run/nginx.pid ]] && ps -p "$(cat run/nginx.pid)" -o command= | grep -F "$PWD/run/nginx.conf" >/dev/null; then echo 'Edge already running'; else self edge; fi;; esac
  case $role in 1|4)
    if [[ -s run/review-dns.pid ]] && ps -ww -p "$(cat run/review-dns.pid)" -o command= | grep -F -- "--conf-file=$PWD/run/dns.conf" >/dev/null; then echo 'DNS already running'; else self dns primary; fi;; esac
  case $role in 3|4) self resolver two;; esac
  self inventory ;;
 status) hostname; sudo lsof -nP -iTCP -sTCP:LISTEN; sudo lsof -nP -iUDP:53 || true ;;
 dns-stop) stop_dns ;;
 dns-primary|dns-standby|dns-wrong)
  [[ ! -s run/review-dns.pid ]] || stop_dns
  self dns "${1#dns-}" ;;
 backend-start) [[ $role == 3 || $role == 4 ]]; start_backend ;;
 backend-stop)
  pid=$(cat run/review-backend.pid); [[ $pid =~ ^[1-9][0-9]*$ ]]
  ps -ww -p "$pid" -o command= | grep -F -- "$PWD/backend.py" >/dev/null
  kill -TERM "$pid"; rm run/review-backend.pid ;;
 balance) for i in {1..6}; do /usr/bin/curl --noproxy '*' --max-time 8 -fsSI "$url/api/status"; done ;;
 probe) for endpoint in "$M3:3001" "$M4:3002"; do nc -vz -w 2 "${endpoint%:*}" "${endpoint#*:}" || echo "Connection failed"; done ;;
 lookup) for ip in "$M1" "$M4"; do dig +tries=1 +time=2 @"$ip" app.team1.test; done; dscacheutil -q host -a name app.team1.test ;;
 https) /usr/bin/curl --noproxy '*' --max-time 20 -vi "$url/api/status" ;;
 wrong-port) /usr/bin/curl --noproxy '*' --max-time 4 -vi https://app.team1.test:8442/ ;;
 watch) self flush; for i in {1..30}; do date '+%T'; /usr/bin/curl --noproxy '*' --max-time 3 -sSI "$url/" || echo 'request failed'; sleep 2; done ;;
 client-one|client-two|client-wrong) self resolver "${1#client-}" ;;
 diagnose) self lookup; nc -vz -w 3 app.team1.test 8443 || true; self https ;;
 bundle)
  out="submission-Mac$role-$(date +%Y%m%d-%H%M%S).zip"
  cat > evidence/network-inventory.md <<DOC
# Team 1 private LAN
| Machine | IPv4 | Services |
|---|---|---|
| Mac 1 | $M1 | Primary DNS, UDP/TCP 53 |
| Mac 2 | $M2 | Primary HTTPS edge, TCP 8443 |
| Mac 3 | $M3 | Backend A, TCP 3001; test client |
| Mac 4 | $M4 | Backend B, TCP 3002; backup DNS, UDP/TCP 53; standby HTTPS, TCP 8443; test client |
Flow: client queries Mac 1 or Mac 4, then connects via TLS to the returned edge.
The edge forwards HTTP to A or B. During isolation only Mac 2 may access the backend ports over the LAN.
Use inventory.txt from each Mac for the observed interface, gateway, netmask, MAC address and ping results.
DOC
  if [[ ! -e evidence/phase2-report.md ]]; then
    { echo '# Phase 2 results'; for extension in 'A Backup DNS' 'B TTL and cache flush' 'C Isolation and rollback' 'D Backend failure and recovery' 'E Standby edge cutover' 'F Faculty troubleshooting'; do
        printf '\n## %s\nChange and prediction:\nObserved result and evidence filename:\nDiagnosis or recovery:\nWhat we learned:\n' "$extension"
      done; } > evidence/phase2-report.md
  fi
  files=(Makefile ROLE run/lan evidence)
  for f in backend.py RUNBOOK.md run/dns.conf run/nginx.conf run/pf.rules run/pf.before edge-2.crt edge-4.crt; do [[ ! -f $f ]] || files+=("$f"); done
  zip -qr "$out" "${files[@]}"; unzip -tq "$out"; echo "$out" ;;
 inventory)
  { hostname; ifconfig "$iface"; route -n get default; for ip in "$M1" "$M2" "$M3" "$M4"; do ping -c 2 "$ip"; done; } 2>&1 | tee evidence/inventory.txt ;;
 backend)
  case $role in 3) export BACKEND=A PORT=3001;; 4) export BACKEND=B PORT=3002;; *) exit 2;; esac
  exec python3 "$PWD/backend.py" ;;
 dns)
  case $role in 1) bind=$M1;; 4) bind=$M4;; *) exit 2;; esac
  case ${2:-primary} in primary) target=$M2;; standby) target=$M4;; wrong) target=$M3;; *) exit 2;; esac
  cat > run/dns.conf <<CFG
port=53
listen-address=$bind
bind-interfaces
no-resolv
no-hosts
local=/team1.test/
host-record=app.team1.test,$target,30
host-record=api.team1.test,$target,30
CFG
  sudo "$(brew --prefix dnsmasq)/sbin/dnsmasq" --pid-file="$PWD/run/review-dns.pid" --conf-file="$PWD/run/dns.conf" ;;
 cert)
  case $role in 2|4);; *) exit 2;; esac
  umask 077
  [[ ! -e run/edge.key && ! -e edge-$role.crt ]] || { echo 'Certificate already generated. Keep existing pair.'; exit 1; }
  "$(brew --prefix openssl@3)/bin/openssl" req -new -newkey rsa:2048 -nodes -x509 -days 180 -sha256 -keyout run/edge.key -out edge-$role.crt -subj "/CN=app.team1.test" -addext "subjectAltName=DNS:app.team1.test,DNS:api.team1.test" -addext "extendedKeyUsage=serverAuth" ;;
 trust)
  case ${2:-} in edge-2.crt|edge-4.crt);; *) exit 2;; esac
  sudo security add-trusted-cert -d -r trustRoot -p ssl -k /Library/Keychains/System.keychain "$2" ;;
 edge)
  case $role in 2|4);; *) exit 2;; esac
  cat > run/nginx.conf <<CFG
worker_processes 1;
pid "$PWD/run/nginx.pid";
error_log "$PWD/run/error.log";
events { worker_connections 128; }
http {
 access_log "$PWD/run/access.log";
 upstream pool {
  server $M3:3001 max_fails=1 fail_timeout=5s;
  server $M4:3002 max_fails=1 fail_timeout=5s;
 }
 server {
  listen 8443 ssl;
  server_name app.team1.test api.team1.test;
  ssl_certificate "$PWD/edge-$role.crt";
  ssl_certificate_key "$PWD/run/edge.key";
  ssl_protocols TLSv1.2;
  add_header X-Edge Mac$role always;
  location / {
   proxy_pass http://pool;
   proxy_http_version 1.1;
   proxy_set_header Host \$host;
   proxy_connect_timeout 2s;
   proxy_next_upstream error timeout;
   proxy_next_upstream_tries 2;
  }
 }
}
CFG
  nginx -t -c "$PWD/run/nginx.conf"
  nginx -c "$PWD/run/nginx.conf" ;;
 resolver)
  sudo mkdir -p /etc/resolver
  [[ ! -e /etc/resolver/team1.test || -f run/resolver-owned ]] || { echo 'Existing team1.test resolver: preserve it and configure manually.'; exit 1; }
  case ${2:-one} in one) printf 'nameserver %s\n' "$M1";; two) printf 'nameserver %s\nnameserver %s\n' "$M1" "$M4";; wrong) printf 'nameserver %s\n' "$M3";; *) exit 2;; esac > run/resolver
  touch run/resolver-owned
  sudo install -m 644 run/resolver /etc/resolver/team1.test
  sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder ;;
 flush) sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder ;;
 capture) exec sudo tcpdump -i "$iface" -s0 -w "evidence/flow-$(date +%s).pcap" '(udp port 53 or tcp port 53 or tcp port 8443)' ;;
 test)
  set -o pipefail
  { dig @"$M1" app.team1.test; dig @"$M1" api.team1.test; dscacheutil -q host -a name app.team1.test
    /usr/bin/curl --noproxy '*' --max-time 12 -fv --http1.1 "$url/"
    for i in {1..6}; do /usr/bin/curl --noproxy '*' --max-time 12 -fsS -i "$url/api/status"; echo; done
    /usr/bin/curl --noproxy '*' --max-time 12 -fsSI "$url/cache-demo"
    /usr/bin/curl --noproxy '*' --max-time 12 -sSi -H 'If-None-Match: "team1-cache-v1"' "$url/cache-demo"
  } 2>&1 | tee "evidence/test-$(date +%s).txt" ;;
 isolate)
  case $role in 3) port=3001;; 4) port=3002;; *) exit 2;; esac
  anchor=com.apple/cn-team1
  sudo pfctl -sr | grep -F 'anchor "com.apple/*"' >/dev/null || { echo 'Default Apple filter anchor required'; exit 1; }
  [[ ! -e run/pf.token ]] || { echo 'Isolation already enabled'; exit 1; }
  sudo pfctl -a "$anchor" -sr > run/pf.before
  [[ ! -s run/pf.before ]] || { echo 'Project anchor already occupied'; exit 1; }
  printf 'pass in quick on %s inet proto tcp from %s to any port %s\nblock return in quick on %s inet proto tcp to any port %s\n' "$iface" "$M2" "$port" "$iface" "$port" > run/pf.rules
  sudo pfctl -n -a "$anchor" -f run/pf.rules
  sudo pfctl -E 2>&1 | tee run/pf.enable
  awk '/Token/{print $NF}' run/pf.enable > run/pf.token
  test -s run/pf.token
  sudo pfctl -a "$anchor" -f run/pf.rules ;;
 restore)
  test -s run/pf.token
  sudo pfctl -a com.apple/cn-team1 -f run/pf.before
  sudo pfctl -X "$(cat run/pf.token)"
  rm run/pf.token ;;
 unresolve) test -f run/resolver-owned; sudo rm -f /etc/resolver/team1.test; rm run/resolver-owned; sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder ;;
 *) echo 'See RUNBOOK.md'; exit 2;;
esac

endef
# Preserve shell dollar signs exactly when passing the embedded code to Bash.
export REVIEW_PROGRAM := $(value PROGRAM)
.PHONY: start status inventory test capture flush balance probe lookup https wrong-port watch client-one client-two client-wrong diagnose bundle dns-stop dns-primary dns-standby dns-wrong backend-start backend-stop isolate restore setup
start status inventory test capture flush balance probe lookup https wrong-port watch client-one client-two client-wrong diagnose bundle dns-stop dns-primary dns-standby dns-wrong backend-start backend-stop isolate restore setup:
	@mkdir -p evidence; set -o pipefail; { date; hostname; echo "make $@"; /bin/bash -c "$$REVIEW_PROGRAM" ./Makefile "$@"; } 2>&1 | tee "evidence/$@-$$(date +%Y%m%d-%H%M%S)-$$$$.txt"
