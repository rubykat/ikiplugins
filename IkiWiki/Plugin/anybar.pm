#!/usr/bin/perl
# Anybar plugin
# Generalization of the Sidebar plugin by Tuomo Valkonen

package IkiWiki::Plugin::anybar;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "getsetup", id => "anybar", call => \&getsetup);
	hook(type => "checkconfig", id => "headfoot", call => \&checkconfig);
	hook(type => "preprocess", id => "anybar", call => \&preprocess);
	hook(type => "pagetemplate", id => "anybar", call => \&pagetemplate);
}

#---------------------------------------------------------------
# Hooks
# --------------------------------

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 1,
		},
		anybar_names => {
			type => "array",
			example => "anybar_names => [qw(page_head page_foot)]",
			description => "list of page/variable names to treat as includes",
			safe => 1,
			rebuild => 1,
		},
		anybar_page_head => {
			type => "hash",
			example => "anybar_page_head => {'/foo/page_head' => '/foo/* or /bar/*'}",
			description => "which pages include which pages?",
			safe => 1,
			rebuild => 1,
		},
		anybar_no_page_head => {
			type => "string",
			example => "fiction/stories* and ! fiction/stories/*/*",
			description => "anybar exclusions",
			safe => 1,
			rebuild => 1,
		},
} # getsetup

sub checkconfig () {
    if (defined $config{anybar_names}
	and !ref $config{anybar_names})
    {
	# convert string to array
	$config{anybar_names} = [$config{anybar_names}];
    }
} # checkconfig

my %page_anybar_content = ();

sub preprocess (@) {
    my %params=@_;

    my $page=$params{page};
    my $ab_name = $params{name};
    return "" unless $page eq $params{destpage};
    return "" unless defined $ab_name;

    if (! defined $params{content}) {
	$page_anybar_content{$page}{$ab_name}=undef;
    }
    else {
	my $file = $pagesources{$page};
	my $type = pagetype($file);

	$page_anybar_content{$page}{$ab_name}=
	    IkiWiki::htmlize($page, $page, $type,
	    IkiWiki::linkify($page, $page,
	    IkiWiki::preprocess($page, $page, $params{content})));
    }

    return "";
} # preprocess

sub pagetemplate (@) {
    my %params=@_;

    if (defined $config{anybar_names}
	and $config{anybar_names})
    {
	my $template=$params{template};
	foreach my $an (@{$config{anybar_names}})
	{
	    if ($params{destpage} eq $params{page} &&
		$template->query(name => $an))
	    {
		my $content=get_anybar_content(%params,anybar_name=>$an);
		if (defined $content && $content)
		{
		    $template->param($an => $content);
		}
	    }
	}
    }
}
#---------------------------------------------------------------
# Private functions
# --------------------------------
my %anybar_cache = ();

sub which_anybar_page ($$) {
    my $page=shift;
    my $ab_name = shift;

    # Don't allow an anybar page to include itself (or any other anybar page)
    # That way lies madness.
    my $basename = IkiWiki::basename($page);
    foreach my $an (@{$config{anybar_names}})
    {
	if ($basename eq $an)
	{
	    return '';
	}
    }
    # Check if this page is excluded
    my $exclude_key = "anybar_no_${ab_name}";
    if (exists $config{$exclude_key}
	and defined $config{$exclude_key})
    {
	if (pagespec_match($page, $config{$exclude_key}))
	{
	    return '';
	}
    }

    my $ab_page = '';
    my $ab_file = '';
    my $conf_key = "anybar_${ab_name}";
    if (exists $config{$conf_key}
	and defined $config{$conf_key})
    {
	foreach my $abp (sort keys %{$config{$conf_key}})
	{
	    my $ps = $config{$conf_key}{$abp};
	    if (pagespec_match($page, $ps))
	    {
		$ab_page = $abp;
		$ab_file=$pagesources{$ab_page};
		last;
	    }
	}
    }
    if (!$ab_file)
    {
	$ab_page=bestlink($page, $ab_name) || return '';
	$ab_file=$pagesources{$ab_page} || return '';
    }

    return $ab_page;

} # which_anybar_page

sub get_anybar_content (%) {
    my %params=@_;
    my $page=$params{page};
    my $ab_name = $params{anybar_name};

    return delete $page_anybar_content{$page}{$ab_name}
    if defined $page_anybar_content{$page}{$ab_name};

    my $anybar_page=which_anybar_page($page, $ab_name) || return;
    my $anybar_file=$pagesources{$anybar_page} || return;
    my $anybar_type=pagetype($anybar_file);

    # if it doesn't have a type, use the type of the page this is going into
    if (!defined $anybar_type)
    {
	my $page_file=$pagesources{$page} || return;
	$anybar_type=pagetype($page_file);
    }

    if (defined $anybar_type) {
	# FIXME: This isn't quite right; it won't take into account
	# adding a new anybar page. So adding such a page
	# currently requires a wiki rebuild.
	add_depends($page, $anybar_page);

	my $content;
	if (defined $anybar_cache{$anybar_file}) {
	    $content=$anybar_cache{$anybar_file};
	}
	else {
	    $content=readfile(srcfile($anybar_file));
	    $anybar_cache{$anybar_file} = $content;
	}

	return unless $content;
#	return IkiWiki::htmlize($anybar_page, $page, $anybar_type,
#	       IkiWiki::linkify($anybar_page, $page,
#	       IkiWiki::preprocess($anybar_page, $page,
#	       IkiWiki::filter($anybar_page, $page, $content))));
	return IkiWiki::htmlize($page, $page, $anybar_type,
	       IkiWiki::linkify($page, $page,
	       IkiWiki::preprocess($page, $page,
	       IkiWiki::filter($page, $page, $content))));
    }

} # get_anybar_content

1;
