#!/usr/bin/perl
package IkiWiki::Plugin::mindmap;
use strict;
=head1 NAME

IkiWiki::Plugin::mindmap - simple mind-maps based on lists

=head1 VERSION

This describes version B<0.20130602> of IkiWiki::Plugin::mindmap

=cut

our $VERSION = '0.20130602';

=head1 DESCRIPTION

Ikiwiki mindmap plugin.
Base mind-maps on lists, cross-linked.
Depends on Graphviz plugin to display the maps as maps.

See plugins/contrib/mindmap for documentation.

=head1 PREREQUISITES

    IkiWiki
    IkiWiki::Plugin::graphviz

=head1 AUTHOR

    Kathryn Andersen (RUBYKAT)
    http://github.com/rubykat

=head1 COPYRIGHT

Copyright (c) 2013 Kathryn Andersen

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

use IkiWiki 3.00;
use Text::Wrap;
use YAML;

sub import {
	hook(type => "getsetup", id => "mindmap",  call => \&getsetup);
	hook(type => "filter", id => "mindmap", call => \&do_filter);

	IkiWiki::loadplugin("graphviz");
}

#---------------------------------------------------------------
# Hooks
# --------------------------------

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
}

sub do_filter (%) {
    my %params=@_;
    my $page = $params{page};

    my $page_file = $pagesources{$page} || return $params{content};
    my $page_type=pagetype($page_file);
    if (defined $page_type)
    {
        # Look for a "mindmap" list, and create a graphviz directive for it.
        $params{content} =~ s/\n[*]\s*mindmap\s*\((.*?)\)\n(.*?)\n\n/create_mindmap($page,$2,$1)/sieg;
        $params{content} =~ s/\n[*]\s*mindmap\n(.*?)\n\n/create_mindmap($page,$1)/sieg;
    }

    return $params{content};
} # do_filter

#---------------------------------------------------------------
# Private functions
# --------------------------------

my $DEBUG = '';

sub parse_lines ($$$$$$);

