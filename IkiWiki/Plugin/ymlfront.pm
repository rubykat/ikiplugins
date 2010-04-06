#!/usr/bin/perl
# HTML as a wiki page type.
package IkiWiki::Plugin::ymlfront;
use warnings;
use strict;
=head1 NAME

IkiWiki::Plugin::ymlfront - add YAML-format data to a page

=head1 VERSION

This describes version B<0.01> of IkiWiki::Plugin::ymlfront

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

    # activate the plugin
    add_plugins => [qw{goodstuff ymlfront ....}],

=head1 DESCRIPTION

This plugin provides a way of adding arbitrary meta-data (data fields) to any
page by prefixing the page with a YAML-format document.  This provides a way to
create per-page structured data, where each page is treated like a record, and
the structured data are fields in that record.  This can include the meta-data
for that page, such as the page title.

This plugin is meant to be used in conjunction with the B<field> plugin.

=head1 DETAILS

The YAML-format data in a page must be placed at the start of the page
and delimited by lines containing precisely three dashes.  The "normal"
content of the page then follows.

For example:

    ---
    title: Foo does not work
    Urgency: High
    Status: Assigned
    AssignedTo: Fred Nurk
    Version: 1.2.3
    ---
    When running on the Sprongle system, the Foo function returns incorrect data.

What will normally be displayed is everything following the second line of dashes.
That will be htmlized using the page-type of the page-file.

=head2 Accessing the Data

There are three ways to access the data given in the YAML section.

=over

=item getfield plugin

The B<getfield> plugin can display the data as individual variable values.

For example:

    ---
    title: Foo does not work
    Urgency: High
    Status: Assigned
    AssignedTo: Fred Nurk
    Version: 1.2.3
    ---
    # {{$title}}

    **Urgency:** {{$Urgency}}\\
    **Status:** {{$Status}}\\
    **Assigned To:** {{$AssignedTo}}\\
    **Version:** {{$Version}}

    When running on the Sprongle system, the Foo function returns incorrect data.

=item ftemplate plugin

The B<ftemplate> plugin is like the B<template> plugin, but it is also aware of B<field>
values.

For example:

    ---
    title: Foo does not work
    Urgency: High
    Status: Assigned
    AssignedTo: Fred Nurk
    Version: 1.2.3
    ---
    [[!ftemplate id="bug_display_template"]]

    When running on the Sprongle system, the Foo function returns incorrect data.

=item write your own plugin

In conjunction with the B<field> plugin, you can write your own plugin to access the data.

=back

=head1 PREREQUISITES

    IkiWiki
    IkiWiki::Plugin::field
    YAML::Any

=head1 AUTHOR

    Kathryn Andersen (RUBYKAT)
    http://github.com/rubykat

=head1 COPYRIGHT

Copyright (c) 2009 Kathryn Andersen

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
use IkiWiki 3.00;
use YAML::Any;

$YAML::UseBlock = 1;

sub import {
	hook(type => "getsetup", id => "ymlfront", call => \&getsetup);
	hook(type => "checkconfig", id => "ymlfront", call => \&checkconfig);
	hook(type => "filter", id => "ymlfront", call => \&filter, first=>1);
	hook(type => "scan", id => "ymlfront", call => \&scan);
	hook(type => "checkcontent", id => "ymlfront", call => \&checkcontent);

	IkiWiki::loadplugin('field');
	IkiWiki::Plugin::field::field_register(id=>'ymlfront', first=>1);
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
}

sub checkconfig () {
	eval q{use YAML::Any};
	if ($@)
	{
	    return error ("ymlfront: failed to use YAML::Any");
	}

} # checkconfig

