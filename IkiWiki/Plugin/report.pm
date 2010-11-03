#!/usr/bin/perl
package IkiWiki::Plugin::report;
use strict;
=head1 NAME

IkiWiki::Plugin::report - Produce templated reports from page field data.

=head1 VERSION

This describes version B<1.20101101> of IkiWiki::Plugin::report

=cut

our $VERSION = '1.20101101';

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
use POSIX qw(ceil);

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
    my $dest_page = $params{destpage};
    my $pages = (defined $params{pages} ? $params{pages} : '*');
    $pages =~ s/{{\$page}}/$this_page/g;

    if (!defined $params{first_page_is_index})
    {
	$params{first_page_is_index} = 0;
    }

    my $template;
    eval {
	# Do this in an eval because it might fail
	# if the template isn't a page in the wiki
	$template=template_depends($params{template}, $params{page},
				   blind_cache => 1);
    };
    if (! $template) {
	# look for .tmpl template (in global templates dir)
	eval {
	    $template=template("$params{template}.tmpl",
				       blind_cache => 1);
	};
	if ($@) {
	    error gettext("failed to process template $params{template}.tmpl:")." $@";
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
    if ($params{pagenames})
    {
	@matching_pages =
	    map { bestlink($params{page}, $_) } split ' ', $params{pagenames};
	foreach my $mp (@matching_pages)
	{
	    if ($mp ne $dest_page)
	    {
		add_depends($dest_page, $mp, $deptype);
	    }
	}
    }
    elsif ($params{trail})
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

		    # Don't add the dependencies yet
		    # because the results could be further filtered below
		}
	    }
	    @matching_pages = @filtered;
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
    # the current page ($dest_page) and the previous page
    # and the next page only, we need to find the current page
    # in the list of matching pages, and set the matching
    # pages to those three pages.
    my @here_only = ();
    my $dest_page_ind;
    if ($params{here_only})
    {
	for (my $i=0; $i < @matching_pages; $i++)
	{
	    if ($matching_pages[$i] eq $dest_page)
	    {
		if ($i > 0)
		{
		    push @here_only, $matching_pages[$i-1];
		    push @here_only, $matching_pages[$i];
		    $dest_page_ind = 1;
		}
		else
		{
		    push @here_only, $matching_pages[$i];
		    $dest_page_ind = 0;
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

    # Only add dependencies when using trails IF we found matches
    if ($params{trail} and $#matching_pages > 0)
    {
	foreach my $tp (@trailpages)
	{
	    add_depends($dest_page, $tp, deptype("links"));
	}
	foreach my $mp (@matching_pages)
	{
	    add_depends($dest_page, $mp, $deptype);
	}
    }
    ##debug("report($dest_page) found " . scalar @matching_pages . " pages");

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
	    debug("report ($dest_page) NO MATCHING PAGES") if !@matching_pages;
	    foreach my $page (@matching_pages)
	    {
		add_link($dest_page, $page);
	    }
	}
	return;
    }

    # build up the report
    #
    my @report = ();

    my $start = ($params{here_only}
		 ? $dest_page_ind
		 : ($params{start} ? $params{start} : 0));
    my $stop = ($params{here_only}
		? $dest_page_ind + 1
		: ($params{count}
		   ? (($start + $params{count}) <= @matching_pages
		      ? $start + $params{count}
		      : scalar @matching_pages
		     )
		   : scalar @matching_pages)
	       );
    my $output = '';
    my $num_pages = 1;
    if ($params{per_page})
    {
	my $num_recs = scalar @matching_pages;
	$num_pages = ceil($num_recs / $params{per_page});
    }
    # Don't do pagination
    # - when there's only one page
    # - on included pages
    if (($num_pages <= 1)
	or ($params{page} ne $params{destpage}))
    {
	$output = build_report(%params,
			       start=>$start,
			       stop=>$stop,
			       matching_pages=>\@matching_pages,
			       template=>$template,
			       scanning=>$scanning,
			      );
    }
    else
    {
	$output = multi_page_report(%params,
				    num_pages=>$num_pages,
				    start=>$start,
				    stop=>$stop,
				    matching_pages=>\@matching_pages,
				    template=>$template,
				    scanning=>$scanning,
				   );
    }

    return $output;
} # preprocess

# -------------------------------------------------------------------
# Private Functions
# -------------------------------------

# Do a multi-page report.
# This assumes that this is not an inlined page.
sub multi_page_report (@) {
    my %params = (
		start=>0,
		@_
	       );

    my @matching_pages = @{$params{matching_pages}};
    my $template = $params{template};
    my $scanning = $params{scanning};
    my $num_pages = $params{num_pages};
    my $first_page_is_index = $params{first_page_is_index};

    my $page_type = pagetype($pagesources{$params{page}});

    my $first_page_out = '';
    for (my $pind = 0; $pind < $num_pages; $pind++)
    {
	my $rep_links = create_page_links(%params,
					  num_pages=>$num_pages,
					  cur_page=>$pind,
					  first_page_is_index=>$first_page_is_index);
	my $start_at = $params{start} + ($pind * $params{per_page});
	my $end_at = $params{start} + (($pind + 1) * $params{per_page});
	my $pout = build_report(%params,
			       start=>$start_at,
			       stop=>$end_at,
			       matching_pages=>\@matching_pages,
			       template=>$template,
			       scanning=>$scanning,
			      );
	$pout =<<EOT;
<div class="report">
$rep_links
$pout
$rep_links
</div>
EOT
	if ($pind == 0 and !$first_page_is_index)
	{
	    $first_page_out = $pout;
	}
	else
	{
	    my $new_page = sprintf("%s%s_%d", 'report', $params{report_id},
				   $pind + 1);
	    my $target = targetpage($params{page}, $config{htmlext}, $new_page);
	    will_render($params{page}, $target);
	    my $rep = IkiWiki::linkify($params{page}, $new_page, $pout);

	    # render as a simple page
	    $rep = render_simple_page(%params,
				      new_page=>$new_page,
				      content=>$rep);
	    writefile($target, $config{destdir}, $rep);
	}
    }
    if ($first_page_is_index)
    {
	$first_page_out = create_page_links(%params,
					    num_pages=>$num_pages,
					    cur_page=>-1,
					    first_page_is_index=>$first_page_is_index);
    }

    return $first_page_out;
} # multi_page_report

sub create_page_links {
    my %params = (
		num_pages=>0,
		cur_page=>0,
		@_
	       );
    my $first_page_is_index = $params{first_page_is_index};

    my @page_links = ();
    for (my $pind = ($first_page_is_index ? -1 : 0);
	 $pind < $params{num_pages}; $pind++)
    {
	if ($pind == $params{cur_page}
	    and $pind == -1)
	{
	    push @page_links,
		 sprintf('<b>[%s]</b>',
			 IkiWiki::pagetitle(IkiWiki::basename($params{page})));
	}
	elsif ($pind == $params{cur_page})
	{
	    push @page_links, sprintf('<b>[%d]</b>', $pind + 1);
	}
	elsif ($pind == -1)
	{
	    push @page_links,
		 sprintf('<a href="%s">[%s]</a>',
			 ($config{usedirs}
			  ? './'
			  : '../' . IkiWiki::basename($params{page})
			  . '.' . $config{htmlext}),
			 IkiWiki::pagetitle(IkiWiki::basename($params{page})));
	}
	elsif ($pind == 0 and !$first_page_is_index)
	{
	    push @page_links,
		 sprintf('<a href="%s">[%d]</a>',
			 ($config{usedirs}
			  ? './'
			  : '../' . IkiWiki::basename($params{page})
			  . '.' . $config{htmlext}),
			 $pind + 1);
	}
	else
	{
	    my $new_page = sprintf("%s%s_%d", 'report', $params{report_id},
				   $pind + 1);
	    push @page_links,
		 sprintf('<a href="%s.%s">[%d]</a>',
			 $new_page, $config{htmlext},
			 $pind + 1);
	}
    }
    return '<div class="rep_pages">' . join(' ', @page_links) . '</div>';
} # create_page_links

sub render_simple_page (@) {
    my %params=@_;

    my $new_page = $params{new_page};
    my $content = $params{content};

    # render as a simple page
    # cargo-culted from IkiWiki::Render::genpage
    my $ptmpl = IkiWiki::template('page.tmpl', blind_cache=>1);
    $ptmpl->param(
		  title => IkiWiki::pagetitle(IkiWiki::basename($new_page)),
		  wikiname => $config{wikiname},
		  content => $content,
		  html5 => $config{html5},
		 );

    IkiWiki::run_hooks(pagetemplate => sub {
		       shift->(page => $params{page},
			       destpage => $new_page,
			       template => $ptmpl);
		       });

    $content=$ptmpl->output;

    IkiWiki::run_hooks(format => sub {
		       $content=shift->(
				    page => $params{page},
				    content => $content,
				   );
		       });
    return $content;
} # render_simple_page

sub build_report (@) {
    my %params = (
		start=>0,
		@_
	       );

    my @matching_pages = @{$params{matching_pages}};
    my $template = $params{template};
    my $scanning = $params{scanning};
    my @report = ();

    my $start = $params{start};
    my $stop = $params{stop};
    my @header_fields = ($params{headers} ? split(' ', $params{headers}) : ());
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
	my $first = ($i == $start);
	my $last = ($i == ($stop - 1));
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
} # build_report

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
