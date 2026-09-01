# Linux Performance Detective

**Linux Performance Detective (LPD)** is a Bash-based Linux troubleshooting tool designed to help investigate common performance incidents using a structured workflow:

**Detect → Diagnose → Explain Evidence → Remediate → Verify → Report**

Current release candidate:

```text
0.2.0-rc1
```

LPD focuses on five common Linux performance areas:

* CPU pressure
* Memory pressure
* Disk I/O pressure
* Network connection anomalies
* File descriptor exhaustion

The project is designed as both a practical Linux SysAdmin troubleshooting tool and a demonstration of safe, evidence-based performance investigation.

---

## Why LPD Exists

High CPU usage, memory pressure, disk latency, connection bursts, and file descriptor exhaustion are common Linux incidents.

The difficult part is usually not detecting that a metric crossed a threshold.

The difficult part is answering:

* What exactly is happening?
* Which process is responsible?
* Is the observation reliable?
* Is remediation safe?
* Did the remediation actually improve the situation?
* What evidence should be preserved for later analysis?

LPD attempts to make that workflow repeatable.

It does **not** blindly apply fixes when a threshold is exceeded.

---

# Core Workflow

LPD follows this model:

```text
Detect
  ↓
Diagnose
  ↓
Explain Evidence
  ↓
Ask User
  ↓
Remediate
  ↓
Verify
  ↓
Report
```

A detected problem does not automatically trigger remediation.

The diagnostic stage first attempts to identify supporting evidence and, where possible, the responsible process.

Interactive remediation requires explicit user interaction and is followed by verification.

---

# Features

## CPU

LPD can investigate:

* overall CPU pressure
* high-CPU processes
* CPU saturation
* process CPU contribution
* available CPU capacity

Depending on available tools, deeper investigation may use:

* `ps`
* `/proc`
* `perf`
* `bpftrace`

---

## Memory

LPD examines information such as:

* available memory
* memory utilization
* swap activity
* memory pressure
* PSI memory signals
* high-memory processes

Optional telemetry such as `vmstat` is used when available.

Missing optional telemetry does not automatically make the entire result invalid.

---

## Disk I/O

LPD can investigate:

* filesystem utilization
* device utilization
* I/O queue pressure
* latency-related indicators
* processes generating I/O

Depending on system capabilities, it can use:

* `df`
* `findmnt`
* `iostat`
* `pidstat`
* `biolatency-bpfcc`

---

## Network

LPD examines connection-related behavior such as:

* TCP connection states
* `TIME_WAIT`
* connection bursts
* active connection counts
* process connection activity

Optional deeper tracing can use:

```text
tcpconnect-bpfcc
```

Network diagnosis may take longer than other subsystems because connection activity is often bursty and cannot always be understood from a single snapshot.

---

## File Descriptors

LPD can investigate:

* system file descriptor pressure
* per-process file descriptor usage
* process soft limits
* FD utilization ratios
* suspected FD exhaustion

Process identity is revalidated before potentially sensitive operations.

---

# Safety Model

LPD is intentionally conservative.

Its design follows several safety rules.

## No Blind Remediation

Crossing a threshold does not automatically mean that changing the system is safe.

LPD separates:

```text
Detection
Diagnosis
Remediation
Verification
```

---

## Process Identity Validation

Linux PIDs can be reused.

Using only a PID before signaling a process can therefore target the wrong process if the original process exits and the PID is reused.

LPD protects against this by validating process identity using:

```text
PID
process command
/proc/<pid>/stat starttime
```

The `/proc/<pid>/stat` parser also avoids the unsafe assumption that field 22 can always be read using a naive:

```text
awk '{print $22}'
```

because process names may contain spaces or parentheses.

---

## Protected Processes

LPD contains protections against targeting important system processes and common system daemons.

Potential remediation is rejected when the process is classified as protected.

---

## Revalidation Before Signaling

A process may disappear or change between diagnosis and remediation.

LPD therefore revalidates the process immediately before signaling operations.

A stale PID is rejected.

---

## No Fake Healthy State

When required telemetry fails, LPD does not convert missing information into a successful result.

The tool uses explicit states such as:

```text
UNKNOWN
NOT_RUN
N/A
```

depending on context.

For machine-readable JSON, unavailable values use native JSON:

```json
null
```

rather than the human-readable string `"N/A"`.

---

# Readiness Model

Before troubleshooting, LPD can evaluate whether the system has the required capabilities.

Run:

```bash
./lpd.sh preflight
```

Preflight produces one of three readiness states.

### READY

```text
Exit code 0
```

