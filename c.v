module c(
         // a to c
         input a_c_0,
         input [1:0] a_c_1,
         // b to c
         input b_c_0,
         input [5:0] b_c_1,
         // c to a
         output [12:0] c_a_0,
         output c_a_1,
         // c to b
         output [134:0] c_b_0,
         output c_b_1,
         // top input to c
         input c_in_0,
         input [1:0] c_in_1,
         // c to top output
         output c_out_0,
         output [43:0] c_out_1
         );
endmodule // c
