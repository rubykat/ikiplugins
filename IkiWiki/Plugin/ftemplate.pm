#!/usr/bin/perl
# Structured template plugin.
# This uses the "fields" plugin to look for values.
# See plugins/contrib/ftemplate and ikiwiki/directive/ftemplate for docs.
package IkiWiki::Plugin::ftemplate;
use strict;
=head1 NAME

IkiWiki::Plugin::ftemplate - field-aware structured template plugin

=head1 VERSION

This describes version B<0.02> of IkiWiki::Plugin::ftemplate

=cut

our $VERSION = '0.02';

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
	error gettext("failed to process template $params{id}:")." $@";
    }
    if (! $template) {
	# look for .tmpl template (in global templates dir)
	eval {
	    $template=template("$params{id}.tmpl",
				       blind_cache => 1);
	};
	if ($@) {
	    error gettext("failed to process template $params{id}.tmpl:")." $@";
	}
	if (! $template) {

	    error sprintf(gettext("%s not found"),
			  htmllink($params{page}, $params{destpage},
				   "/templates/$params{id}"))
	}
    }
    delete $params{template};

    $params{included}=($params{page} ne $params{destpage});

    # The reason we check the template for field names is because we
    # don't know what fields the registered plugins provide; and this is
    # reasonable because for some plugins (e.g. a YAML data plugin) they
    # have no way of knowing, ahead of time, what fields they might be
    # able to provide.

    IkiWiki::Plugin::field::field_set_template_values($template, $params{page},
	 value_fn => sub {
	    my $field = shift;
	    my $page = shift;
	    return ftemplate_get_value($field, $page, %params);
	 },);

    # This needs to run even in scan mode, in order to process
    # links and other metadata includes via the template.
    my $scan=! defined wantarray;

    my $output = $template->output;

    return IkiWiki::preprocess($params{page}, $params{destpage},
			       IkiWiki::filter($params{page}, $params{destpage},
					       $output), $scan);
}

sub ftemplate_get_value ($$;%) {
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
} # ftemplate_get_value

1;
