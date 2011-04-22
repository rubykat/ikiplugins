#!/usr/bin/perl
# Ikiwiki meta_parentlinks plugin.
# Uses titles from meta plugin
package IkiWiki::Plugin::meta_parentlinks;

use warnings;
use strict;
use IkiWiki 3.00;

sub import {
	hook(type => "parentlinks", id => "meta_parentlinks", call => \&parentlinks);
	hook(type => "pagetemplate", id => "meta_parentlinks", call => \&pagetemplate);
}

sub getsetup () {
	return 
		plugin => {
			safe => 1,
			rebuild => 1,
			section => "core",
		},
}

sub parentlinks ($) {
	my $page=shift;

	my @ret;
	my $path="";
	my $title=$config{wikiname};
	my $i=0;
	my $depth=0;
	my $height=0;

	my @pagepath=(split("/", $page));
	my $pagedepth=@pagepath;
	foreach my $dir (@pagepath) {
		next if $dir eq 'index';
		$depth=$i;
		$height=($pagedepth - $depth);
		push @ret, {
			url => urlto(bestlink($page, $path), $page),
			page => $title,
			depth => $depth,
			height => $height,
			"depth_$depth" => 1,
			"height_$height" => 1,
		};
		$path.="/".$dir;
		if (exists $pagestate{$dir}{meta}{title})
		{
		    $title=$pagestate{$dir}{meta}{title};
		}
		else
		{
		    $title=pagetitle($dir);
		}
		# add capitalization to the title
		$title =~ s/ (
			      (^\w)    #at the beginning of the line
			      |      # or
			      (\s\w)   #preceded by whitespace
			     )
		    /\U$1/xg;
		$i++;
	}
	return @ret;
}

sub pagetemplate (@) {
	my %params=@_;
        my $page=$params{page};
        my $template=$params{template};

	if ($template->query(name => "parentlinks") ||
 	   $template->query(name => "has_parentlinks")) {
		my @links=parentlinks($page);
		$template->param(parentlinks => \@links);
		$template->param(has_parentlinks => (@links > 0));
	}
}

1
