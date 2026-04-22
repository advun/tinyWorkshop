/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_advun (
    input  wire [7:0] ui_in,    // Dedicated inputs (DATA IN!!!)
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path //start = 0
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);
    localparam DATA_WIDTH = 8;
    localparam STARTER = 0; //starter compare value for delta
    localparam RLEWIDTH = 8;  //width of RLE tracker
    localparam RAWTHRESHOLD = 8; //how big does delta have to be to go to raw? both pos and neg
    
    //packet codes
    localparam RLE = 2'b00; //Normal run length encoding 
    localparam DELTARLE = 2'b01; //run length encoding of deltas
    localparam DELTA = 2'b10; //small delta change
    localparam RAW = 2'b11; //Raw data bytes
    
    //in/out assigns
    assign uio_oe[0]= 0; //input 
    assign uio_oe[1]= 1; //output
    assign uio_oe[2]= 1; //output
    assign uio_oe[3]= 1; //output
    
    wire [7:0] in;
    assign ui_in = in;
    
    wire start = uio_in[0];
    
    reg [1:0] packet;
    assign uio_out [2:1] = packet;
    
    reg save;
    assign uio_out[3] = save;
    
    logic[7:0] out_r;
    assign uo_out = out_r;
    always_comb begin
        case({OUTFLAG, save, packet})
            4'b0100: out_r = RLE_count; //RLE Output
            4'b1100: out_r = RLE_count; //RLE Output w/outflag
            4'b0101: out_r = RLE_count; //DeltaRLE Output
            4'b1101: out_r = RLE_count; //DeltaRLE Output w/outflag
            4'b0110: out_r = {largeDeltanew[2:0],5'b00000}; //delta
            4'b1110: out_r = {largeDeltanew[2:0],5'b00000}; //delta  w/outflag
            4'b0111: out_r = storagenew; //raw
            4'b1111: out_r = storageold; //raw w/outflag
            default: out_r = 0;
        endcase
    end
    
    
    reg [DATA_WIDTH-1:0] storageold; //store full values for delta encoding. old value
    reg [DATA_WIDTH-1:0] storagenew; //store full values for delta encoding. new value
    reg [RLEWIDTH-1:0] RLE_count; //how many values/deltas same in a row
    //reg [RLEWIDTH-1:0] deltaRLE_count; //how many deltas same in a row (DONT NEED, JUST USE RLE_count)
    reg [DATA_WIDTH-1:0] largeDeltaold; //last delta.  just change out for third storage??
    reg signed [DATA_WIDTH:0] largeDeltanew; //current delta, 1 bit larger for sign bit
    reg OUTFLAG; //goes high if the previous output was skipped for rle or deltarle ending
    reg RLEFLAG; //low if RLE, high if DELTARLE
    
    always @ (posedge clk) begin
        if (!rst_n) begin
            storageold <= 0;
            storagenew <= STARTER; //initialize starting value at 0
            RLE_count <= 0; //reset run length counts
            //deltaRLE_count <= 0;
            largeDeltaold <= 0;
            largeDeltanew <= 0;
            OUTFLAG <= 0;
        end
        
        else begin
             if (start) begin
                 storageold <= storagenew; //move new values to old 
                 storagenew <= ui_in; //read in new values
    
                 if (OUTFLAG) begin
                    packet <= RAW;
                 end
                    
                    if (storagenew == storageold) begin //check if same
                        RLE_count <= RLE_count + 1; //RLE mode!
                        OUTFLAG <= 0;
                        RLEFLAG <= 0;
                        
                        if (RLE_count >= ((1 << RLEWIDTH) - 1)) begin //hit max value (avoid overflow)
                            packet <= RLE;
                            RLE_count <= 0;
                        end
                    else begin //if different
                        //RLE fail
                        if ((RLE_count > 0)&&(RLEFLAG == 0)) begin //if there is an RLE run, end it
                            packet <= RLE;
                            OUTFLAG <= 1;
                            RLE_count <= 0;
                        end
                         
                        largeDeltaold <= largeDeltanew[DATA_WIDTH-1:0]; //update largeDeltaold
                        largeDeltanew <= storagenew - storageold;  //find delta
                            
                        if (largeDeltanew[DATA_WIDTH-1:0] == largeDeltaold) begin //Delta RLE Mode
                            RLE_count <= RLE_count + 1; //increment counter by 1
                            OUTFLAG <= 0;
                            RLEFLAG <= 1;
                               
                            if (RLE_count >= ((1 << RLEWIDTH) - 1)) begin //hit max value (avoid overflow)
                                packet <= DELTARLE;
                                RLE_count <= 0;
                            end
                        end
                            
                        else begin
                            if (RLE_count > 0) begin //if there is a deltaRLE run, end it
                                packet <= DELTARLE;
                                RLE_count <= 0;
                                OUTFLAG <= 1;
                            end
                            
                            else if ((largeDeltanew < RAWTHRESHOLD)&& (!OUTFLAG)) begin // if small delta: DELTA mode!
                                    packet <= DELTA;
                            end
                            
                            else begin //large delta: RAW mode!
                                 if (OUTFLAG) begin 
                                    //nothing, pass value next cycle
                                 end
                                 else begin
                                    packet <= RAW;
                                 end
                            end
                        end   
                    end
                end
            end
        end
    end

        
endmodule
