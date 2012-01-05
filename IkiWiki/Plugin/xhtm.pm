#!/usr/bin/perl
# HTML as a wiki page type.
package IkiWiki::Plugin::xhtm;
use warnings;
use strict;
=head1 NAME

IkiWiki::Plugin::xhtm - HTML as a wiki page type

=head1 VERSION

This describes version B<1.20110610> of IkiWiki::Plugin::xhtm

=cut

our $VERSION = '1.20110610';

=head1 DESCRIPTION

Allows one to use a full HTML page as an input page; unlike the rawhtml
plugin, it doesn't just pass the page on untouched, and unlike the html
plugin, it does parse the body content out of the page, so one gets
a semantically correct page.

See doc/plugin/contrib/xhtm for documentation.

=head1 PREREQUISITES

    IkiWiki
    IkiWiki::Plugin::meta

=head1 AUTHOR

    Kathryn Andersen (RUBYKAT)
    http://github.com/rubykat

=head1 COPYRIGHT

Copyright (c) 2009-2011 Kathryn Andersen

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
use IkiWiki 3.00;

my %PageHeads;

sub import {
	hook(type => "getsetup", id => "xhtm", call => \&getsetup);
	hook(type => "scan", id => "xhtm", call => \&scan);
	hook(type => "filter", id => "xhtm", call => \&filter);
	hook(type => "htmlize", id => "xhtm", call => \&htmlize);
	hook(type => "htmlize", id => "html", call => \&htmlize);
	hook(type => "htmlize", id => "htm", call => \&htmlize);

	# ikiwiki defaults to skipping .html files as a security measure;
	# make it process them so this plugin can take effect
	$config{wiki_file_prune_regexps} = [ grep { !m/\\\.x\?html\?\$/ } @{$config{wiki_file_prune_regexps}} ];

	IkiWiki::loadplugin("field");
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 1,
		},
}

# scan the certain meta content and remember it
# scan for internal links and add them
sub scan (@) {
    my %params=@_;
    my $page=$params{page};

    my $page_file=$pagesources{$page};
    return unless $page_file;
    my $page_type=pagetype($page_file);
    return unless defined $page_type;

    if ($page_type =~ /x?html?/o)
    {
	# scan for internal links
	$params{content} =~ s/{{\$page}}/$page/sg; # we know what the page is
	while ($params{content} =~ m/<a[^>]+href\s*=\s*['"]([^'"#]+)(#[^\s"']+)?['"][^>]*>[^<]+<\/a>/igso)
	{
	    my $link = $1;
	    if ($link !~ /^(http|mailto|#|\.\.)/o and $link !~ /{{\$/o)
	    {
		my $bestlink = bestlink($page, $link);
		if ($bestlink)
		{
		    add_link($page, linkpage($link));
		}
	    }
	}
	scan_meta(%params);
    }
}

# scan the certain meta content and remember it
sub scan_meta (@) {
    my %params=@_;
    my $page=$params{page};

    my $page_file=$pagesources{$page};
    return undef unless $page_file;
    my $page_type=pagetype($page_file);
    return undef unless defined $page_type;

    # scan for titles and descriptions
    my %meta = ();
    if ($page_type =~ /x?html?/o)
    {
	if ($params{content} =~ m#<html[^>]*>.*<head>\s*(.*)\s*</head>#iso)
	{
	    my $head = $1;
	    if ($head =~ m#<title>(.*)</title>#iso)
	    {
		my $title = $1;
		IkiWiki::Plugin::meta::preprocess(
		    title=>$title,
		    page=>$page);
	    }
	    if ($head =~ m#<meta\s+name="description"\s+content\s*=\s*"([^"]*)"#iso)
	    {
		my $desc = $1;
		IkiWiki::Plugin::meta::preprocess(
		    description=>$desc,
		    page=>$page);
	    }
	}
    }
} # scan_meta

# return the BODY content
sub filter (@) {
    my %params=@_;
    my $page = $params{page};

    my $page_file=$pagesources{$page};
    return $params{content} unless $page_file;
    my $page_type=pagetype($page_file);
    return $params{content} unless defined $page_type;

    if (!defined $page_type || $page_type !~ /x?html?/o)
    {
	return $params{content};
    }

    if ($params{content} =~ m#<body[^>]*>\s*(.*)\s*</body>#iso)
    {
	my $body = $1;
	if ($body)
	{
	    $params{content} = $body;
	}
    }
    $params{content} =~ s/{{\$page}}/$page/sg; # we know what the page is
    # convert internal links to ikiwiki links
    $params{content} =~ s/(<a[^>]+href\s*=\s*['"]([^'"]+)['"][^>]*>([^<]+)<\/a>)/convert_internal_link($page, $1, $2, $3)/eigso;
    return $params{content};
}

sub htmlize (@) {
    my %params=@_;
    my $page = $params{page};

    return $params{content};
}

# --------------------------------------------------------------------------
# Private Functions
# -----------------------------------
sub convert_internal_link {
    my $page = shift;
    my $match = shift;
    my $link = shift;
    my $label = shift;

    if ($link !~ /^(http|mailto|#|\.\.)/o)
    {
	my $bestlink = bestlink($page, $link);
	if ($bestlink)
	{
	    return "[[$label|$link]]";
	}
    }
    return $match;
} # convert_internal_link

1;
