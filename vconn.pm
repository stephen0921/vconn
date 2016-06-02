package vconn;

use strict;
use Carp;
use Data::Dumper;
use rvp;
use Template;
use Symbol;
use File::Basename;

sub new {
    my $class = shift;
    my $self = {};
    bless($self, $class);
    $self->init(@_);
    return $self;
}

sub init {
    my ($self) = shift;
    $self->{top}->{name} = shift;
    my $attr = shift;
    if (defined $attr) {
        if (defined $attr->{log}) {
            $self->{log} = $attr->{log};
        }
    }
    $self->{modules} = {};
    $self->{add_ports} = {};
};

sub read_file {
    my $self = shift;
    my ($file_name) = @_;
     
    if(! -e $file_name) {
        croak "Can not find $file_name : $!";
    }

    my @files            = ($file_name);
    my %cmd_line_defines = ();
    my $quiet            = 1;
    my @inc_dirs         = ();
    my @lib_dirs         = ();
    my @lib_exts         = ();

    my $vdb = rvp->read_verilog(\@files,[],\%cmd_line_defines, $quiet,\@inc_dirs,\@lib_dirs,\@lib_exts);
    my @problems = $vdb->get_problems();

    if (@problems) {
        foreach my $problem ($vdb->get_problems()) {
            print STDERR "$problem.\n";
        }
        #die "Warnings parsing files!";
    }

    foreach my $module (sort $vdb->get_modules()) {
        my %parameters = $vdb->get_modules_parameters($module);
        foreach my $p (sort keys %parameters) {
            my $v = $parameters{$p};
            $v =~ s/[ \n]//gs;
            $self->{modules}->{$module}->{parameters}->{$p} = $self->param_preprocess($v); #default parameters, will be updated when call add_inst
            #print "   parameter: $p defaults to \"$v\"\n";
        }

        foreach my $sig (sort $vdb->get_modules_signals($module)) {
            my ($line,$a_line,$i_line,$type,$file,$posedge,$negedge, $type2,$s_file,$s_line,$range,$a_file,$i_file,$dims) = $vdb->get_module_signal($module,$sig);
            if($type =~ /input/) {
                $self->{modules}->{$module}->{inputs}->{$sig}->{range} = $range;#has parameter
                #$self->{modules}->{$module}->{inputs}->{$sig}->{width} = $self->range_to_width($range, $self->{modules}->{$module}->{parameters});
            }
            if($type =~ /output/) {
                $self->{modules}->{$module}->{outputs}->{$sig}->{range} = $range;#has parameter
                #$self->{modules}->{$module}->{outputs}->{$sig}->{width} = $self->range_to_width($range, $self->{modules}->{$module}->{parameters});
            }
        }
    }
}

