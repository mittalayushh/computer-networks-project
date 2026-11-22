# Team 1 private network • operator guide

## Start here

Use four Macs on one private Wi-Fi with client isolation disabled. Keep their DHCP addresses stable throughout the demo. Each Mac needs Homebrew in PATH, admin access for setup and an internet connection for initial package installation. The running lab uses only the LAN. Use Terminal in your extracted role folder for every command. Start a new tab in the same directory for each long-running command. Stop a foreground service with Control-C.

1. On every Mac run `ipconfig getifaddr "$(route -n get default | awk '/interface:/{print $2}')"`. Disable VPN routing or select the correct LAN interface before setup. Share the four addresses in Mac-number order.
2. Run `bash lab setup` on each Mac. Enter those same four IPs at its prompts. Run `bash lab inventory`. Collect the four evidence/inventory.txt files. Record IP, interface, ether (MAC), netmask/prefix and gateway for each role. Verify every peer replied.
3. Mac 3 and Mac 4 each run `bash lab backend`. Mac 1 runs `bash lab dns primary`.
4. On Mac 2 run `bash lab cert`. AirDrop only edge-2.crt into each client's extracted folder. Compare `shasum -a 256 edge-2.crt` with Mac 2's copy. On clients (use Macs 3 and 4, and Mac 1 if testing there) run `bash lab trust edge-2.crt` and `bash lab resolver one`. This installs a project-domain resolver without redirecting unrelated DNS. Keep the private key on its own edge. Mac 2 runs `bash lab edge`.
5. On Mac 3 start `bash lab capture`. In a second tab run `bash lab flush` then `bash lab test`. Stop capture. Repeat the test on Mac 4. Open https://app.team1.test:8443 in a client browser. Troubleshoot any trust warning before the demo. macOS dig uses its own resolver path, so the test checks both explicit DNS and system resolution.

## Architecture and packet walkthrough

| Mac | IP (fill from inventory) | Services and cloud equivalent |
|---|---|---|
|1| | Primary DNS UDP/TCP 53, private hosted zone |
|2| | Primary HTTPS edge TCP 8443, application load balancer |
|3| | A TCP 3001, application instance and test client |
|4| | B TCP 3002, backup DNS 53, standby edge 8443 and test client |

Client → DNS resolver → client (UDP 53 answer naming edge IP).
Client ephemeral TCP port → edge 8443 (SYN, SYN-ACK, ACK → TLS → encrypted HTTP).
Edge ephemeral TCP port → A:3001 or B:3002 (HTTP/1.1); backend → edge → client (response).
TLS ends at nginx. The client needs only the private domain. Layer mapping: Ethernet/Wi-Fi link, IP network, UDP/TCP transport, TLS above TCP, DNS/HTTP application.

Open the pcap in Wireshark. Filter dns, then tcp.port == 8443. If necessary use Decode As TLS. Label the query/answer, both socket endpoints, SYN/SYN-ACK/ACK, sequence and acknowledgement numbers, ClientHello, ServerHello, Certificate, ChangeCipherSpec, Finished and encrypted application records. Acknowledgements identify the next byte expected; TCP retransmits lost data. Use curl's verbose output to show decrypted headers at the endpoint. Use a fresh curl process and flush DNS before capturing. For HTTP/2, if nginx -V lists the HTTP/2 module, enable HTTP/2 for the TLS listener in the generated config (add http2 on; inside server on current nginx), restart using nginx -c "$PWD/run/nginx.conf" -g 'daemon off;' directly, and show curl --http2 -v output with an HTTP/2-capable client. HTTP/3 uses QUIC over UDP; SMTP sends mail, IMAP retrieves/synchronizes it.

## Phase 1 failure demonstrations

On Mac 3 define `u=https://app.team1.test:8443` and run `source run/lan` in your test tab. Save actual output for every test with screenshots or use `script evidence/failures.txt` to record a terminal session (exit to finish).

| Change | Probe and expected observation | Restore |
|---|---|---|
|Mac 3: bash lab resolver wrong|curl --max-time 8 "$u/" fails to resolve, ping -c 2 "$M2" works|bash lab resolver one|
|Mac 1: stop DNS, run bash lab dns wrong|Mac 3: bash lab flush; dig @"$M1" app.team1.test answers Mac 3; curl --max-time 5 "$u/" fails|Restart Mac 1 DNS with primary and flush client|
|Stop A|Repeated curl -i "$u/api/status" shows B only|Restart A; wait 6 seconds, repeat|
|Stop A and B|curl -i "$u/" shows nginx 502 after successful TLS|Restart both; wait 6 seconds|
|Use a closed edge port|curl --connect-timeout 3 https://app.team1.test:8442/ fails at TCP, ping still works|Return to 8443|

