# CN Phase 1 — Build & Observe

Computer Networks Course — Phase 1

This project implements a small multi-machine network using four physical macOS laptops. The system demonstrates private DNS resolution, HTTPS/TLS, reverse proxying, backend load balancing, HTTP caching, packet inspection using Wireshark, and backend failure/recovery.

## Team Members

| Name | Enrollment |
|---|---|
| Ayush Mittal | 2401020091 |
| Saumya Soni | 2401020058  |
| Anurag Kumar | 2401010088 |

## Architecture

```text
                    Client
                      |
                      |
              app.team1.test
                      |
                      v
              +---------------+
              |     Mac 1     |
              |    dnsmasq    |
              |  Private DNS  |
              +---------------+
                      |
                      | resolves domain to Mac 2
                      v
              +---------------+
              |     Mac 2     |
              |     nginx     |
              | HTTPS :8443   |
              | Load Balancer |
              +---------------+
                 /           \
                /             \
               v               v
       +---------------+ +---------------+
       |     Mac 3     | |     Mac 4     |
       |   Backend A   | |   Backend B   |
       |     :3001     | |     :3002     |
       +---------------+ +---------------+
```

## Machine Responsibilities

| Machine | Responsibility | Service |
|---|---|---|
| Mac 1 | Private DNS server | dnsmasq / UDP 53 |
| Mac 2 | HTTPS edge and load balancer | nginx / TCP 8443 |
| Mac 3 | Backend A | Python HTTP server / TCP 3001 |
| Mac 4 | Backend B | Python HTTP server / TCP 3002 |

The application domain used by the project is:

```text
app.team1.test
```

HTTPS is exposed on:

```text
https://app.team1.test:8443
```

## Repository Structure

```text
CN-Phase1-Team1/
├── Makefile
├── README.md
├── backend/
│   └── backend.py
├── configs/
│   ├── nginx.conf
│   └── dnsmasq.conf
├── certs/
│   └── team1-ca.crt
└── docs/
    └── screenshots/
```

The TLS private key is intentionally excluded from this repository.

## Requirements

The project was developed and tested on macOS.

Required software:

```text
Python 3
nginx
dnsmasq
curl
dig
Wireshark
make
```

Homebrew can be used to install the required networking tools:

```bash
brew install nginx
brew install dnsmasq
```

## Running the Project

The root `Makefile` contains commands for starting and testing the project.

To see all available commands:

```bash
make help
```

### 1. Start Backend A — Mac 3

Clone the repository and enter it:

```bash
git clone <REPOSITORY_URL>
cd CN-Phase1-Team1
```

Start Backend A:

```bash
make backend-a
```

Equivalent command:

```bash
BACKEND=A PORT=3001 python3 backend/backend.py
```

Backend A listens on:

```text
0.0.0.0:3001
```

### 2. Start Backend B — Mac 4

Clone the repository and enter it:

```bash
git clone <REPOSITORY_URL>
cd CN-Phase1-Team1
```

Start Backend B:

```bash
make backend-b
```

Equivalent command:

```bash
BACKEND=B PORT=3002 python3 backend/backend.py
```

Backend B listens on:

```text
0.0.0.0:3002
```

### 3. Start nginx — Mac 2

Before starting nginx, update `configs/nginx.conf` with the current private IP addresses of Mac 3 and Mac 4 and the correct local certificate/key paths.

Validate the configuration:

```bash
make nginx-test
```

Start nginx:

```bash
make nginx-start
```

If nginx is already running and the configuration has changed:

```bash
make nginx-reload
```

Check whether nginx is listening on TCP port 8443:

```bash
make nginx-status
```

### 4. Start Private DNS — Mac 1

Update `configs/dnsmasq.conf` so that `app.team1.test` resolves to Mac 2's private IP address.

Start the DNS server:

```bash
make dns-start
```

Check DNS status:

```bash
make dns-status
```

Client machines must use Mac 1's private IP address as their DNS server.

## Testing

### Private DNS

```bash
make test-dns
```

The expected result is:

```text
app.team1.test -> Mac 2 private IP
```

The DNS server shown by `dig` should be Mac 1.

### HTTPS

```bash
make test-https
```

The request is intentionally performed without `curl -k`. Therefore the TLS certificate must be trusted by the client.

Expected result:

```text
HTTP/1.1 200 OK
```

### Load Balancing

```bash
make test-balance
```

Example:

```text
Request 1: X-Backend: A
Request 2: X-Backend: B
Request 3: X-Backend: A
Request 4: X-Backend: B
Request 5: X-Backend: A
Request 6: X-Backend: B
```

The exact sequence is not important. Successful load balancing is demonstrated when responses are served by both Backend A and Backend B.

### HTTP Caching

```bash
make test-cache
```

The `/cache-demo` endpoint returns headers including:

```text
Cache-Control: max-age=60
ETag: "team1-cache-v1"
```

`max-age=60` tells the client that the response may be considered fresh for 60 seconds.

### ETag Revalidation

```bash
make test-etag
```

The request sends:

```text
If-None-Match: "team1-cache-v1"
```

If the resource has not changed, the backend returns:

```text
HTTP/1.1 304 Not Modified
```

This allows the client to reuse its cached representation without downloading the response body again.

## Backend Failure Demonstration

Under normal operation:

```bash
make test-balance
```

returns responses from both backends.

To simulate a backend failure, Backend A is stopped on Mac 3 using `Ctrl+C`.

Running:

```bash
make test-balance
```

again shows that nginx continues serving requests using Backend B.

Backend A is restored with:

```bash
make backend-a
```

After recovery, nginx resumes distributing requests across both Backend A and Backend B.

This demonstrates that the failure of one application backend does not necessarily cause failure of the complete service.

## Packet Analysis

Wireshark was used to observe the network at multiple protocol layers.

The captured traffic demonstrates:

```text
DNS resolution
      ↓
TCP three-way handshake
      ↓
TLS handshake
      ↓
Encrypted HTTPS application data
```

DNS traffic is inspected using:

```text
dns
```

TCP traffic is inspected using:

```text
tcp.port == 8443
```

TLS traffic is inspected using:

```text
tls
```

## Security

The public certificate may be included in this repository:

```text
certs/team1-ca.crt
```

The corresponding private key is **not committed to GitHub**.

The repository `.gitignore` includes:

```gitignore
*.key
**/*.key
.DS_Store
```

Private keys must never be committed to a public repository.

## Useful Commands

```bash
make help

make backend-a
make backend-b

make nginx-test
make nginx-start
make nginx-reload
make nginx-stop
make nginx-status

make dns-start
make dns-stop
make dns-status

make test-dns
make test-public-dns
make test-https
make test-balance
make test-cache
make test-etag

make demo
```

## Technologies Used

- macOS
- Python 3
- nginx
- dnsmasq
- HTTPS / TLS 1.2
- HTTP/1.1
- DNS
- TCP
- Wireshark
- curl
- Git / GitHub

## Course Phase

This repository contains the implementation and evidence for **Computer Networks Phase 1 — Build & Observe**.
