#!/usr/bin/perl
# One half of integration with taskwarrior tasks.
package IkiWiki::Plugin::task;
use warnings;
use strict;
=head1 NAME

IkiWiki::Plugin::task - integration with taskwarrior.

=head1 VERSION

This describes version B<0.01> of IkiWiki::Plugin::task

=cut

our $VERSION = '0.01';

=head1 PREREQUISITES

    IkiWiki
    IkiWiki::Plugin::field

=head1 AUTHOR

    Kathryn Andersen (RUBYKAT)
    http://github.com/rubykat

=head1 COPYRIGHT

Copyright (c) 2009 Kathryn Andersen

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
use IkiWiki 3.00;

sub task_vars ($$);

# ------------------------------------------------------------
# Import
# --------------------------------
sub import {
	hook(type => "getsetup", id => "task", call => \&getsetup);
	hook(type => "checkconfig", id => "task", call => \&checkconfig);
	hook(type => "preprocess", id => "task", call => \&preprocess, scan=>1);

	IkiWiki::loadplugin('field');
	IkiWiki::Plugin::field::field_register(id=>'task',
					       call=>\&task_vars,
					       first=>1);
}

# ------------------------------------------------------------
# Hooks
# --------------------------------
sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => 1,
		},
		task_tags => {
			type => "hash",
			example => "task_tags => {'action/tasks/*' => 'project:/action/projects:status:/action/status'}",
			description => "task info flagged as taggable",
			safe => 0,
			rebuild => undef,
		},
		task_use_tagbase => {
			type => "boolean",
			example => "task_use_tagbase => 1,",
			description => "make the 'tags' field us the global tagbase if there is one",
			safe => 0,
			rebuild => undef,
		},
}

sub checkconfig () {
    if (defined $config{task_tags}
	and !defined $config{task_tags_hash})
    {
	# PageSpec, task_field, sub-page
	# change this to a deeper hash
	my %taginfo = ();
	foreach my $pagespec (sort keys %{$config{task_tags}})
	{
	    my $tstr = $config{task_tags}->{$pagespec};
	    my @ti = split(':', $tstr);
	    my %ti = (@ti);
	    $taginfo{$pagespec} = \%ti;
	}
	$config{task_tags_hash} = \%taginfo;
    }

} # checkconfig

# use this for data in a [[!task ...]] directive
sub preprocess (@) {
    my %params=@_;
    my $page = $params{page};

    if (! exists $params{uuid}
	or ! defined $params{uuid}
	or !$params{uuid})
    {
	error gettext("missing uuid parameter")
    }
    # The fields are registered in scan mode.
    # When in preprocessing mode, display with template
    my $scan=! defined wantarray;
    my $ret = '';

    # save the data to pagestate
    # and add the links
    if ($scan)
    {
	my @task_fields = grep(!/^(:?page|destpage|preview)$/, sort keys %params);
	my @annotations = ();
	foreach my $fn (@task_fields)
	{
	    my $real_fn = "task_$fn";
	    my $fval = $params{$fn};
	    $pagestate{$page}{task}{$real_fn} = $fval;
	    if ($fn =~ /^(start|end|wait|due)$/i)
	    {
		my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
		    localtime($fval);
		$year += 1900;
		$mon++;
		$pagestate{$page}{task}{"${real_fn}date"} = "${year}-${mon}-${mday}";
	    }
	    elsif ($fn =~ /annotation_(\d+)/)
	    {
		my $secs = $1;
		my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) =
		    localtime($secs);
		$year += 1900;
		$mon++;
		push @annotations, "${year}-${mon}-${mday} $fval";
	    }
	}
	if (@annotations)
	{
	    $pagestate{$page}{task}{task_annotations} = \@annotations;
	}
	# special case for "tags" field, if we are using
	# the "tag" plugin
	if ($config{tagbase}
	    and $config{task_use_tagbase}
	    and $pagestate{$page}{task}{task_tags})
	{
	    my @tags = split(' ', $pagestate{$page}{task}{task_tags});
	    foreach my $tag (@tags)
	    {
		my $tagname = $tag;
		$tagname =~ s/_/ /g;
		my $link = $config{tagbase} . '/'
		    . titlepage($tagname);
		add_link($page, $link, 'tag');
		$pagestate{$page}{task}{"task_tags-link"} = $link;
	    }
	}

	# scan for task-tag fields
	if ($config{task_tags_hash})
	{
	    foreach my $pagespec (sort keys %{$config{task_tags_hash}})
	    {
		if (pagespec_match($page, $pagespec))
		{
		    my $taginfo = $config{task_tags_hash}{$pagespec};
		    foreach my $fn (sort keys %{$taginfo})
		    {
			my $real_fn = "task_$fn";
			my $tag = $pagestate{$page}{task}{$real_fn};
			if ($tag)
			{
			    my $tagname = $tag;
			    $tagname =~ s/_/ /g;
			    my $link = $taginfo->{$fn} . '/'
				. titlepage($tagname);
			    add_link($page, $link, $real_fn);
			    $pagestate{$page}{task}{"${real_fn}-link"} = $link;
			}
		    }
		}
	    }
	}
    }
    my $template = 'task.tmpl';
    if ($scan)
    {
	IkiWiki::Plugin::ftemplate::preprocess(%params,
					      %{$pagestate{$page}{task}},
					      id=>$template);
    }
    else
    {
	($ret) = IkiWiki::Plugin::ftemplate::preprocess(%params,
						       %{$pagestate{$page}{task}},
						       id=>$template);
    }
    return $ret;
} # preprocess

