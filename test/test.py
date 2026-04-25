# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")

    # Set the clock period to 10 us (100 KHz)
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    # Reset
    dut._log.info("Reset")
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    dut.uio_in.value = 0b00001000 # start = uio_in[3]

    dut._log.info("Test project behavior")
    
    # --- Cycle 1: First sample, must emit as RAW ---
    dut.ui_in.value = 50
    await ClockCycles(dut.clk, 1)
    assert dut.uo_out.value == 50, f"first sample data: expected 50, got {int(dut.uo_out.value)}"
    assert dut.uio_out.value == 0b00000111, f"first sample: expected RAW+save (0b111), got {bin(int(dut.uio_out.value))}"
    # Decoding: uio_out[1:0]=11 (RAW), uio_out[2]=1 (save), upper bits 0
    
    # --- Cycle 2: Same value, starts RLE run silently ---
    dut.ui_in.value = 50
    await ClockCycles(dut.clk, 1)
    assert dut.uio_out.value & 0b00000100 == 0, f"RLE accumulating: save should be 0, got {bin(int(dut.uio_out.value))}"
    
    # --- Cycle 3: Same value again, extends RLE run silently ---
    dut.ui_in.value = 50
    await ClockCycles(dut.clk, 1)
    assert dut.uio_out.value & 0b00000100 == 0, f"RLE accumulating: save should be 0, got {bin(int(dut.uio_out.value))}"
    
    # --- Cycle 4: Different value (large delta), breaks RLE ---
    # Should emit RLE packet with count=2, queue RAW 200 in mailbox
    dut.ui_in.value = 200
    await ClockCycles(dut.clk, 1)
    assert dut.uo_out.value == 2, f"RLE count: expected 2, got {int(dut.uo_out.value)}"
    assert dut.uio_out.value == 0b00000100, f"RLE close: expected code=00 + save=1 (0b100), got {bin(int(dut.uio_out.value))}"
    # Decoding: uio_out[1:0]=00 (RLE), uio_out[2]=1 (save)
    
    # --- Cycle 5: Pending drain — emits the queued RAW 200 ---
    # Pick ui_in that won't match storageold(=200) and won't have meaningful delta_match
    dut.ui_in.value = 100
    await ClockCycles(dut.clk, 1)
    assert dut.uo_out.value == 200, f"drained RAW data: expected 200, got {int(dut.uo_out.value)}"
    assert dut.uio_out.value == 0b00000111, f"drained RAW: expected RAW+save (0b111), got {bin(int(dut.uio_out.value))}"
    
    # --- Cycle 6: ui_in=100, storageold=200, delta=-100 (doesn't fit, RAW) ---
    # No pending, no match. Should emit RAW 100.
    dut.ui_in.value = 105
    await ClockCycles(dut.clk, 1)
    assert dut.uo_out.value == 100, f"standalone RAW: expected 100, got {int(dut.uo_out.value)}"
    assert dut.uio_out.value == 0b00000111, f"standalone RAW: expected 0b111, got {bin(int(dut.uio_out.value))}"
    
    # --- Cycle 7: ui_in=105, storageold=100, delta=+5 (fits, DELTA) ---
    dut.ui_in.value = 110
    await ClockCycles(dut.clk, 1)
    # DELTA packet: code=10, save=1 → uio_out = 0b00000110
    # data = {new_delta[4:0], 3'b000} = {5'b00101, 3'b000} = 0b00101000 = 40
    assert dut.uo_out.value == 0b00101000, f"DELTA payload: expected 0b00101000, got {bin(int(dut.uo_out.value))}"
    assert dut.uio_out.value == 0b00000110, f"DELTA packet: expected 0b110, got {bin(int(dut.uio_out.value))}"
    
    # --- Cycle 8: ui_in=110, storageold=105, delta=+5 — matches last delta, starts DeltaRLE ---
    dut.ui_in.value = 115
    await ClockCycles(dut.clk, 1)
    assert dut.uio_out.value & 0b00000100 == 0, f"DeltaRLE accumulating: save should be 0, got {bin(int(dut.uio_out.value))}"
    
    # --- Cycle 9: ui_in=115, delta=+5, extends DeltaRLE ---
    dut.ui_in.value = 200
    await ClockCycles(dut.clk, 1)
    assert dut.uio_out.value & 0b00000100 == 0, f"DeltaRLE accumulating: save should be 0, got {bin(int(dut.uio_out.value))}"
    
    # --- Cycle 10: ui_in=200, storageold=115, delta=+85 (no match), breaks DeltaRLE ---
    dut.ui_in.value = 50
    await ClockCycles(dut.clk, 1)
    assert dut.uo_out.value == 2, f"DeltaRLE count: expected 2, got {int(dut.uo_out.value)}"
    assert dut.uio_out.value == 0b00000101, f"DeltaRLE close: expected code=01 + save=1 (0b101), got {bin(int(dut.uio_out.value))}"
