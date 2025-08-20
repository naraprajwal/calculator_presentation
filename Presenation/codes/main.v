module main (
    input  b0    , b1, b2, b3, b4, b5, b6, b7, b8, b9, benter, bdecim,
    input  bplus, bminus, bdiv, bmult, bsin, bcos, btan, bexp,
    input  rst,
    input  toggle, // 0: two-operand, 1: function mode
    output reg LCD_EN, 
    output reg LCD_RS,
    output reg [7:4] DATA
);

    parameter OUTLEN = 10;
    parameter N = 64;
    parameter Q = 47;


    // ===== Clock Generator =====
    wire clk;
    qlal4s3b_cell_macro u_qlal4s3b_cell_macro (
        .Sys_Clk0(clk)
    );

    // ===== Display Message Producer =====
    wire [8*OUTLEN-1:0] top_display;
    wire [N-1:0] val1_out, val2_out;
    wire done;  // now unused

    parser #(
        .OUTLEN(OUTLEN),
        .N(N),
        .Q(Q)
    ) top_inst (
        .b0(b0), .b1(b1), .b2(b2), .b3(b3), .b4(b4), .b5(b5),
        .b6(b6), .b7(b7), .b8(b8), .b9(b9),
        .benter(benter), .bdecim(bdecim),
        .bplus(bplus), .bminus(bminus),
        .bdiv(bdiv), .bmult(bmult),
        .bsin(bsin), .bcos(bcos), .btan(btan), .bexp(bexp),
        .clk(clk),
        .rst(rst),
        .toggle(toggle),
        .display(top_display),
        .val1_out(val1_out),
        .val2_out(val2_out),
        .done(done)
    );

    reg [3:0] char_idx;
    reg [7:0] curr_char;
    reg [15:0] count;
    reg [3:0] lcd_state ;
    reg nibble;  // 0 = high nibble, 1 = low nibble
    reg en;
    reg rs;

    reg [7:4] data;

    localparam S_IDLE  = 0;
    localparam S_SETUP = 1;
    localparam S_EN_PULSE_HI = 2;
    localparam S_EN_PULSE_LO = 3;
    localparam S_WAIT = 4;
    localparam S_NEXT = 5;

    always @(posedge clk) begin
        if (rst) begin
            lcd_state <= S_IDLE;
            char_idx  <= 0;
            nibble    <= 0;
            en        <= 0;
            rs        <= 1;
            data      <= 4'h0;
            count     <= 0;
        end else begin
            case (lcd_state)
                S_IDLE: begin
                    //curr_char <= top_display[8*(OUTLEN - 1 - char_idx) +: 8];
                    lcd_state <= S_SETUP;
                end

                S_SETUP: begin
                    rs <= 1;  // Always data mode
                    data <= nibble ? curr_char[3:0] : curr_char[7:4];
                    en <= 1;
                    count <= 0;
                    lcd_state <= S_EN_PULSE_HI;
                end

                S_EN_PULSE_HI: begin
                    if (count < 20) count <= count + 1;
                    else begin
                        en <= 0;
                        count <= 0;
                        lcd_state <= S_EN_PULSE_LO;
                    end
                end

                S_EN_PULSE_LO: begin
                    if (count < 20) count <= count + 1;
                    else begin
                        count <= 0;
                        if (!nibble) begin
                            nibble <= 1;
                            lcd_state <= S_SETUP;  // send low nibble
                        end else begin
                            nibble <= 0;
                            lcd_state <= S_WAIT;  // pause before next char
                        end
                    end
                end

                S_WAIT: begin
                    if (count < 2000) count <= count + 1;  // ~100us
                    else begin
                        count <= 0;
                        lcd_state <= S_NEXT;
                    end
                end

                S_NEXT: begin
                    char_idx <= (char_idx == OUTLEN-1) ? 0 : char_idx + 1;
                    lcd_state <= S_IDLE;
                end
            endcase
        end

        
    end

    // Outputs to LCD
    assign LCD_EN = en;
    assign LCD_RS = rs;
    assign DATA   = data;
    

endmodule




