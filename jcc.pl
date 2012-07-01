#! /usr/bin/perl

use Switch;

$endl = "\n";

%keywords = (
        'class'                 =>      1,
        'constructor'           =>      1,
        'function'              =>      1,
        'method'                =>      1,
        'field'                 =>      1,
        'static'                =>      1,
        'var'                   =>      1,
        'int'                   =>      1,
        'char'                  =>      1,
        'boolean'               =>      1,
        'void'                  =>      1,
        'true'                  =>      1,
        'false'                 =>      1,
        'null'                  =>      1,
        'this'                  =>      1,
        'let'                   =>      1,
        'do'                    =>      1,
        'if'                    =>      1,
        'else'                  =>      1,
        'while'                 =>      1,
        'return'                =>      1,
);

%symbols = (
        '{'     =>      1,
        '}'     =>      1,
        '('     =>      1,
        ')'     =>      1,
        '['     =>      1,
        ']'     =>      1,
        '.'     =>      1,
        ','     =>      1,
        ';'     =>      1,
        '+'     =>      1,
        '-'     =>      1,
        '*'     =>      1,
        '/'     =>      1,
        '&'     =>      1,
        '|'     =>      1,
        '<'     =>      1,
        '>'     =>      1,
        '='     =>      1,
        '~'     =>      1,
);

%binaryOps = (
        '+'             =>      'add',
        '-'             =>      'sub',
        '*'             =>      'call Math.multiply 2',
        '/'             =>      'call Math.divide 2',
        '&amp;'         =>      'and',
        '|'             =>      'or',
        '&lt;'          =>      'lt',   
        '&gt;'          =>      'gt',
        '='             =>      'eq',
);

%unaryOps = (
        '-'     =>      'neg',
        '~'     =>      'not',
);

sub compileClass {
        %cscope = ();
        $static_index = 0, $field_index = 0;
        start_nt('class');
        transfer();                                                     # 'class'
        $current_class =  peek_value();
        transfer(undef, 'class', undef, 1);     # className
        transfer();                                                     # '{'
        compileClassVarDec();
        compileSubroutineDec();
        transfer();                                                     # '}'
        end_nt('class');
}

sub add_to_scope {
        my ($scope_ref, $v_name, $type, $kind, $index) = @_;
        $scope_ref->{$v_name}{'type'}   = $type;
        $scope_ref->{$v_name}{'kind'}   = $kind;
        $scope_ref->{$v_name}{'index'}  = $index;
}
sub compileClassVarDec {
        my $token = shift(@tokens);
        unless ($token =~ m/static/ || $token =~ m/field/) {
                unshift(@tokens, $token);
                return;
        }
        my $index_ref = $token =~ m/static/ ? \$static_index : \$field_index;
        start_nt('classVarDec');
        my $kind = det_token_value($token);
        tpush($token);                                                                  # 'static' || 'field'
        my $type = peek_value();
        transfer();                                                                             # type
        add_to_scope(\%cscope, peek_value(), $type, $kind, $$index_ref);
        transfer($type, $kind, $$index_ref++, 1);               # varName
        while(peek_value() eq ',') {
                transfer();                                                                     # ','
                add_to_scope(\%cscope, peek_value(), $type, $kind, $$index_ref);
                transfer($type, $kind, $$index_ref++, 1);       # varName
        }
        transfer();                                                                             # ';'
        end_nt('classVarDec');
        compileClassVarDec();   
}

sub compileSubroutineDec {
        my $token = shift(@tokens);
        unless ($token =~ m/constructor/ || $token =~ m/function/ || $token =~ m/method/) {
                unshift(@tokens, $token);
                return;
        }
        $subr_type = det_token_value($token);
        %sscope = ();
        start_nt('subroutineDec');
        tpush($token);                                                          # 'constructor' || 'function' || 'method'
        transfer();                                                                     # 'void' || type
        $cur_sub                = peek_value();
        transfer(undef, 'subroutine', undef, 1);        # subroutineName
        transfer();                                                                     # '('
        compileParameterList(); 
        transfer();                                                                     # ')'
        compileSubroutineBody($subr_type);
        end_nt('subroutineDec');
        compileSubroutineDec();
}

