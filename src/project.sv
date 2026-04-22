/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

//ui_in is input 8 bits
//uo_out is data of packets
//uio_in[0] hold high to operate
//uio_out[2:1] holds packet code
//uio_out[3] if high, save data

// List all unused inputs to prevent warnings (NEED TO DO)
//example:wire _unused = &{ena, clk, rst_n, 1'b0};

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
    localparam RLE = 2'b00; //Normal run length encoding.  2 bit packet code, 8 bit length of run
    localparam DELTARLE = 2'b01; //run length encoding of deltas 2 bit packet code, 8 bit length of run
    localparam DELTA = 2'b10; //small delta change. 2 bit packet code, 1 sign bit 2 bits of delta magnitude
    localparam RAW = 2'b11; //Raw data byte. 2 bit packet code, 8 bits data
    
    //in/out assigns
    assign uio_oe[0]= 0; //input, start
    assign uio_oe[1]= 1; //output, packet[0]
    assign uio_oe[2]= 1; //output, packet[1]
    assign uio_oe[3]= 1; //output, save
    assign uio_oe[4]= 0; //input, NOT USED
    assign uio_oe[5]= 0; //input, NOT USED
    assign uio_oe[6]= 0; //input, NOT USED
    assign uio_oe[7]= 0; //input, NOT USED
    
    assign uio_out[0] = 0; //NOT USED
    assign uio_out[7:4] = 0; //NOT USED
        
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
            4'b0110: out_r = {largeDeltanew[DATA_WIDTH], largeDeltanew[2:0],5'b00000}; //delta
            4'b1110: out_r = {largeDeltanew[DATA_WIDTH], largeDeltanew[2:0],5'b00000}; //delta  w/outflag
            4'b0111: out_r = storagenew; //raw
            4'b1111: out_r = storageold; //raw w/outflag
            default: out_r = 0;
        endcase
    end
    
    
    reg [DATA_WIDTH-1:0] storageold; //store full values for delta encoding. old value
    reg [DATA_WIDTH-1:0] storagenew; //store full values for delta encoding. new value
    reg [RLEWIDTH-1:0] RLE_count; //how many values/deltas same in a row
    //reg [RLEWIDTH-1:0] deltaRLE_count; //how many deltas same in a row (DONT NEED, JUST USE RLE_count)
    reg signed [DATA_WIDTH:0] largeDeltaold; //last delta.
    reg signed [DATA_WIDTH:0] largeDeltanew; //current delta, 1 bit larger for sign bit
    reg OUTFLAG; //goes high if the previous output was skipped for rle or deltarle ending
    reg RLEFLAG; //low if RLE, high if DELTARLE
    
    always @ (posedge clk) begin
        if (!rst_n) begin
            storageold <= 0;
            storagenew <= STARTER; //initialize starting value at 0
            RLE_count <= 0; //reset run length counts
            largeDeltaold <= 0;
            largeDeltanew <= 0;
            OUTFLAG <= 0;
            RLEFLAG <= 0;
        end
        
        else begin
             if (uio_in[0]) begin
                 storageold <= storagenew; //move new values to old 
                 storagenew <= ui_in; //read in new values
                 save <= 0;
    
                 if (OUTFLAG) begin
                    packet <= RAW;
                    save <= 1; //save
                 end
                    
                 if (storagenew == storageold) begin //check if same
                     RLE_count <= RLE_count + 1; //RLE mode!
                     OUTFLAG <= 0;
                     RLEFLAG <= 0;
                        
                        if (RLE_count >= ((1 << RLEWIDTH) - 1)) begin //hit max value (avoid overflow)
                            packet <= RLE;
                            RLE_count <= 0;
                            save <= 1;
                        end
                 end
                 else begin //if different
                        //RLE fail
                        if ((RLE_count > 0)&&(RLEFLAG == 0)) begin //if there is an RLE run, end it
                            packet <= RLE;
                            save <= 1;
                            OUTFLAG <= 1;
                            RLE_count <= 0;
                        end
                         
                        largeDeltaold <= largeDeltanew[DATA_WIDTH-1:0]; //update largeDeltaold
                        largeDeltanew <= storagenew - storageold;  //find delta
                            
                        if (largeDeltanew == largeDeltaold) begin //Delta RLE Mode
                            RLE_count <= RLE_count + 1; //increment counter by 1
                            OUTFLAG <= 0;
                            RLEFLAG <= 1;
                               
                            if (RLE_count >= ((1 << RLEWIDTH) - 1)) begin //hit max value (avoid overflow)
                                packet <= DELTARLE;
                                RLE_count <= 0;
                                save <= 1; 
                            end
                        end
                            
                        else begin
                            if (RLE_count > 0) begin //if there is a deltaRLE run, end it
                                packet <= DELTARLE;
                                RLE_count <= 0;
                                OUTFLAG <= 1;
                                save <= 1;
                            end
                            
                            else if ((largeDeltanew < RAWTHRESHOLD)&& (largeDeltanew > -RAWTHRESHOLD) && (!OUTFLAG)) begin // if small delta: DELTA mode!
                                    packet <= DELTA;
                                    save <= 1;
                            end
                            
                            else begin //large delta: RAW mode!
                                 if (OUTFLAG) begin 
                                    //nothing, pass value next cycle
                                 end
                                 else begin
                                    packet <= RAW;
                                    save <= 1;
                                 end
                            end
                        end   
                    end
                end
            end
        end

        
endmodule
