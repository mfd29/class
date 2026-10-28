// Parallel signed products, reduced into a shared wide accumulator input.
module pe_array #(parameter LANES=2)(
    input [LANES*18-1:0] a, b,
    output reg signed [63:0] sum
);
    integer lane;
    reg signed [17:0] av, bv;
    reg signed [35:0] product;
    always @* begin
        sum=0; av=0; bv=0; product=0;
        for(lane=0;lane<LANES;lane=lane+1) begin
            av=$signed(a[lane*18 +: 18]);
            bv=$signed(b[lane*18 +: 18]);
            product=av*bv;
            sum=sum+{{28{product[35]}},product};
        end
    end
endmodule