sub compileParameterList {
        if (peek_value() eq ')') {
                start_nt('parameterList');
                end_nt('parameterList');
                return;
        }       
        my $arg_index;
        if ($subr_type eq 'method') {
                $arg_index = 1;
        } else {
                $arg_index = 0;
        }
        start_nt('parameterList');
        my $type = peek_value();
        transfer();                                                                                     # type
        add_to_scope(\%sscope, peek_value(), $type, 'argument', $arg_index);
        my $pv = peek_value();
        transfer($type, 'argument', $arg_index++, 1);           # varName
        while (peek_value() eq ',') {
                transfer();                                                                             # ','
                $type = peek_value();
                transfer();                                                                             # type
                add_to_scope(\%sscope, peek_value(), $type, 'argument', $arg_index);
                transfer($type, 'argument', $arg_index++, 1);   # varName
        }
        end_nt('parameterList');
}

sub compileSubroutineBody {
        my ($subr_type) = @_;
        start_nt('subroutineBody');
        transfer();                             # '{'
        $if_label               = 0;
        $while_label    = 0;
        my $var_index   = 0;
        compileVarDec(\$var_index);
        vm("function $current_class\.$cur_sub $var_index");     
        if ($cur_sub eq 'new' && $subr_type ne 'function') {
                #push length
                my $bytes = 0;
                foreach (keys %cscope) {
                        if ($cscope{$_}{'kind'} eq 'field') {
                                $bytes++        
                        }
                }
                vm("push constant $bytes");
                vm("call Memory.alloc 1");      
                vm('pop pointer 0');
        } else {
                unless ($subr_type eq 'function') {
                        vm('push argument 0');
                        vm('pop pointer 0');
                }
        }
        compileStatements();
        transfer();                             # '}'
        end_nt('subroutineBody');
}

sub compileVarDec {
        my ($index_ref) = @_;
        unless (peek_value() eq 'var') {
                return;
        }
        start_nt('varDec');
        transfer();                                                                             # 'var'
        my $type = peek_value();
        transfer();                                                                             # type
        add_to_scope(\%sscope, peek_value(), $type, 'local', $$index_ref);
        transfer($type, 'local', $$index_ref++, 1);             # varName
        while (peek_value() eq ',') {
                transfer();                                                                     # ','
                add_to_scope(\%sscope, peek_value(), $type, 'local', $$index_ref);
                transfer($type, 'local', $$index_ref++, 1);     # varName
        }
        transfer();                                                                             # ';'
        end_nt('varDec');
        compileVarDec($index_ref);
}

sub compileStatements {
        start_nt('statements');
        my $token = peek();
        while(isStatement($token)) {
                switch(det_token_value($token)) {
                        case 'while'    {compileWhileStatement()}
                        case 'if'               {compileIfStatement()}
                        case 'return'   {compileReturnStatement()}
                        case 'let'              {compileLetStatement()}
                        case 'do'               {compileDoStatement()}
                }
                $token = peek();
        }
        end_nt('statements');
}

sub compileWhileStatement {
        my $label_index = $while_label++;
        start_nt('whileStatement');
        transfer();                     # 'while'
        transfer();                             # '('
        vm("label WHILE_EXP$label_index");
        compileExpression();
        vm("not");
        vm("if-goto WHILE_END$label_index");
        transfer();                             # ')'
        transfer();                             # '{'
        compileStatements();
        vm("goto WHILE_EXP$label_index");
        transfer();                             # '}'
        vm("label WHILE_END$label_index");
        end_nt('whileStatement');
}

