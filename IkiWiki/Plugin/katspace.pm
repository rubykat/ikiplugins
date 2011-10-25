#!/usr/bin/perl
# Ikiwiki katspace plugin; common customizations for my IkiWikis.
package IkiWiki::Plugin::katspace;
use warnings;
use strict;
=head1 NAME

IkiWiki::Plugin::katspace - customizations for the KatSpace site

=head1 VERSION

This describes version B<1.20110610> of IkiWiki::Plugin::katspace

=cut

our $VERSION = '1.20110610';

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
use YAML::Any;

my @NavLinks = (qw(
/about/
/computers/
/contact/
/enarrare/
/events/
/fandom/
/fiction/
/games/
/graphics/
/gusto/
/history/
/links/
/lists/
/sitemap/
/reviews/
/search/
/updates/
/zines/
));
my %NavLabels = (
'/about/' => 'About',
'/computers/' => 'Computers',
'/contact/' => 'Contact',
'/enarrare/' => 'Enarrare',
'/events/' => 'Events',
'/fandom/' => 'Fandoms',
'/fiction/' => 'Fan Fiction',
'/games/' => 'Games',
'/graphics/' => 'Graphics',
'/gusto/' => 'Gusto',
'/history/' => 'History',
'/links/' => 'Links',
'/lists/' => 'Lists',
'/sitemap/' => 'Site Map',
'/reviews/' => 'Reviews',
'/search/' => 'Search',
'/updates/' => 'Updates',
'/zines/' => 'Zines',
);

my %Data = ();

my %OrigSubs = ();

sub import {
	hook(type => "getsetup", id => "katspace", call => \&getsetup);

    IkiWiki::loadplugin("field");
    IkiWiki::Plugin::field::field_register(id=>'katspace',
	all_values=>\&all_katspace_vars, last=>1);

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
sub all_katspace_vars (@) {
    my %params=@_;
    my $page = $params{page};

    my %values = ();
    $values{navbar} = do_navbar($page);

    if ($page =~ /ficathon/)
    {
	foreach my $wt (qw(win tie))
	{
	    foreach my $fn (qw(fandom rating type description))
	    {
		$values{"${wt}${fn}"} = do_finishathon_winners($wt, $fn, $page, wantarray);
	    }
	}
	$values{bunnycount} = do_finishathon_bunny_count($page, wantarray);
	$values{fandomlist} = do_finishathon_fandom_list($page, wantarray);
    }
    if ($page =~ /stories/)
    {
	my $date = IkiWiki::Plugin::field::field_get_value('FicDate', $page);
	if ($date)
	{
	    $values{'FicDate-year'} = IkiWiki::Plugin::common_custom::common_vars_calc(page=>$page, value=>$date, id=>'year');
	    $values{'FicDate-month'} = IkiWiki::Plugin::common_custom::common_vars_calc(page=>$page, value=>$date, id=>'month');
	    $values{'FicDate-monthname'} = IkiWiki::Plugin::common_custom::common_vars_calc(page=>$page, value=>$values{'FicDate-month'}, id=>'monthname');
	}
    }

    return \%values;
} # all_katspace_vars

sub do_navbar ($$) {
    my $page = shift;

    my $current_url = IkiWiki::urlto($page, $page, 1);
    # strip off leading http://site stuff
    $current_url =~ s!https?://[^/]+!!;
    $current_url =~ s!//!/!g;

    my $tree = link_list(urls=>\@NavLinks,
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

sub do_finishathon_winners {
    my $field_prefix = shift;
    my $field_name = shift;
    my $page = shift;
    my $wantarray = shift;

    my $find_ind = 0;
    if ($field_prefix =~ /^WinTie/i)
    {
	$find_ind = IkiWiki::Plugin::field::field_get_value('WinnerTie',$page);
    }
    else
    {
	$find_ind = IkiWiki::Plugin::field::field_get_value('Winner',$page);
    }
    if ($find_ind)
    {
	my $value =
	    IkiWiki::Plugin::field::field_get_value($field_name . $find_ind,
						    $page);
	return ($wantarray ? ($value) : $value);
    }
    return undef;
} # do_finishathon_winners

sub do_finishathon_bunny_count {
    my $page = shift;
    my $wantarray = shift;

    my $bunny_count = 0;
    my @fandoms = ();
    for (my $i=1; $i <= 10; $i++)
    {
	$fandoms[$i] =
	    IkiWiki::Plugin::field::field_get_value("Fandom$i", $page);
	if ($fandoms[$i])
	{
	    $bunny_count++;
	}
    }
    return ($wantarray ? ($bunny_count) : $bunny_count);
} # do_finishathon_bunny_count

sub do_finishathon_fandom_list ($) {
    my $page = shift;
    my $wantarray = shift;

    my %fandom_count = ();
    for (my $i=1; $i <= 10; $i++)
    {
    	my $fd = 
	    IkiWiki::Plugin::field::field_get_value("Fandom$i", $page);
	if ($fd)
	{
	    if ($fandom_count{$fd})
	    {
		$fandom_count{$fd}++;
	    }
	    else
	    {
		$fandom_count{$fd} = 1;
	    }
	}
    }
    my @fandoms = sort keys %fandom_count;

    return ($wantarray ? @fandoms : join(', ', @fandoms));
}

1;
