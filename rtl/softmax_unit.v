// 功能块：逐行稳定Softmax，三遍扫描：找最大值 -> 指数求和 -> 除法归一化。
// 输入真实值=logit/16；输出真实概率=prob/32768，原码32768表示1。
module softmax_unit #(parameter N=4)(
    // clk：上升沿工作；rst_n：异步低有效复位；start：仅空闲时接受单拍启动。
    input clk, rst_n, start,
    // 输出请求本行元素的下标；外部必须组合读并提供对应logit。
    output [15:0] read_addr,
    input signed [7:0] logit,
    // valid为1时，index/prob为有效输出；最后一项valid与done同时为1。
    output reg valid,
    output reg [15:0] index, prob,
    output reg done
);
    // 状态0=空闲，1=最大值扫描，2=指数和扫描，3=概率输出扫描。
    reg [2:0] state;
    reg [15:0] ptr;
    reg signed [8:0] maximum;
    wire signed [8:0] extended={{1{logit[7]}},logit}; // 保持符号，避免差值溢出。
    wire [8:0] difference=maximum-extended;
    wire [16:0] exponential;
    reg [31:0] denominator; // N<=64时上限64*65536，32位可容纳。
    wire [47:0] numerator={31'b0,exponential} << 15;
    assign read_addr=ptr;
    // 最大值找完后difference处于0..255；指数查表对应exp(-difference/16)。
    exp_lut lut(.delta(difference[7:0]),.value(exponential));
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=0; ptr<=0; maximum<=-128; denominator<=0;
            valid<=0; index<=0; prob<=0; done<=0;
        end else begin
            valid<=0; done<=0; // 默认清脉冲，仅输出状态覆盖为1。
            case(state)
                0: if(start) begin ptr<=0; maximum<=-128; denominator<=0; state<=1; end
                1: begin // 第一遍：N拍找最大值，避免对正数求大指数。
                    if(extended>maximum) maximum<=extended;
                    if(ptr==N-1) begin ptr<=0; state<=2; end
                    else ptr<=ptr+1;
                end
                2: begin // 第二遍：N拍累加Q16指数；最大项65536保证分母非零。
                    denominator<=denominator+exponential;
                    if(ptr==N-1) begin ptr<=0; state<=3; end
                    else ptr<=ptr+1;
                end
                3: begin // 第三遍：每拍输出一个概率，整除向下取整。
                    // 当前为组合除法+输出寄存；并非已经实现多拍低面积除法器。
                    valid<=1; index<=ptr; prob<=numerator/denominator;
                    if(ptr==N-1) begin ptr<=0; state<=0; done<=1; end
                    else ptr<=ptr+1;
                end
                default: state<=0;
            endcase
        end
    end
endmodule
