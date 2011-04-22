#!/usr/bin/perl
# HTML as a wiki page type.
package IkiWiki::Plugin::xhtm;

use warnings;
use strict;
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
	IkiWiki::Plugin::field::field_register(id=>'xhtml');
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
    my $page_type=pagetype($page_file);
    if (!defined $page_type)
    {
	return;
    }
    # scan for titles and descriptions
    if ($page_type =~ /x?html?/o)
    {
	if ($params{content} =~ m#<html[^>]*>.*<head>\s*(.*)\s*</head>#iso)
	{
	    my $head = $1;
	    if ($head =~ m#<title>(.*)</title>#iso)
	    {
		my $title = $1;
		$pagestate{$page}{xhtm}{title} = $title;
		$pagestate{$page}{meta}{title} = $title;
	    }
	    if ($head =~ m#<meta\s+name="description"\s+content\s*=\s*"([^"]*)"#iso)
	    {
		my $desc = $1;
		$pagestate{$page}{xhtm}{description} = $desc;
		$pagestate{$page}{meta}{description} = $desc;
	    }
	    $head =~ s#\s*<title>.*</title>\s*##iso;
	}

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
    }
}

# return the BODY content
sub filter (@) {
    my %params=@_;
    my $page = $params{page};

    my $page_file=$pagesources{$page} || return $params{content};
    my $page_type=pagetype($page_file);
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
