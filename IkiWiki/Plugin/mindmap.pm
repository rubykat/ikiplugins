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

my @X11_colours = (qw(
GhostWhite
WhiteSmoke
gainsboro
FloralWhite
OldLace
linen
AntiqueWhite
PapayaWhip
BlanchedAlmond
bisque
PeachPuff
NavajoWhite
moccasin
cornsilk
ivory
LemonChiffon
seashell
honeydew
MintCream
azure
AliceBlue
lavender
LavenderBlush
MistyRose
white
black
DarkSlateGray
DarkSlateGrey
DimGray
DimGrey
SlateGray
SlateGrey
LightSlateGray
LightSlateGrey
gray
grey
LightGrey
LightGray
MidnightBlue
navy
NavyBlue
CornflowerBlue
DarkSlateBlue
SlateBlue
MediumSlateBlue
LightSlateBlue
MediumBlue
RoyalBlue
blue
DodgerBlue
DeepSkyBlue
SkyBlue
LightSkyBlue
SteelBlue
LightSteelBlue
LightBlue
PowderBlue
PaleTurquoise
DarkTurquoise
MediumTurquoise
turquoise
cyan
LightCyan
CadetBlue
MediumAquamarine
aquamarine
DarkGreen
DarkOliveGreen
DarkSeaGreen
SeaGreen
MediumSeaGreen
LightSeaGreen
PaleGreen
SpringGreen
LawnGreen
green
chartreuse
MediumSpringGreen
GreenYellow
LimeGreen
YellowGreen
ForestGreen
OliveDrab
DarkKhaki
khaki
PaleGoldenrod
LightGoldenrodYellow
LightYellow
yellow
gold
LightGoldenrod
goldenrod
DarkGoldenrod
RosyBrown
IndianRed
SaddleBrown
sienna
peru
burlywood
beige
wheat
SandyBrown
tan
chocolate
firebrick
brown
DarkSalmon
salmon
LightSalmon
orange
DarkOrange
coral
LightCoral
tomato
OrangeRed
red
HotPink
DeepPink
pink
LightPink
PaleVioletRed
maroon
MediumVioletRed
VioletRed
magenta
violet
plum
orchid
MediumOrchid
DarkOrchid
DarkViolet
BlueViolet
purple
MediumPurple
thistle
snow1
snow2
snow3
snow4
seashell1
seashell2
seashell3
seashell4
AntiqueWhite1
AntiqueWhite2
AntiqueWhite3
AntiqueWhite4
bisque1
bisque2
bisque3
bisque4
PeachPuff1
PeachPuff2
PeachPuff3
PeachPuff4
NavajoWhite1
NavajoWhite2
NavajoWhite3
NavajoWhite4
LemonChiffon1
LemonChiffon2
LemonChiffon3
LemonChiffon4
cornsilk1
cornsilk2
cornsilk3
cornsilk4
ivory1
ivory2
ivory3
ivory4
honeydew1
honeydew2
honeydew3
honeydew4
LavenderBlush1
LavenderBlush2
LavenderBlush3
LavenderBlush4
MistyRose1
MistyRose2
MistyRose3
MistyRose4
azure1
azure2
azure3
azure4
SlateBlue1
SlateBlue2
SlateBlue3
SlateBlue4
RoyalBlue1
RoyalBlue2
RoyalBlue3
RoyalBlue4
blue1
blue2
blue3
blue4
DodgerBlue1
DodgerBlue2
DodgerBlue3
DodgerBlue4
SteelBlue1
SteelBlue2
SteelBlue3
SteelBlue4
DeepSkyBlue1
DeepSkyBlue2
DeepSkyBlue3
DeepSkyBlue4
SkyBlue1
SkyBlue2
SkyBlue3
SkyBlue4
LightSkyBlue1
LightSkyBlue2
LightSkyBlue3
LightSkyBlue4
SlateGray1
SlateGray2
SlateGray3
SlateGray4
LightSteelBlue1
LightSteelBlue2
LightSteelBlue3
LightSteelBlue4
LightBlue1
LightBlue2
LightBlue3
LightBlue4
LightCyan1
LightCyan2
LightCyan3
LightCyan4
PaleTurquoise1
PaleTurquoise2
PaleTurquoise3
PaleTurquoise4
CadetBlue1
CadetBlue2
CadetBlue3
CadetBlue4
turquoise1
turquoise2
turquoise3
turquoise4
cyan1
cyan2
cyan3
cyan4
DarkSlateGray1
DarkSlateGray2
DarkSlateGray3
DarkSlateGray4
aquamarine1
aquamarine2
aquamarine3
aquamarine4
DarkSeaGreen1
DarkSeaGreen2
DarkSeaGreen3
DarkSeaGreen4
SeaGreen1
SeaGreen2
SeaGreen3
SeaGreen4
PaleGreen1
PaleGreen2
PaleGreen3
PaleGreen4
SpringGreen1
SpringGreen2
SpringGreen3
SpringGreen4
green1
green2
green3
green4
chartreuse1
chartreuse2
chartreuse3
chartreuse4
OliveDrab1
OliveDrab2
OliveDrab3
OliveDrab4
DarkOliveGreen1
DarkOliveGreen2
DarkOliveGreen3
DarkOliveGreen4
khaki1
khaki2
khaki3
khaki4
LightGoldenrod1
LightGoldenrod2
LightGoldenrod3
LightGoldenrod4
LightYellow1
LightYellow2
LightYellow3
LightYellow4
yellow1
yellow2
yellow3
yellow4
gold1
gold2
gold3
gold4
goldenrod1
goldenrod2
goldenrod3
goldenrod4
DarkGoldenrod1
DarkGoldenrod2
DarkGoldenrod3
DarkGoldenrod4
RosyBrown1
RosyBrown2
RosyBrown3
RosyBrown4
IndianRed1
IndianRed2
IndianRed3
IndianRed4
sienna1
sienna2
sienna3
sienna4
burlywood1
burlywood2
burlywood3
burlywood4
wheat1
wheat2
wheat3
wheat4
tan1
tan2
tan3
tan4
chocolate1
chocolate2
chocolate3
chocolate4
firebrick1
firebrick2
firebrick3
firebrick4
brown1
brown2
brown3
brown4
salmon1
salmon2
salmon3
salmon4
LightSalmon1
LightSalmon2
LightSalmon3
LightSalmon4
orange1
orange2
orange3
orange4
DarkOrange1
DarkOrange2
DarkOrange3
DarkOrange4
coral1
coral2
coral3
coral4
tomato1
tomato2
tomato3
tomato4
OrangeRed1
OrangeRed2
OrangeRed3
OrangeRed4
red1
red2
red3
red4
DeepPink1
DeepPink2
DeepPink3
DeepPink4
HotPink1
HotPink2
HotPink3
HotPink4
pink1
pink2
pink3
pink4
LightPink1
LightPink2
LightPink3
LightPink4
PaleVioletRed1
PaleVioletRed2
PaleVioletRed3
PaleVioletRed4
maroon1
maroon2
maroon3
maroon4
VioletRed1
VioletRed2
VioletRed3
VioletRed4
magenta1
magenta2
magenta3
magenta4
orchid1
orchid2
orchid3
orchid4
plum1
plum2
plum3
plum4
MediumOrchid1
MediumOrchid2
MediumOrchid3
MediumOrchid4
DarkOrchid1
DarkOrchid2
DarkOrchid3
DarkOrchid4
purple1
purple2
purple3
purple4
MediumPurple1
MediumPurple2
MediumPurple3
MediumPurple4
thistle1
thistle2
thistle3
thistle4
gray0
grey0
gray1
grey1
gray2
grey2
gray3
grey3
gray4
grey4
gray5
grey5
gray6
grey6
gray7
grey7
gray8
grey8
gray9
grey9
gray10
grey10
gray11
grey11
gray12
grey12
gray13
grey13
gray14
grey14
gray15
grey15
gray16
grey16
gray17
grey17
gray18
grey18
gray19
grey19
gray20
grey20
gray21
grey21
gray22
grey22
gray23
grey23
gray24
grey24
gray25
grey25
gray26
grey26
gray27
grey27
gray28
grey28
gray29
grey29
gray30
grey30
gray31
grey31
gray32
grey32
gray33
grey33
gray34
grey34
gray35
grey35
gray36
grey36
gray37
grey37
gray38
grey38
gray39
grey39
gray40
grey40
gray41
grey41
gray42
grey42
gray43
grey43
gray44
grey44
gray45
grey45
gray46
grey46
gray47
grey47
gray48
grey48
gray49
grey49
gray50
grey50
gray51
grey51
gray52
grey52
gray53
grey53
gray54
grey54
gray55
grey55
gray56
grey56
gray57
grey57
gray58
grey58
gray59
grey59
gray60
grey60
gray61
grey61
gray62
grey62
gray63
grey63
gray64
grey64
gray65
grey65
gray66
grey66
gray67
grey67
gray68
grey68
gray69
grey69
gray70
grey70
gray71
grey71
gray72
grey72
gray73
grey73
gray74
grey74
gray75
grey75
gray76
grey76
gray77
grey77
gray78
grey78
gray79
grey79
gray80
grey80
gray81
grey81
gray82
grey82
gray83
grey83
gray84
grey84
gray85
grey85
gray86
grey86
gray87
grey87
gray88
grey88
gray89
grey89
gray90
grey90
gray91
grey91
gray92
grey92
gray93
grey93
gray94
grey94
gray95
grey95
gray96
grey96
gray97
grey97
gray98
grey98
gray99
grey99
gray100
grey100
DarkGrey
DarkGray
DarkBlue
DarkCyan
DarkMagenta
DarkRed
LightGreen
));

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
            $this_line =~ tr{"}{'};

            my ($term, $rest_of_line, $number) = listprefix($this_line);
            my $fg;
            my $bg;
            ($fg, $bg, $rest_of_line) = parse_X11_colours($rest_of_line);
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
                fg => $fg,
                bg => $bg,
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
    ($term, $rest_of_line, $number);
}    # listprefix

