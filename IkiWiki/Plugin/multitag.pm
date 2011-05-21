#!/usr/bin/perl
# Ikiwiki multitag plugin.
package IkiWiki::Plugin::multitag;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "checkconfig", id => "multitag", call => \&checkconfig);
	hook(type => "getsetup", id => "multitag", call => \&getsetup);
	hook(type => "preprocess", id => "multitag", call => \&preprocess_multitag, scan => 1);

	IkiWiki::loadplugin("transient");
	IkiWiki::loadplugin("tag");
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
	if (! defined $config{tag_autocreate_commit}) {
		$config{tag_autocreate_commit} = 1;
	}
}

sub preprocess_multitag (@) {
    if (! @_) {
	return "";
    }
    my %params=@_;

    # get the known parameters
    my $page = $params{page};
    delete $params{page};
    my $destpage = $params{destpage};
    delete $params{destpage};
    my $preview = $params{preview};
    delete $params{preview};
    my $base = $params{base};
    delete $params{base};
    my $sep = $params{sep};
    delete $params{sep};
    my $tags = $params{tags};
    delete $params{tags};
    my $strip = $params{strip};
    delete $params{strip};

    my @tags = ($tags ? split(($sep ? $sep : ' '), $tags) : ());
    push @tags, (keys %params);
    my @links = ();
    foreach my $tag (@tags)
    {
	my $tagpage=$tag;
	if ($strip)
	{
	    $tagpage =~ s/\s//g;
	    $tagpage =~ s/[^0-9a-zA-Z]//g if ($strip eq 'alpha');
	}
	$tagpage=linkpage($tagpage);
	my $link = multitaglink($tagpage, $base);

	push @links, htmllink($page, $destpage, $link, linktext=>$tag);
	add_link($page, $link, ($base ? $base : 'tag'));

	genmultitag($tagpage, $base);
    }

    return join(' ', @links);
}

# -------------------------------------------------------------------
# Helper functions
# -------------------------------------

sub multitaglink ($$) {
    my $multitag = shift;
    my $tagbase = shift;

    if ($multitag !~ m{^/} &&
	defined $tagbase)
    {
	$multitag="/".$tagbase."/".$multitag;
	$multitag=~y#/#/#s; # squash dups
    }

    return $multitag;
}

# Returns a multitag name from a multitag link
sub multitagname ($$) {
    my $multitag=shift;
    my $tagbase = shift;

    if (defined $tagbase) {
	$multitag =~ s!^/\Q${tagbase}\E/!!;
    } else {
	$multitag =~ s!^\.?/!!;
    }
    return pagetitle($multitag, 1);
}

sub genmultitag ($$) {
    my $multitag=shift;
    my $tagbase = shift;

    if ($config{tag_autocreate} ||
	($tagbase && ! defined $config{tag_autocreate})) {
	my $multitagpage=multitaglink($multitag,$tagbase);
	if ($multitagpage=~/^\.\/(.*)/) {
	    $multitagpage=$1;
	}
	else {
	    $multitagpage=~s/^\///;
	}
	if (exists $IkiWiki::pagecase{lc $multitagpage}) {
	    $multitagpage=$IkiWiki::pagecase{lc $multitagpage}
	}

	my $multitagfile = newpagefile($multitagpage, $config{default_pageext});

	add_autofile($multitagfile, "multitag", sub {
		my $message=sprintf(gettext("creating multitag page %s"), $multitagpage);
		debug($message);

		my $template=template("autotag.tmpl");
		$template->param(tagname => multitagname($multitag,$tagbase));
		$template->param(tag => $multitag);

		my $dir = $config{srcdir};
		if (! $config{tag_autocreate_commit}) {
		    $dir = $IkiWiki::Plugin::transient::transientdir;
		}

		writefile($multitagfile, $dir, $template->output);
		if ($config{rcs} && $config{tag_autocreate_commit}) {
		    IkiWiki::disable_commit_hook();
		    IkiWiki::rcs_add($multitagfile);
		    IkiWiki::rcs_commit_smultitaged(message => $message);
		    IkiWiki::enable_commit_hook();
		}
	    });
    }
}


1;
