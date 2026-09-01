# Incident 03 - Memory Pressure and Swap Investigation

## Scenario

A controlled memory workload was generated to observe how Linux behaves under memory pressure and when swap begins to be used.

The test system had approximately:

* 1.9 GiB RAM
* 984 MiB Swap

## Baseline

Before the test:

* Available memory: approximately 1.2 GiB
* Swap used: 0
* Swap-in: 0
* Swap-out: 0
* CPU idle: approximately 95% to 98%

This confirmed that the system was not under memory pressure before the workload.

## Workload

Memory pressure was generated using:

`stress-ng --vm 1 --vm-bytes 1.5G --vm-keep --timeout 20s`

During execution, `stress-ng` reported that approximately 1 GiB was used by the memory worker.

## Investigation

### 1. free

Command used:

`free -h`

Before the workload:

* RAM total: approximately 1.9 GiB
* Available memory: approximately 1.2 GiB
* Swap used: 0

This showed that the system had sufficient available memory.

### 2. vmstat

Command used:

`vmstat 1`

During the workload, free memory decreased progressively:

* Approximately 623 MiB
* 486 MiB
* 404 MiB
* 330 MiB
* 244 MiB
* 162 MiB
* 88 MiB
* Approximately 67 MiB

At the same time, Linux began reclaiming memory used for cache.

Cache decreased from approximately:

`760 MiB`

to approximately:

`291 MiB`

This showed that Linux attempted to reclaim reusable memory before relying heavily on swap.

## Swap Activity

As memory pressure increased, swap began to be used.

Observed swap usage increased to approximately:

`15-16 MiB`

Swap-out activity was observed in `vmstat`.

Example values:

* `so = 10708 KB/s`
* `so = 4960 KB/s`

This confirmed that the kernel moved some memory pages from RAM to swap.

After the workload finished, small amounts of swap-in were also observed.

Example values:

* `si = 152 KB/s`
* `si = 52 KB/s`
* `si = 28 KB/s`

## CPU Behavior

During peak memory pressure, kernel CPU usage increased significantly.

System CPU usage reached approximately:

`79%`

This reflected additional kernel work related to memory allocation, page reclaim, and swap management.

## Recovery

After `stress-ng` completed:

* Available memory returned to approximately 1.2 GiB
* Free memory increased to approximately 1.1 GiB
* Swap still contained approximately 15 MiB
* Active swap-in and swap-out returned to zero
* CPU idle returned to approximately 96% to 98%

The remaining swap usage did not indicate continuing memory pressure.

Linux does not immediately move all swapped pages back into RAM if those pages are not actively required.

## Findings

This incident demonstrated that low free memory alone does not prove that a Linux system is experiencing memory pressure.

Linux may use memory for cache and reclaim that memory when required.

More meaningful indicators of memory pressure include:

* Low available memory
* Active swap-out
* Active swap-in
* Increased kernel CPU usage
* Sustained page reclaim activity

## Root Cause

The controlled `stress-ng` workload consumed a large amount of RAM.

As available memory decreased, the Linux kernel reclaimed cache and eventually moved some memory pages to swap.

## Resolution

The workload automatically stopped after 20 seconds.

After the workload ended, memory was released and the system returned to its normal baseline.

No manual recovery action was required.

## Conclusion

The incident showed the difference between:

* Low free memory
* Actual memory pressure
* Active swapping

A Linux administrator should not diagnose memory problems using only the `free` column.

Available memory and swap activity provide more useful evidence.

## Tools Used

* free
* vmstat
* stress-ng
* swap
* Linux memory management