sub compileIfStatement {
        my $label_index = $if_label++;
        start_nt('ifStatement');
        transfer();                     # 'if'
        transfer();                             # '('
        compileExpression();
        vm("if-goto IF_TRUE$label_index");
        vm("goto IF_FALSE$label_index");
        transfer();                             # ')'
        transfer();                             # '{'
        vm("label IF_TRUE$label_index");
        compileStatements();
        transfer();                             # '}'
        if (peek_value() eq 'else') {
                vm("goto IF_END$label_index");
                vm("label IF_FALSE$label_index");
                transfer();                     # 'else'
                transfer();                     # '{';
                compileStatements();
                vm("label IF_END$label_index");
                transfer();                     # '}'
        } else {
                vm("label IF_FALSE$label_index");
        }
        end_nt('ifStatement');
}

sub compileReturnStatement {
        start_nt('returnStatement');
        transfer();                             # 'return'
        if (peek_value() eq ';') {
                vm('push constant 0');
        } else {
                compileExpression();
        }
        transfer();                             # ';'
        end_nt('returnStatement');
        vm('return');
}

sub compileLetStatement {
        start_nt('letStatement');
        transfer();                                                                                                             # 'let'
        my $var = peek_value();
        unless (defined $cscope{$var} || defined $sscope{$var}) {
                print "Unknown variable: $var\n";
        }
        my $sref = defined $cscope{$var} ? \%{$cscope{$var}} : \%{$sscope{$var}};
        transfer($sref->{'type'}, $sref->{'kind'}, $sref->{'index'}, 0);# varName
        my $array = 0;
        if (peek_value() eq '[') {
                $array = 1;
                transfer();                                                                                                                                     # '['
                compileExpression();
                if (defined $cscope{$var}) {
                        if ($sref->{'kind'} eq 'static') {
                                vm("push static $sref->{'index'}");
                        } else {
                                vm("push this $sref->{'index'}");
                        }
                } else {
                        vm("push $sref->{'kind'} $sref->{'index'}");
                }
                vm('add');
                transfer();                                                                                                                                     # ']'
        }
        transfer();                                                                                                                                             # '='
        compileExpression();
        if ($array) {
                vm('pop temp 0');
                vm('pop pointer 1');
                vm('push temp 0');
                vm('pop that 0');
        } else {
                if (defined $cscope{$var}) {
                        if ($sref->{'kind'} eq 'static') {
                                vm("pop static $sref->{'index'}");
                        } else {
                                vm("pop this $sref->{'index'}");
                        }
                } else {
                        vm("pop $sref->{'kind'} $sref->{'index'}");
                }
        }
        transfer();                                                                                                                                             # ';'
        end_nt('letStatement');
}

sub compileDoStatement {
        start_nt('doStatement');
        transfer();                             # 'do'
        compileCall();
        transfer();                             #  ';'
        end_nt('doStatement');
        # return value cleanup
        vm('pop temp 0');
}

sub compileExpression {
        start_nt('expression');
        #variable, constant or unary op
        compileTerm();
        while (isBinaryOp(peek())) {
                my $op = peek_value();
                transfer();                     # op
                compileTerm();
                vm($binaryOps{$op});
        }
        end_nt('expression');
}

