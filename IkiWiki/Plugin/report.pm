#!/usr/bin/perl
package IkiWiki::Plugin::report;
use strict;
=head1 NAME

IkiWiki::Plugin::report - Produce templated reports from page field data.

=head1 VERSION

This describes version B<0.10> of IkiWiki::Plugin::report

=cut

our $VERSION = '0.10';

=head1 SYNOPSIS

    # activate the plugin
    add_plugins => [qw{goodstuff report ....}],

=head1 DESCRIPTION

This plugin provides the B<report> directive.  This enables one to report on
the structured data ("field" values) of multiple pages; the output is formatted
via a template.  This depends on the "field" plugin.

The pages to report on are selected by a PageSpec given by the "pages"
parameter.  The template is given by the "template" parameter.
The template expects the data from a single page; it is applied
to each matching page separately, one after the other.

Additional parameters can be used to fill out the template, in
addition to the "field" values.  Passed-in values override the
"field" values.

There are two places where template files can live.  One, as with the
B<template> plugin, is in the /templates directory on the wiki.  These
templates are wiki pages, and can be edited from the web like other wiki
pages.

The second place where template files can live is in the global
templates directory (the same place where the page.tmpl template lives).
This is a useful place to put template files if you want to prevent
them being edited from the web, and you don't want to have to make
them work as wiki pages.

=head1 OPTIONS

=over

=item template

The template to use for the report.

=item pages

A PageSpec to determine the pages to report on.  See also "trail".

=item trail

A page or pages to use as a "trail" page.  When a trail page is used,
the matching pages are limited to (a subset of) the pages which that
page links to; the "pages" pagespec in this case, rather than selecting
pages from the entire wiki, will select pages from within the set of pages
given by the trail page.

Additional space-separated trail pages can be given in this option.
For example:

    trail="animals/cats animals/dogs"

This will take the links from both the "animals/cats" page and the
"animals/dogs" page as the set of pages to apply the PageSpec to.

=item sort

A SortSpec to determine how the matching pages should be sorted.

=item here_only

Report on the current page only.  This is useful in combination with
"prev_" and "next_" variables to make a navigation trail.

If the current page doesn't match the pagespec, then no pages will
be reported on.

=back

=head2 Headers

An additional option is the "headers" option.  This is a space-separated
list of field names which are to be used as headers in the report.  This
is a way of getting around one of the limitations of HTML::Template, that
is, not being able to do tests such as
"if this-header is not equal to previous-header".

Instead, that logic is performed inside the plugin.  The template is
given parameters "HEADER1", "HEADER2" and so on, for each header.
If the value of a header field is the same as the previous value,
then HEADERB<N> is set to be empty, but if the value of the header
field is new, then HEADERB<N> is given that value.

=head3 Example

Suppose you're writing a blog in which you record "moods", and you
want to display your blog posts by mood.

    [[!report template="mood_summary"
    pages="blog/*"
    sort="Mood Date title"
    headers="Mood"]]

The "mood_summary" template might be like this:

    <TMPL_IF NAME="HEADER1">
    ## <TMPL_VAR NAME="HEADER1">
    </TMPL_IF>
    ### <TMPL_VAR NAME="TITLE">
    (<TMPL_VAR NAME="DATE">) [[<TMPL_VAR NAME="PAGE">]]
    <TMPL_VAR NAME="DESCRIPTION">
    
=head2 Advanced Options

The following options are used to improve efficiency when dealing
with large numbers of pages; most people probably won't need them.

=over

=item doscan

Whether this report should be called in "scan" mode; if it is, then
the pages which match the pagespec are added to the list of links from
this page.  This can be used by I<another> report by setting this
page to be a "trail" page in I<that> report.
It is not possible to use "trail" and "doscan" at the same time.
By default, "doscan" is false.

=back

=head1 TEMPLATE PARAMETERS

The templates are in HTML::Template format, just as B<template> and
B<ftemplate> are.  The parameters passed in to the template are as follows:

=over

=item fields

The structured data from the current matching page.  This includes
"title" and "description" if they are defined.

=item common values

Values known for all pages: "page", "destpage".
Also "basename" (the base name of the page).

=item passed-in values

Any additional parameters to the report directive are passed to the
template; a parameter will override the matching "field" value.
For example, if you have a "Mood" field, and you pass Mood="bad" to
the report, then that will be the Mood which is given for the whole
report.

Generally this is useful if one wishes to make a more generic
template and hide or show portions of it depending on what
values are passed in the report directive call.

For example, one could have a "hide_mood" parameter which would hide
the "Mood" section of your template when it is true, which one could
use when the Mood is one of the headers.

=item prev_ and next_ items

Any of the above variables can be prefixed with "prev_" or "next_"
and that will give the previous or next value of that variable; that is,
the value from the previous or next page that this report is reporting on.
This is mainly useful for a "here_only" report.

=item headers

See the section on Headers.

=item first and last

If this is the first page-record in the report, then "first" is true.
If this is the last page-record in the report, then "last" is true.

=back

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
