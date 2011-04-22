#!/usr/bin/perl
# Ikiwiki tagger plugin. A more powerful tagging plugin.
package IkiWiki::Plugin::tagger;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "tagger",  call => \&getsetup);
	hook(type => "checkconfig", id => "tagger", call => \&checkconfig);
	hook(type => "scan", id => "tagger", call => \&scan);

	IkiWiki::loadplugin('field');
	IkiWiki::Plugin::field::field_register(id=>'tagger', call=>\&tagger_get_value);
}

# ===============================================
# Hooks
# ---------------------------
sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
		tagger_tags => {
			type => "hash",
			example => "tagger_tags => {'category' => '*', 'ingredients' => 'gusto/*', }",
			description => "define the tags and where they apply",
			safe => 0,
			rebuild => 1,
		},
}

sub checkconfig () {
    if (!exists $config{tagger_tags})
    {
	return error("\$config{tagger_tags} not defined");
    }
    IkiWiki::Plugin::field::field_register(id=>'tagger', call=>\&tagger_get_value);
}

sub scan (@) {
    my %params=@_;
    my $page = $params{page};

    my $page_file=$pagesources{$page};
    my $page_type=pagetype($page_file);
    if (!defined $page_type)
    {
	return;
    }
    # first clear any existing tags on this page
    if (exists $pagestate{$page}{tagger})
    {
	delete $pagestate{$page}{tagger};
    }
    # find out if there are field values for this page
    # and add hidden links
    foreach my $tag (keys %{$config{tagger_tags}})
    {
	my $match = $config{tagger_tags}->{$tag};
	if ($page =~ m!${match}!)
	{
	    scan_for_tag(%params, tag=>$tag, tagterm=>$tag);
	    # alternative labels for tag
	    if (exists $config{"tagger_alt_${tag}"}
		and $config{"tagger_alt_${tag}"})
	    {
		foreach my $alt_term (@{$config{"tagger_alt_${tag}"}})
		{
		    scan_for_tag(%params, tag=>$tag, tagterm=>$alt_term);
		}
	    }
	}
    }
} # scan

# ===============================================
# Field functions
# ---------------------------
sub tagger_get_value ($$) {
    my $field_name = shift;
    my $page = shift;

    if ($field_name =~ /^([-\w]+)-(link|linked)$/)
    {
	my $tag = lc($1);
	my $linktype = $2;
	if (exists $pagestate{$page}{tagger}{tags}{$tag})
	{
	    my @links = ();
	    my @tagorder = @{$pagestate{$page}{tagger}{tagorder}{$tag}};
	    if ($pagestate{$page}{tagger}{tagsep}{$tag} ne '/')
	    {
		@tagorder = sort @tagorder;
	    }
	    foreach my $key (@tagorder)
	    {
		my $tagpage = $pagestate{$page}{tagger}{tags}{$tag}{$key}->{page};
		my $label = $pagestate{$page}{tagger}{tags}{$tag}{$key}->{label};
		if (exists $pagestate{$tagpage}{meta}{title}
		    and $pagestate{$tagpage}{meta}{title})
		{
		    $label = $pagestate{$tagpage}{meta}{title};
		}
		my $link = bestlink($page, $tagpage);
		if ($link)
		{
		    push @links, "<a href='/${link}'>${label}</a>";
		}
		else
		{
		    push @links, htmllink($page, $page, "/$tagpage",
					  linktext=>$label);
		}
#		if ($linktype eq 'linked')
#		{
#		    push @links, htmllink($page, $page, "/$tagpage",
#					  linktext=>$label,
#					  absolute=>1);
#		}
#		else
#		{
#		    # Don't call htmllink, its too slow; just make an abs link
#		    push @links, "<a href='/${tagpage}'>${label}</a>";
#		}
	    }
	    my $separator = $pagestate{$page}{tagger}{tagsep}{$tag};
	    return (wantarray ? @links : join($separator, @links));
	}
    }
    elsif ($field_name =~ /^([-\w]+)-tagpage$/)
    {
	my $tag = lc($1);
	my $linktype = $2;
	if (exists $pagestate{$page}{tagger}{tags}{$tag})
	{
	    my @pages = ();
	    my @tagorder = @{$pagestate{$page}{tagger}{tagorder}{$tag}};
	    if ($pagestate{$page}{tagger}{tagsep}{$tag} ne '/')
	    {
		@tagorder = sort @tagorder;
	    }
	    foreach my $key (@tagorder)
	    {
		my $tagpage = $pagestate{$page}{tagger}{tags}{$tag}{$key}->{page};
		my $link = bestlink($page, $tagpage);
		if ($link)
		{
		    push @pages, $link;
		}
		else
		{
		    push @pages, $tagpage;
		}
	    }
	    my $separator = $pagestate{$page}{tagger}{tagsep}{$tag};
	    return (wantarray ? @pages : join($separator, @pages));
	}
    }
    else
    {
	my $tag = lc($field_name);
	if (exists $pagestate{$page}{tagger}{tags}{$tag})
	{
	    my $separator = $pagestate{$page}{tagger}{tagsep}{$tag};
	    my @tags = ();
	    foreach my $key (sort keys %{$pagestate{$page}{tagger}{tags}{$tag}})
	    {
		my $label = $pagestate{$page}{tagger}{tags}{$tag}{$key}->{label};
		push @tags, $label;
	    }
	    return (wantarray ? @tags : join($separator, @tags));
	}
    }
    return undef;
} # tagger_get_value

