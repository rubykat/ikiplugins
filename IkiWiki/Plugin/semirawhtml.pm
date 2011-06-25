#!/usr/bin/perl
package IkiWiki::Plugin::semirawhtml;
use warnings;
use strict;
=head1 NAME

IkiWiki::Plugin::semirawhtml - copy some HTML files raw, and process others

=head1 VERSION

This describes version B<0.20110618> of IkiWiki::Plugin::semirawhtml

=cut

our $VERSION = '0.20110618';

=head1 DESCRIPTION

This allows one to treat HTML pages as either raw HTML or as a wiki page,
depending on the extension.

Pages with a .html extension are treated as raw HTML, and passed on
completely untouched.

Pages with a .htm or .xhtm extension are treated as wiki pages, but unlike the
html plugin, it does parse the body content out of the page, so one gets a
semantically correct page.

See doc/plugin/contrib/semirawhtml for documentation.

=head1 PREREQUISITES

    IkiWiki
    IkiWiki::Plugin::meta

=head1 AUTHOR

    Kathryn Andersen (RUBYKAT)
    http://github.com/rubykat

=head1 COPYRIGHT

Copyright (c) 2011 Kathryn Andersen

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "semirawhtml", call => \&getsetup);
	hook(type => "scan", id => "semirawhtml", call => \&scan_meta, first=>1);
	hook(type => "filter", id => "semirawhtml", call => \&filter);
	hook(type => "htmlize", id => "xhtm", call => \&htmlize);
	hook(type => "htmlize", id => "htm", call => \&htmlize);

	# ikiwiki defaults to skipping .html files as a security measure;
	# make it process them so this plugin can take effect
	$config{wiki_file_prune_regexps} = [ grep { !m/\\\.x\?html\?\$/ } @{$config{wiki_file_prune_regexps}} ];

}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 1,
		},
}

# scan the certain meta content and remember it
sub scan_meta (@) {
    my %params=@_;
    my $page=$params{page};

    my $page_file=$pagesources{$page} || return undef;
    my $page_type=pagetype($page_file);
    if (!defined $page_type)
    {
	return undef;
    }
    # scan for titles and descriptions
    if ($page_type =~ /x?htm/o)
    {
	if ($params{content} =~ m#<html[^>]*>.*<head>\s*(.*)\s*</head>#iso)
	{
	    my $head = $1;
	    if ($head =~ m#<title>(.*)</title>#iso)
	    {
		my $title = $1;
		$pagestate{$page}{meta}{title} = $title;
	    }
	    if ($head =~ m#<meta\s+name="description"\s+content\s*=\s*"([^"]*)"#iso)
	    {
		my $desc = $1;
		$pagestate{$page}{meta}{description} = $desc;
	    }
	}
    }
} # scan_meta

# return the BODY content
sub filter (@) {
    my %params=@_;
    my $page = $params{page};

    my $page_file=$pagesources{$page} || return $params{content};
    my $page_type=pagetype($page_file);
    if (!defined $page_type || $page_type !~ /x?htm?/o)
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
    return $params{content};
}

sub htmlize (@) {
    my %params=@_;
    my $page = $params{page};

    return $params{content};
}

1;
