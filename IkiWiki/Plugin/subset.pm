#!/usr/bin/perl
package IkiWiki::Plugin::subset;
# Ikiwiki PageSpec cache plugin.
# See doc/plugin/contrib/subset.mdwn for documentation.

use warnings;
use strict;
use IkiWiki 3.00;

my %OrigSubs = ();

sub import {
    hook(type => "getsetup", id => "subset", call => \&getsetup);
    hook(type => "checkconfig", id => "subset", call => \&checkconfig);
    hook(type => "preprocess", id => "subset", call => \&preprocess_subset);

    $OrigSubs{pagespec_match_list} = \&pagespec_match_list;
    inject(name => 'IkiWiki::pagespec_match_list', call => \&subset_pagespec_match_list);
}

# ===============================================
# Hooks
# ---------------------------

sub getsetup () {
    return
    plugin => {
	safe => 1,
	rebuild => undef,
	section => "widget",
    },
    subset_page => {
	type => "string",
	example => "subset_page => 'subsets'",
	description => "page to look for subset definitions",
	safe => 0,
	rebuild => undef,
    },
}

sub checkconfig () {
    if (defined $config{srcdir} && $config{srcdir}) {

	my $subset_page = ($config{subset_page}
	    ? $config{subset_page}
	    : 'subsets');
	$config{subset_page} = $subset_page;

	# Preprocess the subsets page to get all the available
	# subsets defined before other pages are rendered.

	my $srcfile=srcfile($subset_page.'.'.$config{default_pageext}, 1);
	if (! defined $srcfile) {
	    $srcfile=srcfile("${subset_page}.mdwn", 1);
	}
	if (! defined $srcfile) {
	    print STDERR sprintf(gettext("subset plugin will not work without %s"),
		$subset_page.'.'.$config{default_pageext})."\n";
	}
	else {
	    IkiWiki::preprocess($subset_page, $subset_page, readfile($srcfile));
	}
    }
}

sub preprocess_subset (@) {
    my %params=@_;

    if (! defined $params{name} || ! defined $params{pages}) {
	error gettext("missing name or pages parameter");
    }
    if ($params{name} !~ /^\w+$/)
    {
	error gettext(sprintf("name '%s' is not valid", $params{name}));
    }

    my $key = $params{name};
    $wikistate{subset}{name}{$key} = $params{pages};
    $wikistate{subset}{matches}{$key} = undef;
    $wikistate{subset}{sort}{$key} = $params{sort} if exists $params{sort};

    #This is used to display what subsets are defined.
    return sprintf(gettext("<b>subset(%s)</b>: `%s`"),
	$params{name}, $params{pages});
}

# ===============================================
# Private Functions
# ---------------------------

sub subset_pagespec_match_list ($$;@) {
    my $page=shift;
    my $pagespec=shift;
    my %params=@_;

    # if there's a list, use it immediately
    if (exists $params{list})
    {
	return $OrigSubs{pagespec_match_list}->($page, $pagespec, %params);
    }

    my $subset_id = '';
    # if "subset" is the first thing in the pagespec
    if ($pagespec =~ /^subset\((\w+)\)\s+and\s+(.*)$/so)
    {
	$subset_id = $1;
	$pagespec = $2;
    }
    elsif ($pagespec =~ /^subset\((\w+)\)\s*$/so)
    {
	$subset_id = $1;
	$pagespec = '';
    }
    elsif (exists $params{subset}) # if there's a separate "subset" param
    {
	$subset_id = $params{subset};
	delete $params{subset};
    }

    if ($subset_id and exists $wikistate{subset}{name}{$subset_id})
    {
	# Subset sorting:
	# Since a subset is stored as an array, it has an order.
	# If we don't want to have to keep on re-sorting the subset,
	# we can define a default sort for it, sort it once,
	# and only re-sort the results if the requested sort
	# is different from the default sort.
	
	my @subset;
	if (defined $wikistate{subset}{matches}{$subset_id})
	{
	    @subset = @{$wikistate{subset}{matches}{$subset_id}};

	    # Don't re-sort the results if the requested sort
	    # is the same as the default sort.
	    if (exists $wikistate{subset}{sort}{$subset_id}
		    and exists $params{sort}
		    and $params{sort} eq $wikistate{subset}{sort}{$subset_id})
	    {
		delete $params{sort};
	    }
	}
	else
	{
	    my $old_sort;
	    if (exists $wikistate{subset}{sort}{$subset_id})
	    {
		if ( exists $params{sort}
			and $params{sort} ne $wikistate{subset}{sort}{$subset_id})
		{
		    $old_sort = $params{sort};
		}
		$params{sort} = $wikistate{subset}{sort}{$subset_id};
	    }
	    @subset = $OrigSubs{pagespec_match_list}->($page,
		"subset(${subset_id})",
		deptype=>deptype('presence'),
		%params);
	    $wikistate{subset}{matches}{$subset_id} = \@subset;
	    if ($old_sort)
	    {
		$params{sort} = $old_sort;
	    }
	    else
	    {
		delete $params{sort};
	    }
	}
	if ($pagespec)
	{
	    return $OrigSubs{pagespec_match_list}->($page, $pagespec, %params,
		list=>\@subset);
	}
	else # empty pagespec means we just want the subset
	{
	    return @subset;
	}
    }

    return $OrigSubs{pagespec_match_list}->($page, $pagespec, %params);
} # subset_pagespec_match_list

# ===============================================
# PageSpec functions
# ---------------------------

package IkiWiki::PageSpec;

sub match_subset ($$;@) {
    my $page=shift;
    my $subset=shift;

    if (exists $IkiWiki::wikistate{subset}{name}{$subset})
    {
	return IkiWiki::pagespec_match($page, $IkiWiki::wikistate{subset}{name}{$subset});
    }
    else
    {
	return IkiWiki::FailReason->new("subset ($subset) not defined");
    }
} # match_subset

1
