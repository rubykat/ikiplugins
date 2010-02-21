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

A PageSpec to determine the pages to report on.

=item sort

How the matching pages should be sorted.  Sorting criteria are separated by spaces.

The possible values for sorting are:

=over

=item page

Sort by the full page ID.

=item pagename

Sort by the base page name.

=item pagename_natural

Sort by the base page name, using Sort::Naturally if it is installed.

=item mtime

Sort by the page modification time.

=item age

Sort by the page creation time, newest first.

=back

Any other value is taken to be a field name to sort by.

If a sort value begins with a minus (-) then the order for that field is reversed.

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
    (<TMPL_VAR NAME="DATE">) [[<TMPL_VAR NAME="PAGE"]]
    <TMPL_VAR NAME="DESCRIPTION">
    
=head2 Advanced Options

The following options are used to improve efficiency when dealing
with large numbers of pages; most people probably won't need them.

=over

=item trail

A page or pages to use as a "trail" page.  When a trail page is used,
the matching pages are limited to (a subset of) the pages which that
page links to; the "pages" pagespec in this case, rather than selecting
pages from the entire wiki, will select pages from within the set of pages
given by the trail page.

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
    my $sort = $params{sort};
    delete $params{sort};

    my $template_page="templates/$params{template}";
    my $template_file=$pagesources{$template_page};
    my $template;
    if ($template_file)
    {
	add_depends($this_page, $template_page);
	eval {
	    $template=HTML::Template->new(
					  filter => sub {
					  my $text_ref = shift;
					  $$text_ref=&Encode::decode_utf8($$text_ref);
					  chomp $$text_ref;
					  },
					  filename => srcfile($template_file),
					  die_on_bad_params => 0,
					  no_includes => 1,
					  blind_cache => 1,
					 );
	};
	if ($@) {
	    error gettext("failed to process:")." $@"
	}
    }
    else
    {
	# get this from the default template directory outside the
	# ikiwiki tree
	my @params=IkiWiki::template_params($params{template}.".tmpl",
					    filter => sub {
					    my $text_ref = shift;
					    $$text_ref=&Encode::decode_utf8($$text_ref);
					    chomp $$text_ref;
					    },
					    die_on_bad_params => 0,
					    blind_cache => 1);
	if (! @params) {
	    error sprintf(gettext("nonexistant template %s"), $params{template});
	}
	$template=HTML::Template->new(@params);
    }
    delete $params{template};

    my $deptype=deptype($params{quick} ? 'presence' : 'content');

    my @matching_pages;
    # "trail" means "all the pages linked to from a given page"
    # which is a bit looser than the PmWiki definition
    # but it will do
    if ($params{trail})
    {
	my @trailpages = split(' ', $params{trail});
	foreach my $tp (@trailpages)
	{
	    add_depends($this_page, $tp, deptype("links"));
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
		$result=pagespec_match($mp, $pages);
		if ($result)
		{
		    push @filtered, $mp;
		    add_depends($this_page, $mp, $deptype);
		}
	    }
	    @matching_pages = @filtered;
	}
    }
    else
    {
	@matching_pages = pagespec_match_list($params{destpage}, $pages,
					      %params,
					      deptype => $deptype);
    }

    debug("report($this_page) found " . scalar @matching_pages . " pages");

    # sort the pages
    # multiple sort-fields are separated by spaces
    if ($sort)
    {
	my @sortfields = split(' ', $sort);
	# need to reverse the sortfields, going from the specific
	# to the general.
	@sortfields = reverse @sortfields;
	foreach my $sortfield (@sortfields)
	{
	    my $f;
	    my $reverse = 0;
	    if ($sortfield =~ /^-(.*)/)
	    {
		$sortfield = $1;
		$reverse = 1;
	    }
	    if ($sortfield eq 'page') {
		$f=sub { $a cmp $b };
	    }
	    elsif ($sortfield eq 'pagename') {
		$f=sub { IkiWiki::pagetitle(IkiWiki::basename($a)) cmp IkiWiki::pagetitle(IkiWiki::basename($b)) };
	    }
	    elsif ($sortfield eq 'pagename_natural') {
		eval q{use Sort::Naturally};
		if ($@) {
		    error(gettext("Sort::Naturally needed for title_natural sort"));
		}
		$f=sub {
		    Sort::Naturally::ncmp(IkiWiki::pagetitle(IkiWiki::basename($a)),
					  IkiWiki::pagetitle(IkiWiki::basename($b)))
		};
	    }
	    elsif ($sortfield eq 'mtime') {
		$f=sub { $IkiWiki::pagemtime{$b} <=> $IkiWiki::pagemtime{$a} };
	    }
	    elsif ($sortfield eq 'age') {
		$f=sub { $IkiWiki::pagectime{$b} <=> $IkiWiki::pagectime{$a} };
	    }
	    else # some other field
	    {
		$f=sub {
		    my $val_a = IkiWiki::Plugin::field::field_get_value($sortfield, $a);
		    $val_a = '' if !defined $val_a;
		    my $val_b = IkiWiki::Plugin::field::field_get_value($sortfield, $b);
		    $val_b = '' if !defined $val_b;
		    $val_a cmp $val_b;
		};
	    }
	    @matching_pages = sort { &$f } @matching_pages;
	    @matching_pages=reverse(@matching_pages) if $reverse;
	}
    }

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
	    debug("report scanning($this_page)");
	    debug("report NO MATCHING PAGES") if !@matching_pages;
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

    my $count = ($params{count}
		 ? ($params{count} < @matching_pages
		    ? $params{count}
		    : scalar @matching_pages
		   )
		 : scalar @matching_pages);
    my @header_fields = ($params{headers} ? split(' ', $params{headers}) : ());
    delete $params{headers};
    my @prev_headers = ();
    for (my $j=0; $j < @header_fields; $j++)
    {
	$prev_headers[$j] = '';
    }
    for (my $i=0; $i < $count; $i++)
    {
	my $page = $matching_pages[$i];
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

    $params{basename}=IkiWiki::basename($params{page});
    $params{included}=($params{page} ne $params{destpage});

    # The reason we check the template for field names is because we
    # don't know what fields the registered plugins provide; and this is
    # reasonable because for some plugins (e.g. a YAML data plugin) they
    # have no way of knowing, ahead of time, what fields they might be
    # able to provide.

    my $page_type = pagetype($pagesources{$params{page}});
    my @parameter_names = $template->param();
    foreach my $field (@parameter_names)
    {
	my $real_fn = $field;
	my $is_raw = 0;
	if ($field =~ /^raw_(.*)/)
	{
	    $real_fn = $1;
	    $is_raw = 1;
	}
	elsif ($field =~ /^(first|last|header)$/i)
	{
	    $is_raw = 1;
	}
	my $value = ((exists $params{$real_fn} and defined $params{$real_fn})
		     ? $params{$real_fn}
		     : IkiWiki::Plugin::field::field_get_value($real_fn,
							       $params{page}));
	if (defined $value)
	{
	    $value = IkiWiki::htmlize($params{page}, $params{destpage},
				      $page_type,
				      $value) unless ($is_raw ||
						      !$page_type);
	    $template->param($field => $value);
	}
	else
	{
	    $template->param($field => '');
	}
    }
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
1;
