#!/usr/bin/perl
package IkiWiki::Plugin::wordcount;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "wordcount", call => \&getsetup);
	hook(type => "scan", id => "wordcount", call => \&scan);
	hook(type => "preprocess", id => "wordcount", call => \&preprocess);
}

sub getsetup () {
	return 
		plugin => {
			safe => 1,
			rebuild => undef,
			section => "widget",
		},
}

sub scan (@) {
    my %params=@_;
    my $page=$params{page};

    my $page_file=$pagesources{$page};
    return unless $page_file;
    my $page_type=pagetype($page_file);
    return unless defined $page_type;

    # count the words in the content
    $params{content} =~ s/<[^>]+>/ /gs; # remove html tags
    # Remove everything but letters + spaces
    # This is so that things like apostrophes don't make one
    # word count as two words
    $params{content} =~ s/[^\w\s]//gs;

    my @matches = ($params{content} =~ m/\b[\w]+/gs);
    $pagestate{$page}{wordcount}{words} = int @matches;
} # scan

sub preprocess (@) {
    my %params=@_;
    my $page = $params{page};
    my $pages=(defined $params{pages} ? $params{pages} : $page);

    my @matching_pages = ();
    if ($pages eq $page)
    {
        push @matching_pages, $page;
    }
    else
    {
        @matching_pages = pagespec_match_list($params{page}, $pages);
    }
    my $total = 0;
    foreach my $pn (@matching_pages)
    {
        my $words = $pagestate{$pn}{wordcount}{words};
        $total += $words;
    }
    return $total;
} # preprocess

1