sub add_inst {
    my $self = shift;
    my ($mod_name,$inst_name,$port_href,$sub_href,$param_ref) = @_;
    
    #check whether module is read in
    my $mod_found = 0;
    foreach my $item (keys %{ $self->{modules} }) {
        if ($mod_name eq $item) {
            $mod_found = 1;
            last;
        }
    }
    if ($mod_found == 0) {
        croak "Please make sure module $mod_name is read by read_file : $!";
    }

    #modify instances data structure
    $self->{top}->{instances}->{$inst_name}->{mod_name} = $mod_name;
    $self->{top}->{instances}->{$inst_name}->{inputs} = $self->{modules}->{$mod_name}->{inputs};
    $self->{top}->{instances}->{$inst_name}->{outputs} = $self->{modules}->{$mod_name}->{outputs};
    #$self->{top}->{instances}->{$inst_name}->{inouts} = $self->{modules}->{$mod_name}->{inouts};

    #default net name
    foreach my $item (keys %{ $self->{top}->{instances}->{$inst_name}->{inputs} }) {
        if ((defined $sub_href) and (ref($sub_href) eq "CODE")) { #callback sub
            $self->{top}->{instances}->{$inst_name}->{inputs}->{$item}->{conn} = &$sub_href($item);
        } else { #default
            $self->{top}->{instances}->{$inst_name}->{inputs}->{$item}->{conn} = $item;
        }
    }
    foreach my $item (keys %{ $self->{top}->{instances}->{$inst_name}->{outputs} }) {
        if ((defined $sub_href) and (ref($sub_href) eq "CODE")) { #callback sub
            $self->{top}->{instances}->{$inst_name}->{outputs}->{$item}->{conn} = &$sub_href($item);
        } else { #default 
            $self->{top}->{instances}->{$inst_name}->{outputs}->{$item}->{conn} = $item;
        }
    }
    #wire name customized
    if ((defined $port_href) and (ref($port_href) eq "HASH")) {
        foreach my $item (keys %{ $port_href }) {
            if (defined $self->{top}->{instances}->{$inst_name}->{inputs}->{$item}) {
                $self->{top}->{instances}->{$inst_name}->{inputs}->{$item}->{conn} = $port_href->{$item}; #can be bus0[5:2], bus1, or {bus2[3:2], bus3}
            }
            if (defined $self->{top}->{instances}->{$inst_name}->{outputs}->{$item}) {
                $self->{top}->{instances}->{$inst_name}->{outputs}->{$item}->{conn} = $port_href->{$item};
            }
        }
    }
    #default parameters
    $self->{top}->{instances}->{$inst_name}->{parameters} = $self->{modules}->{$mod_name}->{parameters};
    
    #parameter customized
    if ((defined $param_ref) and (ref($param_ref) eq "HASH")) {
        #print "custom parameters\n";
        foreach my $item (keys %{ $param_ref }) {
            if (defined $self->{top}->{instances}->{$inst_name}->{parameters}->{$item}) {
                $self->{top}->{instances}->{$inst_name}->{parameters}->{$item} = $self->param_preprocess($param_ref->{$item});
            }
            
        }
        
    }
    my $param_value;
    $param_value = \%{ $self->{top}->{instances}->{$inst_name}->{parameters} } ;
    foreach my $param (keys %{ $param_value }) {
        #print "before replace",$param_value->{$param},"\n";
        $param_value->{$param} = $self->replace_parameter($param_value->{$param}, $self->{top}->{instances}->{$inst_name}->{parameters});
        #print "after  replace",$param_value->{$param},"\n";
        $param_value->{$param} = eval($param_value->{$param});
    }
    $self->{top}->{instances}->{$inst_name}->{parameters} = $param_value;
        
    foreach my $input (keys %{ $self->{top}->{instances}->{$inst_name}->{inputs} }) {
        $self->{top}->{instances}->{$inst_name}->{inputs}->{$input}->{width} = $self->range_to_width($self->{top}->{instances}->{$inst_name}->{inputs}->{$input}->{range}, $self->{top}->{instances}->{$inst_name}->{parameters});
    }
    foreach my $output (keys %{ $self->{top}->{instances}->{$inst_name}->{outputs} }) {
        $self->{top}->{instances}->{$inst_name}->{outputs}->{$output}->{width} = $self->range_to_width($self->{top}->{instances}->{$inst_name}->{outputs}->{$output}->{range}, $self->{top}->{instances}->{$inst_name}->{parameters});
    }
    
    #generate or update top nets
    #inputs
    foreach my $item (keys %{ $self->{top}->{instances}->{$inst_name}->{inputs} }) {
        #bus0
        if ($self->{top}->{instances}->{$inst_name}->{inputs}->{$item}->{conn} =~/^\w+$/) {
            my $net = $&;
            push @{ $self->{top}->{instances}->{$inst_name}->{inputs}->{$item}->{nets} }, $net;
                
            my $mod_name = $self->{top}->{instances}->{$inst_name}->{mod_name};
          
            if (defined $self->{top}->{nets}->{$net}) {
                if ($self->{top}->{nets}->{$net}->{width} != $self->{top}->{instances}->{$inst_name}->{inputs}->{$item}->{width}) {
                    croak "Known width for net $net is $self->{top}->{nets}->{$net}->{width}, but the newly added one is $self->{top}->{instances}->{$inst_name}->{inputs}->{$item}->{width}";
                }
                #print "if input item = $item\n";
                
            }
            else {
                defined ($mod_name) or croak "instance $inst_name must is a known module";
                $self->{top}->{nets}->{$net}->{width} = $self->{top}->{instances}->{$inst_name}->{inputs}->{$item}->{width};
                #print "else input item = $item\n";
                #print "net $net: width = $self->{top}->{nets}->{$net}->{width}\n";   
            }
        }
        #bus0[11:2] or bus0[1]
        elsif ($self->{top}->{instances}->{$inst_name}->{inputs}->{$item}->{conn} =~/^(\w+)\[(\d+)(\:\d+)?\]$/) {
            my $net = $1;
            push @{ $self->{top}->{instances}->{$inst_name}->{inputs}->{$item}->{nets} }, $net;
                
            my $high = $2;
            #my $low = $3;
            my $mod_name = $self->{top}->{instances}->{$inst_name}->{mod_name};

            if (defined $self->{top}->{nets}->{$net}) {
                my $width = $self->{top}->{nets}->{$net}->{width};
                if ($width < ($high + 1)) {
                    croak "net $net that newly added has $high bits at least, but $net is already known to be $width bits wide";
                }
            }
            else {
                defined ($mod_name) or croak "instance $inst_name must is a known module";
                #check against to inst info
                my $width = $self->{top}->{instances}->{$inst_name}->{inputs}->{$item}->{width};
                if ($width < ($high +1)) {
                    croak "Known width for port $item is $width bits wide, but the newly added one's highest bit is $high";
                }

                #use high+1 as the width
                #$self->{top}->{nets}->{$net}->{width} = $high + 1;
            }
        }
        #11'b1, 4'd10, 9'h1
        elsif ($self->{top}->{instances}->{$inst_name}->{inputs}->{$item}->{conn} =~/^(\d+)\'[bdh](\w+)$/) {
            my $width = $1;
            my $mod_name = $self->{top}->{instances}->{$inst_name}->{mod_name};
            #check against to inst info
            if ($width ne $self->{top}->{instances}->{$inst_name}->{inputs}->{$item}->{width}) {
                croak "Width mismatch between module and instance for port $item";
            }
        }
        #{bus2[21:10],bus3[3:1],bus4}
        else {
            if ($self->{top}->{instances}->{$inst_name}->{inputs}->{$item}->{conn} =~ /\{(.*)\}/) {
                my $conn = $1;
                foreach my $tmp (split /,/, $conn) {
                    $tmp =~s/\s//g;
                    if ($tmp =~ /^(\w+)/) {
                        push @{ $self->{top}->{instances}->{$inst_name}->{inputs}->{$item}->{nets} }, $1;
                    } else {
                        croak "There is something wrong with $tmp in $conn";
                    }
                }        
            } else {
                croak "This branch must be {bus2[21:0], bus3[3:1],bus4} alike";
            }
            
            my $width = $self->{top}->{instances}->{$inst_name}->{inputs}->{$item}->{width};
            $self->check_combination($self->{top}->{instances}->{$inst_name}->{inputs}->{$item}->{conn}, $width);
        }
    }
    #outputs
    foreach my $item (keys %{ $self->{top}->{instances}->{$inst_name}->{outputs} }) {
        #bus0
        if ($self->{top}->{instances}->{$inst_name}->{outputs}->{$item}->{conn} =~/^\w+$/ ) {
            my $net = $&;
            push @{ $self->{top}->{instances}->{$inst_name}->{outputs}->{$item}->{nets} }, $net;
            my $mod_name = $self->{top}->{instances}->{$inst_name}->{mod_name};

            if (defined $self->{top}->{nets}->{$net}) {
                if ($self->{top}->{nets}->{$net}->{width} != $self->{top}->{instances}->{$inst_name}->{outputs}->{$item}->{width}) {
                    croak "Known width for net $net is $self->{top}->{nets}->{$net}->{width}, but the newly added one is $self->{top}->{instances}->{$inst_name}->{outputs}->{$item}->{width}";
                }
                #print "if output item = $item\n";
                
            }
            else {
                defined ($mod_name) or croak "instance $inst_name must is a known module";
                $self->{top}->{nets}->{$net}->{width} = $self->{top}->{instances}->{$inst_name}->{outputs}->{$item}->{width};
                #print "else output item = $item\n";
                #print "net $net: width = $self->{top}->{nets}->{$net}->{width}\n";
                
            }
        }
        #bus0[11:2] or bus0[1] must not occur in outputs
        elsif ($self->{top}->{instances}->{$inst_name}->{outputs}->{$item}->{conn} =~/^(\w+)\[(\d+)(\:\d+)?\]$/) {
            croak "outputs must not partly connect";
        }
        #11'b1, 4'd10, 9'h1 must not occur in outputs
        elsif ($self->{top}->{instances}->{$inst_name}->{outputs}->{$item}->{conn} =~/^(\d+)\'[bdh](\w+)$/) {
            croak "outputs must not tie 0 or 1";
        }
        #output float
        elsif ($self->{top}->{instances}->{$inst_name}->{outputs}->{$item}->{conn} =~/^$/) {
               
        }
        else {
            croak "Unexpected branch happens, conn info: $self->{top}->{instances}->{$inst_name}->{outputs}->{$item}->{conn}";
        }
    }
}