sub parse_lines ($$$$$$) {
    my $lines_ref = shift;
    my $terms_ref = shift;
    my $xref_ref = shift;
    my $inverted_ref = shift;
    my $prev_indent = shift;
    my $parent = shift;

    if (@{$lines_ref})
    {
        my @siblings = ();
        my $this_indent = 0;
        my $next_line = undef;
        my $next_indent = -1;

        my $this_line = (@{$lines_ref} ? $lines_ref->[0] : undef);
        my ($ws) = $this_line =~ /^( *)[^ ]/;
        $this_indent = length($ws);

        if ($this_indent < $prev_indent)
        {
            # higher-level list
            return ();
        }

        do {
            $this_line = shift @{$lines_ref};
 
            # Labels are going to be in double-quotes, so replace all double-quotes with single quotes
            $this_line =~ tr{"}{'};

            my ($term, $rest_of_line, $number) = listprefix($this_line);
            while ($rest_of_line =~ /\(See ([-\s\w]+)\)/)
            {
                my $xref = $1;
                $rest_of_line =~ s/\s*\(See [-\s\w]+\)\s*//;
                if (!$xref_ref->{$term})
                {
                    $xref_ref->{$term} = {};
                }
                if (!defined $xref_ref->{$term}->{$xref})
                {
                    $xref_ref->{$term}->{$xref} = 0;
                }
                $xref_ref->{$term}->{$xref}++;
            }
            while ($rest_of_line =~ /\(Ref ([-\s\w]+)\)/)
            {
                my $xref = $1;
                $rest_of_line =~ s/\s*\(Ref [-\s\w]+\)\s*//;
                if (!$xref_ref->{$xref})
                {
                    $xref_ref->{$xref} = {};
                }
                if (!defined $xref_ref->{$xref}->{$term})
                {
                    $xref_ref->{$xref}->{$term} = 0;
                }
                $xref_ref->{$xref}->{$term}++;
            }
            push @siblings, {term => $term,
                line => $rest_of_line,
                parent => $parent,
                number => $number};
            $terms_ref->{$term} = {
                line=>$rest_of_line,
            };
            $inverted_ref->{$term} = $parent;

            # count the number of leading spaces
            my ($ws) = $this_line =~ /^( *)[^ ]/;
            $this_indent = length($ws);

            $next_line = (@{$lines_ref} ? $lines_ref->[0] : undef);
            if ($next_line)
            {
                ($ws) = $next_line =~ /^( *)[^ ]/;
                $next_indent = length($ws);
            }
        } until (!$next_line
                 or $next_indent != $this_indent);

        # okay, no more siblings
        # next line must be (a) parent, (b) child, (c) empty

        if ($next_indent > $this_indent)
        {
            # next item is a child
            my @children = parse_lines($lines_ref, $terms_ref, $xref_ref, $inverted_ref, $this_indent, $siblings[$#siblings]->{term});
            $siblings[$#siblings]->{children} = \@children;
            return (@siblings, parse_lines($lines_ref, $terms_ref, $xref_ref, $inverted_ref, $this_indent, $parent));
        }
        else
        {
            # coming to the end of a sub-list
            return @siblings;
        }
    }
    return ();
} # parse_lines

sub listprefix ($)
{
    my $line = shift;

    my ($number, $term);
    my $rest_of_line = $line;
    my $fg = '';
    my $bg = '';

    my $bullets         = '*';
    my $bullets_ordered = '';
    my $number_match    = '(\d+|[^\W\d])';
    if ($bullets_ordered)
    {
        $number_match = '(\d+|[[:alpha:]]|[' . "${bullets_ordered}])";
    }
    return ('', $rest_of_line, 0)
      if ( !($line =~ /^\s*[${bullets}]\s+\S/)
        && !($line =~ /^\s*${number_match}[\.\)\]:]\s+\S/));

    if ($line =~ /^\s*${number_match}[\.\)\]:]\s+(\S.*)/)
    {
        $number = $1;
        $rest_of_line = $2;
    }
    $number = 0 unless defined($number);
    if (   $bullets_ordered
        && $number =~ /[${bullets_ordered}]/)
    {
        $number = 1;
    }

    if (!$number)
    {
        if ($line =~ /^(\s*[${bullets}].)\s*(.*)/)
        {
            $rest_of_line = $2;
        }
    }
    my $term_match = '(\w\w+)';
    if (!$term)
    {
        ($term)   = $rest_of_line =~ /^\s*${term_match}:/;
        $rest_of_line =~ s/^\s*${term_match}:\s*//;
    }

    if (!$term)
    {
        $term = $rest_of_line;
    }
    ($term, $rest_of_line, $number, $fg, $bg);
}    # listprefix

sub create_mindmap ($$;$) {
    my $page = shift;
    my $list_str = shift;

    my $params = (@_ ? shift : '');
    my %params;
    while ($params =~ m{
        (?:([-.\w]+)=)?		# 1: named parameter key?
        (?:
         """(.*?)"""	# 2: triple-quoted value
         |
         "([^"]*?)"	# 3: single-quoted value
         |
         '''(.*?)'''     # 4: triple-single-quote
         |
         <<([a-zA-Z]+)\n # 5: heredoc start
         (.*?)\n\5	# 6: heredoc value
         |
         (\S+)		# 7: unquoted value
        )
            (?:\s+|$)		# delimiter to next param
    }msgx) {
        my $key=$1;
        my $val;
        if (defined $2) {
            $val=$2;
            $val=~s/\r\n/\n/mg;
            $val=~s/^\n+//g;
            $val=~s/\n+$//g;
        }
        elsif (defined $3) {
            $val=$3;
        }
        elsif (defined $4) {
            $val=$4;
        }
        elsif (defined $7) {
            $val=$7;
        }
        elsif (defined $6) {
            $val=$6;
        }

        if (defined $key) {
            $params{$key} = $val;
        }
        else {
            $params{$val} = '';
        }
    }

    my $prog = (exists $params{'prog'} ? $params{'prog'} : 'dot');
    $params{top} = 'Mindmap' if !defined $params{top};
    $params{legend} = 'Map Legend' if !defined $params{legend};

    my $map =<<EOT;