# ===============================================
# Private functions
# ---------------------------

sub scan_for_tag {
    my %params=@_;
    my $page = $params{page};
    my $tag = $params{tag};
    my $tagterm = $params{tagterm};

    my $value = undef;
    # tag: value
    if ($params{content} =~ /^\s*${tagterm}:\s*'(.*)'$/mi)
    {
	$value = $1;
    }
    elsif ($params{content} =~ /^\s*${tagterm}:\s*"(.*)"$/mi)
    {
	$value = $1;
    }
    elsif ($params{content} =~ /^\s*${tagterm}:\s*(.*)$/mi)
    {
	$value = $1;
    }
    # (:tag:value:)
    elsif ($params{content} =~ /\(:${tagterm}:\s*(.*?):\)/mi)
    {
	$value = $1;
    }
    if (defined $value and $value)
    {
	$value =~ s/,\s+/,/g;
	$value =~ s/\/\s+/\//g;
	$value =~ s/\s*\+\s+/\+/g;
	$value =~ s/_/ /g;
	my $tag_base = bestlink($page, $tag);
	my @tag_keys;
	my @tagvalues;
	my $separator = '';
	if ($value =~ /\//)
	{
	    @tag_keys = split(/\//, lc($value));
	    @tagvalues = split(/\//, $value);
	    $separator = '/';
	}
	elsif ($value =~ /\+/)
	{
	    @tag_keys = split(/\+/, lc($value));
	    @tagvalues = split(/\+/, $value);
	    $separator = ' + ';
	}
	else
	{
	    @tag_keys = split(/,/, lc($value));
	    @tagvalues = split(/,/, $value);
	    $separator = ', ';
	}
	if (@tagvalues)
	{
	    $pagestate{$page}{tagger}{tagsep}{$tagterm} = $separator;
	    $pagestate{$page}{tagger}{tagorder}{$tagterm} = [];
	    for (my $i=0; $i < @tag_keys; $i++)
	    {
		my $key = linkpage($tag_keys[$i]);
		my $val = $tagvalues[$i];
		my $tag_pagename=titlepage($val);
		my $tagpage = $tag_base . "/$tag_pagename";
		$pagestate{$page}{tagger}{tags}{$tagterm}->{$key}->{page} = $tagpage;
		$pagestate{$page}{tagger}{tags}{$tagterm}->{$key}->{label} = $val;
		$pagestate{$page}{tagger}{tags}{$tagterm}->{$key}->{term} = $tagterm;
		$pagestate{$page}{tagger}{tags}{$tagterm}->{$key}->{tag} = $tag;
		add_link($page, $tagpage);
		push @{$pagestate{$page}{tagger}{tagorder}{$tagterm}}, $key;

		# permuted index for quick lookup of pages that link
		# to a given tag-page
		my $tpc = lc($tagpage);
		if (!exists $pagestate{$tpc}{tagger}{links})
		{
		    $pagestate{$tpc}{tagger}{links} = {};
		}
		$pagestate{$tpc}{tagger}{links}{$page} = 1;
	    }
	}
    }
} # scan_for_tag

# ===============================================
# PageSpec functions
# ---------------------------

package IkiWiki::PageSpec;

sub match_tag_linked_to ($$;@) {
    my $page=shift;
    my $wanted=shift;
    my %params=@_;

    # Is the page linked to the given destination-page for a tag-link?
    # Basically a quick "link" test.
    # one argument: the tag-destination-page (full name)
    my $tag_page = lc($wanted);
    if (!exists $IkiWiki::pagestate{$tag_page}{tagger}{links}
	or !$IkiWiki::pagestate{$tag_page}{tagger}{links})
    {
	return IkiWiki::FailReason->new("$tag_page tag not a tag-page");
    }
    if (exists $IkiWiki::pagestate{$tag_page}{tagger}{links}{$page}
	and $IkiWiki::pagestate{$tag_page}{tagger}{links}{$page})
    {
	return IkiWiki::SuccessReason->new("$page links to $tag_page", $page => $IkiWiki::DEPEND_LINKS, "" => 1);
    }

    return IkiWiki::FailReason->new("$page does not link to $tag_page", "" => 1);
} # match_tag_linked_to

1;
