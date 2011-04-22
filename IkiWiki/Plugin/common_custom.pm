#!/usr/bin/perl
# Ikiwiki common_custom plugin; common customizations for my IkiWikis.
package IkiWiki::Plugin::common_custom;

use warnings;
use strict;
use IkiWiki 3.00;
use File::Basename;

my %OrigSubs = ();

sub import {
	hook(type => "getsetup", id => "common_custom", call => \&getsetup);
	hook(type => "pagetemplate", id => "common_custom", call => \&pagetemplate);

    IkiWiki::loadplugin("field");
    IkiWiki::Plugin::field::field_register(id=>'common_custom',
						call=>\&common_vars);

    $OrigSubs{htmllink} = \&htmllink;
    inject(name => 'IkiWiki::htmllink', call => \&my_htmllink);
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
		common_custom_themes => {
			type => "array",
			example => "[qw{midblu green}]",
			description => "alternative site themes",
			safe => 0,
			rebuild => undef,
		},
} # getsetup

sub pagetemplate (@) {
    my %params=@_;
    my $template=$params{template};
    my $page=$params{page};

    if (defined $config{common_custom_themes})
    {
	my @themes = ();
	foreach my $theme (@{$config{common_custom_themes}})
	{
	    push @themes, {this_theme => $theme};
	}
	$template->param(more_themes => \@themes);
    }
}
#-------------------------------------------------------
# Injected functions
#-------------------------------------------------------

sub my_htmllink ($$$;@) {
	my $lpage=shift; # the page doing the linking
	my $page=shift; # the page that will contain the link (different for inline)
	my $link=shift;
	my %opts=@_;

	# if {{$page}} is there, do an immediate substitution
	$link =~ s/\{\{\$page\}\}/$lpage/sg;

	$link=~s/\/$//;

	my $bestlink;
	if (! $opts{forcesubpage}) {
		$bestlink=bestlink($lpage, $link);
	}
	else {
		$bestlink="$lpage/".lc($link);
	}

	my $linktext;
	if (defined $opts{linktext}) {
		$linktext=$opts{linktext};
	}
	else {
		$linktext=pagetitle(basename($link));
	}
	
	return "<span class=\"selflink\">$linktext</span>"
		if $bestlink && $page eq $bestlink &&
		   ! defined $opts{anchor};
	
	if (! $destsources{$bestlink}) {
		$bestlink=htmlpage($bestlink);

		if (! $destsources{$bestlink}) {
			return $linktext unless $config{cgiurl};
			return "<span class=\"createlink\"><a href=\"".
				IkiWiki::cgiurl(
					do => "create",
					page => $link,
					subpage => ($opts{forcesubpage} ? 1 : ''),
					from => ($opts{absolute} ? '' : $lpage),
				).
				"\" rel=\"nofollow\">$linktext ?</a></span>"
		}
	}
	
	$bestlink=IkiWiki::abs2rel($bestlink, IkiWiki::dirname(htmlpage($page)));
	$bestlink=IkiWiki::beautify_urlpath($bestlink);
	
	if (! $opts{noimageinline} && IkiWiki::isinlinableimage($bestlink)) {
		return "<img src=\"$bestlink\" alt=\"$linktext\" />";
	}

	if (defined $opts{anchor}) {
		$bestlink.="#".$opts{anchor};
	}

	my @attrs;
	foreach my $attr (qw{rel class title}) {
		if (defined $opts{$attr}) {
			push @attrs, " $attr=\"$opts{$attr}\"";
		}
	}

	return "<a href=\"$bestlink\"@attrs>$linktext</a>";
}