[[!graph
prog=$prog
src="""
rankdir=LR;
node [ fontsize = 10 ];
edge [ color = grey30 ];
EOT
    my @lines       = split(/^/, $list_str);
    my %terms = ();
    my %xref = ();
    my %inverted = ();
    my @ret = parse_lines(\@lines, \%terms, \%xref, \%inverted, 0, '');
    my %legend = extract_legend(\@ret, \%terms, %params);
    apply_legend(\%terms, \%legend);
    my %derived = derive_xrefs(\%terms, \%inverted);
    $map .= start_map(\%terms);
    $map .= build_map_levels(\@ret, 0, %params);
    $map .= build_xrefs(\%xref, 'blue3');
    $map .= build_xrefs(\%derived, 'green3');

    $map .=<<EOT;
"""]]
EOT

    my $out = "\n\n" . $list_str . "\n\n" . $map . "\n\n";
    if ($DEBUG)
    {
        my $dump1 = Dump(\@ret);
        my $dump2 = Dump(\%legend);
        $out .= "<pre>\\$map\n\n$dump1\n\n$dump2</pre>\n\n";
    }
    return $out;
} # create_mindmap

sub derive_xrefs {
    my $terms_ref = shift;
    my $inverted_ref = shift;

    my %derived = ();

    # search for references to existing terms
    # inside other nodes
    # but don't link a child to a parent
    foreach my $term (sort keys %{$terms_ref})
    {
        foreach my $term2 (sort keys %{$terms_ref})
        {
            if ($term2 ne $term)
            {
                my $line = $terms_ref->{$term2}->{line};
                if ($line =~ /\b$term\b/i)
                {
                    if ($inverted_ref->{$term2} ne $term)
                    {
                        if (!$derived{$term2})
                        {
                            $derived{$term2} = {};
                        }
                        if (!defined $derived{$term2}->{$term})
                        {
                            $derived{$term2}->{$term} = 0;
                        }
                        $derived{$term2}->{$term}++;
                    }
                }
            }
        }
    }

    return %derived;
} # derive_xrefs

sub extract_legend ($$;%) {
    my $list_ref = shift;
    my $terms_ref = shift;
    my %params = @_;

    # If there is a top-level item which is a map-legend
    # it will tell us what colours to put for matching nodes

    my %legend = ();
    my $legend = $params{legend};
    my $found = 0;
    for (my $i = 0; !$found and $i < @{$list_ref}; $i++)
    {
        my $item = $list_ref->[$i];
        my $term = $item->{term};
        my $line = $item->{line};
        if ($term eq $legend) # this is the legend
        {
            $found = 1;
            # The children of the legend contain terms and colours
            if ($item->{children})
            {
                for (my $j = 0; $j < @{$item->{children}}; $j++)
                {
                    my $child = $item->{children}->[$j];
                    my $ch_term = $child->{term};
                    my $ch_line = $child->{line};
                    my $fg = '';
                    my $bg = '';

                    if ($ch_line =~ /\b(\w\w+)\/(\w\w+)\b/)
                    {
                        $fg = $1;
                        $bg = $2;
                    }
                    elsif ($ch_line =~ /\b(\w\w+)\b/)
                    {
                        $fg = $1;
                    }
                    $legend{$ch_term} = {
                        fg => $fg,
                        bg => $bg
                    };
                    delete $terms_ref->{$ch_term};
                }
                # now we need to remove the legend from the map
                delete $list_ref->[$i];
            }
        }
    }
    return %legend;
} # extract_legend