Cache demo: inspect an initial 200, max-age=60 and ETag, then a conditional GET returning 304 without the body (bash lab test). A fresh cache entry can be reused locally. A stale entry can be revalidated. A full GET transfers the representation.

## Phase 2, in order

1. **Backup DNS.** Mac 4 runs bash lab dns primary. On both clients run bash lab resolver two. On Mac 3 run source run/lan, then dig @"$M4" app.team1.test. Stop Mac 1 DNS, flush Mac 3 and use dscacheutil -q host -a name app.team1.test followed by /usr/bin/curl -i https://app.team1.test:8443/. Allow resolver retry time. Capture Mac 3 traffic to show the backup actually answered. Restart Mac 1 DNS. Losing DNS prevents new uncached resolution; losing one backend leaves name resolution intact.
2. **Isolation and rollback.** On Macs 3 and 4 run bash lab isolate. This uses the existing Apple wildcard anchor and retains a baseline and a PF enable token. On Mac 2 and then Mac 1 run source run/lan followed by nc -vz -w 2 "$M3" 3001 and nc -vz -w 2 "$M4" 3002. Both must succeed from Mac 2 and fail from Mac 1. Use fresh connections. Confirm client HTTPS still succeeds. Save results including sudo pfctl -a com.apple/cn-team1 -sr on each backend. Then run bash lab restore on BOTH backends and repeat probes to confirm restoration before moving the edge. Isolation and standby migration are separate demonstrations since the permitted source in the isolation exercise is Mac 2 alone.
3. **HA.** Repeat the single-backend stop and recovery from Phase 1. Save headers before, during and after. nginx retries a failed upstream and temporarily avoids it. Mac 2 remains the active edge single point of failure. Automatic edge redundancy also needs failure detection and a coordinated address or traffic switch.
4. **Standby and TTL.** On Mac 4 run bash lab cert and bash lab edge in its own tab. Distribute edge-4.crt to clients, compare fingerprints, and run bash lab trust edge-4.crt. On Mac 3 run source run/lan and set u=https://app.team1.test:8443. Check /usr/bin/curl --resolve "app.team1.test:8443:$M4" -I "$u/" shows X-Edge: Mac4. Start with both DNS services in primary mode. Flush Mac 3, request "$u/" and record X-Edge: Mac2. Immediately restart BOTH DNS processes with bash lab dns standby. Coordinate teammates to finish inside 30 seconds. Compare dig @"$M1" app.team1.test and dig @"$M4" app.team1.test (new address and TTL) with repeated /usr/bin/curl -sI "$u/" on the primed client (old edge until cached answer expires). Use date before probes. A freshly flushed second client should reach Mac 4 immediately. Show the primed client changes after expiry. Repeat in reverse and flush before TTL expires to show immediate cutover. Restore both records to primary. New DNS affects new connections. Keep both edges up during the transition.
5. **Faculty fault.** Work from a client. Use dig against each configured resolver and dscacheutil to compare answers, nc -vz app.team1.test 8443 for TCP, /usr/bin/curl -v "$u/" for certificate and handshake, then curl -i "$u/api/status" for HTTP status, X-Edge and X-Backend. From the edge check each backend directly and inspect run/error.log. Record the first failing layer, hypothesis, distinguishing test, correction and successful retest.

## Evaluation and cleanup

Follow PDF §8 in order: topology/inventory, LAN pings, private DNS, trusted HTTPS, A/B headers, packet walkthrough, cache/304, backend failure, Phase 2 resilience, faculty fault, individual viva. Save screenshots/terminal transcripts and pcaps under evidence with the Mac number and scenario. For the Phase 2 report, write one paragraph per extension covering change, prediction, observed result, evidence filename, troubleshooting and learning. Include team names, actual IP/service table, role assignments and remaining edge/DNS limitations. A prepared capture or example output cannot substitute for your live results.

Stop foreground services. On both backend Macs restore isolation if active. On each configured client run bash lab unresolve and remove only the lab certificates you installed in Keychain Access (identify by fingerprint). Keep your captures and reports.
