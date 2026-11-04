#!/usr/bin/env bash
# UART receiver, stop-bit handling. Back-to-back 8N1 characters from a
# transmitter whose clock differs from the receiver's by a little: with
# MIDSTOP=1 (COM2) every character must arrive intact for a transmitter up to
# 2.5 % fast or 2.5 % slow. MIDSTOP=0 (original receiver, COM1/MPU-401) is
# only required to still be right at the exact rate.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"

opts="--std=93c --ieee=synopsys"
for f in slib_clock_div slib_counter slib_edge_detect slib_input_filter \
         slib_input_sync slib_mv_filter uart_receiver; do
  ghdl -a $opts "$root/rtl/uart/$f.vhd"
done
ghdl -a $opts "$root/sim/uart/uart_rx_midstop_tb.vhd"
ghdl -e $opts uart_rx_midstop_tb

run() {  # midstop txbit
  ghdl -r $opts uart_rx_midstop_tb -gMIDSTOP=$1 -gTXBIT=$2 2>&1 | grep RESULT | sed 's/.*RESULT/RESULT/'
}

fail=0
for tx in 156 158 160 164 166; do          # receiver bit time is 160 clocks
  line=$(run 1 "$tx"); echo "$line"
  case "$line" in *"got=200 wrong=0 fe=0"*) ;; *) fail=1 ;; esac
done
line=$(run 0 160); echo "$line"
case "$line" in *"got=200 wrong=0 fe=0"*) ;; *) fail=1 ;; esac

if [ "$fail" -ne 0 ]; then echo UART_RX_MIDSTOP_TEST_FAIL; exit 1; fi
echo UART_RX_MIDSTOP_TEST_PASS
