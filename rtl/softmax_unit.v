// Three-pass stable softmax. Logits: signed Q4.4; probabilities: unsigned Q0.15.
module softmax_unit #(parameter N=4)(
    input clk, rst_n, start,
    output [15:0] read_addr,
    input signed [7:0] logit,
    output reg valid,
    output reg [15:0] index, prob,
    output reg done
);
    reg [2:0] state;
    reg [15:0] ptr;
    reg signed [8:0] maximum;
    wire signed [8:0] extended={{1{logit[7]}},logit};
    wire [8:0] difference=maximum-extended;
    wire [16:0] exponential;
    reg [31:0] denominator;
    wire [47:0] numerator={31'b0,exponential} << 15;
    assign read_addr=ptr;
    exp_lut lut(.delta(difference[7:0]),.value(exponential));
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=0; ptr<=0; maximum<=-128; denominator<=0;
            valid<=0; index<=0; prob<=0; done<=0;
        end else begin
            valid<=0; done<=0;
            case(state)
                0: if(start) begin ptr<=0; maximum<=-128; denominator<=0; state<=1; end
                1: begin
                    if(extended>maximum) maximum<=extended;
                    if(ptr==N-1) begin ptr<=0; state<=2; end
                    else ptr<=ptr+1;
                end
                2: begin
                    denominator<=denominator+exponential;
                    if(ptr==N-1) begin ptr<=0; state<=3; end
                    else ptr<=ptr+1;
                end
                3: begin
                    valid<=1; index<=ptr; prob<=numerator/denominator;
                    if(ptr==N-1) begin ptr<=0; state<=0; done<=1; end
                    else ptr<=ptr+1;
                end
                default: state<=0;
            endcase
        end
    end
endmodule
