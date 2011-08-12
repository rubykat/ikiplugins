#!/usr/bin/perl
#
# Produce a simple "trail" to be used inside a pagetemplate.
#
package IkiWiki::Plugin::simpletrail;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "simpletrail", call => \&getsetup);
	hook(type => "pagetemplate", id => "simpletrail", call => \&pagetemplate);
}

# -------------------------------------------------------------------
# Hooks
# -------------------------------------
sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
}

sub pagetemplate (@) {
    my %params=@_;
    my $this_page = $params{page};

    # "trail" means "all the pages linked to from a given page"
    # which is a bit looser than the PmWiki definition
    # but it will do

    # Get the "previous" and "next" pages from the links on
    # the parent page of the current page.
    my $parent_page = '';
    if ($this_page =~ m{^(.*)/[-\.\w]+$}o)
    {
	$parent_page = $1;
    }
    else # top-level page
    {
	$parent_page = 'index';
    }

    my @matching_pages;
    add_depends($this_page, $parent_page, deptype("links"));
    foreach my $ln (@{$links{$parent_page}})
    {
	my $bl = bestlink($parent_page, $ln);
	push @matching_pages, $bl;
    }

    # find the previous and next page on the trail
    my $prev_page = '';
    my $next_page = '';
    my $first = 0;
    my $last = 0;
    for (my $i=0; $i < @matching_pages; $i++)
    {
	my $page = $matching_pages[$i];
	if ($page eq $this_page)
	{
	    if ($i > 0)
	    {
		$prev_page = $matching_pages[$i - 1];
	    }
	    else
	    {
		$first = 1;
	    }
	    if ($i < $#matching_pages)
	    {
		$next_page = $matching_pages[$i + 1];
	    }
	    else
	    {
		$last = 1;
	    }
	    last;
	}
    }

    my $ret = '';
    if ($prev_page or $next_page) # this page is on the trail
    {
	my $template = $params{template};
	if ($prev_page)
	{
	    $template->param(
		prev_page=>$prev_page,
		prev_page_url=>urlto($prev_page, $this_page),
		prev_title=>
		(exists $pagestate{$prev_page}{meta}{title}
		    ?  $pagestate{$prev_page}{meta}{title}
		    : pagetitle(IkiWiki::basename($prev_page))));
	}
	if ($next_page)
	{
	    $template->param(
		next_page=>$next_page,
		next_page_url=>urlto($next_page, $this_page),
		next_title=>
		(exists $pagestate{$next_page}{meta}{title}
		    ?  $pagestate{$next_page}{meta}{title}
		    : pagetitle(IkiWiki::basename($next_page))));
	}
	$template->param(
	    trailpage=>$parent_page,
	    trailpage_url=>urlto($parent_page, $this_page),
	    trail_first=>$first,
	    trail_last=>$last);
	$template->param(trailpage_title=>
	    (exists $pagestate{$parent_page}{meta}{title}
		?  $pagestate{$parent_page}{meta}{title}
		: pagetitle(IkiWiki::basename($parent_page))));
    }

} # pagetemplate

1;
