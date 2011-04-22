#!/usr/bin/perl
# Ikiwiki katspace plugin; common customizations for my IkiWikis.
package IkiWiki::Plugin::katspace;

use warnings;
use strict;
use IkiWiki 3.00;
use File::Basename;
use HTML::LinkList qw(link_list nav_tree);
use Sort::Naturally;
use Fcntl;
use Tie::File;
use DBM::Deep;
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
						call=>\&katspace_vars);

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
sub katspace_vars ($$;$) {
    my $field_name = shift;
    my $page = shift;

    my $value = undef;
    if ($field_name eq 'navbar')
    {
	$value = do_navbar($page);
    }
    elsif ($field_name =~ /^year$/i)
    {
	$value =
	    IkiWiki::Plugin::field::field_get_value('FicDate-year',$page);
    }
    elsif ($field_name =~ /^month$/i)
    {
	$value =
	    IkiWiki::Plugin::field::field_get_value('FicDate-month',$page);
    }
    elsif ($field_name =~ /^monthname$/i)
    {
	$value =
	    IkiWiki::Plugin::field::field_get_value('FicDate-monthname',$page);
    }
    elsif ($field_name =~ /^(win(?:tie)?)(fandom|rating|type|description)/oi)
    {
	return do_finishathon_winners($1, $2, $page, wantarray);
    }
    elsif ($field_name eq 'bunnycount')
    {
	return do_finishathon_bunny_count($page, wantarray);
    }
    elsif ($field_name eq 'fandomlist')
    {
	return do_finishathon_fandom_list($page, wantarray);
    }
    elsif ($field_name =~ /^([-\w]+)-tarball$/o)
    {
	my $proj = $1;
	$value = tool_tarball($page, $proj);
    }
    if (defined $value)
    {
	return (wantarray ? ($value) : $value);
    }
    return undef;
} # katspace_vars

sub tool_tarball ($$) {
    my $page = shift;
    my $proj = shift;

    my $page_file=srcfile($pagesources{$page}) || return '';
    my $dir = dirname($page_file) . '/' . IkiWiki::basename($page);
    my $tb = `ls $dir/${proj}*.tar.gz`;
    $tb = basename($tb);
    return $tb;
} # tool_tarball

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
