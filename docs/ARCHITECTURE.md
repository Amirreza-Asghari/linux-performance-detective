# Linux Performance Detective — Architecture

## Overview

Linux Performance Detective (LPD) is a modular Bash-based Linux performance troubleshooting tool.

The project separates system observation, diagnosis, remediation, verification, presentation, reporting, and safety controls into distinct modules.

The primary workflow is:

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

The architecture intentionally avoids treating a threshold violation as sufficient justification for an automatic system change.

---

# CLI Entry Point

The main executable is:

```text
lpd.sh
```

It is responsible for:

* resolving the project root;
* loading core libraries;
* loading checks;
* loading diagnostic modules;
* loading remediation modules;
* loading verification modules;
* initializing logging;
* loading configuration;
* validating required module functions;
* enforcing interactive TTY requirements;
* routing CLI commands.

Supported commands are:

```text
./lpd.sh preflight
./lpd.sh scan
./lpd.sh diagnose [cpu|memory|disk|network|fd|all]
./lpd.sh interactive [cpu|memory|disk|network|fd|all]
./lpd.sh version
./lpd.sh help
```

The CLI contract is intentionally kept stable.

---

# Module Layout

## `lib/`

Core framework components.

### `lib/common.sh`

Contains shared application identity and basic terminal helpers.

Examples:

* product name;
* version;
* common status output;
* basic command availability checks.

`LPD_VERSION` has one authoritative definition in this file.

---

### `lib/ui.sh`

TTY-aware presentation layer.

Responsibilities include:

* professional terminal banner;
* status rendering;
* workflow stage rendering;
* subsystem summaries;
* real progress calculation;
* Unicode fallback;
* `NO_COLOR` handling.

The UI does not determine system health.

It renders results produced by the diagnostic logic.

Progress percentages represent completed workflow units, not health scores.

---

### `lib/safety.sh`

Central process-safety module.

Responsibilities include:

* checking whether a PID exists;
* reading `/proc/<pid>/stat`;
* extracting process start time safely;
* validating process identity;
* identifying protected processes;
* validating whether a process is safe to signal.

This module exists partly to defend against PID reuse.

---

### `lib/runtime.sh`

Tracks temporary resources created by LPD itself.

Responsibilities include:

* registering helper processes;
* unregistering helper processes;
* registering temporary files;
* cleanup during normal exit;
* cleanup during signals.

The runtime cleanup system is limited to resources owned by the LPD run.

---

### `lib/config.sh`

Loads and validates configuration.

Configuration is parsed as data and is not executed using:

```text
source config/lpd.conf
```

This is a deliberate security decision.

The parser validates:

* accepted configuration keys;
* numeric values;
* threshold relationships.

Invalid configuration fails closed.

---

### `lib/capabilities.sh`

Provides capability detection.

It distinguishes between:

* required tools;
* optional tools;
* feature availability.

Missing optional functionality should reduce available diagnostics rather than crash the entire product.

---

### `lib/logger.sh`

Provides audit and remediation logging.

Important system decisions can therefore be reviewed after execution.

---

### `lib/evidence.sh`

Collects evidence used by reporting and troubleshooting.

Evidence collection is kept separate from the final human and machine-readable reports.

---

### `lib/report.sh`

Generates:

```text
Markdown
JSON
```

reports.

JSON output includes explicit execution coverage so collected evidence cannot be confused with a workflow that actually executed.

---

### `lib/preflight.sh`

Evaluates product readiness before troubleshooting.

Readiness states are:

```text
READY
DEGRADED
UNSUPPORTED
```

---

### `lib/scan.sh`

Runs the lightweight system scan.

Subsystems:

```text
CPU
Memory
Disk
Network
File Descriptors
```

The scan aggregates subsystem results conservatively.

---

### `lib/diagnose.sh`

Runs deep diagnostic operations.

The `all` mode aggregates results with the precedence:

```text
UNKNOWN > CRITICAL > WARNING > HEALTHY
```

---

### `lib/interactive.sh`

