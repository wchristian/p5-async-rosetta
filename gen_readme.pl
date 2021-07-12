use strictures;
use IO::All -binary;
use Text::Diff;

run();

sub run {
    io->dir("diffs")->rmtree;
    io->dir("diffs")->mkdir;

    my $readme_text = io("README.md")->all;
    $readme_text =~ s/(?<=# Comparison Matrices).*//s;

    my @base_combos = ( [] => [qw( curry )] => [qw( curry F-outer )] =>
          [qw( curry F-total )] => [qw( curry F-total AA)] );
    my @ia_combos = map [ "iA", $_->@* ], @base_combos;
    my @ae_combos = map [ "AE", $_->@* ], @base_combos;

    io("README.md")->print($_)
      for join "\n\n",
      $readme_text,
      make_table( iA => iA => \@ia_combos, \@ia_combos ),
      make_table( AE => AE => \@ae_combos, \@ae_combos ),
      make_table( iA => AE => \@ia_combos, \@ae_combos );

    return;
}

sub sep_line { "| " . join( " | ", ("---"), (":---:") x (@_) ) . " |" }

sub make_table {
    my ( $from_e, $to_e, $from, $to ) = @_;

    my $same_engine = $to_e eq $from_e;

    $to   = [ $to->@[ 1 .. $#{$to} ] ]         if $same_engine;
    $from = [ $from->@[ 0 .. $#{$from} - 1 ] ] if $same_engine;

    my @table_lines = (
        "## " .    #
          ( $same_engine ? "$from_e Upgrades" : "Comparison $from_e to $to_e" ),
        "",
    );

    for my $line ( 0 .. 3 ) {
        my @heads =    #
          map sprintf( "% 8s", $_ ), map $_ ? "**$_**" : "", map $_->[$line],  #
          [], $to->@*;
        $heads[0] = "From -> To" if !$line;
        push @table_lines, "| " . join( " | ", @heads ) . " |";
        next if $line;
        push @table_lines, sep_line( $to->@* );
    }

    my $main_counter = 0;
    for my $combo ( $from->@* ) {
        $main_counter++;
        my $main_name = join " + ", $combo->@*;
        my $main_file = "rosetta - $main_name.t";
        $main_name =~ s/ //g;
        my @elements    = ("**$main_name**");
        my $sub_counter = 0;
        for my $sub_combo ( $to->@* ) {
            $sub_counter++;
            my $sub_file = "rosetta - " . join( " + ", $sub_combo->@* ) . ".t";
            if ( $main_file eq $sub_file
                or ( $same_engine and $sub_counter < $main_counter ) )
            {
                push @elements, "";
                next;
            }
            my $diff_name = "diffs/$main_file - $sub_file .txt";
            io($diff_name)->print($_) for diff [ io($main_file)->getlines ],   #
              [ io($sub_file)->getlines ],
              { STYLE => "Table", CONTEXT => 99999 };
            $diff_name =~ s/ /%20/g;
            my $text = $main_counter == $sub_counter ? "**DIFF**" : "DIFF";
            push @elements, "[ $text ]"                                        #
              . "(https://raw.githubusercontent.com/wchristian/p5-async-rosetta/main/$diff_name)";
        }
        push @table_lines, "| " . join( " | ", @elements ) . " |";
    }

    return join "\n", @table_lines;
}
