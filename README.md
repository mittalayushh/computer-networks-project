# Private Network Service Platform · Team 1

Four Macs serve two private names, `app.team1.test` and `api.team1.test`. In Phase 1, a client resolves either name to Mac 2 and connects over HTTPS. Nginx terminates TLS and selects one of two HTTP backends. Phase 2 adds a second DNS server, a standby edge, backend access control and recovery exercises.

**Team:** Ayush Mittal (2401020091), Saumya Soni (2401020058), Anurag Kumar (2401010088).

| Mac | Role | LAN service | Directory |
|---|---|---|---|
| 1 | Private DNS | dnsmasq, UDP/TCP 53 | `mac1-dns` |
| 2 | Primary edge | Nginx, HTTPS/TCP 8443 | `mac2-edge` |
| 3 | Backend A and test client | Python HTTP/TCP 3001 | `mac3-backend-a` locally or `mac3-backend-a 2` in the published checkout |
| 4 | Backend B and test client | Python HTTP/TCP 3002. Phase 2 adds DNS on 53 and HTTPS on 8443 | `mac4-backend-b` |

```text
Client on Mac 3 or 4 ── DNS query ──────► Mac 1 (or Mac 4 in Phase 2)
                     ◄─ edge IP + TTL ──┘
Client               ── TLS on 8443 ───► Mac 2 (or Mac 4 after cutover)
                                             ├── HTTP ──► Mac 3:3001 / A
                                             └── HTTP ──► Mac 4:3002 / B
```

## 1. Prepare the LAN and role directories

Use four Macs on the same private LAN with peer communication enabled. Each needs Terminal, Homebrew in its PATH and admin access for its local setup. Have Wireshark available to inspect the capture. Internet access is needed for the initial checkout and dependency installation.

On each Mac, open the existing repository or clone it once:

```sh
git clone https://github.com/mittalayushh/computer-networks-project.git
cd computer-networks-project
```

From the repository root, **run only the line for that Mac**. Start each additional terminal tab in the same role directory.

```sh
cd mac1-dns                                                        # Mac 1
cd mac2-edge                                                       # Mac 2
if [ -d mac3-backend-a ]; then cd mac3-backend-a; else cd 'mac3-backend-a 2'; fi  # Mac 3
cd mac4-backend-b                                                  # Mac 4
```

Check the role number and share each Mac's current LAN address. If the default route uses a VPN, select the private LAN route before continuing.

```sh
cat ROLE
iface=$(route -n get default | awk '/interface:/{print $2}')
ipconfig getifaddr "$iface"
```

On **all four Macs**, run the following and enter the same four current IPs in Mac 1–4 order. Setup installs the role dependencies and writes `run/lan`. Inventory prints interface details, gateway and ping results. Record each IP, netmask, interface, MAC address and gateway for Task A. Check for replies from every peer in each Mac's output.

```sh
bash lab setup
bash lab inventory
cat run/lan
```

In each **test tab**, load these variables. The examples use the macOS system curl and bypass any configured HTTP proxy for the lab.

```sh
source run/lan
u=https://app.team1.test:8443
labcurl() { /usr/bin/curl --noproxy '*' --max-time 15 "$@"; }
```

## 2. Start Phase 1

The service commands below run in the foreground. Keep each in its own tab so that Ctrl-C stops exactly the service you are testing. Use a separate tab for probes. If a port is already occupied, inspect its owner with `make status` before starting a second copy. Saved logs, PID files and generated configs in a checkout describe an earlier run.

1. **Mac 3 and Mac 4** each run `bash lab backend`. From **Mac 2**, run the following checks. Expect HTTP 200, JSON with `status` set to `ok`, and the corresponding `X-Backend` header.

   ```sh
   labcurl -i "http://$M3:3001/api/status"
   labcurl -i "http://$M4:3002/api/status"
   ```

2. Before configuring a client, check whether it already has a `/etc/resolver/team1.test` file. If it does, save a copy and restore it after the demo. The checkout may contain an old `run/resolver-owned` marker.

   **Mac 1** runs `bash lab dns primary`. **Mac 3 and Mac 4** each run `bash lab resolver one`. This configures macOS to use Mac 1 for the project domain. On both clients, verify the two records and the system resolver. All should return Mac 2's address.

   ```sh
   dig @"$M1" app.team1.test A +noall +answer
   dig @"$M1" api.team1.test A +noall +answer
   dscacheutil -q host -a name app.team1.test
   ```