sub compileTerm {
        start_nt('term');
        if (isUnaryOp(peek())) {
                my $op = peek_value();
                transfer();                     # '-' or '~'
                compileTerm();
                vm($unaryOps{$op});
                goto RETURN;
        }
        if (peek_value() eq '(') {
                transfer();                     # '('
                compileExpression();
                transfer();                     # ')'
                goto RETURN;
        }
        if (peek_value(1) eq '(' || peek_value(1) eq '.') {
                compileCall();
                goto RETURN;
        }
        if (peek_type() eq 'identifier') {
                my $var = peek_value();
                unless (defined $cscope{$var} || defined $sscope{$var}) {
                        print "Unknown variable during compileTerm: $var\n";
                }
                my $sref = defined $cscope{$var} ? \%{$cscope{$var}} : \%{$sscope{$var}};
                transfer($sref->{'type'}, $sref->{'kind'}, $sref->{'index'},  0);       # varName || arrayName
                if (peek_value() eq '[') {
                        transfer();             # '['
                        compileExpression();

                        if (defined $cscope{$var} && $sref->{'kind'} ne 'static') {
                                vm("push this $sref->{'index'}");
                        } else {
                                vm("push $sref->{'kind'} $sref->{'index'}");
                        }
                        vm('add');
                        vm('pop pointer 1');
                        vm('push that 0');
                        transfer();             # ']'
                } else {
                        if (defined $cscope{$var} && $sref->{'kind'} ne 'static') {
                                vm("push this $sref->{'index'}");
                        } else {
                                vm("push $sref->{'kind'} $sref->{'index'}");
                        }
                }
                goto RETURN;
        }
        # integerConstant || stringConstant || keywordConstant
        my $val = peek_value();
        switch($val) {
                case 'true' {
                        vm('push constant 0');
                        vm('not');
                }
                case 'false' {
                        vm('push constant 0');
                }
                case 'this' {
                        vm('push pointer 0');
                }
                case 'null' {
                        vm('push constant 0');
                }
                else {
                        if (peek_type() eq 'stringConstant') {
                                my $len = length($val);
                                vm("push constant $len");
                                vm('call String.new 1');
                                my $i;
                                for ($i = 0; $i < $len; $i++) {
                                        my $c = ord(substr($val, $i, 1));
                                        vm("push constant $c");
                                        vm('call String.appendChar 2');
                                }
                        } else {
                                vm("push constant $val");
                        }
                }
        }
        transfer();
        RETURN:
        end_nt('term');
}

sub compileExpressionList {
        start_nt('expressionList');
        my $args = 0;
        if (peek_value() ne ')') {
                compileExpression();
                $args++;
                while (peek_value() eq ',') {
                        transfer();                     # ','
                        compileExpression();    
                        $args++;
                }       
        }
        end_nt('expressionList');
        return $args;
}

sub compileCall {
        my $callee = '';
        my $sr;
        my $inc = 0;
        if (peek_value(1) ne '.') {
                # do f();
                vm('push pointer 0');
                $inc++;
                $callee = $current_class.'.'.peek_value();
                transfer(undef, 'subroutine', undef, 0);        # subroutineName || varName || className
        } else {
                my $pv = peek_value();
                if (defined $cscope{$pv} || defined $sscope{$pv}) {
                        # do a.f();
                        $sr = defined $cscope{$pv} ? \%{$cscope{$pv}} : \%{$sscope{$pv}};
                        $callee = "$sr->{'type'}\.";
                        transfer($sr->{'type'}, $sr->{'kind'}, $sr->{'index'}, 0);
                        if (defined $sscope{$pv}) {
                                vm("push $sr->{'kind'} $sr->{'index'}");
                        } else {
                                vm("push this $sr->{'index'}");
                        }
                        $inc++;
                } else {
                        # do A.f();
                        transfer(undef, 'class', undef, 0);     #class  
                        $callee = "$pv\.";
                }
        }
        if (peek_value() eq '.') {
                transfer();                                     # '.'
                $callee .= peek_value();
                transfer(undef, 'subroutine', undef, 0);        # subroutineName
        }
        transfer(); # '('
        if ($callee eq 'new') {
                vm('push constant 0');
        }
        my $args = compileExpressionList();
        $args += $inc;
        vm("call $callee $args");
        transfer(); # ')'               
}

sub vm {
        my ($row) = @_;
        print VMF $row."\n";
}

sub peek {
        my ($two_steps) = @_;
        my $token = shift(@tokens);
        if ($two_steps) {
                my $token2 = shift(@tokens);
                unshift(@tokens, $token2);
                unshift(@tokens, $token);
                return $token2;
        }
        unshift(@tokens, $token);
        return $token;
}

