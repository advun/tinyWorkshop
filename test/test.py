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
    


    dut.ui_in.value = 50  # in1 (RAW 50)
    await ClockCycles(dut.clk, 1)

    dut.ui_in.value = 50  # in2 (RLE start, silent)
    await ClockCycles(dut.clk, 1)

    dut.ui_in.value = 50  # in3 (RLE extend, silent)
    # test1: in1 produced RAW 50
    assert int(dut.uo_out.value) == 50, f"test1 data: expected 50, got {int(dut.uo_out.value)}"
    assert int(dut.uio_out.value) == 0b111, f"test1: expected RAW+save (0b111), got {bin(int(dut.uio_out.value))}"
    await ClockCycles(dut.clk, 1)

    dut.ui_in.value = 200  # in4 (RLE break, emits RLE(2), queues RAW 200)
    # test2: in2 produced silent RLE start (save=0)
    assert (int(dut.uio_out.value) & 0b100) == 0, f"test2 save should be 0, got {bin(int(dut.uio_out.value))}"
    await ClockCycles(dut.clk, 1)

    dut.ui_in.value = 100  # in5 (drains pending RAW 200, re-queues RAW 100)
    # test3: in3 produced silent RLE extend (save=0)
    assert (int(dut.uio_out.value) & 0b100) == 0, f"test3 save should be 0, got {bin(int(dut.uio_out.value))}"
    await ClockCycles(dut.clk, 1)

    dut.ui_in.value = 105  # in6 (drains pending RAW 100, re-queues DELTA +5)
    # test4: in4 produced RLE break -> RLE(2)
    assert int(dut.uo_out.value) == 2, f"test4 RLE count: expected 2, got {int(dut.uo_out.value)}"
    assert int(dut.uio_out.value) == 0b100, f"test4: expected RLE+save (0b100), got {bin(int(dut.uio_out.value))}"
    await ClockCycles(dut.clk, 1)

    dut.ui_in.value = 110  # in7 (drains pending DELTA, starts DeltaRLE)
    # test5: in5 drained pending -> RAW 200
    assert int(dut.uo_out.value) == 200, f"test5 drained RAW: expected 200, got {int(dut.uo_out.value)}"
    assert int(dut.uio_out.value) == 0b111, f"test5: expected RAW+save (0b111), got {bin(int(dut.uio_out.value))}"
    await ClockCycles(dut.clk, 1)

    dut.ui_in.value = 115  # in8 (DeltaRLE extend, silent)
    # test6: in6 drained pending -> RAW 100
    assert int(dut.uo_out.value) == 100, f"test6 drained RAW: expected 100, got {int(dut.uo_out.value)}"
    assert int(dut.uio_out.value) == 0b111, f"test6: expected RAW+save (0b111), got {bin(int(dut.uio_out.value))}"
    await ClockCycles(dut.clk, 1)

    dut.ui_in.value = 200  # in9 (DeltaRLE break, emits DELTARLE(2), queues RAW 200)
    # test7: in7 drained pending -> DELTA(+5) = 0b00101000
    assert int(dut.uo_out.value) == 0b00101000, f"test7 DELTA payload: expected 0b00101000, got {bin(int(dut.uo_out.value))}"
    assert int(dut.uio_out.value) == 0b110, f"test7: expected DELTA+save (0b110), got {bin(int(dut.uio_out.value))}"
    await ClockCycles(dut.clk, 1)

    dut.ui_in.value = 200  # in10 (drains pending RAW 200, starts RLE run since 200==200)
    # test8: in8 produced silent DeltaRLE extend (save=0)
    assert (int(dut.uio_out.value) & 0b100) == 0, f"test8 save should be 0, got {bin(int(dut.uio_out.value))}"
    await ClockCycles(dut.clk, 1)

    dut.ui_in.value = 50  # in11 (RLE break since 50!=200, emits RLE(1), queues RAW 50)
    # test9: in9 produced DeltaRLE break -> DELTARLE(2)
    assert int(dut.uo_out.value) == 2, f"test9 DeltaRLE count: expected 2, got {int(dut.uo_out.value)}"
    assert int(dut.uio_out.value) == 0b101, f"test9: expected DELTARLE+save (0b101), got {bin(int(dut.uio_out.value))}"
    await ClockCycles(dut.clk, 1)

    # Drain final pending and check last few results
    # test10: in10 drained pending -> RAW 200
    assert int(dut.uo_out.value) == 200, f"test10 drained RAW: expected 200, got {int(dut.uo_out.value)}"
    assert int(dut.uio_out.value) == 0b111, f"test10: expected RAW+save (0b111), got {bin(int(dut.uio_out.value))}"

    
    #RESET TESTING
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    dut.uio_in.value = 0b00001000 # start = uio_in[3]
    
    #DIFFERENT START TESTING
    dut.ui_in.value = 50  # in1 (RAW 50)
    await ClockCycles(dut.clk, 1)

    dut.ui_in.value = 20  # in2 (RAW20)
    await ClockCycles(dut.clk, 1)

    dut.ui_in.value = 50  # in3 (RAW50)
    # test1: in1 produced RAW 50
    assert int(dut.uo_out.value) == 50, f"test1 data: expected 50, got {int(dut.uo_out.value)}"
    assert int(dut.uio_out.value) == 0b111, f"test1: expected RAW+save (0b111), got {bin(int(dut.uio_out.value))}"
    await ClockCycles(dut.clk, 1)

    #OVERFLOW TESTING
    # test2: in2 produced RAW 20
    assert int(dut.uo_out.value) == 20, f"test1 data: expected 50, got {int(dut.uo_out.value)}"
    assert int(dut.uio_out.value) == 0b111, f"test1: expected RAW+save (0b111), got {bin(int(dut.uio_out.value))}"
    await ClockCycles(dut.clk, 1)


    # test3: in3 produced RAW 50
    assert int(dut.uo_out.value) == 50, f"test1 data: expected 50, got {int(dut.uo_out.value)}"
    assert int(dut.uio_out.value) == 0b111, f"test1: expected RAW+save (0b111), got {bin(int(dut.uio_out.value))}"
    await ClockCycles(dut.clk, 1)

    # RESET!!!! TEST OVERFLOW 
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    dut.uio_in.value = 0b00001000

    dut.ui_in.value = 200
    await ClockCycles(dut.clk, 1)

    dut.ui_in.value = 200
    await ClockCycles(dut.clk, 1)

    dut.ui_in.value = 200
    assert int(dut.uo_out.value) == 200, f"in1 RAW data: expected 200, got {int(dut.uo_out.value)}"
    assert int(dut.uio_out.value) == 0b111, f"in1: expected RAW+save (0b111), got {bin(int(dut.uio_out.value))}"
    await ClockCycles(dut.clk, 1)

    for i in range(4, 257):
        dut.ui_in.value = 200
        assert (int(dut.uio_out.value) & 0b100) == 0, f"in{i-2}: save should be 0 during accumulation, got {bin(int(dut.uio_out.value))}"
        await ClockCycles(dut.clk, 1)

    dut.ui_in.value = 200
    assert (int(dut.uio_out.value) & 0b100) == 0, f"in255: save should still be 0, got {bin(int(dut.uio_out.value))}"
    await ClockCycles(dut.clk, 1)

    dut.ui_in.value = 200
    assert (int(dut.uio_out.value) & 0b100) == 0, f"in256: save should still be 0, got {bin(int(dut.uio_out.value))}"
    await ClockCycles(dut.clk, 1)

    dut.ui_in.value = 200
    assert int(dut.uo_out.value) == 255, f"in257 overflow RLE count: expected 255, got {int(dut.uo_out.value)}"
    assert int(dut.uio_out.value) == 0b100, f"in257 overflow: expected RLE+save (0b100), got {bin(int(dut.uio_out.value))}"
    await ClockCycles(dut.clk, 1)

    dut.ui_in.value = 200
    assert (int(dut.uio_out.value) & 0b100) == 0, f"in258 post-overflow: save should be 0, got {bin(int(dut.uio_out.value))}"
    await ClockCycles(dut.clk, 1)