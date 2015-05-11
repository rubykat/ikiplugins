#!/usr/bin/perl
package IkiWiki::Plugin::katplay;
use warnings;
use strict;
=head1 NAME

IkiWiki::Plugin::katplay - customizations for the KatPlay site

=head1 VERSION

This describes version B<1.20120105> of IkiWiki::Plugin::katplay

=cut

our $VERSION = '1.20120105';

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
	get_value=>\&katplay_get_value);

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
sub katplay_get_value ($$;@) {
    my $field_name = shift;
    my $page = shift;
    my %params = @_;

    my $value = undef;
    if ($field_name eq 'themes')
    {
	if ($config{kat_themes})
	{
	    my $baseurl = IkiWiki::baseurl($page);
	    my @themes = @{$config{kat_themes}};
	    my @tout = ();
	    foreach my $theme (@themes)
	    {
		push @tout, sprintf('<link rel="alternate stylesheet" title="%s" href="%sstyles/themes/theme_%s.css" type="text/css" />',
		    $theme,
		    $baseurl,
		    $theme);
	    }
	    $value = join("\n", @tout);
	}
    }
    elsif ($field_name =~ /^(datelong|date|year|month|monthname)$/)
    {
	my %vals = ();

	my $timestamp = IkiWiki::Plugin::field::field_get_value('timestamp', $page);
	my $ctime = $IkiWiki::pagectime{$page};
	if ($timestamp and $timestamp ne $ctime)
	{
	    $IkiWiki::pagectime{$page}=$timestamp;
	    $ctime=$timestamp;
	}
	my $longdate = IkiWiki::date_3339($ctime);
	$vals{datelong} = $longdate;
	$vals{date} = $longdate;
	$vals{date} =~ s/T.*$//;
	if ($vals{date} =~ /^(\d{4})-/)
	{
	    $vals{year} = $1;
	}
	if ($vals{date} =~ /^\d{4}-(\d{2})/)
	{
	    $vals{month} = $1;
	}
	$vals{monthname} = IkiWiki::Plugin::common_custom::common_vars_calc(page=>$page,
	    value=>$vals{month}, id=>'monthname');

	$value = $vals{$field_name};
    }
    elsif ($field_name =~ /^(major_characters|minor_characters)$/)
    {
	# Major characters are the first two characters
	my $char_loop = IkiWiki::Plugin::field::field_get_value('characters_loop', $page);
	if ($char_loop)
	{
	    my %vals = ();
	    my @characters = @{$char_loop};
	    $vals{major_characters} = [];
	    for (my $i = 0; $i < @characters; $i++)
	    {
		my $ch_hash = $characters[$i];
		if ($i < 2)
		{
		    push @{$vals{major_characters}}, $ch_hash->{characters};
		}
		else
		{
		    if (!exists $vals{minor_characters})
		    {
			$vals{minor_characters} = [];
		    }
		    push @{$vals{minor_characters}}, $ch_hash->{characters};
		}
	    }
	    $value = $vals{$field_name};
	}
    }
    elsif ($field_name =~ /gutenberg_?(id|url)?/)
    {
        my $type = ($1 ? $1 : 'id');
        if ($page =~ /stories/)
        {
            my $id;
            my $basename = pagetitle(basename($page));
            my $ext = '';
            my $bn = $basename;
            if ($basename =~ /(.*)\.(\w+)$/)
            {
                $bn = $1;
                $ext = $2;
            }
            if ($basename =~ /^(\d+)\.txt$/)
            {
                $id = $1;
            }
            elsif ($bn =~ /-([1-9]\d+)$/)
            {
                $id = $1;
            }
            elsif ($bn =~ /-pg(\d+)$/)
            {
                $id = $1;
            }
            if ($id)
            {
                if ($type eq 'url')
                {
                    $value = "http://www.gutenberg.org/ebooks/$id";
                }
                else
                {
                    $value = $id;
                }
            }
        }
    }
    elsif ($field_name =~ /^section(\d+)$/)
    {
        my $wanted_level = $1;
        my %vals = ();
        my @bits = split(/\//, $page);
        # remove the actual page-file from this list
        pop @bits;
        if ($page =~ /stories/)
        {
            my $found = 0;
            my $level = 0;
            while (@bits)
            {
                my $s = shift @bits;
                if ($found)
                {
                    $level++;
                    $vals{"section${level}"} = $s;
                }
                if ($s eq 'stories')
                {
                    $found = 1;
                }
            }
            $value = $vals{$field_name};
        }
        else
        {
            $value = $bits[$wanted_level];
        }
    }
    elsif ($field_name eq 'story_class')
    {
	if ($page =~ m{/stories/}o)
	{
	    $value = 'A Stories';
	}
	elsif ($page =~ m{/limbo/}o)
	{
	    $value = 'B Limbo';
	}
	elsif ($page =~ m{/zoo/}o)
	{
	    $value = 'Z Zoo';
	}
    }
    if ($page =~ /agito/)
    {
        if ($field_name eq 'giftee')
        {
            my $tdesc = IkiWiki::Plugin::field::field_get_value('task_description', $page);
            if ($tdesc
                and $tdesc =~ /present for\s+(.*)$/)
            {
                $value = $1
            }
        }
    }
    return $value;
} # katplay_get_value

1;
