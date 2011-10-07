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
use YAML::Any;

my %OrigSubs = ();

sub import {
	hook(type => "getsetup", id => "katplay", call => \&getsetup);

    IkiWiki::loadplugin("field");
    IkiWiki::Plugin::field::field_register(id=>'katplay',
	all_values=>\&katplay_vars);
    IkiWiki::Plugin::field::field_register(id=>'katplay2',
	all_values=>\&katplay_late_vars, last=>1);

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

    if ($page =~ /stories/)
    {
	my @bits = split(/\//, $page);
	# remove the actual page-file from this list
	pop @bits;
	my $found = 0;
	my $level = 0;
	while (@bits)
	{
	    my $s = shift @bits;
	    if ($found)
	    {
		$level++;
		$values{"section${level}"} = $s;
	    }
	    if ($s eq 'stories')
	    {
		$found = 1;
	    }
	}
    }
    my $baseurl = IkiWiki::baseurl($page);
    my @themes = (qw(b7 cloud cnblue gblue gblue2 gblue3 gold green green2 green3 iron irons ivy jungle lav lblue matrix midblu rainbow sand sfc silver stars sunset team tricolore turk violet yellow));
    my @tout = ();
    foreach my $theme (@themes)
    {
	push @tout, sprintf('<link rel="alternate stylesheet" title="%s" href="%sstyles/themes/theme_%s.css" type="text/css" />',
	    $theme,
	    $baseurl,
	    $theme);
    }
    $values{themes} = join("\n", @tout);
    return \%values;
} # katplay_vars

# these vars depend on other values
sub katplay_late_vars (@) {
    my %params=@_;
    my $page = $params{page};

    my %values = ();

    my $timestamp = IkiWiki::Plugin::field::field_get_value('timestamp', $page);
    my $ctime = $IkiWiki::pagectime{$page};
    if ($timestamp and $timestamp ne $ctime)
    {
	$IkiWiki::pagectime{$page}=$timestamp;
	$ctime=$timestamp;
    }
    my $longdate = IkiWiki::date_3339($ctime);
    $values{datelong} = $longdate;
    $values{date} = $longdate;
    $values{date} =~ s/T.*$//;
    if ($values{date} =~ /^(\d{4})-/)
    {
	$values{year} = $1;
    }
    if ($values{date} =~ /^\d{4}-(\d{2})/)
    {
	$values{month} = $1;
    }
    $values{monthname} = IkiWiki::Plugin::common_custom::common_vars_calc(page=>$page,
	value=>$values{month}, id=>'monthname');

    # Major characters are the first two characters
    my $char_loop = IkiWiki::Plugin::field::field_get_value('characters_loop', $page);
    if ($char_loop)
    {
	my @characters = @{$char_loop};
	$values{major_characters} = [];
	for (my $i = 0; $i < @characters; $i++)
	{
	    my $ch_hash = $characters[$i];
	    if ($i < 2)
	    {
		push @{$values{major_characters}}, $ch_hash->{characters};
	    }
	    else
	    {
		if (!exists $values{minor_characters})
		{
		    $values{minor_characters} = [];
		}
		push @{$values{minor_characters}}, $ch_hash->{characters};
	    }
	}
    }
    return \%values;
} # katplay_late_vars

1;
