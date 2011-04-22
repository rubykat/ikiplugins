#!/usr/bin/perl
#
# Produce templated "trails" from the links on trail pages.
#
package IkiWiki::Plugin::linktrail;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "linktrail", call => \&getsetup);
	hook(type => "preprocess", id => "linktrail", call => \&preprocess);
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

sub preprocess (@) {
    my %params=@_;

    if (! exists $params{trail})
    {
	error gettext("missing trail parameter");
    }
    if (exists $params{template}) {
	$params{template}=~s/[^-_a-zA-Z0-9]+//g;
    }
    else {
	$params{template} = 'linktrail';
    }

    my $this_page = $params{page};
    delete $params{page};
    my $pages = (defined $params{pages} ? $params{pages} : '*');


    my $deptype=deptype("presence");

    my @matching_pages;
    # "trail" means "all the pages linked to from a given page"
    # which is a bit looser than the PmWiki definition
    # but it will do
    my @trailpages = split(' ', $params{trail});
    my %trailsrc = ();
    foreach my $tp (@trailpages)
    {
	add_depends($this_page, $tp, deptype("links"));
	foreach my $ln (@{$links{$tp}})
	{
	    my $bl = bestlink($tp, $ln);
	    push @matching_pages, $bl;
	    $trailsrc{$bl} = $tp;
	}
    }
    if ($params{pages}) # filter the found pages
    {
	# filter out the pages that don't match
	my @filtered = ();
	my $result=0;
	foreach my $mp (@matching_pages)
	{
	    $result=pagespec_match($mp, $pages);
	    if ($result)
	    {
		push @filtered, $mp;
		add_depends($this_page, $mp, $deptype);
	    }
	}
	@matching_pages = @filtered;
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
	require HTML::Template;
	my @params=IkiWiki::template_params($params{template}.".tmpl", blind_cache => 1);
	if (! @params) {
	    error sprintf(gettext("nonexistant template %s"), $params{template});
	}
	my $template=HTML::Template->new(@params);
	$template->param(page=>$this_page,
			 prev_page=>$prev_page,
			 next_page=>$next_page,
			 trailpage=>$trailsrc{$this_page},
			 first=>$first,
			 last=>$last);
	$template->param(title=>
			 (exists $pagestate{$this_page}{meta}{title}
			  ?  $pagestate{$this_page}{meta}{title}
			  : pagetitle(IkiWiki::basename($this_page))));
	$template->param(trailtitle=>
			 (exists $pagestate{$trailsrc{$this_page}}{meta}{title}
			  ?  $pagestate{$trailsrc{$this_page}}{meta}{title}
			  : pagetitle(IkiWiki::basename($trailsrc{$this_page}))));
	$template->param(prev_title=>
			 ($prev_page and exists $pagestate{$prev_page}{meta}{title}
			  ?  $pagestate{$prev_page}{meta}{title}
			  : pagetitle(IkiWiki::basename($prev_page))));
	$template->param(next_title=>
			 ($next_page and exists $pagestate{$next_page}{meta}{title}
			  ?  $pagestate{$next_page}{meta}{title}
			  : pagetitle(IkiWiki::basename($next_page))));

	$ret = $template->output;
    }

    return $ret;
} # preprocess

1;
