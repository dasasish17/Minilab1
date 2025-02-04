module MAC #
(
parameter DATA_WIDTH = 8
)
(
input clk,
input rst_n,
input En,
input Clr,
input [DATA_WIDTH-1:0] Ain,
input [DATA_WIDTH-1:0] Bin,
output [DATA_WIDTH*3-1:0] Cout
);

    // Internal signals
    logic [DATA_WIDTH*2-1:0] product_ff;          
    logic [DATA_WIDTH*3-1:0] accumulator;      

    // Multiply operation
   
    reg [DATA_WIDTH-1:0] ff_Ain, ff_Bin, ffff_Ain, ffff_Bin;
    reg ff_En, ffff_En;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ff_Ain <= 0;    
            ff_Bin <= 0;  
            ff_En <= 0;   
            ffff_Ain <= 0;  
            ffff_Bin <= 0; 
            ffff_En <= 0;                         
        end else  begin
            ff_Ain <= Ain;    
            ff_Bin <= Bin; 
            ff_En <= En;  
            ffff_Ain <= ff_Ain;  
            ffff_Bin <= ff_Bin; 
            ffff_En <= ff_En;  
        end
    end

     always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            product_ff<= 0;                          
        end else if (ff_En) begin
            product_ff <=  ff_Ain * ff_Bin; 
        end
    end
    // Accumulate operation
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accumulator <= 0;                  
        end else if (Clr) begin
            accumulator <= 0;                 
        end else if (ffff_En) begin
            accumulator <= accumulator + product_ff;
        end
    end

    // Assign output
    assign Cout = accumulator ;


endmodule