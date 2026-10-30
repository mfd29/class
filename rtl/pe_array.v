// 功能块：LANES 路有符号乘法与组合求和；跨拍累加由顶层 accumulator 完成。
// 本模块无时钟、无内部流水寄存器，for 循环描述并行硬件，不表示多拍执行。
module pe_array #(parameter LANES=2)(
    // 每路18位，低18位为lane0；INT8符号扩展，概率则补零后输入。
    input [LANES*18-1:0] a, b,
    // 本组乘积之和，符号扩展到64位，送顶层累加器。
    output reg signed [63:0] sum
);
    integer lane;
    reg signed [17:0] av, bv;
    reg signed [35:0] product;
    always @* begin
        // 组合块先给全路径默认值，避免保留旧值而推断锁存器。
        sum=0; av=0; bv=0; product=0;
        for(lane=0;lane<LANES;lane=lane+1) begin
            av=$signed(a[lane*18 +: 18]); // 从lane*18起取18位，并按补码解释。
            bv=$signed(b[lane*18 +: 18]);
            product=av*bv;
            sum=sum+{{28{product[35]}},product}; // 复制符号位：36位扩为64位。
        end
    end
endmodule
