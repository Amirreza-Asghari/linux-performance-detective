# Linux Performance Detective

**Linux Performance Detective (LPD)** is a safety-first Linux
performance troubleshooting tool built with Bash.

LPD helps investigate Linux performance incidents through a structured
workflow:

``` text
Detect → Diagnose → Explain Evidence → Remediate → Verify → Report
```

Current release:

``` text
0.2.0
```

## Overview

LPD focuses on common Linux performance problems:

-   CPU saturation
-   Memory pressure
-   Disk I/O issues
-   Network anomalies
-   File descriptor exhaustion

The goal is not only detecting a problem, but understanding:

-   What is happening?
-   Which process or subsystem is involved?
-   Is the evidence reliable?
-   Is remediation safe?
-   Was the issue actually resolved?

------------------------------------------------------------------------

# Demo Workflow

## 1. Validate environment

``` bash
./lpd.sh preflight
```

LPD checks:

-   Linux capabilities
-   Required tools
-   Kernel features
-   eBPF readiness
-   Runtime environment

## 2. Simulate an incident

Example CPU workload:

``` bash
stress-ng --cpu 2 --timeout 300s
```

## 3. Diagnose

``` bash
./lpd.sh diagnose cpu
```

Example:

``` text
Diagnosis:           Multi-process CPU saturation
Culprit confidence:  HIGH
```

## 4. Safety workflow

``` bash
./lpd.sh interactive cpu
```

LPD validates targets before sensitive operations and blocks unsafe
automatic actions.

------------------------------------------------------------------------

# Features

## CPU Diagnostics

-   CPU pressure detection
-   Load analysis
-   Process identification
-   Single-process saturation detection
-   Multi-process saturation detection

## Memory Diagnostics

-   Memory availability analysis
-   Swap monitoring
-   Memory pressure detection

## Disk I/O Diagnostics

-   Filesystem usage checks
-   Inode analysis
-   Device performance analysis
-   I/O pressure detection

## Network Diagnostics

-   TCP state analysis
-   Connection activity analysis
-   Optional eBPF tracing support

## File Descriptor Diagnostics

-   System FD usage
-   Process descriptor analysis
-   Limit validation
-   Exhaustion detection

------------------------------------------------------------------------

# Safety Model

LPD follows:

``` text
Detection
    ↓
Diagnosis
    ↓
Remediation Decision
    ↓
Verification
```

## No Blind Remediation

LPD does not apply changes only because a threshold is exceeded.

Actions require:

-   reliable evidence
-   target validation
-   safety checks
-   verification

## Process Identity Validation

Before sensitive operations LPD validates:

``` text
PID
Process command
/proc/<pid>/stat starttime
```

## Protected Processes

Important system processes are protected from unsafe remediation.

## Revalidation Before Signaling

Targets are checked again before signaling operations.

------------------------------------------------------------------------

# CLI Usage

``` bash
./lpd.sh version
./lpd.sh preflight
./lpd.sh scan
./lpd.sh diagnose cpu
./lpd.sh diagnose all
./lpd.sh interactive cpu
```

------------------------------------------------------------------------

# Reports

LPD generates:

-   Markdown reports
-   JSON reports

------------------------------------------------------------------------

# Testing

``` bash
./tests/run-safe-tests.sh
./tests/run-ui-tests.sh
./tests/run-incident-tests.sh
./tests/run-fault-injection-tests.sh
./tests/run-final-regression.sh
```

Validated areas:

-   CLI contracts
-   Shell syntax
-   Safety behavior
-   Incident detection
-   Fault handling
-   UI behavior

------------------------------------------------------------------------

# Project Structure

``` text
linux-performance-detective/
├── lpd.sh
├── lib/
├── checks/
├── diagnostics/
├── fixes/
├── verify/
├── tests/
├── config/
├── reports/
└── logs/
```

------------------------------------------------------------------------

# Development Principles

``` text
Measure before changing.
Diagnose before remediating.
Never invent missing telemetry.
Fail closed when safety cannot be established.
Verify remediation outcomes.
Keep machine-readable output clean.
```

------------------------------------------------------------------------

# Status

Linux Performance Detective v0.2.0

Public release prepared for portfolio demonstration.
