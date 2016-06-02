#!/usr/bin/perl -w
use vconn;

$top = vconn->new("chip_top");
#$top->print_debug("top");

#$top->read_file("a.v");
#$top->read_file("b.v");
#$top->read_file("c.v");
$top->read_file(["a.v","b.v","c.v"]);

#$top->print_debug("modules");
#$top->add_inst("a", "u_a", {"a_out_1" => ""},'',{"TEST1" => "12"});
$top->add_inst("a", "u_a", {"a_out_1" => ""},'',{"TEST3" => "4'h4","A_B_0" => "2*TEST3+4'h5",});

$sub_ref = sub {
  my $var = shift;
  $var =~s /^i_(\w+)/$1/g;
  return $var;
};

$b_ref = {
  'b_c_0' => 'b_c_0_alias'
};

$top->add_inst("b", "u_b", $b_ref, $sub_ref);

$c_ref = {
  'b_c_0' => 'b_c_0_alias'
};

$top->add_inst("c", "u_c", $c_ref);

$top->add_port("output", "new_out");
$code = <<ENDOFCODE;
assign new_out = 1'b1;
ENDOFCODE
$top->add_code($code);
$top->add_code("//ending code", 0);
$top->add_code("//beginning code", 1);
$top->conn();
#$top->print_debug("top");

#$top->write_file("gen/chip_top.v"); #may fail in windows
$top->write_out();
