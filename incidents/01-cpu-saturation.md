# Incident 01 - CPU Saturation

## Scenario

A Linux process caused one CPU core to become fully utilized.

The test process was:

yes > /dev/null

## Symptoms

During the incident:

- One CPU core reached 100% utilization.
- CPU 1 showed 0% idle time.
- Overall CPU idle dropped to approximately 47%.
- The system was not experiencing significant I/O wait.

## Baseline

Before the incident, the system was mostly idle.

Average CPU idle:

97.58%

I/O wait:

0%

This confirmed that the CPU load was caused by the test process and was not normal system activity.

## Investigation

### 1. mpstat

Command used:

mpstat -P ALL 1 5

Result:

CPU 1 reached 0% idle while CPU 0 remained mostly idle.

This indicated that one CPU core was fully utilized.

### 2. ps

Command used:

ps -eo pid,comm,%cpu,%mem,stat --sort=-%cpu | head

Result:

The `yes` process was using approximately 100% CPU.

The process state was `R`, meaning running or runnable.

### 3. strace

Command used:

strace -c -p PID

Result:

100% of the observed system calls were:

write()

During one test, 15,344 write system calls were observed.

This showed that the process was continuously writing data to /dev/null.

### 4. perf

Command used:

perf stat -p PID sleep 5

Result:

Approximately:

0.998 CPUs utilized

This confirmed that the process was consuming almost one complete CPU core.

Hardware counters such as cycles and instructions were not available inside the VMware virtual machine.

### 5. bpftrace / eBPF

Command used:

bpftrace -e 'tracepoint:syscalls:sys_enter_write /comm == "yes"/ { @writes = count(); } interval:s:1 { print(@writes); clear(@writes); }'

Result:

The process generated hundreds of thousands of write() system calls per second.

Observed values included approximately:

237,000 writes/sec
323,000 writes/sec
336,000 writes/sec

eBPF allowed the syscall activity to be observed with much lower tracing overhead than strace.

## Root Cause

The `yes` process continuously generated output and wrote it to `/dev/null`.

This caused a very large number of `write()` system calls and consumed approximately one full CPU core.

## Resolution

The offending process was terminated using:

kill PID

## Verification

After stopping the process:

- Overall CPU idle returned to approximately 97.6%.
- CPU 0 idle was approximately 96.8%.
- CPU 1 idle was approximately 98.4%.
- I/O wait remained at 0%.

The system returned to its normal baseline.

## Tools Used

- mpstat
- ps
- strace
- perf
- bpftrace
- eBPF
