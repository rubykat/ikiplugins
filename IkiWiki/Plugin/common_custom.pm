#!/usr/bin/perl
# Ikiwiki common_custom plugin; common customizations for my IkiWikis.
package IkiWiki::Plugin::common_custom;
use warnings;
use strict;
=head1 NAME

IkiWiki::Plugin::common_custom - a bunch of personal customizations.

=head1 VERSION

This describes version B<1.20110610> of IkiWiki::Plugin::common_custom

=cut

our $VERSION = '1.20110610';

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

my %OrigSubs = ();

sub import {
	hook(type => "getsetup", id => "common_custom", call => \&getsetup);
	hook(type => "pagetemplate", id => "common_custom", call => \&pagetemplate);

    IkiWiki::loadplugin("field");
    IkiWiki::Plugin::field::field_register(id=>'common_custom',
	all_values=>\&all_common_vars);
    foreach my $id (qw(year month monthname date datelong))
    {
	IkiWiki::Plugin::field::field_register_calculation(
	    id=>$id,
	    call=>\&common_vars_calc);
    }

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
sub all_common_vars ($$) {
    my $field_name = shift;
    my $page = shift;

    my %values = ();
    my $basename = pagetitle(basename($page));

    # pagename as search term
    my $term = $basename;
    $term =~ s#_#+#g;
    $values{pageterm} = $term;

    my $namespaced = $basename;
    $namespaced =~ s#_# #g;
    $namespaced =~ s#-# #g;
    $namespaced =~ s/([-\w]+)/\u\L$1/g;
    $values{namespaced} = $namespaced;
    
    $namespaced = $basename;
    $namespaced =~ s/\.\w+$//;
    $namespaced =~ s#_# #g;
    $namespaced =~ s#-# #g;
    $namespaced =~ s/([-\w]+)/\u\L$1/g;
    $values{namespaced_no_ext} = $namespaced;

    if (not exists $pagestate{$page}{meta}{title})
    {
	my $title = $basename;
	$title =~ s#_# #g;
	$title =~ s#-# #g;
	$title =~ s/([-\w]+)/\u\L$1/g;
	$values{title} = $title;
    }

    $values{name_a} = uc(substr($basename, 0, 1));

    my $bn = $basename;
    $bn =~ s/\.\w+$//;
    $values{base_no_ext} = $bn;

    if (exists $config{local_css}
	    and defined $config{local_css})
    {
	foreach my $ps (sort keys %{$config{local_css}})
	{
	    if (pagespec_match($page, $ps))
	    {
		$values{local_css} = $config{local_css}{$ps};
		last;
	    }
	}
    }

    if (exists $config{local_css2}
	    and defined $config{local_css2})
    {
	foreach my $ps (sort keys %{$config{local_css2}})
	{
	    if (pagespec_match($page, $ps))
	    {
		$values{local_css2} = $config{local_css2}{$ps};
		last;
	    }
	}
    }

    if ($IkiWiki::pagemtime{$page})
    {
	my $mtime = IkiWiki::date_3339($IkiWiki::pagemtime{$page});
	$values{plain_mtime} = $mtime;
    }
    if ($IkiWiki::pagectime{$page})
    {
	my $ctime = IkiWiki::date_3339($IkiWiki::pagectime{$page});
	$values{plain_ctime} = $ctime;
    }

    return \%values;
} # all_common_vars

sub common_vars_calc (@) {
    my %params=@_;
    my $page = $params{page};
    my $value = $params{value};
    my $calc_id = $params{id};

    return $value if (!defined $value);

    if ($calc_id eq 'a')
    {
	$value = uc(substr($value, 0, 1));
    }
    elsif ($calc_id eq 'datelong')
    {
	$value = IkiWiki::date_3339($value);
    }
    elsif ($calc_id eq 'date')
    {
	$value = IkiWiki::date_3339($value);
	$value =~ s/T.*$//;
    }
    elsif ($calc_id eq 'year')
    {
	my $date = $value;
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
    elsif ($calc_id eq 'month')
    {
	my $date = $value;
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
    elsif ($calc_id eq 'monthname'
	    and defined $value
	    and $value =~ /^\d+$/)
    {
	my $month = $value;
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
	return $value;
    }
    return undef;
} # common_vars_calc

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

# ===============================================
# SortSpec functions
# ---------------------------
package IkiWiki::SortSpec;

sub cmp_page {

    my $left = $a;
    my $right = $b;

    $left = "" unless defined $left;
    $right = "" unless defined $right;
    return $left cmp $right;
}

1;
