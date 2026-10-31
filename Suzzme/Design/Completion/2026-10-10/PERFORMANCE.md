# Performance evidence and limits

Measurements from this pass are diagnostic samples, not a production benchmark. The host has 8 GiB RAM. Simulator startup, builds and acceptance harnesses contended for resources; the computer-use service was intermittently unavailable. No app optimization was made without evidence of an app bottleneck.

| Measurement | Observed | Meaning |
|---|---|---|
| Mac process PID 27299, elapsed 3:50 | 0.0% CPU, RSS 10,672 KiB | Single idle sample from the unsigned Debug app; RSS alone omits compressed/shared footprint |
| Relaunched Mac process PID 30192, elapsed 16:53 | 0.0% CPU, RSS 8,960 KiB | Single idle sample during host contention; not representative peak working memory |
| System memory query | 8,589,934,592 bytes; reported free percentage 31% | Host diagnostic at one instant, not battery/thermal acceptance |
| Step 11 acceptance command | 964.91 s in the contended rerun | Includes compilation and test execution; **not** summary/assistant latency |
| Other acceptance commands | Recorded individually in validation `results.json` | Build/harness wall time only, not user-perceived runtime latency |

Exact diagnostic commands: `ps -p <observed Suzzme PID> -o pid=,etime=,%cpu=,rss=,comm=` and `memory_pressure -Q`. No process environment or credential-bearing arguments were inspected for these measurements.

Still unmeasured: controlled cold/warm launch, invocation, first transcript, first spoken response, Foundation Models latency, real network read latency, summary generation under real accounts, Memory retrieval latency, sustained CPU/footprint, battery and thermal behavior. Instruments/device traces are required. Audible quality requires human listening.

The iPhone 18 Pro and then iPhone 17 Pro simulator attempts stalled during boot/install. The test devices were shut down without deleting their data; pending install commands returned CoreSimulator invalid-state / IPC-server-died errors during cleanup. No successful iOS app launch was observed in this pass. This is an environment-blocked runtime check, not evidence of an app startup crash or a simulator PASS.

A third runtime attempt after compilation finished again stalled on install. The Simulator GUI application could not be located through computer use or at the selected Xcode developer path. Shutdown succeeded without erasing data; the pending install exited 204 with NSMachError -308 (IPC server died). This did not establish an app defect or runtime acceptance.
