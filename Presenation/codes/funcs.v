

module parser #(
    parameter OUTLEN = 16,
    parameter N = 64,
    parameter Q = 47
)(
    input  b0, b1, b2, b3, b4, b5, b6, b7, b8, b9, benter, bdecim,
    input  bplus, bminus, bdiv, bmult, bsin, bcos, btan, bexp,
    input  clk,
    input  rst,
    input  toggle, // 0: two-operand, 1: function mode
    output reg [8*OUTLEN-1:0] display,
    output reg [N-1:0] val1_out,
    output reg [N-1:0] val2_out,
    output reg done
);

    // State encoding
    localparam S_NUM1        = 4'd0;
    localparam S_OP          = 4'd1;
    localparam S_NUM2        = 4'd2;
    localparam S_CALC        = 4'd3;
    localparam S_WAIT_DIV    = 4'd4;
    localparam S_WAIT_SIN    = 4'd5;
    localparam S_WAIT_COS    = 4'd6;
    localparam S_WAIT_TAN    = 4'd7;
    localparam S_WAIT_EXP    = 4'd8;
    localparam S_SHOW        = 4'd9;
    localparam S_FUNC_SELECT = 4'd10;
    localparam S_FUNC_ARG    = 4'd11;
    localparam S_FUNC_CALC   = 4'd12;
    localparam S_DONE_DIV    = 4'd13;
    localparam S_DONE_SIN    = 4'd14;

    reg [3:0] state;

    reg [8*OUTLEN-1:0] ascii_num1;
    reg [8*OUTLEN-1:0] ascii_num2;
    reg [4:0] idx_num1, idx_num2;
    reg [3:0] op; // 0:none 1:+ 2:- 3:* 4:/ 5:sin 6:cos 7:tan 8:exp

    wire [N-1:0] val1, val2;
    wire [8*OUTLEN-1:0] ascii_val1, ascii_val2, ascii_result;

    atf #(.N(N), .Q(Q), .INLEN(OUTLEN)) atf1 (.ascii_array(ascii_num1), .value(val1));
    atf #(.N(N), .Q(Q), .INLEN(OUTLEN)) atf2 (.ascii_array(ascii_num2), .value(val2));
    //fta #(.N(N), .Q(Q), .OUTLEN(OUTLEN)) fta1 (.value(val1), .ascii_array(ascii_val1));
    //fta #(.N(N), .Q(Q), .OUTLEN(OUTLEN)) fta2 (.value(val2), .ascii_array(ascii_val2));

    // Arithmetic modules
    wire [N-1:0] sum, diff, prod, quot;
    wire ovr, div_done_wire, div_ovr;
    reg [N-1:0] result_reg;
    reg div_start;
    adder      #(.N(N), .Q(Q)) add1 (.a(val1), .b(val2), .c(sum));
    adder      #(.N(N), .Q(Q)) sub1 (.a(val1), .b(~val2+1), .c(diff));
    multiplier #(.N(N), .Q(Q)) mult1 (.iMultiplicand(val1), .iMultiplier(val2), .oResult(prod), .ovr(ovr));
    divider    #(.N(N), .Q(Q)) div1 (.clk(clk), .rst(rst), .start(div_start), .dividend(val1), .divisor(val2), .quotient(quot), .done(div_done_wire), .overflow(div_ovr));

    // SIN/COS/TAN/EXP modules
    reg sin_start, cos_start, tan_start, exp_start, sin_rst, cos_rst, tan_rst, exp_rst;
    wire [N-1:0] sin_y, cos_y, tan_y, exp_y;
    wire sin_done, cos_done, tan_done, exp_done;
    fsinFixed #(.N(N), .Q(Q)) sinmod (.clk(clk), .rst(sin_rst), .start(sin_start), .x(val1), .y(sin_y), .done(sin_done));
    fcosFixed #(.N(N), .Q(Q)) cosmod (.clk(clk), .rst(cos_rst), .start(cos_start), .x(val1), .y(cos_y), .done(cos_done));
    ftanFixed #(.N(N), .Q(Q)) tanmod (.clk(clk), .rst(tan_rst), .start(tan_start), .x(val1), .y(tan_y), .done(tan_done));
    fexpFixed #(.N(N), .Q(Q)) expmod (.clk(clk), .rst(exp_rst), .start(exp_start), .x(val1), .y(exp_y), .done(exp_done));
    wire [8*OUTLEN-1:0] ascii_sin, ascii_cos, ascii_tan, ascii_exp;
    fta #(.N(N), .Q(Q), .OUTLEN(OUTLEN)) fta_sin (.value(sin_y), .ascii_array(ascii_sin));
    fta #(.N(N), .Q(Q), .OUTLEN(OUTLEN)) fta_cos (.value(cos_y), .ascii_array(ascii_cos));
    fta #(.N(N), .Q(Q), .OUTLEN(OUTLEN)) fta_tan (.value(tan_y), .ascii_array(ascii_tan));
    fta #(.N(N), .Q(Q), .OUTLEN(OUTLEN)) fta_exp (.value(exp_y), .ascii_array(ascii_exp));
    fta #(.N(N), .Q(Q), .OUTLEN(OUTLEN)) ftaop (.value(result_reg), .ascii_array(ascii_result));

    // --- Negedge detection for all buttons ---
    reg b0_prev, b1_prev, b2_prev, b3_prev, b4_prev, b5_prev, b6_prev, b7_prev, b8_prev, b9_prev;
    reg benter_prev, bdecim_prev, bplus_prev, bminus_prev, bdiv_prev, bmult_prev;
    reg bsin_prev, bcos_prev, btan_prev, bexp_prev;

    wire b0_negedge, b1_negedge, b2_negedge, b3_negedge, b4_negedge, b5_negedge, b6_negedge, b7_negedge, b8_negedge, b9_negedge;
    wire benter_negedge, bdecim_negedge, bplus_negedge, bminus_negedge, bdiv_negedge, bmult_negedge;
    wire bsin_negedge, bcos_negedge, btan_negedge, bexp_negedge;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            b0_prev <= 0; b1_prev <= 0; b2_prev <= 0; b3_prev <= 0; b4_prev <= 0;
            b5_prev <= 0; b6_prev <= 0; b7_prev <= 0; b8_prev <= 0; b9_prev <= 0;
            benter_prev <= 0; bdecim_prev <= 0; bplus_prev <= 0; bminus_prev <= 0;
            bdiv_prev <= 0; bmult_prev <= 0; bsin_prev <= 0; bcos_prev <= 0; btan_prev <= 0; bexp_prev <= 0;
        end else begin
            b0_prev <= b0; b1_prev <= b1; b2_prev <= b2; b3_prev <= b3; b4_prev <= b4;
            b5_prev <= b5; b6_prev <= b6; b7_prev <= b7; b8_prev <= b8; b9_prev <= b9;
            benter_prev <= benter; bdecim_prev <= bdecim; bplus_prev <= bplus; bminus_prev <= bminus;
            bdiv_prev <= bdiv; bmult_prev <= bmult; bsin_prev <= bsin; bcos_prev <= bcos; btan_prev <= btan; bexp_prev <= bexp;
        end
    end

    assign b0_negedge = (b0_prev && ~b0);
    assign b1_negedge = (b1_prev && ~b1);
    assign b2_negedge = (b2_prev && ~b2);
    assign b3_negedge = (b3_prev && ~b3);
    assign b4_negedge = (b4_prev && ~b4);
    assign b5_negedge = (b5_prev && ~b5);
    assign b6_negedge = (b6_prev && ~b6);
    assign b7_negedge = (b7_prev && ~b7);
    assign b8_negedge = (b8_prev && ~b8);
    assign b9_negedge = (b9_prev && ~b9);
    assign benter_negedge = (benter_prev && ~benter);
    assign bdecim_negedge = (bdecim_prev && ~bdecim);
    assign bplus_negedge = (bplus_prev && ~bplus);
    assign bminus_negedge = (bminus_prev && ~bminus);
    assign bdiv_negedge = (bdiv_prev && ~bdiv);
    assign bmult_negedge = (bmult_prev && ~bmult);
    assign bsin_negedge = (bsin_prev && ~bsin);
    assign bcos_negedge = (bcos_prev && ~bcos);
    assign btan_negedge = (btan_prev && ~btan);
    assign bexp_negedge = (bexp_prev && ~bexp);

    integer i;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            idx_num1 <= 0; idx_num2 <= 0;
            sin_rst <= 1; cos_rst <= 1; tan_rst <= 1; exp_rst <= 1;
            op <= 0; state <= S_NUM1;
            ascii_num1 <= {OUTLEN{8'd0}};
            ascii_num2 <= {OUTLEN{8'd0}};
            display <= {OUTLEN{8'd32}}; // fill with space
            val1_out <= 0; val2_out <= 0; result_reg <= 0;
            div_start <= 0; sin_start <= 0; cos_start <= 0; tan_start <= 0; exp_start <= 0;
            done <= 0;
        end else begin
            if (!toggle) begin // Two-operand mode
                case (state)
                    S_NUM1: begin
                        done <= 0;
                        if (b0_negedge) begin ascii_num1[8*(OUTLEN-1-idx_num1) +: 8] <= "0"; idx_num1 <= idx_num1 + 1; end
                        else if (b1_negedge) begin ascii_num1[8*(OUTLEN-1-idx_num1) +: 8] <= "1"; idx_num1 <= idx_num1 + 1; end
                        else if (b2_negedge) begin ascii_num1[8*(OUTLEN-1-idx_num1) +: 8] <= "2"; idx_num1 <= idx_num1 + 1; end
                        else if (b3_negedge) begin ascii_num1[8*(OUTLEN-1-idx_num1) +: 8] <= "3"; idx_num1 <= idx_num1 + 1; end
                        else if (b4_negedge) begin ascii_num1[8*(OUTLEN-1-idx_num1) +: 8] <= "4"; idx_num1 <= idx_num1 + 1; end
                        else if (b5_negedge) begin ascii_num1[8*(OUTLEN-1-idx_num1) +: 8] <= "5"; idx_num1 <= idx_num1 + 1; end
                        else if (b6_negedge) begin ascii_num1[8*(OUTLEN-1-idx_num1) +: 8] <= "6"; idx_num1 <= idx_num1 + 1; end
                        else if (b7_negedge) begin ascii_num1[8*(OUTLEN-1-idx_num1) +: 8] <= "7"; idx_num1 <= idx_num1 + 1; end
                        else if (b8_negedge) begin ascii_num1[8*(OUTLEN-1-idx_num1) +: 8] <= "8"; idx_num1 <= idx_num1 + 1; end
                        else if (b9_negedge) begin ascii_num1[8*(OUTLEN-1-idx_num1) +: 8] <= "9"; idx_num1 <= idx_num1 + 1; end
                        else if (bdecim_negedge) begin ascii_num1[8*(OUTLEN-1-idx_num1) +: 8] <= "."; idx_num1 <= idx_num1 + 1; end
                        else if (bplus_negedge || bminus_negedge || bmult_negedge || bdiv_negedge) begin
                            if (bplus_negedge)  op <= 1;
                            else if (bminus_negedge) op <= 2;
                            else if (bmult_negedge)  op <= 3;
                            else if (bdiv_negedge)   op <= 4;
                            val1_out <= val1;
                            state <= S_OP;
                        end
                        display <= ascii_num1;
                    end
                    S_OP: begin
                        idx_num2 <= 0;
                        ascii_num2 <= {OUTLEN{8'd0}};
                        display <= {OUTLEN{8'd32}};
                        if (op == 1) display[8*(OUTLEN-1-0) +: 8] <= "+";
                        else if (op == 2) display[8*(OUTLEN-1-0) +: 8] <= "-";
                        else if (op == 3) display[8*(OUTLEN-1-0) +: 8] <= "*";
                        else if (op == 4) display[8*(OUTLEN-1-0) +: 8] <= "/";
                        state <= S_NUM2;
                    end
                    S_NUM2: begin
                        if (b0_negedge) begin ascii_num2[8*(OUTLEN-1-idx_num2) +: 8] <= "0"; idx_num2 <= idx_num2 + 1; end
                        else if (b1_negedge) begin ascii_num2[8*(OUTLEN-1-idx_num2) +: 8] <= "1"; idx_num2 <= idx_num2 + 1; end
                        else if (b2_negedge) begin ascii_num2[8*(OUTLEN-1-idx_num2) +: 8] <= "2"; idx_num2 <= idx_num2 + 1; end
                        else if (b3_negedge) begin ascii_num2[8*(OUTLEN-1-idx_num2) +: 8] <= "3"; idx_num2 <= idx_num2 + 1; end
                        else if (b4_negedge) begin ascii_num2[8*(OUTLEN-1-idx_num2) +: 8] <= "4"; idx_num2 <= idx_num2 + 1; end
                        else if (b5_negedge) begin ascii_num2[8*(OUTLEN-1-idx_num2) +: 8] <= "5"; idx_num2 <= idx_num2 + 1; end
                        else if (b6_negedge) begin ascii_num2[8*(OUTLEN-1-idx_num2) +: 8] <= "6"; idx_num2 <= idx_num2 + 1; end
                        else if (b7_negedge) begin ascii_num2[8*(OUTLEN-1-idx_num2) +: 8] <= "7"; idx_num2 <= idx_num2 + 1; end
                        else if (b8_negedge) begin ascii_num2[8*(OUTLEN-1-idx_num2) +: 8] <= "8"; idx_num2 <= idx_num2 + 1; end
                        else if (b9_negedge) begin ascii_num2[8*(OUTLEN-1-idx_num2) +: 8] <= "9"; idx_num2 <= idx_num2 + 1; end
                        else if (bdecim_negedge) begin ascii_num2[8*(OUTLEN-1-idx_num2) +: 8] <= "."; idx_num2 <= idx_num2 + 1; end
                        else if (benter_negedge) begin
                            val2_out <= val2;
                            state <= S_CALC;
                        end
                        display <= ascii_num2;
                    end
                    S_CALC: begin
                        case (op)
                            1: begin result_reg <= sum; state <= S_SHOW; end
                            2: begin result_reg <= diff; state <= S_SHOW; end
                            3: begin result_reg <= prod; state <= S_SHOW; end
                            4: begin div_start <= 1; state <= S_WAIT_DIV; end
                            default: state <= S_SHOW;
                        endcase
                    end
                    S_WAIT_DIV: begin
                        div_start <= 0;
                        state <= S_DONE_DIV;
                    end
                    S_DONE_DIV: begin
                        if (div_done_wire) begin
                            result_reg <= quot;
                            state <= S_SHOW;
                        end
                    end
                    S_SHOW: begin
                        display <= ascii_result;
                        done <= 1;
                    end
                endcase
            end else begin // Function mode
                case (state)
                    S_NUM1: begin
                        done <= 0;
                        if (bsin_negedge) begin
                            display <= {OUTLEN{8'd32}};
                            display[8*(OUTLEN-1-0) +: 8] <= "s";
                            display[8*(OUTLEN-1-1) +: 8] <= "i";
                            display[8*(OUTLEN-1-2) +: 8] <= "n";
                            op <= 5; state <= S_FUNC_ARG;
                        end else if (bcos_negedge) begin
                            display <= {OUTLEN{8'd32}};
                            display[8*(OUTLEN-1-0) +: 8] <= "c";
                            display[8*(OUTLEN-1-1) +: 8] <= "o";
                            display[8*(OUTLEN-1-2) +: 8] <= "s";
                            op <= 6; state <= S_FUNC_ARG;
                        end else if (btan_negedge) begin
                            display <= {OUTLEN{8'd32}};
                            display[8*(OUTLEN-1-0) +: 8] <= "t";
                            display[8*(OUTLEN-1-1) +: 8] <= "a";
                            display[8*(OUTLEN-1-2) +: 8] <= "n";
                            op <= 7; state <= S_FUNC_ARG;
                        end else if (bexp_negedge) begin
                            display <= {OUTLEN{8'd32}};
                            display[8*(OUTLEN-1-0) +: 8] <= "e";
                            display[8*(OUTLEN-1-1) +: 8] <= "x";
                            display[8*(OUTLEN-1-2) +: 8] <= "p";
                            op <= 8; state <= S_FUNC_ARG;
                        end
                    end
                    S_FUNC_ARG: begin
                        idx_num1 <= 0;
                        sin_rst <= 1;
                        ascii_num1 <= {OUTLEN{8'd0}};
                        if (benter_negedge) state <= S_FUNC_CALC;
                    end
                    S_FUNC_CALC: begin
                        if (b0_negedge) begin ascii_num1[8*(OUTLEN-1-idx_num1) +: 8] <= "0"; idx_num1 <= idx_num1 + 1; end
                        else if (b1_negedge) begin ascii_num1[8*(OUTLEN-1-idx_num1) +: 8] <= "1"; idx_num1 <= idx_num1 + 1; end
                        else if (b2_negedge) begin ascii_num1[8*(OUTLEN-1-idx_num1) +: 8] <= "2"; idx_num1 <= idx_num1 + 1; end
                        else if (b3_negedge) begin ascii_num1[8*(OUTLEN-1-idx_num1) +: 8] <= "3"; idx_num1 <= idx_num1 + 1; end
                        else if (b4_negedge) begin ascii_num1[8*(OUTLEN-1-idx_num1) +: 8] <= "4"; idx_num1 <= idx_num1 + 1; end
                        else if (b5_negedge) begin ascii_num1[8*(OUTLEN-1-idx_num1) +: 8] <= "5"; idx_num1 <= idx_num1 + 1; end
                        else if (b6_negedge) begin ascii_num1[8*(OUTLEN-1-idx_num1) +: 8] <= "6"; idx_num1 <= idx_num1 + 1; end
                        else if (b7_negedge) begin ascii_num1[8*(OUTLEN-1-idx_num1) +: 8] <= "7"; idx_num1 <= idx_num1 + 1; end
                        else if (b8_negedge) begin ascii_num1[8*(OUTLEN-1-idx_num1) +: 8] <= "8"; idx_num1 <= idx_num1 + 1; end
                        else if (b9_negedge) begin ascii_num1[8*(OUTLEN-1-idx_num1) +: 8] <= "9"; idx_num1 <= idx_num1 + 1; end
                        else if (bdecim_negedge) begin ascii_num1[8*(OUTLEN-1-idx_num1) +: 8] <= "."; idx_num1 <= idx_num1 + 1; end
                        else if (benter_negedge) begin
                            val1_out <= val1;
                            if (op==5) begin sin_rst <=0; sin_start<=1; state<=S_WAIT_SIN; end
                            else if (op==6) begin cos_rst <=0; cos_start<=1; state<=S_WAIT_COS; end
                            else if (op==7) begin tan_rst <=0; tan_start<=1; state<=S_WAIT_TAN; end
                            else if (op==8) begin exp_rst <=0; exp_start<=1; state<=S_WAIT_EXP; end
                        end
                        display <= ascii_num1;
                    end
                    S_WAIT_SIN: begin
                        if (sin_done) begin
                            result_reg <= sin_y;
                            display <= ascii_sin;
                            done <= 1;
                            sin_start <= 0;
                            state <= S_SHOW;
                        end
                    end
                    S_WAIT_COS: begin
                        if (cos_done) begin
                            result_reg <= cos_y;
                            display <= ascii_cos;
                            done <= 1;
                            cos_start <= 0;
                            state <= S_SHOW;
                        end
                    end
                    S_WAIT_TAN: begin
                        if (tan_done) begin
                            result_reg <= tan_y;
                            display <= ascii_tan;
                            done <= 1;
                            tan_start <= 0;
                            state <= S_SHOW;
                        end
                    end
                    S_WAIT_EXP: begin
                        if (exp_done) begin
                            result_reg <= exp_y;
                            display <= ascii_exp;
                            done <= 1;
                            exp_start <= 0;
                            state <= S_SHOW;
                        end
                    end
                    S_SHOW: begin
                        display <= ascii_result;
                    end
                endcase
            end
        end
    end

endmodule


module fta #(
    parameter N = 64,
    parameter Q = 47,
    parameter OUTLEN = 16
) (
    input  [N-1:0] value,
    output reg [OUTLEN*8-1:0] ascii_array
);

    // Internal variables
    reg sign;
    reg [N-1:0] abs;
    reg [15:0] int_part;
    reg [46:0] frac_part;
    reg [63:0] frac_scaled;
    reg [OUTLEN*8-1:0] temp_ascii;
    reg [15:0] int_copy;
    reg [3:0]  digits [0:4];
    integer i, j, k, m;
    reg [19:0] frac_digits;

    always @(*) begin
        // 1. Extract sign, integer, and fraction
        sign      = value[N-1];
        abs = sign ? ~value + 1 : value;
        int_part  = abs[62:47];
        frac_part = abs[46:0];

        // 2. Clear output
        for (i = 0; i < OUTLEN; i = i + 1)
            temp_ascii[8*(OUTLEN-1-i) +: 8] = " ";

        i = 0;
        if (sign) begin
            temp_ascii[8*(OUTLEN-1-i) +: 8] = "-";
            i = i + 1;
        end

        // Integer to decimal ASCII
        if (int_part == 0) begin
            temp_ascii[8*(OUTLEN-1-i) +: 8] = "0";
            i = i + 1;
        end else begin
            int_copy = int_part;
            for (j = 0; j < 5; j = j + 1) begin
                digits[j] = int_copy % 10;
                int_copy = int_copy / 10;
            end
            for (k = 4; k >= 0; k = k - 1) begin
                if (digits[k] != 0 || i > (sign ? 1 : 0)) begin
                    temp_ascii[8*(OUTLEN-1-i) +: 8] = digits[k] + "0";
                    i = i + 1;
                end
            end
        end

        // Decimal point
        temp_ascii[8*(OUTLEN-1-i) +: 8] = ".";
        i = i + 1;

        // 3. Convert fractional part to decimal ASCII (5 digits)
        frac_scaled = (frac_part * 100000) >> Q;
        frac_digits = frac_scaled[19:0];
        for (m = 4; m >= 0; m = m - 1) begin
            temp_ascii[8*(OUTLEN-1-(i+m)) +: 8] = (frac_digits % 10) + "0";
            frac_digits = frac_digits / 10;
        end

        // 4. Output
        ascii_array = temp_ascii;
    end

endmodule


module atf #(
    parameter N = 64,
    parameter Q = 47,
    parameter INLEN = 16
) (
    input  [8*INLEN - 1:0] ascii_array,
    output reg [N-1:0] value
);

    // Internal variables
    reg sign;
    integer i, j, state, int_digits, frac_digits;
    reg [15:0] int_accum;
    reg [19:0] frac_accum;
    reg [N-1:0] result;
    reg [31:0] frac_scale;
    reg [7:0] current;

    always @(*) begin
        // 1. Initialize
        sign = 0;
        int_accum = 0;
        frac_accum = 0;
        int_digits = 0;
        frac_digits = 0;
        state = 0; // 0: start, 1: int, 2: frac
        i = 0;
        // 2. Parse ASCII string
        for (i = 0; i < INLEN; i = i + 1) begin
            current = ascii_array[8*(INLEN -i) +: 8];
            if (current == 8'd0 || current == " ") begin
                state = 0;
            end
            if (state == 0) begin
                if (current == "-") begin
                    sign = 1;
                end
                state = 1;
            end else if (state == 1) begin
                if (current >= "0" && current <= "9" && int_digits < 5) begin
                    int_accum = int_accum * 10 + (current - "0");
                    int_digits = int_digits + 1;
                end else if (current == ".") begin
                    state = 2;
                end else begin
                end
            end else if (state == 2) begin
                if (current >= "0" && current <= "9" && frac_digits < 5) begin
                    frac_accum = frac_accum * 10 + (current - "0");
                    frac_digits = frac_digits + 1;
                end else begin
                end
            end
        end

        // 3. Convert integer part
        result = int_accum;
        result = result << Q;

        // 4. Convert fractional part (up to 5 digits)
        if (frac_digits > 0) begin
            frac_scale = 1;
            for (j = 0; j < 6; j = j + 1)
                if(j < frac_digits) begin
                    frac_scale = frac_scale * 10;
                end
            result = result + ((frac_accum << Q) / frac_scale);
        end

        // 5. Apply sign
        if (sign)
            value = ~result + 1;
        else
            value = result;
    end

endmodule


module adder #(
    parameter Q = 47,
    parameter N = 64
)(
    input signed [N-1:0] a,
    input signed [N-1:0] b,
    output signed [N-1:0] c
);

    assign c = a + b;


endmodule


module multiplier #(
    parameter Q = 47,
    parameter N = 64
)(
    input  [N-1:0] iMultiplicand,
    input  [N-1:0] iMultiplier,
    output [N-1:0] oResult,
    output reg     ovr
);

    reg [2*N-1:0] result;      // 128-bit intermediate result
    reg [N-1:0]   retVal;

    assign oResult = retVal;

    always @(*) begin
        // Zero check: if either operand is zero, short-circuit
        if (iMultiplicand[N-2:0] == 0 || iMultiplier[N-2:0] == 0) begin
            result <= 0;
            ovr    <= 0;
        end else begin
            result <= iMultiplicand[N-2:0] * iMultiplier[N-2:0];
            ovr    <= 0;
        end
    end

    always @(*) begin
        // Sign bit = XOR of signs
        retVal[N-1]   <= iMultiplicand[N-1] ^ iMultiplier[N-1];

        // Shift result to fixed-point position (middle bits)
        retVal[N-2:0] <= result[N-2+Q:Q];

        // Overflow check: any bits above the expected MSB
        if (|result[2*N-2:N-1+Q])
            ovr <= 1;
    end

endmodule

module divider #(
    parameter Q = 47,
    parameter N = 64
)(
    input  wire             clk,
    input  wire             rst,
    input  wire             start,
    input  wire [N-1:0]     dividend,
    input  wire [N-1:0]     divisor,
    output reg  [N-1:0]     quotient,
    output reg              done,
    output reg              overflow
);

    // Internal registers
    reg [2*N+Q-3:0]   working_quotient;
    reg [N-2+Q:0]     working_dividend;
    reg [2*N+Q-3:0]   working_divisor;
    reg [N+Q-1:0]     count;
    reg               sign;


    always @(posedge clk or posedge rst) begin
        if (rst) begin
            done             <= 1'b1;
            overflow         <= 1'b0;
            sign             <= 1'b0;
            working_quotient <= 0;
            quotient         <= 0;
            working_dividend <= 0;
            working_divisor  <= 0;
            count            <= 0;
        end else if (done && start) begin
            // Start division
            done             <= 1'b0;
            overflow         <= 1'b0;
            working_quotient <= 0;
            working_dividend <= 0;
            working_divisor  <= 0;
            count            <= N+Q-1;

            // Left-align dividend and divisor
            working_dividend[N+Q-2:Q] <= dividend[N-2:0];
            working_divisor[2*N+Q-3:N+Q-1] <= divisor[N-2:0];

            // Set sign bit
            sign <= dividend[N-1] ^ divisor[N-1];

        end else if (!done) begin
            // Shift divisor right
            working_divisor <= working_divisor >> 1;

            // If dividend >= divisor, set quotient bit and subtract
            if (working_dividend >= working_divisor) begin
                working_quotient[count] <= 1'b1;
                working_dividend <= working_dividend - working_divisor;
            end

            // Decrement count
            if (count == 0) begin
                done     <= 1'b1;
                quotient[N-2:0] <= working_quotient[N-2:0];
                quotient[N-1]   <= sign;
                if (|working_quotient[2*N+Q-3:N])
                    overflow <= 1'b1;
            end else begin
                count <= count - 1;
            end
        end
    end

endmodule



module fixedCompare (
    input  [63:0] a,
    input  [63:0] b,
    output reg result
);

    wire [63:0] absA = a[63] ? (~a + 1) : a;
    wire [63:0] absB = b[63] ? (~b + 1) : b;

    always @(*) begin
        result = (absA < absB);
    end

endmodule

module fsinFixed #(
    parameter N = 64,
    parameter Q = 47
)(
    input                  clk,
    input                  rst,
    input                  start,
    input      [N-1:0]     x,
    output reg [N-1:0]     y,
    output reg             done
);

    parameter H         = 64'h0000000080000000; // ~2^-16
    parameter TWO       = 64'h0000FFFFFFFF8000; // 2.0 - h^h
    parameter MINUS_ONE = 64'hFFFF800000000000; // -1.0

    reg [N-1:0] i, yp, ypp;
    wire [N-1:0] twoYp, yppNeg, yIter, iNext;
    wire compare;

    multiplier #(.N(N), .Q(Q)) m1 (
        .iMultiplicand(yp),
        .iMultiplier(TWO),
        .oResult(twoYp),
        .ovr()
    );

    assign yppNeg = ~ypp + 1;

    adder #(.N(N), .Q(Q)) a1 (
        .a(twoYp),
        .b(yppNeg),
        .c(yIter)
    );

    adder #(.N(N), .Q(Q)) a2 (
        .a(i),
        .b(H),
        .c(iNext)
    );

    fixedCompare cmp (
        .a(i),
        .b(x),
        .result(compare)
    );

    // Main FSM
    always @(posedge clk) begin
        if (rst) begin
            i    <= 64'd0;
            yp   <= H;       // dy/dx ≈ small value
            ypp  <= 64'd0;
            y    <= 64'd0;
            done <= 0;
        end else if (start && !done) begin
            if (compare) begin
                ypp <= yp;
                yp  <= yIter;
                i   <= iNext;
            end else begin
                y <= {yIter[N-1]^x[N-1],yIter[N-2:0]};
                done <= 1;
            end
        end
    end

endmodule

module fcosFixed #(
    parameter N = 64,
    parameter Q = 47
)(
    input                  clk,
    input                  rst,
    input                  start,
    input      [N-1:0]     x,
    output reg [N-1:0]     y,
    output reg             done
);

    parameter H         = 64'h0000000080000000; // ~2^-16
    parameter TWO       = 64'h0000FFFFFFFF8000; // 2.0 - h^h
    parameter MINUS_ONE = 64'hFFFF800000000000; // -1.0

    reg [N-1:0] i, yp, ypp;
    wire [N-1:0] twoYp, yppNeg, yIter, iNext;
    wire compare;

    multiplier #(.N(N), .Q(Q)) m1 (
        .iMultiplicand(yp),
        .iMultiplier(TWO),
        .oResult(twoYp),
        .ovr()
    );

    assign yppNeg = ~ypp + 1;

    adder #(.N(N), .Q(Q)) a1 (
        .a(twoYp),
        .b(yppNeg),
        .c(yIter)
    );

    adder #(.N(N), .Q(Q)) a2 (
        .a(i),
        .b(H),
        .c(iNext)
    );

    fixedCompare cmp (
        .a(i),
        .b(x),
        .result(compare)
    );

    // Main FSM
    always @(posedge clk) begin
        if (rst) begin
            i    <= 64'd0;
            yp   <= 64'h00007FFFFFFFC000;       // dy/dx ≈ small value
            ypp  <= 64'h0000800000000000;
            y    <= 64'd0;
            done <= 0;
        end else if (start && !done) begin
            if (compare) begin
                ypp <= yp;
                yp  <= yIter;
                i   <= iNext;
            end else begin
                y <= yIter[N-2:0];
                done <= 1;
            end
        end
    end

endmodule

module ftanFixed #(
    parameter N = 64,
    parameter Q = 47
)(
    input                  clk,
    input                  rst,
    input                  start,
    input      [N-1:0]     x,
    output reg [N-1:0]     y,
    output reg             done
);

    parameter H         = 64'h0000000080000000; // ~2^-16

    reg [N-1:0] i, yp;
    wire [N-1:0] ypSq, ypPlusH, ypSqH,yIter, iNext;
    wire compare;

    multiplier #(.N(N), .Q(Q)) m1 (
        .iMultiplicand(yp),
        .iMultiplier(yp),
        .oResult(ypSq),
        .ovr()
    );

    multiplier #(.N(N), .Q(Q)) m2 (
        .iMultiplicand(ypSq),
        .iMultiplier(H),
        .oResult(ypSqH),
        .ovr()
    );


    adder #(.N(N), .Q(Q)) a1 (
        .a(yp),
        .b(H),
        .c(ypPlusH)
    );

    adder #(.N(N), .Q(Q)) a2 (
        .a(ypSqH),
        .b(ypPlusH),
        .c(yIter)
    );

    adder #(.N(N), .Q(Q)) a3 (
        .a(i),
        .b(H),
        .c(iNext)
    );

    fixedCompare cmp (
        .a(i),
        .b(x),
        .result(compare)
    );

    // Main FSM
    always @(posedge clk) begin
        if (rst) begin
            i    <= 64'd0;
            yp   <= 64'd0;       // dy/dx ≈ small value
            y    <= 64'd0;
            done <= 0;
        end else if (start && !done) begin
            if (compare) begin
                yp  <= yIter;
                i   <= iNext;
            end else begin
                y <= {yIter[N-1]^x[N-1],yIter[N-2:0]};
                done <= 1;
            end
        end
    end

endmodule



module fexpFixed #(
    parameter N = 64,
    parameter Q = 47
)(
    input                  clk,
    input                  rst,
    input                  start,
    input      [N-1:0]     x,
    output reg [N-1:0]     y,
    output reg             done
);

    parameter H         = 64'h0000000080000000; // ~2^-16
    parameter MUL = 64'h0000800080000000;

    reg [N-1:0] i, yp;
    wire [N-1:0] yIter, iNext;
    wire compare;

    multiplier #(.N(N), .Q(Q)) m1 (
        .iMultiplicand(yp),
        .iMultiplier(MUL),
        .oResult(yIter),
        .ovr()
    );

    adder #(.N(N), .Q(Q)) a1 (
        .a(i),
        .b(H),
        .c(iNext)
    );

    fixedCompare cmp (
        .a(i),
        .b(x),
        .result(compare)
    );

    // Main FSM
    always @(posedge clk) begin
        if (rst) begin
            i    <= 64'd0;
            yp   <= 64'h0000800000000000;       // dy/dx ≈ small value
            y    <= 64'd0;
            done <= 0;
        end else if (start && !done) begin
            if (compare) begin
                yp  <= yIter;
                i   <= iNext;
            end else begin
                y <= yIter;
                done <= 1;
            end
        end
    end

endmodule