3. **Mac 2** prepares its TLS identity. Reuse its valid matching `edge-2.crt` and `run/edge.key` if available. A fresh clone includes the public certificate only. In that case, archive that certificate and generate a new local pair using the commands below. Use the same procedure on **Mac 4** with its own role number when preparing the standby. Keep each private key on the edge that generated it.

   ```sh
   crt="edge-$(cat ROLE).crt"
   if [ -f "$crt" ] && [ ! -e run/edge.key ]; then
     saved=$(mktemp -d)
     mv "$crt" "$saved/"
     echo "Previous public certificate saved in $saved"
   fi
   if [ ! -e "$crt" ] && [ ! -e run/edge.key ]; then bash lab cert; fi
   openssl x509 -in "$crt" -noout -dates -subject
   shasum -a 256 "$crt"
   ```

4. Copy **Mac 2's current public certificate** into both client role directories. On each client, compare `shasum -a 256 edge-2.crt` with Mac 2's output, then run `bash lab trust edge-2.crt`. **Mac 2** runs `bash lab edge`. It generates and checks the Nginx config for this checkout before listening on 8443.

## 3. Verify the healthy Phase 1 path

On **Mac 3**, run `bash lab capture` in one tab. In a second test tab, run:

```sh
bash lab flush
labcurl -v --http1.1 "$u/"
labcurl -i "$u/api/status"
make balance
labcurl -I "$u/cache-demo"
labcurl -i -H 'If-None-Match: "team1-cache-v1"' "$u/cache-demo"
```

Stop the capture with Ctrl-C. On **both clients**, run `bash lab test` for the recorded DNS, HTTPS, load-balancing and cache checks, and open `https://app.team1.test:8443/` in a browser.

| Task | What to verify and save |
|---|---|
| A · LAN | The four inventories, peer ping results and topology above with your live addresses. |
| B · DNS | Both names resolve through Mac 1 on two clients. DNS supplies the address used for the subsequent TCP connection. |
| C · REST | Both backend ports answer from Mac 2. GET requests to `/` and `/api/status` through the edge return backend identity and status. |
| D · Load balancing | Repeated requests to one URL show `X-Edge: Mac2` and both `X-Backend: A` and `B`. Nginx uses round robin over the two upstreams. |
| E · TLS | The browser accepts the edge certificate and verbose curl completes hostname and trust validation. Nginx decrypts the request and opens a separate HTTP connection to the backend. |
| F · Caching | The first cache probe returns 200, `Cache-Control: max-age=60` and an ETag. The conditional GET returns 304 with no body. A fresh cache hit can skip the network request. Revalidation sends a request but can reuse the stored body. An ordinary GET transfers the body. |
| G · Packet evidence | Open the new `evidence/flow-*.pcap` in Wireshark. Filter on `dns` for the question and A answer, then `tcp.port == 8443` for the SYN, SYN-ACK and ACK. Record both IPs, the ephemeral client port, service port, and sequence/ACK numbers. Decode 8443 as TLS if needed. Identify ClientHello, ServerHello, Certificate, key exchange, ChangeCipherSpec and encrypted handshake/application records. Use verbose curl for the HTTP headers visible at the endpoint. |

**Protocol discussion.** Wi-Fi/Ethernet carries IP, which carries UDP or TCP. DNS normally uses UDP here. HTTPS carries HTTP over TLS over TCP. TCP acknowledgements identify the next byte expected, retransmissions recover loss, and the receive window limits outstanding data. The DNS service corresponds to a private hosted zone, Nginx to an application load balancer, and the backends to application instances. HTTP/3 uses QUIC over UDP. SMTP sends mail and IMAP synchronizes a mailbox.