Required capabilities are available.

### DEGRADED

```text
Exit code 1
```

The core product can run, but one or more optional capabilities are unavailable.

Examples may include missing advanced diagnostic tools.

### UNSUPPORTED

```text
Exit code 3
```

A required capability is unavailable and reliable operation cannot be guaranteed.

---

# Supported Environment

LPD is developed and tested primarily on Linux systems similar to:

* Debian
* Ubuntu
* RHEL-family distributions

The current development environment uses:

```text
Debian GNU/Linux 13 (trixie)
Linux kernel 6.12
Bash 5.2
```

LPD uses feature detection and fallbacks where practical.

It should **not** be interpreted as claiming universal compatibility with every Linux distribution or kernel configuration.

---

# Requirements

Core operation relies on common Linux utilities such as:

```text
bash
awk
grep
sed
ps
df
findmnt
```

Some functionality can benefit from:

```text
ss
vmstat
iostat
pidstat
strace
perf
bpftrace
bpftool
tcpconnect-bpfcc
biolatency-bpfcc
```

Advanced tools are not all mandatory.

Run:

```bash
./lpd.sh preflight
```

to see what functionality is available on the current system.

---

# Installation

## From Source

Clone or extract the project and enter its directory:

```bash
cd linux-performance-detective
```

Make the main executable runnable if necessary:

```bash
chmod +x lpd.sh
```

Check the installed version:

```bash
./lpd.sh version
```

---

## From Release Archive

Example for release candidate `0.2.0-rc1`:

```bash
tar -xzf linux-performance-detective-0.2.0-rc1.tar.gz
cd linux-performance-detective-0.2.0-rc1
```

Verify:

```bash
./lpd.sh version
```

---

# Checksum Verification

Release archives include a SHA256 checksum file.

Verify the archive before extraction:

```bash
sha256sum -c \
  linux-performance-detective-0.2.0-rc1.tar.gz.sha256
```

A valid package should report:

```text
linux-performance-detective-0.2.0-rc1.tar.gz: OK
```

---

# CLI

The command-line interface is:

```text
./lpd.sh preflight

./lpd.sh scan

./lpd.sh diagnose [cpu|memory|disk|network|fd|all]

./lpd.sh interactive [cpu|memory|disk|network|fd|all]

./lpd.sh version

./lpd.sh help
```

---

# Quick Scan

Run:

```bash
./lpd.sh scan
```

The scan checks:

```text
CPU
Memory
Disk
Network
File Descriptors
```

Possible subsystem outcomes are represented through the tool's exit-code and status model.

---

# Deep Diagnosis

Diagnose a specific subsystem:

```bash
./lpd.sh diagnose cpu
```

Other targets:

```bash
./lpd.sh diagnose memory
./lpd.sh diagnose disk
./lpd.sh diagnose network
./lpd.sh diagnose fd
```

Diagnose all supported subsystems:

```bash
./lpd.sh diagnose all
```

Diagnosis mode is non-interactive.

It does not ask for remediation approval.

---

# Interactive Mode

Interactive workflows use:

```bash
./lpd.sh interactive cpu
```

or:

```bash
./lpd.sh interactive all
```

Interactive mode follows the investigation through remediation and verification when appropriate.

It requires a real terminal.

For safety, a command such as:

```bash
./lpd.sh interactive cpu </dev/null
```

is rejected instead of silently attempting interactive remediation in an automation environment.

Use `scan` or `diagnose` for scripts and CI workflows.

---

# Terminal UI

When LPD runs in a real terminal, it can display:

* status indicators
* colors
* structured sections
* subsystem summaries
* progress information

Progress percentages represent **real completed workflow units**.

For example:

```text
1 / 5 = 20%
2 / 5 = 40%
3 / 5 = 60%
4 / 5 = 80%
5 / 5 = 100%
```

This is workflow progress.

It is **not** a fabricated system health score.

LPD does not generate fake confidence percentages or arbitrary health scores.

---

# Non-Interactive Behavior

When output is redirected or piped, terminal decoration is disabled.

Example:

```bash
./lpd.sh scan > scan.txt
```

Non-interactive output does not contain:

* ANSI color escape sequences
* progress bars
* decorative terminal boxes
* interactive prompts

This makes the output safer for:

* shell automation
* CI pipelines
* log collection
* downstream processing

---

# NO_COLOR

ANSI colors can be disabled using the common `NO_COLOR` convention:

```bash
NO_COLOR=1 ./lpd.sh scan
```

Information remains available while terminal color sequences are suppressed.

---

# Exit Codes

LPD uses the following high-level exit-code contract:

| Exit Code | Meaning                                 |
| --------- | --------------------------------------- |
| `0`       | Healthy / successful / resolved         |
| `1`       | Warning / attention required / degraded |
| `2`       | Critical / failed                       |
| `3`       | Unknown / unsupported / tool failure    |

Internal remediation logic can additionally use:

```text
10 = no remediation performed
```

This internal value is normalized by the interactive workflow and is not intended to represent a successful resolution.

---

# Result Precedence

When multiple subsystems are evaluated, LPD uses conservative aggregation.

For diagnosis:

```text
UNKNOWN > CRITICAL > WARNING > HEALTHY
```

For interactive workflow results:

```text
UNKNOWN > FAILED > ATTENTION > HEALTHY
```

A failed or unknown subsystem must not result in a false overall healthy classification.

---

# Reports

Interactive workflows generate reports under:

```text
reports/
```

Reports are generated in both:

```text
Markdown
JSON
```

The Markdown report is intended for humans.

The JSON report is intended for automation and downstream tooling.

---

# JSON Reporting

The machine-readable report contains explicit metadata including:

```json
{
  "schema_version": 1,
  "run": {
    "mode": "interactive",
    "target": "cpu",
    "exit_code": 0
  },
  "coverage": {
    "scope": "cpu",
    "full_system": false
  }
}
```

This is an example of the schema structure, not a guaranteed runtime result.

---

## Coverage Semantics

LPD distinguishes between:

```text
evidence collected
```

and:

```text
workflow executed
```

For example, an `interactive cpu` run may collect supplemental system evidence while only executing the CPU workflow.

The report therefore exposes fields such as:

```json
"executed": true
```

for subsystems that actually ran.

Subsystems that were not executed use:

```json
{
  "executed": false,
  "status": "NOT_RUN",
  "exit_code": null
}
```

This prevents a CPU-only investigation from being incorrectly interpreted as a full-system health assessment.

---

# Logs and Audit Trail

Runtime logs are written under:

```text
logs/
```

LPD records important decisions and failures including:

* diagnosis outcomes
* invalid module return codes
* missing functions
* remediation decisions
* safety rejections
* report generation failures

The goal is to keep troubleshooting decisions auditable.

---

# Evidence

Collected evidence is stored under:

```text
evidence/
```

Evidence collection is separated from the final report so that raw diagnostic material can be retained independently.

---

# Remediation Philosophy

LPD is not designed as an automatic "fix everything" script.

A remediation should only occur when:

1. the condition has been detected;
2. supporting evidence exists;
3. the target can be identified safely;
4. the proposed action is considered acceptable;
5. the user approves the operation when interaction is required;
6. the result can be verified.

If a safe generic remediation does not exist, LPD can leave the condition unresolved and report that state rather than forcing a risky action.

---

# Verification

A remediation is not treated as successful merely because the command itself executed.

LPD performs verification where supported.

Possible conceptual outcomes include:

```text
RESOLVED
MITIGATED
FAILED
UNKNOWN
```

The final workflow return code reflects whether the condition was actually resolved or still requires attention.

---

# Rollback

Where a temporary reversible action is supported, LPD records enough state to restore the previous configuration when appropriate.

For example, disk remediation involving `ionice` preserves the previous scheduling state before changing it.

Rollback behavior is covered by automated tests.

---

# Testing

LPD includes multiple test suites.

## Safe Regression Suite

```bash
./tests/run-safe-tests.sh
```

This covers areas including:

* Bash syntax
* configuration command-injection protection
* threshold relationship validation
* protected process policy
* stale PID rejection
* invalid diagnosis result handling
* invalid remediation result handling
* invalid verification result handling
* no-action remediation semantics
* rollback restoration
* required telemetry failure
* optional telemetry fallback
* CPU evidence arithmetic
* Markdown and JSON reporting

---

## UI Regression Suite

```bash
./tests/run-ui-tests.sh
```

This verifies:

* TTY-aware UI behavior
* non-TTY output
* absence of ANSI in redirected output
* interactive TTY protection
* `NO_COLOR`
* terminal progress rendering

---

## Incident Tests

```bash
./tests/run-incident-tests.sh
```

The incident suite creates bounded test workloads for performance scenarios including:

* CPU saturation
* memory pressure
* disk I/O pressure
* network connection activity
* file descriptor exhaustion

---

## Fault Injection Suite

```bash
./tests/run-fault-injection-tests.sh
```

Fault injection verifies fail-safe behavior such as:

