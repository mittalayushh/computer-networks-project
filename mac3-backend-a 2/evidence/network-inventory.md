# Team 1 private LAN
| Machine | IPv4 | Services |
|---|---|---|
| Mac 1 | 10.7.15.3 | Primary DNS, UDP/TCP 53 |
| Mac 2 | 10.7.19.44 | Primary HTTPS edge, TCP 8443 |
| Mac 3 | 10.7.8.159 | Backend A, TCP 3001; test client |
| Mac 4 | 10.7.10.8 | Backend B, TCP 3002; backup DNS, UDP/TCP 53; standby HTTPS, TCP 8443; test client |
Flow: client queries Mac 1 or Mac 4, then connects via TLS to the returned edge.
The edge forwards HTTP to A or B. During isolation only Mac 2 may access the backend ports over the LAN.
Use inventory.txt from each Mac for the observed interface, gateway, netmask, MAC address and ping results.
