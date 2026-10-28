"""Compile real RTL, generate file-backed vectors, check every intermediate bank."""
from pathlib import Path
import argparse
import json
import math
import os
import shutil
import signal
import subprocess
import time
import numpy as np
from golden import make_inputs, evaluate, self_test

ROOT = Path(__file__).resolve().parents[1]
SOURCES = [ROOT / "rtl" / s for s in ("pe_array.v","exp_lut.v","softmax_unit.v","transformer_top.v")]

def tool(name):
    root = Path(os.environ.get("EDA_OSS_CAD_SUITE",r"D:\eda-tools\oss-cad-suite"))
    executable = root / "bin" / (name + (".exe" if os.name=="nt" else ""))
    return str(executable) if executable.exists() else shutil.which(name)

def run(command, cwd, env, log):
    process = subprocess.Popen(command,cwd=cwd,env=env,stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE,text=True,start_new_session=(os.name!="nt"))
    try:
        stdout,stderr = process.communicate(timeout=240)
    except subprocess.TimeoutExpired as exc:
        # Compiler drivers can leave child processes holding the log pipes open.
        if os.name=="nt":
            subprocess.run(["taskkill","/PID",str(process.pid),"/T","/F"],capture_output=True)
        else:
            os.killpg(process.pid,signal.SIGKILL)
        stdout,stderr = process.communicate()
        log.write_text(stdout+stderr+str(exc),encoding="utf-8")
        raise RuntimeError(f"Timeout: {log}") from exc
    log.write_text(stdout+stderr,encoding="utf-8")
    if process.returncode:
        raise RuntimeError(f"Command failed ({process.returncode}): {log}\n{stdout[-1600:]}\n{stderr[-1600:]}")
    return stdout

def hex_file(path, arrays, bits):
    mask = (1 << bits)-1
    path.write_text("".join(f"{int(x)&mask:0{bits//4}x}\n" for a in arrays for x in a.flat),encoding="ascii")

def testbench(n,d,f,lanes,cases):
    sizes = [n*d,d*d,d*d,d*d,d*f,f*d]
    checks = []
    input_offset=0
    for bank,size in enumerate(sizes):
        checks.append(f"for(a=0;a<{size};a=a+1) begin @(negedge clk); wr_en=1; wr_bank={bank}; wr_addr=a; wr_data=stim[c*INPUT_SIZE+{input_offset}+a]; end")
        input_offset += size
    banks=[n*d,n*d,n*d,n*d,n*n,n*n,n*d,n*f]
    expected_offset=0
    compare=[]
    for bank,size in enumerate(banks):
        compare.append(f'''rd_bank={bank};
for(a=0;a<{size};a=a+1) begin
 rd_addr=a; #1;
 if(rd_data !== expected[c*OUTPUT_SIZE+{expected_offset}+a]) begin
  $display("MISMATCH case=%0d bank={bank} addr=%0d got=%0d expected=%0d",c,a,rd_data,$signed(expected[c*OUTPUT_SIZE+{expected_offset}+a])); $fatal(1);
 end
 checked=checked+1;
end''')
        expected_offset+=size
    macs=3*n*d*math.ceil(d/lanes)+n*n*math.ceil(d/lanes)+n*d*math.ceil(n/lanes)+n*f*math.ceil(d/lanes)+n*d*math.ceil(f/lanes)
    expected_cycles=macs+n*(3*n+2)
    return f'''`timescale 1ns/1ps
module tb;
localparam INPUT_SIZE={input_offset}, OUTPUT_SIZE={expected_offset}, CASES={len(cases)};
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
transformer_top #(.N({n}),.D({d}),.F({f}),.LANES({lanes}),.SCALE({int(512/math.sqrt(d)+0.5)})) dut(.*);
initial begin
 $readmemh("input.hex",stim); $readmemh("expected.hex",expected);
 if($test$plusargs("wave")) begin $dumpfile("wave.vcd"); $dumpvars(1,tb); $dumpvars(1,dut); end
 repeat(3) @(negedge clk); rst_n=1;
 for(c=0;c<CASES;c=c+1) begin
  {chr(10).join(checks)}
  @(negedge clk); wr_en=0; start=1;
  @(negedge clk); start=0;
  // Busy-time requests must not restart or corrupt the transaction.
  if(!busy) $fatal(1,"busy did not assert");
  start=1; wr_en=1; wr_bank=0; wr_addr=0; wr_data=99;
  @(negedge clk); start=0; wr_en=0;
  waited=0;
  while(!done && waited<{expected_cycles+30}) begin @(negedge clk); waited=waited+1; end
  if(!done || busy) $fatal(1,"timeout or invalid done/busy");
  if(cycles!={expected_cycles}) $fatal(1,"unexpected cycle count %0d",cycles);
  {chr(10).join(compare)}
  $display("PASS case=%0d N={n} D={d} F={f} LANES={lanes} cycles=%0d",c,cycles);
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
 while(!done && waited<{expected_cycles+30}) begin @(negedge clk); waited=waited+1; end
 if(!done) $fatal(1,"reset recovery timeout");
 c=CASES-1;
 {chr(10).join(compare)}
 $display("ALL_PASS checked=%0d reset_recovery=PASS",checked);
 $finish;
end
initial begin #{(expected_cycles+input_offset+100)*10*(len(cases)+3)}; $fatal(1,"global timeout"); end
endmodule
'''