```text
malicious configuration   → rejected
required telemetry loss   → UNKNOWN
required dependency loss  → UNSUPPORTED
optional dependency loss  → DEGRADED
optional telemetry loss   → fallback / N/A
report generation failure → UNKNOWN
missing module function   → fail closed
invalid module return     → UNKNOWN
stale PID                 → signaling rejected
```

---

## Final Regression / Release Gate

Before release:

```bash
./tests/run-final-regression.sh
```

The release gate checks the overall CLI and test contract, including:

* Bash syntax
* ShellCheck
* version command
* help output
* frozen CLI commands
* invalid-command behavior
* preflight
* scan
* individual diagnosis targets
* full diagnosis
* interactive non-TTY safety
* namespace regression
* safe regression tests
* UI regression tests
* incident tests

A release candidate should not be accepted if the release gate fails.

---

# ShellCheck

Production Bash code is checked using ShellCheck.

The project intentionally suppresses a small number of known cross-file/source-analysis false positives when running repository-wide checks.

The goal is not simply to silence ShellCheck.

Actionable warnings are treated separately from known static-analysis limitations caused by modular Bash sourcing.

---

# Project Structure

```text
linux-performance-detective/
├── lpd.sh
├── lib/
│   ├── common.sh
│   ├── ui.sh
│   ├── safety.sh
│   ├── runtime.sh
│   ├── config.sh
│   ├── capabilities.sh
│   ├── logger.sh
│   ├── evidence.sh
│   ├── report.sh
│   ├── preflight.sh
│   ├── scan.sh
│   ├── diagnose.sh
│   └── interactive.sh
├── checks/
│   ├── cpu.sh
│   ├── memory.sh
│   ├── disk.sh
│   ├── network.sh
│   └── file-descriptors.sh
├── diagnostics/
│   ├── cpu.sh
│   ├── memory.sh
│   ├── disk.sh
│   ├── network.sh
│   └── file-descriptors.sh
├── fixes/
│   ├── cpu.sh
│   ├── memory.sh
│   ├── disk.sh
│   ├── network.sh
│   └── file-descriptors.sh
├── verify/
│   ├── cpu.sh
│   ├── memory.sh
│   ├── disk.sh
│   ├── network.sh
│   └── file-descriptors.sh
├── config/
│   └── lpd.conf
├── tests/
├── scripts/
├── incidents/
├── baseline/
├── evidence/
├── reports/
├── logs/
└── dist/
```

Runtime directories such as `logs/`, `reports/`, and `evidence/` are not populated with development-system data inside release archives.

---

# Configuration

Thresholds are stored in:

```text
config/lpd.conf
```

The configuration file is parsed as data.

It is intentionally **not sourced as Bash code**.

This protects against configuration values being interpreted as shell commands.

Threshold relationships are validated before operation.

Invalid configuration causes the tool to fail closed.

---

# Packaging

A release archive can be built using:

```bash
./scripts/build-release.sh
```

The builder:

* creates an isolated staging tree
* excludes development runtime data
* preserves required project files
* creates empty runtime directories
* validates the staged package
* creates a deterministic `.tar.gz`
* generates a SHA256 checksum
* verifies archive safety
* extracts the result into a temporary directory
* executes version/help smoke tests

Generated packages are stored under:

```text
dist/
```

---

# Current Release Status

Current version:

```text
0.2.0-rc1
```

This is a **release candidate**, not the final stable `0.2.0` release.

The core diagnostic workflow is feature-complete for the current project scope.

Remaining release work primarily concerns:

* documentation
* repository cleanup
* final Git/GitHub preparation
* demonstration material
* portfolio presentation

---

# What LPD Is Not

LPD is not:

* a replacement for full observability platforms
* a universal Linux monitoring agent
* an automatic production remediation system
* a benchmark
* a synthetic health-score generator
* a reason to signal arbitrary processes
* a substitute for understanding the workload being investigated

It is a structured Linux troubleshooting assistant built around evidence, safety, verification, and reproducibility.

---

# Development Principles

The project follows several principles:

```text
Measure before changing.
Diagnose before remediating.
Never invent missing telemetry.
Fail closed when safety cannot be established.
Revalidate process identity before signaling.
Treat UNKNOWN as different from HEALTHY.
Verify remediation outcomes.
Keep machine-readable output machine-readable.
Keep terminal presentation separate from diagnostic logic.
```

---

# License

A license has not yet been finalized for the release candidate.

Before publishing the stable release, an explicit repository license should be selected and added as:

```text
LICENSE
```

---

# Status

**Linux Performance Detective — v0.2.0-rc1**

Release candidate under final documentation and repository preparation.
