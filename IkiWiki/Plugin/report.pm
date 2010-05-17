#!/usr/bin/perl
package IkiWiki::Plugin::report;
use strict;
=head1 NAME

IkiWiki::Plugin::report - Produce templated reports from page field data.

=head1 VERSION

This describes version B<0.10> of IkiWiki::Plugin::report

=cut

our $VERSION = '0.10';

=head1 PREREQUISITES

    IkiWiki
    IkiWiki::Plugin::field
    HTML::Template
    Encode

=head1 AUTHOR

    Kathryn Andersen (RUBYKAT)
    http://github.com/rubykat

=head1 COPYRIGHT

Copyright (c) 2009 Kathryn Andersen

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
use IkiWiki 3.00;
use HTML::Template;
use Encode;

sub import {
	hook(type => "getsetup", id => "report", call => \&getsetup);
	hook(type => "preprocess", id => "report", call => \&preprocess, scan=>1);

	IkiWiki::loadplugin("field");
}

# -------------------------------------------------------------------
# Hooks
# -------------------------------------
sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
}

sub preprocess (@) {
    my %params=@_;

    if (! exists $params{template}) {
	error gettext("missing template parameter");
    }
    if (exists $params{doscan} and exists $params{trail})
    {
	error gettext("doscan and trail are incompatible");
    }

    # disable scanning if we don't want it
    my $scanning=! defined wantarray;
    if ($scanning and !$params{doscan})
    {
	return '';
    }

    my $this_page = $params{page};
    delete $params{page};
    my $pages = (defined $params{pages} ? $params{pages} : '*');
    $pages =~ s/{{\$page}}/$this_page/g;

    my $template;
    eval {
	$template=template_depends($params{template}, $params{page},
				   blind_cache => 1);
    };
    if ($@) {
	error gettext("failed to process template $params{id}:")." $@";
    }
    if (! $template) {
	# look for .tmpl template (in global templates dir)
	eval {
	    $template=template("$params{template}.tmpl",
				       blind_cache => 1);
	};
	if ($@) {
	    error gettext("failed to process template $params{id}.tmpl:")." $@";
	}
	if (! $template) {

	    error sprintf(gettext("%s not found"),
			  htmllink($params{page}, $params{destpage},
				   "/templates/$params{template}"))
	}
    }
    delete $params{template};

    my $deptype=deptype($params{quick} ? 'presence' : 'content');

    my @matching_pages;
    # "trail" means "all the pages linked to from a given page"
    # which is a bit looser than the PmWiki definition
    # but it will do
    my @trailpages = ();
    if ($params{trail})
    {
	@trailpages = split(' ', $params{trail});
	foreach my $tp (@trailpages)
	{
	    foreach my $ln (@{$links{$tp}})
	    {
		my $bl = bestlink($tp, $ln);
		if ($bl)
		{
		    push @matching_pages, $bl;
		}
	    }
	}
	if ($params{pages})
	{
	    # filter out the pages that don't match
	    my @filtered = ();
	    my $result=0;
	    foreach my $mp (@matching_pages)
	    {
		$result=pagespec_match($mp, $params{pages});
		if ($result)
		{
		    push @filtered, $mp;
		    add_depends($this_page, $mp, $deptype);
		}
	    }
	    @matching_pages = @filtered;
	}
	if (!$params{here_only})
	{
	    debug("report found " . scalar @matching_pages . " pages");
	}
	# Because we used a trail, we have to sort the pages ourselves.
	# This code is cribbed from pagespec_match_list
	if ($params{sort})
	{
	    my $sort=IkiWiki::sortspec_translate($params{sort},
						 $params{reverse});
	    @matching_pages=IkiWiki::SortSpec::sort_pages($sort,
							  @matching_pages);
	}
    }
    else
    {
	@matching_pages = pagespec_match_list($params{destpage}, $pages,
					      %params,
					      deptype => $deptype);
    }

    # ------------------------------------------------------------------
    # If we want this report to be in "here_only", that is,
    # the current page ($this_page) and the previous page
    # and the next page only, we need to find the current page
    # in the list of matching pages, and set the matching
    # pages to those three pages.
    my @here_only = ();
    my $this_page_ind;
    if ($params{here_only})
    {
	for (my $i=0; $i < @matching_pages; $i++)
	{
	    if ($matching_pages[$i] eq $this_page)
	    {
		if ($i > 0)
		{
		    push @here_only, $matching_pages[$i-1];
		    push @here_only, $matching_pages[$i];
		    $this_page_ind = 1;
		}
		else
		{
		    push @here_only, $matching_pages[$i];
		    $this_page_ind = 0;
		}
		if ($i < $#matching_pages)
		{
		    push @here_only, $matching_pages[$i+1];
		}
		last;
	    }
	} # for all matching pages
	@matching_pages = @here_only;
    }
    # only add the dependency on the trail pages
    # if we found matches
    if ($params{trail} and $#matching_pages > 0)
    {
	foreach my $tp (@trailpages)
	{
	    add_depends($this_page, $tp, deptype("links"));
	}
    }
    ##debug("report($this_page) found " . scalar @matching_pages . " pages");

    # ------------------------------------------------------------------
    # If we are scanning, we only care about the list of pages we found.
    # If "doscan" is true, then add the found pages to the list of links
    # from this page.
    # Note that "doscan" and "trail" are incompatible because one
    # cannot guarantee that the trail page has been scanned before
    # this current page.

    if ($scanning)
    {
	if ($params{doscan} and !$params{trail})
	{
	    debug("report ($this_page) NO MATCHING PAGES") if !@matching_pages;
	    foreach my $page (@matching_pages)
	    {
		add_link($this_page, $page);
	    }
	}
	return;
    }

    # build up the report
    #
    my @report = ();

    my $start = ($params{here_only} ? $this_page_ind : 0);
    my $stop = ($params{here_only}
		? $this_page_ind + 1
		: ($params{count}
		   ? ($params{count} < @matching_pages
		      ? $params{count}
		      : scalar @matching_pages
		     )
		   : scalar @matching_pages)
	       );
    my @header_fields = ($params{headers} ? split(' ', $params{headers}) : ());
    delete $params{headers};
    my @prev_headers = ();
    for (my $j=0; $j < @header_fields; $j++)
    {
	$prev_headers[$j] = '';
    }
    for (my $i=$start; $i < $stop and $i < @matching_pages; $i++)
    {
	my $page = $matching_pages[$i];
	my $prev_page = ($i > 0 ? $matching_pages[$i-1] : '');
	my $next_page = ($i < $#matching_pages ? $matching_pages[$i+1] : '');
	my $first = ($page eq $matching_pages[0]);
	my $last = ($page eq $matching_pages[$#matching_pages]);
	my @header_values = ();
	foreach my $fn (@header_fields)
	{
	    my $val =
		IkiWiki::Plugin::field::field_get_value($fn, $page);
	    $val = '' if !defined $val;
	    push @header_values, $val;
	}
	my $rowr = do_one_template(
	    %params,
	    template=>$template,
	    page=>$page,
	    prev_page=>$prev_page,
	    next_page=>$next_page,
	    destpage=>$params{destpage},
	    first=>$first,
	    last=>$last,
	    scan=>$scanning,
	    headers=>\@header_values,
	    prev_headers=>\@prev_headers,
	);
	for (my $j=0; $j < @header_fields; $j++)
	{
	    if ($header_values[$j] ne $prev_headers[$j])
	    {
		$prev_headers[$j] = $header_values[$j];
	    }
	}
	push @report, $rowr;
    }

    if (! @report) {
	return '';
    } 
    my $output = join('', @report);

    return $output;
}

sub do_one_template (@) {
    my %params=@_;

    my $scan = $params{scan};
    my $template = $params{template};
    delete $params{template};

    $params{included}=($params{page} ne $params{destpage});

    $template->clear_params(); # don't accidentally repeat values
    IkiWiki::Plugin::field::field_set_template_values($template, $params{page},
	 value_fn => sub {
	    my $field = shift;
	    my $page = shift;
	    return report_get_value($field, $page, %params);
	 },);
    # -------------------------------------------------
    # headers
    for (my $i=0; $i < @{$params{headers}}; $i++) # clear the headers
    {
	my $hname = "header" . ($i + 1);
	$template->param($hname => '');
    }
    for (my $i=0; $i < @{$params{headers}}; $i++)
    {
	my $hname = "header" . ($i + 1);
	if ($params{headers}[$i] ne $params{prev_headers}[$i])
	{
	    $template->param($hname => $params{headers}[$i]);
	    # change the lower-level headers also
	    for (my $j=($i + 1); $j < @{$params{headers}}; $j++)
	    {
		my $hn = "header" . ($j + 1);
		$template->param($hn => $params{headers}[$j]);
	    }
	}
    }

    my $output = $template->output;

    return IkiWiki::preprocess($params{page}, $params{destpage},
			       IkiWiki::filter($params{page}, $params{destpage},
					       $output), $scan);

} # do_one_template

sub report_get_value ($$;%) {
    my $field = shift;
    my $page = shift;
    my %params = @_;

    my $use_page = $page;
    my $real_fn = $field;
    my $is_raw = 0;
    my $page_type = pagetype($pagesources{$page});

    if ($field =~ /^raw_(.*)/)
    {
	$real_fn = $1;
	$is_raw = 1;
    }
    elsif ($field =~ /^(first|last|header)$/i)
    {
	$is_raw = 1;
    }
    if ($real_fn =~ /^(prev|next)_page$/i)
    {
	$use_page = $params{$real_fn};
    }
    elsif ($real_fn =~ /^prev_(.*)/)
    {
	$real_fn = $1;
	$use_page = $params{prev_page};
    }
    elsif ($real_fn =~ /^next_(.*)/)
    {
	$real_fn = $1;
	$use_page = $params{next_page};
    }

    if (wantarray)
    {
	my @val_array = ();
	if (exists $params{$real_fn}
	    and defined $params{$real_fn})
	{
	    if (ref $params{$real_fn})
	    {
		@val_array = @{$params{$real_fn}};
	    }
	    else
	    {
		@val_array = ($params{$real_fn});
	    }
	}
	else
	{
	    @val_array = IkiWiki::Plugin::field::field_get_value($real_fn, $page);
	}
	if (!$is_raw && $page_type)
	{
	    # HTMLize the values
	    my @h_vals = ();
	    foreach my $v (@val_array)
	    {
		if (defined $v and $v)
		{
		    my $hv = IkiWiki::htmlize($params{page}, $params{destpage},
					      $page_type,
					      $v);
		    push @h_vals, $hv;
		}
	    }
	    @val_array = @h_vals;
	}
	return @val_array;
    }
    else # simple value
    {
	my $value = ((exists $params{$real_fn}
		      and defined $params{$real_fn})
		     ? (ref $params{$real_fn}
			? join(",", @{$params{$real_fn}})
			: $params{$real_fn}
		       )
		     : ($use_page
			? IkiWiki::Plugin::field::field_get_value($real_fn,
								  $use_page)
			: ''));
	if (defined $value and $value)
	{
	    $value = IkiWiki::htmlize($params{page}, $params{destpage},
				      $page_type,
				      $value) unless ($is_raw ||
						      !$page_type);
	}
	return $value;
    }
    return undef;
} # report_get_value

1;
