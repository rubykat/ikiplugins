#!/usr/bin/perl
# HeadFoot plugin
# Add page header and/or page footer to the contents of a page, before the page
# is processed.

package IkiWiki::Plugin::headfoot;

use warnings;
use strict;
use IkiWiki 3.00;

my %HeadFoot = (
    head => {},
    foot => {},
);
my %HeadFootDone = ();
my %IsScanning = ();

sub import {
	hook(type => "getsetup", id => "headfoot", call => \&getsetup);
	hook(type => "checkconfig", id => "headfoot", call => \&checkconfig);
	hook(type => "pagetemplate", id => "headfoot", call => \&pagetemplate);

        # use an internal page for the included pages
	hook(type => "htmlize", id => "_inc", call => \&htmlize);
	
	# Depends on field plugin
	IkiWiki::loadplugin("field");
}

#---------------------------------------------------------------
# Hooks
# --------------------------------

sub getsetup () {
	return
		plugin => {
			safe => 0,
			rebuild => 1,
		},
} # getsetup

sub checkconfig () {
    return 1;
}

sub htmlize (@) {
    my %params=@_;
    my $page = $params{page};

    return $params{content};
}

sub pagetemplate (@) {
    my %params=@_;

    my $template=$params{template};
    foreach my $hf (qw{head foot})
    {
	if ($params{destpage} eq $params{page} &&
	    $template->query(name => "page_${hf}")) {
	    my $content=get_headfoot_content(hf_type=>$hf, %params);
	    if (defined $content && $content) {
		$template->param("page_${hf}" => $content);
	    }
	}
    }
}

#---------------------------------------------------------------
# Private functions
# --------------------------------

sub headfoot_page ($$) {
    my $page=shift;
    my $hf_type = shift;

    # Ask what the headfoot page is, if any
    my $headfoot_page =
	IkiWiki::Plugin::field::field_get_value("${hf_type}_page", $page) || return '';
    my $headfoot_file=$pagesources{$headfoot_page};
    if (!$headfoot_file)
    {
	$headfoot_page=bestlink($page, $headfoot_page) || return '';
	$headfoot_file=$pagesources{$headfoot_page} || return '';
    }
    return $headfoot_page;

} # headfoot_page

{
my %phead_cache = ();

sub clear_headfoot_content_cache () {
	%phead_cache=();
}

sub get_headfoot_content (%) {
    my %params=@_;
    my $page=$params{page};
    my $hf_type = $params{hf_type};

    my $phead_page=headfoot_page($page, $hf_type) || return;
    my $phead_file=$pagesources{$phead_page} || return;

    # use the type of the page this is going into
    my $page_file=$pagesources{$page} || return;
    my $page_type=pagetype($page_file);

    if (defined $page_type) {
	# FIXME: This isn't quite right; it won't take into account
	# adding a new phead page. So adding such a page
	# currently requires a wiki rebuild.
	add_depends($page, $phead_page);

	my $content;
	if (defined $phead_cache{$phead_file}) {
	    $content=$phead_cache{$phead_file};
	}
	else {
	    $content=readfile(srcfile($phead_file));
	    $phead_cache{$phead_file} = $content;
	}

	return unless $content;
	# process this content as if it were on the $page page
	return IkiWiki::htmlize
	    ($page, $page, $page_type,
	     IkiWiki::linkify($page, $page,
			      IkiWiki::preprocess
			      ($page, $page,
			       IkiWiki::filter
			       ($page, $page, $content))));
    }

} # get_headfoot_content
}


1;