sub create_mindmap ($$;$) {
    my $page = shift;
    my $string = shift;

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

    my $map =<<EOT;
[[!graph
prog=$prog
src="""
rankdir=LR;
node [ fontsize = 10 ];
edge [ color = grey30 ];
EOT
    my @lines       = split(/^/, $string);
    my %terms = ();
    my %xref = ();
    my %inverted = ();
    my @ret = parse_lines(\@lines, \%terms, \%xref, \%inverted, 0, '');
    my %derived = derive_xrefs(\%terms, \%inverted);
    $map .= start_map(\%terms);
    $map .= build_map_levels(\@ret, 0, %params);
    $map .= build_xrefs(\%xref, 'blue3');
    $map .= build_xrefs(\%derived, 'green3');

    $map .=<<EOT;
"""]]
EOT

    my $dump = Dump(\@ret);
    my $out = "\n\n" . $string . "\n\n" . $map . "\n\n";
    if ($DEBUG)
    {
        $out .= "<pre>\\$map\n\n$dump\n\n$DEBUG</pre>\n\n";
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
        push @nodeargs, "bgcolor = $bg" if $bg;
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

        if ($level == 0)
        {
            if ($top)
            {
                $map .= '"' . $top . '"' . " [ fontsize = 14 ];\n";
            }
            $map .= '"' . $term . '"' . " [ fontsize = 14 ];\n";
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

sub parse_X11_colours ($) {
    my $line = shift;

    my $fg = '';
    my $bg = '';
    my $rest_of_line = $line;

    my $cmatch = '%(' . join('|', @X11_colours) . ')%';
    if ($line =~ /${cmatch}\/${cmatch}/)
    {
        $fg = $1;
        $bg = $2;
        $rest_of_line =~ s/${cmatch}\${cmatch}//;
    }
    elsif ($line =~ /${cmatch}/)
    {
        $fg = $1;
        $rest_of_line =~ s/${cmatch}//;
    }
    return ($fg, $bg, $rest_of_line);
} # parse_X11_colours

1;
