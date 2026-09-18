#!/usr/bin/env bash
set -euo pipefail
ulimit -c 0
root=$(cd "$(dirname "$0")/.." && pwd)
build_dir="${PCAT_BUILD_DIR:-$root/build/at-xub-probe}"
mkdir -p "$build_dir"
cd "$root"
nasm -f bin tests/firmware/at_xub_probe.asm -o "$build_dir/fixture.bin"
mapfile -t sources < <(sed -n 's/.*SYSTEMVERILOG_FILE "\(vendor\/spk286\/[^\"]*\.sv\)".*/\1/p' rtl/spk286_integration/spk286_integration.qip)
sources+=(
  rtl/common/simple_fifo.v rtl/common/floppy.v rtl/common/ide.v
  sim/spk286_integration/dpram_model.sv
  rtl/spk286_integration/spk286_machine_cpu.sv
  rtl/spk286_integration/spk286_at_bus_bridge.sv
  rtl/spk286_integration/spk286_at_memory_decode.sv
  rtl/spk286_integration/spk286_at_arbiter.sv
  rtl/spk286_integration/spk286_at_pic.sv
  rtl/spk286_integration/spk286_at_dma.sv
  rtl/spk286_integration/spk286_at_refresh.sv
  rtl/spk286_integration/spk286_at_pit.sv
  rtl/spk286_integration/spk286_at_pit_clock.sv
  rtl/spk286_integration/spk286_at_system_control.sv
  rtl/spk286_integration/spk286_at_8042.sv
  rtl/spk286_integration/spk286_at_rtc_cmos.sv
  rtl/spk286_integration/spk286_at_fdc.sv
  rtl/spk286_integration/spk286_at_xtide.sv
  rtl/spk286_integration/spk286_at_storage_video.sv
  rtl/spk286_integration/spk286_at_video_adapter.sv
  rtl/spk286_integration/at286ctl.sv
  rtl/KFPC-XT/HDL/ega_vram_bram_frontend.sv
  rtl/common/tandy_pcjr_joy.sv
  rtl/spk286_integration/spk286_at_gameport.sv
  rtl/spk286_integration/spk286_at_sound.sv
  rtl/spk286_integration/spk286_at_serial.sv
  rtl/spk286_integration/spk286_at_device_router.sv
  rtl/spk286_integration/spk286_at_machine.sv
  rtl/KFPC-XT/HDL/KF8253/HDL/*.sv rtl/KFPC-XT/HDL/KF8259/HDL/*.sv
  rtl/video/*.v rtl/video/*.sv sim/spk286_integration/spk286_at_xub_probe_tb.sv
)
verilator --binary --timing -j 4 -Wno-fatal -DSPK286_P05_PARALLEL_LIMIT_CHECK \
  -DSPK286_AT_SIM_MODEL \
  -Irtl/KFPC-XT/HDL/KF8253/HDL -Irtl/KFPC-XT/HDL/KF8259/HDL \
  --top-module spk286_at_xub_probe_tb --Mdir "$build_dir/obj" -o xub_probe \
  "${sources[@]}" >"$build_dir/build.log" 2>&1
cd "$root/rtl/video"
for variant in missing fixed; do
fixture="$build_dir/fixture.bin"
rom="$root/SW/ROMs/test/xtsergey_mod_at_atpic.rom"
extra=(+EXPECT_MISSING_INT40)
if [[ "$variant" == fixed ]]; then
  rom="$root/SW/ROMs/test/xtsergey_mod_at_atpic_int40.rom"
  extra=()
fi
"$build_dir/obj/xub_probe" \
  "+ROM=$rom" \
  "+XUB=$root/SW/ROMs/test/ide_at.bin" "+FIXTURE=$fixture" \
  "+TRACE=$build_dir/instructions-$variant.log" "+TRACE_LIMIT=${TRACE_LIMIT:-30000}" \
  "+MAX_CYCLES=${MAX_CYCLES:-1000000}" +STOP_AT_DETECTION "${extra[@]}" | tee "$build_dir/run-$variant.log"
done

# Post-detection regression: unchanged BIOS/XUB, two synthetic ATA disks.
# Speed up only the fixture's PIT divisor; still execute the production PIT,
# PIC and Sergey IRQ0 handler. No BDA tick injection or BIOS wait patch.
nasm -f bin -DPIT_DIVISOR=1024 "$root/tests/firmware/at_xub_probe.asm" \
  -o "$build_dir/fixture-fast.bin"
"$build_dir/obj/xub_probe" \
  "+ROM=$root/SW/ROMs/test/xtsergey_mod_at_atpic_int40.rom" \
  "+XUB=$root/SW/ROMs/test/ide_at.bin" "+FIXTURE=$build_dir/fixture-fast.bin" \
  +TWO_DISKS +CONTINUE_BOOT +MAX_CYCLES=6000000 | tee "$build_dir/run-boot-fixed.log"