sub apply_legend {
    my $terms_ref = shift;
    my $legend_ref = shift;

    # search for references to Legend terms
    # inside other nodes
    # and add the appropriate colours
    foreach my $lterm (sort keys %{$legend_ref})
    {
        foreach my $term (sort keys %{$terms_ref})
        {
            my $line = $terms_ref->{$term}->{line};
            if (($lterm eq $term)
                or ($line =~ /\b$lterm\b/i))
            {
                $terms_ref->{$term}->{fg} = $legend_ref->{$lterm}->{fg};
                $terms_ref->{$term}->{bg} = $legend_ref->{$lterm}->{bg};
            }
        }
    }

} # apply_legend


sub start_map ($) {
    my $terms_ref = shift;

    my $map = '';
    # first do all the terms + labels
    local $Text::Wrap::columns = 20;
    foreach my $term (sort keys %{$terms_ref})
    {
        my $fg = $terms_ref->{$term}->{fg};
        my $bg = $terms_ref->{$term}->{bg};
        my @nodeargs = ();
        push @nodeargs, "fontcolor = $fg" if $fg;
        push @nodeargs, "fillcolor = $bg, style = filled" if $bg;
        my $line = $terms_ref->{$term}->{line};
        if ($term ne $line)
        {
            my $label = wrap('', '', $line);
            $label =~ s/\n/\\n/sg; # replace newlines with newline escapes
            push @nodeargs, 'label="' . $label . '"';
        }
        if (@nodeargs > 0)
        {
            $map .= '"' . $term . '" [ ' . join(',', @nodeargs) . " ];\n";
        }
    }
    return $map;
} # start_map

sub build_xrefs {
    my $xref_ref = shift;
    my $xref_edge_colour = shift;

    my $map = '';
    # do the cross-references
    foreach my $term (sort keys %{$xref_ref})
    {
        foreach my $xref (sort keys %{$xref_ref->{$term}})
        {
            $map .= '"' . $term . '" -> "' . $xref . '"' . " [ color=$xref_edge_colour ];\n";
        }
    }
    return $map;
} # end_map

sub build_map_levels ($$;%);

sub build_map_levels ($$;%) {
    my $list_ref = shift;
    my $level = shift;
    my %params = @_;

    my $map = '';

    my $ordered_colour = 'red3';
    my $top = $params{top};
    for (my $i = 0; $i < @{$list_ref}; $i++)
    {
        my $item = $list_ref->[$i];
        my $term = $item->{term};
        my $line = $item->{line};

        next if !$term;

        if ($level == 0)
        {
            if ($top)
            {
                $map .= '"' . $top . '"' . " [ fontsize = 14 ];\n";
            }
            $map .= '"' . $term . '"' . " [ fontsize = 12 ];\n";
            if ($top)
            {
                $map .= '"' . $top . '" -> "' . $term . '"' . ";\n";
            }
        }
        # do child-items
        if ($item->{children})
        {
            # Link to the children
            # If the children are an ordered list,
            # link to the first and link them to each other
            my $firstchild = $item->{children}->[0];
            if ($firstchild->{number})
            {
                $map .= '"' . $term . '" -> "' . $firstchild->{term} . '"' . ";\n";
            }
            for (my $j = 0; $j < @{$item->{children}}; $j++)
            {
                my $child = $item->{children}->[$j];
                if ($firstchild->{number})
                {
                    $map .= '"' . $child->{term} . '"' . " [ shape = box ];\n";
                    if ($j + 1 < @{$item->{children}})
                    {
                        $map .= '"' . $child->{term} . '" -> "' . $item->{children}->[$j+1]->{term} . '"' . " [ color = $ordered_colour ];\n";
                    }
                }
                else
                {
                    $map .= '"' . $term . '" -> "' . $child->{term} . '"' . ";\n";
                }
            }
            $map .= build_map_levels($item->{children}, $level + 1, %params);
        }
    }

    return $map;
} # build_map_levels

1;
