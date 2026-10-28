"""Check all exp LUT addresses and standalone arbitrary-logit softmax rows."""
import json
import math
import os
from pathlib import Path
import numpy as np
from golden import softmax
from run_tests import ROOT, tool, run, hex_file

def main():
    compiler,simulator=tool("iverilog"),tool("vvp")
    if not compiler or not simulator: raise SystemExit("Icarus required")
    env=dict(os.environ)
    suite=Path(compiler).parent.parent
    env["PATH"]=os.pathsep.join([str(suite/"bin"),str(suite/"lib"),env.get("PATH","")])
    records=[]
    for n in (1,3,64):
        work=ROOT/f"build/softmax_n{n}"; work.mkdir(parents=True,exist_ok=True)
        rng=np.random.default_rng(500+n)
        rows=np.vstack([np.full((1,n),-128),np.full((1,n),127),
                        np.linspace(-128,127,n).astype(np.int64)[None,:],
                        rng.integers(-128,128,size=(64,n))])
        probs=softmax(rows)
        hex_file(work/"logits.hex",[rows],8)
        hex_file(work/"prob.hex",[probs],32)
        values=[int(math.floor(math.exp(-d/16)*65536+0.5)) for d in range(256)]
        hex_file(work/"lut.hex",[np.array(values)],32)
        tb=f'''`timescale 1ns/1ps
module tb;
reg clk=0; always #5 clk=~clk;
reg rst_n=0,start=0;
wire [15:0] read_addr,index,prob;
wire valid,done;
reg signed [7:0] rows[0:{rows.size-1}];
reg [31:0] expected[0:{rows.size-1}],lut_ref[0:255];
integer row=0,a,count,timeout;
wire signed [7:0] logit=rows[row*{n}+read_addr];
reg [7:0] delta; wire [16:0] exponential;
exp_lut lut(.delta(delta),.value(exponential));
softmax_unit #(.N({n})) dut(.*);
initial begin
 $readmemh("logits.hex",rows); $readmemh("prob.hex",expected); $readmemh("lut.hex",lut_ref);
 for(a=0;a<256;a=a+1) begin delta=a; #1; if(exponential!==lut_ref[a]) $fatal(1,"LUT mismatch %0d",a); end
 repeat(3) @(negedge clk); rst_n=1;
 for(row=0;row<{len(rows)};row=row+1) begin
  @(negedge clk); start=1;
  @(negedge clk); start=0; count=0; timeout=0;
  while(!done && timeout<{3*n+10}) begin
   @(negedge clk); timeout=timeout+1;
   if(valid) begin
    if(index!==count || prob!==expected[row*{n}+count]) $fatal(1,"softmax row=%0d index=%0d",row,index);
    count=count+1;
   end
  end
  if(!done || count!={n}) $fatal(1,"missing softmax result");
 end
 $display("ALL_PASS softmax_N={n} rows={len(rows)} LUT=256"); $finish;
end
initial begin #10000000; $fatal(1,"timeout"); end
endmodule
'''
        (work/"tb.sv").write_text(tb,encoding="ascii")
        run([compiler,"-g2012","-s","tb","-o","sim.vvp",str(ROOT/"rtl/exp_lut.v"),str(ROOT/"rtl/softmax_unit.v"),"tb.sv"],work,env,work/"compile.log")
        output=run([simulator,"sim.vvp"],work,env,work/"simulation.log")
        if "ALL_PASS" not in output: raise RuntimeError(output)
        records.append({"N":n,"rows":len(rows),"probabilities_checked":int(rows.size),"LUT_addresses_checked":256,"status":"PASS"})
        print(output.strip())
    (ROOT/"build/softmax_summary.json").write_text(json.dumps(records,indent=2))

if __name__=="__main__": main()
