#!/usr/bin/perl
# PmWiki as a wiki page type.
package IkiWiki::Plugin::pmwiki;
use warnings;
use strict;
=head1 NAME

IkiWiki::Plugin::pmwiki - process pages written in PmWiki format.

=head1 VERSION

This describes version B<0.20110610> of IkiWiki::Plugin::pmwiki

=cut

our $VERSION = '0.20110610';

=head1 SYNOPSIS

In the ikiwiki setup file, enable this plugin by adding it to the
list of active plugins.

    add_plugins => [qw{goodstuff pmwiki ....}],

=head1 DESCRIPTION

IkiWiki::Plugin::pmwiki is an IkiWiki plugin enabling ikiwiki to
process pages written in PmWiki (http://www.pmwiki.org) format.
This will treat files with a B<.pmwiki> extension as files
which contain PmWiki markup.

=head1 OPTIONS

The following options can be set in the ikiwiki setup file.

=over

=item pmwiki_ptv

If true, will interpret PageTextVariables.

=back

=head1 PREREQUISITES

    IkiWiki

=head1 AUTHOR

    Kathryn Andersen (RUBYKAT)
    http://github.com/rubykat

=head1 COPYRIGHT

Copyright (c) 2009 Kathryn Andersen

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

use IkiWiki 3.00;

my $link_regexp;

sub import {
	hook(type => "getsetup", id => "pmwiki", call => \&getsetup);
	hook(type => "checkconfig", id => "pmwiki", call => \&checkconfig);
	hook(type => "scan", id => "pmwiki", call => \&scan);
	hook(type => "filter", id => "pmwiki", call => \&filter);
	hook(type => "linkify", id => "pmwiki", call => \&linkify, first=>1);
	hook(type => "htmlize", id => "pmwiki", call => \&htmlize);
    IkiWiki::Plugin::field::field_register(id=>'pmwiki',
	all_values=>\&scan_ptvs, first=>1);
}

# ===============================================
# Hooks
# ---------------------------
sub getsetup () {
	return
		plugin => {
			description => "process pages written in PmWiki format",
			safe => 1,
			rebuild => undef,
		},
		pmwiki_links => {
			type => "boolean",
			example => "0",
			description => "if true, use PmWiki-style links not IkiWiki links",
			safe => 0,
			rebuild => undef,
		},
}

sub checkconfig () {
    if (!defined $config{pmwiki_links})
    {
	$config{pmwiki_links} = 1;
    }
    if ($config{pmwiki_links})
    {
	$link_regexp = qr{
	    \[\[(?=[^!])            # beginning of link
		([^\n\r\]#\|]+)           # 1: page to link to
		(?:
		 \#              # '#', beginning of anchor
		 ([^\s\]]+)      # 2: anchor text
		)?                      # optional
		(?:
		 \|              # started with '|'
		 ([^\]\|]+)      # 3: link text
		)?                      # optional

		\]\]                    # end of link
	}x;
    }
    return 1;
}

