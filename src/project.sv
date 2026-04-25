/*
 * Copyright (c) 2024 advun
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_advun (
    input  wire [7:0] ui_in, // Dedicated inputs (DATA IN!!!)
    output wire [7:0] uo_out, // Dedicated outputs
    input  wire [7:0] uio_in, // IOs: Input path //start = 0
    output wire [7:0] uio_out, // IOs: Output path
    output wire [7:0] uio_oe, // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena, // always 1 when the design is powered, so you can ignore it
    input  wire       clk, // clock
    input  wire       rst_n // reset_n - low to reset
);
    localparam DATA_WIDTH = 8;
    localparam RLEWIDTH = 8; //width of RLE tracker
    localparam DELTA_MIN = -16; //minimum small delta (delta is 4 bits + sign bit -> -16 to 15)
    localparam DELTA_MAX = 15;

    //packet codes
    localparam RLE = 2'b00; //Normal run length encoding.  2 bit packet code, 8 bit length of run
    localparam DELTARLE = 2'b01; //run length encoding of deltas 2 bit packet code, 8 bit length of run
    localparam DELTA = 2'b10; //small delta change. 2 bit packet code, 1 sign bit 4 bit signed delta magnitude
    localparam RAW = 2'b11; //Raw data byte. 2 bit packet code, 8 bits data

    //in/out assigns
    assign uio_oe[0]= 1; //output, packet[0]
    assign uio_oe[1]= 1; //output, packet[1]
    assign uio_oe[2]= 1; //output, save
    assign uio_oe[3]= 0; //input, start
    assign uio_oe[4]= 0; //input, NOT USED
    assign uio_oe[5]= 0; //input, NOT USED
    assign uio_oe[6]= 0; //input, NOT USED
    assign uio_oe[7]= 0; //input, NOT USED

    assign uio_out[7:3] = 0; //NOT USED

    //suppress unused-input warnings
    wire _unused = &{ena, uio_in[7:4], uio_in[2:0], 1'b0};

    //operational registers
    reg [DATA_WIDTH-1:0] storageold; //store full values for delta encoding. previous value
    reg [RLEWIDTH-1:0] RLE_count; //how many values/deltas same in a row
    reg signed [DATA_WIDTH:0] largeDeltaold; //previous delta, 1 bit larger for sign bit
    reg RLEFLAG; //low if RLE, high if DELTARLE
    reg seen_first; //false if first cycle
    reg seen_delta; //false if first or second cycle

    //seen_first prevents a bug where the first data packet might output as a delta or start a RLE/DELTARLE run
    //forces first packet to be raw

    //seen_delta prevents a bug where the second packet could be a deltarle packet, based on the first packets
    //change from the reset value of 0. it forces the first packet to be a delta, raw, or rle

    //output registers
    reg [DATA_WIDTH-1:0] out_data;
    reg [1:0] out_packetcode;
    reg out_save;

    assign uo_out = out_data; //actual data
    assign uio_out[1:0] = out_packetcode; //what type of packet?
    assign uio_out[2]   = out_save; //if true, save data

    //mailbox registers
    reg pending_valid;
    reg [1:0] pending_packetcode;
    reg [DATA_WIDTH-1:0] pending_data;

    wire signed [DATA_WIDTH:0] new_delta = $signed({1'b0, ui_in}) - $signed({1'b0, storageold});

    wire value_match = (ui_in == storageold); //RLE ACTIVE
    wire delta_match = (new_delta == largeDeltaold); //DELTARLE ACTIVE
    wire delta_fits  = (new_delta >= DELTA_MIN) && (new_delta <= DELTA_MAX); //DELTA

    //save ui_in as a delta or raw
    wire [1:0]  sample_packetcode = delta_fits ? DELTA : RAW;
    wire [DATA_WIDTH-1:0] sample_data = delta_fits ? {new_delta[4:0], 3'b000} : ui_in;


    always @ (posedge clk) begin
        if (!rst_n) begin
            storageold <= 0;
            largeDeltaold <= 0;
            RLE_count <= 0;
            RLEFLAG <= 0;
            seen_first <= 0;
            seen_delta <= 0;
            pending_valid <= 0;
            pending_packetcode <= 0;
            pending_data <= 0;
            out_data <= 0;
            out_packetcode <= 0;
            out_save <= 0;
        end

        else if (uio_in[3]) begin //if start is asserted
        //save data
            storageold <= ui_in;
            largeDeltaold  <= new_delta;
            

            if (!seen_first) begin //first round detection, transmit current data as raw
                seen_first <= 1;
                out_packetcode <= RAW;
                out_data   <= ui_in;
                out_save   <= 1;
            end

            else if (!seen_delta && value_match) begin //second round detection, rle run start
                seen_delta <= 1;
                RLE_count <= 1;
                RLEFLAG <= 0;
                out_save <= 0;
            end

            else if (!seen_delta) begin //second round detection, transmit current data as raw or delta
                seen_delta <= 1;
                out_packetcode <= sample_packetcode;
                out_data <= sample_data;
                out_save <= 1;
            end

            //if packet is queued, and current data would be delta or raw
            else if (pending_valid && !value_match  && !delta_match) begin
                out_packetcode <= pending_packetcode;
                out_data <= pending_data;
                out_save <= 1;

                pending_packetcode <= sample_packetcode; //save current packet for next cycle
                pending_data <= sample_data;
                pending_valid <= 1;
            end

            else if (pending_valid && value_match) begin //if an rle run is starting while pending
                out_packetcode <= pending_packetcode;
                out_data <= pending_data;
                out_save <= 1;
                pending_valid <= 0; //no need to output next cycle
                RLE_count <= 1;
                RLEFLAG <= 0;
            end

            else if (pending_valid && delta_match) begin //if a deltarle run is starting while pending
                out_packetcode <= pending_packetcode;
                out_data <= pending_data;
                out_save <= 1;
                pending_valid <= 0; //no need to output next cycle
                RLE_count <= 1;
                RLEFLAG <= 1;
            end

            //RLE mode: same value as last cycle
            else if (value_match) begin
                RLEFLAG <= 0;
                if (RLE_count == {RLEWIDTH{1'b1}}) begin //hit max value (avoid overflow)
                    out_packetcode <= RLE;
                    out_data <= RLE_count;
                    out_save <= 1;
                    RLE_count <= 0;
                end
                else begin
                    RLE_count <= RLE_count + 1;
                    out_save <= 0; // don't save anything this cycle
                end
            end

            //DeltaRLE mode: same delta as last cycle
            else if (delta_match) begin
                RLEFLAG <= 1;
                if (RLE_count == {RLEWIDTH{1'b1}}) begin //hit max value (avoid overflow)
                    out_packetcode <= DELTARLE;
                    out_data <= RLE_count;
                    out_save <= 1;
                    RLE_count <= 0;
                end
                else begin
                    RLE_count <= RLE_count + 1;
                    out_save   <= 0; // don't save anything this cycle
                end
            end

            //RLE run breaks: close run and output, queue current data as raw or delta
            else if ((RLE_count > 0) && (RLEFLAG == 0)) begin
                //output RLE length
                out_packetcode <= RLE;
                out_data <= RLE_count;
                out_save <= 1;
                RLE_count <= 0;
                //save data that would have been output for next cycle
                pending_valid <= 1;
                pending_packetcode <= sample_packetcode;
                pending_data <= sample_data;
            end

            //DeltaRLE run breaks: close run and output, queue current data as raw or delta
            else if ((RLE_count > 0) && (RLEFLAG == 1)) begin
                //output DELTARLE length
                out_packetcode <= DELTARLE;
                out_data <= RLE_count;
                out_save <= 1;
                RLE_count <= 0;
                RLEFLAG <= 0;
                //save data that would have been output for next cycle
                pending_valid <= 1;
                pending_packetcode <= sample_packetcode;
                pending_data <= sample_data;
            end


            //no run active: output data as DELTA or RAW
            else begin
                out_packetcode <= sample_packetcode;
                out_data   <= sample_data;
                out_save   <= 1;
            end

        end
    end

endmodule
