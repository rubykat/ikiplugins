#!/usr/bin/perl
# See doc/plugin/contrib/subset.mdwn for documentation.
package IkiWiki::Plugin::subset;
use warnings;
use strict;
=head1 NAME

IkiWiki::Plugin::subset - define and remember an often-used PageSpec, a subset of pages

=head1 VERSION

This describes version B<1.20110610> of IkiWiki::Plugin::subset

=cut

our $VERSION = '1.20110610';

=head1 PREREQUISITES

    IkiWiki

=head1 AUTHOR

    Kathryn Andersen (RUBYKAT)
    http://github.com/rubykat

=head1 COPYRIGHT

Copyright (c) 2009-2010 Kathryn Andersen

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
use IkiWiki 3.00;

my %OrigSubs = ();

sub import {
    hook(type => "getsetup", id => "subset", call => \&getsetup);
    hook(type => "checkconfig", id => "subset", call => \&checkconfig);
    hook(type => "preprocess", id => "subset", call => \&preprocess_subset);
    hook(type => "delete", id => "navdb", call => \&delete);
    hook(type => "change", id => "navdb", call => \&change);

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
    $wikistate{subset}{match_list}{$key} = undef;
    $wikistate{subset}{match_hash}{$key} = undef;
    $wikistate{subset}{sort}{$key} = $params{sort} if exists $params{sort};

    #This is used to display what subsets are defined.
    return sprintf(gettext("<b>subset(%s)</b>: `%s`"),
	$params{name}, $params{pages});
} # preprocess_subset

sub delete (@) {
    my @files=@_;

    if (!exists $wikistate{subset})
    {
	return;
    }
    my @subsets = (keys %{$wikistate{subset}{name}});

    # clear the subsets associated with these pages
    foreach my $subset (@subsets)
    {
	if (defined $wikistate{subset}{match_hash}{$subset})
	{
	    foreach my $file (@files)
	    {
		my $page=pagename($file);
		if ($wikistate{subset}{match_hash}{$subset}{$page})
		{
		    $wikistate{subset}{match_hash}{$subset} = undef;
		    $wikistate{subset}{match_list}{$subset} = undef;
		    last;
		}
	    }
	}
    }
} # delete

sub change (@) {
    my @files=@_;
    if (!exists $wikistate{subset})
    {
	return;
    }
    my @subsets = (keys %{$wikistate{subset}{name}});

    # clear the subsets associated with these pages
    foreach my $subset (@subsets)
    {
	if (defined $wikistate{subset}{match_hash}{$subset})
	{
	    foreach my $file (@files)
	    {
		my $page=pagename($file);
		if ($wikistate{subset}{match_hash}{$subset}{$page})
		{
		    $wikistate{subset}{match_hash}{$subset} = undef;
		    $wikistate{subset}{match_list}{$subset} = undef;
		    last;
		}
	    }
	}
    }
} # change

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
    # or if "subset" is the only thing in the pagespec
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
	if (defined $wikistate{subset}{match_list}{$subset_id})
	{
	    @subset = @{$wikistate{subset}{match_list}{$subset_id}};

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
	    my $old_num;
	    if (exists $wikistate{subset}{sort}{$subset_id})
	    {
		if ( exists $params{sort}
			and $params{sort} ne $wikistate{subset}{sort}{$subset_id})
		{
		    $old_sort = $params{sort};
		}
		$params{sort} = $wikistate{subset}{sort}{$subset_id};
	    }
	    if (exists $params{num} and $params{num})
	    {
		$old_num = $params{num};
		delete $params{num};
	    }
	    @subset = $OrigSubs{pagespec_match_list}->($page,
		"subset(${subset_id})",
		deptype=>deptype('presence'),
		%params);
	    $wikistate{subset}{match_list}{$subset_id} = \@subset;
	    # remember in a hash also
	    foreach my $k (@subset)
	    {
		$wikistate{subset}{match_hash}{$subset_id}{$k} = 1;
	    }
	    if ($old_sort)
	    {
		$params{sort} = $old_sort;
	    }
	    else
	    {
		delete $params{sort};
	    }
	    if ($old_num)
	    {
		$params{num} = $old_num;
	    }
	}
	if ($pagespec)
	{
	    return $OrigSubs{pagespec_match_list}->($page, $pagespec, %params,
		list=>\@subset);
	}
	else # empty pagespec means we just want the subset
	{
	    my @matching_pages = @subset;
	    if ($params{sort}) # we need to sort it, though!
	    {
		my $sort=IkiWiki::sortspec_translate($params{sort},
		    $params{reverse});
		@matching_pages=IkiWiki::SortSpec::sort_pages($sort,
		    @subset);
	    }
	    if ($params{num})
	    {
		@matching_pages = splice(@matching_pages, 0, $params{num});
	    }
	    return @matching_pages;
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
	if (defined $IkiWiki::wikistate{subset}{match_hash}{$subset})
	{
	    # if it's in the hash, it matches; if it isn't it doesn't
	    if ($IkiWiki::wikistate{subset}{match_hash}{$subset}{$page})
	    {
		return IkiWiki::SuccessReason->new("$page in subset $subset");
	    }
	    else
	    {
		return IkiWiki::FailReason->new("$page not in subset $subset");
	    }
	}
	else
	{
	    return IkiWiki::pagespec_match($page, $IkiWiki::wikistate{subset}{name}{$subset});
	}
    }
    else
    {
	return IkiWiki::FailReason->new("subset ($subset) not defined");
    }
} # match_subset

1
