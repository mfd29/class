// INT8单头注意力+ReLU前馈网络；同一套PE按phase复用，矩阵均按行主序存放。
// 使用前完整加载输入/权重；计算期间禁止主机写入，done后再读最终结果。
module transformer_top #(
    // 静态尺寸：N序列长，D隐藏维度，F前馈中间维度，LANES并行乘法路数。
    parameter N=4, D=8, F=16, LANES=2,
    // 默认raw/16定点数；乘法后算术右移4位，再饱和成INT8。
    parameter PROJ_SHIFT=4, SCORE_SHIFT=4, FF_SHIFT=4,
    parameter SCALE=181, SCALE_SHIFT=9 // round(512/sqrt(D))；改变D需同步改SCALE。
)(
    // 上升沿计算，异步低有效复位；外部应同步释放复位。start只拉高一拍。
    input clk, rst_n, start,
    // 写接口：空闲且start=0才接受；每拍写一个8位元素，无额外ready响应。
    input wr_en,
    input [2:0] wr_bank, // 0=X，1=Wq，2=Wk，3=Wv，4=W1，5=W2。
    input [17:0] wr_addr, // bank内元素下标，不是字节总线地址。
    input signed [7:0] wr_data,
    // 组合读接口：0=Y，1=Q，2=K，3=V，4=score，5=P，6=Context，7=Hidden。
    input [2:0] rd_bank,
    input [17:0] rd_addr,
    output reg signed [31:0] rd_data, // 有符号元素符号扩展；概率补零；越界返回0。
    output busy, // 非IDLE为1，忙时忽略start和主机写请求。
    output reg done, // 完成时单拍为1，同时busy回0；不是持续有效标志。
    output reg [31:0] cycles // 只计计算拍数，不含主机加载/读回。
);
    // 功能块①：输入、权重及中间存储。寄存器阵列基线，没有实例化SRAM/BRAM。
    // 二维坐标(r,c)对应数组地址r*列数+c；所有INT8矩阵按raw/16解释。
    reg signed [7:0] x[0:N*D-1], wq[0:D*D-1], wk[0:D*D-1], wv[0:D*D-1];
    reg signed [7:0] w1[0:D*F-1], w2[0:F*D-1];
    reg signed [7:0] q[0:N*D-1], key[0:N*D-1], v[0:N*D-1];
    reg signed [7:0] score[0:N*N-1], context_mem[0:N*D-1];
    reg [15:0] probability[0:N*N-1]; // 无符号Q0.15，32768表示概率1。
    reg signed [7:0] hidden[0:N*F-1], result[0:N*D-1];
    // 功能块②：控制器。IDLE加载/等待；MAC共享点积；SM_START启动行Softmax；SM_WAIT接收结果。
    localparam IDLE=0, MAC=1, SM_START=2, SM_WAIT=3;
    reg [2:0] state;
    reg [2:0] phase; // 0=Q，1=K，2=V，3=score，4=Context，5=FF1，6=FF2。
    integer row, col, pos; // row/col指向输出元素；pos是点积归约维度的起始项。
    integer inner_dim, columns, lane, idx;
    reg [LANES*18-1:0] pe_a, pe_b;
    reg signed [17:0] aa, bb;
    reg signed [63:0] accumulator;
    wire signed [63:0] partial_sum;
    wire signed [63:0] total=accumulator+partial_sum; // 包含本拍PE结果，防止漏最后一组。
    wire signed [63:0] scaled=total*SCALE;
    wire [15:0] sm_read, sm_index, sm_value;
    wire sm_valid, sm_done;
    wire signed [7:0] sm_logit=score[row*N+sm_read];
    assign busy=(state!=IDLE);

    // 功能块③：输出量化。超过INT8范围钳位，避免直接截位导致正负翻转。
    function [7:0] sat8;
        input signed [63:0] value;
        begin
            if(value>127) sat8=8'h7f;
            else if(value< -128) sat8=8'h80;
            else sat8=value[7:0];
        end
    endfunction

    // 功能块④：唯一一套共享PE，默认两路18x18乘法；不是七套独立矩阵乘硬件。
    pe_array #(.LANES(LANES)) pe(.a(pe_a),.b(pe_b),.sum(partial_sum));
    // 功能块⑤：专用逐行Softmax；顶层组合读score，子模块回传valid/index/prob。
    softmax_unit #(.N(N)) sm(
        .clk(clk),.rst_n(rst_n),.start(state==SM_START),
        .read_addr(sm_read),.logit(sm_logit),
        .valid(sm_valid),.index(sm_index),.prob(sm_value),.done(sm_done)
    );

    // 功能块⑥：按phase选择操作数。尾部不满LANES的路填0，组合默认赋值防锁存。
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
                    3: begin aa=q[row*D+idx]; bb=key[col*D+idx]; end // 按K的一行读取，实现K转置访问。
                    // P必须先补零再按signed18位处理，否则0x8000会被误当负数。
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

    // 功能块⑦：主机读多路选择；done之前中间结果可能未写完，不保证最终有效。
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
        if(!rst_n) begin // 仅复位控制和累加器，不清矩阵；初次运行前必须完整加载。
            state<=IDLE; phase<=0; row<=0; col<=0; pos<=0;
            accumulator<=0; done<=0; cycles<=0;
        end else begin
            done<=0;
            // start与wr_en同拍为1时两者均不接受；非法bank/地址忽略。
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
                IDLE: if(start && !wr_en) begin // 新事务从Q投影开始，周期数清零。
                    state<=MAC; phase<=0; row<=0; col<=0; pos<=0;
                    accumulator<=0; cycles<=0;
                end
                MAC: begin
                    if(pos+LANES>=inner_dim) begin // 当前输出元素的最后一组乘积。
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
                        // 换元素顺序：先列、再行、再phase；每个元素重新累加。
                        accumulator<=0; pos<=0;
                        if(col+1<columns) col<=col+1;
                        else begin
                            col<=0;
                            if(row+1<N) row<=row+1;
                            else begin
                                row<=0;
                                if(phase==3) state<=SM_START; // 所有得分写完后逐行Softmax。
                                else if(phase==6) begin state<=IDLE; done<=1; end
                                else phase<=phase+1;
                            end
                        end
                    end else begin accumulator<=total; pos<=pos+LANES; end
                end
                SM_START: state<=SM_WAIT; // 仅一拍启动脉冲，下一拍等待子模块。
                SM_WAIT: begin
                    // 非阻塞赋值下，最后一项写回仍使用旧row，再切换到下一行。
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