**HTTP/2 when supported.** On Mac 2, check `nginx -V 2>&1` for `--with-http_v2_module`, and check `/usr/bin/curl -V` on the client for HTTP2. To demonstrate it, stop the foreground edge, copy `run/nginx.conf` to `run/nginx-h2.conf` and enable HTTP/2 in that copy's TLS server block (`http2 on;` on Nginx 1.25.1+, or `listen 8443 ssl http2;` on older builds supporting HTTP/2). Run `nginx -t -c "$PWD/run/nginx-h2.conf"`, then `nginx -c "$PWD/run/nginx-h2.conf" -g 'daemon off;'`. From the client, run `labcurl --http2 -v "$u/"` and verify negotiation of h2. Stop that edge and restart `bash lab edge` for the remaining tests.

## 4. Run the five Phase 1 failure tests

Start with both backends healthy and the client using Mac 1 DNS. Run each row in order, saving the output and restoring the baseline before the next row. Client commands below run on **Mac 3**.

| Fault | Change and client probe | Expected observation and recovery |
|---|---|---|
| Wrong client resolver | On Mac 3 run `bash lab resolver wrong`, then `labcurl -v "$u/"` and `ping -c 2 "$M2"`. | Name lookup fails or times out while the edge IP still answers. Run `bash lab resolver one` and retry HTTPS. |
| Wrong A record | On Mac 1 stop DNS with Ctrl-C and run `bash lab dns wrong`. On Mac 3 run `bash lab flush`, `dig @"$M1" app.team1.test +short` and `labcurl -v "$u/"`. | DNS now returns Mac 3, where no edge is listening. Restart Mac 1 DNS with `bash lab dns primary`, flush Mac 3 and retry. |
| One backend down | Stop only Mac 3's backend with Ctrl-C. Run `make balance`. | Requests succeed through B. Restart `bash lab backend` on Mac 3, wait six seconds, then verify both headers reappear. |
| Both backends down | Stop the backend tabs on Macs 3 and 4. Run `labcurl -vi "$u/api/status"`. | DNS and TLS succeed, followed by HTTP 502 from Nginx. Restart both backends, wait six seconds and rerun `make balance`. |
| Wrong destination port | Run `ping -c 2 "$M2"` and `make wrong-port`. | The IP responds but TCP to the unused port 8442 fails. Repeat with `labcurl -i "$u/"` on 8443. |

## 5. Run Phase 2 on the same LAN

### A. Prove backup DNS answers with the primary offline

On **Mac 4**, leave backend B running and start `bash lab dns primary` in another tab. Here `primary` selects **Mac 2 as the answer**. Both DNS servers now publish the same records. On **both clients**, run `bash lab resolver two`. On Mac 3, run `make lookup` and start a new `bash lab capture` in another tab. Stop **Mac 1 DNS** with Ctrl-C. On Mac 3 run:

```sh
bash lab flush
dig @"$M4" app.team1.test +noall +answer
dscacheutil -q host -a name app.team1.test
labcurl -i "$u/api/status"
```

Allow time for resolver retries. In the capture, identify the system lookup and reply from Mac 4 after the explicit dig. Restart Mac 1 with `bash lab dns primary`. Losing all DNS servers prevents fresh name resolution. Losing a backend leaves resolution operational.

### C. Isolate backend ports and prove rollback

Run this before migrating the edge. From **Mac 1 and Mac 2**, run `make probe` and record baseline connectivity. On **each backend Mac**, inspect the current project anchor, apply the role rule and display it:

```sh
sudo pfctl -a com.apple/cn-team1 -sr
bash lab isolate
sudo pfctl -a com.apple/cn-team1 -sr
```

The helper saves the prior anchor in `run/pf.before` and records a PF enable token. Repeat `make probe` on Mac 2 (both ports reachable) and Mac 1 (both blocked). Inspect each connection result because the probe logs expected failures and continues. On Mac 3, `make balance` should still reach A and B through Mac 2. On **both backends**, run `bash lab restore`, inspect the anchor again and repeat both Macs' probes. Save the before, isolated and restored observations.

### D. Demonstrate backend failover and recovery

From Mac 3, run `make balance` before, during and after stopping its backend tab. During the outage, every successful response should identify B. Restart `bash lab backend`, wait six seconds, then confirm A and B both appear again. Nginx retries failed connections and temporarily avoids a failed upstream (`max_fails=1 fail_timeout=5s`). Mac 2 remains a single point of failure for clients directed to it. Automatic edge failover would require health detection and a coordinated switch to the standby.