sub check_combination {
    my $self = shift;
    my ($conn, $all_width) = @_;

    my $net;
    my $width;
    
    if ($conn =~ /\{.*\}/) {
        $conn =~s/\{//g;
        $conn =~s/\}//g;
        my @arr = split(/\,/,$conn);
        my $left_width = $all_width;
        foreach my $item (@arr) {
            $item =~s/\s//g;
            if ($item =~ /^\w+$/) {
                #bus4 must be known already
                if (defined $self->{top}->{nets}->{$item}) {
                    $left_width = $left_width - $self->{top}->{nets}->{$item}->{width};
                }
                else {
                    croak "$item in combination is unknown";
                }
            }
            elsif ($item =~ /^(\w+)\[(\d+)\:(\d+)\]$/) {
                $net = $1;
                my $high = $2;
                my $low = $3;
                if (defined $self->{top}->{nets}->{$item}) {
                    $width = $self->{top}->{nets}->{$item};
                    croak "net $item is known to be $width bits wide, but the highest bit of net newly added is $high" unless ($width >= $high + 1);
                    $left_width = $left_width - ($high - $low + 1);
                }
                else {
                    $left_width = $left_width - ($high - $low + 1);
                }   
            }
            elsif ($item =~ /^(\w+)\[(\d+)\]$/) {
                $net = $1;
                my $pos = $2;
                if (defined $self->{top}->{nets}-{$item}) {
                    $width = $self->{top}->{nets}->{$item};
                    croak "net $item is known to be $width bits wide, but the highest bit of net newly added is $pos" unless ($width >= $pos + 1);
                    $left_width = $left_width - 1;
                }
                else {
                    $left_width = $left_width - 1;
                }
            }
        }
    }
    else {
        croak "conn must be {bus2[21:10], bus3[3:1], bus4} alike, but actually is $conn";
    }
}

