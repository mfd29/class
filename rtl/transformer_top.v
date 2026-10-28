module transformer_top #(
    parameter N=4, D=8, F=16, LANES=2,
    parameter PROJ_SHIFT=4, SCORE_SHIFT=4, FF_SHIFT=4,
    parameter SCALE=181, SCALE_SHIFT=9
)(
    input clk, rst_n, start,
    input wr_en,
    input [2:0] wr_bank,
    input [17:0] wr_addr,
    input signed [7:0] wr_data,
    input [2:0] rd_bank,
    input [17:0] rd_addr,
    output reg signed [31:0] rd_data,
    output busy,
    output reg done,
    output reg [31:0] cycles
);
    // Register-backed baseline; no SRAM macro is inferred or claimed.
    reg signed [7:0] x[0:N*D-1], wq[0:D*D-1], wk[0:D*D-1], wv[0:D*D-1];
    reg signed [7:0] w1[0:D*F-1], w2[0:F*D-1];
    reg signed [7:0] q[0:N*D-1], key[0:N*D-1], v[0:N*D-1];
    reg signed [7:0] score[0:N*N-1], context_mem[0:N*D-1];
    reg [15:0] probability[0:N*N-1];
    reg signed [7:0] hidden[0:N*F-1], result[0:N*D-1];
    localparam IDLE=0, MAC=1, SM_START=2, SM_WAIT=3;
    reg [2:0] state;
    reg [2:0] phase;
    integer row, col, pos;
    integer inner_dim, columns, lane, idx;
    reg [LANES*18-1:0] pe_a, pe_b;
    reg signed [17:0] aa, bb;
    reg signed [63:0] accumulator;
    wire signed [63:0] partial_sum;
    wire signed [63:0] total=accumulator+partial_sum;
    wire signed [63:0] scaled=total*SCALE;
    wire [15:0] sm_read, sm_index, sm_value;
    wire sm_valid, sm_done;
    wire signed [7:0] sm_logit=score[row*N+sm_read];
    assign busy=(state!=IDLE);

    function [7:0] sat8;
        input signed [63:0] value;
        begin
            if(value>127) sat8=8'h7f;
            else if(value< -128) sat8=8'h80;
            else sat8=value[7:0];
        end
    endfunction

    pe_array #(.LANES(LANES)) pe(.a(pe_a),.b(pe_b),.sum(partial_sum));
    softmax_unit #(.N(N)) sm(
        .clk(clk),.rst_n(rst_n),.start(state==SM_START),
        .read_addr(sm_read),.logit(sm_logit),
        .valid(sm_valid),.index(sm_index),.prob(sm_value),.done(sm_done)
    );

    always @* begin
        inner_dim=D; columns=D;
        if(phase==3) columns=N;
        if(phase==4) inner_dim=N;
        if(phase==5) columns=F;
        if(phase==6) inner_dim=F;
        pe_a=0; pe_b=0; aa=0; bb=0; idx=0;
        for(lane=0;lane<LANES;lane=lane+1) begin
            idx=pos+lane;
            aa=0; bb=0;
            if(state==MAC && idx<inner_dim) begin
                case(phase)
                    0: begin aa=x[row*D+idx]; bb=wq[idx*D+col]; end
                    1: begin aa=x[row*D+idx]; bb=wk[idx*D+col]; end
                    2: begin aa=x[row*D+idx]; bb=wv[idx*D+col]; end
                    3: begin aa=q[row*D+idx]; bb=key[col*D+idx]; end
                    4: begin aa=$signed({2'b00,probability[row*N+idx]}); bb=v[idx*D+col]; end
                    5: begin aa=context_mem[row*D+idx]; bb=w1[idx*F+col]; end
                    6: begin aa=hidden[row*F+idx]; bb=w2[idx*D+col]; end
                    default: begin aa=0; bb=0; end
                endcase
            end
            pe_a[lane*18 +: 18]=aa;
            pe_b[lane*18 +: 18]=bb;
        end
    end

    always @* begin
        rd_data=0;
        case(rd_bank)
            0: if(rd_addr<N*D) rd_data=result[rd_addr];
            1: if(rd_addr<N*D) rd_data=q[rd_addr];
            2: if(rd_addr<N*D) rd_data=key[rd_addr];
            3: if(rd_addr<N*D) rd_data=v[rd_addr];
            4: if(rd_addr<N*N) rd_data=score[rd_addr];
            5: if(rd_addr<N*N) rd_data={16'b0,probability[rd_addr]};
            6: if(rd_addr<N*D) rd_data=context_mem[rd_addr];
            7: if(rd_addr<N*F) rd_data=hidden[rd_addr];
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=IDLE; phase<=0; row<=0; col<=0; pos<=0;
            accumulator<=0; done<=0; cycles<=0;
        end else begin
            done<=0;
            if(wr_en && state==IDLE && !start) begin
                case(wr_bank)
                    0: if(wr_addr<N*D) x[wr_addr]<=wr_data;
                    1: if(wr_addr<D*D) wq[wr_addr]<=wr_data;
                    2: if(wr_addr<D*D) wk[wr_addr]<=wr_data;
                    3: if(wr_addr<D*D) wv[wr_addr]<=wr_data;
                    4: if(wr_addr<D*F) w1[wr_addr]<=wr_data;
                    5: if(wr_addr<F*D) w2[wr_addr]<=wr_data;
                    default: ;
                endcase
            end
            if(state!=IDLE) cycles<=cycles+1;
            case(state)
                IDLE: if(start && !wr_en) begin
                    state<=MAC; phase<=0; row<=0; col<=0; pos<=0;
                    accumulator<=0; cycles<=0;
                end
                MAC: begin
                    if(pos+LANES>=inner_dim) begin
                        case(phase)
                            0: q[row*D+col]<=sat8(total >>> PROJ_SHIFT);
                            1: key[row*D+col]<=sat8(total >>> PROJ_SHIFT);
                            2: v[row*D+col]<=sat8(total >>> PROJ_SHIFT);
                            3: score[row*N+col]<=sat8(scaled >>> (SCALE_SHIFT+SCORE_SHIFT));
                            4: context_mem[row*D+col]<=sat8(total >>> 15);
                            5: if(total<0) hidden[row*F+col]<=0;
                               else hidden[row*F+col]<=sat8(total >>> FF_SHIFT);
                            6: result[row*D+col]<=sat8(total >>> FF_SHIFT);
                            default: ;
                        endcase
                        accumulator<=0; pos<=0;
                        if(col+1<columns) col<=col+1;
                        else begin
                            col<=0;
                            if(row+1<N) row<=row+1;
                            else begin
                                row<=0;
                                if(phase==3) state<=SM_START;
                                else if(phase==6) begin state<=IDLE; done<=1; end
                                else phase<=phase+1;
                            end
                        end
                    end else begin accumulator<=total; pos<=pos+LANES; end
                end
                SM_START: state<=SM_WAIT;
                SM_WAIT: begin
                    if(sm_valid) probability[row*N+sm_index]<=sm_value;
                    if(sm_done) begin
                        if(row+1<N) begin row<=row+1; state<=SM_START; end
                        else begin row<=0; phase<=4; state<=MAC; end
                    end
                end
                default: state<=IDLE;
            endcase
        end
    end
endmodule
