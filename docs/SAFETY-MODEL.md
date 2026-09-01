# Linux Performance Detective — Safety Model

## Purpose

Linux performance troubleshooting sometimes requires interacting with live processes.

That creates risk.

A PID may disappear, be reused, represent a protected system process, or no longer match the process that was originally diagnosed.

Linux Performance Detective therefore treats process remediation as a safety-sensitive operation.

---

# Core Rule

LPD does not assume:

```text
Detected problem = safe remediation
```

The intended chain is:

```text
Detect
  ↓
Diagnose
  ↓
Validate target
  ↓
Ask user where required
  ↓
Revalidate target
  ↓
Remediate
  ↓
Verify
```

If safety cannot be established, remediation should not proceed.

---

# PID Reuse

Linux process IDs are reusable.

Consider:

```text
Diagnosis:
PID 1234 = workload-A

Later:
workload-A exits

PID 1234 is reused by workload-B
```

A remediation system that stores only:

```text
PID=1234
```

could signal the wrong process.

LPD therefore does not treat PID alone as sufficient process identity.

---

# Process Identity

LPD can validate a process using:

```text
PID
command
/proc/<pid>/stat starttime
```

The process start time provides an additional identity property.

If the current process does not match the captured identity, the target is considered stale.

---

# Safe `/proc/<pid>/stat` Parsing

A naive parser such as:

```text
awk '{print $22}' /proc/<pid>/stat
```

is unsafe.

The `comm` field inside `/proc/<pid>/stat` is enclosed in parentheses and can contain characters or spaces that make simplistic whitespace-field assumptions unreliable.

LPD centralizes this parsing in:

```text
lib/safety.sh
```

Other modules should use the shared safety helper instead of implementing their own field-22 parsing.

---

# Target Revalidation

A valid target during diagnosis may no longer be valid during remediation.

LPD therefore revalidates process identity immediately before safety-sensitive signaling.

The basic rule is:

```text
diagnosis identity
      ↓
time passes
      ↓
revalidate
      ↓
signal only if still valid
```

---

# Protected Processes

Some processes should not be targeted by generic performance remediation.

LPD maintains protection logic for important system processes and common daemons.

Examples include system-level processes such as:

```text
init
systemd
kthreadd
kworker
```

and other processes classified by the safety policy.

Protected targets are rejected rather than automatically signaled.

---

# Stale PID Policy

When a stored PID identity no longer matches:

```text
LPD must reject the target.
```

It must not assume that a PID still represents the previously diagnosed process.

Automated tests specifically cover stale PID rejection.

---

# Fail-Closed Behavior

LPD prefers:

```text
UNKNOWN
```

over an unjustified:

```text
HEALTHY
```

or unsafe remediation.

Examples:

```text
required telemetry failure
    → UNKNOWN

invalid module return code
    → UNKNOWN

missing required function
    → fail closed

reporting failure
    → UNKNOWN

stale process identity
    → reject signaling
```

---

# Optional vs Required Telemetry

Not every missing tool has the same severity.

For example:

```text
required capability missing
    → operation may be unsupported

optional capability missing
    → reduced diagnostic depth
```

An optional tool failure should not automatically invalidate unrelated reliable observations.

Where appropriate, missing human-readable telemetry is displayed as:

```text
N/A
```

Machine-readable JSON uses:

```json
null
```

for unavailable values.

---

# Configuration Security

The configuration file:

```text
config/lpd.conf
```

is parsed as data.

It is not directly sourced into Bash.

This prevents a configuration entry such as:

```text
EVIL=$(some-command)
```

from being executed merely because it appears in the configuration file.

The parser also validates accepted keys and threshold relationships.

---

# No Blind Cache Dropping

LPD does not treat operations such as:

```text
drop_caches
```

as generic performance fixes.

Blind cache dropping can reduce performance and hide the actual cause of an incident.

---

# No Arbitrary Sysctl Changes

The project does not apply random kernel tuning changes simply because a system appears slow.

A generic performance tool cannot reliably determine that a particular sysctl modification is correct for every workload.

---

# No Arbitrary File Deletion

Disk pressure does not justify deleting arbitrary files.

LPD can diagnose disk pressure without assuming which data is safe to remove.

---

# No Blind Limit Increase

File descriptor pressure does not automatically justify raising process or system limits.

A high FD count can indicate:

* legitimate load;
* poor sizing;
* resource leakage;
* application defects.

Increasing a limit without diagnosis can merely delay failure.

---

# Remediation Result `10`

Interactive remediation uses an internal result:

```text
10 = no remediation performed
```

This is deliberate.

Skipping remediation must not be confused with successful resolution.

The interactive engine records the no-action decision and returns a state requiring attention when the diagnosed condition remains unresolved.

---

# Verification Requirement

A remediation command returning zero does not prove the incident has been fixed.

For example:

```text
command executed successfully
```

does not necessarily mean:

```text
system condition resolved
```

LPD therefore separates remediation from verification.

---

# Reversible Operations

Where supported, a remediation should capture the previous state before modification.

Disk I/O remediation using `ionice` is an example.

LPD can capture the original scheduling state and restore it when rollback is required.

Rollback behavior is covered by regression testing.

---

# Runtime Cleanup

LPD tracks helper processes and temporary files that it creates.

Cleanup is limited to LPD-owned runtime resources.

The project should never perform broad cleanup against unrelated system processes or files.

---

# Interactive Safety Boundary

The CLI rejects interactive mode when stdin or stdout is not attached to a terminal.

This prevents accidental use of interactive remediation inside environments such as:

```text
cron
CI
pipes
redirected scripts
```

Automation should use:

```text
scan
diagnose
```

instead.

---

# Audit Trail

Important safety events are logged.

Examples include:

```text
invalid return code
missing function
stale process
no remediation
report generation failure
```

This allows later review of why LPD accepted or rejected an operation.

---

# Safety Principle

LPD follows this rule:

```text
If the target cannot be trusted,
do not act on it.

If the evidence cannot be trusted,
do not claim health.

If remediation cannot be verified,
do not claim resolution.
```
