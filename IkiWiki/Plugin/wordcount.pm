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
    # ignoring all punctuation
    my @matches = ($params{content} =~ m/\b[\w-]+/gs);
    $pagestate{$page}{wordcount} = scalar @matches;
} # scan

sub preprocess (@) {
    my %params=@_;
    my $pages=defined $params{pages} ? $params{pages} : "*";

    my @matching_pages = ();
    if ($pages eq '*') {
        # optimisation to avoid needing to try matching every page
        add_depends($params{page}, $pages);
        @matching_pages = keys %pagesources;
    }

    @matching_pages = pagespec_match_list($params{page}, $pages);
    my $total = 0;
    foreach my $pn (@matching_pages)
    {
        $total += $pagestate{$pn}{wordcount};
    }
    return $total;
} # preprocess

1
