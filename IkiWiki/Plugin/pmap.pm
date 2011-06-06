#!/usr/bin/perl
#
# Produce a hierarchical map of links.
# Uses HTML::LinkList and DBM::Deep
#
# based on map by Alessandro Dotti Contra <alessandro@hyboria.org>
#
# Revision: 0.2
package IkiWiki::Plugin::pmap;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "pmap", call => \&getsetup);
	hook(type => "checkconfig", id => "pmap", call => \&checkconfig);
	hook(type => "preprocess", id => "pmap", call => \&preprocess,
	     scan=>1);
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

sub checkconfig () {
    eval {use HTML::LinkList qw(nav_tree full_tree link_list breadcrumb_trail)};
    if ($@)
    {
	error("pmap: HTML::LinkList failed to load");
	return 0;
    }
    $config{pmap_sort_naturally} = 1;
    eval {use Sort::Naturally};
    if ($@)
    {
	$config{pmap_sort_naturally} = 0;
    }

} # checkconfig

sub preprocess (@) {
    my %params=@_;
    my $this_page = $params{page};
    my $destpage = $params{destpage};
    my $pages = (defined $params{pages} ? $params{pages} : '*');
    $pages =~ s/{{\$page}}/$this_page/g;
    my $show = $params{show};
    delete $params{show};
    my $map_type = (defined $params{map_type} ? $params{map_type} : '');

    # backwards-compatible (should use maketrail not doscan)
    if (!exists $params{maketrail} and exists $params{doscan})
    {
	$params{maketrail} = $params{doscan};
	delete $params{doscan};
    }
    my $scanning=! defined wantarray;

    if (exists $params{maketrail} and exists $params{trail})
    {
	error gettext("maketrail and trail are incompatible")
    }

    # disable scanning if we don't want it
    if ($scanning and !$params{maketrail})
    {
	return '';
    }

    # check if "field" plugin is enabled
    my $using_field_plugin = 0;
    if (UNIVERSAL::can("IkiWiki::Plugin::field", "import"))
    {
	$using_field_plugin = 1;
    }

    # Needs to update whenever a page is added or removed;
    # sometimes also when content is changed, if we care about that.
    my $deptype=deptype((exists $params{show} and !$params{quick})
			? "content" : "presence");

    # Get all the items to map.
    my @matching_pages;
    my @trailpages = ();
    if ($params{pagenames})
    {
	@matching_pages =
	    map { bestlink($params{page}, $_) } split ' ', $params{pagenames};
	foreach my $mp (@matching_pages)
	{
	    if ($mp ne $destpage)
	    {
		add_depends($destpage, $mp, $deptype);
	    }
	}
    }
    # "trail" means "all the pages linked to from a given page"
    # which is a bit looser than the PmWiki definition
    # but it will do
    elsif ($params{trail})
    {
	@trailpages = split(' ', $params{trail});
	foreach my $tp (@trailpages)
	{
	    foreach my $pn (@{$links{$tp}})
	    {
		# NEED to use bestlink because the links list
		# does not store absolute links
		push @matching_pages, bestlink($tp, $pn);
	    }
	}
	if ($params{pages})
	{
	    # filter out the pages that don't match
	    @matching_pages = pagespec_match_list($destpage, $params{pages},
		%params, deptype=>$deptype, list=>\@matching_pages);
	}
    }
    else
    {
	@matching_pages = pagespec_match_list($destpage, $pages,
					      %params,
					      deptype => $deptype);
    }

    if (!$params{trail}
	    and !$params{pagenames}
	    and !$params{subset})
    {
	if ($config{pmap_sort_naturally})
	{
	    @matching_pages = nsort(@matching_pages);
	}
	else
	{
	    @matching_pages = sort @matching_pages;
	}
    }

    # Only add dependencies when using trails IF we found matches
    if ($params{trail} and $#matching_pages > 0)
    {
	foreach my $tp (@trailpages)
	{
	    add_depends($destpage, $tp, deptype("links"));
	}
    }

    # If we are scanning, we only care about the list of pages we found.
    # (but we want to do the sort first, because we want to preserve
    # the order that we expect)
    # If "maketrail" is true, then add the found pages to the list of links
    # from this page.
    # Note that "maketrail" and "trail" are incompatible because one
    # cannot guarantee that the trail page has been scanned before
    # this current page.

    if ($scanning)
    {
	if ($params{maketrail} and !$params{trail})
	{
	    debug("pmap ($this_page) [$pages] NO MATCHING PAGES") if !@matching_pages;
	    foreach my $page (@matching_pages)
	    {
		add_link($this_page, $page);
	    }
	}
	return;
    }
    
    my @link_list = ();
    my %page_labels = ();
    my %page_desc = ();
    my $count = ($params{count}
		 ? ($params{count} < @matching_pages
		    ? $params{count}
		    : scalar @matching_pages
		   )
		 : scalar @matching_pages);
    my $min_depth = 100;
    my $max_depth = 0;
    for (my $i=0; $i < $count; $i++)
    {
	my $page = $matching_pages[$i];
	my $pd = page_depth($page);
	if ($pd < $min_depth)
	{
	    $min_depth = $pd;
	}
	if ($pd > $max_depth)
	{
	    $max_depth = $pd;
	}
	my $urlto = IkiWiki::urlto($page, $destpage, 1);
	# strip off leading http://site stuff
	$urlto =~ s!https?://[^/]+!!o;
	$urlto =~ s!^\s+!!o;
	$urlto =~ s!\s+$!!o;
	push @link_list, $urlto;

	if (defined $show
	    and exists $pagestate{$page}
	    and $show =~ /title/o)
	{
	    if (exists $pagestate{$page}{meta}{title})
	    {
		$page_labels{$urlto}=$pagestate{$page}{meta}{title};
		$page_labels{$urlto} =~ s/ & / &amp; /go;
	    }
	}
	if (defined $show
	    and exists $pagestate{$page}
	    and $show =~ /desc/o)
	{
	    if (exists $pagestate{$page}{meta}{description})
	    {
		$page_desc{$urlto}=$pagestate{$page}{meta}{description};
	    }
	    elsif ($using_field_plugin)
	    {
		$page_desc{$urlto}=
		    IkiWiki::Plugin::field::field_get_value('description', $page);
	    }
	}
    }

    # Create the map.
    if (! @link_list) {
	# return empty div for empty map
	return "<div class='map'></div>\n";
    } 

    # Note the current URL
    my $current_url = IkiWiki::urlto($destpage, $destpage, 1);
    # strip off leading http://site stuff
    $current_url =~ s!https?://[^/]+!!o;
    $current_url =~ s!//!/!go;
    $current_url =~ s!^\s+!!o;
    $current_url =~ s!\s+$!!o;

    # if all the pages are at the same depth, and the map_type is
    # not set, then set the map_type to 'list'
    $map_type = 'list' if (!$map_type and $min_depth == $max_depth);

    my $tree = ($map_type eq 'nav'
		   ? nav_tree(paths=>\@link_list,
			      preserve_paths=>1,
			      labels=>\%page_labels,
			      descriptions=>\%page_desc,
			      current_url=> $current_url,
			      %params)
		: ($map_type eq 'breadcrumb'
		   ? breadcrumb_trail(current_url=>$current_url,
				      labels=>\%page_labels)
		: ($map_type eq 'list'
		    ? link_list(urls=>\@link_list,
				labels=>\%page_labels,
				descriptions=>\%page_desc,
				current_url => $current_url,
				%params)
		: full_tree(paths=>\@link_list,
			      preserve_paths=>1,
			    labels=>\%page_labels,
			    descriptions=>\%page_desc,
			    current_url => $current_url,
			    %params)
		  )));


    return ($params{no_div} 
	    ? $tree
	    : "<div class='map'>$tree</div>\n");
}

# -------------------------------------------------------------------
# Helper functions
# -------------------------------------

sub page_depth {
    my $page = shift;

    return 0 if ($page eq 'index'); # root is zero
    return scalar ($page =~ tr!/!/!) + 1;
} # page_depth

# ===============================================
# PageSpec functions
# ---------------------------
package IkiWiki::PageSpec;

sub match_pmap_links_from ($$;@) {
    my $page=shift;
    my $link_page=shift;
    my %params=@_;

    # Does $link_page link to $page?
    # Basically a fast "backlink" test; only works if the links are exact.

    # one argument: the source-page (full name)
    if (!exists $IkiWiki::links{$link_page}
	or !$IkiWiki::links{$link_page})
    {
	return IkiWiki::FailReason->new("$link_page has no links");
    }
    foreach my $link (@{$IkiWiki::links{$link_page}})
    {
	if (($page eq $link)
	    or ($link eq "/$page"))
	{
	    return IkiWiki::SuccessReason->new("$link_page links to $page", $page => $IkiWiki::DEPEND_LINKS, "" => 1);
	}
    }

    return IkiWiki::FailReason->new("$link_page does not link to $page", "" => 1);
} # match_pmap_links_from
1;