Coordinates the complete interactive workflow:

```text
Check
Diagnosis
Remediation
Verification
Reporting
```

Interactive mode requires a real terminal before it can be entered through the CLI.

---

# Checks

The `checks/` directory provides lightweight detection.

```text
checks/cpu.sh
checks/memory.sh
checks/disk.sh
checks/network.sh
checks/file-descriptors.sh
```

A check determines whether further investigation is required.

Checks should avoid performing remediation.

---

# Diagnostics

The `diagnostics/` directory performs deeper investigation.

```text
diagnostics/cpu.sh
diagnostics/memory.sh
diagnostics/disk.sh
diagnostics/network.sh
diagnostics/file-descriptors.sh
```

Diagnostics may use advanced tooling when available.

Examples include:

```text
perf
bpftrace
pidstat
tcpconnect-bpfcc
biolatency-bpfcc
```

Optional diagnostic tooling must not be treated as universally available.

---

# Remediation

The `fixes/` directory contains remediation logic.

```text
fixes/cpu.sh
fixes/memory.sh
fixes/disk.sh
fixes/network.sh
fixes/file-descriptors.sh
```

Remediation is deliberately separate from detection and diagnosis.

The system does not assume that every detected performance problem has a safe generic fix.

An unresolved condition can remain unresolved instead of triggering an unsafe automatic action.

---

# Verification

The `verify/` directory contains post-remediation verification.

```text
verify/cpu.sh
verify/memory.sh
verify/disk.sh
verify/network.sh
verify/file-descriptors.sh
```

Successful command execution alone is not considered proof that a performance incident was resolved.

The verification stage evaluates the state after remediation.

---

# Result Model

At the high-level CLI boundary:

```text
0 = healthy / success / resolved
1 = warning / attention required / degraded
2 = critical / failed
3 = unknown / unsupported / tool failure
```

Interactive remediation can internally return:

```text
10 = no remediation performed
```

The interactive engine normalizes this to a high-level result.

---

# Conservative Aggregation

LPD intentionally favors uncertainty over false confidence.

For deep diagnosis:

```text
UNKNOWN
   >
CRITICAL
   >
WARNING
   >
HEALTHY
```

For interactive workflow results:

```text
UNKNOWN
   >
FAILED
   >
ATTENTION
   >
HEALTHY
```

Therefore a failed or unknown subsystem cannot be hidden by healthy results from other subsystems.

---

# Reporting Architecture

Reports distinguish between:

```text
workflow execution
```

and:

```text
supplemental evidence collection
```

For example, an interactive CPU investigation may still collect memory, disk, network, or FD evidence for context.

This does not mean those subsystem workflows were executed.

The JSON schema therefore contains explicit fields such as:

```json
{
  "coverage": {
    "scope": "cpu",
    "full_system": false
  },
  "subsystems": {
    "cpu": {
      "executed": true
    },
    "memory": {
      "executed": false
    }
  }
}
```

Unavailable machine-readable values use JSON `null`.

---

# Presentation Separation

The UI is intentionally separated from diagnostic decisions.

The architecture follows:

```text
Checks / Diagnostics / Verify
            ↓
       real results
            ↓
          UI
```

Not:

```text
UI
 ↓
invent health/result
```

TTY decoration is disabled when output is redirected or piped.

This keeps automation output clean.

---

# Packaging

`scripts/build-release.sh` creates an isolated release tree.

The release builder:

* copies required source files;
* excludes development runtime data;
* creates empty runtime directories;
* removes common development artifacts;
* builds a deterministic archive;
* creates a SHA256 checksum;
* validates archive paths;
* extracts the package again;
* performs smoke tests.

Generated packages are stored under:

```text
dist/
```

---

# Design Principle

The architectural rule behind LPD is:

```text
Measurement creates evidence.
Evidence supports diagnosis.
Diagnosis may justify remediation.
Remediation requires safety.
Safety requires verification.
Verification determines the final result.
```

The presentation layer never substitutes for that chain.
