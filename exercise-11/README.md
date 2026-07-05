# Exercise 11: CrashLoopBackOff Investigation

This document details the analysis of the `CrashLoopBackOff` error in `payment-service` due to a database connection refusal.

## Incident Investigation

The logs show:
```text
panic: dial tcp 10.20.0.15:5432: connection refused
```

We must classify the issue based on the network layer behavior:

### 1. DNS Issue? (Ruled Out)
**No**. The application is attempting to connect directly to an IP address (`10.20.0.15`). 
- If there were a DNS resolution issue (e.g. failing to resolve `database.production.svc.cluster.local`), the error message would indicate a name resolution failure, such as:
  `dial tcp: lookup database.production.svc.cluster.local: no such host`
- Since it resolved or bypassed DNS and targeted a specific IP address directly, DNS is working correctly (or the IP was hardcoded).

### 2. Secret Issue? (Ruled Out)
**No**. A credentials/secrets issue (e.g. wrong DB password or username) occurs *after* a successful TCP handshake.
- If it were a secret issue, the error would represent an authentication failure at the application layer, such as:
  `pq: password authentication failed for user "postgres"` or `HTTP 401 Unauthorized`
- Since the connection was rejected at the transport layer (TCP), the SDK/client never reached the phase where it could send database credentials.

### 3. Database Issue? (Root Cause)
**Yes**. The error `connection refused` (TCP RST) indicates that the destination host (`10.20.0.15`) is reachable, but nothing is listening on port `5432`, or the host is actively rejecting the connection.

There are three common root causes on the database side:

#### Cause A: Database Service is Offline
The database process (e.g., PostgreSQL) running on `10.20.0.15` has crashed, is restarting, or has failed to start.
* **To fix**: Check the status of the database database service:
  ```bash
  systemctl status postgresql # If on VM
  kubectl get pods -n db -o wide # If in Kubernetes (find pod with IP 10.20.0.15)
  ```

#### Cause B: Database is not listening on the network interface
By default, databases are often configured to only listen on the loopback interface (`localhost` / `127.0.0.1`). If the database has not been configured to listen on the external network interface (`10.20.0.15` or `0.0.0.0`), it will reject external connections.
* **To fix**: In `postgresql.conf`, ensure the listen address is set to allow external connections:
  ```ini
  listen_addresses = '*'
  ```
  And check `pg_hba.conf` to allow the subnet CIDR of the EKS pods.

#### Cause C: Network / Firewall Policy (iptables)
A local firewall (like `ufw` or `iptables`) on the database host is configured to reject incoming traffic on port `5432` from the EKS pod CIDR.
* **To fix**: Update the host firewall rules to allow TCP ingress on port 5432.