# scan gets called before filter
sub scan (@) {
    my %params=@_;
    my $page = $params{page};

    my $page_file=$pagesources{$page} || return;
    my $page_type=pagetype($page_file);
    if (!defined $page_type)
    {
	return;
    }
    # clear the old data
    if (exists $pagestate{$page}{ymlfront})
    {
	delete $pagestate{$page}{ymlfront};
    }
    my $parsed_yml = parse_yml(%params);
    if (defined $parsed_yml
	and defined $parsed_yml->{yml})
    {
	# save the data to pagestate
	foreach my $fn (keys %{$parsed_yml->{yml}})
	{
	    my $fval = $parsed_yml->{yml}->{$fn};
	    $pagestate{$page}{ymlfront}{$fn} = $fval;
	}
    }
    if (exists $pagestate{$page}{ymlfront}{title}
	and $pagestate{$page}{ymlfront}{title})
    {
	$pagestate{$page}{meta}{title} = $pagestate{$page}{ymlfront}{title};
    }
    if (exists $pagestate{$page}{ymlfront}{description}
	and $pagestate{$page}{ymlfront}{description})
    {
	$pagestate{$page}{meta}{description} = $pagestate{$page}{ymlfront}{description};
    }
    if (exists $pagestate{$page}{ymlfront}{author}
	and $pagestate{$page}{ymlfront}{author})
    {
	$pagestate{$page}{meta}{author} = $pagestate{$page}{ymlfront}{author};
    }
} # scan

sub filter (@) {
    my %params=@_;
    my $page = $params{page};

    my $page_file=$pagesources{$page} || return $params{content};
    my $page_type=pagetype($page_file);
    if (!defined $page_type)
    {
	return $params{content};
    }
    my $parsed_yml = parse_yml(%params);
    if (defined $parsed_yml
	and defined $parsed_yml->{yml}
	and defined $parsed_yml->{content})
    {
	$params{content} = $parsed_yml->{content};
	# also check for a content value
	if (exists $pagestate{$page}{ymlfront}{content}
	    and defined $pagestate{$page}{ymlfront}{content}
	    and $pagestate{$page}{ymlfront}{content})
	{
	    $params{content} .= $pagestate{$page}{ymlfront}{content};
	}
    }

    return $params{content};
} # filter

# check the correctness of the YAML code before saving a page
sub checkcontent {
    my %params=@_;
    my $page = $params{page};

    my $page_file=$pagesources{$page};
    if ($page_file)
    {
	my $page_type=pagetype($page_file);
	if (!defined $page_type)
	{
	    return undef;
	}
    }
    my $parsed_yml = parse_yml(%params);
    if (!defined $parsed_yml)
    {
	debug("ymlfront: Save of $page failed: $@");
	return gettext("YAML data incorrect: $@");
    }
    return undef;
} # checkcontent

# ------------------------------------------------------------
# Helper functions
# --------------------------------

# parse the YAML data from the given content
# Expects page, content
# Returns { yml=>%yml_data, content=>$content } or undef
sub parse_yml {
    my %params=@_;
    my $page = $params{page};
    my $content = $params{content};

    my $page_file=$pagesources{$page};
    if ($page_file)
    {
	my $page_type=pagetype($page_file);
	if (!defined $page_type)
	{
	    return undef;
	}
    }
    if ($content =~ /^---[\n\r](.*?)[\n\r]---[\n\r](.*)$/s)
    {
	my $yml_str = $1;
	my $rest_of_content = $2;
	# if {{$page}} is there, do an immediate substitution
	$yml_str =~ s/\{\{\$page\}\}/$page/sg;

	my $ydata;
	eval q{$ydata = Load($yml_str);};
	if ($@)
	{
	    debug("ymlfront: Load of $page failed: $@");
	    return undef;
	}
	if (!$ydata)
	{
	    debug("ymlfront: no YAML for $page");
	    return undef;
	}
	my %lc_data = ();
	if ($ydata)
	{
	    # make lower-cased versions of the data
	    foreach my $fn (keys %{$ydata})
	    {
		my $fval = $ydata->{$fn};
		$lc_data{lc($fn)} = $fval;
	    }
	}
	return { yml=>\%lc_data, content=>$rest_of_content };
    }
    return { yml=>undef, content=>$content };
} # parse_yml
1;
