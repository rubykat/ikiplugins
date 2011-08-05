#!/usr/bin/perl
package IkiWiki::Plugin::anypar;
use warnings;
use strict;
=head1 NAME

IkiWiki::Plugin::anypar - any pagetemplate parameter

=head1 VERSION

This describes version B<0.20110617> of IkiWiki::Plugin::anypar

=cut

our $VERSION = '1.20110617';

=head1 DESCRIPTION

Allows you to define any parameter of the pagetemplate (page.tmpl)
using a template file; moreover, it allows you to use different
template files for different sets of pages, as defined by a pagespec.

See doc/plugin/contrib/anypar.mdwn for documentation.

=head1 PREREQUISITES

    IkiWiki

=head1 AUTHOR

    Kathryn Andersen (RUBYKAT)
    http://github.com/rubykat

=head1 COPYRIGHT

Copyright (c) 2011 Kathryn Andersen

This program is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
use IkiWiki 3.00;
use HTML::Template;
use Encode;

sub import {
	hook(type => "getsetup", id => "anypar",  call => \&getsetup);
	hook(type => "checkconfig", id => "anypar", call => \&checkconfig);
	hook(type => "pagetemplate", id => "anypar", call => \&pagetemplate);
	IkiWiki::loadplugin("field");
}

# ------------------------------------------------------------
# Hooks
# ----------------------------
sub getsetup () {
    return
    plugin => {
	safe => 1,
	rebuild => undef,
    },
    anypar_pars => {
	type => "hash",
	example => "anypar_pars => {'nav_side1.tmpl' => 'nav_side'}",
	description => "which pagetemplate parameters are created by which templates",
	safe => 0,
	rebuild => 0,
    },
    anypar_pages => {
	type => "hash",
	example => "anypar_pages => {'nav_side1.tmpl' => '* and !*.* and !*/*/*'}",
	description => "pagespec showing which templates to apply to which pages",
	safe => 0,
	rebuild => 0,
    },
} # getsetup

sub checkconfig () {
    foreach my $required (qw(anypar_pars anypar_pages)) {
	if (! length $config{$required}) {
	    error(sprintf(gettext("Must specify %s when using the %s plugin"), $required, 'anypar'));
	}
    }
} # checkconfig

sub pagetemplate (@) {
    my %params=@_;
    my $page=$params{page};
    my $template=$params{template};

    my $page_file = $pagesources{$params{page}} || return;
    my $page_type=pagetype($page_file);
    if ($page_type)
    {
	while (my ($tmpl, $ps) = each %{$config{anypar_pages}})
	{
	    if (pagespec_match($page, $ps))
	    {
		render_par(%params,
		    page_type=>$page_type,
		    par_template=>$tmpl);
	    }
	}
    }

} # pagetemplate

# ------------------------------------------------------------
# Private Functions
# ----------------------------
sub render_par (@) {
    my %params = @_;
    my $page = $params{page};
    my $destpage = $params{destpage};
    my $page_template = $params{template};
    my $par_template_name = $params{par_template};

    my $parname = $config{anypar_pars}{$par_template_name};
    if (!$parname)
    {
	error sprintf("%s: template %s has no matching parameter",
	    'anypar', $par_template_name);
    }

    my $par_tmpl = IkiWiki::Plugin::field::field_get_template(%params,
	template=>$par_template_name);
    IkiWiki::Plugin::field::field_set_template_values($par_tmpl, $page);
    my $content = $par_tmpl->output;

    return unless $content;

    $content = IkiWiki::htmlize($page, $destpage,
	$params{page_type},
	IkiWiki::linkify($page, $destpage,
	    IkiWiki::preprocess($page, $destpage,
		IkiWiki::filter($page, $destpage, $content))));

    # now set the matching pagetemplate parameter
    $page_template->param($parname => $content);

} # render_par

1;
