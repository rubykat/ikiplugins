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
	my $fetch_timestamp = IkiWiki::Plugin::field::field_get_value('fetch_datetime', $page);
	my $ctime = $IkiWiki::pagectime{$page};
	if ($timestamp and $timestamp ne $ctime)
	{
	    $IkiWiki::pagectime{$page}=$timestamp;
	    $ctime=$timestamp;
	}
	elsif ($fetch_timestamp and $fetch_timestamp ne $ctime)
	{
	    $IkiWiki::pagectime{$page}=$fetch_timestamp;
	    $ctime=$fetch_timestamp;
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
    elsif ($field_name =~ /^era$/i)
    {
        my $universe = IkiWiki::Plugin::field::field_get_value('universe', $page);
        if (defined $universe)
        {
            my $crossover = 0;
            if (ref $universe eq 'ARRAY')
            {
                $universe = join(' ', @{$universe}) if ref $universe eq 'ARRAY';
                $crossover = 1;
            }
            if ($universe =~ /Harry Potter/)
            {
                my $category = IkiWiki::Plugin::field::field_get_value('category', $page);
                $category = join(' ', @{$category}) if ref $category eq 'ARRAY';
                if ($category =~ /(Post-Voldemort|Voldemort-wins|Marauders|pre-Hogwarts|Hogwarts-era|Pre-Canon)/i)
                {
                    $value = $1
                }
                elsif ($category =~ /(First Year|Second Year|Third Year|Fourth Year|Fifth Year|Sixth Year|Seventh Year)/)
                {
                    $value = 'Hogwarts-era';
                }
                elsif ($category =~ /(Alternate Reality|Post-Apocalypse|Crossover)/)
                {
                    $value = $1
                }
                elsif ($crossover)
                {
                    $value = 'Crossover';
                }
            }
            elsif ($universe =~ /Doctor Who/)
            {
                my $characters = IkiWiki::Plugin::field::field_get_value('characters', $page);
                $characters = join(' ', @{$characters}) if ref $characters eq 'ARRAY';
                if (!$characters)
                {
                    $value = '99 Unknown Doctor';
                }
                else
                {
                    if ($characters =~ /First Doctor/)
                    {
                        $value = '01 First Doctor';
                    }
                    elsif ($characters =~ /Second Doctor/)
                    {
                        $value = '02 Second Doctor';
                    }
                    elsif ($characters =~ /Third Doctor/)
                    {
                        $value = '03 Third Doctor';
                    }
                    elsif ($characters =~ /Fourth Doctor/)
                    {
                        $value = '04 Fourth Doctor';
                    }
                    elsif ($characters =~ /Fifth Doctor/)
                    {
                        $value = '05 Fifth Doctor';
                    }
                    elsif ($characters =~ /Sixth Doctor/)
                    {
                        $value = '06 Sixth Doctor';
                    }
                    elsif ($characters =~ /Seventh Doctor/)
                    {
                        $value = '07 Seventh Doctor';
                    }
                    elsif ($characters =~ /Eighth Doctor/)
                    {
                        $value = '08 Eighth Doctor';
                    }
                    elsif ($characters =~ /Ninth Doctor/)
                    {
                        $value = '09 Ninth Doctor';
                    }
                    elsif ($characters =~ /Tenth Doctor/)
                    {
                        $value = '10 Tenth Doctor';
                    }
                    elsif ($characters =~ /Eleventh Doctor/)
                    {
                        $value = '11 Eleventh Doctor';
                    }
                    elsif ($characters =~ /Twelfth Doctor/)
                    {
                        $value = '12 Twelfth Doctor';
                    }
                    elsif ($characters =~ /Thirteenth Doctor/)
                    {
                        $value = '13 Thirteenth Doctor';
                    }
                    elsif ($characters =~ /Other Doctor/)
                    {
                        $value = '30 Other Doctor';
                    }
                    elsif ($characters =~ /Jo Grant/)
                    {
                        $value = '03 Third Doctor';
                    }
                    elsif ($characters =~ /(Leela|Romana|Harry Sullivan)/)
                    {
                        $value = '04 Fourth Doctor';
                    }
                    elsif ($characters =~ /(Tegan|Turlough|Adric|Nyssa)/)
                    {
                        $value = '05 Fifth Doctor';
                    }
                    elsif ($characters =~ /(Peri|Mel|Evelyn)/)
                    {
                        $value = '06 Sixth Doctor';
                    }
                    elsif ($characters =~ /(Ace|Benny)/)
                    {
                        $value = '07 Seventh Doctor';
                    }
                    elsif ($characters =~ /(Charley|Sam)/)
                    {
                        $value = '08 Eighth Doctor';
                    }
                    elsif ($characters =~ /(Donna|Martha)/)
                    {
                        $value = '10 Tenth Doctor';
                    }
                    elsif ($characters =~ /(Amy|Amelia|Rory)/)
                    {
                        $value = '11 Eleventh Doctor';
                    }
                    else
                    {
                        $value = '99 Unknown Doctor';
                    }
                }
            }
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
	if ($page =~ m{stories/}o)
	{
	    $value = 'A Stories';
	}
	elsif ($page =~ m{limbo/}o)
	{
	    $value = 'B Limbo';
	}
	elsif ($page =~ m{zoo/}o)
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