sub peek_value {
        my ($two_steps) = @_;
        return det_token_value(peek($two_steps));
}

sub peek_type {
        return det_token_type(peek());
}

sub isStatement {
        my $val = det_token_value($_[0]);
        return ($val eq 'let' || $val eq 'if' || $val eq 'while' || $val eq 'do' || $val eq 'return');
}

sub isBinaryOp {
        my $val = det_token_value($_[0]);
        if (defined $binaryOps{$val}) {
                return 1;
        }
        return 0;
}

sub isUnaryOp {
        my $val = det_token_value($_[0]);
        if (defined $unaryOps{$val}) {
                return 1;
        }
        return 0;
}

sub det_token_type {
        my ($row) = @_;
        if ($row =~ m/<(\w+)> (.*?) <\/\1>/) {
                return $1;      
        }
}

sub det_token_value {
        my ($row) = @_;
        if ($row =~ m/<(\w+)> (.*?) <\/\1>/) {
                return $2;      
        }
}

sub tpush {
        my ($token) = @_;
        for (my $i = 0; $i < $tabs; $i++) {
                $token = '  '.$token;
        }
        push(@result, $token);
}

sub transfer {
        my ($type, $kind, $index, $dec) = @_;
        unless (defined $type) {
                $type = '';
        }
        unless (defined $index) {
                $index = '';
        }
        my $token = shift @tokens;
        if ($kind) {
                if ($token =~ m/^(.*?)>(.*)$/) {
                        my ($left, $right) = ($1, $2);
                        $left .= " type='$type' kind='$kind' index='$index' dec=$dec";
                        $token = $left.'>'.$right;
                }
        }
        tpush($token);
}

sub start_nt {
        my ($token) = @_;
        $token = '<'.$token.'>';
        tpush($token);
        $tabs++;
}

sub end_nt {
        my ($token) = @_;
        $token = '</'.$token.'>';
        $tabs--;
        tpush($token);
}

sub compile {
        my ($file) = @_;
        @tokens = ();
        my $file_name, $dir;
        if ($file =~ m/^(.*?)([^\/\.]+\.xml)/) {
                ($dir, $file_name) = ($1, $2);
        }
        open (FH, $dir.'output/'.$file_name) || die $!;

        while (my $str = <FH>) {
                if ($str =~ m/<(\w+)> (.*?) <\/\1>/) {
                        chomp($str);
                        push(@tokens, $str);
                }
        }
        close FH;

        $file_name =~ s/T\.xml$/\.vm/;
        open(VMF, '>'.$dir.'output/'.$file_name) || die $!;
        compileClass();
        close VMF;

        $file_name =~ s/\.vm$/\.xml/;
        open (OFH, '>'.$dir.'output/'.$file_name) || die $!;
        foreach(@result) {
                print OFH "$_$endl";
        }
        close OFH;
        @result = ();
}

