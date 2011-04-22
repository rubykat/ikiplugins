#!/usr/bin/perl
# Table Of Contents generator
# which applies ToC to pages matching a PageSpec.
package IkiWiki::Plugin::gentoc;

use warnings;
use strict;
use IkiWiki 3.00;

# -------------------------------------------------------------------
# Globals
# -------------------------------------
my $TocObj;
my %TocPages;

# -------------------------------------------------------------------
# Import
# -------------------------------------
sub import {
	hook(type => "getsetup", id => "gentoc", call => \&getsetup);
	hook(type => "checkconfig", id => "gentoc", call => \&checkconfig);
	hook(type => "preprocess", id => "gentoc", call => \&preprocess);
	hook(type => "format", id => "gentoc", call => \&format);
}

# -------------------------------------------------------------------
# Hooks
# -------------------------------------
sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
			section => "widget",
		},
		gentoc_pages => {
			type => "string",
			example => "docs/*",
			description => "Which pages to give a ToC to",
			safe => 0,
			rebuild => undef,
		},
		gentoc_placeafter => {
			type => "string",
			example => "</h1>",
			description => "default placement of the ToC",
			safe => 0,
			rebuild => undef,
		},
		gentoc_defaults => {
			type => "hash",
			example => "gentoc_defaults => { ol => 1 }",
			description => "default arguments for gentoc",
			safe => 0,
			rebuild => undef,
		},
}

sub checkconfig () {
    eval q{use HTML::GenToc};
    if ($@)
    {
	error("pmap: HTML::GenToc failed to load");
	return 0;
    }
    if (!defined $config{gentoc_pages})
    {
	$config{gentoc_pages} = "* and !*.*";
    }
    if (!defined $config{gentoc_placeafter})
    {
	$config{gentoc_placeafter} = '</h1>';
    }
    if ($config{gentoc_defaults})
    {
	$TocObj = HTML::GenToc->new(%{$config{gentoc_defaults}},
	    use_id=>1,
	    inline=>1,
	    toc_tag=>'div id="gtoc"',
	    );
    }
    else
    {
	$TocObj = HTML::GenToc->new(
				    use_id=>1,
				    inline=>1,
				    toc_tag=>'div id="gtoc"',
				    );
    }
}


sub preprocess (@) {
    my %params=@_;

    $TocPages{$params{destpage}}=\%params;
    if ($params{page} eq $params{destpage}) {
	return "\n<div id=\"gtoc\"></div>\n";
    }
    else {
	# use the default location for inlined pages
	return "";
    }
}

sub format (@) {
    my %params=@_;
    my $content=$params{content};
    my $page=$params{page};

    if (!pagespec_match($page, $config{gentoc_pages}))
    {
	return $content;
    }

    # ------------------------------
    # Add the TOC tag if it isn't there
    if ($content !~ /<div id="gtoc"/o)
    {
	$content =~ s#($config{gentoc_placeafter})#${1}\n<div id="gtoc"></div>#i;
    }
    if (exists $TocPages{$page}->{class})
    {
	my $class = $TocPages{$page}->{class};
	$content =~ s#<div id="gtoc">#<div id="gtoc" class="$class">#;
	$TocPages{$page}->{toc_tag} = "div id=\"gtoc\" class=\"$class\"";
    }

    # ------------------------------
    # Generate the ToC
    $content = $TocObj->generate_toc(
	(exists $TocPages{$params{page}}
	? %{$TocPages{$params{page}}}
	: ()
	),
	input=>$content,
	to_string=>1);

    # ------------------------------
    # Remove the empty toc div if there wasn't a ToC
    $content =~ s!<div id="gtoc"[^>]*>\s*</div>!!os;

    return $content;
}

1