### B and E. Measure the DNS TTL during a controlled edge migration

1. On **Mac 4**, prepare its certificate/key pair as in setup, distribute the current `edge-4.crt`, and verify its checksum on the clients. Run `bash lab trust edge-4.crt` on both clients. Start `bash lab edge` on Mac 4 in a third service tab. Keep Mac 2's edge running. From Mac 3, verify the standby independently of DNS:

   ```sh
   labcurl --resolve "app.team1.test:8443:$M4" -I "$u/"
   ```

   Expect `X-Edge: Mac4` with successful TLS validation.
2. With both DNS services still in primary mode, run `dig @"$M1" app.team1.test +noall +answer` on **Mac 3**. Verify the Mac 2 address and 30-second TTL. Start `make watch` on Mac 3. It flushes once, then samples a new HTTPS connection every two seconds. Wait for the first `X-Edge: Mac2`.
3. Immediately stop the **DNS tabs only** on Macs 1 and 4 and restart both with `bash lab dns standby`. On Mac 4 run `make lookup`, `bash lab flush` and `labcurl -I "$u/"`. Both direct DNS answers should now name Mac 4. The freshly flushed client should reach Mac 4 while the primed Mac 3 may still reach Mac 2 until expiry. Record timestamps and headers from both clients. If the transition took longer than the TTL, repeat it to capture the cached interval.
4. To demonstrate manual flushing, prime Mac 3 on the standby with `bash lab flush` and `labcurl -I "$u/"`. Switch **both** DNS services back with `bash lab dns primary`. Before 30 seconds elapse, compare Mac 3's `labcurl -I "$u/"` before and after `bash lab flush`. Verify the post-flush request reaches Mac 2. DNS changes steer new connections as each client's cache refreshes.

### F. Diagnose a faculty-injected fault

Run the following on **Mac 3** in order. Record the first unexpected result, one hypothesis and the test that distinguishes it. After correcting the affected service or setting, repeat the failing test and the end-to-end request.

| Layer | Command | What the result tells you |
|---|---|---|
| DNS | `make lookup` | Compare each DNS server's answer and TTL with the macOS system lookup. Disagreement can identify a stale cache or inconsistent records. |
| TCP | `nc -vz -w 3 app.team1.test 8443` | With the correct address, a refusal or timeout points toward listener, port or reachability problems. |
| TLS | `labcurl -v "$u/"` | Inspect handshake, hostname and certificate trust before interpreting the HTTP status. |
| HTTP/upstream | `labcurl -i "$u/api/status"` | Inspect status, body, `X-Edge` and `X-Backend`. For a 502, run `make probe` and `tail -n 30 run/error.log` on the active edge, then check the relevant backend listener with `make status`. |

## 6. Save evidence, present and clean up

Keep the four inventories, live IP/service map, generated DNS/Nginx configs, firewall baseline and rules, packet captures, curl headers and failure/recovery transcripts. Make targets log under `evidence/`. For manual probes, start `script "evidence/session-$(date +%Y%m%d-%H%M%S).txt"` before the commands and type `exit` when finished. Save a Phase 1 config snapshot before cutover. Run `make bundle` in each role directory to create its local submission ZIP. Complete `evidence/phase2-report.md` with the change, prediction, observed result, evidence filename, diagnosis and learning for each extension, then bundle again to include the final report.

**Live review order (project brief §8):** (1) topology and inventory, (2) peer pings, (3) private DNS, (4) trusted HTTPS by name, (5) A/B responses, (6) DNS/TCP/TLS capture, (7) caching and 304, (8) single-backend failure, (9) Phase 2 resilience and cutover, (10) faculty fault diagnosis, (11) individual viva.

After the review, restore any active isolation on both backends with `bash lab restore`. Stop the lab's foreground services with Ctrl-C in their own tabs. On each client where this session installed the domain resolver, run `bash lab unresolve`. Remove the lab trust entries you installed using Keychain Access, matching the certificates to the copies used for this run.