sub tokenize {
        my ($file) = @_;
        my $file_name, $dir;
        if ($file =~ m/^(.*?)([^\/\.]+\.jack)/) {
                ($dir, $file_name) = ($1, $2);
        }
        open (FH, "$dir$file_name") || die $!;

        mkdir ($dir.'output');
        $file_name =~ s/\.jack$/T\.xml/;
        open (OFH, '>'.$dir.'output/'.$file_name) || die $!;
        print OFH "<tokens>$endl";
        my $buffer;
        while (my $str = <FH>) {
                $str =~ s/\/\/.*$//;
                if ($str =~ m/^(.*)(".*")(.*)$/) {
                        my ($beg, $mid, $end) = ($1, $2, $3);
                        $mid =~ s/\s/_/g;
                        $str = $beg.$mid.$end;
                } else {
                        $str =~ s/(\w)\(/\1 \(/g;
                }

                $buffer .= $str;
        }
        $buffer =~ s/\s{2,}/ /g;
        $buffer =~ s/\/\*.*?\*\///g;
        $buffer =~ s/([^\s]);/\1 ;/g;
        $buffer =~ s/^\s+//;
        $buffer =~ s/\s+$//;
        $buffer =~ s/\n//g;
        $buffer =~ s/\r//g;
        my @rows = split(/ /, $buffer);
        close FH;       
        
        foreach (@rows) {
                my $row = $_;
                while ($row =~ m/./) {
                        my $token, $type;
                        eat_token(\$row, \$token, \$type);
                        print OFH "<$type> $token </$type>$endl";
                }
        }
        print OFH "</tokens>$endl";
        close OFH;
}

sub set_indicators {
        my ($token) = @_;
        if ($token eq ';')                      { $var_dec              = 0; $field_dec = 0; $static_dec = 0 }
        if ($token eq 'var')                    { $var_dec              = 1; }
        if ($token eq 'class')                  { $class_dec    = 1;}
        if ($token eq '{')                      { $class_dec    = 0; }
        if ($token eq 'function')               { $function_dec = 1; }
        if ($token eq 'constructor')            { $function_dec = 1; $constructor_dec = 1; }
        if ($token eq 'field')                  { $field_dec    = 1; }
        if ($token eq ')')                      { $argument_dec = 0; }
        if ($token eq 'static')                 { $static_dec   = 1; }

        if ($token eq '(') {
                if ($function_dec) { $argument_dec = 1; }
                $function_dec = 0; $constructor_dec = 0;
        }
}

sub eat_token {
        my ($row_ref, $token_ref, $type_ref) = @_;
        my @charr = split("", $$row_ref);

        set_indicators($$row_ref);
        if ($$row_ref =~ m/^"(.*?)"(.*)$/) {
                $$row_ref       = $2;
                $$token_ref     = $1;
                $$token_ref =~ s/_/ /g;
                $$type_ref      = 'stringConstant';
                return;
        }
        
        if (defined $symbols{$charr[0]}) {
                $$row_ref       =~ s/^.//;
                $$token_ref = $charr[0];
                if ($$token_ref eq '<') {$$token_ref = '&lt;'}
                if ($$token_ref eq '>') {$$token_ref = '&gt;'}
                if ($$token_ref eq '"') {$$token_ref = '&quot;'}
                if ($$token_ref eq '&') {$$token_ref = '&amp;'}
                $$type_ref      = 'symbol';
                return;
        }

        if ($$row_ref =~ m/^([a-zA-Z_][\w_]*)(.*)$/) {
                $$row_ref       = $2;
                $$token_ref     = $1;
                $$type_ref      = 'identifier';

                my $opening_bracket_next = 0;
                if ($$row_ref =~ m/^\(/) {
                        $opening_bracket_next = 1;
                }

                if (defined $keywords{$$token_ref}) {
                        $$type_ref      = 'keyword';
                }
                return;
        }
        
        if ($$row_ref =~ m/^(\d+)(.*)$/) {
                $$row_ref       = $2;
                $$token_ref = $1;
                $$type_ref      = 'integerConstant';
                return;
        }
        print "Unrecognized syntax: '$$row_ref'$endl";
        exit;
}
###################################################################
foreach (@ARGV) {
        my $fod = $_;
        if ($fod =~ m/jack$/) {
                push(@files, $fod);
        } else {
                if ($fod =~ m/\.\w/) {
                        print "Wrong file extension: $fod$endl";
                        exit;
                } else {
                        my @dir = glob("./$fod/*");
                        foreach(@dir) {
                                if ($_ =~ m/jack$/) {
                                        push(@files, $_);
                                        $_ =~ s/\.jack/T\.xml/;
                                        push(@tfiles, $_);
                                }
                        }
                }
        }
}

foreach (@files) {
        tokenize($_);
}

foreach (@tfiles) {
        compile($_);
}
