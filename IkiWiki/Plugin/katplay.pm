#!/usr/bin/perl
package IkiWiki::Plugin::katplay;
use warnings;
use strict;
=head1 NAME

IkiWiki::Plugin::katplay - customizations for the KatPlay site

=head1 VERSION

This describes version B<1.20110610> of IkiWiki::Plugin::katplay

=cut

our $VERSION = '1.20110610';

=head1 PREREQUISITES

    IkiWiki
    File::Basename
    HTML::LinkList
    Sort::Naturally
    Fcntl
    Tie::File
    DBM::Deep
    YAML::Any
    IkiWiki::Plugin::field

=head1 AUTHOR

    Kathryn Andersen (RUBYKAT)
    http://github.com/rubykat

=head1 COPYRIGHT

Copyright (c) 2009-2011 Kathryn Andersen

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut

use IkiWiki 3.00;
use File::Basename;
use HTML::LinkList qw(link_list nav_tree);
use Sort::Naturally;
use Fcntl;
use Tie::File;
use DBM::Deep;
use YAML::Any;

my @NavLinks = (qw(
/action/
/addressbook/
/docs/
/episodes/
/gusto/
http://localhost/~kat/netfic/
/search/
/stories/
/text/
/wiki/
));
my %NavLabels = (
'/sitemap/' => 'Site Map',
);

my %Data = ();

my %OrigSubs = ();

sub import {
	hook(type => "getsetup", id => "katplay", call => \&getsetup);

    IkiWiki::loadplugin("field");
    IkiWiki::Plugin::field::field_register(id=>'katplay',
	all_values=>\&katplay_vars);

}

#-------------------------------------------------------
# Hooks
#-------------------------------------------------------
sub getsetup () {
	return
		plugin => {
			safe => 0,
			rebuild => 1,
		},
} # getsetup

#-------------------------------------------------------
# field functions
#-------------------------------------------------------
sub katplay_vars (@) {
    my %params=@_;
    my $page = $params{page};

    my %values = ();
    $values{navbar} = do_navbar($page);
    $values{navbar2} = do_navbar2($page);
    return \%values;
} # katplay_vars

sub do_navbar ($) {
    my $page = shift;

    my $current_url = IkiWiki::urlto($page, $page, 1);
    # strip off leading http://site stuff
    $current_url =~ s!https?://[^/]+!!;
    $current_url =~ s!//!/!g;

    my @navlinks = @NavLinks;
    @navlinks = sort(@navlinks);

    my $tree = link_list(urls=>\@navlinks,
			      labels=>\%NavLabels,
			      current_url=> $current_url,
			      pre_current_parent=>'<span class="current">',
			      post_current_parent=>'</span>',
			      links_head=>'<ul>',
			      links_foot=>'</ul>',
			      start_depth=>1,
			      end_depth=>1,
			      hide_ext=>1,
			      );
    return $tree;
} # do_navbar

sub do_navbar2 ($) {
    my $page = shift;

    my $current_url = IkiWiki::urlto($page, $page, 1);
    # strip off leading http://site stuff
    $current_url =~ s!https?://[^/]+!!;
    $current_url =~ s!//!/!g;

    my @wikitop = ();
    my $pages = "* and !*.* and !*/*";
    my @top_pages = pagespec_match_list($page, $pages,
					deptype=>deptype('presence'));
    foreach my $pn (@top_pages)
    {
	my $url = IkiWiki::urlto($pn, $pn, 1);
	$url =~ s!https?://[^/]+!!;
	$url =~ s!//!/!g;
	push @wikitop, $url;
    }

    @wikitop = sort(@wikitop);
    my $tree = link_list(urls=>\@wikitop,
			      labels=>\%NavLabels,
			      current_url=> $current_url,
			      pre_current_parent=>'<span class="current">',
			      post_current_parent=>'</span>',
			      links_head=>'<ul>',
			      links_foot=>'</ul>',
			      start_depth=>1,
			      end_depth=>1,
			      hide_ext=>1,
			      );

    return $tree;
} # do_navbar2

1;