sub add_port {
    my $self = shift;
    my ($type, $port_name) = @_;

    if ($port_name =~ /^(\w+)(\[\d+\:\d+\])?$/) { #bus0[5:0] or bus0
        my $name = $1;
        my $range;
        if (defined $2) {
            $range = $2; #[5:0]
            $range =~s/\(//g;
            $range =~s/\)//g; #5:0
        } else {
            $range = "determine";
        }
        
        #update add_ports
        if (defined $self->{add_ports}->{$name}) {
            croak "port $name is already in add_ports";
        }
        
        if ($type eq "input") {
            $self->{add_ports}->{$name}->{type} = "input";
        } elsif ($type eq "output") {
            $self->{add_ports}->{$name}->{type} = "output";
        } else {
            croak "add_port type can not be input or output";
        }
        
        $self->{add_ports}->{$name}->{range} = $range; #5:0 or "determine"
    } else {
        croak "add ports failed, $port_name does not obey the rule: bus0[5:0] or bus0";
    }   
}

sub conn {
    my $self = shift;
    my $port;
    my $net;
    my $inst;
    
    #update top nets
    #iterate each instances
    foreach $inst (keys %{ $self->{top}->{instances} }) {
        foreach $port (keys %{ $self->{top}->{instances}->{$inst}->{inputs} }) {
            foreach $net ( @{ $self->{top}->{instances}->{$inst}->{inputs}->{$port}->{nets} } ) {
                if (! defined $self->{top}->{nets}->{$net}) {
                    croak "$net can not be found in the top nets";
                }
                push @{ $self->{top}->{nets}->{$net}->{dest} } , "$inst\.$port";
            }
        }
        foreach $port (keys %{ $self->{top}->{instances}->{$inst}->{outputs} }) {
            foreach $net ( @{ $self->{top}->{instances}->{$inst}->{outputs}->{$port}->{nets} } ) {
                if (! defined $self->{top}->{nets}->{$net}) {
                    croak "$net can not be found in the top nets";
                }
                push @{ $self->{top}->{nets}->{$net}->{src} } , "$inst\.$port";
            }
        }    
    }

    #gen inputs and outputs of top
    foreach $net (keys %{ $self->{top}->{nets} }) {
        if (! defined $self->{top}->{nets}->{$net}->{src}) {
            $self->{top}->{inputs}->{$net}->{width} = $self->{top}->{nets}->{$net}->{width}; 
        }
        if (! defined $self->{top}->{nets}->{$net}->{dest}) {
            $self->{top}->{outputs}->{$net}->{width} = $self->{top}->{nets}->{$net}->{width}; 
        }
    }
    #add_ports
    foreach my $add_port (keys %{ $self->{add_ports} }) {
        my $already_is_port = 0;
        #check whether in top inputs and outputs
        foreach $port (keys %{ $self->{top}->{inputs} }) {
            if ($add_port eq $port) {
                $already_is_port = 1;
                print "WARNING: $add_port is already the input of top.\n";
            }
        }
        foreach $port (keys %{ $self->{top}->{outputs} }) {
            if ($add_port eq $port) {
                $already_is_port = 1;
                print "WARNING: $add_port is already the output of top.\n";
            }
        }
        if ($already_is_port == 0) {
            if ($self->{add_ports}->{$add_port}->{type} eq "input") {
                if ($self->{add_ports}->{$add_port}->{range} eq "determine") {
                    $self->{top}->{inputs}->{$add_port}->{width} = 1;
                } else {
                    $self->{top}->{inputs}->{$add_port}->{width} = $self->range_to_width($self->{add_ports}->{$add_port}->{range});
                }
            } else { #output
                if ($self->{add_ports}->{$add_port}->{range} eq "determine") {
                    if (defined $self->{top}->{nets}->{$add_port}) {
                        $self->{top}->{outputs}->{$add_port}->{width} = $self->{top}->{nets}->{$add_port}->{width};
                    } else {
                        $self->{top}->{outputs}->{$add_port}->{width} = 1;
                    }
                }
            }
        }
    }
}

