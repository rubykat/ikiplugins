#!/usr/bin/perl
# Ikiwiki fauxinclude plugin.
# Make separate files with templates, to be included later with SSI.
# This is useful for dynamic navigation.
# The reason for having dynamic navigation is so that
# the whole site doesn't have to be rebuilt when a new page is added
# or a page is deleted.
package IkiWiki::Plugin::fauxinclude;

use warnings;
use strict;
use IkiWiki 3.00;
use Encode;
use File::Spec;
use File::Path;
use File::Temp ();

sub import {
	hook(type => "getsetup", id => "fauxinclude",  call => \&getsetup);
	hook(type => "checkconfig", id => "fauxinclude", call => \&checkconfig);
	hook(type => "change", id => "fauxinclude", call => \&change);
	hook(type => "scan", id => "fauxinclude", call => \&scan);
}

# ------------------------------------------------------------
# Hooks
# ----------------------------
sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
		fauxinclude_files => {
			type => "hash",
			example => "fauxinclude_files => {'nav_side1.tmpl' => 'nav_side'}",
			description => "which files are created by which templates",
			safe => 0,
			rebuild => 0,
		},
		fauxinclude_pages => {
			type => "hash",
			example => "fauxinclude_pages => {'nav_side1.tmpl' => '* and !*.* and !*/*/*'}",
			description => "which templates to apply to which pages",
			safe => 0,
			rebuild => 0,
		},
} # getsetup

sub checkconfig () {
	foreach my $required (qw(fauxinclude_files fauxinclude_pages)) {
		if (! length $config{$required}) {
			error(sprintf(gettext("Must specify %s when using the %s plugin"), $required, 'fauxinclude'));
		}
	}
} # checkconfig

sub scan (@) {
    my %params=@_;
    my $page=$params{page};

    my $page_file = $pagesources{$params{page}};
    my $page_type=pagetype($page_file);
    if ($page_type)
    {
	while (my ($tmpl, $ps) = each %{$config{fauxinclude_pages}})
	{
	    if (pagespec_match($page, $ps))
	    {
		gen_navpages(page=>$page,
			     template=>$tmpl,
			     file=>$config{fauxinclude_files}->{$tmpl},
			     scan=>1);
	    }
	}
    }
} # scan

sub change (@) {
    my @files=@_;
    foreach my $file (@files)
    {
	my $page=pagename($file);
	my $page_type=pagetype($file);
	if ($page_type)
	{
	    while (my ($tmpl, $ps) = each %{$config{fauxinclude_pages}})
	    {
		if (pagespec_match($page, $ps))
		{
		    gen_navpages(page=>$page,
				 template=>$tmpl,
				 file=>$config{fauxinclude_files}->{$tmpl},
				 scan=>0);
		}
	    }
	}
    }
} # change

# ------------------------------------------------------------
# Private Functions
# ----------------------------
sub gen_navpages (@) {
    my %params = @_;
    my $page = $params{page};
    my $tmpl = $params{template};
    my $base = $params{file};

    my $newfile = '';
    if ($page eq 'index')
    {
	$newfile = "$page-${base}." . $config{htmlext};
    }
    else
    {
	$newfile = "$page/${base}." . $config{htmlext};
    }

    if ($params{scan})
    {
	will_render($page, $newfile);
    }
    else
    {
	my $message = sprintf(gettext("creating fauxinclude file %s"),
			      $newfile);
	debug($message);

	my $content = IkiWiki::Plugin::ftemplate::preprocess(
							     page=>$page,
							     destpage=>$page,
							     to=>$page,
							     id=>$tmpl,
							    );
	writefile($newfile, $config{destdir}, $content);
    }
} # gen_navpages
1;
