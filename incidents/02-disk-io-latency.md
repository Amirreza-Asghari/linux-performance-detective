# Incident 02 - Disk I/O Latency Investigation

## Scenario

A controlled 4 KiB random-write workload was generated on the Linux virtual machine to investigate disk I/O performance and latency.

The test was performed on `/lab`, located on the `/dev/sda3` ext4 filesystem.

## Baseline

Before generating the workload, the disk was mostly idle.

Observed baseline:

* I/O wait: approximately 0%
* Disk utilization: approximately 0%
* I/O queue: approximately 0
* Very little read or write activity

This confirmed that the system was not experiencing significant storage activity before the test.

## Workload

The workload was generated using `fio`.

Test characteristics:

* Random writes
* Block size: 4 KiB
* Direct I/O enabled
* Linux AIO (`libaio`)
* Test file size: 512 MiB
* Initial queue depth: 32

## Investigation

### 1. iostat

Command used:

`iostat -xz 1`

During the workload, disk activity increased significantly.

Observed values included:

* Approximately 2,900 to 4,500 writes per second
* Disk utilization approximately 70% to 90%
* I/O queue approximately 1 to 2
* System CPU usage increased significantly

This confirmed that the workload was creating heavy storage activity.

## fio Results - Queue Depth 32

With:

`iodepth=32`

Observed results:

* IOPS: approximately 4,223
* Bandwidth: approximately 16.5 MiB/s
* Average completion latency: approximately 7.35 ms
* Average total latency: approximately 7.56 ms
* System CPU usage: approximately 93%

The workload achieved higher throughput but also showed significantly higher latency.

## eBPF/BCC Investigation

Block I/O latency was investigated using:

`biolatency-bpfcc`

Most block-device I/O requests completed in less than 1 millisecond.

Example histogram:

`0 -> 1 ms: several thousand requests`

A small number of requests showed higher tail latency.

The test was repeated using the `-Q` option to include operating-system queue time.

Most requests still completed below 1 ms, although some requests appeared in higher latency ranges such as:

* 2–3 ms
* 4–7 ms
* 8–15 ms
* 16–31 ms
* Higher latency outliers

This showed that the block device itself was completing most requests quickly.

## Queue Depth Investigation

The test was repeated with:

`iodepth=1`

Observed results:

* IOPS: approximately 2,485
* Bandwidth: approximately 9.7 MiB/s
* Average completion latency: approximately 0.247 ms
* Average total latency: approximately 0.397 ms
* System CPU usage: approximately 44.8%

Reducing queue depth from 32 to 1 caused latency to decrease dramatically.

Completion latency changed from approximately:

`7.35 ms`

to:

`0.247 ms`

This is approximately a 30x reduction in average completion latency.

However, throughput also decreased.

## Findings

Increasing I/O queue depth produced higher throughput but significantly increased latency.

The investigation also showed that high application-level I/O latency did not automatically mean the virtual disk itself was slow.

eBPF/BCC showed that most block-device requests completed in less than 1 ms.

The high latency observed by `fio` was strongly associated with increased I/O concurrency and queue depth.

## Root Cause

The high observed I/O latency was primarily associated with running many concurrent I/O operations using a queue depth of 32.

The storage device itself handled most individual block requests relatively quickly.

## Conclusion

This incident demonstrated an important storage-performance trade-off:

Higher queue depth can increase IOPS and throughput, but it can also significantly increase application-visible latency.

Disk performance should therefore not be diagnosed using a single metric such as average latency, `%util`, or `%iowait`.

Multiple tools and measurements are required to understand where latency is occurring.

## Tools Used

* fio
* iostat
* biolatency-bpfcc
* eBPF
* BCC
