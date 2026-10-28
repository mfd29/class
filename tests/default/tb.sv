`timescale 1ns/1ps
module tb;
localparam INPUT_SIZE=480, OUTPUT_SIZE=256, CASES=6;
reg clk=0; always #5 clk=~clk;
reg rst_n=0,start=0,wr_en=0;
reg [2:0] wr_bank=0,rd_bank=0;
reg [17:0] wr_addr=0,rd_addr=0;
reg signed [7:0] wr_data=0;
wire signed [31:0] rd_data;
wire busy,done; wire [31:0] cycles;
reg [7:0] stim[0:INPUT_SIZE*CASES-1];
reg [31:0] expected[0:OUTPUT_SIZE*CASES-1];
integer c,a,waited,checked=0;
transformer_top #(.N(4),.D(8),.F(16),.LANES(2),.SCALE(181)) dut(.*);
initial begin
 $readmemh("input.hex",stim); $readmemh("expected.hex",expected);
 if($test$plusargs("wave")) begin $dumpfile("wave.vcd"); $dumpvars(1,tb); $dumpvars(1,dut); end
 repeat(3) @(negedge clk); rst_n=1;
 for(c=0;c<CASES;c=c+1) begin
  for(a=0;a<32;a=a+1) begin @(negedge clk); wr_en=1; wr_bank=0; wr_addr=a; wr_data=stim[c*INPUT_SIZE+0+a]; end
for(a=0;a<64;a=a+1) begin @(negedge clk); wr_en=1; wr_bank=1; wr_addr=a; wr_data=stim[c*INPUT_SIZE+32+a]; end
for(a=0;a<64;a=a+1) begin @(negedge clk); wr_en=1; wr_bank=2; wr_addr=a; wr_data=stim[c*INPUT_SIZE+96+a]; end
for(a=0;a<64;a=a+1) begin @(negedge clk); wr_en=1; wr_bank=3; wr_addr=a; wr_data=stim[c*INPUT_SIZE+160+a]; end
for(a=0;a<128;a=a+1) begin @(negedge clk); wr_en=1; wr_bank=4; wr_addr=a; wr_data=stim[c*INPUT_SIZE+224+a]; end
for(a=0;a<128;a=a+1) begin @(negedge clk); wr_en=1; wr_bank=5; wr_addr=a; wr_data=stim[c*INPUT_SIZE+352+a]; end
  @(negedge clk); wr_en=0; start=1;
  @(negedge clk); start=0;
  // Busy-time requests must not restart or corrupt the transaction.
  if(!busy) $fatal(1,"busy did not assert");
  start=1; wr_en=1; wr_bank=0; wr_addr=0; wr_data=99;
  @(negedge clk); start=0; wr_en=0;
  waited=0;
  while(!done && waited<1110) begin @(negedge clk); waited=waited+1; end
  if(!done || busy) $fatal(1,"timeout or invalid done/busy");
  if(cycles!=1080) $fatal(1,"unexpected cycle count %0d",cycles);
  rd_bank=0;
for(a=0;a<32;a=a+1) begin
 rd_addr=a; #1;
 if(rd_data !== expected[c*OUTPUT_SIZE+0+a]) begin
  $display("MISMATCH case=%0d bank=0 addr=%0d got=%0d expected=%0d",c,a,rd_data,$signed(expected[c*OUTPUT_SIZE+0+a])); $fatal(1);
 end
 checked=checked+1;
end
rd_bank=1;
for(a=0;a<32;a=a+1) begin
 rd_addr=a; #1;
 if(rd_data !== expected[c*OUTPUT_SIZE+32+a]) begin
  $display("MISMATCH case=%0d bank=1 addr=%0d got=%0d expected=%0d",c,a,rd_data,$signed(expected[c*OUTPUT_SIZE+32+a])); $fatal(1);
 end
 checked=checked+1;
end
rd_bank=2;
for(a=0;a<32;a=a+1) begin
 rd_addr=a; #1;
 if(rd_data !== expected[c*OUTPUT_SIZE+64+a]) begin
  $display("MISMATCH case=%0d bank=2 addr=%0d got=%0d expected=%0d",c,a,rd_data,$signed(expected[c*OUTPUT_SIZE+64+a])); $fatal(1);
 end
 checked=checked+1;
end
rd_bank=3;
for(a=0;a<32;a=a+1) begin
 rd_addr=a; #1;
 if(rd_data !== expected[c*OUTPUT_SIZE+96+a]) begin
  $display("MISMATCH case=%0d bank=3 addr=%0d got=%0d expected=%0d",c,a,rd_data,$signed(expected[c*OUTPUT_SIZE+96+a])); $fatal(1);
 end
 checked=checked+1;
end
rd_bank=4;
for(a=0;a<16;a=a+1) begin
 rd_addr=a; #1;
 if(rd_data !== expected[c*OUTPUT_SIZE+128+a]) begin
  $display("MISMATCH case=%0d bank=4 addr=%0d got=%0d expected=%0d",c,a,rd_data,$signed(expected[c*OUTPUT_SIZE+128+a])); $fatal(1);
 end
 checked=checked+1;
end
rd_bank=5;
for(a=0;a<16;a=a+1) begin
 rd_addr=a; #1;
 if(rd_data !== expected[c*OUTPUT_SIZE+144+a]) begin
  $display("MISMATCH case=%0d bank=5 addr=%0d got=%0d expected=%0d",c,a,rd_data,$signed(expected[c*OUTPUT_SIZE+144+a])); $fatal(1);
 end
 checked=checked+1;
end
rd_bank=6;
for(a=0;a<32;a=a+1) begin
 rd_addr=a; #1;
 if(rd_data !== expected[c*OUTPUT_SIZE+160+a]) begin
  $display("MISMATCH case=%0d bank=6 addr=%0d got=%0d expected=%0d",c,a,rd_data,$signed(expected[c*OUTPUT_SIZE+160+a])); $fatal(1);
 end
 checked=checked+1;
end
rd_bank=7;
for(a=0;a<64;a=a+1) begin
 rd_addr=a; #1;
 if(rd_data !== expected[c*OUTPUT_SIZE+192+a]) begin
  $display("MISMATCH case=%0d bank=7 addr=%0d got=%0d expected=%0d",c,a,rd_data,$signed(expected[c*OUTPUT_SIZE+192+a])); $fatal(1);
 end
 checked=checked+1;
end
  $display("PASS case=%0d N=4 D=8 F=16 LANES=2 cycles=%0d",c,cycles);
  @(negedge clk); if(done) $fatal(1,"done must be one cycle");
 end
 // Abort mid-computation, then rerun using retained input memories.
 @(negedge clk); start=1;
 @(negedge clk); start=0;
 repeat(2) @(negedge clk); rst_n=0;
 @(negedge clk); if(busy || done || cycles!=0) $fatal(1,"reset failed"); rst_n=1;
 @(negedge clk); start=1;
 @(negedge clk); start=0;
 waited=0;
 while(!done && waited<1110) begin @(negedge clk); waited=waited+1; end
 if(!done) $fatal(1,"reset recovery timeout");
 c=CASES-1;
 rd_bank=0;
for(a=0;a<32;a=a+1) begin
 rd_addr=a; #1;
 if(rd_data !== expected[c*OUTPUT_SIZE+0+a]) begin
  $display("MISMATCH case=%0d bank=0 addr=%0d got=%0d expected=%0d",c,a,rd_data,$signed(expected[c*OUTPUT_SIZE+0+a])); $fatal(1);
 end
 checked=checked+1;
end
rd_bank=1;
for(a=0;a<32;a=a+1) begin
 rd_addr=a; #1;
 if(rd_data !== expected[c*OUTPUT_SIZE+32+a]) begin
  $display("MISMATCH case=%0d bank=1 addr=%0d got=%0d expected=%0d",c,a,rd_data,$signed(expected[c*OUTPUT_SIZE+32+a])); $fatal(1);
 end
 checked=checked+1;
end
rd_bank=2;
for(a=0;a<32;a=a+1) begin
 rd_addr=a; #1;
 if(rd_data !== expected[c*OUTPUT_SIZE+64+a]) begin
  $display("MISMATCH case=%0d bank=2 addr=%0d got=%0d expected=%0d",c,a,rd_data,$signed(expected[c*OUTPUT_SIZE+64+a])); $fatal(1);
 end
 checked=checked+1;
end
rd_bank=3;
for(a=0;a<32;a=a+1) begin
 rd_addr=a; #1;
 if(rd_data !== expected[c*OUTPUT_SIZE+96+a]) begin
  $display("MISMATCH case=%0d bank=3 addr=%0d got=%0d expected=%0d",c,a,rd_data,$signed(expected[c*OUTPUT_SIZE+96+a])); $fatal(1);
 end
 checked=checked+1;
end
rd_bank=4;
for(a=0;a<16;a=a+1) begin
 rd_addr=a; #1;
 if(rd_data !== expected[c*OUTPUT_SIZE+128+a]) begin
  $display("MISMATCH case=%0d bank=4 addr=%0d got=%0d expected=%0d",c,a,rd_data,$signed(expected[c*OUTPUT_SIZE+128+a])); $fatal(1);
 end
 checked=checked+1;
end
rd_bank=5;
for(a=0;a<16;a=a+1) begin
 rd_addr=a; #1;
 if(rd_data !== expected[c*OUTPUT_SIZE+144+a]) begin
  $display("MISMATCH case=%0d bank=5 addr=%0d got=%0d expected=%0d",c,a,rd_data,$signed(expected[c*OUTPUT_SIZE+144+a])); $fatal(1);
 end
 checked=checked+1;
end
rd_bank=6;
for(a=0;a<32;a=a+1) begin
 rd_addr=a; #1;
 if(rd_data !== expected[c*OUTPUT_SIZE+160+a]) begin
  $display("MISMATCH case=%0d bank=6 addr=%0d got=%0d expected=%0d",c,a,rd_data,$signed(expected[c*OUTPUT_SIZE+160+a])); $fatal(1);
 end
 checked=checked+1;
end
rd_bank=7;
for(a=0;a<64;a=a+1) begin
 rd_addr=a; #1;
 if(rd_data !== expected[c*OUTPUT_SIZE+192+a]) begin
  $display("MISMATCH case=%0d bank=7 addr=%0d got=%0d expected=%0d",c,a,rd_data,$signed(expected[c*OUTPUT_SIZE+192+a])); $fatal(1);
 end
 checked=checked+1;
end
 $display("ALL_PASS checked=%0d reset_recovery=PASS",checked);
 $finish;
end
initial begin #149400; $fatal(1,"global timeout"); end
endmodule
