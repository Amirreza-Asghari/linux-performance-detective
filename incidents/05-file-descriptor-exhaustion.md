# Incident 05 - File Descriptor Exhaustion

## Scenario

A controlled per-process file descriptor limit was configured to simulate an application failing because it could no longer open additional files or resources.

The test was performed inside a temporary Bash process so that the main system environment was not affected.

## Baseline

The original shell had:

* Soft open-file limit: 1024
* Hard open-file limit: 524288
* Approximately 4 file descriptors open in the shell

The system-wide file handle limit was not the bottleneck.

## Controlled Limit

A temporary Bash process was configured with:

`ulimit -n 64`

The limit was verified using:

`/proc/PID/limits`

Observed value:

`Max open files 64 64 files`

This confirmed that the test process could open a maximum of 64 file descriptors.

## Failure Simulation

The test process repeatedly opened `/dev/null` until no additional file descriptors were available.

The process successfully opened approximately 54 additional descriptors before Bash reported:

`Too many open files`

The number was lower than 64 because the process already required file descriptors for standard input, standard output, standard error, and internal shell operations.

## File Descriptor Inspection

Open descriptors were inspected using:

`/proc/PID/fd`

Standard descriptors included:

* FD 0 - standard input
* FD 1 - standard output
* FD 2 - standard error

Additional descriptors were observed pointing to:

`/dev/null`

This demonstrated how `/proc/PID/fd` can be used to inspect the resources currently held open by a Linux process.

## Syscall Investigation

The failure was traced using `strace`.

The important syscall result was:

`fcntl(3, F_DUPFD, 10) = -1 EMFILE (Too many open files)`

The kernel returned:

`EMFILE`

This confirmed that the failure was caused by the per-process file descriptor limit.

## Root Cause

The process reached its configured maximum number of open file descriptors.

This was a per-process resource exhaustion issue rather than a system-wide file handle exhaustion problem.

## Resolution

The test was performed inside a temporary process.

When the process terminated, all file descriptors belonging to it were automatically closed by the kernel.

The main shell retained its original file descriptor limit.

## Findings

A `Too many open files` error should not automatically be treated as a system-wide resource problem.

Useful investigation points include:

* Per-process soft limit
* Per-process hard limit
* `/proc/PID/limits`
* `/proc/PID/fd`
* Number and type of open descriptors
* Syscall errors such as `EMFILE`

`EMFILE` indicates that a process has reached its own open-file limit.

## Conclusion

Linux file descriptor problems can be diagnosed by combining resource limits, `/proc` inspection, and syscall tracing.

Increasing the limit without identifying why an application is opening excessive resources may only hide the underlying problem.

## Tools Used

* ulimit
* /proc/PID/limits
* /proc/PID/fd
* strace
* Bash
