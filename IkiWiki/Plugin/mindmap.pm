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
        $params{content} =~ s/\n[*]\s*mindmap\n(.*?)\n\n/create_mindmap($1,$page)/sieg;
    }

    return $params{content};
} # do_filter

#---------------------------------------------------------------
# Private functions
# --------------------------------
sub parse_lines ($$$$);

sub parse_lines ($$$$) {
    my $lines_ref = shift;
    my $terms_ref = shift;
    my $xref_ref = shift;
    my $prev_indent = shift;

    if (@{$lines_ref})
    {
        local $Text::Wrap::columns = 20;

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
            $this_line =~ tr{"}{'};

            my ($term, $rest_of_line) = listprefix($this_line);
            while ($rest_of_line =~ /\(See ([-\s\w]+)\)/)
            {
                my $xref = $1;
                $rest_of_line =~ s/\s*\(See [-\s\w]+\)\s*//;
                if (!$xref_ref->{$term})
                {
                    $xref_ref->{$term} = [];
                }
                push @{$xref_ref->{$term}},  $xref;
            }
            while ($rest_of_line =~ /\(Ref ([-\s\w]+)\)/)
            {
                my $xref = $1;
                $rest_of_line =~ s/\s*\(Ref [-\s\w]+\)\s*//;
                if (!$xref_ref->{$xref})
                {
                    $xref_ref->{$xref} = [];
                }
                push @{$xref_ref->{$xref}},  $term;
            }
            push @siblings, {term => $term,
                line => $rest_of_line};
            my $label = wrap('', '', $rest_of_line);
            $label =~ s/\n/\\n/sg; # replace newlines with newline escapes
            $terms_ref->{$term} = $label;

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
            my @children = parse_lines($lines_ref, $terms_ref, $xref_ref, $this_indent);
            $siblings[$#siblings]->{children} = \@children;
            return (@siblings, parse_lines($lines_ref, $terms_ref, $xref_ref, $this_indent));
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

    my ($prefix, $number, $rawprefix, $term);
    my $rest_of_line = $line;

    my $bullets         = '*';
    my $bullets_ordered = '#';
    my $number_match    = '(\d+|[^\W\d])';
    if ($bullets_ordered)
    {
        $number_match = '(\d+|[[:alpha:]]|[' . "${bullets_ordered}])";
    }
    my $term_match = '(\w\w+)';
    return (0, 0, 0, 0, $rest_of_line)
      if ( !($line =~ /^\s*[${bullets}]\s+\S/)
        && !($line =~ /^\s*${number_match}[\.\)\]:]\s+\S/)
        && !($line =~ /^\s*${term_match}:/));

    ($term)   = $line =~ /^\s*${term_match}:/;
    ($number) = $line =~ /^\s*${number_match}\S\s+\S/;
    $number = 0 unless defined($number);
    if (   $bullets_ordered
        && $number =~ /[${bullets_ordered}]/)
    {
        $number = 1;
    }

    if ($term)
    {
        ($rawprefix, $rest_of_line) = $line =~ /^(\s*${term_match}.)\s*(.*)/;
        $prefix = $rawprefix;
        $prefix =~ s/${term_match}//;    # Take the term out
    }
    elsif ($number)
    {
        ($rawprefix, $rest_of_line) = $line =~ /^(\s*${number_match}.)\s*(.*)/;
        $prefix = $rawprefix;
        $prefix =~ s/${number_match}//;    # Take the number out
    }
    else
    {
        ($rawprefix, $rest_of_line) = $line =~ /^(\s*[${bullets}].)\s*(.*)/;
        $prefix = $rawprefix;
    }
    if (!$term)
    {
        ($term)   = $rest_of_line =~ /^\s*${term_match}:/;
        $rest_of_line =~ s/^\s*${term_match}:\s*//;
    }
    if (!$term)
    {
        $term = $rest_of_line;
    }
    ($term, $rest_of_line);
}    # listprefix

sub create_mindmap ($$) {
    my $string = shift;
    my $page = shift;

    my $map =<<EOT;
[[!graph
src="""
graph [ aspect = 2 ];
node [ fontsize = 10 ];
EOT
    my @lines       = split(/^/, $string);
    my %terms = ();
    my %xref = ();
    my @ret = parse_lines(\@lines, \%terms, \%xref, 0);
    $map .= build_map_levels(\@ret, \%terms, \%xref, 0);

    $map .=<<EOT;
"""]]
EOT

    return "\n\n" . $string . "\n\n" . $map . "\n\n" . "<pre>\\$map</pre>\n\n";
} # create_mindmap

sub build_map_levels ($$$$);

sub build_map_levels ($$$$) {
    my $list_ref = shift;
    my $terms_ref = shift;
    my $xref_ref = shift;
    my $level = shift;

    my $map = '';

    # first do all the terms + labels
    if ($level == 0)
    {
        foreach my $term (sort keys %{$terms_ref})
        {
            my $label = $terms_ref->{$term};
            if ($term ne $label)
            {
                $map .= '"' . $term . '" [ label="' . $label . '"' . " ];\n";
            }
        }
    }
    my $top = "Map";
    for (my $i = 0; $i < @{$list_ref}; $i++)
    {
        my $item = $list_ref->[$i];
        my $term = $item->{term};
        my $line = $item->{line};

        if ($level == 0)
        {
            $map .= '"' . $term . '"' . " [ fontsize = 14 ];\n";
            $map .= '"' . $top . '" -> "' . $term . '"' . ";\n";
        }
        # do child-items
        if ($item->{children})
        {
            # link to the children
            for (my $j = 0; $j < @{$item->{children}}; $j++)
            {
                my $child = $item->{children}->[$j];
                $map .= '"' . $term . '" -> "' . $child->{term} . '"' . ";\n";
            }
            $map .= build_map_levels($item->{children}, $terms_ref, $xref_ref, $level + 1);
        }
    }

    # do the cross-references
    my $xref_edge_colour = 'blue';
    if ($level == 0)
    {
        foreach my $term (sort keys %{$xref_ref})
        {
            my $xref_array = $xref_ref->{$term};
            foreach my $xref (@{$xref_array})
            {
                $map .= '"' . $term . '" -> "' . $xref . '"' . " [ color=$xref_edge_colour ];\n";
            }
        }
    }
    return $map;
} # build_map_levels

1;
