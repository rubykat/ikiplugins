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
	hook(type => "checkconfig", id => "belowme", call => \&checkconfig);
	hook(type => "needsbuild", id => "belowme", call => \&set_below_me);

    IkiWiki::loadplugin("field");
    IkiWiki::Plugin::field::field_register(id=>'belowme', first=>1);
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
		belowme_besideme => {
			type => "boolean",
			example => "belowme_besideme => 1",
			description => "record the 'beside-me' value as well as the 'below-me' value",
			safe => 0,
			rebuild => undef,
		},
} # getsetup

sub checkconfig () {

    if (!defined $config{belowme_besideme})
    {
	$config{belowme_besideme} = 1;
    }
} # checkconfig

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
    my %reset_me_files = ();
    my %reset_me = ();
    foreach my $file (@{$needsbuild}, @{$deleted})
    {
	my $page=pagename($file);
	if (!$deleted{$page})
	{
	    $reset_me{$page}++;
            $reset_me_files{$page} = $file;
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
            $reset_me_files{$parent_page} = '' if !defined $reset_me_files{$parent_page};
	}
    }

    # set the below-me values;
    foreach my $pp (keys %reset_me)
    {
	my %values = ();
	below_me($pp, $reset_me_files{$pp}, \%values);
	if (%values)
	{
	    $pagestate{$pp}{belowme}{pages_below_me} = $values{pages_below_me} if exists $values{pages_below_me};
	    $pagestate{$pp}{belowme}{files_below_me} = $values{files_below_me} if exists $values{files_below_me};
	    if ($config{belowme_besideme})
	    {
		# set their children values
		if (exists $values{pages_below_me}
			and $values{pages_below_me})
		{
		    foreach my $cp (@{$values{pages_below_me}})
		    {
			$pagestate{$cp}{belowme}{pages_beside_me} = $values{pages_below_me};
		    }
		}
	    }

	}
    }
} # set_below_me

#-------------------------------------------------------
# Private functions
#-------------------------------------------------------

sub below_me {
    my $page = shift;
    my $pagefile = shift;
    my $values = shift;

    # This figures out what is "below" this page;
    # the files in the directory associated with this page.
    my $srcdir = $config{srcdir};
    my $topdir = $srcdir;
    my $page_dir = File::Spec->catdir($srcdir, $page);
    my $full_page_file = File::Spec->catfile($srcdir, $pagefile);
    if ($page eq 'index')
    {
	$page_dir = $srcdir;
    }
    if (!-d $page_dir and !-e $full_page_file) # try to find the real dir
    {
        foreach my $dir (@{$config{underlaydirs}}, $config{underlaydir})
        {
            my $newdir = File::Spec->catdir($dir, $page);
            if ($pagefile)
            {
                $full_page_file = File::Spec->catfile($dir, $pagefile);
            }
            else
            {
                $full_page_file = $newdir;
            }
            if (-e $full_page_file)
            {
                # expect the directory to be below the file
                if (-d $newdir)
                {
                    $page_dir = $newdir;
                    $topdir = $dir;
                }
                last;
            }
        }
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
	    if ($file =~ m!$topdir/(.*)!)
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
