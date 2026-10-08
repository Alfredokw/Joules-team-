# Ubuntu server setup

The final host described in the paper is Ubuntu 24.04 on two Intel Xeon Silver
4208 processors with approximately 384 GiB RAM. The preflight check rejects a
different host unless `--allow-hardware-mismatch` is explicitly used for a
diagnostic run.

## System packages

```sh
sudo apt update
sudo apt install -y clang valgrind python3 make time git cargo libcap2-bin \
  linux-tools-common linux-tools-$(uname -r)
sudo modprobe msr
```

Confirm that `clang`, `valgrind`, `/usr/bin/time`, and `turbostat` are available.

## EnergiBridge

Install a fixed EnergiBridge release and retain its version in the replication
archive. A source installation can be made from the official repository:

```sh
git clone https://github.com/tdurieux/EnergiBridge.git
cd EnergiBridge
cargo build --release
sudo install -m 0755 target/release/energibridge /usr/local/bin/energibridge
sudo setcap cap_sys_rawio=ep /usr/local/bin/energibridge
```

If EnergiBridge is stored elsewhere, set `ENERGIBRIDGE_BIN` to its absolute
path before running the experiment.

## Counter permissions

EnergiBridge and Turbostat must be able to read the Intel MSR/RAPL counters.
Capabilities may need to be reapplied after moving or upgrading either binary.

```sh
sudo setcap cap_sys_admin,cap_sys_rawio,cap_sys_nice=ep "$(command -v turbostat)"
sudo chmod +r /dev/cpu/*/msr
sudo chmod +r /dev/cpu_dma_latency
```

Do not start the measured campaign until both live measurement checks in
`scripts/preflight.py` pass.

## Final checks

From the package root:

```sh
make static-check
make preflight
python3 scripts/validate.py --repeats 3
make validate-detectors
make smoke
```

The preflight report is saved as `results/preflight.json` and records the host,
kernel, CPU, memory, and tool versions. Preserve it with the final results.