#-------------------------------------------------------
# field functions
#-------------------------------------------------------
sub common_vars ($$;$) {
    my $field_name = shift;
    my $page = shift;

    my $value = undef;
    if ($field_name eq 'pageterm')
    {
	# pagename as search term
	my $term = pagetitle(basename($page));
	$term =~ s#_#+#g;
	$value = $term;
    }
    elsif ($field_name eq 'namespaced')
    {
	my $namespaced = pagetitle(basename($page));
	$namespaced =~ s#_# #g;
	$namespaced =~ s#-# #g;
	$namespaced =~ s/([-\w]+)/\u\L$1/g;
	$value = $namespaced;
    }
    elsif ($field_name eq 'namespaced_no_ext')
    {
	my $namespaced = pagetitle(basename($page));
	$namespaced =~ s/\.\w+$//;
	$namespaced =~ s#_# #g;
	$namespaced =~ s#-# #g;
	$namespaced =~ s/([-\w]+)/\u\L$1/g;
	$value = $namespaced;
    }
    elsif ($field_name eq 'title'
	   and not exists $pagestate{$page}{meta}{title})
    {
	my $title = pagetitle(basename($page));
	$title =~ s#_# #g;
	$title =~ s#-# #g;
	$title =~ s/([-\w]+)/\u\L$1/g;
	$value = $title;
    }
    elsif ($field_name eq 'base_no_ext')
    {
	my $basename = IkiWiki::basename($page);
	$basename =~ s/\.\w+$//;
	$value = $basename;
    }
    elsif ($field_name eq 'name_a')
    {
	$value = uc(substr(IkiWiki::basename($page), 0, 1));
    }
    elsif ($field_name eq 'title_a')
    {
	my $title =
	    IkiWiki::Plugin::field::field_get_value('title',$page);
	$value = uc(substr($title, 0, 1));
    }
    elsif ($field_name eq 'local_css')
    {
	if (exists $config{local_css}
	    and defined $config{local_css})
	{
	    foreach my $ps (sort keys %{$config{local_css}})
	    {
		if (pagespec_match($page, $ps))
		{
		    $value = $config{local_css}{$ps};
		    last;
		}
	    }
	}
    }
    elsif ($field_name eq 'local_css2')
    {
	if (exists $config{local_css2}
	    and defined $config{local_css2})
	{
	    foreach my $ps (sort keys %{$config{local_css2}})
	    {
		if (pagespec_match($page, $ps))
		{
		    $value = $config{local_css2}{$ps};
		    last;
		}
	    }
	}
    }
    elsif ($field_name =~ /^(.*)-year$/i)
    {
	my $date_field = $1;
	my $date =
	    IkiWiki::Plugin::field::field_get_value($date_field,$page);
	if ($date)
	{
	    if ($date =~ /^\d{4}$/)
	    {
		$value = $date;
	    }
	    elsif ($date =~ /^(\d{4})-/)
	    {
		$value = $1;
	    }
	}
    }
    elsif ($field_name =~ /^(.*)-month$/i)
    {
	my $date_field = $1;
	my $date =
	    IkiWiki::Plugin::field::field_get_value($date_field,$page);
	if (!$date)
	{
	    $date =
		IkiWiki::Plugin::field::field_get_value("${date_field}-date",$page);
	}
	if ($date)
	{
	    if ($date =~ /^\d{4}$/)
	    {
		$value = 1;
	    }
	    elsif ($date =~ /^\d{4}-(\d{2})/)
	    {
		$value = $1;
	    }
	}
    }
    elsif ($field_name =~ /^(.*)-monthname$/i)
    {
	my $date_field = $1;
	my $month =
	    IkiWiki::Plugin::field::field_get_value("${date_field}-month",$page);
	$value = gettext($month == 1
		       ? 'January'
		       : ($month == 2
			  ? 'February'
			  : ($month == 3
			     ? 'March'
			     : ($month == 4
				? 'April'
				: ($month == 5
				   ? 'May'
				   : ($month == 6
				      ? 'June'
				      : ($month == 7
					 ? 'July'
					 : ($month == 8
					    ? 'August'
					    : ($month == 9
					       ? 'September'
					       : ($month == 10
						  ? 'October'
						  : ($month == 11
						     ? 'November'
						     : ($month == 12
							? 'December'
							: 'Unknown'
						       )
						    )
						 )
					      )
					   )
					)
				     )
				   )))));
    }
    if (defined $value)
    {
	return (wantarray ? ($value) : $value);
    }
    return undef;
} # common_vars

# ===============================================
# PageSpec functions
# ---------------------------

package IkiWiki::PageSpec;

sub match_links_from ($$;@) {
    my $page=shift;
    my $link_page=shift;
    my %params=@_;

    # Does $link_page link to $page?
    # Basically a fast "backlink" test; only works if the links are exact.

    # one argument: the source-page (full name)
    if (!exists $IkiWiki::links{$link_page}
	or !$IkiWiki::links{$link_page})
    {
	return IkiWiki::FailReason->new("$link_page has no links");
    }
    foreach my $link (@{$IkiWiki::links{$link_page}})
    {
	if (($page eq $link)
	    or ($link eq "/$page"))
	{
	    return IkiWiki::SuccessReason->new("$link_page links to $page", $page => $IkiWiki::DEPEND_LINKS, "" => 1);
	}
    }

    return IkiWiki::FailReason->new("$link_page does not link to $page", "" => 1);
} # match_links_from


1;
