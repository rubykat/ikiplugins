#!/usr/bin/perl
package IkiWiki::Plugin::belowme;
use warnings;
use strict;
=head1 NAME

IkiWiki::Plugin::belowme - info about files and pages "below me"

=head1 VERSION

This describes version B<0.20110627> of IkiWiki::Plugin::belowme

=cut

our $VERSION = '0.20110627';

=head1 PREREQUISITES

    IkiWiki
    File::Basename

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
use File::Spec;
use Sort::Naturally;

sub import {
	hook(type => "getsetup", id => "belowme", call => \&getsetup);

    IkiWiki::loadplugin("field");
    IkiWiki::Plugin::field::field_register_precontent(id=>'belowme',
	call=>\&set_below_me);
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

sub set_below_me ($;$) {
    my $needsbuild = shift;
    my $deleted = shift;

    # Not only do the needsbuild pages need to be reset, but
    # the parent-pages of the given pages need to reset their
    # 'below_me' info

    my %deleted = ();
    foreach my $df (@{$deleted})
    {
	$deleted{$df} = 1;
    }
    my %reset_me = ();
    foreach my $file (@{$needsbuild}, @{$deleted})
    {
	my $page=pagename($file);
	if (!$deleted{$page})
	{
	    $reset_me{$page}++;
	}

	my $parent_page;
	if ($page =~ m{^(.*)/[-\.\w]+$}o)
	{
	    $parent_page = $1;
	}
	else # top-level page
	{
	    $parent_page = 'index';
	}
	if ($parent_page and !$deleted{$parent_page})
	{
	    $reset_me{$parent_page}++;
	}
    }

    # set the below-me values;
    my %all_values = ();
    foreach my $pp (keys %reset_me)
    {
	my %values = ();
	below_me($pp, \%values);
	if (%values)
	{
	    $all_values{$pp}{pages_below_me} = $values{pages_below_me} if exists $values{pages_below_me};
	    $all_values{$pp}{files_below_me} = $values{files_below_me} if exists $values{files_below_me};
	    # set their children values
#	    if (exists $values{pages_below_me}
#		    and $values{pages_below_me})
#	    {
#		foreach my $cp (@{$values{pages_below_me}})
#		{
#		    $all_values{$cp}{pages_beside_me} = $values{pages_below_me};
#		}
#	    }
	}
    }
    return \%all_values;
} # set_below_me

#-------------------------------------------------------
# Private functions
#-------------------------------------------------------

sub below_me {
    my $page = shift;
    my $values = shift;

    # This figures out what is "below" this page;
    # the files in the directory associated with this page.
    # Note that this does NOT take account of underlays.
    my $srcdir = $config{srcdir};
    my $page_dir = $srcdir . '/' . $page;
    if ($page eq 'index')
    {
	$page_dir = $srcdir;
    }
    if (-d $page_dir) # there is a page directory
    {
	my @files = <${page_dir}/*>;
	my %pagenames = ();
	my %filenames = ();
	my $pn_count = 0;
	my $fn_count = 0;
	foreach my $file (@files)
	{
	    if ($file =~ m!$srcdir/(.*)!)
	    {
		my $p = $1;
		if (pagetype($p))
		{
		    my $pn = pagename($p);
		    $pagenames{$pn} = 1 unless $pn eq $page;
		    $pn_count++;
		    $filenames{$pn} = 1;
		}
		else
		{
		    $filenames{$p} = 1;
		    $fn_count++;
		}
	    }
	}
	if ($pn_count and $fn_count)
	{
	    my @all_pages = (nsort(keys %pagenames));
	    $values->{pages_below_me} = \@all_pages;
	    my @all_files = (nsort(keys %filenames));
	    $values->{files_below_me} = \@all_files;
	}
	elsif ($pn_count)
	{
	    my @all_pages = (nsort(keys %pagenames));
	    $values->{pages_below_me} = \@all_pages;
	}
	elsif ($fn_count)
	{
	    my @all_files = (nsort(keys %filenames));
	    $values->{files_below_me} = \@all_files;
	}
    }
    return undef;
} # below_me

1;
