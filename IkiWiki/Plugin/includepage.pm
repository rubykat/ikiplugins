#!/usr/bin/perl
# Include Page plugin
# Similar to inline, this includes the contents of another page into
# the current page, but this is much simpler and less featureful
# than inline.

package IkiWiki::Plugin::includepage;

use warnings;
use strict;
use IkiWiki 3.00;

my @included;
my $nested=0;

sub import {
	hook(type => "getsetup", id => "includepage", call => \&getsetup);
	hook(type => "preprocess", id => "includepage", call => \&preprocess_in);
	hook(type => "format", id => "includepage", call => \&format, first => 1);
}

#---------------------------------------------------------------
# Hooks
# --------------------------------

sub getsetup () {
	return
		plugin => {
			safe => 0,
			rebuild => undef,
		},
} # getsetup

sub format (@) {
        my %params=@_;

	# Fill in the included content generated earlier. This is actually an
	# optimisation.
	$params{content}=~s{<div class="includepage" id="([^"]+)"></div>}{
		delete @included[$1,]
	}eg;
	return $params{content};
}

sub preprocess_in (@) {
    my %params=@_;

    if (! exists $params{pagenames}) {
	error gettext("missing pagenames parameter");
    }
    my $quick=exists $params{quick} ? IkiWiki::yesno($params{quick}) : 0;
    my $raw=exists $params{raw} ? IkiWiki::yesno($params{raw}) : 0;
    my $class = ($params{class} ? $params{class} : 'includepage');

    my @list;
    @list = map { bestlink($params{page}, $_) } split ' ', $params{pagenames};

    if (IkiWiki::yesno($params{reverse})) {
	@list=reverse(@list);
    }

    foreach my $p (@list) {
	add_depends($params{page}, $p, deptype($quick ? "presence" : "content"));
    }

    my @in_stuff = ();
    foreach my $page (@list) {
	my $this_stuff = get_included_content($page, $params{destpage});
	$this_stuff = join('', ("<div class='$class'>\n", $this_stuff, "</div>")) if $this_stuff and !$raw;
	push @in_stuff, $this_stuff if $this_stuff;
    }
    my $ret = join("\n", @in_stuff);
    clear_included_content_cache();

    return $ret if $nested;
    push @included, $ret;
    return "<div class=\"includepage\" id=\"$#included\"></div>\n\n";
} # preprocess_in

#---------------------------------------------------------------
# Private functions
# --------------------------------

{
my %included_content;
my $cached_destpage="";

sub get_included_content ($$) {
    my $page=shift;
    my $destpage=shift;

    if (exists $included_content{$page} && $cached_destpage eq $destpage) {
	return $included_content{$page};
    }

    my $file=$pagesources{$page} || return '';
    my $type=pagetype($file);
    my $ret="";
    if (defined $type) {
	$nested++;
	$ret=IkiWiki::htmlize($page, $destpage, $type,
		     IkiWiki::linkify($page, $destpage,
			     IkiWiki::preprocess($page, $destpage,
					IkiWiki::filter($page, $destpage,
					       readfile(srcfile($file))))));
	$nested--;
    }
    elsif ($file) {
	$ret = readfile(srcfile($file));
    }

    if ($cached_destpage ne $destpage) {
	clear_included_content_cache();
	$cached_destpage=$destpage;
    }
    return $included_content{$page}=$ret;
}

sub clear_included_content_cache () {
	%included_content=();
}

}
1;
