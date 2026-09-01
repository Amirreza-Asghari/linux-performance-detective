# Incident 04 - TCP Connection Churn and TIME-WAIT Investigation

## Scenario

A controlled TCP connection workload was generated to observe how Linux handles short-lived connections and how they appear in TCP socket states.

The test was performed locally on:

`127.0.0.1:8080`

A temporary HTTP server was used as the target service.

## Baseline

Before the test:

* TCP established connections: 0
* TIME-WAIT connections: 0
* Primary interface: `ens33`
* System IP address: `192.0.2.10/24`
* Default gateway: `192.0.2.1`

## Test Service

A local HTTP server was started using:

`python3 -m http.server 8080 --bind 127.0.0.1`

The listening socket was verified using:

`ss -lntp | grep 8080`

The service was listening on:

`127.0.0.1:8080`

## Investigation

### 1. TCP Connection State

A TCP connection was created using netcat.

The connection was inspected using:

`ss -tnp | grep 8080`

The connection appeared in the:

`ESTAB`

state.

After closing the connection, the socket appeared in:

`TIME-WAIT`

This demonstrated the normal TCP connection lifecycle.

## Connection Churn Test

One hundred short-lived HTTP connections were generated.

Before the test:

`TIME-WAIT = 0`

After the test:

`TIME-WAIT = 100`

The `ss -s` command reported:

* approximately 100 closed connections
* approximately 100 TIME-WAIT sockets

This confirmed that repeated short-lived TCP connections can rapidly increase the number of sockets in TIME-WAIT.

## eBPF Investigation

TCP connection creation was traced using:

`tcpconnect-bpfcc`

Ten test connections were generated using `curl`.

eBPF captured each connection individually.

Example information captured:

* Process: `curl`
* IP version: IPv4
* Source address: `127.0.0.1`
* Destination address: `127.0.0.1`
* Destination port: `8080`

This showed that eBPF could identify the exact processes generating TCP connections in real time.

## Recovery

After waiting for the TCP TIME-WAIT timeout to expire, the number of TIME-WAIT sockets returned to:

`0`

No manual recovery action was required.

## Findings

This incident demonstrated that a high number of TIME-WAIT sockets does not automatically indicate a network failure.

Short-lived TCP connections naturally remain in TIME-WAIT for a period after closing.

However, a large and sustained number of TIME-WAIT sockets can indicate heavy connection churn.

Using `ss` showed the current socket states.

Using `tcpconnect-bpfcc` provided deeper visibility by showing which process was creating the connections.

## Root Cause

The increase in TIME-WAIT sockets was caused by repeatedly creating and closing short-lived TCP connections to the local HTTP server.

## Conclusion

TCP troubleshooting should not rely only on connection counts.

Useful evidence includes:

* TCP state distribution
* Established connections
* TIME-WAIT sockets
* Process responsible for new connections
* Destination addresses and ports

Combining standard Linux networking tools with eBPF provides both state-level and process-level visibility.

## Tools Used

* ss
* ip
* nc
* curl
* python3 http.server
* tcpconnect-bpfcc
* eBPF
* BCC
