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

    if (! defined $params{name} || ! defined $params{set}) {
	error gettext("missing name or set parameter");
    }
    if ($params{name} !~ /^\w+$/)
    {
	error gettext(sprintf("name '%s' is not valid", $params{name}));
    }

    {
	my $key = $params{name};
	$pagestate{$params{page}}{subset}{name}{$key} = $params{set};
	$pagestate{$params{page}}{subset}{matches}{$key} = undef;

	no strict 'refs';
	no warnings 'redefine';

	my $subname = "IkiWiki::PageSpec::match_$key";
	*{ $subname } = sub {
	    my $path = shift;
	    return IkiWiki::pagespec_match($path, $params{set});
	}
    }

    #This is used to display what subsets are defined.
    return sprintf(gettext("subset <b>%s()</b> is <i>%s</i>"),
	$params{name}, $params{set});
}

# ===============================================
# Private Functions
# ---------------------------

sub subset_pagespec_match_list ($$;@) {
    my $page=shift;
    my $pagespec=shift;
    my %params=@_;

    if (exists $params{list})
    {
	return $OrigSubs{pagespec_match_list}->($page, $pagespec, %params);
    }
    elsif (exists $params{subset}
	    and exists $pagestate{$config{subset_page}}{subset}{name}{$params{subset}})
    {
	my @subset;
	my $subset_spec = $params{subset};
	delete $params{subset};
	if (defined $pagestate{$config{subset_page}}{subset}{matches}{$subset_spec})
	{
	    @subset = @{$pagestate{$config{subset_page}}{subset}{matches}{$subset_spec}};
	}
	else
	{
	    @subset = $OrigSubs{pagespec_match_list}->($page, "${subset_spec}()", %params);
	    $pagestate{$config{subset_page}}{subset}{matches}{$subset_spec} = \@subset;
	}
	return $OrigSubs{pagespec_match_list}->($page, $pagespec, %params,
	    list=>\@subset);
    }

    return $OrigSubs{pagespec_match_list}->($page, $pagespec, %params);
} # subset_pagespec_match_list

1