def main():
    parser=argparse.ArgumentParser()
    parser.add_argument("--full",action="store_true",help="include D=256 and N=64 D=256 boundaries (slow with Icarus)")
    parser.add_argument("--generate-only",action="store_true",help="generate portable vectors/Testbenches without a local simulator")
    args=parser.parse_args()
    iverilog,vvp=tool("iverilog"),tool("vvp")
    if not args.generate_only and (not iverilog or not vvp):
        raise SystemExit("Install Icarus or set EDA_OSS_CAD_SUITE; no tests were run.")
    env=dict(os.environ)
    if iverilog:
        suite=Path(iverilog).parent.parent
        env["PATH"]=os.pathsep.join([str(suite/"bin"),str(suite/"lib"),env.get("PATH","")])
    build=ROOT/"build"; build.mkdir(exist_ok=True)
    summary={"golden_self_test":self_test(),"rtl_configurations":[],"status":"RUNNING"}
    summary_path=build/("vector_manifest.json" if args.generate_only else "test_summary.json")
    summary_path.write_text(json.dumps(summary,indent=2))
    configs=[(1,1,1,2),(3,5,7,2),(4,8,16,2),(4,8,16,1),(8,16,32,4),(64,8,16,2)]
    if args.full: configs.extend([(1,256,256,4),(64,256,256,4)])
    started=time.time()
    for n,d,f,lanes in configs:
        work=build/f"n{n}_d{d}_f{f}_p{lanes}"; work.mkdir(exist_ok=True)
        kinds=["zero","identity","extreme","random","random","random"]
        if d>=256: kinds=["random"]
        cases=[make_inputs(n,d,f,kind,100+i) for i,kind in enumerate(kinds)]
        outputs=[evaluate(case,d) for case in cases]
        hex_file(work/"input.hex",[a for case in cases for a in case],8)
        hex_file(work/"expected.hex",[a for case in outputs for a in case],32)
        (work/"tb.sv").write_text(testbench(n,d,f,lanes,cases),encoding="ascii")
        if args.generate_only:
            summary["rtl_configurations"].append({"N":n,"D":d,"F":f,"LANES":lanes,"cases":len(cases),"status":"GENERATED_NOT_SIMULATED"})
            continue
        run([iverilog,"-g2012","-Wall","-s","tb","-o","sim.vvp",*[str(s) for s in SOURCES],"tb.sv"],work,env,work/"compile.log")
        log=run([vvp,"sim.vvp",*(["+wave"] if (n,d,lanes)==(4,8,2) else [])],work,env,work/"simulation.log")
        if "ALL_PASS" not in log: raise RuntimeError(f"Missing completion: {work}")
        record={"N":n,"D":d,"F":f,"LANES":lanes,"cases":len(cases),"result":log.splitlines()[-2:]}
        summary["rtl_configurations"].append(record)
        print(json.dumps(record),flush=True)
        summary_path.write_text(json.dumps(summary,indent=2))
    summary.update(status="GENERATED_NOT_SIMULATED" if args.generate_only else "PASS",elapsed_seconds=round(time.time()-started,2))
    summary_path.write_text(json.dumps(summary,indent=2))
    print("Vectors generated (no simulation)." if args.generate_only else "PASS: all RTL stage banks matched NumPy, including reset recovery.")

if __name__=="__main__":
    try:
        main()
    except Exception as exc:
        path=ROOT/"build/test_summary.json"
        if path.exists():
            record=json.loads(path.read_text())
            record.update(status="FAIL",error=str(exc))
            path.write_text(json.dumps(record,indent=2))
        raise