sub scan (@) {
    my %params=@_;
    my $page=$params{page};

    my $page_file=$pagesources{$page};
    my $page_type=pagetype($page_file);
    if (!defined $page_type
	or $page_type ne 'pmwiki')
    {
	return;
    }
    if ($config{pmwiki_links})
    {
	$params{content} =~ s/{{\$page}}/$page/sg;
	while ($params{content} =~ /(?<!\\)$link_regexp/g) {
	    my $link = $1;
	    #print STDERR "pmwiki: $page => $link (" . linkpage($link) . ")\n";
	    if ($link !~ /^(?:http|mailto|ftp|#|\.\.)/)
	    {
		add_link($page, linkpage($link));
	    }
	}
    }
}

sub filter (@) {
    my %params=@_;
    my $page = $params{page};

    my $page_file=$pagesources{$page} || return $params{content};
    my $page_type=pagetype($page_file);
    if (!defined $page_type
	or $page_type ne 'pmwiki')
    {
	return $params{content};
    }

    # remove hidden PTVs
    #$params{content} =~ s!(?:^|\n)\(:[-\w]+:(?:.*?):\)\s*!!gs;
    $params{content} =~ s!\(:[-\w]+:(?:.*?):\)\s*!!gs;

    return $params{content};
}

sub linkify (@) {
    my %params=@_;
    my $page=$params{page};
    my $destpage=$params{destpage};

    my $page_file=$pagesources{$page};
    my $page_type=pagetype($page_file);

    if (!defined $page_type
	or $page_type ne 'pmwiki'
	or !$config{pmwiki_links})
    {
	return $params{content};
    }

    # [[link|label]]
    $params{content} =~ s{(?<!\\)\[\[(?=[^!])([^\]\|#]+(?:#[^\s\]\|]+)?)(?:\|([^\]]+))?\]\]}{
	process_link($page, $destpage, $1, $2)
    }egso;

    # [[#anchor]]
    $params{content} =~ s{(?<!\\)\[\[#([^\s\]\|]+)(?:\|([^\]]+))?\]\]}{
	process_anchor($page, $destpage, $1, $2)
    }egso;

    # plain http:// links
    $params{content} =~ s{(?<![<>"'\[])(http:[\w/\.:\@+\-~\%#?=&;,]+[\w/])}{<a href="$1">$1</a>}g;
    $params{content} =~ s{^\s*(http:[\w/\.:\@+\-~\%#?=&;,]+[\w/])}{<a href="$1">$1</a>};
    
    return $params{content};
}

sub htmlize (@) {
    my %params=@_;
    my $page = $params{page};
    my $destpage = $params{destpage};

    return '' if !$params{content};

    eval {use Text::PmWiki};
    return $params{content} if $@;

    # don't parse WikiLinks, that's been done already
    pmwiki_customlinks();
    pmwiki_custombarelinks();

    my $out = pmwiki_parse($params{content});

    # there are some stupid things it does that I couldn't fix
    #$out =~ s{<td>\s*<p>}{<td>}ogs;
    #$out =~ s{</p>\s*</td>\s*}{</td>\n}ogs;
    $out =~ s{<p>\s*</p>}{}ogs;

    # fix random ampersands
    $out =~ s{ & }{ &amp; }ogs;

    return $out;
}
# ===============================================
# Private functions
# ---------------------------
sub scan_ptvs (@) {
    my %params=@_;
    my $page = $params{page};

    my $page_file=$pagesources{$page} || return;
    my $page_type=pagetype($page_file);
    if (!defined $page_type
	or $page_type ne 'pmwiki')
    {
	return undef;
    }
    my %values = ();
    # scan for title
    if ($params{content} =~ m!(?:^|\n)\(:title\s+(.*?):\)\s*!so)
    {
	my $key = 'title';
	my $val = $1;
	$values{$key} = $val;
    }
    while ($params{content} =~ m!(?:^|\n)\(:([-\w]+):(.*?):\)!igso)
    {
	my $key = $1;
	my $val = $2;
	$values{lc($key)} = $val;
    }
    return \%values;
} # scan_ptvs

sub process_link ($$$$) {
    my $page = shift;
    my $destpage = shift;
    my $fulllink = shift;
    my $label = shift;

    if ($fulllink =~ /^(?:http|mailto|ftp)/o) # external link
    {
	return (defined $label
	? "<a href='$fulllink'>$label</a>"
	: "<a href='$fulllink'>$fulllink</a>");
    }
    else
    {
	my ($link, $anchor) = split(/#/, $fulllink);
	return (
	    defined $label
	    ? (defined $anchor
	      ? htmllink($page, $destpage, linkpage($link), anchor => $anchor, linktext=>$label)
	      : htmllink($page, $destpage, linkpage($fulllink), linktext=>$label ))
	    : (defined $anchor
	    ? htmllink($page, $destpage, linkpage($link), anchor=>$anchor)
	    : htmllink($page, $destpage, linkpage($fulllink)) )
	);
    }
    return '';
} # process_link

sub process_anchor ($$$$) {
    my $page = shift;
    my $destpage = shift;
    my $anchor = shift;
    my $label = shift;

    return (
	    defined $label
	    ? "<a href='#$anchor'>$label</a>"
	    : "<a name='#$anchor'></a>"
	   );
} # process_anchor

1;