# ===============================================
# field functions
# ---------------------------
sub task_vars ($$) {
    my $field_name = shift;
    my $page = shift;

    my $value = undef;
    if ($field_name eq 'task_annotations') # this is an array
    {
	if (exists $pagestate{$page}{task}{$field_name})
	{
	    $value = $pagestate{$page}{task}{$field_name};
	    return (wantarray ? $value : join(", ", @{$value}));
	}
    }
    elsif ($field_name eq 'task_is_done')
    {
	if (exists $pagestate{$page}{task}{task_status}
	    and defined $pagestate{$page}{task}{task_status})
	{
	    if ($pagestate{$page}{task}{task_status} =~ /deleted|completed/)
	    {
		$value = 1;
	    }
	    else
	    {
		$value = 0;
	    }
	}
    }
    elsif ($field_name eq 'task_is_started')
    {
	if (exists $pagestate{$page}{task}{task_start}
	    and defined $pagestate{$page}{task}{task_start}
	    and $pagestate{$page}{task}{task_start})
	{
	    $value = 1;
	}
	else
	{
	    $value = 0;
	}
    }
    if ($field_name eq 'task_project')
    {
	if ($page =~ /projects\//)
	{
	    if ($page =~ /projects\/\w+-(\w+)/)
	    {
		$value = $1;
	    }
	    else
	    {
		$value = IkiWiki::basename($page);
	    }
	}
	elsif (exists $pagestate{$page}{task}{task_project}
	       and defined $pagestate{$page}{task}{task_project})
	{
	    $value = $pagestate{$page}{task}{task_project};
	}
    }
    elsif ($field_name eq 'task_full_project')
    {
	if ($page =~ /projects\//)
	{
	    $value = IkiWiki::basename($page);
	}
	elsif (exists $pagestate{$page}{task}{task_full_project}
	       and defined $pagestate{$page}{task}{task_full_project})
	{
	    $value = $pagestate{$page}{task}{task_full_project};
	}
    }
    elsif ($field_name eq 'task_proj_type')
    {
	if ($page =~ /projects\//)
	{
	    if ($page =~ /projects\/(\w+)-/)
	    {
		$value = $1;
	    }
	    else
	    {
		$value = IkiWiki::basename($page);
	    }
	}
	elsif (exists $pagestate{$page}{task}{task_proj_type}
	       and defined $pagestate{$page}{task}{task_proj_type})
	{
	    $value = $pagestate{$page}{task}{task_proj_type};
	}
    }
    elsif (exists $pagestate{$page}{task}{$field_name})
    {
	$value = $pagestate{$page}{task}{$field_name};
    }
    elsif (exists $pagestate{$page}{task}{lc($field_name)})
    {
	$value = $pagestate{$page}{task}{lc($field_name)};
    }
    if (defined $value)
    {
	return (wantarray ? ($value) : $value);
    }
    return undef;
} # task_vars

# ===============================================
# SortSpec functions
# ---------------------------
package IkiWiki::SortSpec;

sub cmp_task_priority {

    my $field = 'task_priority';

    my $left = IkiWiki::Plugin::field::field_get_value($field, $a);
    my $right = IkiWiki::Plugin::field::field_get_value($field, $b);

    my $left_pri = ($left eq 'H'
		    ? 1
		    : ($left eq 'M'
		       ? 2
		       : ($left eq 'L'
			  ? 3 : 4)));
    my $right_pri = ($right eq 'H'
		     ? 1
		     : ($right eq 'M'
			? 2
			: ($right eq 'L'
			   ? 3 : 4)));
    return $left_pri <=> $right_pri;
}

sub cmp_task_id {

    my $field = 'task_id';

    my $left = IkiWiki::Plugin::field::field_get_value($field, $a);
    my $right = IkiWiki::Plugin::field::field_get_value($field, $b);

    $left = 0 if !defined $left;
    $right = 0 if !defined $right;
    return $left <=> $right;
}
1;
