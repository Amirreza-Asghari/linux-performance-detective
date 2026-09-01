# Linux Performance Detective — Testing and Release Gates

## Overview

Linux Performance Detective uses multiple layers of testing.

The goal is not only to prove that commands run.

The tests attempt to verify:

* syntax;
* safety behavior;
* error normalization;
* missing-tool fallbacks;
* report semantics;
* UI separation;
* bounded incident detection;
* fault handling;
* packaging.

---

# Exit-Code Contract

At the high-level CLI boundary:

| Code | Meaning                                             |
| ---: | --------------------------------------------------- |
|  `0` | Healthy, successful, or resolved                    |
|  `1` | Warning, degraded, mitigated, or attention required |
|  `2` | Critical or failed                                  |
|  `3` | Unknown, unsupported, or tool failure               |

Interactive remediation may internally use:

```text
10
```

to indicate:

```text
No remediation was performed.
```

The interactive engine converts this into the appropriate high-level workflow result.

---

# Safe Regression Suite

Run:

```bash
./tests/run-safe-tests.sh
```

This suite covers core safety and regression behavior.

Current areas include:

```text
Bash syntax
configuration command-injection protection
configuration relationship validation
protected process policy
stale PID rejection
invalid diagnosis return normalization
invalid remediation return normalization
invalid verification return normalization
no-action remediation semantics
ionice rollback restoration
required ps failure handling
optional vmstat fallback
CPU evidence arithmetic
Markdown and JSON report semantics
```

The report test also checks machine-readable semantics such as:

```text
schema_version
mode
target
coverage
executed
NOT_RUN
null exit codes
```

The expected application version is derived from the project version instead of being hard-coded into the test.

---

# UI Regression Suite

Run:

```bash
./tests/run-ui-tests.sh
```

This verifies separation between terminal presentation and automation output.

Important checks include:

```text
UI Bash syntax
non-TTY scan behavior
interactive non-TTY guard
TTY UI rendering
NO_COLOR behavior
```

Redirected output must not contain terminal ANSI escape sequences.

---

# Incident Suite

Run:

```bash
./tests/run-incident-tests.sh
```

This creates bounded workloads representing the five primary incident categories:

```text
CPU saturation
Memory pressure
Disk I/O pressure
Network connection activity
File descriptor exhaustion
```

The workloads are intended for controlled testing.

They are not benchmarks.

Test helpers should be cleaned up after execution.

---

# Fault Injection Suite

Run:

```bash
./tests/run-fault-injection-tests.sh
```

Fault injection deliberately simulates failures without intentionally damaging the host system.

Tested scenarios include:

```text
malicious configuration
required telemetry failure
required preflight dependency failure
optional preflight dependency failure
optional vmstat failure
report generation failure
missing interactive function
invalid module return code
stale PID
```

Expected behavior follows the fail-safe model.

Examples:

```text
required dependency missing
    → UNSUPPORTED

optional dependency missing
    → DEGRADED

required runtime telemetry unreliable
    → UNKNOWN

stale PID
    → reject signal
```

---

# Final Regression Gate

Run:

```bash
./tests/run-final-regression.sh
```

This is the main release regression gate.

It validates:

```text
Bash syntax
production ShellCheck
version contract
help / CLI contract
unknown command behavior
preflight automation
scan automation
single-target diagnosis
all-subsystem diagnosis
interactive non-TTY guard
scan namespace behavior
safe regression suite
UI regression suite
incident suite
```

A release candidate should not be accepted if this gate fails.

---

# ShellCheck

Production code is checked with:

```bash
find \
  lpd.sh lib checks diagnostics fixes verify \
  -type f \
  -name '*.sh' \
  -print0 |
xargs -0 shellcheck \
  -x \
  -e SC1090,SC1091,SC2034,SC2317,SC2016
```

Some exclusions correspond to known limitations of static analysis across sourced Bash modules.

They should not be used to hide actionable defects.

Historically identified real issues have included:

```text
unsafe awk variable naming
naive /proc/<pid>/stat parsing
namespace leakage
```

Those problems were fixed instead of suppressed.

---

# Non-Interactive Regression

Automation-oriented commands should support output redirection.

Example:

```bash
./lpd.sh scan > /tmp/lpd-scan.out 2>&1
```

The output should not contain:

```text
ANSI escape sequences
interactive prompts
TTY-only progress decoration
```

---

# Interactive Regression

Interactive mode must require a real terminal.

For example:

```bash
./lpd.sh interactive cpu </dev/null
```

should fail rather than attempting remediation.

Expected high-level result:

```text
exit code 3
```

---

# Report Validation

Generated JSON should be syntactically valid.

Example:

```bash
jq -e . reports/example.json >/dev/null
```

The JSON schema includes:

```text
schema_version
run metadata
coverage
subsystems
evidence
remediations
actions
audit log reference
```

Missing machine-readable values should use:

```json
null
```

rather than `"N/A"`.

---

# Coverage Validation

A single-subsystem workflow must not masquerade as a full-system health assessment.

For:

```text
interactive cpu
```

expected semantics include:

```json
{
  "coverage": {
    "scope": "cpu",
    "full_system": false
  }
}
```

Only the CPU subsystem should indicate:

```json
"executed": true
```

for that workflow.

---

# Full-System Coverage

For:

```text
interactive all
```

expected coverage is:

```json
{
  "coverage": {
    "scope": "all",
    "full_system": true
  }
}
```

All five subsystem workflows should indicate execution.

Their health results remain dependent on the real system state.

Tests should never require a healthy result merely because all workflows executed.

---

# Packaging Validation

Build:

```bash
./scripts/build-release.sh
```

The builder performs several packaging checks.

After building, verify the archive:

```bash
cd dist

sha256sum -c \
  linux-performance-detective-0.2.0-rc1.tar.gz.sha256
```

Then test extraction:

```bash
rm -rf /tmp/lpd-package-test
mkdir -p /tmp/lpd-package-test

tar -xzf \
  linux-performance-detective-0.2.0-rc1.tar.gz \
  -C /tmp/lpd-package-test
```

Inside the extracted package:

```bash
./lpd.sh version
./lpd.sh help
```

must work.

---

# Release Candidate Gate

For an RC build, the expected sequence is:

```text
Safe Regression
      ↓
UI Regression
      ↓
Incident Regression
      ↓
Fault Injection
      ↓
Final Regression
      ↓
Build Release
      ↓
Verify SHA256
      ↓
Extract Smoke Test
```

If an earlier stage fails, the release should not be promoted.

---

# Testing Principle

Tests should verify actual contracts.

They should not force the system to report healthy when the host is genuinely under load.

A valid test distinguishes between:

```text
correct program behavior
```

and:

```text
a particular host health state
```

The objective is to prove that LPD reports uncertainty and failure correctly, not merely to maximize the number of green test messages.
