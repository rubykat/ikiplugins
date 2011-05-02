#!/usr/bin/perl
# Ikiwiki permish plugin.
# Change permissions on generated files.
# Useful for things like the Apache XBitHack.
# Use with care on an open site.
package IkiWiki::Plugin::permish;

use warnings;
use strict;
use IkiWiki 3.00;
use Encode;
use File::Spec;
use File::Path;
use File::Temp ();

sub import {
	hook(type => "getsetup", id => "permish",  call => \&getsetup);
	hook(type => "checkconfig", id => "permish", call => \&checkconfig);
	hook(type => "change", id => "permish", call => \&change);
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
		permish_chmod => {
			type => "string",
			example => "permish_chmod=>'*'",
			description => "set the mod on matching pages",
			safe => 0,
			rebuild => 0,
		},
		permish_chmod_mode => {
			type => "string",
			example => "permish_chmod_mode=>'0644'",
			description => "the mode to set the pages to",
			safe => 0,
			rebuild => 0,
		},
		permish_chmod_ignore => {
			type => "string",
			example => "permish_chmod_ignore=>'nav_side'",
			description => "skip the *rendered* files that match",
			safe => 0,
			rebuild => 0,
		},
		permish_mtime => {
			type => "string",
			example => "permish_mtime=>'*'",
			description => "set the mtime of the matching pages",
			safe => 0,
			rebuild => 0,
		},
} # getsetup

sub checkconfig () {
    if (!defined $config{permish_chmod_mode})
    {
	$config{permish_chmod_mode} = '0644';
    }
} # checkconfig

sub change (@) {
    my @files=@_;
    if ($config{permish_chmod} or $config{permish_mtime})
    {
	foreach my $file (@files)
	{
	    my $page=pagename($file);
	    my $page_type=pagetype($file);
	    my $destfile = $config{destdir} . '/' . htmlpage($page);
	    if (-f $destfile)
	    {
		if ($page_type
		    and $config{permish_chmod}
		    and pagespec_match($page, $config{permish_chmod}))
		{
		    chmod oct($config{permish_chmod_mode}), $destfile;
		    # also check the files rendered by this page
		    if ($IkiWiki::renderedfiles{$page})
		    {
			foreach my $rf (@{$IkiWiki::renderedfiles{$page}})
			{
			    my $full_rf = $config{destdir} . '/' . $rf;
			    # only change permissions of html files
			    if ($rf =~ /\.($config{htmlext}|s?html?)$/
				and -f $full_rf
				and (!$config{permish_chmod_ignore}
				     or $rf !~ /$config{permish_chmod_ignore}/)
				)
			    {
				chmod oct($config{permish_chmod_mode}),
				    $full_rf;
			    }
			}
		    }
		}
		if ($config{permish_mtime}
		    and pagespec_match($page, $config{permish_mtime})
		    and $IkiWiki::pagemtime{$page})
		{
		    utime($IkiWiki::pagemtime{$page},
			  $IkiWiki::pagemtime{$page},
			  $destfile);
		}
	    }
	}
    } # if permish
} # change

1;
