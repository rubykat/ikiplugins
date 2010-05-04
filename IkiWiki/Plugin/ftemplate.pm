#!/usr/bin/perl
# Structured template plugin.
# This uses the "fields" plugin to look for values.
package IkiWiki::Plugin::ftemplate;
use strict;
=head1 NAME

IkiWiki::Plugin::ftemplate - field-aware structured template plugin

=head1 VERSION

This describes version B<0.01> of IkiWiki::Plugin::ftemplate

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

    # activate the plugin
    add_plugins => [qw{goodstuff ftemplate ....}],

=head1 DESCRIPTION

This plugin provides the B<ftemplate> directive.  This is like
the B<template> directive, with the addition that one does not
have to provide all the values in the call to the template,
because ftemplate can query structured data ("fields") using
the B<field> plugin.

Templates are files that can be filled out and inserted into pages in
the wiki, by using the ftemplate directive. The directive has an id
parameter that identifies the template to use.

Additional parameters can be used to fill out the template, in
addition to the "field" values.  Passed-in values override the
"field" values.

There are two places where template files can live.  One is, as with the
B<template> plugin, in the /templates directory on the wiki.  These
templates are wiki pages, and can be edited from the web like other wiki
pages.

The second place where template files can live is in the global
templates directory (the same place where the page.tmpl template lives).
This is a useful place to put template files if you want to prevent
them being edited from the web, and you don't want to have to make
them work as wiki pages.

=head2 EXAMPLES

=head3 Example 1

PageA:

    [[!meta title="I Am Page A"]]
    [[!meta description="A is for Apple."]]
    [[!meta author="Fred Nurk"]]
    [[!ftemplate id="mytemplate"]]

Template "mytemplate":

    # <TMPL_VAR NAME="TITLE">
    by <TMPL_VAR NAME="AUTHOR">

    **Summary:** <TMPL_VAR NAME="DESCRIPTION">

This will give:

    <h1>I Am Page A</h1>
    <p>by Fred Nurk</p>
    <p><strong>Summary:</strong> A is for Apple.

=head3 Example 2: Overriding values

PageB:

    [[!meta title="I Am Page B"]]
    [[!meta description="B is for Banana."]]
    [[!meta author="Fred Nurk"]]
    [[!ftemplate id="mytemplate" title="Bananananananas"]]

This will give:

    <h1>Bananananananas</h1>
    <p>by Fred Nurk</p>
    <p><strong>Summary:</strong> B is for Banana.

=head2 LIMITATIONS

One cannot query the values of fields on pages other than the current
page.

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
	hook(type => "getsetup", id => "ftemplate", call => \&getsetup);
	hook(type => "preprocess", id => "ftemplate", call => \&preprocess,
	     scan => 1);

	IkiWiki::loadplugin("field");
}

sub getsetup () {
	return
		plugin => {
			safe => 1,
			rebuild => undef,
		},
}

sub preprocess (@) {
    my %params=@_;

    if (! exists $params{id}) {
	error gettext("missing id parameter")
    }

    my $template;
    eval {
	$template=template_depends($params{id}, $params{page},
				   blind_cache => 1);
    };
    if ($@) {
	error gettext("failed to process template:")." $@";
    }
    if (! $template) {
	# look for .tmpl template
	eval {
	    $template=template_depends("$params{id}.tmpl", $params{page},
				       blind_cache => 1);
	};
	if ($@) {
	    error gettext("failed to process template:")." $@";
	}
	if (! $template) {

	    error sprintf(gettext("%s not found"),
			  htmllink($params{page}, $params{destpage},
				   "/templates/$params{id}"))
	}
    }
    delete $params{template};

    $params{basename}=IkiWiki::basename($params{page});
    $params{included}=($params{page} ne $params{destpage});

    # The reason we check the template for field names is because we
    # don't know what fields the registered plugins provide; and this is
    # reasonable because for some plugins (e.g. a YAML data plugin) they
    # have no way of knowing, ahead of time, what fields they might be
    # able to provide.

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
	my $value = ((exists $params{$real_fn} and defined $params{$real_fn})
		     ? $params{$real_fn}
		     : IkiWiki::Plugin::field::field_get_value($real_fn,
							       $params{page}));
	if (defined $value)
	{
	    $value = IkiWiki::htmlize($params{page}, $params{destpage},
				      pagetype($pagesources{$params{page}}),
				      $value) unless $is_raw;
	    # tweak
	    $value =~ s/^\s*<p>// unless $is_raw;
	    $value =~ s/<\/p>\s*$// unless $is_raw;
	    $template->param($field => $value);
	}
    }

    # This needs to run even in scan mode, in order to process
    # links and other metadata includes via the template.
    my $scan=! defined wantarray;

    my $output = $template->output;

    return IkiWiki::preprocess($params{page}, $params{destpage},
			       IkiWiki::filter($params{page}, $params{destpage},
					       $output), $scan);
}

1;