sub add_code {
    my $self = shift;
    my ($code, $pos) = @_;
    if ((! defined $pos) or ($pos == 0)) {
        push @{ $self->{top}->{tail_code} }, $code;
    } elsif ($pos == 1) {
        push @{ $self->{top}->{head_code} }, $code;
    } else {
        croak "pos can only be set 0 or 1 : $!";
    }
}

sub write_file {
    my $self = shift;
    my ($file) = @_;
    my $toolscr = $ENV{'TOOLSCR'};
    my $tpl = "top_vconn.tt";
    my $out_fh = gensym;

    my $dir = dirname($file);
    mkdir $dir unless (-e $dir);
    open($out_fh, ">$file") or croak "Can not write file $file!: $!";
    my @out;
    pipe(READER, WRITER) or croak "pipe no good: $!";
    my $pid = fork();

    croak "Can not fork: $!" unless defined $pid;

    if($pid) {
        #parent
        close WRITER;
        while(<READER>) {
            push @out, $_;
        }
        close READER;
    }
    else {
        #child
        close READER;
        open STDOUT, ">&WRITER";

        my $tt = Template->new({
            INCLUDE_PATH => "$toolscr/tpl",
            INTERPOLATE => 1,
            OUTLINE_TAG => ';',
        }) || croak "$Template::ERROR\n";

        $tt->process("$tpl", $self)
            || croak $tt->error(), "\n";

        close WRITER;

        exit 0;
    }

    foreach (@out) {
        print $out_fh "$_";
    }
        
    close $out_fh;
}

sub write_out {
    my $self = shift;
    my $tpl = "top_vconn.tt";
    my $out_fh = gensym;

    my $tt = Template->new({
        INCLUDE_PATH => "./",
        INTERPOLATE => 1,
        OUTLINE_TAG => ';',
    }) || croak "$Template::ERROR\n";

    $tt->process("$tpl", $self)
        || croak $tt->error(), "\n";

}

sub range_to_width {
    my $self = shift;
    my ($range, $parameters_ref) = @_;
    my $tmp1;
    my $tmp2;
    my $width = 1;
    if ($range =~ /(.*):(.*)/) {
        $tmp1 = $1;
        $tmp2 = $2;
        $tmp1 = $self->replace_parameter($tmp1, $parameters_ref);
        $tmp2 = $self->replace_parameter($tmp2, $parameters_ref);
        
        $width = eval($tmp1) - eval($tmp2) +1;
    }
    $width;
}

sub replace_parameter {
    my $self = shift;
    my ($var, $parameters_ref) = @_;
    #print "in replace func\n";
    #print Dumper($var);
    #sort by length, because N are contained by MN, so replace MN first
    foreach (sort {length($b)<=>length($a)} keys(%{$parameters_ref})) {
        my $key = $_;
        my $value = $parameters_ref->{$key};
        if ($var =~ /$key/) {
            $var =~s/$key/$value/g;
            $var = $self->replace_parameter($var, $parameters_ref);
        }
    }
    #print "out of replace func\n";
    return $var;
}

sub print_debug {
    my ($self) = shift;
    my ($var) = @_;
    
    print Dumper($self->{$var});
}

sub param_preprocess {
    my ($self) = shift;
    my ($param) = @_;
    my $tmp;
    if ($param =~m/(\d+)?\'b(\d+)/i) {
        $tmp = oct "0b"."$2";
        $param =~ s/(\d+)?\'b(\d+)/$tmp/;
        $param = $self->param_preprocess($param);
    } elsif ($param =~m/(\d+)?\'h(\w+)/i) {
        $tmp = hex "0x"."$2";
        $param =~ s/(\d+)?\'h(\w+)/$tmp/;
        $param = $self->param_preprocess($param);
    } else {
        return $param;
    }
}
    
1;
